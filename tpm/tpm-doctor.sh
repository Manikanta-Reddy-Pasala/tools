#!/usr/bin/env bash
# Guided recovery. Reads the TPM, then tells you exactly which script to run next.
# Never destroys anything on its own.
set -euo pipefail
HERE="$(dirname "$(readlink -f "$0")")"
source "$HERE/lib/common.sh"

setup_tpm_env
load_varcap

IN="$(prop inLockout)"
LA="$(prop lockoutAuthSet)"
DC="$(prop disableClear)"
PH="$(prop phEnable)"
RCV="$(prop TPM2_PT_LOCKOUT_RECOVERY)"

hdr "diagnosis"
printf '    inLockout      = %s\n' "${IN:-?}"
printf '    lockoutAuthSet = %s\n' "${LA:-?}"
printf '    disableClear   = %s\n' "${DC:-?}"
printf '    phEnable       = %s\n' "${PH:-?}"
printf '    lockoutRecovery= %s\n' "$(human_secs "${RCV:-0}")"

hdr "recommended path"

if [[ "$IN" == "0" && "$LA" == "0" ]]; then
  ok "TPM is healthy and unowned. Nothing to recover."
  echo "    Harden it:  sudo RECOVERY=0 $HERE/05-set-lockout-params.sh"
  exit 0
fi

if [[ "$IN" == "0" && "$LA" == "1" ]]; then
  warn "Not locked, but a lockout password is set."
  OA="$(prop ownerAuthSet)"; EA="$(prop endorsementAuthSet)"
  if [[ "$OA" == "0" && "$EA" == "0" ]]; then
    info "owner and endorsement auth are EMPTY - only the lockout hierarchy is owned."
    info "No Linux disk-encryption tool does that. Windows does, on first boot, and it"
    info "keeps a copy of the password. Recover it instead of wiping the TPM:"
    info "  sudo $HERE/08-recover-windows-auth.sh"
  fi
  cat <<MSG

    Know the password?
      sudo $HERE/05-set-lockout-params.sh 'yourpassword'
    Recover it from a Windows install on this machine:
      sudo $HERE/08-recover-windows-auth.sh
    Truly lost?  Only a TPM clear resets it to empty:
      sudo $HERE/01-preflight-safety.sh     # check what you would destroy
      sudo $HERE/04-clear-tpm.sh

    Note: lockoutAuth gates ONLY TPM2_DictionaryAttackParameters and LockReset.
    Sealing, unsealing, clevis and systemd-cryptenroll use the OWNER hierarchy and
    keep working. If you do not need to tune DA params, living with it costs nothing.
MSG
  exit 0
fi

# inLockout == 1 from here
err "TPM is in lockout. Auth-gated commands will return 0x921."
echo
echo "  STEP 1 - free, non-destructive, try this first:"
if [[ "${RCV:-0}" == "0" ]]; then
  echo "      lockoutRecovery = 0, so a full power cycle clears it:"
  echo "        sudo poweroff; unplug; hold power button 15s; boot"
else
  echo "      stay idle for $(human_secs "$RCV") - watch it with:"
  echo "        sudo $HERE/02-wait-out-lockout.sh"
  echo "      (also try a full power cycle first: some firmware resets DA state on S5)"
fi
echo
echo "  STEP 2 - if you DO have the lockout password:"
echo "        sudo $HERE/03-clear-lockout.sh 'yourpassword'"
echo
echo "  STEP 3 - lost the password, need it back now (DESTRUCTIVE):"
echo "        sudo $HERE/01-preflight-safety.sh"
if [[ "$DC" == "1" ]]; then
  echo "      disableClear=1 -> lockout-hierarchy clear is blocked."
fi
if [[ "$PH" == "0" ]]; then
  echo "      phEnable=0 -> 'tpm2_clear -c p' will fail with 0x184."
  echo "      No OS-side clear is possible. Ask the FIRMWARE to do it instead:"
  echo "        sudo $HERE/10-ppi-clear.sh    # TCG Physical Presence request, works with no BIOS menu item"
  echo "      Or, if PPI is unavailable: $HERE/bios-nuc15-pro.md (toggle Intel PTT off -> boot -> on)"
else
  echo "      phEnable=1 -> the platform hierarchy is still open, this should work:"
  echo "        sudo $HERE/04-clear-tpm.sh"
fi
echo
echo "  Background: $HERE/docs/lockout-explained.md"
