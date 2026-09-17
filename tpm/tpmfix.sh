#!/usr/bin/env bash
# tpmfix.sh - one script, no dependencies on anything else. It is an OFFLINE tool: it installs
# nothing. tpm2-tools, cryptsetup-bin, clevis, clevis-luks, clevis-tpm2, clevis-initramfs and
# initramfs-tools must already be in the image; it stops and names what is missing if not.
#
# Fixes three things on an Ubuntu 22.04 / Intel PTT box (ASUS NUC 15 Pro):
#   1. lockoutAuthSet=1 with an unknown password, which blocks every attempt to set
#      the dictionary-attack parameters (lockoutRecovery stuck at 24h).
#   2. a clevis LUKS binding with no pcr_ids, which unseals in ANY boot state.
#   3. an /etc/crypttab that unlocks the disk through a custom TPM keyscript
#      (e.g. keyscript=/usr/local/sbin/tpm2-getkey). The TPM clear destroys the key
#      that script unseals, and a crypttab keyscript is cryptroot's ONLY key source -
#      no passphrase prompt - so every boot ends at the (initramfs) shell. This script
#      drops the keyscript so cryptroot asks normally and clevis answers the prompt.
#
# It runs in two phases with a reboot between them, and works out which phase it is in
# by reading the TPM. Run it, reboot when told, run it again. Re-running is safe.
#
#   sudo ./tpmfix.sh              # act (asks for typed confirmation before a clear)
#   sudo ./tpmfix.sh --status     # read-only, changes nothing
#   sudo DRY=1 ./tpmfix.sh        # print every change instead of making it
#   sudo ALLOW_NO_CLEVIS=1 ./tpmfix.sh   # box has no clevis: repair boot only, no auto-unlock
#
# PHASE 1 verifies your LUKS passphrase, moves boot off any TPM keyscript, removes the
# clevis bindings, and asks the firmware to clear the TPM on the next boot.
# PHASE 2 makes sure boot can unlock without the old TPM key, sets the dictionary-attack
# parameters (default 32 tries / 60s / 60s, same as provision.sh), and binds clevis
# sealed to PCR 7.
#
# Settings (environment): MAXTRIES=32 RECOVERY_TIME=60 LOCKOUT_RECOVERY_TIME=60 PCR_IDS=7
#   DEV=/dev/...  (default: the only crypto_LUKS partition)
#
# New machine with nothing sealed yet? Use provision.sh instead.
#
# Already cleared and every boot stops at (initramfs)? At that prompt:
#   cryptsetup open /dev/nvme0n1p3 dm_crypt-0     (your LUKS partition; see blkid)
#   lvm vgchange -ay
#   exit
# then, once booted, run this script - it is in phase 2 and repairs the boot path.
set -uo pipefail

PCR_IDS="${PCR_IDS:-7}"
PCR_BANK="${PCR_BANK:-}"                             # empty: sha256 if the TPM has it, else sha1
MAXTRIES="${MAXTRIES:-32}"                           # auth failures before lockout
RECOVERY_TIME="${RECOVERY_TIME:-60}"                 # seconds until one failure is forgiven
LOCKOUT_RECOVERY_TIME="${LOCKOUT_RECOVERY_TIME:-60}" # seconds before lockoutAuth may be retried
DRY="${DRY:-0}"
DEV="${DEV:-}"
CT="${CRYPTTAB:-/etc/crypttab}"
STATE="${STATE:-/var/lib/tpmfix}"
PPI=/sys/class/tpm/tpm0/ppi

r()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
g()   { printf '\033[32m%s\033[0m\n' "$*"; }
y()   { printf '\033[33m%s\033[0m\n' "$*" >&2; }
b()   { printf '\033[1m\n== %s ==\033[0m\n' "$*"; }
die() { r "FAILED: $*"; exit 1; }
run() {
  if [[ "$DRY" == 1 ]]; then printf '  DRY: %s\n' "$*"; return 0; fi
  "$@"
}

# `cryptsetup --key-file=-` is BYTE-EXACT: it does not trim a trailing newline. clevis,
# by contrast, line-reads the passphrase and so drops one. A passphrase typed at an
# interactive prompt (every normal install) has no trailing newline, so the no-newline
# form is the realistic one and is tried first. The others are tried only as fallbacks,
# for a volume whose passphrase was set from a keyfile and therefore really does end in
# a newline. A wrong passphrase is rejected by every form, so this loosens nothing - it
# only stops a correct passphrase being wrongly refused, which here would read as
# "there is no way back in" right before an irreversible wipe.
# Sets PASS_SLOT to the keyslot the passphrase opened.
luks_pass_ok() {
  local pass="$1" dev="$2" out form
  PASS_SLOT=""
  for form in 1 2 3; do
    case "$form" in
      1) out="$(printf '%s'   "$pass" | cryptsetup open -v --test-passphrase "$dev" --key-file=- 2>&1)" ;;
      2) out="$(printf '%s\n' "$pass" | cryptsetup open -v --test-passphrase "$dev" --key-file=- 2>&1)" ;;
      3) out="$(printf '%s\n' "$pass" | cryptsetup open -v --test-passphrase "$dev" 2>&1)" ;;
    esac || continue
    PASS_SLOT="$(sed -n 's/^Key slot \([0-9]\{1,\}\) unlocked.*/\1/p' <<<"$out" | head -n1)"
    return 0
  done
  return 1
}

