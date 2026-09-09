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

hdr "clevis luks list parser"
CL="$(parse_clevis_list < "$HERE/fixtures/clevis-luks-list.txt")"
is "three bindings parsed"      "$(wc -l <<<"$CL" | tr -d ' ')"                    "3"
is "slot 1 row"                 "$(sed -n 1p <<<"$CL" | cut -d' ' -f1-2)"          "1 tpm2"
is "slot 3 pin is tang"         "$(sed -n 3p <<<"$CL" | cut -d' ' -f2)"            "tang"
is "config json survives quotes" "$(sed -n 2p <<<"$CL" | cut -d' ' -f3-)"          '{"hash":"sha256","key":"ecc","pcr_bank":"sha256","pcr_ids":"7"}'
is "no trailing quote in cfg"   "$(sed -n 1p <<<"$CL" | grep -c "'" || true)"      "0"
is "junk lines ignored"         "$(printf 'not a binding\nSlot 9 blah\n' | parse_clevis_list | wc -l | tr -d ' ')" "0"

hdr "pcr policy detection - the unsafe-bind check"
clevis_cfg_has_pcrs '{"pcr_bank":"sha256"}'              && R=yes || R=no
is "pcr_bank alone is NOT pcr-sealed" "$R" "no"
clevis_cfg_has_pcrs '{"pcr_bank":"sha256","pcr_ids":"7"}' && R=yes || R=no
is "pcr_ids present is pcr-sealed"    "$R" "yes"
clevis_cfg_has_pcrs '{"pcr_ids":"0,2,4,7"}'               && R=yes || R=no
is "multiple pcr_ids"                 "$R" "yes"

hdr "PPI operation-list parser (real ASUS/Intel NUC tcg_operations)"
PPIF="$HERE/fixtures/ppi-tcg-operations.txt"
is "op 5 status"                "$(ppi_op_status 5  < "$PPIF")" "4"
is "op 18 status"               "$(ppi_op_status 18 < "$PPIF")" "3"
is "op 12 status (unimplemented)" "$(ppi_op_status 12 < "$PPIF")" "0"
is "absent op -> empty"         "$(ppi_op_status 999 < "$PPIF")" ""
is "op 2 is not matched by op 22 prefix" "$(ppi_op_status 2 < "$PPIF")" "4"
ppi_op_allowed 4 && R=yes || R=no; is "status 4 allowed" "$R" "yes"
ppi_op_allowed 3 && R=yes || R=no; is "status 3 allowed" "$R" "yes"
ppi_op_allowed 0 && R=yes || R=no; is "status 0 refused" "$R" "no"
ppi_op_allowed 2 && R=yes || R=no; is "status 2 (blocked) refused" "$R" "no"
like "status 4 text warns of no prompt" "$(ppi_status_text 4)" "will NOT prompt"
like "status 3 text promises a prompt"  "$(ppi_status_text 3)" "WILL prompt"

hdr "clevis subcommand detection (the jammy false-negative)"
SHIM="$(mktemp -d)"
cat > "$SHIM/clevis" <<'SH'
#!/usr/bin/env bash
# Mimics Ubuntu 22.04 clevis 18: getopts ":d:s:" means --help is not a flag, so it
# falls into usage() and exits 1. --summary is handled and exits 0.
[[ "$1" == luks && "$2" == pass && "$3" == "--summary" ]] && { echo "Returns the LUKS passphrase"; exit 0; }
[[ "$1" == luks && "$2" == pass ]] && { echo "Usage: clevis luks pass -d DEV -s SLT" >&2; exit 1; }
[[ "$1" == luks && "$2" == nosuch ]] && { echo "unknown" >&2; exit 1; }
exit 1
SH
chmod +x "$SHIM/clevis"
OLDPATH="$PATH"; PATH="$SHIM:$PATH"
is "--help would have said exit 1"   "$(clevis luks pass --help >/dev/null 2>&1; echo $?)" "1"
has_clevis_subcmd pass   && R=yes || R=no; is "pass detected via --summary" "$R" "yes"
has_clevis_subcmd nosuch && R=yes || R=no; is "absent subcommand still refused" "$R" "no"
PATH="$OLDPATH"; rm -rf "$SHIM"

hdr "result"
printf '  %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 )) || exit 1
ok "selftest green"
