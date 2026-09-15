#!/usr/bin/env bash
# TPM + LUKS auto-unlock, Ubuntu 22.04 / Intel PTT. Offline: installs nothing, prints nothing.
#   read -rs LUKS_PASS && export LUKS_PASS && sudo --preserve-env=LUKS_PASS ./provision.sh
# Exit 0 = done. Any other exit = a command failed; run it by hand to see why. No arguments:
# for a read-only look at a box, use ./tpmfix.sh --status.
# Needs: tpm2-tools clevis clevis-luks clevis-tpm2 clevis-initramfs cryptsetup-bin initramfs-tools
set -euo pipefail
[[ $# -eq 0 ]] || exit 64

MAXTRIES="${MAXTRIES:-32}"
RECOVERY_TIME="${RECOVERY_TIME:-60}"
LOCKOUT_RECOVERY_TIME="${LOCKOUT_RECOVERY_TIME:-60}"
PCR_IDS="${PCR_IDS:-7}"
PCR_BANK="${PCR_BANK:-sha256}"
DEV="${DEV:-$(blkid -t TYPE=crypto_LUKS -o device)}"   # more than one: set DEV, or this fails
PASS="${LUKS_PASS-}"; unset LUKS_PASS     # unset drops the export: no child inherits it
export TPM2TOOLS_TCTI="device:/dev/tpmrm0"

# slots sealed to PCR $PCR_IDS, and whether any of them still releases the key
pinned()  { clevis luks list -d "$DEV" | grep -E "^[0-9]+: tpm2 .*\"pcr_ids\":\"$PCR_IDS\"" | cut -d: -f1 || true; }
unseals() { local s; for s in $(pinned); do clevis luks pass -d "$DEV" -s "$s" >/dev/null 2>&1 && return 0; done; return 1; }

# dictionary-attack parameters. Fails if lockoutAuth is set (Windows sets it): run tpmfix.sh.
tpm2_dictionarylockout --setup-parameters --max-tries="$MAXTRIES" \
  --recovery-time="$RECOVERY_TIME" --lockout-recovery-time="$LOCKOUT_RECOVERY_TIME" >/dev/null

# clevis sealed to PCR 7, unless a slot already unseals (a slot that exists but no longer
# unseals - BIOS or Secure Boot changed - does not count). -y -k - is the only working
# non-interactive path on jammy. pcr_ids is not optional: without it the key unseals in ANY
# boot state.
if ! unseals; then
  STALE="$(pinned)"        # sealed to a PCR 7 state this box no longer has (BIOS/Secure Boot changed)
  printf '%s' "$PASS" | clevis luks bind -y -k - -d "$DEV" tpm2 \
    "{\"pcr_bank\":\"$PCR_BANK\",\"pcr_ids\":\"$PCR_IDS\"}"
  unseals                  # the new slot must work before the old ones go
  # left in place they would release the key again if that old firmware state ever returns
  for s in $STALE; do clevis luks unbind -d "$DEV" -s "$s" -f; done
fi
unset PASS

unseals                                    # prove the TPM releases the key before boot needs it
update-initramfs -u -k all >/dev/null      # -k all: a kernel installed but not yet booted needs the hook too
