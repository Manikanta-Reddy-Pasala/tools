#!/usr/bin/env bash
# Prints ONE compact block to paste into chat. Read-only, no secrets, no auth attempts.
#
#   sudo ./paste-me.sh | tee tpm-paste.txt
#
# Deliberately does NOT try any password: a failed lockout-auth attempt restarts
# the lockoutRecovery timer and makes things worse. Use --probe only if told to.
set -euo pipefail
HERE="$(dirname "$(readlink -f "$0")")"
source "$HERE/lib/common.sh"

PROBE=0
[[ "${1:-}" == "--probe" ]] && PROBE=1

sec() { printf '\n### %s\n' "$*"; }
kv()  { printf '%-22s %s\n' "$1" "$2"; }

echo '```text'
echo "=== tpm paste-me $(date -Is 2>/dev/null || date) ==="

sec "host"
kv "hostname" "$(hostname 2>/dev/null || echo ?)"
for f in sys_vendor product_name board_name bios_vendor bios_version bios_date; do
  [[ -r "/sys/class/dmi/id/$f" ]] && kv "$f" "$(cat "/sys/class/dmi/id/$f")"
done
[[ -r /etc/os-release ]] && kv "os" "$(. /etc/os-release; echo "$PRETTY_NAME")"
kv "kernel" "$(uname -r)"
kv "uid" "$(id -u) ($(id -un))"

sec "tpm device"
for d in /dev/tpm0 /dev/tpmrm0; do
  if [[ -c $d ]]; then kv "$d" "$(stat -c '%A %U:%G' "$d" 2>/dev/null || echo present)"
  else kv "$d" "MISSING"; fi
done
[[ -r /sys/class/tpm/tpm0/tpm_version_major ]] && kv "tpm_version_major" "$(cat /sys/class/tpm/tpm0/tpm_version_major)"
[[ -r /sys/class/tpm/tpm0/device/description ]] && kv "description" "$(cat /sys/class/tpm/tpm0/device/description)"
kv "tpm2-tools" "$(tpm2_getcap --version 2>&1 | head -n1 || echo 'NOT INSTALLED')"
kv "abrmd active" "$(systemctl is-active tpm2-abrmd 2>/dev/null || echo no)"

if ! have tpm2_getcap; then
  echo; echo "tpm2-tools missing -> run: sudo ./install-deps.sh"; echo '```'; exit 0
fi
if ! TPM2TOOLS_TCTI="$(detect_tcti 2>/dev/null)"; then
  echo; echo "no usable TPM device -> TPM/PTT likely disabled in BIOS"; echo '```'; exit 0
fi
export TPM2TOOLS_TCTI
kv "TCTI" "$TPM2TOOLS_TCTI"

sec "manufacturer / firmware (properties-fixed, filtered)"
tpm2_getcap properties-fixed 2>&1 | \
  grep -A2 -E 'TPM2_PT_(MANUFACTURER|VENDOR_STRING_1|FIRMWARE_VERSION_1|FIRMWARE_VERSION_2|FAMILY_INDICATOR|REVISION)' \
  | sed 's/^/  /' || echo "  (failed)"

sec "properties-variable (RAW - this is the important one)"
tpm2_getcap properties-variable 2>&1 || echo "  (failed - permission? run with sudo)"

sec "decoded"
# capture directly: never let a failed getcap abort mid-fence
TPM_VARCAP="$(tpm2_getcap properties-variable 2>/dev/null || echo 'getcap_failed: 1')"
for f in ownerAuthSet endorsementAuthSet lockoutAuthSet disableClear inLockout tpmGeneratedEPS phEnable shEnable ehEnable orderly; do
  v="$(prop "$f")"; [[ -n "$v" ]] && kv "$f" "$v"
done
kv "lockoutCounter"  "$(prop TPM2_PT_LOCKOUT_COUNTER)"
kv "maxAuthFail"     "$(prop TPM2_PT_MAX_AUTH_FAIL)"
kv "lockoutInterval" "$(human_secs "$(prop TPM2_PT_LOCKOUT_INTERVAL)")"
kv "lockoutRecovery" "$(human_secs "$(prop TPM2_PT_LOCKOUT_RECOVERY)")"

sec "handles"
echo "persistent:"; tpm2_getcap handles-persistent 2>&1 | sed 's/^/  /' | head -n 20
echo "nv-index:";   tpm2_getcap handles-nv-index   2>&1 | sed 's/^/  /' | head -n 20

sec "what would be destroyed by a clear"
if have cryptsetup; then
  ANY=0
  while read -r dev; do
    [[ -n "$dev" ]] || continue
    ANY=1
    D="$(cryptsetup luksDump "$dev" 2>/dev/null || true)"
    S="$(grep -cE '^[[:space:]]+[0-9]+: luks2' <<<"$D" || true)"
    [[ "${S:-0}" == 0 ]] && S="$(grep -cE '^Key Slot [0-9]+: ENABLED' <<<"$D" || true)"
    T="$(grep -ciE 'systemd-tpm2|clevis' <<<"$D" || true)"
    kv "$dev" "keyslots=${S:-0} tpm_tokens=${T:-0} $( ((${T:-0}>0)) && echo '<-- TPM-BOUND' )"
  done < <(luks_devices)
  (( ANY == 0 )) && echo "  no LUKS containers"
else
  echo "  cryptsetup not installed"
fi
[[ -f /etc/crypttab ]] && { echo "crypttab tpm2 lines:"; grep -i tpm2 /etc/crypttab 2>/dev/null | sed 's/^/  /' || echo "  none"; }
have mokutil && kv "secureboot" "$(mokutil --sb-state 2>&1 | head -n1)"

sec "kernel tpm messages (last 25)"
dmesg 2>/dev/null | grep -i tpm | tail -n 25 | sed 's/^/  /' || echo "  (dmesg needs root)"

if (( PROBE == 1 )); then
sec "PROBE: empty-auth lockout reset (WILL increment the DA counter if auth is set)"
  tpm2_dictionarylockout -c 2>&1 | sed 's/^/  /' || true
fi

sec "verdict"
IN="$(prop inLockout)"; PH="$(prop phEnable)"; RC="$(prop TPM2_PT_LOCKOUT_RECOVERY)"
if [[ "$IN" == "1" ]]; then
  echo "  IN LOCKOUT."
  [[ "${RC:-0}" == "0" ]] && echo "  lockoutRecovery=0 -> a FULL POWER CYCLE clears it." \
                          || echo "  must idle $(human_secs "$RC"), or clear the TPM."
  [[ "$PH" == "0" ]] && echo "  phEnable=0 -> tpm2_clear -c p is dead this boot; BIOS only." \
                     || echo "  phEnable=1 -> tpm2_clear -c p should work."
else
  echo "  not in lockout."
fi
echo '```'