# The PCR bank to seal against. Firmware decides which banks are allocated: Dell ships
# some TPMs with only SHA-1 active, and then sealing to sha256 reads an empty PCR and
# tpm2_createpolicy dies with "pcr-input-file filesize does not match pcr set-list".
# A bank counts only if every PCR in PCR_IDS reads back a real value: all zeros (never
# extended) or all Fs would seal to a state every boot has, as weak as no pcr_ids.
bank_has_pcrs() {
  local bank="$1" out id v
  out="$(tpm2_pcrread "$bank:$PCR_IDS" 2>/dev/null)" || return 1
  for id in ${PCR_IDS//,/ }; do
    v="$(sed -n "s/^[[:space:]]*${id}[[:space:]]*:[[:space:]]*0x\([0-9A-Fa-f]\{1,\}\)[[:space:]]*$/\1/p" <<<"$out")"
    [[ -n "$v" && "$v" =~ [1-9A-Ea-e] ]] || return 1
  done
}
pick_bank() {
  local b
  if [[ -n "$PCR_BANK" ]]; then bank_has_pcrs "$PCR_BANK"; return; fi
  for b in sha256 sha1; do
    bank_has_pcrs "$b" && { PCR_BANK="$b"; return 0; }
  done
  return 1
}

# Same reasoning for the handoff to clevis: its documented no-newline form first.
# -k - is required: without it clevis reads with an unguarded `read` inside
# `#!/bin/bash -e`, and a pipe with no trailing newline kills it mid-bind.
clevis_bind() {
  local pass="$1" dev="$2" cfg="{\"pcr_bank\":\"$PCR_BANK\",\"pcr_ids\":\"$PCR_IDS\"}"
  printf '%s'   "$pass" | clevis luks bind -y -k - -d "$dev" tpm2 "$cfg" 2>/dev/null && return 0
  printf '%s\n' "$pass" | clevis luks bind -y -k - -d "$dev" tpm2 "$cfg" && return 0
  return 1
}

slots() { command -v clevis >/dev/null || return 0
  clevis luks list -d "$DEV" 2>/dev/null \
    | sed -n "s/^\([0-9]\{1,\}\):[[:space:]]*\([a-z0-9]\{1,\}\)[[:space:]]*'\(.*\)'[[:space:]]*$/\1 \2 \3/p"; }
luks_slots() { cryptsetup luksDump "$DEV" 2>/dev/null \
    | sed -n 's/^[[:space:]]\{1,\}\([0-9]\{1,\}\): luks2.*/\1/p; s/^Key Slot \([0-9]\{1,\}\): ENABLED.*/\1/p'; }
nslots() { luks_slots | wc -l | tr -d ' '; }

# ---------------------------------------------------------------- crypttab
# The /etc/crypttab line for $DEV, as "lineno<TAB>name<TAB>source<TAB>key<TAB>options".
# Matches UUID=, PARTUUID= and any /dev path that resolves to $DEV. Prints nothing if
# there is no entry.
ct_entry() {
  local n=0 line name src key opts rest u pu
  [[ -r "$CT" ]] || return 0
  u="${UUID_DEV:-$(blkid -s UUID -o value "$DEV" 2>/dev/null)}"
  pu="${PARTUUID_DEV:-$(blkid -s PARTUUID -o value "$DEV" 2>/dev/null)}"
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    read -r name src key opts rest <<<"$line"
    case "$src" in
      UUID=*)     [[ -n "$u"  && "${src#UUID=}" == "$u" ]] || continue ;;
      PARTUUID=*) [[ -n "$pu" && "${src#PARTUUID=}" == "$pu" ]] || continue ;;
      /*)         [[ "$(readlink -f "$src" 2>/dev/null)" == "$(readlink -f "$DEV" 2>/dev/null)" ]] || continue ;;
      *)          continue ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$name" "$src" "${key:-none}" "${opts:-}"
    return 0
  done < "$CT"
}

# Loads CT_LN CT_NAME CT_SRC CT_KEY CT_OPTS CT_KS from the current crypttab.
ct_load() {
  CT_LN="" CT_NAME="" CT_SRC="" CT_KEY="" CT_OPTS="" CT_KS=""
  IFS=$'\t' read -r CT_LN CT_NAME CT_SRC CT_KEY CT_OPTS <<<"$(ct_entry)"
  CT_KS="$(keyscript_of "$CT_OPTS")" || CT_KS=""
}

keyscript_of() {
  local o x
  IFS=, read -ra o <<<"$1"
  for x in "${o[@]}"; do
    [[ "$x" == keyscript=* ]] && { printf '%s' "${x#keyscript=}"; return 0; }
  done
  return 1
}

# Keyscripts shipped by cryptsetup (decrypt_keyctl, passdev, decrypt_derived, ...)
# prompt or derive; they do not hold a TPM key and are left alone.
stock_keyscript() {
  [[ "$1" != */* || "$1" == /lib/cryptsetup/scripts/* || "$1" == /usr/lib/cryptsetup/scripts/* ]]
}

ks_is_tpm() {
  [[ "$(basename "$1")" == *tpm* ]] || grep -qiE 'tpm2_|tpm2-|tpm_|clevis|tcti' "$1" 2>/dev/null
}

strip_keyscript() {
  local o x out=()
  IFS=, read -ra o <<<"$1"
  for x in "${o[@]}"; do [[ -n "$x" && "$x" != keyscript=* ]] && out+=("$x"); done
  (( ${#out[@]} )) || out=(luks)
  local IFS=,; printf '%s' "${out[*]}"
}

ct_rewrite() {
  local n="$1" tmp
  tmp="$(mktemp "${CT}.tpmfix.XXXXXX")" || return 1
  if ! L="$2" awk -v n="$n" 'NR == n { print ENVIRON["L"]; next } { print }' "$CT" > "$tmp"; then
    rm -f "$tmp"; return 1
  fi
  chmod --reference="$CT" "$tmp" 2>/dev/null
  chown --reference="$CT" "$tmp" 2>/dev/null
  mv -f "$tmp" "$CT"
}

# Removes a TPM keyscript from $DEV's crypttab line so cryptroot falls back to its
# askpass prompt, which clevis answers (or you do). With a keyscript the key field is
# only the script's argument, so it becomes "none" too - otherwise cryptroot would try
# it as a key FILE, once, and still never prompt.
# Returns 0 fixed or nothing to do, 1 write failed, 2 custom keyscript that does not
# look TPM-based (left alone). Sets CT_CHANGED=1 and CT_BAK when it wrote.
fix_crypttab() {
  CT_CHANGED=0 CT_BAK=""
  ct_load
  if [[ -z "$CT_LN" ]]; then
    y "  no $CT entry for $DEV - nothing to change there"
    return 0
  fi
  if [[ -z "$CT_KS" ]]; then
    g "  $CT_NAME: no keyscript - cryptroot prompts, clevis answers the prompt"
    return 0
  fi
  if stock_keyscript "$CT_KS"; then
    y "  $CT_NAME uses cryptsetup's own keyscript $CT_KS - not a TPM key, leaving it"
    return 0
  fi
  if ! ks_is_tpm "$CT_KS"; then
    r "  $CT_NAME unlocks through $CT_KS, which does not look TPM-based"
    return 2
  fi
  local newline
  newline="$CT_NAME $CT_SRC none $(strip_keyscript "$CT_OPTS")"
  printf '  before: %s\n' "$(sed -n "${CT_LN}p" "$CT")"
  printf '  after:  %s\n' "$newline"
  if [[ "$DRY" == 1 ]]; then
    printf '  DRY: rewrite %s line %s\n' "$CT" "$CT_LN"; CT_CHANGED=1; return 0
  fi
  CT_BAK="$CT.tpmfix-$(date +%Y%m%d-%H%M%S).bak"
  cp -p "$CT" "$CT_BAK" || return 1
  ct_rewrite "$CT_LN" "$newline" || return 1
  CT_CHANGED=1
  g "  $CT rewritten, backup at $CT_BAK"
}

# Runs the keyscript the way cryptroot does and reports which LUKS slot its key opens -
# the slot that becomes dead weight once the TPM is cleared. Best effort: prints nothing
# if the script needs anything we do not provide.
keyscript_slot() {
  local out
  [[ -x "$CT_KS" ]] || return 0
  out="$(CRYPTTAB_NAME="$CT_NAME" CRYPTTAB_SOURCE="$DEV" CRYPTTAB_KEY="$CT_KEY" \
         CRYPTTAB_OPTIONS="$CT_OPTS" CRYPTTAB_TRIED=0 \
         timeout 30 "$CT_KS" "$CT_KEY" </dev/null 2>/dev/null \
         | cryptsetup open -v --test-passphrase "$DEV" --key-file=- 2>&1)" || return 0
  sed -n 's/^Key slot \([0-9]\{1,\}\) unlocked.*/\1/p' <<<"$out" | head -n1
}

