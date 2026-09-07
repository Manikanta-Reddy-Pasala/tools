#!/usr/bin/env bash
# Set (or clear) the owner / endorsement / lockout hierarchy passwords.
# THIS is the command that got you locked out. Read the note at the bottom.
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

setup_tpm_env
need_root "$@"

HIER="${1:-}"; NEW="${2:-}"; OLD="${3:-${OLD_AUTH:-}}"
usage() {
  cat <<'MSG'
usage: sudo ./06-set-hierarchy-auth.sh <owner|endorsement|lockout> <new-password> [old-password]
       sudo ./06-set-hierarchy-auth.sh lockout ""            # clear it back to empty

Hierarchy letters used by tpm2_changeauth: o = owner, e = endorsement, l = lockout
MSG
}
case "$HIER" in
  owner)       H=o ;;
  endorsement) H=e ;;
  lockout)     H=l ;;
  *) usage; exit 1 ;;
esac
[[ $# -ge 2 ]] || { usage; exit 1; }

mapfile -t P < <(auth_args -p "$OLD")
if [[ -z "$NEW" ]]; then
  info "clearing $HIER auth (setting to empty)"
  run_tpm tpm2_changeauth -c "$H" ${P[@]+"${P[@]}"} || die "failed"
else
  info "setting $HIER auth"
  run_tpm tpm2_changeauth -c "$H" ${P[@]+"${P[@]}"} "$NEW" || die "failed"
fi
ok "done"

cat <<'MSG'

  NOTE - why this bit you:
  A lockout password you cannot reproduce is a one-way door. Wrong guesses
  raise lockoutCounter; past maxAuthFail the TPM refuses ALL lockout-gated
  commands - including the one that resets the lockout. The only exits are
  waiting out lockoutRecovery, a power cycle (if lockoutRecovery == 0), or
  wiping the TPM.

  Store this password in your password manager NOW, or leave it empty and
  rely on physical presence instead.
MSG
