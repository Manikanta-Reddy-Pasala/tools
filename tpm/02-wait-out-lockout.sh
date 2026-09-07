#!/usr/bin/env bash
# Non-destructive. Poll until lockout self-clears. Try this BEFORE clearing the TPM.
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

setup_tpm_env
INTERVAL="${POLL_SECS:-60}"

load_varcap
RCV="$(prop TPM2_PT_LOCKOUT_RECOVERY)"
IVL="$(prop TPM2_PT_LOCKOUT_INTERVAL)"

hdr "lockout recovery watch"
info "lockoutRecovery = $(human_secs "${RCV:-0}")"
info "lockoutInterval = $(human_secs "${IVL:-0}")"

if [[ "${RCV:-0}" == "0" ]]; then
  cat <<'MSG'

lockoutRecovery is 0 -> lockout only clears on a TPM reset.
A reboot is NOT always enough (S5 vs warm reset). Do a real power cycle:

  1. sudo poweroff
  2. unplug the power brick
  3. hold the power button 15 seconds (drains standby rails)
  4. plug back in, boot

Then re-run ./00-status.sh
MSG
  exit 0
fi

info "polling every ${INTERVAL}s. Keep the machine IDLE - any failed auth restarts the timer."
info "Ctrl-C to stop."
START=$(date +%s)
while :; do
  TPM_VARCAP=""; load_varcap
  IN="$(prop inLockout)"; CNT="$(prop TPM2_PT_LOCKOUT_COUNTER)"
  NOW=$(date +%s); EL=$(( NOW - START ))
  printf '\r[%s] inLockout=%s lockoutCounter=%s elapsed=%s     ' \
    "$(date +%H:%M:%S)" "$IN" "${CNT:-?}" "$(human_secs $EL)"
  if [[ "$IN" == "0" ]]; then
    echo; ok "lockout cleared after $(human_secs $EL)"
    info "next: ./05-set-lockout-params.sh  (needs lockout auth; empty auth works if TPM was cleared)"
    exit 0
  fi
  sleep "$INTERVAL"
done
