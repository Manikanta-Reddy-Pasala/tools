#!/usr/bin/env bash
# Install tpm2-tools + friends on Ubuntu/Debian.
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

need_root "$@"
info "installing tpm2-tools, tpm2-abrmd, cryptsetup helpers"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y tpm2-tools tpm2-abrmd cryptsetup-bin >/dev/null
ok "installed: $(tpm2_getcap --version 2>/dev/null || echo tpm2-tools)"

if [[ ! -c /dev/tpmrm0 && ! -c /dev/tpm0 ]]; then
  warn "no /dev/tpm* device. TPM/PTT probably disabled in BIOS."
  warn "check kernel view: dmesg | grep -i tpm"
fi
