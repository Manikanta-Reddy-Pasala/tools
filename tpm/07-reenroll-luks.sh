#!/usr/bin/env bash
# After a TPM clear, re-bind LUKS auto-unlock. Requires the LUKS passphrase.
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

need_root "$@"
DEV="${1:-}"
PCRS="${PCRS:-7}"    # 7 = Secure Boot state. Add 0+2+4 for firmware+bootloader, but they
                     # change on every firmware/kernel update and will lock you out again.

if [[ -z "$DEV" ]]; then
  cat <<'MSG'
usage: sudo ./07-reenroll-luks.sh /dev/nvme0n1p3 [--wipe-stale]
       sudo PCRS=7 ./07-reenroll-luks.sh /dev/nvme0n1p3

Find your LUKS device:
MSG
  lsblk -pno NAME,TYPE,FSTYPE,MOUNTPOINT 2>/dev/null | grep -i crypto_LUKS || true
  exit 1
fi

cryptsetup isLuks "$DEV" || die "$DEV is not a LUKS device"
have systemd-cryptenroll || die "systemd-cryptenroll not found"

hdr "current keyslots"
cryptsetup luksDump "$DEV" | sed -n '/^Keyslots:/,/^Tokens:/p' | sed 's/^/    /'

if [[ "${2:-}" == "--wipe-stale" ]]; then
  warn "removing stale tpm2 keyslots (they point at the OLD, now-destroyed SRK)"
  systemd-cryptenroll "$DEV" --wipe-slot=tpm2 || warn "nothing to wipe"
fi

info "enrolling against PCR set: $PCRS"
info "you will be asked for an EXISTING LUKS passphrase"
systemd-cryptenroll "$DEV" --tpm2-device=auto --tpm2-pcrs="$PCRS"
ok "enrolled"

cat <<'MSG'

Make sure /etc/crypttab has tpm2-device=auto on that volume, then:
  sudo update-initramfs -u -k all       # Ubuntu
  # or: sudo dracut -f

Keep a passphrase keyslot forever. Verify before you reboot:
  sudo cryptsetup open --test-passphrase DEVICE && echo "passphrase still works"
MSG