# ---------------------------------------------------------------- live mapping
# The name $DEV is open under right now (e.g. "dm_crypt-0"), or nothing.
live_name() {
  local n dev
  command -v dmsetup >/dev/null || return 0
  for n in $(dmsetup ls --target crypt 2>/dev/null | awk '$1 != "No" { print $1 }'); do
    dev="$(cryptsetup status "$n" 2>/dev/null | sed -n 's/^[[:space:]]*device:[[:space:]]*//p' | head -n1)"
    if [[ -n "$dev" && "$(readlink -f "$dev")" == "$(readlink -f "$DEV")" ]]; then
      printf '%s' "$n"; return 0
    fi
  done
}

# update-initramfs finds the root's crypttab entry by the LIVE dm-crypt name under /
# (jammy /lib/cryptsetup/functions: _foreach_cryptdev -> dmsetup unmangled_name ->
# crypttab_find_entry). Unlock by hand as anything but the crypttab name - e.g.
# `cryptsetup open /dev/nvme0n1p3 os-vg` at the (initramfs) prompt - and it prints
# "target 'os-vg' not found in /etc/crypttab" and builds an initrd with NO unlock
# entry at all. Renaming the open mapping is a name change only (same device number,
# holders untouched), so it is safe with root mounted on it.
fix_mapping() {
  local live
  [[ -n "$CT_NAME" ]] || return 0
  live="$(live_name)"
  if [[ -z "$live" ]]; then
    y "  $DEV is not open (or dmsetup is missing) - nothing to match"
    return 0
  fi
  if [[ "$live" == "$CT_NAME" ]]; then
    g "  $DEV is open as $live, matching $CT"
    return 0
  fi
  y "  $DEV is open as '$live' but $CT names it '$CT_NAME'."
  y "  update-initramfs matches by the live name, so it would build an initrd that never unlocks $DEV."
  if [[ -e "/dev/mapper/$CT_NAME" ]]; then
    r "  /dev/mapper/$CT_NAME already exists - cannot rename $live to it"
    return 1
  fi
  local direct=0
  findmnt -rno SOURCE 2>/dev/null | grep -qxF "/dev/mapper/$live" && direct=1
  run dmsetup rename "$live" "$CT_NAME" || return 1
  [[ "$DRY" == 1 ]] || udevadm settle 2>/dev/null
  [[ "$DRY" == 1 || "$(live_name)" == "$CT_NAME" ]] || { r "  rename did not take"; return 1; }
  g "  renamed the open mapping $live -> $CT_NAME"
  # A filesystem mounted straight off the mapping keeps the OLD path in /proc/mounts,
  # and the hook resolves / through that path (stat -L). Point the old name at the
  # renamed node until the initrd is rebuilt; drop_compat_link removes it.
  if (( direct )); then
    # absolute: /dev/mapper/NAME is a ../dm-N link under udev but a real node without it
    run ln -sfn "$(readlink -f "/dev/mapper/$CT_NAME")" "/dev/mapper/$live" || return 1
    COMPAT_LINK="/dev/mapper/$live"
    y "  a filesystem is mounted directly on it: $COMPAT_LINK kept as a link until the initrd is built"
  fi
}

