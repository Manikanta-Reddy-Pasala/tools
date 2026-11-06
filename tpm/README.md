# TPM + LUKS auto-unlock — runbook

Short Confluence-ready version: [TPM-GUIDE.md](TPM-GUIDE.md).

Ubuntu 22.04 on ASUS NUC 15 Pro (Intel PTT) and Dell servers. Disk unlocks at boot through
clevis, sealed to PCR 7 (the Secure Boot state), with a passphrase fallback.

| Script | Run it when | Does |
|---|---|---|
| [`provision.sh`](provision.sh) | Fresh install: on the installed system, or from autoinstall `late-commands` (hands off to a first-boot unit, §4a) | PCR bank check → clears DA lockout → lockout parameters → clevis bind to PCR 7 → proves unseal → `update-initramfs`. If Windows left `lockoutAuthSet`/`ownerAuthSet` = `1` it queues a PPI clear (exit 10): reboot, run again. |
| [`tpmfix.sh`](tpmfix.sh) | `lockoutAuthSet` = `1`, or every boot stops at `(initramfs)` | Phase 1 clears the TPM (reboot), phase 2 does what `provision.sh` does and repairs the boot unlock path. |

Both are single offline files: no `apt-get`, no network. `tpmfix.sh` names any missing tool;
`provision.sh` checks nothing and just fails on the first command that is missing
(a missing `tpm2_pcrread` is named).

---

## 1. Standard (apply the same way on every box)

| Decision | Our setting | Why |
|---|---|---|
| Seal to | clevis `tpm2`, `pcr_ids` **7** | Released only in the same Secure Boot state. No `pcr_ids` = released to any kernel. Needs **Secure Boot on** to mean anything (§4b). |
| PCR bank | **SHA-256** | Set it in BIOS **before** sealing — removing the sealed bank later breaks every seal (adding one does not). Scripts fall back to SHA-1 only if the TPM has nothing else; fleet runs pass `PCR_BANK=sha256` so that fails instead. |
| Lockout parameters | `max-tries 32`, `recovery 60 s`, `lockout-recovery 60 s` | A lockout **blocks boot unlock** (see below). 32 absorbs power cuts; 60 s forgives one per powered-on minute. Set while `lockoutAuth` is empty; set again after any clear (a clear resets them to vendor defaults). |
| Owner (storage) password | **leave empty** | clevis (jammy 18; noble 20 too) creates its primary in the owner hierarchy **with no password** — setting ownerAuth breaks both bind and boot unlock. |
| Lockout password | empty today; if set, **unique per box**, kept in the vault | Empty = root (or the `tss` group) can reset a lockout or clear the TPM. A clear destroys keys but discloses nothing. Never share one value across the fleet. |
| Endorsement | untouched | Not used by disk unlock. Never change the EPS — it invalidates the vendor EK certificate. |
| Recovery | LUKS passphrase kept per box | A BIOS / Secure Boot / firmware change makes the TPM refuse — by design. Re-run `provision.sh` to reseal; never clear the TPM as a first fix. |

Facts behind those choices:

- **A dictionary-attack lockout blocks disk unlock.** The sealed key itself is `noda`, but clevis
  loads it under a primary key created with default attributes, and that primary is **not**
  `noda` (jammy `clevis-tpm2_18`). While the TPM is in lockout, that load fails. Boot then falls
  back to the passphrase. Clear the lockout with `tpm2_dictionarylockout --clear-lockout`.
  Proven on swtpm with jammy tpm2-tools: in lockout `tpm2_load` fails with "not allowed … DA
  lockout mode"; after `--clear-lockout` the same load and unseal succeed. (Windows BitLocker
  doesn't hit this because its storage key is `noda`.)
- **Power cuts count.** Every boot unlock uses that DA-protected key, so an unclean shutdown
  adds a failure. Use clean shutdowns where possible; 32 tries with 60 s recovery covers the
  rest.
- **Setting PCR banks is a firmware job.** `tpm2_pcrallocate` needs platform auth, which firmware
  holds. Dell: *System Security → TPM Advanced Settings → TPM2 Algorithm Selection* (or racadm / Dell
  Command | Configure across the fleet). Check with `tpm2_getcap pcrs`.
