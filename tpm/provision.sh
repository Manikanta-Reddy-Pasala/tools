#!/usr/bin/env bash
# TPM + LUKS auto-unlock, Ubuntu 22.04 / Intel PTT. Offline: installs nothing, silent on success.
#   read -rs LUKS_PASS && export LUKS_PASS && sudo --preserve-env=LUKS_PASS ./provision.sh
# From autoinstall late-commands (curtin in-target) it binds the TPM right there, and leaves a
# one-time unit that checks the bind on the first real boot (see "in the installer" below, README §4a).
#   curtin in-target --target=/target -- env LUKS_PASS_FILE=/run/luks.pass /usr/local/bin/provision.sh
# Exit 0 = done (in the installer: bound, or left to the first boot). 10 = TPM clear queued: reboot, run again.
# 75 = TPM locked: wait/reboot, run again. 3 = clear the TPM in BIOS. 2 = setup problem
# (message says which). Other = a command failed. No arguments: for a read-only look, use
# ./tpmfix.sh --status.
# Needs: tpm2-tools clevis clevis-luks clevis-tpm2 clevis-initramfs cryptsetup-bin initramfs-tools
set -euo pipefail                # stop on the first failed command, unset variable or pipe error
[[ $# -eq 0 ]] || exit 64        # takes no arguments: a typo must not provision anything

# ---------------------------------------------------------------- settings (all from env)
MAXTRIES="${MAXTRIES:-32}"                            # wrong TPM passwords allowed before DA lockout
RECOVERY_TIME="${RECOVERY_TIME:-60}"                  # seconds until one wrong try is forgotten
LOCKOUT_RECOVERY_TIME="${LOCKOUT_RECOVERY_TIME:-60}"  # wait after a wrong lockout password (0 = until reboot)
PCR_IDS="${PCR_IDS:-7}"          # PCRs the key is sealed to; 7 = Secure Boot state (see the check below)
PCR_BANK="${PCR_BANK:-}"         # empty: sha256 if the TPM has that bank allocated, else sha1
# the LUKS partition: blkid lists every crypto_LUKS device; exactly one is expected
DEV="${DEV:-$(blkid -t TYPE=crypto_LUKS -o device || true)}"
[[ -n "$DEV" && "$DEV" != *$'\n'* ]] || { echo "provision.sh: need one LUKS device, found: ${DEV:-none} (set DEV=)" >&2; exit 2; }
PASS="${LUKS_PASS-}"; unset LUKS_PASS     # unset drops the export: no child inherits it
# LUKS_PASS_FILE: read the passphrase from a file (installer: keeps it off every command line)
if [[ -z "$PASS" && -n "${LUKS_PASS_FILE-}" ]]; then
  [[ -r "$LUKS_PASS_FILE" ]] || { echo "provision.sh: cannot read LUKS_PASS_FILE $LUKS_PASS_FILE" >&2; exit 2; }
  PASS="$(cat "$LUKS_PASS_FILE")"         # $(...) drops a trailing newline, as typing would
fi
export TPM2TOOLS_TCTI="device:/dev/tpmrm0" # tpm2-tools talk to the kernel resource manager
PPI="${PPI:-/sys/class/tpm/tpm0/ppi}"     # Physical Presence Interface: asks firmware to clear the TPM
STAGE="${STAGE:-/var/lib/tpm-provision}"  # installer -> first boot hand-off (one-time key + env)
# UEFI SecureBoot variable: 4 attribute bytes, then 1 data byte (1 = on, 0 = off)
SB_VAR="${SB_VAR:-/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c}"

# ---------------------------------------------------------------- Secure Boot off?
# PCR 7 still gets a value with Secure Boot off (it records "SecureBoot = 0" and the key
# databases), so binding and auto-unlock work. But nothing about the boot loader goes in, so
# ANY USB stick reads the same PCR 7 and can unseal the key. Not fatal: warn, keep going.
if [[ -r "$SB_VAR" && ",$PCR_IDS," == *,7,* ]]; then
  sb="$(od -An -tx1 -j4 -N1 "$SB_VAR" 2>/dev/null | tr -d ' \n' || true)"   # the data byte, as hex; a read error only skips the warning
  [[ "$sb" == 01 || -z "$sb" ]] || echo "provision.sh: Secure Boot is off - PCR 7 is the same for any boot media, a USB stick can unseal the key too. Turn Secure Boot on in BIOS (then run this again), or see README 'Secure Boot off'" >&2
fi

# ---------------------------------------------------------------- in the installer
# In the installer: a curtin in-target chroot (/ is not PID 1's root) or the live shell with
# /target mounted. The installed system first gets a one-time random key in a spare LUKS slot,
# this script, and a unit that runs it on the first real boot (the safety net below).
#  - chroot (curtin in-target): / IS the installed system, so the normal steps run right here:
#    bind the TPM, update the installed initrd. PCR 7 read now is the USB boot's; with Secure
#    Boot off it equals the disk boot's (it holds only firmware settings), and with it on it
#    matches as long as the same signers booted both. If the disk boot reads another PCR 7, that
#    boot asks for the passphrase once and the first-boot unit binds again.
#  - live shell (/target mounted, not a chroot): update-initramfs would rebuild the live
#    system's initrd, so nothing is bound; the first-boot unit does all of it.
# The first-boot run binds if needed, then removes the one-time key from LUKS and the disk.
# legacy BIOS boot: no efivars at all, PCR 7 then says nothing about the boot
[[ ",$PCR_IDS," != *,7,* || -d "${SB_VAR%/*}" ]] \
  || echo "provision.sh: no UEFI (legacy BIOS boot?) - PCR 7 then protects nothing; boot UEFI with Secure Boot on" >&2

if [[ -n "${NO_INSTALLER-}" ]]; then INSTALL_ROOT=     # NO_INSTALLER=1: never treat this as the installer
elif [[ -z "${INSTALL_ROOT-}" ]]; then                 # INSTALL_ROOT=<dir> forces a root (tests)
  if ! [[ / -ef /proc/1/root ]]; then INSTALL_ROOT=/  # chroot: the installed system is /
  elif grep -qs ' /target ' /proc/mounts; then INSTALL_ROOT=/target; fi   # live shell
fi
if [[ -n "${INSTALL_ROOT-}" ]]; then
  R="${INSTALL_ROOT%/}"; S="$R$STAGE"                  # S = the stage dir inside the installed system
  # the passphrase must open the disk now: it is what adds the one-time key below
  printf '%s' "$PASS" | cryptsetup open --test-passphrase "$DEV" --key-file=- 2>/dev/null \
    || { echo "provision.sh: installer: set LUKS_PASS (or LUKS_PASS_FILE) to the passphrase of $DEV" >&2; exit 2; }
  # the installed system must have the tools, or every first boot would fail: stop the install now
  for t in clevis clevis-luks-bind clevis-encrypt-tpm2 tpm2_pcrread update-initramfs; do
    found=
    for d in usr/bin usr/sbin bin sbin; do [[ -x "$R/$d/$t" ]] && found=1; done   # where packages put them
    [[ -n "$found" ]] \
      || { echo "provision.sh: installer: $t missing in the installed system (add tpm2-tools clevis clevis-luks clevis-tpm2 clevis-initramfs to packages:)" >&2; exit 2; }
  done
  install -d -m 700 "$S"                               # root-only dir
  # re-run: keep a key that already opens the disk, so slots don't pile up
  if ! cryptsetup open --test-passphrase "$DEV" --key-file="$S/key" 2>/dev/null; then
    # 48 random bytes as base64 text: no NUL or newline, so it survives a shell variable
    (umask 077; head -c 48 /dev/urandom | base64 -w0 > "$S/key")
    printf '%s' "$PASS" | cryptsetup luksAddKey --key-file=- "$DEV" "$S/key"   # spare LUKS slot
  fi
  # settings for the first boot run, read by the unit's EnvironmentFile
  # DEV by UUID: sdX names can change between the installer and the installed system
  { echo "DEV=/dev/disk/by-uuid/$(cryptsetup luksUUID "$DEV")"
    for n in STAGE PCR_IDS PCR_BANK MAXTRIES RECOVERY_TIME LOCKOUT_RECOVERY_TIME; do
      [[ -z "${!n}" ]] || echo "$n=${!n}"              # ${!n} = value of the variable named n
    done; } > "$S/env"
  # this script, copied into the installed system for the unit to run
  install -D -m 700 "$(readlink -f "${BASH_SOURCE[0]}")" "$R/usr/local/sbin/tpm-provision"
  install -d "$R/etc/systemd/system/multi-user.target.wants"
  # the one-time unit; it runs only while the key file exists
  cat > "$R/etc/systemd/system/tpm-provision.service" <<EOF
[Unit]
Description=Bind the LUKS disk to the TPM (one time, after install)
ConditionPathExists=$STAGE/key
# after cloud-init's first-boot run: a reboot for a TPM clear must not cut it short
After=local-fs.target cloud-final.service
StartLimitIntervalSec=1h
StartLimitBurst=5

[Service]
# exec, not oneshot: boot does not wait for it (TPM lockout retries can take minutes)
Type=exec
EnvironmentFile=$STAGE/env
ExecStartPre=-/usr/bin/timeout 30 /bin/sh -c 'until [ -e /dev/tpmrm0 ]; do sleep 1; done'
ExecStart=/usr/local/sbin/tpm-provision
# 75 = TPM locked: wait, try again. 10 = TPM clear queued: the script reboots for it.
RestartForceExitStatus=75
RestartSec=90
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOF
  # enable by symlink: systemctl can't talk to systemd from inside a chroot
  ln -sfn ../tpm-provision.service "$R/etc/systemd/system/multi-user.target.wants/tpm-provision.service"
  if ! [[ "$INSTALL_ROOT" -ef / ]]; then               # live shell: handed off, TPM untouched
    echo "provision.sh: installer (live shell): TPM bind left to the first boot of $INSTALL_ROOT" >&2; exit 0
  fi
  # chroot: go on with the normal steps. Anything that stops them from here on (TPM clear
  # queued, TPM locked, TPM off in BIOS, a clevis error) must not fail the install: the
  # first-boot unit is staged and runs it again, with its error in the journal.
  trap 'rc=$?; if (( rc )); then echo "provision.sh: installer: TPM bind left to the first boot (exit $rc above)" >&2; exit 0; fi' EXIT
fi

# ---------------------------------------------------------------- first boot after the installer
# The one-time key stands in for the passphrase.
# Under systemd, a queued TPM clear (exit 10) reboots for it, at most 3 times.
if [[ -z "$PASS" && -s "$STAGE/key" ]]; then
  PASS="$(cat "$STAGE/key")"
  if [[ -n "${INVOCATION_ID-}" ]]; then                # set by systemd only: never reboot a shell user's box
    trap 'rc=$?; if [[ $rc == 10 ]]; then n=$(( $(cat "$STAGE/reboots" 2>/dev/null || echo 0) + 1 ))
      if (( n <= 3 )); then echo "$n" > "$STAGE/reboots"; echo "provision.sh: rebooting for the TPM clear" >&2; systemctl --no-block reboot; fi; fi' EXIT
  fi
fi

# ---------------------------------------------------------------- PCR bank
# Firmware picks the allocated PCR banks; some Dell TPMs run SHA-1 only, and sealing to an
# empty sha256 bank dies in tpm2_createpolicy ("pcr-input-file filesize does not match").
# A bank counts only if every PCR in PCR_IDS reads a real value (not all 0s / all Fs).
has() {
  local out id v
  out="$(tpm2_pcrread "$1:$PCR_IDS" 2>/dev/null)" || return 1   # e.g. "sha256:7"
  for id in ${PCR_IDS//,/ }; do                                 # "5,7" -> 5 7
    # the hex value printed for this PCR ("  7 : 0xABC...")
    v="$(sed -n "s/^[[:space:]]*${id}[[:space:]]*:[[:space:]]*0x\([0-9A-Fa-f]\{1,\}\)[[:space:]]*$/\1/p" <<<"$out")"
    [[ -n "$v" && "$v" =~ [1-9A-Ea-e] ]] || return 1            # all 0s or all Fs = bank not in use
  done
}
if [[ -z "$PCR_BANK" ]]; then                      # pick one: sha256 first
  if has sha256; then PCR_BANK=sha256
  elif has sha1; then PCR_BANK=sha1; echo "provision.sh: TPM has no SHA-256 PCR bank, sealing to sha1 (set SHA-256 in BIOS to fix)" >&2
  elif ! command -v tpm2_pcrread >/dev/null; then echo "provision.sh: tpm2_pcrread missing" >&2; exit 2
  else echo "provision.sh: tpm2_pcrread found PCR $PCR_IDS in no bank (tpm2_getcap pcrs)" >&2; exit 2; fi
elif ! has "$PCR_BANK"; then                       # asked for one: it must work
  echo "provision.sh: PCR bank $PCR_BANK does not hold PCR $PCR_IDS (tpm2_getcap pcrs)" >&2; exit 2
fi

# ---------------------------------------------------------------- helpers
# slots sealed to PCR $PCR_IDS, and whether any of them still releases the key
pinned()  { clevis luks list -d "$DEV" | grep -E "^[0-9]+: tpm2 .*\"pcr_ids\":\"$PCR_IDS\"" | cut -d: -f1 || true; }
unseals() { local s; for s in $(pinned); do clevis luks pass -d "$DEV" -s "$s" >/dev/null 2>&1 && return 0; done; return 1; }

VC="$(tpm2_getcap properties-variable)"     # TPM state: auth flags, lockout counters
v() { sed -n "s/^[[:space:]]*$1:[[:space:]]*\([^[:space:]]*\).*/\1/p" <<<"$VC" | head -n1; }   # one field of it

# ---------------------------------------------------------------- TPM owned by someone else
# lockoutAuth set (Windows left it): no password works and every wrong try re-locks the
# lockout hierarchy (0x921). Only TPM2_Clear resets it; queue that through PPI (no password,
# works in lockout). Intel PTT clears on the next reboot WITHOUT a prompt. Old clevis slots
# die with the clear; the re-run after the reboot binds a new one, so prove the passphrase now.
# A crypttab keyscript would lose its TPM key too, with no passphrase fallback: tpmfix.sh.
# ownerAuth set is the same dead end: clevis seals under the owner hierarchy with no password.
if [[ "$(v lockoutAuthSet)" == 1 || "$(v ownerAuthSet)" == 1 ]]; then
  # the passphrase is the only way in after the clear: it must be right before we clear
  printf '%s' "$PASS" | cryptsetup open --test-passphrase "$DEV" --key-file=- 2>/dev/null \
    || { echo "provision.sh: TPM must be cleared; set LUKS_PASS to the right passphrase first" >&2; exit 2; }
  ! grep -qs '^[^#]*keyscript=' /etc/crypttab || { echo "provision.sh: crypttab uses a keyscript, run tpmfix.sh" >&2; exit 2; }
  for d in $(blkid -t TYPE=crypto_LUKS -o device || true); do   # the clear kills their TPM slots too
    [[ "$d" -ef "$DEV" ]] || ! clevis luks list -d "$d" 2>/dev/null | grep -q tpm2 \
      || { echo "provision.sh: $d also unlocks via the TPM; a clear would break it" >&2; exit 2; }
  done
  # already queued, or the last clear was refused (prompt declined, firmware ignored it): don't loop
  [[ "$(cat "$PPI/request" 2>/dev/null || true)" != 5 ]] || { echo "provision.sh: TPM clear already queued. Reboot." >&2; exit 10; }
  if grep -qs '^[[:space:]]*5[[:space:]]\{1,\}[1-9]' "$PPI/response"; then   # "5 <non-zero>" = op 5 failed
    echo "provision.sh: last TPM clear failed ($(cat "$PPI/response")); clear the TPM in BIOS (PTT off, boot, PTT on)" >&2; exit 3
  fi
  # how firmware handles op 5: 3 = asks the user at boot, 4 = clears without asking
  st="$(sed -n 's/^[[:space:]]*5[[:space:]]\{1,\}\([0-9]\{1,\}\):.*/\1/p' "$PPI/tcg_operations" 2>/dev/null | head -n1 || true)"
  if [[ "$st" == 3 || "$st" == 4 ]]; then
    printf '5' > "$PPI/request"                     # op 5 = TPM2_Clear on the next reboot
    [[ "$st" == 4 ]] || p=" and confirm the firmware prompt"
    echo "provision.sh: TPM clear queued (wipes every TPM key, BitLocker too). Reboot${p-}, then run this again." >&2; exit 10
  fi
  echo "provision.sh: clear the TPM in BIOS (PTT off, boot, PTT on), then run this again" >&2; exit 3
fi

# ---------------------------------------------------------------- dictionary-attack settings
# out of DA lockout (it blocks clevis unlock too), then the parameters. Two calls: jammy's
# tpm2_dictionarylockout given both flags only clears, and still exits 0.
# 0x921 here = an earlier wrong lockout password: the TPM refuses until lockoutRecovery passes.
if ! out="$(tpm2_dictionarylockout --clear-lockout 2>&1 && tpm2_dictionarylockout --setup-parameters \
    --max-tries="$MAXTRIES" --recovery-time="$RECOVERY_TIME" --lockout-recovery-time="$LOCKOUT_RECOVERY_TIME" 2>&1)"; then
  if [[ "$out" == *0x921* ]]; then
    w="$(v TPM2_PT_LOCKOUT_RECOVERY)"; w=$((w))   # hex -> seconds still to wait
    if (( w )); then echo "provision.sh: TPM locked, leave it powered on up to ${w}s, then run this again" >&2
    else echo "provision.sh: TPM locked until reboot. Reboot, then run this again." >&2; fi
    exit 75
  fi
  echo "$out" >&2; exit 1                           # any other TPM error: show it as is
fi

# ---------------------------------------------------------------- bind
# clevis sealed to PCR $PCR_IDS, unless a slot already unseals (a slot that exists but no longer
# unseals - BIOS or Secure Boot changed - does not count). -y -k - is the only working
# non-interactive path on jammy. pcr_ids is not optional: without it the key unseals in ANY
# boot state.
if ! unseals; then
  STALE="$(pinned)"        # sealed to a PCR state this box no longer has (BIOS/Secure Boot changed)
  # -y: don't ask, -k -: existing LUKS key from stdin; adds a new LUKS slot + its LUKS2 token
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
unset PASS                                 # done with the key

unseals                                    # prove the TPM releases the key before boot needs it
update-initramfs -u -k all >/dev/null      # clevis hook into every initrd; -k all: a kernel installed but not yet booted needs it too

# ---------------------------------------------------------------- clean up the installer hand-off
# the one-time key leaves the LUKS header, then the disk; the unit stops running.
# Not in the installer: there the key stays for the first-boot check.
if [[ -z "${INSTALL_ROOT-}" && -e "$STAGE/key" ]]; then
  # if the slot can't be removed, keep everything: the unit tries again next boot
  cryptsetup luksRemoveKey "$DEV" "$STAGE/key" \
    || { echo "provision.sh: could not remove the one-time key slot, will retry (cryptsetup luksDump $DEV)" >&2; exit 1; }
  rm -f "$STAGE/key" "$STAGE/env" "$STAGE/reboots" /etc/systemd/system/multi-user.target.wants/tpm-provision.service
  rmdir "$STAGE" 2>/dev/null || true
fi