drop_compat_link() {
  [[ -n "${COMPAT_LINK:-}" && -L "$COMPAT_LINK" ]] && run rm -f "$COMPAT_LINK"
  COMPAT_LINK=""
}

# ---------------------------------------------------------------- initrd check
# update-initramfs exiting 0 is not proof: this checks what the next boot will actually
# run. The initrd's cryptroot/crypttab must name $CT_NAME, and must not carry a keyscript
# that /etc/crypttab no longer has.
verify_initrd() {
  local img="$1" tmp ct line rc=0
  [[ -s "$img" ]] || { r "  $img missing or empty"; return 1; }
  tmp="$(mktemp -d)" || return 1
  if ! unmkinitramfs "$img" "$tmp" >/dev/null 2>&1; then
    rm -rf "$tmp"; r "  $img will not unpack (truncated?)"; return 1
  fi
  ct="$(find "$tmp" -path '*/cryptroot/crypttab' -type f 2>/dev/null | head -n1)"
  line=""
  [[ -n "$ct" ]] && line="$(awk -v n="$CT_NAME" '$1 == n { print; exit }' "$ct")"
  if [[ -z "$line" ]]; then
    r "  $img: no '$CT_NAME' in its cryptroot/crypttab - it would not unlock $DEV"; rc=1
  elif [[ -z "$CT_KS" && "$line" == *keyscript=* ]]; then
    r "  $img: still unlocks via a keyscript: $line"; rc=1
  else
    g "  $img: $line"
  fi
  if ! find "$tmp" -path '*/scripts/local-top/clevis' 2>/dev/null | grep -q .; then
    if [[ -n "$(slots | awk '$2 == "tpm2" { print $1 }')" ]]; then
      r "  $img: no clevis hook, but $DEV has a tpm2 binding - that kernel cannot auto-unlock"; rc=1
    else
      y "  $img: no clevis hook - boot will ask for the passphrase (no auto-unlock)"
    fi
  fi
  rm -rf "$tmp"
  return "$rc"
}

verify_initrds() {
  local k img fails=0 n=0
  [[ -n "$CT_NAME" ]] || { y "  no crypttab entry to check the initrd against"; return 0; }
  command -v unmkinitramfs >/dev/null || { r "  unmkinitramfs missing (initramfs-tools-core)"; return 1; }
  for k in /boot/vmlinuz-*; do
    [[ -f "$k" ]] || continue
    img="/boot/initrd.img-${k#/boot/vmlinuz-}"
    n=$((n + 1))
    verify_initrd "$img" || fails=$((fails + 1))
  done
  (( n > 0 )) || { r "  no kernels found in /boot"; return 1; }
  (( fails == 0 ))
}