- **Windows sets the lockout password** when it provisions an unowned TPM. It calls this the
  "TPM owner password" and, by default since 1703, keeps it in the registry. Once Windows is gone, the only way to reset
  the parameters is a TPM clear — hence `tpmfix.sh`.
- **A clear** (`TPM2_Clear`) mainly does four things:
  - changes the storage seed, so every sealed key dies;
  - wipes the owner, endorsement and lockout passwords and policies, and the owner/endorsement
    persistent objects and NV indices;
  - resets the lockout parameters to vendor defaults;
  - leaves the endorsement seed unchanged, so the same EK can be recreated.

### Common TPM 2.0 guidance, checked against this setup

| Guidance | Verdict | For us |
|---|---|---|
| Set owner, lockout and endorsement passwords to high-entropy values and keep them in a vault. | **Partly wrong** | **Owner password: never set it.** It breaks clevis bind and unlock. Lockout password: fine if it is **unique per box** and vaulted, never one value for the fleet. Endorsement password: optional; disk unlock doesn't use it. |
| Lockout "laptop" profile: 10–32 tries, recovery of minutes to hours, short lockout-recovery. | **Correct** | We use 32 / 60 s / 60 s. |
| Lockout "server" profile: about 10 tries, a central lockout password, lockout-recovery about 1 s, sometimes no self-healing. | **Not for us** | A lockout blocks boot unlock, so a box that never heals needs a hands-on reset. Couldn't confirm the "TCG profiles" wording. |
| Windows uses 32 tries and 10 minutes. | **Correct** | Microsoft's *TPM fundamentals* page: since Win10 1703, 32 failures, one forgotten every 10 powered-on minutes (1607 and earlier: every 2 hours). A wrong lockout password blocks retries for 24 hours. |
| Raise max tries so power cuts don't lock the TPM. | **Correct** | Every boot unlock uses a lockout-protected key, so unclean shutdowns count. 32 tries plus 60 s recovery covers that. |
| `tpm2_dictionarylockout -s -n 32 -t 600 -l 1 -p ''` | **Valid, matches Windows; not our values** | `-p ''` means an empty lockout password, which contradicts row 1. With `-t 600`, one failure is forgiven every 10 powered-on minutes. We use 60 s because a lockout here blocks boot unlock, so we keep 32/60/60. Check with `tpm2_getcap properties-variable`. |
| Prefer SHA-256 (or SHA-384) PCR banks, not SHA-1 for new seals. | **Correct** | Scripts fall back to SHA-1 only when nothing else exists. Fleet runs set `PCR_BANK=sha256`. |
| Allocate PCR banks before sealing, because changing them breaks seals. | **Correct, with two caveats** | Only *removing* the sealed bank breaks a seal. Allocation needs platform auth, so it is done in BIOS, not by a first-boot script. |
| Keep the storage (owner) hierarchy enabled. | **Correct** | clevis seals there. |
| Endorsement is privacy-sensitive: create the EK, keep endorsement auth, optionally disable endorsement. | **Correct but optional** | Not used for disk unlock. Disabling endorsement from the OS lasts only until the next reboot. |
| Don't change the EPS. | **Correct** | It invalidates the vendor EK certificate. A TPM clear keeps the EPS. |
| Shut down cleanly so the unclean-shutdown counter doesn't rise. | **Correct** | See the power-cut row. |
| After firmware, Secure Boot or bootloader changes, reseal; don't treat PCR drift as lockout. | **Correct** | Re-run `provision.sh`. PCR 7 changes with the Secure Boot state: on/off, key or dbx updates (fwupd can push these), or a boot chain signed by a different certificate. A normal kernel or GRUB update does not change it. |
| Never clear the TPM as a first fix when keys are sealed. | **Correct** | `tpmfix.sh` clears only when `lockoutAuthSet=1` and only after the passphrase is proven. |
| Same first-boot script and same numbers on every box. | **Correct** | That is `provision.sh`. |
| First-boot step: set hierarchy passwords. | **Wrong for us** | Owner password breaks clevis (row 1). |
| First-boot step: allocate PCR banks. | **Wrong layer** | BIOS / racadm, not the OS. |
| First-boot step: create a persistent storage primary and a seal policy. | **Not needed** | clevis recreates its primary on every bind and unlock and writes its own PCR policy. |
| First-boot step: record the EK or attestation identity. | **Optional** | Only needed for fleet attestation; not used today. |

