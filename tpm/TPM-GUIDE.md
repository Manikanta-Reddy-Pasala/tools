# TPM Disk Auto-Unlock — Best Practices and How-To

**Applies to:** Ubuntu 22.04 on ASUS NUC 15 Pro and Dell servers
**Scripts:** `provision.sh`, `tpmfix.sh` (repo `tools`, folder `tpm/`). The full runbook is in `README.md`.

---

## What this does

Each box's disk is encrypted with LUKS. At boot, the TPM chip hands over the disk key
automatically, so nobody has to type a passphrase. It does this only when the machine
boots in the expected Secure Boot state. If anything about that state changes, the TPM
refuses, and the box asks for the LUKS passphrase instead.

---

## Recommended TPM settings

| Setting | Value | Why |
|---|---|---|
| Seal the disk key to | **PCR 7** | PCR 7 records the Secure Boot state. The key is released only when Secure Boot matches what it was at setup. Without a PCR, any boot, including an attacker's USB stick, gets the key. |
| PCR bank | **SHA-256** | SHA-1 is outdated. Choose the bank in BIOS **before** setup; removing it later breaks the seal. |
| Max failed attempts | **32** | This matches Windows. Every boot uses the TPM, and power cuts count as failures, so a low number would lock boxes after a few outages. |
| Recovery time | **60 s** | One failure is forgotten every 60 seconds while the box is powered on. A locked TPM blocks auto-unlock, so we want it to heal fast. Windows uses 600 s. |
| Lockout recovery time | **60 s** | Wait time after a wrong lockout password. A value of `0` would mean "until reboot". |
| Owner password | **Leave empty** | clevis, the unlock tool, cannot use an owner password. Setting one breaks auto-unlock. |
| Lockout password | Empty today; if set, **different on every box** and stored in the vault | One shared password leaks the whole fleet. An empty one lets root reset a lockout, which is acceptable here. |
| Endorsement key / EPS | **Don't touch** | Disk unlock doesn't use it. Changing the EPS invalidates the vendor certificate. |
| LUKS passphrase | **Keep one per box, in the vault** | It is the fallback whenever the TPM refuses. Without it, the data is lost. |

---

## Best practices

1. **Set up once, the same way everywhere.** Run `provision.sh` on every box with the same values.
2. **Set BIOS first:** TPM on, SHA-256 bank, Secure Boot as it will stay. Then run the script.
3. **Shut down cleanly.** Power cuts add lockout failures.
4. **After a BIOS, firmware or Secure Boot change, reseal.** Re-run `provision.sh`. A passphrase
   prompt after such a change is expected, not an attack.
5. **Never clear the TPM as a first fix.** A clear destroys the sealed key. Use `tpmfix.sh`, which
   checks the passphrase first.
6. **Reboot at the machine**, not remotely, the first time after any TPM change.
7. **Don't install Windows first.** Windows sets a lockout password we don't know, which later
   forces a TPM clear.

---

## How to use the scripts

### Before you start

The box needs these packages (the scripts install nothing):
`tpm2-tools cryptsetup-bin util-linux dmsetup initramfs-tools clevis clevis-luks clevis-tpm2 clevis-initramfs`

Copy both scripts to the box, for example with `scp` or a USB stick, then run
`chmod +x provision.sh tpmfix.sh`.

### Step 1 — Check the box (read-only)

```bash
sudo ./tpmfix.sh --status
sudo tpm2_getcap pcrs          # sha256 should list PCR 7
```

Look at `lockoutAuthSet`:

| `lockoutAuthSet` | Meaning | Next step |
|---|---|---|
| `0` | Normal / new box | **Step 2A** |
| `1` | A lockout password was set, usually by Windows | **Step 2B** |

If the output shows `pcr bank sha1`, switch the BIOS to SHA-256 first.
On Dell, the setting is *System Security → TPM Advanced Settings → TPM2 Algorithm Selection*.

### Step 2A — New or normal box: `provision.sh`

```bash
read -rs LUKS_PASS && export LUKS_PASS          # type the disk passphrase (not shown)
sudo --preserve-env=LUKS_PASS PCR_BANK=sha256 ./provision.sh
unset LUKS_PASS
```

- Exit code `0` means done. The script is quiet by design.
- It is safe to re-run. If auto-unlock already works, it changes nothing.
- It sets the lockout values, seals the key to PCR 7, proves the TPM releases the key, and updates boot.

### Step 2B — `lockoutAuthSet` = 1: `tpmfix.sh` (two runs, one reboot)

```bash
sudo DRY=1 ./tpmfix.sh         # optional: shows what it would do
sudo ./tpmfix.sh               # phase 1: checks passphrase, asks you to confirm, schedules a TPM clear
sudo reboot                    # at the machine - boot will ask for the passphrase (expected)
sudo ./tpmfix.sh               # phase 2: sets values, seals to PCR 7, repairs boot
```

> **Warning:** On NUCs (Intel PTT) the TPM is cleared on the next boot **without any
> confirmation screen**. To cancel before rebooting, run
> `echo 0 | sudo tee /sys/class/tpm/tpm0/ppi/request`.

Reboot only when phase 2 ends with `DONE` and no failed steps.

### Step 3 — Verify

```bash
sudo ./tpmfix.sh --status
sudo clevis luks list -d "$(blkid -t TYPE=crypto_LUKS -o device)"   # expect "pcr_bank":"sha256","pcr_ids":"7"
```

Then reboot. The box should start without asking for the passphrase.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Boot asks for the passphrase | BIOS / Secure Boot changed, or the TPM is locked out | Type the passphrase, then re-run `provision.sh`. If locked out: `sudo tpm2_dictionarylockout --clear-lockout` |
| Every boot stops at `(initramfs)` | Boot path broken | At the prompt: `cryptsetup open <luks-partition> dm_crypt-0`, `lvm vgchange -ay`, `exit`. Then run `sudo ./tpmfix.sh` |
| `pcr-input-file filesize does not match pcr set-list` | TPM has no SHA-256 bank (seen on Dell) | Set SHA-256 in BIOS and re-run |
| `provision.sh` exits `2` | No usable PCR bank, or `tpm2_pcrread` missing | Check `tpm2_getcap pcrs` and the BIOS setting |
| Parameters refused (`provision.sh` fails at the start) | `lockoutAuthSet` = 1 | Use `tpmfix.sh` |

---

## Why we chose these settings

- **PCR 7 only.** It locks the key to the Secure Boot setup, which blocks booting another OS to
  steal the key. Routine kernel and GRUB updates normally don't change it, so patching doesn't
  trigger passphrase prompts. Secure Boot key or revocation-list (dbx) updates can change it.
- **32 tries / 60 s.** Our boxes lose power unexpectedly. Each unclean shutdown can count as a
  failure, and a locked TPM stops auto-unlock. We tested this on a software TPM: while locked
  out, the key load was refused, and after a lockout reset it worked. 32 gives room for several
  outages; 60 s heals quickly.
- **No owner password.** Required by clevis. We checked the Ubuntu 22.04 package: it always uses
  an empty owner password.
- **SHA-256.** Current standard. The scripts fall back to SHA-1 only when the TPM has nothing
  else, and fleet runs pass `PCR_BANK=sha256` to refuse even that.
- **Clearing only through `tpmfix.sh`.** A clear is irreversible. The script first proves you can
  open the disk with the passphrase, and keeps boot working in the meantime.
