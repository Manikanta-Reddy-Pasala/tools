#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2015,SC1091  # vars are read by the sourced functions; A && ok || bad is deliberate
# Unit tests for the parsing in ../provision.sh - no TPM, no root, no disk.
# The functions between die() and live_name() are sourced out of the script itself.
#   bash t/provision-test.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../provision.sh"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
sed -n '/^die()/,/^}$/p;/^rp()/p;/^# dm name/,/^}$/p' "$SRC" > "$W/funcs.sh"
sed -n '/^# crypttab entry/,/^}$/p' "$SRC" >> "$W/funcs.sh"
PCR_IDS=7 PCR_BANK=sha256 DEV=/dev/fakeluks CT="$W/crypttab" VC=""
# shellcheck disable=SC1090
source "$W/funcs.sh"
blkid() { [[ "$*" == *"-s UUID"* ]] && printf 'abc-123\n'; }   # stub: $DEV has UUID abc-123
for f in die rp warn num da slots pinned unpinned unseals testpass dobind try2 first_unsealing ct_scan live_name; do
  declare -F "$f" >/dev/null || { printf 'FAIL extraction: %s() was not sourced from provision.sh\n' "$f"; exit 1; }
done

pass=0 fail=0
ok()  { pass=$((pass+1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf 'FAIL %s: got [%s] want [%s]\n' "$1" "$2" "$3"; }
eq()  { [[ "$2" == "$3" ]] && ok "$1" || bad "$1" "$2" "$3"; }

printf 'dm_crypt-0 UUID=abc-123 none luks,discard\n' > "$CT"
ct_scan; eq "plain entry: name"  "$NAME" "dm_crypt-0"; eq "plain entry: no keyscript" "$KS" ""

printf 'dm_crypt-0 UUID=abc-123 none luks,keyscript=/usr/local/sbin/tpm2-getkey' > "$CT"  # no trailing newline
ct_scan; eq "no trailing newline: name" "$NAME" "dm_crypt-0"
eq "no trailing newline: custom keyscript" "$KS" "/usr/local/sbin/tpm2-getkey"
eq "KS_ANY: set for a custom keyscript" "$KS_ANY" "/usr/local/sbin/tpm2-getkey"

printf 'sda3_crypt UUID=abc-123 none luks,discard,keyscript=decrypt_keyctl\n' > "$CT"
ct_scan; eq "stock keyscript (bare name) is not flagged" "$KS" ""
eq "KS_ANY: still set for a stock keyscript (the initrd check keys off this)" "$KS_ANY" "decrypt_keyctl"
printf 'sda3_crypt UUID=abc-123 none luks,keyscript=/lib/cryptsetup/scripts/passdev\n' > "$CT"
ct_scan; eq "stock keyscript (stock path) is not flagged" "$KS" ""

printf '# comment\n\nother UUID=zzz none luks\ndm_crypt-0 UUID=abc-123 none luks\n' > "$CT"
ct_scan; eq "comments and other volumes skipped" "$NAME" "dm_crypt-0"

printf 'dm_crypt-0 UUID=abc-123 none\n' > "$CT"
ct_scan; eq "3-field entry: no options" "$OPTS" ""
eq "KS_ANY: cleared on a keyscript-free re-scan" "$KS_ANY" ""

printf 'dm_crypt-0 PARTUUID=abc-123 none luks\n' > "$CT"
ct_scan; eq "PARTUUID source does not match a UUID" "$NAME" ""

rm -f "$CT"; ct_scan; eq "missing crypttab is not fatal" "$NAME" ""

VC="$(printf 'TPM2_PT_PERMANENT:\n  lockoutAuthSet:   1\n  inLockout:        0\nTPM2_PT_MAX_AUTH_FAIL: 0x20\nTPM2_PT_LOCKOUT_INTERVAL: 0x3C\nTPM2_PT_LOCKOUT_RECOVERY: 0x3C\n')"
eq "num: decimal"            "$(num lockoutAuthSet)" "1"
eq "num: hex -> decimal"     "$(num TPM2_PT_MAX_AUTH_FAIL)" "32"
eq "da: all three"           "$(da)" "32/60/60"
out="$(num TPM2_PT_NOT_THERE 2>&1)"; rc=$?
[[ "$out" == *"cannot read"* ]] && ok "num: missing property says so" || bad "num missing" "$out" "cannot read..."
eq "num: missing property returns non-zero (callers must assign, not inline)" "$rc" "1"
VC2="$VC"; VC="$(printf 'TPM2_PT_MAX_AUTH_FAIL: 0x20\n')"
out="$(da 2>/dev/null)"; rc=$?
eq "da: one property missing -> fails, never a half value like 32//" "$rc/$out" "1/"
VC="$VC2"

clevis() { printf "1: tpm2 '{\"pcr_bank\":\"sha256\",\"pcr_ids\":\"7\"}'\n2: tpm2 '{\"pcr_bank\":\"sha256\"}'\n3: tang '{\"url\":\"x\"}'\n"; }
eq "slots: parses 3"  "$(slots | wc -l | tr -d ' ')" "3"
eq "pinned: slot 1"   "$(pinned)" "1"
eq "unpinned: slot 2" "$(unpinned)" "2"

# the keyslot count that decides the "no passphrase left to fall back on" warning
slotcount() { grep -cE '^[[:space:]]+[0-9]+: (luks2|reencrypt)|^Key Slot [0-9]+: ENABLED'; }
eq "keyslots: LUKS2 dump"    "$(printf 'Keyslots:\n  0: luks2\n  1: luks2\n' | slotcount)" "2"
eq "keyslots: LUKS1 dump"    "$(printf 'Key Slot 0: ENABLED\nKey Slot 1: DISABLED\n' | slotcount)" "1"
eq "keyslots: cryptsetup failed -> 0, never a false warning" "$(printf '' | slotcount)" "0"

dmsetup() { printf 'dm_crypt-0\n'; }
cryptsetup() { printf '  device:  %s\n' "$DEV"; }
eq "live_name: finds the open mapping" "$(live_name)" "dm_crypt-0"
cryptsetup() { printf 'nothing parseable\n'; }
eq "live_name: unparseable status is not a match" "$(live_name)" ""

probe() { read -r x; [[ "$x" == "pw" ]]; }
try2 probe "pw" && ok "try2: passphrase with no trailing newline" || bad "try2" "fail" "pass"

# offline tool: neither script may reach for the network or a package manager
for f in "$SRC" "$HERE/../tpmfix.sh"; do
  pat='^[^#]*\b(apt|apt-get|aptitude|dpkg|snap|pip3?|curl|wget|nc|ssh|scp|rsync)\b'
  if grep -qE "$pat" "$f"; then
    bad "offline: $(basename "$f") must not install or fetch anything" "$(grep -nE "$pat" "$f" | head -n1)" ""
  else ok "offline: no installer or fetch in $(basename "$f")"; fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
