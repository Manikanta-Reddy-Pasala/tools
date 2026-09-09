#!/usr/bin/env bash
# DESTRUCTIVE. TPM2_Clear: regenerates the storage + endorsement seeds, drops all
# hierarchy auths (incl. the lockout password you lost), wipes persistent objects
# and non-platform NV indices.
#
# Everything sealed to this TPM becomes permanently unrecoverable.
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

# Parse --help before touching the TPM: asking what a script does must not require
# tpm2-tools, a TPM, or root.
for a in "$@"; do
  case "$a" in -h|--help) sed -n '2,10p' "$0"; exit 0 ;; esac
done

setup_tpm_env

FORCE=0
AUTH="${LOCKOUT_AUTH:-}"
for a in "$@"; do
  case "$a" in
    --force|-f) FORCE=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) AUTH="$a" ;;
  esac
done
need_root "$@"

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

hdr "clevis bindings"
STRANDED=0
if have clevis; then
  while read -r dev; do
    [[ -n "$dev" ]] || continue
    while read -r slot pin cfg; do
      [[ -n "${slot:-}" ]] || continue
      STRANDED=1
      err "$dev slot $slot ($pin) will be DEAD after this clear"
    done < <(clevis_slots "$dev")
  done < <(luks_devices)
fi
if (( STRANDED == 1 )); then
  cat <<'MSG'

  A cleared TPM cannot decrypt a Clevis JWE, and the keyslot stays in the header.
  The initramfs will still try it, fail, and drop you at a passphrase prompt.
  Do these two things first:

    sudo ./09-clevis.sh rescue     # read the passphrase back out of the TPM
    sudo ./09-clevis.sh unbind     # remove the slots that are about to die

  Then clear, then: sudo ./09-clevis.sh bind && sudo ./09-clevis.sh verify
MSG
  (( FORCE == 0 )) && die "refusing while live Clevis bindings exist. Re-run with --force to override."
fi

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

  1. Ask the FIRMWARE to clear it on the next boot. Needs no password, works
     while inLockout=1, and works on boards with no "Clear TPM" menu item
     (ASUS NUC 15 Pro / Intel PTT):
       sudo ./10-ppi-clear.sh
  2. Power cycle and retry immediately (some firmware leaves the platform
     hierarchy enabled early; a systemd unit ordered before other TPM users
     can win the race - see docs/early-clear.md)
  3. BIOS: toggle Intel PTT off -> boot -> on. See bios-nuc15-pro.md
  4. BIOS security jumper -> Maintenance Mode. Same doc.

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
info "then: ./07-reenroll-luks.sh                          # systemd-cryptenroll disk unlock"
info "  or: ./09-clevis.sh bind && ./09-clevis.sh verify        # clevis disk unlock"
