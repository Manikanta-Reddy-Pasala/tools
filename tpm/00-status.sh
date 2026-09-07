#!/usr/bin/env bash
# Read-only. Full picture of TPM lockout state. Start here.
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

setup_tpm_env
load_varcap

hdr "device"
info "TCTI            : $TPM2TOOLS_TCTI"
info "tpm2-tools major: $(tools_major)"
for d in /dev/tpm0 /dev/tpmrm0; do
  [[ -c $d ]] && ok "present: $d" || warn "missing: $d"
done
if [[ -r /sys/class/tpm/tpm0/tpm_version_major ]]; then
  info "TPM spec        : $(cat /sys/class/tpm/tpm0/tpm_version_major).x"
fi
if [[ -r /sys/class/tpm/tpm0/device/description ]]; then
  info "description     : $(cat /sys/class/tpm/tpm0/device/description)"
fi
MANU="$(tpm2_getcap properties-fixed 2>/dev/null | sed -n '/TPM2_PT_MANUFACTURER/,/value/s/.*value:[[:space:]]*"\(.*\)"/\1/p' | head -n1 || true)"
[[ -n "$MANU" ]] && info "manufacturer    : $MANU  ${MANU/INTC/(Intel PTT = firmware TPM)}"

hdr "permanent flags"
for f in ownerAuthSet endorsementAuthSet lockoutAuthSet disableClear inLockout tpmGeneratedEPS; do
  v="$(prop "$f")"
  [[ -z "$v" ]] && continue
  case "$f:$v" in
    inLockout:1)     err  "$f = $v   <-- LOCKED OUT" ;;
    disableClear:1)  err  "$f = $v   <-- tpm2_clear via lockout hierarchy is BLOCKED" ;;
    lockoutAuthSet:1) warn "$f = $v   (a lockout password is set)" ;;
    *) printf '    %-20s = %s\n' "$f" "$v" ;;
  esac
done

hdr "hierarchy enables (startup-clear)"
for f in phEnable shEnable ehEnable phEnableNV orderly; do
  v="$(prop "$f")"; [[ -z "$v" ]] && continue
  if [[ "$f" == phEnable && "$v" == 0 ]]; then
    err "$f = $v   <-- platform hierarchy disabled: 'tpm2_clear -c p' will FAIL"
  else
    printf '    %-20s = %s\n' "$f" "$v"
  fi
done

hdr "dictionary attack parameters"
CNT="$(prop TPM2_PT_LOCKOUT_COUNTER)"
MAXF="$(prop TPM2_PT_MAX_AUTH_FAIL)"
IVL="$(prop TPM2_PT_LOCKOUT_INTERVAL)"
RCV="$(prop TPM2_PT_LOCKOUT_RECOVERY)"
printf '    %-20s = %s\n' "lockoutCounter"  "${CNT:-?}"
printf '    %-20s = %s\n' "maxAuthFail"     "${MAXF:-?}"
printf '    %-20s = %s\n' "lockoutInterval" "$(human_secs "${IVL:-0}")"
printf '    %-20s = %s\n' "lockoutRecovery" "$(human_secs "${RCV:-0}")"

hdr "what is sealed to this TPM (clearing destroys these)"
FOUND=0
if have cryptsetup; then
  while read -r dev; do
    [[ -b "$dev" ]] || continue
    if cryptsetup isLuks "$dev" 2>/dev/null; then
      if cryptsetup luksDump "$dev" 2>/dev/null | grep -qi 'systemd-tpm2'; then
        err "LUKS $dev has a systemd-tpm2 keyslot -> auto-unlock BREAKS if TPM cleared"
        FOUND=1
      fi
      if cryptsetup luksDump "$dev" 2>/dev/null | grep -qi 'clevis'; then
        err "LUKS $dev has a Clevis binding -> auto-unlock BREAKS if TPM cleared"
        FOUND=1
      fi
    fi
  done < <(lsblk -pnro NAME,TYPE 2>/dev/null | awk '$2=="part"||$2=="crypt"{print $1}')
fi
if [[ -d /var/lib/clevis ]] || have clevis; then
  warn "clevis present on system"
fi
if tpm2_getcap handles-persistent 2>/dev/null | grep -q 0x81; then
  err "persistent handles exist (keys stored in TPM):"
  tpm2_getcap handles-persistent | sed 's/^/      /'
  FOUND=1
fi
(( FOUND == 0 )) && ok "no TPM-sealed disk keys or persistent handles detected"

hdr "verdict"
if [[ "$(prop inLockout)" == "1" ]]; then
  err "TPM IS IN LOCKOUT."
  if [[ "${RCV:-0}" == "0" ]]; then
    info "lockoutRecovery = 0  ->  a FULL POWER CYCLE clears it. Run: ./02-wait-out-lockout.sh"
  else
    info "wait up to $(human_secs "$RCV") idle, or clear the TPM. Run: ./02-wait-out-lockout.sh"
  fi
  echo
  info "no lockout password? -> ./04-clear-tpm.sh (DESTRUCTIVE) or BIOS PTT toggle (see bios-nuc15-pro.md)"
else
  ok "not in lockout. You can set params now: ./05-set-lockout-params.sh"
  [[ "$(prop lockoutAuthSet)" == "1" ]] && \
    warn "but lockoutAuthSet=1 and you said you do not have it -> param changes still need that password. Clear the TPM to reset it to empty."
fi
