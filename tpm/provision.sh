#!/usr/bin/env bash
# provision.sh - first-time TPM + LUKS setup for a NEW NUC (Ubuntu 22.04, Intel PTT).
#
# Run once, as root, before anything else is sealed to the TPM:
#   sudo ./provision.sh                    # asks for the LUKS passphrase
#   sudo LUKS_PASS='...' ./provision.sh    # non-interactive (keep it out of shell history)
#   sudo ./provision.sh --status           # read-only, changes nothing
#
# In this order - the order matters:
#   1. dictionary-attack parameters (maxTries/recovery/lockoutRecovery). The TPM only
#      accepts them while lockoutAuth is EMPTY; once Windows (or anyone) sets it, the
#      only way back is a TPM clear. So they are set before anything else.
#   2. clevis bound to the LUKS volume, sealed to PCR 7 (Secure Boot state).
#   3. proof that the TPM releases the key, before a reboot depends on it.
#   4. initramfs rebuilt, and the new initrd checked for an unlock entry.
# Re-running is safe: every step checks before it acts.
#
# Settings (environment): MAXTRIES=32 RECOVERY_TIME=60 LOCKOUT_RECOVERY_TIME=60 PCR_IDS=7
#   DEV=/dev/...  (default: the only crypto_LUKS partition)
set -uo pipefail

MAXTRIES="${MAXTRIES:-32}"                           # auth failures before lockout
RECOVERY_TIME="${RECOVERY_TIME:-60}"                 # seconds until one failure is forgiven
LOCKOUT_RECOVERY_TIME="${LOCKOUT_RECOVERY_TIME:-60}" # seconds before lockoutAuth may be retried
PCR_IDS="${PCR_IDS:-7}"
PCR_BANK="${PCR_BANK:-sha256}"
DEV="${DEV:-}"
CT="${CRYPTTAB:-/etc/crypttab}"
SKIP_APT="${SKIP_APT:-0}"
NO_INITRAMFS="${NO_INITRAMFS:-0}"

r()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
g()   { printf '\033[32m%s\033[0m\n' "$*"; }
y()   { printf '\033[33m%s\033[0m\n' "$*" >&2; }
b()   { printf '\033[1m\n== %s ==\033[0m\n' "$*"; }
die() { r "FAILED: $*"; exit 1; }

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0; }
STATUS_ONLY=0
[[ "${1:-}" == "--status" ]] && STATUS_ONLY=1
[[ $(id -u) -eq 0 ]] || die "run as root: sudo $0 $*"

# ---------------------------------------------------------------- packages + devices
if [[ "$SKIP_APT" != 1 && "$STATUS_ONLY" != 1 ]]; then
  if ! command -v tpm2_getcap >/dev/null || ! command -v clevis-luks-bind >/dev/null \
     || [[ ! -e /usr/share/initramfs-tools/hooks/clevis ]]; then
    y "installing tpm2-tools clevis clevis-luks clevis-tpm2 clevis-initramfs"
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      tpm2-tools clevis clevis-luks clevis-tpm2 clevis-initramfs || die "apt-get install failed"
  fi
fi
command -v tpm2_getcap >/dev/null || die "tpm2-tools missing: apt install tpm2-tools"
command -v clevis >/dev/null || die "clevis missing: apt install clevis clevis-luks clevis-tpm2 clevis-initramfs"

# jammy clevis ignores TPM2TOOLS_TCTI and always uses /dev/tpmrm?; match it.
if [[ -c /dev/tpmrm0 ]]; then export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
else die "no /dev/tpmrm0 - enable Intel PTT in the BIOS"; fi

if [[ -z "$DEV" ]]; then
  DEV="$(blkid -t TYPE=crypto_LUKS -o device 2>/dev/null)"
  [[ -n "$DEV" ]] || die "no LUKS partition found"
  [[ "$(wc -l <<<"$DEV")" -eq 1 ]] || die "more than one LUKS partition - re-run with DEV=/dev/..."
fi

# ---------------------------------------------------------------- helpers
VC=""
tpmvar() { sed -n "s/^[[:space:]]*$1:[[:space:]]*\([^[:space:]]*\).*/\1/p" <<<"$VC" | head -n1; }
num()    { local v; v="$(tpmvar "$1")"; [[ "$v" == 0x* ]] && printf '%d' "$v" || printf '%s' "${v:-0}"; }
readtpm() { VC="$(tpm2_getcap properties-variable 2>/dev/null)" || die "tpm2_getcap failed"; }

# "slot pin config" for every clevis binding
slots() { clevis luks list -d "$DEV" 2>/dev/null \
  | sed -n "s/^\([0-9]\{1,\}\):[[:space:]]*\([a-z0-9]\{1,\}\)[[:space:]]*'\(.*\)'[[:space:]]*$/\1 \2 \3/p"; }