# Offline box: nothing is installed here, it is only checked for.
need_clevis() {
  local miss=()
  command -v clevis >/dev/null || miss+=(clevis)
  command -v clevis-luks-bind >/dev/null || miss+=(clevis-luks)
  command -v clevis-encrypt-tpm2 >/dev/null || miss+=(clevis-tpm2)
  [[ -e /usr/share/initramfs-tools/hooks/clevis ]] || miss+=(clevis-initramfs)
  if (( ${#miss[@]} == 0 )); then return 0; fi
  r "  missing and NOT installable offline: ${miss[*]} - bake clevis clevis-luks clevis-tpm2 clevis-initramfs into the image"
  return 1
}

# Sourcing with TPMFIX_LIB=1 loads the functions above without running anything (tests).
[[ "${TPMFIX_LIB:-0}" == 1 ]] && return 0

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0; }
STATUS_ONLY=0
[[ "${1:-}" == "--status" ]] && STATUS_ONLY=1
[[ $(id -u) -eq 0 ]] || die "run as root: sudo $0 $*"

# ---------------------------------------------------------------- discover
need=()
for c in tpm2_getcap cryptsetup blkid awk; do command -v "$c" >/dev/null || need+=("$c"); done
if (( STATUS_ONLY == 0 )); then   # --status must still report on a box that is missing packages
  for c in tpm2_dictionarylockout dmsetup findmnt find update-initramfs unmkinitramfs; do
    command -v "$c" >/dev/null || need+=("$c")
  done
fi
if (( ${#need[@]} )); then
  die "missing on this box: ${need[*]} - nothing can be installed offline, so bake tpm2-tools cryptsetup-bin util-linux dmsetup initramfs-tools into the image first"
fi
# clevis is what restores auto-unlock after the clear. Without it phase 1 destroys the TPM key
# and nothing can rebind - so say so BEFORE anything is queued, not after the reboot.
if (( STATUS_ONLY == 0 )) && ! need_clevis && [[ "${ALLOW_NO_CLEVIS:-0}" != 1 ]]; then
  die "a TPM clear would leave this box with no auto-unlock and no way to restore it offline. Run with ALLOW_NO_CLEVIS=1 if you only want the crypttab/boot repair (you will type the passphrase at every boot)"
fi
if [[ -c /dev/tpmrm0 ]]; then export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
elif [[ -c /dev/tpm0 ]]; then export TPM2TOOLS_TCTI="device:/dev/tpm0"
else die "no /dev/tpm* - TPM/PTT disabled in BIOS?"; fi

VC="$(tpm2_getcap properties-variable 2>/dev/null)" || die "tpm2_getcap failed"
p() { sed -n "s/^[[:space:]]*$1:[[:space:]]*\([^[:space:]]*\).*/\1/p" <<<"$VC" | head -n1; }
d() { local v; v="$(p "$1")"; [[ "$v" == 0x* ]] && printf '%d' "$v" || printf '%s' "${v:-0}"; }

LOCKAUTH="$(d lockoutAuthSet)"; INLOCK="$(d inLockout)"
OWNAUTH="$(d ownerAuthSet)";    PHEN="$(d phEnable)"
RCV="$(d TPM2_PT_LOCKOUT_RECOVERY)"

if [[ -z "$DEV" ]]; then
  DEV="$(blkid -t TYPE=crypto_LUKS -o device 2>/dev/null | head -n2)"
  [[ -n "$DEV" ]] || die "no LUKS container found"
  [[ "$(wc -l <<<"$DEV")" -le 1 ]] || die "more than one LUKS device:
$DEV
re-run with DEV=/dev/... set"
  DEV="$(head -n1 <<<"$DEV")"
fi

ct_load

b "state"
printf '  %-18s %s\n' "LUKS device" "$DEV"
printf '  %-18s %s\n' "keyslots" "$(luks_slots | tr '\n' ' ')"
printf '  %-18s %s\n' "lockoutAuthSet" "$LOCKAUTH"
printf '  %-18s %s\n' "ownerAuthSet" "$OWNAUTH"
printf '  %-18s %s\n' "inLockout" "$INLOCK"
printf '  %-18s %ss\n' "lockoutRecovery" "$RCV"
printf '  %-18s %s\n' "phEnable" "$PHEN"
if pick_bank; then
  printf '  %-18s %s\n' "pcr bank" "$PCR_BANK"
  [[ "$PCR_BANK" == sha1 ]] && y "  only the SHA-1 PCR bank is active - works, but set the TPM to SHA-256 in BIOS
    (Dell: System Security > TPM Advanced Settings > TPM2 Algorithm Selection) and re-run"
else
  r "  pcr bank           ${PCR_BANK:-sha256/sha1}: PCR $PCR_IDS unreadable - clevis cannot seal"
  PCR_BANK_BAD=1
fi
if [[ -n "$CT_LN" ]]; then
  printf '  %-18s %s %s %s %s\n' "crypttab" "$CT_NAME" "$CT_SRC" "$CT_KEY" "$CT_OPTS"
else
  printf '  %-18s %s\n' "crypttab" "<no entry for $DEV>"
fi
LIVE="$(live_name)"
if [[ -n "$LIVE" && -n "$CT_NAME" && "$LIVE" != "$CT_NAME" ]]; then
  printf '  %-18s %s  <-- crypttab says %s: update-initramfs will build an initrd that cannot unlock\n' \
    "open as" "$LIVE" "$CT_NAME"
else
  printf '  %-18s %s\n' "open as" "${LIVE:-<not open>}"
fi
if [[ -n "$CT_KS" ]] && ! stock_keyscript "$CT_KS"; then
  printf '  %-18s %s  <-- boot unlock depends on this script\n' "keyscript" "$CT_KS"
  if [[ "$LOCKAUTH" == 0 ]] && ks_is_tpm "$CT_KS"; then
    r "  TPM has no lockout password (cleared, or never set) and boot uses a TPM keyscript:"
    r "  if that key was lost with a clear, every boot stops at (initramfs)."
    r "  Run this script without --status to repair it."
  fi
fi
while read -r s pin cfg; do
  [[ -n "${s:-}" ]] || continue
  if [[ "$pin" == tpm2 && "$cfg" != *pcr_ids* ]]; then
    printf '  slot %-13s %s %s  <-- NO pcr_ids\n' "$s" "$pin" "$cfg"
  else
    printf '  slot %-13s %s %s\n' "$s" "$pin" "$cfg"
  fi
done < <(slots)

(( STATUS_ONLY == 1 )) && exit 0
[[ "$INLOCK" == "1" ]] && die "TPM is in lockout. Power off, unplug, hold power 15s, boot, re-run."

# ---------------------------------------------------------------- phase 2
if [[ "$LOCKAUTH" == "0" ]]; then
  b "PHASE 2 - TPM is cleared, finishing up"
  FAILS=0

  need_clevis || { r "  clevis is missing: this run can only leave you with a passphrase prompt"; FAILS=$((FAILS + 1)); }

  # First, because it is the one that decides whether the machine boots.
  b "2a. boot unlock path ($CT)"
  fix_crypttab; rc=$?
  (( rc == 1 )) && die "could not rewrite $CT"
  (( rc == 2 )) && { y "  review that script yourself; leaving it in place"; FAILS=$((FAILS + 1)); }

  b "2b. dictionary-attack parameters"
  if run tpm2_dictionarylockout --setup-parameters --max-tries="$MAXTRIES" \
       --recovery-time="$RECOVERY_TIME" --lockout-recovery-time="$LOCKOUT_RECOVERY_TIME"; then
    g "  maxTries=$MAXTRIES recovery=${RECOVERY_TIME}s lockoutRecovery=${LOCKOUT_RECOVERY_TIME}s"
  else
    r "  could not set DA params (lockoutAuthSet=0, so this should have worked)"
    FAILS=$((FAILS + 1))
  fi

  b "2c. clevis sealed to PCR $PCR_IDS"
  BOUND=""
  for s in $(slots | awk -v p="pcr_ids\":\"$PCR_IDS\"" '$2 == "tpm2" && index($3, p) { print $1 }'); do
    if [[ "$DRY" == 1 ]] || clevis luks pass -d "$DEV" -s "$s" >/dev/null 2>&1; then BOUND="$s"; break; fi
    y "  slot $s is sealed to the TPM as it was before the clear - it can never unseal"
    y "    remove it once you are happy: sudo clevis luks unbind -d $DEV -s $s -f"
  done
  if [[ -z "$BOUND" && "${PCR_BANK_BAD:-0}" == 1 ]]; then
    r "  no active PCR bank holds PCR $PCR_IDS (tpm2_getcap pcrs) - enable SHA-256 in BIOS"
    FAILS=$((FAILS + 1))
  elif [[ -n "$BOUND" ]]; then
    g "  slot $BOUND already unseals against the current PCR $PCR_IDS state - keeping it"
  elif ! need_clevis; then
    r "  so boot will ask for the passphrase every time"
    FAILS=$((FAILS + 1))
  else
    printf 'existing LUKS passphrase for %s: ' "$DEV" >&2
    read -r -s PASS; echo >&2
    [[ -n "$PASS" ]] || die "empty passphrase"
    luks_pass_ok "$PASS" "$DEV" || die "that passphrase does not open $DEV"
    g "  passphrase verified${PASS_SLOT:+ (keyslot $PASS_SLOT)}"
    if [[ "$DRY" == 1 ]]; then
      printf '  DRY: clevis luks bind -y -k - -d %s tpm2 {pcr_bank:%s,pcr_ids:%s}\n' "$DEV" "$PCR_BANK" "$PCR_IDS"
      BOUND=dry
    elif clevis_bind "$PASS" "$DEV"; then
      BOUND="$(slots | awk -v p="pcr_ids\":\"$PCR_IDS\"" '$2 == "tpm2" && index($3, p) { s = $1 } END { print s }')"
      if [[ -n "$BOUND" ]] && clevis luks pass -d "$DEV" -s "$BOUND" >/dev/null 2>&1; then
        g "  bound slot $BOUND, and the TPM releases its key"
      else
        r "  bound, but the new slot did not unseal - boot will ask for the passphrase"
        FAILS=$((FAILS + 1))
      fi
    else
      r "  bind failed - boot will ask for the passphrase"
      FAILS=$((FAILS + 1))
    fi
    unset PASS
  fi

  # A tpm2 binding with no pcr_ids unseals in any boot state (or, sealed before the
  # clear, never). Either way it goes - but only once a PCR-sealed slot is proven.
  if [[ -n "$BOUND" && "$BOUND" != dry ]]; then
    for s in $(slots | awk '$2 == "tpm2" && $3 !~ /pcr_ids/ { print $1 }'); do
      run clevis luks unbind -d "$DEV" -s "$s" -f && y "  removed slot $s (tpm2 with no pcr_ids)"
    done
  fi

  # Always rebuilt: askpass only goes into the initrd once crypttab has no keyscript,
  # and the clevis hook only if clevis-initramfs is installed.
  b "2d. initramfs"
  ct_load
  fix_mapping || die "the open mapping name does not match $CT - fix that before rebuilding the initrd"
  run update-initramfs -u -k all || { drop_compat_link; die "update-initramfs failed - do NOT reboot until it succeeds"; }
  drop_compat_link
  if [[ "$DRY" == 1 ]]; then
    printf '  DRY: would unpack each /boot/initrd.img-* and check its cryptroot/crypttab\n'
  else
    verify_initrds || die "the new initrd would not unlock $DEV - do NOT reboot.${CT_BAK:+ Your old crypttab is at $CT_BAK.}"
  fi

  # The keyslot the keyscript's key opened is now unusable: the only copy was in the TPM.
  DEADKS=""
  [[ -r "$STATE/keyscript-slot" ]] && DEADKS="$(sed -n 's/^slot=\([0-9]\{1,\}\).*/\1/p' "$STATE/keyscript-slot")"
  if [[ -n "$DEADKS" ]]; then
    y "  keyslot $DEADKS held the old keyscript's TPM key (recorded in phase 1). It is dead."
    y "    remove it once auto-unlock works: sudo cryptsetup luksKillSlot $DEV $DEADKS"
  elif [[ "$CT_CHANGED" == 1 && -n "${PASS_SLOT:-}" ]]; then
    others="$(luks_slots | grep -vxF "$PASS_SLOT" | grep -vxF -f <(slots | awk '{ print $1 }') | tr '\n' ' ')"
    [[ -n "${others// /}" ]] && y "  keyslot(s) ${others}are neither your passphrase nor clevis - likely the dead keyscript key. Check before removing."
  fi

  b "DONE"
  g "boot unlock: cryptroot prompt${BOUND:+, answered by clevis (PCR $PCR_IDS)}; lockoutRecovery=${LOCKOUT_RECOVERY_TIME}s."
  y "Reboot once at the machine to confirm. PCR 7 is the Secure Boot state: changing"
  y "Secure Boot or enrolling keys stops it unsealing, by design. Keep your passphrase."
  (( FAILS == 0 )) || { r "$FAILS step(s) above did not complete - boot still works with the passphrase."; exit 1; }
  exit 0
fi

# ---------------------------------------------------------------- phase 1
b "PHASE 1 - clear the TPM"
cat <<MSG

lockoutAuthSet=1 and the password is unknown, so TPM2_DictionaryAttackParameters is
refused and lockoutRecovery stays at ${RCV}s. The only reset is TPM2_Clear.

This is IRREVERSIBLE. It regenerates the storage and endorsement seeds. Every key
sealed to this TPM is destroyed - the clevis binding(s) on $DEV, and the key behind
any crypttab keyscript - which is why the passphrase check below is not optional.

On Intel PTT the firmware does NOT show a confirmation screen: the next boot wipes
the TPM with no further chance to stop.
MSG

# Refuse before touching anything if boot depends on a script we cannot judge.
if [[ -n "$CT_KS" ]] && ! stock_keyscript "$CT_KS" && ! ks_is_tpm "$CT_KS"; then
  die "$CT_NAME unlocks through $CT_KS, which does not look TPM-based. Read it, and remove keyscript= from $CT yourself if it depends on the TPM."
fi

# Clearing is pointless if phase 2 has no PCR bank to seal to: the box would end up on
# the passphrase with an irreversible clear behind it.
[[ "${PCR_BANK_BAD:-0}" == 1 ]] && die "no active PCR bank holds PCR $PCR_IDS - enable SHA-256 in BIOS first (tpm2_getcap pcrs)"

b "1a. can you open $DEV without the TPM?"
printf 'existing LUKS passphrase for %s: ' "$DEV" >&2
read -r -s PASS1; echo >&2
[[ -n "$PASS1" ]] || die "empty passphrase - refusing to clear a TPM you cannot recover from"
luks_pass_ok "$PASS1" "$DEV" \
  || die "that passphrase does not open $DEV. Refusing to go further - you would not get back in."
unset PASS1
g "  passphrase verified${PASS_SLOT:+ (keyslot $PASS_SLOT)} - you can boot without the TPM"

b "1b. PPI availability"
[[ -d "$PPI" ]] || die "no $PPI - the OS cannot request a clear. Use the BIOS: Intel PTT off -> full boot -> on."
OP=""
for o in 5 22 21 14; do
  st="$(sed -n "s/^[[:space:]]*${o}[[:space:]]\{1,\}\([0-9]\{1,\}\):.*/\1/p" "$PPI/tcg_operations" 2>/dev/null | head -n1)"
  printf '  opcode %-3s status %s\n' "$o" "${st:-absent}"
  [[ -z "$OP" && ( "$st" == 3 || "$st" == 4 ) ]] && OP="$o"
done
[[ -n "$OP" ]] || die "firmware exposes no usable clear opcode. Use the BIOS: Intel PTT off -> full boot -> on."
ST="$(sed -n "s/^[[:space:]]*${OP}[[:space:]]\{1,\}\([0-9]\{1,\}\):.*/\1/p" "$PPI/tcg_operations" | head -n1)"
g "  will use opcode $OP"
[[ "$ST" == 4 ]] && r "  status 4 = firmware will NOT prompt. The reboot is the point of no return."
[[ "$ST" == 3 ]] && y "  status 3 = firmware will prompt at the machine; declining is safe."

b "1c. confirm"
PHRASE="CLEAR MY TPM AND DESTROY ITS KEYS"
printf 'Type exactly: \033[1m%s\033[0m\n> ' "$PHRASE"
read -r ANS
[[ "$ANS" == "$PHRASE" ]] || die "not confirmed"

REM=$(( $(nslots) - $(slots | wc -l) ))
(( REM >= 1 )) || die "removing the clevis bindings would leave 0 keyslots on $DEV"

b "1d. move boot off the TPM keyscript"
if [[ -n "$CT_KS" ]] && ! stock_keyscript "$CT_KS"; then
  KSLOT="$(keyscript_slot)"
  if [[ -n "$KSLOT" ]]; then
    g "  $CT_KS opens keyslot $KSLOT - that slot dies with the clear"
    run mkdir -p "$STATE"
    [[ "$DRY" == 1 ]] || printf 'slot=%s keyscript=%s dev=%s date=%s\n' \
      "$KSLOT" "$CT_KS" "$DEV" "$(date -Is)" > "$STATE/keyscript-slot"
  fi
fi
fix_crypttab; rc=$?
(( rc == 0 )) || die "could not rewrite $CT - nothing queued"

b "1e. remove clevis bindings"
# They cannot survive the clear, and leaving them makes boot attempt a doomed unseal
# before falling back to the passphrase prompt.
while read -r s pin cfg; do
  [[ -n "${s:-}" ]] || continue
  printf '  unbinding slot %s (%s)\n' "$s" "$pin"
  run clevis luks unbind -d "$DEV" -s "$s" -f || y "  slot $s failed"
done < <(slots)

b "1f. initramfs"
# Fatal now: if the initrd is not rebuilt with the new crypttab, the clearing boot runs
# the old keyscript against an empty TPM and stops at (initramfs).
restore_ct() {
  [[ "$CT_CHANGED" == 1 && -n "$CT_BAK" ]] || return 0
  cp -p "$CT_BAK" "$CT" && update-initramfs -u -k all >/dev/null 2>&1
  y "  $CT restored from $CT_BAK"
}
ct_load
fix_mapping || { restore_ct; die "the open mapping name does not match $CT - nothing queued"; }
run update-initramfs -u -k all || { drop_compat_link; restore_ct; die "update-initramfs failed - nothing queued"; }
drop_compat_link
if [[ "$DRY" == 1 ]]; then
  printf '  DRY: would unpack each /boot/initrd.img-* and check its cryptroot/crypttab\n'
else
  verify_initrds || { restore_ct; die "the new initrd would not unlock $DEV - nothing queued"; }
fi

b "1g. queue the clear"
run tee "$PPI/request" <<<"$OP" >/dev/null || die "write to $PPI/request refused - PPI disabled in BIOS setup?"
g "  opcode $OP queued"

b "REBOOT NOW - at the machine, with a keyboard"
cat <<MSG

  sudo reboot

The TPM is wiped during that boot. It will then ask for your LUKS passphrase, which
is expected: auto-unlock is gone until you run phase 2.

To back out instead, before rebooting:
  echo 0 | sudo tee $PPI/request
${CT_BAK:+  sudo cp -p $CT_BAK $CT && sudo update-initramfs -u -k all}

After the reboot, run this same script again to finish:
  sudo $0
MSG
