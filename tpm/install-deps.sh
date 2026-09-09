#!/usr/bin/env bash
# Install tpm2-tools on Ubuntu/Debian.
# tpm2-abrmd is NOT installed by default: the in-kernel resource manager
# (/dev/tpmrm0) is what these scripts use, and a running abrmd can hold the
# TPM open. Pass --with-abrmd only if /dev/tpmrm0 does not exist.
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

need_root "$@"
# libhivex-bin -> hivexget, used by 08-recover-windows-auth.sh to read the lockout
# password Windows left in the SYSTEM registry hive. clevis-* -> 09-clevis.sh.
PKGS=(tpm2-tools cryptsetup-bin libhivex-bin)
for a in "$@"; do
  case "$a" in
    --with-abrmd)  PKGS+=(tpm2-abrmd) ;;
    --with-clevis) PKGS+=(clevis clevis-luks clevis-tpm2 clevis-initramfs) ;;
  esac
done

info "installing: ${PKGS[*]}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y "${PKGS[@]}" >/dev/null
ok "$(tpm2_getcap --version 2>/dev/null || echo 'tpm2-tools installed')"
have hivexget && ok "hivexget present (Windows lockout-password recovery available)"

# Ubuntu 22.04 ships tpm2-tools 5.2 and clevis 18 - both new enough for everything here.
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  info "OS: ${PRETTY_NAME:-unknown}"
  [[ "${VERSION_ID:-}" == "22.04" ]] && ok "jammy: tpm2-tools 5.2, clevis 18 ('clevis luks pass' available)"
fi

if [[ -c /dev/tpmrm0 ]]; then
  ok "/dev/tpmrm0 present (in-kernel resource manager)"
elif [[ -c /dev/tpm0 ]]; then
  warn "/dev/tpm0 only, no /dev/tpmrm0. Kernel is old or TPM2 not detected as 2.0."
else
  err "no /dev/tpm* device at all."
  echo "    - TPM/PTT is probably disabled in BIOS (Advanced -> Security -> Intel Platform Trust Technology)"
  echo "    - kernel view: dmesg | grep -i tpm"
fi
