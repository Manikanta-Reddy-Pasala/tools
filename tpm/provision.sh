#!/usr/bin/env bash
# provision.sh - first-time TPM + LUKS setup for a NEW NUC (Ubuntu 22.04, Intel PTT).
#   sudo ./provision.sh                 # asks for the LUKS passphrase
#   sudo ./provision.sh --status        # read-only, changes nothing
#   read -rs LUKS_PASS && export LUKS_PASS && sudo --preserve-env=LUKS_PASS ./provision.sh
#     ^ the non-interactive form. Never put the passphrase in argv: sudo logs it and ps shows it.
# Order matters: read-only checks first (a wrong crypttab makes everything below useless, and
# the apt install below triggers update-initramfs on its own), then DA params - the TPM accepts
# those only while lockoutAuth is empty - then clevis sealed to PCR 7, proof it unseals, drop
# unpinned slots, verify every initrd.
# Silent on success; anything printed is an error or a warning. Re-running is safe.
# Exit: 0 all checks passed - 1 failed, do not reboot - 2 done, but read the warnings
#       3 bound and unsealed, but no initrd could be verified (NO_INITRAMFS=1 is your own choice: 0)
# Env: MAXTRIES RECOVERY_TIME LOCKOUT_RECOVERY_TIME PCR_IDS PCR_BANK DEV CRYPTTAB
#      SKIP_APT NO_INITRAMFS LUKS_PASS
set -uo pipefail

MAXTRIES="${MAXTRIES:-32}"
RECOVERY_TIME="${RECOVERY_TIME:-60}"
LOCKOUT_RECOVERY_TIME="${LOCKOUT_RECOVERY_TIME:-60}"
PCR_IDS="${PCR_IDS:-7}"
PCR_BANK="${PCR_BANK:-sha256}"
DEV="${DEV:-}"
CT="${CRYPTTAB:-/etc/crypttab}"

die()  { printf 'provision: %s\n' "$*" >&2; exit 1; }
rp()   { readlink -f "${1:-}" 2>/dev/null; }   # never compare two EMPTY results: that matches anything
WARNED=0
warn() { WARNED=1; printf 'provision: %s\n' "$*" >&2; }
# num/da die in a SUBSHELL, so every caller must take the value by assignment and check it
num()  { local v; v="$(sed -n "s/^[[:space:]]*$1:[[:space:]]*\([^[:space:]]*\).*/\1/p" <<<"$VC" | head -n1)"
         [[ "$v" =~ ^(0x)?[0-9a-fA-F]+$ ]] || die "cannot read $1 from tpm2_getcap"
         [[ "$v" == 0x* ]] && printf '%d' "$v" || printf '%s' "$v"; }
da()   { local a b c; a="$(num TPM2_PT_MAX_AUTH_FAIL)" && b="$(num TPM2_PT_LOCKOUT_INTERVAL)" \
         && c="$(num TPM2_PT_LOCKOUT_RECOVERY)" || return 1; printf '%s/%s/%s' "$a" "$b" "$c"; }
slots() { clevis luks list -d "$DEV" 2>/dev/null | sed -n "s/^\([0-9]\{1,\}\):[[:space:]]*\([a-z0-9]\{1,\}\)[[:space:]]*'\(.*\)'[[:space:]]*\$/\1 \2 \3/p"; }
pinned()   { slots | while read -r s pin cfg; do [[ "$pin" == tpm2 && "$cfg" == *"\"pcr_ids\":\"$PCR_IDS\""* ]] && printf '%s\n' "$s"; done; }
unpinned() { slots | while read -r s pin cfg; do [[ "$pin" == tpm2 && "$cfg" != *pcr_ids* ]] && printf '%s\n' "$s"; done; }
unseals()  { clevis luks pass -d "$DEV" -s "$1" >/dev/null 2>&1; }
# a typed passphrase has no trailing newline, a keyfile-set one may; --key-file=- is byte-exact
testpass() { cryptsetup open --test-passphrase "$DEV" --key-file=- >/dev/null 2>&1; }
# -k - is the guarded stdin path; without it clevis dies on a pipe with no trailing newline
dobind()   { clevis luks bind -y -k - -d "$DEV" tpm2 "{\"pcr_bank\":\"$PCR_BANK\",\"pcr_ids\":\"$PCR_IDS\"}" >/dev/null 2>>"$ERR"; }
# not "A | B || C | D": a callee that exits without draining stdin gives printf SIGPIPE, and
# under pipefail that would run the second attempt - a second bind, a duplicate keyslot
try2()     { local rc; printf '%s' "$2" | "$1"; rc=${PIPESTATUS[1]}      # [1]: printf can take SIGPIPE,
             (( rc == 0 )) || { printf '%s\n' "$2" | "$1"; rc=${PIPESTATUS[1]}; }; return "$rc"; }
