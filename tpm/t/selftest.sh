#!/usr/bin/env bash
# Offline test of the parsing helpers. Needs NO TPM - run it anywhere with bash 4+.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../lib/common.sh"

PASS=0; FAIL=0
is() { # is <label> <got> <want>
  if [[ "$2" == "$3" ]]; then printf '  ok   %-42s = %s\n' "$1" "$2"; PASS=$((PASS+1))
  else printf '  FAIL %-42s got=%q want=%q\n' "$1" "$2" "$3"; FAIL=$((FAIL+1)); fi
}
like() { # like <label> <got> <substring>
  if [[ "$2" == *"$3"* ]]; then printf '  ok   %-42s ~ %s\n' "$1" "$3"; PASS=$((PASS+1))
  else printf '  FAIL %-42s got=%q want~=%q\n' "$1" "$2" "$3"; FAIL=$((FAIL+1)); fi
}

hdr "fixture: locked Intel PTT (phEnable=0, recovery=24h)"
TPM_VARCAP="$(cat "$HERE/fixtures/locked-intel-ptt.txt")"
is "prop inLockout"              "$(prop inLockout)"                    "1"
is "prop lockoutAuthSet"         "$(prop lockoutAuthSet)"               "1"
is "prop disableClear"           "$(prop disableClear)"                 "0"
is "prop phEnable"               "$(prop phEnable)"                     "0"
is "prop LOCKOUT_COUNTER hex->dec" "$(prop TPM2_PT_LOCKOUT_COUNTER)"    "32"
is "prop MAX_AUTH_FAIL hex->dec" "$(prop TPM2_PT_MAX_AUTH_FAIL)"        "32"
is "prop LOCKOUT_INTERVAL 0x1C20" "$(prop TPM2_PT_LOCKOUT_INTERVAL)"    "7200"
is "prop LOCKOUT_RECOVERY 0x15180" "$(prop TPM2_PT_LOCKOUT_RECOVERY)"   "86400"
is "prop of absent key is empty" "$(prop TPM2_PT_NOT_A_REAL_KEY)"       ""

hdr "fixture: clean TPM, recovery 0"
TPM_VARCAP="$(cat "$HERE/fixtures/clean-recovery0.txt")"
is "prop inLockout"              "$(prop inLockout)"                    "0"
is "prop lockoutAuthSet"         "$(prop lockoutAuthSet)"               "0"
is "prop phEnable"               "$(prop phEnable)"                     "1"
is "prop LOCKOUT_RECOVERY"       "$(prop TPM2_PT_LOCKOUT_RECOVERY)"     "0"

hdr "human_secs"
like "recovery 0 explains power cycle" "$(human_secs 0)"    "power cycle"
like "86400 -> 1d"                     "$(human_secs 86400)" "1d"
like "7200 -> 2h"                      "$(human_secs 7200)"  "2h"
like "90 -> 1m"                        "$(human_secs 90)"    "1m"
like "empty arg is treated as 0"       "$(human_secs "")"    "power cycle"

hdr "explain_rc against real tpm2-tools stderr"
like "0x921" "$(explain_rc 'ERROR: Esys_DictionaryAttackLockReset(0x921) - tpm:warn(2.0): TPM is in DA lockout mode')" "lockout"
like "0x9a2" "$(explain_rc 'ERROR: Esys_Clear(0x9a2) - tpm:session(1):authorization failure')"                          "wrong password"
like "0x184" "$(explain_rc 'ERROR: Esys_Clear(0x184) - tpm:handle(1):hierarchy is not enabled')"                        "hierarchy is disabled"
is   "unknown code -> empty" "$(explain_rc 'ERROR: something else')" ""

hdr "auth_args"
is "empty auth emits nothing"   "$(auth_args -p '' | tr '\n' '|')"        ""
is "bare password gets str:"    "$(auth_args -p 'hunter2' | tr '\n' '|')" "-p|str:hunter2|"
is "prefixed auth passes through" "$(auth_args -p 'hex:0a0b' | tr '\n' '|')" "-p|hex:0a0b|"
is "file: auth passes through"  "$(auth_args -P 'file:/tmp/a' | tr '\n' '|')" "-P|file:/tmp/a|"

hdr "empty-array expansion is safe under set -u"
mapfile -t A < <(auth_args -p "")
is "expands to zero args" "$(printf '%s' "${A[@]+"${A[@]}"}")" ""

hdr "result"
printf '  %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 )) || exit 1
ok "selftest green"
