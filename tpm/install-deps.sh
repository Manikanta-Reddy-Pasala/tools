#!/usr/bin/env bash
# Install tpm2-tools on Ubuntu/Debian.
# tpm2-abrmd is NOT installed by default: the in-kernel resource manager
# (/dev/tpmrm0) is what these scripts use, and a running abrmd can hold the
# TPM open. Pass --with-abrmd only if /dev/tpmrm0 does not exist.
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

need_root "$@"
PKGS=(tpm2-tools cryptsetup-bin)
[[ "${1:-}" == "--with-abrmd" ]] && PKGS+=(tpm2-abrmd)

info "installing: ${PKGS[*]}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y "${PKGS[@]}" >/dev/null
ok "$(tpm2_getcap --version 2>/dev/null || echo 'tpm2-tools installed')"

if [[ -c /dev/tpmrm0 ]]; then
  ok "/dev/tpmrm0 present (in-kernel resource manager)"
elif [[ -c /dev/tpm0 ]]; then
  warn "/dev/tpm0 only, no /dev/tpmrm0. Kernel is old or TPM2 not detected as 2.0."
else
  err "no /dev/tpm* device at all."
  echo "    - TPM/PTT is probably disabled in BIOS (Advanced -> Security -> Intel Platform Trust Technology)"
  echo "    - kernel view: dmesg | grep -i tpm"
fi