---

## 2. Prerequisites (bake into the image)

```
tpm2-tools cryptsetup-bin util-linux dmsetup initramfs-tools
clevis clevis-luks clevis-tpm2 clevis-initramfs
```

```bash
for c in tpm2_getcap tpm2_pcrread tpm2_dictionarylockout clevis clevis-luks-bind clevis-encrypt-tpm2 \
         cryptsetup blkid dmsetup findmnt awk find update-initramfs unmkinitramfs; do
  command -v "$c" >/dev/null || echo "MISSING: $c"
done
[ -e /usr/share/initramfs-tools/hooks/clevis ] || echo "MISSING: clevis-initramfs hook"
```

Silence = ready. Copy the scripts over (`scp provision.sh tpmfix.sh user@box:/tmp/` or USB), `chmod +x`.

## 3. Look first

```bash
sudo ./tpmfix.sh --status      # read-only
sudo tpm2_getcap pcrs          # sha256 must list PCR 7
```

| Output | Meaning | Do |
|---|---|---|
| `lockoutAuthSet 0` | TPM accepts parameters | §4 `provision.sh` |
| `lockoutAuthSet 1` | Lockout password set (Windows) | §4 `provision.sh` (fresh install: PPI clear, reboot, re-run) or §5 `tpmfix.sh` (box with a keyscript / already in service) |
| `pcr bank sha1` / warning | No SHA-256 bank | Switch BIOS to SHA-256 first |
| `<-- NO pcr_ids` | Old binding, unseals in any state | `tpmfix.sh` removes it; `provision.sh` only adds a pinned one |
| `keyscript ... <-- boot unlock depends on this script` | Boot has no passphrase fallback | `tpmfix.sh` (see §8) |

---

## 4. `provision.sh`

```bash
read -rs LUKS_PASS && export LUKS_PASS
sudo --preserve-env=LUKS_PASS PCR_BANK=sha256 ./provision.sh
unset LUKS_PASS
```

It runs, in order:

1. Picks the PCR bank. It exits `2` if PCR 7 can't be read from the requested bank or
   (with no `PCR_BANK` set) from sha256 or sha1. An all-zero or all-F value counts as unreadable.
2. If `lockoutAuthSet` or `ownerAuthSet` is 1 (Windows left it) it never tries a password (a wrong
   one re-locks the TPM, `0x921`). It proves `LUKS_PASS`, refuses if crypttab has a keyscript or
   another LUKS volume unlocks via the TPM, then queues PPI op 5 (TPM2_Clear) and exits `10`.
   Intel PTT clears on the reboot **with no prompt**, wiping every TPM key (BitLocker too).
   Re-run after the reboot. A clear already pending exits `10` again; a failed one exits `3`.
3. `tpm2_dictionarylockout --clear-lockout`, then `--setup-parameters` 32/60/60 — two calls: jammy's
   tool given both flags only clears and still exits 0. `0x921` (lockout hierarchy locked by an
   earlier wrong password) → exits `75` with the wait (`LOCKOUT_RECOVERY`; 0 = until reboot).
4. `clevis luks bind -y -k - … tpm2 '{"pcr_bank":"…","pcr_ids":"7"}'`. This is skipped if a pinned
   slot already unseals, so re-runs are safe. A pinned slot that no longer unseals is rebound. The
   stale slot is removed only after the new one is proven; a new slot that does not unseal is removed.
5. `clevis luks pass` — proves the TPM releases the key.
6. `update-initramfs -u -k all`.

| Exit | Meaning |
|---|---|
| `0` | done |
| `10` | TPM clear queued (or already pending): reboot, run again |
| `75` | TPM locked (`0x921`): wait the printed seconds powered on, or reboot if it says so; run again |
| `3` | clear the TPM in BIOS (PTT off → boot → on) |
| `2` | setup problem, message says which: PCR bank, LUKS device count, wrong passphrase, keyscript, another TPM-unlocked volume |
| `64` | it was given arguments |
| other | the command that failed (normal output is silenced; its error message still shows) |
It does **not** check crypttab, unpack the initrd, or remove unpinned bindings. Use
`tpmfix.sh --status` for those.

