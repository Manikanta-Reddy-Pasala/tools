#!/usr/bin/env bash
# Reset the lockout counter. Needs lockout-hierarchy auth (empty auth if never set / after a clear).
# Non-destructive - does NOT wipe keys.
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

setup_tpm_env
AUTH="${LOCKOUT_AUTH:-}"

usage() {
  cat <<'MSG'
usage: sudo ./03-clear-lockout.sh [lockout-password]
       sudo LOCKOUT_AUTH=str:mypass ./03-clear-lockout.sh
       sudo ./03-clear-lockout.sh                 # empty auth
MSG
}
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }
[[ -n "${1:-}" ]] && AUTH="$1"

need_root "$@"
load_varcap

if [[ "$(prop inLockout)" == "1" && "$(prop TPM2_PT_LOCKOUT_RECOVERY)" != "0" ]]; then
  warn "TPM reports inLockout=1. A wrong password here restarts the recovery timer."
  warn "If unsure of the password, stop and run ./02-wait-out-lockout.sh instead."
fi

mapfile -t A < <(auth_args -p "$AUTH")
info "running: tpm2_dictionarylockout -c ${A[*]:-<empty auth>}"
if run_tpm tpm2_dictionarylockout -c ${A[@]+"${A[@]}"}; then
  ok "lockout counter cleared"
  TPM_VARCAP=""; load_varcap
  info "inLockout is now: $(prop inLockout)"
else
  err "failed"
  cat <<'MSG'

No lockout password and still locked? Only two ways out:
  1. ./02-wait-out-lockout.sh   - wait / power cycle    (keeps keys)
  2. ./04-clear-tpm.sh          - wipe the TPM          (DESTROYS keys)
  3. BIOS: toggle Intel PTT off/on - see bios-nuc15-pro.md (also DESTROYS keys)
MSG
  exit 1
fi
