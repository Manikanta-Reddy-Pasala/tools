#!/usr/bin/env bash
# DESTRUCTIVE (on the next boot). Request a TPM clear through the TCG Physical
# Presence Interface.
#
# This is the answer to "my BIOS has no Clear TPM item". The OS does not clear the
# TPM itself - it parks a request in firmware-owned NV, and on the next boot the
# firmware displays its own confirmation screen and performs TPM2_Clear before the
# platform hierarchy is handed over. It needs no lockout password and it works while
# inLockout=1, because the firmware acts as the platform, not as an authorised user.
#
# Ubuntu 22.04 exposes it at /sys/class/tpm/tpm0/ppi/.
set -euo pipefail
HERE="$(dirname "$(readlink -f "$0")")"
source "$HERE/lib/common.sh"

PPI=/sys/class/tpm/tpm0/ppi
FORCE=0
OP="${OP:-}"
for a in "$@"; do
  case "$a" in
    --force|-f) FORCE=1 ;;
    --cancel)   OP=0 ;;
    -h|--help)  sed -n '2,14p' "$0"; echo; echo "usage: sudo ./10-ppi-clear.sh [--force] [--cancel]"; exit 0 ;;
  esac
done

hdr "PPI availability"
[[ -d "$PPI" ]] || die "no $PPI - kernel has no PPI for this TPM. Nothing here applies; use bios-nuc15-pro.md."
[[ -r "$PPI/version" ]] && info "PPI version       : $(cat "$PPI/version")"
if [[ -r "$PPI/request" ]]; then
  PEND="$(cat "$PPI/request")"
  info "pending request   : $PEND"
  # Firmware that has nothing queued reports whatever it likes here - 0, 255, or
  # stale junk that changes between reads. Only a real TCG opcode means anything.
  if [[ "$PEND" =~ ^[0-9]+$ ]] && (( PEND >= 1 && PEND <= 40 )); then
    warn "PPI opcode $PEND is already queued and will run on the next boot."
    warn "Withdraw it with: sudo $0 --cancel"
  fi
fi
[[ -r "$PPI/response" ]] && info "last response     : $(cat "$PPI/response")"
if [[ -r "$PPI/transition_action" ]]; then
  info "transition action : $(cat "$PPI/transition_action")"
fi

hdr "operations this firmware allows"
OPSFILE=""
for f in tcg_operations vs_operations; do
  [[ -r "$PPI/$f" ]] || continue
  echo "  --- $f ---"
  # only the clear-related opcodes matter here; the full list is 30+ lines of noise
  grep -E '^[[:space:]]*(5|14|21|22)[[:space:]]' "$PPI/$f" | sed 's/^/      /' \
    || echo "      (no clear opcodes listed here)"
  [[ -z "$OPSFILE" ]] && OPSFILE="$PPI/$f"
done
[[ -n "$OPSFILE" ]] || warn "firmware published no operation list; the request may still work"

# TCG PPI opcodes that clear a TPM 2.0. 5 is the canonical one; 14/21/22 are the
# TPM 1.2-era combined forms that most firmware still implements for 2.0.
pick_op() {
  local o st
  for o in 5 22 21 14; do
    if [[ -z "$OPSFILE" ]]; then echo "$o"; return; fi
    st="$(ppi_op_status "$o" < "$OPSFILE")"
    [[ -n "$st" ]] || continue
    if ppi_op_allowed "$st"; then echo "$o"; return; fi
  done
  echo ""
}
[[ -n "$OP" ]] || OP="$(pick_op)"

if [[ "$OP" == "0" ]]; then
  need_root "$@"
  echo 0 > "$PPI/request"
  ok "pending PPI request cancelled"
  exit 0
fi
[[ -n "$OP" ]] || die "firmware exposes no usable clear operation. Fall back to bios-nuc15-pro.md (PTT off/on)."

hdr "what this will do"
ST=""
[[ -n "$OPSFILE" ]] && ST="$(ppi_op_status "$OP" < "$OPSFILE")"
info "opcode $OP -> $PPI/request"
info "status $ST: $(ppi_status_text "$ST")"

cat <<'MSG'

  TPM2_Clear runs on the next boot: new SRK and endorsement seed, every hierarchy
  auth back to empty - including the lockout password nobody set on purpose - and
  every key sealed to this TPM gone for good.
MSG

if [[ "$ST" == "3" ]]; then
  cat <<'MSG'
  Firmware will put up its own confirmation - typically a full-screen "A
  configuration change was requested to clear the TPM" page - and it needs a keypress
  AT THE MACHINE. That cannot be given over SSH; that is the point of physical
  presence. Use a directly attached keyboard, since some firmware ignores
  USB-over-KVM at that stage. Declining is safe and cancels the request.
MSG
elif [[ "$ST" == "4" ]]; then
  err "This firmware reports 'User not required' for opcode $OP."
  cat <<'MSG'
  There will be NO confirmation screen. The next boot wipes the TPM with no further
  chance to back out. Once you reboot, the only thing standing between you and a
  destroyed key is this prompt right here.
  Change your mind before rebooting with:  sudo ./10-ppi-clear.sh --cancel
MSG
fi

if (( FORCE == 0 )); then
  hdr "safety check"
  "$HERE/01-preflight-safety.sh" || die "preflight found risks - resolve them or re-run with --force"
fi

need_root "$@"
confirm_typed "CLEAR MY TPM ON NEXT BOOT"

echo "$OP" > "$PPI/request" 2>/dev/null || die "write to $PPI/request failed (rc=$?). Firmware may have PPI disabled in setup."
sleep 1
NOW="$(cat "$PPI/request" 2>/dev/null || echo '?')"
if [[ "$NOW" == "$OP" ]]; then
  ok "request $OP queued"
else
  warn "request reads back as '$NOW' rather than '$OP' - firmware may have rejected or remapped it"
fi

cat <<MSG

Next:
  1. sudo reboot        (a full power cycle is fine too)
  2. Accept the firmware's TPM-clear prompt at the machine
  3. Back in Linux:
       sudo $HERE/00-status.sh                          # expect all *AuthSet = 0
       sudo RECOVERY=0 $HERE/05-set-lockout-params.sh   # so this cannot recur
       sudo $HERE/09-clevis.sh bind && sudo $HERE/09-clevis.sh verify

If the prompt never appeared, read $PPI/response after the reboot - it carries the
firmware's error code - and fall back to bios-nuc15-pro.md.
Cancel before rebooting with: sudo $0 --cancel
MSG