pinned()   { slots | awk -v p="\"pcr_ids\":\"$PCR_IDS\"" '$2 == "tpm2" && index($3, p) { print $1 }'; }
unpinned() { slots | awk '$2 == "tpm2" && $3 !~ /pcr_ids/ { print $1 }'; }
unseals()  { clevis luks pass -d "$DEV" -s "$1" >/dev/null 2>&1; }

# cryptsetup --key-file=- is byte-exact; a typed passphrase has no trailing newline,
# a keyfile-set one may. Try both; a wrong passphrase fails every form.
pass_ok() {
  printf '%s'   "$1" | cryptsetup open --test-passphrase "$DEV" --key-file=- >/dev/null 2>&1 && return 0
  printf '%s\n' "$1" | cryptsetup open --test-passphrase "$DEV" --key-file=- >/dev/null 2>&1
}
# -k - is the guarded, documented stdin path; without it clevis dies on a pipe with no
# trailing newline.
bind() {
  local cfg="{\"pcr_bank\":\"$PCR_BANK\",\"pcr_ids\":\"$PCR_IDS\"}"
  printf '%s'   "$1" | clevis luks bind -y -k - -d "$DEV" tpm2 "$cfg" 2>/dev/null && return 0
  printf '%s\n' "$1" | clevis luks bind -y -k - -d "$DEV" tpm2 "$cfg"
}

