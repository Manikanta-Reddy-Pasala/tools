#!/usr/bin/env bash
# DESTRUCTIVE. TPM2_Clear: regenerates the storage + endorsement seeds, drops all
# hierarchy auths (incl. the lockout password you lost), wipes persistent objects
# and non-platform NV indices.
#
# Everything sealed to this TPM becomes permanently unrecoverable.
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

setup_tpm_env
need_root "$@"

FORCE=0
AUTH="${LOCKOUT_AUTH:-}"
for a in "$@"; do
  case "$a" in
    --force|-f) FORCE=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) AUTH="$a" ;;
  esac
done

load_varcap
hdr "state"
printf '    inLockout    = %s\n' "$(prop inLockout)"
printf '    disableClear = %s\n' "$(prop disableClear)"
printf '    phEnable     = %s\n' "$(prop phEnable)"

if [[ "$(prop disableClear)" == "1" ]]; then
  warn "disableClear=1 -> TPM2_Clear via the LOCKOUT hierarchy is blocked. Only platform hierarchy or BIOS can clear."
fi

if (( FORCE == 0 )); then
  hdr "safety check"
  if ! "$(dirname "$(readlink -f "$0")")/01-preflight-safety.sh"; then
    err "preflight found risks. Re-run with --force only if you have verified your recovery path."
    exit 2
  fi
fi

cat <<'MSG'

--------------------------------------------------------------------------
 WARNING - THIS IS IRREVERSIBLE

 TPM2_Clear regenerates the Storage Root Key and the Endorsement seed.
 Every secret sealed to this TPM is destroyed permanently:
   - LUKS keys enrolled with systemd-cryptenroll --tpm2-device or Clevis
     (an encrypted disk that auto-unlocks will stop unlocking - you will
      need the LUKS passphrase to boot, and without it the data is gone)
   - TPM-backed SSH/GPG keys, tpm2-pkcs11 tokens
   - Any application key with a persistent handle
   - All hierarchy passwords, including the lockout password
--------------------------------------------------------------------------
MSG

confirm_typed "CLEAR MY TPM AND DESTROY ITS KEYS"

hdr "attempt 1/2: lockout hierarchy"
mapfile -t P < <(auth_args -P "$AUTH")
if run_tpm tpm2_clear -c l ${P[@]+"${P[@]}"}; then
  ok "cleared via lockout hierarchy"
else
  warn "lockout hierarchy failed (expected when you do not have the password, or inLockout=1)"

  hdr "attempt 2/2: platform hierarchy"
  info "platformAuth is normally empty until firmware disables the hierarchy at OS handover"
  if run_tpm tpm2_clear -c p; then
    ok "cleared via platform hierarchy"
  else
    err "both hierarchies refused."
    cat <<'MSG'

Nothing in the OS can clear this TPM now. Remaining options, in order:

  1. Power cycle and retry immediately (some firmware leaves the platform
     hierarchy enabled early; a systemd unit ordered before other TPM users
     can win the race - see docs/early-clear.md)
  2. BIOS: toggle Intel PTT off -> boot -> on. See bios-nuc15-pro.md
  3. BIOS security jumper -> Maintenance Mode. See bios-nuc15-pro.md
MSG
    exit 1
  fi
fi

TPM_VARCAP=""; load_varcap
hdr "post-clear state"
for f in ownerAuthSet endorsementAuthSet lockoutAuthSet inLockout; do
  printf '    %-20s = %s\n' "$f" "$(prop "$f")"
done
ok "all hierarchy auths are now EMPTY - you own the TPM again"
info "next: sudo RECOVERY=0 ./05-set-lockout-params.sh    # so this can never brick you again"
info "then: ./07-reenroll-luks.sh                          # if you had TPM disk unlock"
