#!/usr/bin/env bash
# Dump everything into one shareable text file. No secrets are included.
set -euo pipefail
HERE="$(dirname "$(readlink -f "$0")")"
OUT="${1:-tpm-report-$(hostname -s 2>/dev/null || echo host)-$(date +%Y%m%d-%H%M%S).txt}"

{
  echo "=== generated $(date -Is) ==="
  echo "=== uname ==="        ; uname -a
  echo "=== os ==="           ; cat /etc/os-release 2>/dev/null
  echo "=== dmi ==="          ; cat /sys/class/dmi/id/{sys_vendor,product_name,bios_version,bios_date} 2>/dev/null
  echo "=== tpm sysfs ==="    ; ls -l /dev/tpm* 2>/dev/null; cat /sys/class/tpm/tpm0/{tpm_version_major,device/description} 2>/dev/null
  echo "=== dmesg tpm ==="    ; dmesg 2>/dev/null | grep -i tpm | tail -n 40
  echo "=== tools ver ==="    ; tpm2_getcap --version 2>&1
  echo "=== properties-fixed ===";    tpm2_getcap properties-fixed 2>&1
  echo "=== properties-variable ==="; tpm2_getcap properties-variable 2>&1
  echo "=== handles-persistent ==="; tpm2_getcap handles-persistent 2>&1
  echo "=== handles-nv-index ==="  ; tpm2_getcap handles-nv-index 2>&1
  echo "=== pcrs ==="         ; tpm2_pcrread sha256 2>&1 | head -n 30
  echo "=== status.sh ==="    ; "$HERE/00-status.sh" 2>&1
} > "$OUT" 2>&1 || true

echo "wrote $OUT"
echo "review it before sharing - it lists device names, no keys or passwords."