# crypttab line for $DEV -> CT_NAME, CT_OPTS
ct_load() {
  local u line name src opts
  CT_NAME="" CT_OPTS=""
  [[ -r "$CT" ]] || return 0
  u="$(blkid -s UUID -o value "$DEV" 2>/dev/null)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    read -r name src _ opts _ <<<"$line"
    if [[ ( -n "$u" && "$src" == "UUID=$u" ) || "$(readlink -f "$src" 2>/dev/null)" == "$(readlink -f "$DEV")" ]]; then
      CT_NAME="$name" CT_OPTS="${opts:-}"; return 0
    fi
  done < "$CT"
}
custom_keyscript() {  # prints a non-stock keyscript from CT_OPTS, if any
  local o x; IFS=, read -ra o <<<"$CT_OPTS"
  for x in "${o[@]}"; do
    [[ "$x" == keyscript=* ]] || continue
    x="${x#keyscript=}"
    [[ "$x" != */* || "$x" == /lib/cryptsetup/scripts/* || "$x" == /usr/lib/cryptsetup/scripts/* ]] || printf '%s' "$x"
  done
}
live_name() {
  local n d
  for n in $(dmsetup ls --target crypt 2>/dev/null | awk '$1 != "No" { print $1 }'); do
    d="$(cryptsetup status "$n" 2>/dev/null | sed -n 's/^[[:space:]]*device:[[:space:]]*//p' | head -n1)"
    [[ -n "$d" && "$(readlink -f "$d")" == "$(readlink -f "$DEV")" ]] && { printf '%s' "$n"; return 0; }
  done
}

readtpm; ct_load
KS="$(custom_keyscript)"; LIVE="$(live_name)"

b "state"
printf '  %-17s %s\n' "LUKS device" "$DEV"
printf '  %-17s %s\n' "crypttab" "${CT_NAME:-<no entry>} ${CT_OPTS}"
printf '  %-17s %s\n' "open as" "${LIVE:-<not open>}"
printf '  %-17s %s\n' "lockoutAuthSet" "$(num lockoutAuthSet)"
printf '  %-17s %s\n' "inLockout" "$(num inLockout)"
printf '  %-17s maxTries=%s interval=%ss lockoutRecovery=%ss\n' "DA params" \
  "$(num TPM2_PT_MAX_AUTH_FAIL)" "$(num TPM2_PT_LOCKOUT_INTERVAL)" "$(num TPM2_PT_LOCKOUT_RECOVERY)"
while read -r s pin cfg; do
  [[ -n "${s:-}" ]] || continue
  note=""; [[ "$pin" == tpm2 && "$cfg" != *pcr_ids* ]] && note="  <-- NO pcr_ids: unseals in any boot state"
  printf '  slot %-12s %s %s%s\n' "$s" "$pin" "$cfg" "$note"
done < <(slots)
if [[ -n "$KS" ]]; then
  r "  crypttab unlocks through $KS, not clevis. If that script ever cannot get its"
  r "  key (TPM clear, BIOS/Secure Boot change) there is NO passphrase prompt: boot stops at"
  r "  (initramfs). Recommended: drop the keyscript - tpmfix.sh does it safely."
fi
(( STATUS_ONLY == 1 )) && exit 0

[[ "$(num inLockout)" == 1 ]] && die "TPM is in lockout - power off, unplug 15s, boot, re-run"

# ---------------------------------------------------------------- 1. DA parameters
b "1. dictionary-attack parameters"
have="$(num TPM2_PT_MAX_AUTH_FAIL)/$(num TPM2_PT_LOCKOUT_INTERVAL)/$(num TPM2_PT_LOCKOUT_RECOVERY)"
want="$MAXTRIES/$RECOVERY_TIME/$LOCKOUT_RECOVERY_TIME"
if [[ "$(num lockoutAuthSet)" == 0 ]]; then
  tpm2_dictionarylockout --setup-parameters \
    --max-tries="$MAXTRIES" --recovery-time="$RECOVERY_TIME" --lockout-recovery-time="$LOCKOUT_RECOVERY_TIME" \
    || die "tpm2_dictionarylockout refused"
  readtpm
  have="$(num TPM2_PT_MAX_AUTH_FAIL)/$(num TPM2_PT_LOCKOUT_INTERVAL)/$(num TPM2_PT_LOCKOUT_RECOVERY)"
  [[ "$have" == "$want" ]] || die "TPM reports $have after setting $want"
  g "  maxTries=$MAXTRIES recovery=${RECOVERY_TIME}s lockoutRecovery=${LOCKOUT_RECOVERY_TIME}s"
elif [[ "$have" == "$want" ]]; then
  g "  already $want (lockoutAuth is set, but nothing needs changing)"
else
  r "  lockoutAuth is already set (Windows sets it on first boot), so the TPM refuses new"
  r "  DA parameters. Current $have, wanted $want."
  die "run ./tpmfix.sh - it clears the TPM safely (checks your passphrase and crypttab first), then re-run this"
fi

# ---------------------------------------------------------------- 2. clevis
b "2. clevis sealed to PCR $PCR_IDS"
GOOD=""
for s in $(pinned); do unseals "$s" && { GOOD="$s"; break; }; done
if [[ -n "$GOOD" ]]; then
  g "  slot $GOOD already unseals - keeping it"
else
  if [[ -z "${LUKS_PASS:-}" ]]; then
    printf 'LUKS passphrase for %s: ' "$DEV" >&2; read -r -s LUKS_PASS; echo >&2
  fi
  [[ -n "$LUKS_PASS" ]] || die "empty passphrase"
  pass_ok "$LUKS_PASS" || die "that passphrase does not open $DEV"
  bind "$LUKS_PASS" || die "clevis luks bind failed"
  unset LUKS_PASS
  for s in $(pinned); do unseals "$s" && GOOD="$s"; done
  [[ -n "$GOOD" ]] || die "bound, but the TPM does not release the key - do not rely on it"
  g "  bound slot $GOOD, sealed to PCR $PCR_IDS"
fi

# ---------------------------------------------------------------- 3. old bindings
b "3. unsealed-anywhere bindings"
OLD="$(unpinned)"
if [[ -z "$OLD" ]]; then
  g "  none"
else
  # Only now: slot $GOOD is proven to unseal, and the passphrase slot is untouched.
  for s in $OLD; do
    clevis luks unbind -d "$DEV" -s "$s" -f && y "  removed slot $s (tpm2 with no pcr_ids)" \
      || r "  could not remove slot $s"
  done
fi

# ---------------------------------------------------------------- 4. initramfs
b "4. initramfs"
if [[ "$NO_INITRAMFS" == 1 ]]; then
  y "  skipped (NO_INITRAMFS=1)"
else
  if [[ -n "$LIVE" && -n "$CT_NAME" && "$LIVE" != "$CT_NAME" ]]; then
    die "$DEV is open as '$LIVE' but $CT says '$CT_NAME'; update-initramfs would build an initrd that cannot unlock it. Fix: sudo dmsetup rename $LIVE $CT_NAME"
  fi
  update-initramfs -u -k all || die "update-initramfs failed - do NOT reboot"
  img="/boot/initrd.img-$(uname -r)"
  if [[ -n "$CT_NAME" ]] && command -v unmkinitramfs >/dev/null; then
    tmp="$(mktemp -d)"
    unmkinitramfs "$img" "$tmp" >/dev/null 2>&1 || { rm -rf "$tmp"; die "$img will not unpack - do NOT reboot"; }
    line="$(find "$tmp" -path '*/cryptroot/crypttab' -type f -exec awk -v n="$CT_NAME" '$1 == n' {} + | head -n1)"
    hook="$(find "$tmp" -path '*/scripts/local-top/clevis' | head -n1)"
    rm -rf "$tmp"
    [[ -n "$line" ]] || die "$img has no '$CT_NAME' unlock entry - do NOT reboot"
    g "  $img: $line"
    [[ -n "$hook" ]] && g "  clevis hook present" || y "  no clevis hook in the initrd - boot will ask for the passphrase"
  fi
fi

b "DONE"
g "DA params $want, clevis slot $GOOD sealed to PCR $PCR_IDS."
y "Reboot once at the machine to confirm auto-unlock. Keep the LUKS passphrase: after a"
y "BIOS or Secure Boot change the TPM will (correctly) refuse and boot will ask for it."
[[ -n "$KS" ]] && r "crypttab still unlocks through $KS - see the warning at the top."
exit 0
