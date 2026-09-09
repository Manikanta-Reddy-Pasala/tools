#!/usr/bin/env bash
# tpmfix.sh - one script, no dependencies on anything else.
#
# Fixes two things on an Ubuntu 22.04 / Intel PTT box (ASUS NUC 15 Pro):
#   1. lockoutAuthSet=1 with an unknown password, which blocks every attempt to set
#      the dictionary-attack parameters (lockoutRecovery stuck at 24h).
#   2. a clevis LUKS binding with no pcr_ids, which unseals in ANY boot state.
#
# It runs in two phases with a reboot between them, and works out which phase it is in
# by reading the TPM. Run it, reboot when told, run it again.
#
#   sudo ./tpmfix.sh              # act (asks for typed confirmation before anything)
#   sudo ./tpmfix.sh --status     # read-only, changes nothing
#   sudo DRY=1 ./tpmfix.sh        # print every command instead of running it
#
# PHASE 1 verifies your LUKS passphrase, removes the clevis bindings, and asks the
# firmware to clear the TPM on the next boot.
# PHASE 2 sets lockoutRecovery=0 and rebinds clevis sealed to PCR 7.
set -uo pipefail

PCR_IDS="${PCR_IDS:-7}"
PCR_BANK="${PCR_BANK:-sha256}"
MAXTRIES="${MAXTRIES:-32}"
INTERVAL="${INTERVAL:-7200}"
RECOVERY="${RECOVERY:-0}"
DRY="${DRY:-0}"
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

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { sed -n '2,22p' "$0"; exit 0; }
STATUS_ONLY=0
[[ "${1:-}" == "--status" ]] && STATUS_ONLY=1
[[ $(id -u) -eq 0 ]] || die "run as root: sudo $0 $*"

# ---------------------------------------------------------------- discover
command -v tpm2_getcap >/dev/null || {
  y "installing tpm2-tools + cryptsetup"
  run env DEBIAN_FRONTEND=noninteractive apt-get update -qq
  run env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tpm2-tools cryptsetup-bin
  command -v tpm2_getcap >/dev/null || die "tpm2-tools still missing"
}
if [[ -c /dev/tpmrm0 ]]; then export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
elif [[ -c /dev/tpm0 ]]; then export TPM2TOOLS_TCTI="device:/dev/tpm0"
else die "no /dev/tpm* - TPM/PTT disabled in BIOS?"; fi

VC="$(tpm2_getcap properties-variable 2>/dev/null)" || die "tpm2_getcap failed"
p() { sed -n "s/^[[:space:]]*$1:[[:space:]]*\([^[:space:]]*\).*/\1/p" <<<"$VC" | head -n1; }
d() { local v; v="$(p "$1")"; [[ "$v" == 0x* ]] && printf '%d' "$v" || printf '%s' "${v:-0}"; }

LOCKAUTH="$(d lockoutAuthSet)"; INLOCK="$(d inLockout)"
OWNAUTH="$(d ownerAuthSet)";    PHEN="$(d phEnable)"
RCV="$(d TPM2_PT_LOCKOUT_RECOVERY)"

DEV="$(blkid -t TYPE=crypto_LUKS -o device 2>/dev/null | head -n2)"
[[ -n "$DEV" ]] || die "no LUKS container found"
[[ "$(wc -l <<<"$DEV")" -le 1 ]] || die "more than one LUKS device:\n$DEV\nedit DEV= in this script"
DEV="$(head -n1 <<<"$DEV")"

slots() { command -v clevis >/dev/null || return 0
  clevis luks list -d "$DEV" 2>/dev/null \
    | sed -n "s/^\([0-9]\{1,\}\):[[:space:]]*\([a-z0-9]\{1,\}\)[[:space:]]*'\(.*\)'[[:space:]]*$/\1 \2 \3/p"; }
nslots() { local n; n="$(cryptsetup luksDump "$DEV" 2>/dev/null | grep -cE '^[[:space:]]+[0-9]+: luks2')"
  [[ "${n:-0}" == 0 ]] && n="$(cryptsetup luksDump "$DEV" 2>/dev/null | grep -cE '^Key Slot [0-9]+: ENABLED')"
  printf '%s' "${n:-0}"; }

b "state"
printf '  %-18s %s\n' "LUKS device" "$DEV"
printf '  %-18s %s\n' "keyslots" "$(nslots)"
printf '  %-18s %s\n' "lockoutAuthSet" "$LOCKAUTH"
printf '  %-18s %s\n' "ownerAuthSet" "$OWNAUTH"
printf '  %-18s %s\n' "inLockout" "$INLOCK"
printf '  %-18s %ss\n' "lockoutRecovery" "$RCV"
printf '  %-18s %s\n' "phEnable" "$PHEN"
UNPINNED=()
while read -r s pin cfg; do
  [[ -n "${s:-}" ]] || continue
  if [[ "$pin" == tpm2 && "$cfg" != *pcr_ids* ]]; then
    printf '  slot %-13s %s %s  <-- NO pcr_ids\n' "$s" "$pin" "$cfg"; UNPINNED+=("$s")
  else
    printf '  slot %-13s %s %s\n' "$s" "$pin" "$cfg"
  fi
done < <(slots)

(( STATUS_ONLY == 1 )) && exit 0
[[ "$INLOCK" == "1" ]] && die "TPM is in lockout. Power off, unplug, hold power 15s, boot, re-run."

