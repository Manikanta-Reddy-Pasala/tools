#!/usr/bin/env bash
# Set dictionary-attack parameters (this is the TPM2_DictionaryAttackParameters call
# that gets refused while inLockout=1).
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

setup_tpm_env

MAXTRIES="${MAXTRIES:-32}"      # failures allowed before lockout
INTERVAL="${INTERVAL:-7200}"    # seconds to forget one failure (2h)
RECOVERY="${RECOVERY:-0}"       # seconds locked after lockoutAuth failure. 0 = clears on power cycle
AUTH="${LOCKOUT_AUTH:-${1:-}}"

usage() {
  cat <<'MSG'
usage: sudo [MAXTRIES=32] [INTERVAL=7200] [RECOVERY=0] ./05-set-lockout-params.sh [lockout-password]

  MAXTRIES  failed auths tolerated before lockout        (default 32)
  INTERVAL  seconds before the counter drops by one      (default 7200 = 2h)
  RECOVERY  seconds locked after a lockoutAuth failure   (default 0)

RECOVERY=0 is the recommended value for a workstation: it means a full power
cycle always gets you out, so you can never brick yourself again.
MSG
}
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }

need_root "$@"
load_varcap
if [[ "$(prop inLockout)" == "1" ]]; then
  die "inLockout=1 - this command WILL be refused (0x921). Clear the lockout first: ./02-wait-out-lockout.sh"
fi

mapfile -t A < <(auth_args -p "$AUTH")
info "maxTries=$MAXTRIES  interval=$(human_secs "$INTERVAL")  recovery=$(human_secs "$RECOVERY")"
run_tpm tpm2_dictionarylockout -s -n "$MAXTRIES" -t "$INTERVAL" -l "$RECOVERY" ${A[@]+"${A[@]}"} \
  && ok "parameters set" || die "failed"

TPM_VARCAP=""; load_varcap
printf '    maxAuthFail     = %s\n' "$(prop TPM2_PT_MAX_AUTH_FAIL)"
printf '    lockoutInterval = %s\n' "$(human_secs "$(prop TPM2_PT_LOCKOUT_INTERVAL)")"
printf '    lockoutRecovery = %s\n' "$(human_secs "$(prop TPM2_PT_LOCKOUT_RECOVERY)")"