first_unsealing() { local s; for s in $(pinned); do unseals "$s" && { printf '%s' "$s"; return 0; }; done; return 1; }
# crypttab entry for $DEV -> NAME, OPTS, KS (KS = a NON-stock keyscript, the one that bricks boot)
ct_scan() {
  local n src o x u parts dev
  NAME="" OPTS="" KS="" KS_ANY=""
  u="$(blkid -s UUID -o value "$DEV" 2>/dev/null)"
  dev="$(rp "$DEV")"
  while read -r n src _ o _ || [[ -n "${n:-}" ]]; do   # || ... : a last line with no newline still counts
    [[ ( -n "$u" && "$src" == "UUID=$u" ) || ( -n "$dev" && "$(rp "${src:-}")" == "$dev" ) ]] || continue
    NAME="$n" OPTS="${o:-}"; break
  done < <(grep -vE '^[[:space:]]*(#|$)' "$CT" 2>/dev/null)
  IFS=, read -ra parts <<<"$OPTS"
  for x in ${parts[@]+"${parts[@]}"}; do
    [[ "$x" == keyscript=* ]] || continue
    x="${x#keyscript=}"; KS_ANY="$x"
    [[ "$x" != */* || "$x" == /lib/cryptsetup/scripts/* || "$x" == /usr/lib/cryptsetup/scripts/* ]] || KS="$x"
  done
}
# dm name $DEV is currently open under, if any
live_name() {
  local n d dev
  dev="$(rp "$DEV")"; [[ -n "$dev" ]] || return 0
  for n in $(dmsetup ls --target crypt 2>/dev/null | awk '$1 != "No" { print $1 }'); do
    d="$(cryptsetup status "$n" 2>/dev/null | sed -n 's/^[[:space:]]*device:[[:space:]]*//p' | head -n1)"
    [[ -n "$d" && "$(rp "$d")" == "$dev" ]] && { printf '%s' "$n"; return 0; }
  done
}

PASS="${LUKS_PASS-}"; unset LUKS_PASS   # unset drops the export: no child process inherits it
ERR="$(mktemp)" || die "mktemp failed"
trap 'rm -rf "$ERR" "${TMP:-}"' EXIT                      # an INT handler must exit: bash resumes otherwise
trap 'rm -rf "$ERR" "${TMP:-}"; exit 130' INT TERM
for v in MAXTRIES RECOVERY_TIME LOCKOUT_RECOVERY_TIME; do [[ "${!v}" =~ ^[0-9]+$ ]] || die "$v must be a plain number, got '${!v}'"; done
STATUS=0
[[ $# -le 1 ]] || die "too many arguments"
case "${1:-}" in
  --status) STATUS=1 ;;
  -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
  "") ;;
  *) die "unknown argument '$1' (use --status or --help)" ;;
esac
[[ $(id -u) -eq 0 ]] || die "run as root"

# ---- read-only discovery. Before apt, because installing clevis-initramfs rebuilds the initrd.
if [[ -z "$DEV" ]]; then
  DEV="$(blkid -t TYPE=crypto_LUKS -o device 2>/dev/null)"
  [[ -n "$DEV" ]] || die "no LUKS partition found"
  [[ "$(wc -l <<<"$DEV")" -eq 1 ]] || die "more than one LUKS partition - re-run with DEV=/dev/..."
fi
ct_scan; LIVE="$(live_name)"
command -v dmsetup >/dev/null || warn "WARNING: dmsetup missing - cannot check the live mapping name"
[[ -n "$KS" ]] && warn "WARNING: $CT unlocks '$NAME' through $KS, not clevis. If that key ever fails there is NO passphrase prompt - boot stops at (initramfs). Fix it with ./tpmfix.sh"

if (( STATUS == 1 )); then   # report and exit; never abort, the box may not be provisioned yet
  printf 'device=%s crypttab=%s opts=%s open_as=%s\n' "$DEV" "${NAME:-<none>}" "${OPTS:-<none>}" "${LIVE:-<not open>}"
  [[ -z "$LIVE" || -z "$NAME" || "$LIVE" == "$NAME" ]] \
    || printf 'MISMATCH open as %s but %s says %s - fix with: dmsetup rename %s %s\n' "$LIVE" "$CT" "$NAME" "$LIVE" "$NAME"
  if command -v tpm2_getcap >/dev/null && [[ -c /dev/tpmrm0 ]]; then
    export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
    if VC="$(tpm2_getcap properties-variable 2>/dev/null)" \
       && lock="$(num lockoutAuthSet)" && inl="$(num inLockout)" && have="$(da)"; then
      printf 'lockoutAuthSet=%s inLockout=%s DA=%s\n' "$lock" "$inl" "$have"
    else
      warn "WARNING: could not read the TPM state"      # report the rest anyway: --status never aborts
    fi
  else
    warn "WARNING: no tpm2-tools or no /dev/tpmrm0 (enable Intel PTT in the BIOS) - TPM state not read"
  fi
  command -v clevis >/dev/null && slots | while read -r s pin cfg; do
    [[ "$pin" == tpm2 && "$cfg" != *pcr_ids* ]] && cfg="$cfg  <-- no pcr_ids: unseals in any boot state"
    printf 'slot %s %s %s\n' "$s" "$pin" "$cfg"
  done
  exit 0
fi
[[ -z "$LIVE" || -z "$NAME" || "$LIVE" == "$NAME" ]] || die "$DEV is open as '$LIVE' but $CT says '$NAME'; any initrd built now would have no unlock entry. Fix first: dmsetup rename $LIVE $NAME"

# ---- tools
if [[ "${SKIP_APT:-0}" != 1 && "$STATUS" != 1 ]] && { ! command -v tpm2_getcap >/dev/null \
   || ! command -v clevis-luks-bind >/dev/null || [[ ! -e /usr/share/initramfs-tools/hooks/clevis ]]; }; then
  DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tpm2-tools clevis clevis-luks clevis-tpm2 \
    clevis-initramfs >/dev/null 2>&1 || die "apt-get install failed"
fi
command -v tpm2_getcap >/dev/null || die "tpm2-tools missing"
command -v clevis >/dev/null || die "clevis missing"
[[ -c /dev/tpmrm0 ]] || die "no /dev/tpmrm0 - enable Intel PTT in the BIOS"
export TPM2TOOLS_TCTI="device:/dev/tpmrm0"   # jammy clevis globs /dev/tpmrm? regardless; match it
VC="$(tpm2_getcap properties-variable 2>/dev/null)" || die "tpm2_getcap failed"

# ---- 1. dictionary-attack parameters
inl="$(num inLockout)" && lock="$(num lockoutAuthSet)" && have="$(da)" || exit 1
[[ "$inl" == 1 ]] && die "TPM is in lockout - power off, unplug 15s, boot, re-run"
want="$MAXTRIES/$RECOVERY_TIME/$LOCKOUT_RECOVERY_TIME"
if [[ "$lock" == 0 ]]; then
  tpm2_dictionarylockout --setup-parameters --max-tries="$MAXTRIES" --recovery-time="$RECOVERY_TIME" \
    --lockout-recovery-time="$LOCKOUT_RECOVERY_TIME" >/dev/null || die "tpm2_dictionarylockout refused"
  VC="$(tpm2_getcap properties-variable 2>/dev/null)" || die "tpm2_getcap failed"
  have="$(da)" || exit 1
  [[ "$have" == "$want" ]] || die "TPM reports $have after setting $want"
elif [[ "$have" != "$want" ]]; then
  die "lockoutAuth is already set (Windows does this) so the TPM keeps DA params at $have, wanted $want - run ./tpmfix.sh first"
fi

# ---- 2. clevis sealed to PCR $PCR_IDS, proven to unseal before anything else changes
GOOD="$(first_unsealing)"
if [[ -z "$GOOD" ]]; then
  if [[ -z "$PASS" ]]; then
    printf 'LUKS passphrase for %s: ' "$DEV" >&2                 # /dev/tty: never eat piped stdin
    if [[ -r /dev/tty ]]; then read -r -s PASS < /dev/tty; else read -r -s PASS; fi; printf '\n' >&2
  fi
  [[ -n "$PASS" ]] || die "empty passphrase"
  try2 testpass "$PASS" || { unset PASS; die "that passphrase does not open $DEV"; }
  try2 dobind "$PASS" || { unset PASS; warn "$(tail -n3 "$ERR")"; die "clevis luks bind failed"; }
  unset PASS
  GOOD="$(first_unsealing)"
  [[ -n "$GOOD" ]] || die "bound, but the TPM does not release the key - do not rely on it"
fi

for s in $(pinned); do
  [[ "$s" == "$GOOD" ]] || unseals "$s" \
    || warn "WARNING: slot $s is sealed to PCR $PCR_IDS but no longer unseals (stale after a BIOS or Secure Boot change) - remove it with: clevis luks unbind -d $DEV -s $s"
done
enabled="$(cryptsetup luksDump "$DEV" 2>/dev/null | grep -cE '^[[:space:]]+[0-9]+: (luks2|reencrypt)|^Key Slot [0-9]+: ENABLED')"
[[ "$enabled" == 0 || "$enabled" -gt "$(slots | wc -l)" ]] \
  || warn "WARNING: every keyslot on $DEV is a clevis binding - after a BIOS or Secure Boot change there is no passphrase to fall back on. Add one: cryptsetup luksAddKey $DEV"

# ---- 3. bindings that unseal in any boot state - only now, with slot $GOOD proven.
# A failure here must not skip step 4: an unverified /boot is the worse problem.
for s in $(unpinned); do
  clevis luks unbind -d "$DEV" -s "$s" -f >/dev/null 2>&1 \
    || warn "WARNING: could not remove slot $s - a tpm2 binding with no pcr_ids, it unseals in ANY boot state"
done

# ---- 4. initramfs. update-initramfs exiting 0 proves nothing, so unpack what it built and look.
# Exit 3 = bound and unsealed, but nothing could be verified. Only exit 0 means fully checked.
[[ "${NO_INITRAMFS:-0}" == 1 ]] && { (( WARNED )) && exit 2; exit 0; }
update-initramfs -u -k all >/dev/null || die "update-initramfs failed - do NOT reboot"
[[ -n "$NAME" ]] || { warn "WARNING: no $CT entry for $DEV - no initrd was verified"; exit 3; }
command -v unmkinitramfs >/dev/null || { warn "WARNING: unmkinitramfs missing - no initrd was verified"; exit 3; }
bad=0 seen=0
for k in /boot/vmlinuz-*; do          # installed kernels only: initrd.img-* also matches .old-dkms
  [[ -f "$k" ]] || continue
  IMG="/boot/initrd.img-${k#/boot/vmlinuz-}"
  [[ -f "$IMG" ]] || { warn "WARNING: $k has no $IMG"; bad=$((bad + 1)); continue; }
  TMP="$(mktemp -d)" || die "mktemp failed"
  if ! unmkinitramfs "$IMG" "$TMP" >/dev/null 2>&1; then
    rm -rf "$TMP"; TMP=""; warn "WARNING: $IMG will not unpack (truncated image, or TMPDIR too small)"
    bad=$((bad + 1)); continue
  fi
  line="$(find "$TMP" -path '*/cryptroot/crypttab' -type f -exec awk -v n="$NAME" '$1 == n' {} + | head -n1)"
  hook="$(find "$TMP" -path '*/scripts/local-top/clevis' | head -n1)"
  rm -rf "$TMP"; TMP=""
  if [[ -z "$line" ]]; then
    warn "WARNING: $IMG has no '$NAME' unlock entry"; bad=$((bad + 1)); continue
  elif [[ -z "$KS_ANY" && "$line" == *keyscript=* ]]; then   # $CT has none, the initrd invented one
    warn "WARNING: $IMG unlocks '$NAME' through a keyscript that $CT does not have"; bad=$((bad + 1)); continue
  fi
  [[ -n "$hook" ]] || warn "WARNING: no clevis hook in $IMG - that kernel will ask for the passphrase"
  seen=$((seen + 1))
done
(( bad )) && die "$bad of $((bad + seen)) initrd images would not unlock '$NAME' - do NOT reboot"
(( seen )) || { warn "WARNING: no installed kernel found under /boot - nothing was verified"; exit 3; }
(( WARNED )) && exit 2
exit 0