Reboot once **at the machine**.

## 4a. From the installer (autoinstall `late-commands`)

```yaml
late-commands:
  - cp /cdrom/software/provision.sh /target/usr/local/bin/ && chmod +x /target/usr/local/bin/provision.sh
  # passphrase in a file on tmpfs (/run is shared with the chroot): never on a command line
  - install -m 600 /cdrom/software/luks.pass /run/luks.pass; curtin in-target --target=/target -- env LUKS_PASS_FILE=/run/luks.pass /usr/local/bin/provision.sh; rc=$?; rm -f /run/luks.pass; exit $rc
```
The installed system needs the §2 packages (`tpm2-tools clevis clevis-luks clevis-tpm2
clevis-initramfs`) in `packages:`; without them the script stops the install (exit `2`).

What it does in the installer (detected: `/` is not PID 1's root, or `/target` is mounted):

1. checks the passphrase opens the disk and the tools are in the installed system (exit `2` if not);
2. adds a **one-time random key** to a spare LUKS slot, in `/var/lib/tpm-provision/key` (dir 0700, file 0600);
3. writes `/var/lib/tpm-provision/env` (`DEV` by UUID, `STAGE`, `PCR_*` and lockout settings);
4. copies itself to `/usr/local/sbin/tpm-provision` and enables `tpm-provision.service`;
5. **in the `curtin in-target` chroot: binds the TPM right there** and rebuilds the installed
   initrd, the normal §4 steps. With Secure Boot off, PCR 7 holds only firmware settings, so
   the USB boot and the disk boot read the same value; the first boot unlocks with no prompt.
   If any TPM step fails here (TPM clear needed, TPM locked, PTT off, clevis error), it says
   `TPM bind left to the first boot` and still exits `0`: the install never fails over the TPM.
   From the live installer shell (not a chroot) it binds nothing and leaves it all to the first boot.

**First boot**: the unit runs the script with the one-time key. If the installer's slot already
unseals it binds nothing; if this boot reads another PCR 7 (that boot asked for the passphrase
once) it binds again and drops the stale slot. Then it **removes the one-time key slot**, deletes
the key and disables itself. Exit `10` (Windows left a TPM password) reboots for the clear, at
most 3 times; exit `75` retries every 90 s, 5 times. The unit does not hold up boot.

If it fails for good, the one-time key stays (a working LUKS key, inside the encrypted root):
`journalctl -u tpm-provision`, fix, then `sudo systemctl reset-failed tpm-provision && sudo systemctl start tpm-provision`.

Check after the first install: `sudo cryptsetup luksDump <dev>` = passphrase slot + clevis slot
only, and `/var/lib/tpm-provision` is gone. `NO_INSTALLER=1` forces a normal run in a chroot.

## 4b. Secure Boot off

`provision.sh` still binds and the box still auto-unlocks: PCR 7 has a value with Secure Boot
off (it records `SecureBoot = 0` plus the PK/KEK/db/dbx databases). It warns, because with
Secure Boot off whatever boots first runs unchecked and **can reproduce that PCR 7** (replay the
expected events), so any USB stick can unseal the key. The binding then only protects a disk
taken out of the box (the TPM stays behind). No UEFI at all (legacy BIOS boot) also warns.

| Option | Effect | Cost |
|---|---|---|
| **Turn Secure Boot on** (recommended) | PCR 7 also records the keys that verified the boot chain; unsigned media can no longer fake it | Ubuntu's signed shim boots as is; DKMS modules (e.g. nvidia) need MOK enrolment. Turning it on changes PCR 7: the next boot asks for the passphrase once, then run `provision.sh` again (rebinds, drops the stale slot). |
| `PCR_IDS=5,7` | adds the boot disk's partition table (most firmware measures the GPT it boots from) | stops booting another disk only; repartitioning needs a re-run |
| `PCR_IDS=4,7` | adds the boot loader binaries (shim, grub; on newer grub also the kernel) | the next boot after every such update asks for the passphrase until `provision.sh` is re-run. Check `tpm2_eventlog /sys/kernel/security/tpm0/binary_bios_measurements` on one box first |

Neither 4 nor 5 stops the cheapest attack: boot the box's own disk and edit the grub command
line (`break=premount`, `init=/bin/sh`) at the keyboard; the command line and initrd are
measured into PCR 8/9, not 4/5/7. Even with Secure Boot on, a signed Ubuntu live USB reads the
same PCR 7, and Ubuntu does not sign the initrd. PCR 7 auto-unlock stops a stolen disk and
unsigned boot media, not a person with the whole box.

## 5. `lockoutAuthSet` = 1 — `tpmfix.sh`

```bash
sudo DRY=1 ./tpmfix.sh         # prints changes instead of making them (still asks for passphrase + phrase)
sudo ./tpmfix.sh               # phase 1
```

**Phase 1** does the following, in order:

1. Refuses if a crypttab keyscript does not look TPM-based, or if no PCR bank is usable.
2. Checks the LUKS passphrase. It refuses to continue unless the passphrase opens the disk.
3. Checks that the firmware offers a clear opcode.
4. Asks you to type `CLEAR MY TPM AND DESTROY ITS KEYS`.
5. Refuses if removing the clevis bindings would leave no keyslot.
6. Moves boot off any TPM keyscript (crypttab backup kept).
7. Removes the clevis bindings and rebuilds and checks the initrd.
8. Queues a firmware (PPI) clear.

> **Warning — Intel PTT clears on the next boot with no confirmation screen.**
> Back out before rebooting: `echo 0 | sudo tee /sys/class/tpm/tpm0/ppi/request`. If crypttab
> was changed, the script also prints the restore + `update-initramfs` command — run that too.
> The clevis bindings are already removed, so after backing out boot asks for the passphrase.

Reboot at the machine; the next boot asks for the passphrase (expected). Then:

```bash
sudo ./tpmfix.sh               # phase 2, detected automatically
```

**Phase 2** does the following, in order:

1. Repairs crypttab.
2. Sets the lockout parameters to 32/60/60.
3. Binds clevis to PCR 7 and proves it unseals.
4. Removes unpinned bindings.
5. Fixes the mapping name, then rebuilds the initrd and checks it.

Reboot only when it ends with `DONE` **and** exits 0. If it prints `N step(s) above did not
complete`, fix the step it names. The box still boots, most often asking for the passphrase.

## 6. Stuck at `(initramfs)`

```sh
blkid | grep crypto_LUKS                      # e.g. /dev/nvme0n1p3
cryptsetup open /dev/nvme0n1p3 dm_crypt-0     # NAME from /etc/crypttab
lvm vgchange -ay
exit
```

Once booted: `sudo ./tpmfix.sh`. It repairs the boot path and renames the mapping if you used
another name. By hand: `sudo dmsetup rename <name> dm_crypt-0`.

## 7. Verify

```bash
sudo ./tpmfix.sh --status
sudo tpm2_getcap properties-variable | grep -E 'lockoutAuthSet|inLockout|MAX_AUTH_FAIL|LOCKOUT_INTERVAL|LOCKOUT_RECOVERY'
sudo clevis luks list -d "$(blkid -t TYPE=crypto_LUKS -o device)"
```

Expected results:

- `MAX_AUTH_FAIL: 0x20`, `LOCKOUT_INTERVAL: 0x3C`, `LOCKOUT_RECOVERY: 0x3C`.
- The binding shows `"pcr_bank":"sha256","pcr_ids":"7"`.
- The box boots without a passphrase prompt.

---

## Settings (environment, both scripts)

| Variable | Default | Meaning |
|---|---|---|
| `MAXTRIES` | `32` | `--max-tries`: failures before lockout |
| `RECOVERY_TIME` | `60` | `--recovery-time`: seconds (powered on) to forgive one failure |
| `LOCKOUT_RECOVERY_TIME` | `60` | `--lockout-recovery-time`: wait after a wrong lockout password (`0` = until reboot) |
| `PCR_IDS` | `7` | PCRs to seal to |
| `PCR_BANK` | sha256, else sha1 | Set `sha256` on the fleet to forbid the SHA-1 fallback |
| `DEV` | only `crypto_LUKS` partition | Set it when there is more than one |
| `LUKS_PASS` | — | `provision.sh` only: needed when it has to bind (it never prompts) |
| `DRY` | `0` | `tpmfix.sh` only: print instead of change |
| `ALLOW_NO_CLEVIS` | `0` | `tpmfix.sh` only: `1` = repair boot without clevis (passphrase only) |
| `CRYPTTAB` / `STATE` | `/etc/crypttab` / `/var/lib/tpmfix` | `tpmfix.sh` only: paths |

## Command reference

```bash
# state (read-only)
sudo tpm2_getcap properties-variable       # lockoutAuthSet, inLockout, DA params
sudo tpm2_getcap pcrs                      # allocated PCR banks
DEV=$(blkid -t TYPE=crypto_LUKS -o device)
sudo clevis luks list -d "$DEV"            # bindings + pcr_ids
sudo cryptsetup luksDump "$DEV"            # keyslots, tokens
cat /etc/crypttab; sudo dmsetup ls --target crypt
cat /sys/class/tpm/tpm0/ppi/tcg_operations # status 4 = firmware clears with no prompt

# lockout parameters (lockoutAuth empty)
sudo tpm2_dictionarylockout --setup-parameters --max-tries=32 --recovery-time=60 --lockout-recovery-time=60
sudo tpm2_dictionarylockout --clear-lockout

# bind / check / remove
printf '%s' "$LUKS_PASS" | sudo clevis luks bind -y -k - -d "$DEV" tpm2 '{"pcr_bank":"sha256","pcr_ids":"7"}'
sudo clevis luks pass -d "$DEV" -s 1 >/dev/null && echo "slot 1 unseals"
sudo clevis luks unbind -d "$DEV" -s 1 -f
sudo update-initramfs -u -k all

# what the next boot runs
d=$(mktemp -d) && sudo unmkinitramfs /boot/initrd.img-$(uname -r) "$d"
sudo find "$d" -path '*cryptroot/crypttab' -exec cat {} +       # crypttab name, no keyscript
sudo find "$d" -path '*scripts/local-top/*clevis*'              # clevis hook present

# firmware clear (irreversible - prefer tpmfix.sh)
echo 5 | sudo tee /sys/class/tpm/tpm0/ppi/request   # queue
echo 0 | sudo tee /sys/class/tpm/tpm0/ppi/request   # cancel

# dead keyslot (only once auto-unlock works)
sudo cryptsetup luksKillSlot "$DEV" <slot>
```

## 8. Gotchas

These are why the scripts work the way they do.

- **`-k -` with `printf`.** Without `-k -`, clevis reads the passphrase with an unguarded
  `read`. Piped input with no trailing newline then kills the bind.
- **crypttab `keyscript=`.** `cryptroot` runs the keyscript 3 times and then stops, with **no
  passphrase fallback**. clevis only answers the passphrase prompt, so it can't help either.
  Use `none luks` plus `clevis-initramfs`.
- **Mapping name.** `update-initramfs` looks up the crypttab entry by the name the disk is
  open under *now*. A wrong name gives `WARNING: target '<name>' not found in /etc/crypttab`
  and an initrd that can't unlock the disk.
- **Empty PCR bank.** The bind fails with `pcr-input-file filesize does not match pcr set-list`.
  The TPM doesn't have the bank you asked for; see `tpm2_getcap pcrs`.
- **Intel PTT PPI.** Every clear opcode reports status 4 ("user not required"), so the
  clear happens without a prompt.

## Tests

Run these on a Linux test box, never on the box being fixed.

```bash
bash t/tpmfix-test.sh            # crypttab repair, keyslots, initrd checks
sudo bash t/tpmfix-test.sh       # + real dm-crypt rename while mounted
sudo bash t/swtpm-e2e-test.sh    # provision.sh + tpmfix.sh phase 2 against swtpm (docker, vTPM proxy; host TPM untouched)
```
