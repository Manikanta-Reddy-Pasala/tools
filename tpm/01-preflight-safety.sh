#!/usr/bin/env bash
# Read-only. Answers ONE question: is it safe to wipe this TPM?
# Run this before 04-clear-tpm.sh or before toggling PTT in BIOS.
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

setup_tpm_env
RISK=0
note() { err "$*"; RISK=$((RISK+1)); }

hdr "1. LUKS volumes bound to the TPM"
if have cryptsetup && have lsblk; then
  while read -r dev; do
    cryptsetup isLuks "$dev" 2>/dev/null || continue
    DUMP="$(cryptsetup luksDump "$dev" 2>/dev/null || true)"
    if grep -qi 'systemd-tpm2' <<<"$DUMP"; then
      note "$dev : systemd-cryptenroll TPM2 keyslot"
    fi
    if grep -qi 'clevis' <<<"$DUMP"; then
      note "$dev : Clevis TPM2 binding"
    fi
    # Is there any plain passphrase slot left as an escape route?
    SLOTS="$(grep -cE '^[[:space:]]+[0-9]+: luks2' <<<"$DUMP" || true)"
    TOKENS="$(grep -ciE 'systemd-tpm2|clevis' <<<"$DUMP" || true)"
    if [[ "${SLOTS:-0}" -gt 0 ]]; then
      info "$dev : $SLOTS keyslot(s), $TOKENS TPM-backed token(s)"
      if [[ "${SLOTS:-0}" -le "${TOKENS:-0}" ]]; then
        note "$dev : NO passphrase-only keyslot left -> wiping the TPM makes this volume UNOPENABLE"
      fi
    fi
  done < <(lsblk -pnro NAME,TYPE 2>/dev/null | awk '$2=="part"{print $1}')
else
  warn "cryptsetup/lsblk missing, cannot check LUKS"
fi

hdr "2. Persistent objects stored in the TPM"
PERSIST="$(tpm2_getcap handles-persistent 2>/dev/null || true)"
if grep -q '0x81' <<<"$PERSIST"; then
  note "persistent handles present (TPM-resident keys - ssh-tpm-agent, tpm2-pkcs11, IMA, etc.):"
  sed 's/^/      /' <<<"$PERSIST"
else
  ok "no persistent handles"
fi

hdr "3. NV indices with user data"
NV="$(tpm2_getcap handles-nv-index 2>/dev/null || true)"
if grep -q '0x1' <<<"$NV"; then
  warn "NV indices defined (some are firmware-owned and will come back):"
  sed 's/^/      /' <<<"$NV"
else
  ok "no NV indices"
fi

hdr "4. Consumers on this system"
for u in tpm2-pkcs11 ssh-tpm-agent clevis-luks-askpass systemd-cryptsetup; do
  have "$u" && warn "installed: $u"
done
[[ -d "$HOME/.tpm2_pkcs11" ]] && note "tpm2-pkcs11 token store at ~/.tpm2_pkcs11"
if [[ -f /etc/crypttab ]] && grep -qi 'tpm2' /etc/crypttab; then
  note "/etc/crypttab references tpm2"
  grep -i tpm2 /etc/crypttab | sed 's/^/      /'
fi

hdr "5. Secure Boot / measured boot"
if have mokutil; then
  info "SecureBoot: $(mokutil --sb-state 2>/dev/null || echo unknown)"
fi
info "clearing the TPM does not disable Secure Boot, but it does invalidate any PCR-sealed policy"

hdr "verdict"
if (( RISK == 0 )); then
  ok "no TPM-sealed secrets found. Clearing the TPM looks safe on this box."
  info "proceed: sudo ./04-clear-tpm.sh"
else
  err "$RISK risk item(s) found."
  cat <<'MSG'

Before clearing, make sure you can still get in without the TPM:

  # confirm a passphrase keyslot exists and that YOU KNOW the passphrase
  sudo cryptsetup luksDump /dev/<your-luks-part>
  sudo cryptsetup open --test-passphrase /dev/<your-luks-part> && echo "passphrase OK"

  # back up the LUKS header off-box
  sudo cryptsetup luksHeaderBackup /dev/<your-luks-part> --header-backup-file luks-header.img

Only then run ./04-clear-tpm.sh
MSG
  exit 2
fi
