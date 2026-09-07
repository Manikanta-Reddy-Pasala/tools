# tpm/

Recovery and hardening scripts for TPM 2.0 on Linux — built for the case where a
`tpm2_dictionarylockout` password was set, then lost, and the TPM refuses every
command that would undo it.

Target: Ubuntu / Debian, `tpm2-tools` 4.x or 5.x. Written against an **ASUS NUC 15
Pro** (Intel PTT firmware TPM), but nothing here is board-specific except
`bios-nuc15-pro.md`.

## The problem these solve

`TPM2_DictionaryAttackParameters` and `TPM2_DictionaryAttackLockReset` are authorized
by the **lockout hierarchy**. When the TPM is in lockout it refuses exactly those
commands — so the fix is gated behind the thing that is broken. Full explanation in
[`docs/lockout-explained.md`](docs/lockout-explained.md).

## Start here

```bash
sudo ./install-deps.sh     # tpm2-tools, once
sudo ./tpm-doctor.sh       # reads state, prints the exact next command
```

## Scripts

| Script | Destructive | What it does |
|---|---|---|
| `install-deps.sh` | no | apt install tpm2-tools, tpm2-abrmd, cryptsetup |
| `tpm-doctor.sh` | no | diagnose + recommend the next step |
| `00-status.sh` | no | full lockout state, DA params, what is sealed to the TPM |
| `01-preflight-safety.sh` | no | what a TPM wipe would destroy; exit 2 if risky |
| `02-wait-out-lockout.sh` | no | poll until lockout self-clears |
| `03-clear-lockout.sh` | no | reset the lockout counter (needs lockout auth) |
| `04-clear-tpm.sh` | **YES** | `TPM2_Clear` via lockout, then platform hierarchy |
| `05-set-lockout-params.sh` | no | set maxTries / interval / recovery |
| `06-set-hierarchy-auth.sh` | no | set or clear owner/endorsement/lockout passwords |
| `07-reenroll-luks.sh` | no | re-bind `systemd-cryptenroll` TPM unlock after a clear |
| `decode-rc.sh` | no | explain a TPM return code (`0x921`, `0x184`, …) |
| `99-collect-report.sh` | no | one text file with everything, for sharing |

## Danger

`04-clear-tpm.sh` and the BIOS PTT toggle both run `TPM2_Clear`. That regenerates the
storage and endorsement seeds. **Everything sealed to the TPM is permanently
unrecoverable**: `systemd-cryptenroll --tpm2-device` and Clevis LUKS keys, TPM-backed
SSH/GPG keys, `tpm2-pkcs11` tokens, any persistent handle.

If your root disk auto-unlocks via the TPM, you will not boot afterwards without the
LUKS passphrase. Verify a passphrase keyslot exists *and that you know it* first:

```bash
sudo cryptsetup luksDump /dev/nvme0n1p3
sudo cryptsetup open --test-passphrase /dev/nvme0n1p3 && echo "passphrase OK"
sudo cryptsetup luksHeaderBackup /dev/nvme0n1p3 --header-backup-file luks-header.img
```

`01-preflight-safety.sh` checks all of this and refuses to proceed if it finds a
TPM-only keyslot.

## Recovery order (no lockout password)

1. `sudo ./tpm-doctor.sh`
2. Full power cycle — shutdown, unplug, hold power 15 s, boot. Clears the lockout
   outright when `lockoutRecovery == 0`.
3. Wait out `lockoutRecovery` idle: `sudo ./02-wait-out-lockout.sh`
4. `sudo ./01-preflight-safety.sh` then `sudo ./04-clear-tpm.sh`
5. BIOS: Intel PTT off → boot → on. See [`bios-nuc15-pro.md`](bios-nuc15-pro.md)
6. BIOS security jumper → Maintenance Mode. Same doc.

## Afterwards

```bash
sudo RECOVERY=0 ./05-set-lockout-params.sh
```

`lockoutRecovery = 0` keeps brute-force protection but guarantees a power cycle
always gets you out. Firmware defaults of 24 h are what turn a typo into a day of
downtime.

## Notes

- Scripts need bash 4+ (`mapfile`). Ubuntu is fine; macOS `/bin/bash` 3.2 is not —
  run them on the target machine.
- TCTI is auto-detected: `/dev/tpmrm0`, then `/dev/tpm0`, then `tabrmd`. Override with
  `TPM2TOOLS_TCTI=...`.
- No script writes a password to disk or to the report.
