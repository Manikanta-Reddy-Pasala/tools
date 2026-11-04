#!/usr/bin/env bash
# TPM + LUKS auto-unlock, Ubuntu 22.04 / Intel PTT. Offline: installs nothing, silent on success.
#   read -rs LUKS_PASS && export LUKS_PASS && sudo --preserve-env=LUKS_PASS ./provision.sh
# Exit 0 = done. 10 = TPM clear queued: reboot, run again. 75 = TPM locked: wait/reboot, run
# again. 3 = clear the TPM in BIOS, or not run on the installed system. 2 = setup problem
# (message says which). Other = a command failed. No arguments: for a read-only look, use
# ./tpmfix.sh --status.
# Needs: tpm2-tools clevis clevis-luks clevis-tpm2 clevis-initramfs cryptsetup-bin initramfs-tools
set -euo pipefail
[[ $# -eq 0 ]] || exit 64

MAXTRIES="${MAXTRIES:-32}"
RECOVERY_TIME="${RECOVERY_TIME:-60}"
LOCKOUT_RECOVERY_TIME="${LOCKOUT_RECOVERY_TIME:-60}"
PCR_IDS="${PCR_IDS:-7}"
PCR_BANK="${PCR_BANK:-}"   # empty: sha256 if the TPM has that bank allocated, else sha1
DEV="${DEV:-$(blkid -t TYPE=crypto_LUKS -o device || true)}"
[[ -n "$DEV" && "$DEV" != *$'\n'* ]] || { echo "provision.sh: need one LUKS device, found: ${DEV:-none} (set DEV=)" >&2; exit 2; }
PASS="${LUKS_PASS-}"; unset LUKS_PASS     # unset drops the export: no child inherits it
export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
PPI="${PPI:-/sys/class/tpm/tpm0/ppi}"

# From the installer shell this would bind against the USB boot's PCR 7 and rebuild the
# live system's initrd, not the installed one's (a curtin in-target chroot: PCR 7 is still the
# USB boot's). Run it on the installed system.
! grep -qs ' /target ' /proc/mounts && [[ / -ef /proc/1/root ]] || { echo "provision.sh: run after first boot, not in the installer" >&2; exit 3; }

# Firmware picks the allocated PCR banks; some Dell TPMs run SHA-1 only, and sealing to an
# empty sha256 bank dies in tpm2_createpolicy ("pcr-input-file filesize does not match").
# A bank counts only if every PCR in PCR_IDS reads a real value (not all 0s / all Fs).
has() {
  local out id v
  out="$(tpm2_pcrread "$1:$PCR_IDS" 2>/dev/null)" || return 1
  for id in ${PCR_IDS//,/ }; do
    v="$(sed -n "s/^[[:space:]]*${id}[[:space:]]*:[[:space:]]*0x\([0-9A-Fa-f]\{1,\}\)[[:space:]]*$/\1/p" <<<"$out")"
    [[ -n "$v" && "$v" =~ [1-9A-Ea-e] ]] || return 1
  done
}
if [[ -z "$PCR_BANK" ]]; then
  if has sha256; then PCR_BANK=sha256
  elif has sha1; then PCR_BANK=sha1; echo "provision.sh: TPM has no SHA-256 PCR bank, sealing to sha1 (set SHA-256 in BIOS to fix)" >&2
  elif ! command -v tpm2_pcrread >/dev/null; then echo "provision.sh: tpm2_pcrread missing" >&2; exit 2
  else echo "provision.sh: tpm2_pcrread found PCR $PCR_IDS in no bank (tpm2_getcap pcrs)" >&2; exit 2; fi
elif ! has "$PCR_BANK"; then
  echo "provision.sh: PCR bank $PCR_BANK does not hold PCR $PCR_IDS (tpm2_getcap pcrs)" >&2; exit 2
fi

# slots sealed to PCR $PCR_IDS, and whether any of them still releases the key
pinned()  { clevis luks list -d "$DEV" | grep -E "^[0-9]+: tpm2 .*\"pcr_ids\":\"$PCR_IDS\"" | cut -d: -f1 || true; }
unseals() { local s; for s in $(pinned); do clevis luks pass -d "$DEV" -s "$s" >/dev/null 2>&1 && return 0; done; return 1; }

VC="$(tpm2_getcap properties-variable)"
v() { sed -n "s/^[[:space:]]*$1:[[:space:]]*\([^[:space:]]*\).*/\1/p" <<<"$VC" | head -n1; }

# lockoutAuth set (Windows left it): no password works and every wrong try re-locks the
# lockout hierarchy (0x921). Only TPM2_Clear resets it; queue that through PPI (no password,
# works in lockout). Intel PTT clears on the next reboot WITHOUT a prompt. Old clevis slots
# die with the clear; the re-run after the reboot binds a new one, so prove the passphrase now.
# A crypttab keyscript would lose its TPM key too, with no passphrase fallback: tpmfix.sh.
# ownerAuth set is the same dead end: clevis seals under the owner hierarchy with no password.
if [[ "$(v lockoutAuthSet)" == 1 || "$(v ownerAuthSet)" == 1 ]]; then
  printf '%s' "$PASS" | cryptsetup open --test-passphrase "$DEV" --key-file=- 2>/dev/null \
    || { echo "provision.sh: TPM must be cleared; set LUKS_PASS to the right passphrase first" >&2; exit 2; }
  ! grep -qs '^[^#]*keyscript=' /etc/crypttab || { echo "provision.sh: crypttab uses a keyscript, run tpmfix.sh" >&2; exit 2; }
  for d in $(blkid -t TYPE=crypto_LUKS -o device || true); do   # the clear kills their TPM slots too
    [[ "$d" -ef "$DEV" ]] || ! clevis luks list -d "$d" 2>/dev/null | grep -q tpm2 \
      || { echo "provision.sh: $d also unlocks via the TPM; a clear would break it" >&2; exit 2; }
  done
  # already queued, or the last clear was refused (prompt declined, firmware ignored it): don't loop
  [[ "$(cat "$PPI/request" 2>/dev/null || true)" != 5 ]] || { echo "provision.sh: TPM clear already queued. Reboot." >&2; exit 10; }
  if grep -qs '^[[:space:]]*5[[:space:]]\{1,\}[1-9]' "$PPI/response"; then
    echo "provision.sh: last TPM clear failed ($(cat "$PPI/response")); clear the TPM in BIOS (PTT off, boot, PTT on)" >&2; exit 3
  fi
  st="$(sed -n 's/^[[:space:]]*5[[:space:]]\{1,\}\([0-9]\{1,\}\):.*/\1/p' "$PPI/tcg_operations" 2>/dev/null | head -n1 || true)"
  if [[ "$st" == 3 || "$st" == 4 ]]; then
    printf '5' > "$PPI/request"
    [[ "$st" == 4 ]] || p=" and confirm the firmware prompt"
    echo "provision.sh: TPM clear queued (wipes every TPM key, BitLocker too). Reboot${p-}, then run this again." >&2; exit 10
  fi
  echo "provision.sh: clear the TPM in BIOS (PTT off, boot, PTT on), then run this again" >&2; exit 3
fi

# out of DA lockout (it blocks clevis unlock too), then the parameters. Two calls: jammy's
# tpm2_dictionarylockout given both flags only clears, and still exits 0.
# 0x921 here = an earlier wrong lockout password: the TPM refuses until lockoutRecovery passes.
if ! out="$(tpm2_dictionarylockout --clear-lockout 2>&1 && tpm2_dictionarylockout --setup-parameters \
    --max-tries="$MAXTRIES" --recovery-time="$RECOVERY_TIME" --lockout-recovery-time="$LOCKOUT_RECOVERY_TIME" 2>&1)"; then
  if [[ "$out" == *0x921* ]]; then
    w="$(v TPM2_PT_LOCKOUT_RECOVERY)"; w=$((w))
    if (( w )); then echo "provision.sh: TPM locked, leave it powered on up to ${w}s, then run this again" >&2
    else echo "provision.sh: TPM locked until reboot. Reboot, then run this again." >&2; fi
    exit 75
  fi
  echo "$out" >&2; exit 1
fi

# clevis sealed to PCR 7, unless a slot already unseals (a slot that exists but no longer
# unseals - BIOS or Secure Boot changed - does not count). -y -k - is the only working
# non-interactive path on jammy. pcr_ids is not optional: without it the key unseals in ANY
# boot state.
if ! unseals; then
  STALE="$(pinned)"        # sealed to a PCR 7 state this box no longer has (BIOS/Secure Boot changed)
  printf '%s' "$PASS" | clevis luks bind -y -k - -d "$DEV" tpm2 \
    "{\"pcr_bank\":\"$PCR_BANK\",\"pcr_ids\":\"$PCR_IDS\"}"
  # the new slot must work before the old ones go; a dud is removed so re-runs don't pile up slots
  if ! unseals; then
    for s in $(pinned | grep -vxF -e "${STALE:-none}" || true); do clevis luks unbind -d "$DEV" -s "$s" -f; done
    echo "provision.sh: the new TPM slot does not unseal; removed it" >&2; exit 1
  fi
  # left in place they would release the key again if that old firmware state ever returns
  for s in $STALE; do clevis luks unbind -d "$DEV" -s "$s" -f; done
fi
unset PASS

unseals                                    # prove the TPM releases the key before boot needs it
update-initramfs -u -k all >/dev/null      # -k all: a kernel installed but not yet booted needs the hook too
