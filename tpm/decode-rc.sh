#!/usr/bin/env bash
# Translate a TPM2 return code. usage: ./decode-rc.sh 0x921
set -euo pipefail
RC="${1:-}"
[[ -n "$RC" ]] || { echo "usage: $0 0x921"; exit 1; }
if command -v tpm2_rc_decode >/dev/null 2>&1; then
  tpm2_rc_decode "$RC" || true
  echo
fi
case "${RC,,}" in
  0x921|*921) cat <<'M'
TPM_RC_LOCKOUT (0x921)
  The TPM is in dictionary-attack lockout. Every command that needs
  lockout-hierarchy auth is refused - including tpm2_dictionarylockout,
  which is the command that would clear it. Chicken-and-egg by design.
  Exits: wait lockoutRecovery / power cycle if lockoutRecovery==0 / clear TPM.
M
;;
  0x98e|*98e|0x9a2|*9a2) cat <<'M'
TPM_RC_AUTH_FAIL (0x98e / 0x9a2 with session offset)
  Wrong password. Each occurrence increments lockoutCounter. Stop guessing -
  you are walking yourself into 0x921.
M
;;
  0x18b|*18b) cat <<'M'
TPM_RC_BAD_AUTH (0x18b)
  Auth rejected but the DA counter was NOT incremented.
M
;;
  0x184|*184) cat <<'M'
TPM_RC_HIERARCHY (0x184)
  The hierarchy is disabled. Usually means phEnable=0: firmware dropped the
  platform hierarchy before handing off to the OS, so 'tpm2_clear -c p' is
  dead on this boot. BIOS is the only route left.
M
;;
  0x2c4|*2c4) echo "TPM_RC_VALUE - a parameter is out of range" ;;
  0x9a5|*9a5) echo "TPM_RC_BAD_TAG / session problem - check the -p auth syntax (str:, hex:, file:)" ;;
  *) echo "no local entry. Try: tpm2_rc_decode $RC" ;;
esac