# ---------------------------------------------------------------- phase 2
if [[ "$LOCKAUTH" == "0" ]]; then
  b "PHASE 2 - TPM is cleared, finishing up"

  b "2a. dictionary-attack parameters"
  run tpm2_dictionarylockout -s -n "$MAXTRIES" -t "$INTERVAL" -l "$RECOVERY" \
    || die "could not set DA params (lockoutAuthSet=0, so this should have worked)"
  g "  maxTries=$MAXTRIES interval=${INTERVAL}s recovery=${RECOVERY}s"
  [[ "$RECOVERY" == 0 ]] && g "  recovery=0 -> a power cycle always gets you out of a lockout"

  if [[ -n "$(slots)" ]]; then
    y "  clevis bindings already present - skipping bind. Remove them first if you want a rebind."
  else
    b "2b. bind clevis to PCR $PCR_IDS"
    command -v clevis >/dev/null || die "clevis missing: apt install clevis clevis-luks clevis-tpm2 clevis-initramfs"
    printf 'existing LUKS passphrase for %s: ' "$DEV" >&2
    read -r -s PASS; echo >&2
    [[ -n "$PASS" ]] || die "empty passphrase"
    printf '%s' "$PASS" | cryptsetup open --test-passphrase "$DEV" - >/dev/null 2>&1 \
      || die "that passphrase does not open $DEV"
    g "  passphrase verified"
    # -k - is required: without it clevis reads with an unguarded `read` inside
    # `#!/bin/bash -e`, and a pipe with no trailing newline kills it mid-bind.
    if [[ "$DRY" == 1 ]]; then printf '  DRY: clevis luks bind -y -k - -d %s tpm2 {...pcr_ids:%s}\n' "$DEV" "$PCR_IDS"
    else printf '%s' "$PASS" | clevis luks bind -y -k - -d "$DEV" tpm2 \
           "{\"pcr_bank\":\"$PCR_BANK\",\"pcr_ids\":\"$PCR_IDS\"}" || die "bind failed"; fi
    unset PASS
    g "  bound to PCR $PCR_IDS"

    b "2c. initramfs"
    run update-initramfs -u -k all || die "update-initramfs failed"

    b "2d. verify the TPM actually releases the key"
    NEW="$(slots | awk '$3 ~ /pcr_ids/ {print $1; exit}')"
    if [[ -n "$NEW" ]] && { [[ "$DRY" == 1 ]] || clevis luks pass -d "$DEV" -s "$NEW" >/dev/null 2>&1; }; then
      g "  slot $NEW unseals against the current PCR $PCR_IDS state"
    else
      die "the new binding did not unseal. Your passphrase still works - do not reboot blind."
    fi
  fi

  b "DONE"
  g "lockoutAuth empty, lockoutRecovery=${RECOVERY}s, clevis sealed to PCR $PCR_IDS."
  y "Reboot once at the machine to confirm auto-unlock. PCR 7 is the Secure Boot state:"
  y "changing Secure Boot or enrolling keys will stop it unsealing, by design. Keep your passphrase."
  exit 0
fi

# ---------------------------------------------------------------- phase 1
b "PHASE 1 - clear the TPM"
cat <<MSG

lockoutAuthSet=1 and the password is unknown, so TPM2_DictionaryAttackParameters is
refused and lockoutRecovery stays at ${RCV}s. The only reset is TPM2_Clear.

This is IRREVERSIBLE. It regenerates the storage and endorsement seeds. Every key
sealed to this TPM is destroyed - here that means the clevis binding(s) on $DEV,
which is why the passphrase check below is not optional.

On Intel PTT the firmware does NOT show a confirmation screen: the next boot wipes
the TPM with no further chance to stop.
MSG

b "1a. can you open $DEV without the TPM?"
printf 'existing LUKS passphrase for %s: ' "$DEV" >&2
read -r -s PASS1; echo >&2
[[ -n "$PASS1" ]] || die "empty passphrase - refusing to clear a TPM you cannot recover from"
printf '%s' "$PASS1" | cryptsetup open --test-passphrase "$DEV" - >/dev/null 2>&1 \
  || die "that passphrase does not open $DEV. Refusing to go further - you would not get back in."
unset PASS1
g "  passphrase verified - you can boot without the TPM"

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

b "1d. remove clevis bindings"
# They cannot survive the clear, and leaving them makes boot attempt a doomed unseal
# before falling back to the passphrase prompt.
REM=$(( $(nslots) - $(slots | wc -l) ))
(( REM >= 1 )) || die "that would leave 0 keyslots on $DEV"
while read -r s pin cfg; do
  [[ -n "${s:-}" ]] || continue
  printf '  unbinding slot %s (%s)\n' "$s" "$pin"
  run clevis luks unbind -d "$DEV" -s "$s" -f || y "  slot $s failed"
done < <(slots)
run update-initramfs -u -k all || y "  update-initramfs failed - not fatal here"

b "1e. queue the clear"
run tee "$PPI/request" <<<"$OP" >/dev/null || die "write to $PPI/request refused - PPI disabled in BIOS setup?"
g "  opcode $OP queued"

b "REBOOT NOW - at the machine, with a keyboard"
cat <<MSG

  sudo reboot

The TPM is wiped during that boot. It will then ask for your LUKS passphrase, which
is expected: auto-unlock is gone until you run phase 2.

To back out instead, before rebooting:
  echo 0 | sudo tee $PPI/request

After the reboot, run this same script again to finish:
  sudo $0
MSG
