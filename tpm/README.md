# TPM + LUKS auto-unlock on NUCs — runbook

How to set the TPM lockout parameters and bind disk auto-unlock to the TPM, on a **new**
NUC and on one that is **already configured**. Two scripts do all of it:

| Script | Use it on | What it does |
|---|---|---|
| [`provision.sh`](provision.sh) | **New system**, or any box whose `lockoutAuthSet` is `0` | Sets the lockout parameters, binds clevis sealed to PCR 7, proves the TPM releases the key, rebuilds and checks the initramfs. One run, no reboot needed. |
| [`tpmfix.sh`](tpmfix.sh) | **Already configured system** whose `lockoutAuthSet` is `1` (the parameters are refused), or a box that stops at `(initramfs)` | Two phases with a reboot between: clears the TPM safely, then does everything `provision.sh` does, plus repairs the boot unlock path. |

Target: Ubuntu 22.04, Intel PTT firmware TPM (ASUS NUC 15 Pro). Both scripts are single
files with no dependencies on each other or on anything else in this repo.

**These are offline tools. Neither script installs anything** — no `apt-get`, no network.
Everything they need must already be in the image; a missing piece is named and the run stops.

### Prerequisites — bake into the image

```
tpm2-tools  cryptsetup-bin  util-linux  dmsetup  initramfs-tools
clevis  clevis-luks  clevis-tpm2  clevis-initramfs
```

Check a box in one line (every one of these must print a path, and the hook must exist):

```bash
for c in tpm2_getcap tpm2_dictionarylockout clevis clevis-luks-bind clevis-encrypt-tpm2 \
         cryptsetup blkid dmsetup findmnt awk find update-initramfs unmkinitramfs; do
  command -v "$c" >/dev/null || echo "MISSING: $c"
done
[ -e /usr/share/initramfs-tools/hooks/clevis ] || echo "MISSING: clevis-initramfs hook"
```

Silence means the box is ready. (`command -v a b c` is no good here — it exits 0 while a name
in the middle is missing.)

---

## 1. Get the scripts onto the box

The box has no network, so copy them across — `scp` from a jump host, or a USB stick:

```bash
scp provision.sh tpmfix.sh user@nuc:/tmp/      # from a machine that does have the repo
```

then on the NUC: `cd /tmp && chmod +x provision.sh tpmfix.sh`.

## 2. Decide which script — always look first

```bash
sudo ./tpmfix.sh --status         # read-only, changes nothing (provision.sh takes no arguments)
```

Read the `lockoutAuthSet` line:

| `lockoutAuthSet` | Meaning | Run |
|---|---|---|
| `0` | TPM accepts new lockout parameters | **§3 `provision.sh`** — new or already configured, same command |
| `1` | Someone set the lockout password (Windows does this on its first boot). The TPM refuses new parameters until it is cleared. | **§4 `tpmfix.sh`** |

Also look for these warnings in the same output:

- `<-- NO pcr_ids` — a binding made with the old command. It unseals in any boot state. `tpmfix.sh` removes it; `provision.sh` only adds a pinned slot beside it.
- `crypttab unlocks through ... keyscript` — boot does **not** use clevis, and if that script ever fails there is no passphrase prompt. See [§7](#7-why-it-is-done-this-way).

---

## 3. New system (or `lockoutAuthSet` = 0) — `provision.sh`

Five commands in a file. It prints nothing, checks nothing beyond what the commands
themselves enforce, and exits non-zero the moment one of them fails.

```bash
read -rs LUKS_PASS && export LUKS_PASS
sudo --preserve-env=LUKS_PASS ./provision.sh
unset LUKS_PASS
```

What it runs, in this order:

1. `tpm2_dictionarylockout --setup-parameters` — `max-tries=32`, `recovery-time=60`,
   `lockout-recovery-time=60`. First, because the TPM only accepts them while
   `lockoutAuthSet` is `0`. **If it is `1` this command fails and the script stops here
   having bound nothing — run [`tpmfix.sh`](#4-already-configured-system-lockoutauthset--1).**
2. `clevis luks bind … tpm2 '{"pcr_bank":"sha256","pcr_ids":"7"}'` — skipped when a pinned slot
   already **unseals**, so re-running is safe and asks for nothing; a slot that exists but no
   longer unseals (BIOS or Secure Boot changed) does not count and is re-bound beside. `pcr_ids`
   is not optional: without it the key unseals in **any** boot state. Once the new slot is proven,
   the slots that no longer unseal are unbound — left in place they would release the key again if
   that old firmware state ever came back. `pcr_bank` is `sha256` when the TPM has that bank
   allocated, else `sha1` — some Dell servers ship with SHA-1 only, and sealing to the empty
   sha256 bank fails with `pcr-input-file filesize does not match pcr set-list`. Neither bank
   holds PCR 7 → `provision.sh` exits 2. Check with `tpm2_getcap pcrs`; prefer switching the BIOS
   to SHA-256 (Dell: System Security → TPM Advanced Settings → TPM2 Algorithm Selection). Switching
   banks after binding means the slot no longer unseals; re-run the script and it re-binds.
3. `clevis luks pass` again — proves the TPM releases the key before a boot depends on it.
4. `update-initramfs -u -k all` — every kernel, because one installed but not yet booted needs
   the clevis hook too.

`DEV` defaults to the only `crypto_LUKS` partition; on a box with more than one, `blkid` returns
them all and the run fails — set `DEV` explicitly there. `MAXTRIES`, `RECOVERY_TIME`, `LOCKOUT_RECOVERY_TIME`, `PCR_IDS` and `PCR_BANK` override
the values above.

**What it deliberately does not do** — run `tpmfix.sh --status` (or the commands in
[§6](#6-verify-after-the-reboot)) if you want any of it checked:

- it does not look at `/etc/crypttab`, so a `keyscript=` entry or a live dm name that disagrees
  with it is not caught — and either means the initrd cannot unlock the disk;
- it does not unpack the new initrd, so `update-initramfs` returning 0 is all you know;
- it does not remove a binding that has no `pcr_ids` (only stale PCR-pinned ones);
- it says nothing on failure beyond the exit status. Re-run the failing command by hand to see
  the error.

Reboot once **at the machine**, never remotely, and keep the LUKS passphrase: after a BIOS or
Secure Boot change the TPM will (correctly) refuse and boot will ask for it.

---

## 4. Already configured system (`lockoutAuthSet` = 1) — `tpmfix.sh`

```bash
sudo ./tpmfix.sh --status          # read-only
sudo DRY=1 ./tpmfix.sh             # prints every change, makes none
```

### Phase 1 — clear the TPM

```bash
sudo ./tpmfix.sh
```

- Asks for the LUKS passphrase and **refuses to go on unless it opens the disk** (after
  the clear, that passphrase is your only way in until phase 2).
- If `/etc/crypttab` unlocks through a TPM keyscript, switches boot to the normal
  passphrase prompt first, and records which keyslot dies with the clear.
- Asks you to type `CLEAR MY TPM AND DESTROY ITS KEYS`.
- Removes clevis bindings, rebuilds and checks the initramfs, then queues a TPM clear
  through the firmware (PPI).

> **Warning — Intel PTT does not ask.** On these NUCs the firmware clears the TPM on the
> next boot with **no confirmation screen**. The reboot is the point of no return.
> To back out before rebooting: `echo 0 | sudo tee /sys/class/tpm/tpm0/ppi/request`

```bash
sudo reboot                        # at the machine, with a keyboard
```

The next boot asks for the LUKS passphrase — expected.

### Phase 2 — finish

```bash
sudo ./tpmfix.sh                   # same command; it detects phase 2 by itself
```

1. Repairs the boot unlock path: removes a TPM `keyscript=` from `/etc/crypttab`
   (backup kept next to it), and renames the open disk mapping if it does not match
   crypttab (see [§7](#7-why-it-is-done-this-way)).
2. Lockout parameters `32 / 60 / 60`.
3. clevis bind sealed to PCR 7, proven to unseal; removes bindings with no `pcr_ids`.
4. `update-initramfs`, then checks the new initrd can unlock the disk.

Reboot only when it ends with `DONE`.

---

## 5. Box stops at `(initramfs)` on every boot

At the `(initramfs)` prompt:

```sh
blkid | grep crypto_LUKS                          # find the partition, e.g. /dev/nvme0n1p3
cryptsetup open /dev/nvme0n1p3 dm_crypt-0         # use the NAME from /etc/crypttab
lvm vgchange -ay
exit
```

Then, once booted: `sudo ./tpmfix.sh` (it is in phase 2 and repairs the boot path).
If you opened it under another name, `tpmfix.sh` renames it; by hand it is
`sudo dmsetup rename <name-you-used> dm_crypt-0`.

---

## 6. Verify after the reboot

```bash
sudo ./tpmfix.sh --status
sudo tpm2_getcap properties-variable | grep -E 'lockoutAuthSet|inLockout|MAX_AUTH_FAIL|LOCKOUT_INTERVAL|LOCKOUT_RECOVERY'
sudo clevis luks list -d /dev/nvme0n1p3            # expect "pcr_ids":"7"
```

Expected: `TPM2_PT_MAX_AUTH_FAIL: 0x20` (32), `TPM2_PT_LOCKOUT_INTERVAL: 0x3C` (60),
`TPM2_PT_LOCKOUT_RECOVERY: 0x3C` (60), and the machine booted without asking for the passphrase.

---

## Settings

Both scripts read the same environment variables:

| Variable | Default | `tpm2_dictionarylockout` flag | Meaning |
|---|---|---|---|
| `MAXTRIES` | `32` | `--max-tries` | Wrong-auth attempts before the TPM locks out |
| `RECOVERY_TIME` | `60` | `--recovery-time` | Seconds until one failure is forgiven |
| `LOCKOUT_RECOVERY_TIME` | `60` | `--lockout-recovery-time` | Seconds before the lockout password may be tried again after a failure (`0` = only after a reboot) |
| `PCR_IDS` | `7` | — | PCR the disk key is sealed to (7 = Secure Boot state) |
| `DEV` | the only `crypto_LUKS` partition | — | LUKS partition, if there is more than one |
| `LUKS_PASS` | — | — | `provision.sh`: **required**, it never prompts. `tpmfix.sh` still asks |
| `DRY` | `0` | — | `tpmfix.sh` only: `1` prints changes instead of making them |

Example: `sudo MAXTRIES=10 RECOVERY_TIME=120 ./provision.sh`

---

## Command reference

What the scripts run, for doing it — or checking it — by hand.

**Read state (all read-only)**

```bash
sudo tpm2_getcap properties-variable                 # lockoutAuthSet, inLockout, DA params
sudo clevis luks list -d /dev/nvme0n1p3              # bindings and their pcr_ids
sudo cryptsetup luksDump /dev/nvme0n1p3              # keyslots and tokens
cat /etc/crypttab                                    # how boot unlocks the disk
sudo dmsetup ls --target crypt                       # name the disk is open under now
cat /sys/class/tpm/tpm0/ppi/tcg_operations           # firmware clear ops; status 4 = no prompt
cat /sys/class/tpm/tpm0/ppi/request /sys/class/tpm/tpm0/ppi/response
```

**Lockout parameters** (only while `lockoutAuthSet` is `0`)

```bash
sudo tpm2_dictionarylockout --setup-parameters \
  --max-tries=32 --recovery-time=60 --lockout-recovery-time=60
sudo tpm2_dictionarylockout --clear-lockout          # leave an active lockout (empty lockoutAuth)
```

**Bind, check, remove**

```bash
DEV=$(blkid -t TYPE=crypto_LUKS -o device)
printf '%s' "$LUKS_PASS" | sudo clevis luks bind -y -k - -d "$DEV" tpm2 '{"pcr_bank":"sha256","pcr_ids":"7"}'
sudo clevis luks pass -d "$DEV" -s 1 >/dev/null && echo "slot 1 unseals"
sudo clevis luks unbind -d "$DEV" -s 1 -f
sudo update-initramfs -u -k all
```

**Clear the TPM through the firmware** (irreversible — use `tpmfix.sh`, which checks first)

```bash
echo 5 | sudo tee /sys/class/tpm/tpm0/ppi/request    # queue: next boot clears, no prompt on PTT
echo 0 | sudo tee /sys/class/tpm/tpm0/ppi/request    # cancel before rebooting
```

**Check what the next boot will run**

```bash
d=$(mktemp -d) && sudo unmkinitramfs /boot/initrd.img-$(uname -r) "$d"
sudo cat "$d"/main/cryptroot/crypttab                # must list the crypttab name, no keyscript
ls "$d"/main/scripts/local-top/ | grep clevis        # clevis auto-unlock hook
```

**Remove a dead keyslot** (only once auto-unlock works and you still have the passphrase)

```bash
sudo cryptsetup luksKillSlot /dev/nvme0n1p3 <slot>
```

---

## 7. Why it is done this way

- **Lockout parameters first.** `tpm2_dictionarylockout` is authorised by the TPM's
  lockout password. While it is empty, anyone with root can set the parameters. Windows
  sets it on first boot (and calls it the "TPM owner password"), after which the only
  reset is a TPM clear — which destroys every key sealed to the TPM. On a new box nothing
  is sealed yet, so that is the moment to set them.
- **`"pcr_ids":"7"`.** The old command `clevis luks bind ... tpm2 '{"pcr_bank":"sha256"}'`
  seals to no boot state: the TPM hands the disk key to any kernel, Secure Boot on or off.
  With PCR 7 it is released only in the same Secure Boot state. After a BIOS or Secure
  Boot change the TPM will refuse and boot asks for the passphrase — by design; keep it.
- **`-k -` and `printf`.** The documented way to pass the passphrase on stdin. Without `-k -`,
  clevis reads it with an unguarded `read`; `echo -e` only works because it adds a newline.
- **crypttab `keyscript=`.** With a keyscript, Ubuntu's `cryptroot` runs it three times
  and then gives up — there is **no passphrase prompt as a fallback**, so any unseal
  failure (TPM clear, BIOS change) means `(initramfs)` on every boot. clevis cannot help
  either: it answers the passphrase prompt, which a keyscript entry never shows. The
  plain `none luks` entry plus `clevis-initramfs` auto-unlocks normally and falls back to
  the prompt.
- **Name the disk is open under.** `update-initramfs` finds the root disk's crypttab entry
  by the name it is open under right now. Unlocking by hand as anything other than the
  crypttab name gives `cryptsetup: WARNING: target '<name>' not found in /etc/crypttab`
  and an initrd that cannot unlock the disk at all. Both scripts check the new initrd
  before telling you to reboot, and `tpmfix.sh` renames the mapping.
- **Intel PTT clears silently.** Every clear opcode reports status 4 ("user not
  required") in `/sys/class/tpm/tpm0/ppi/tcg_operations`, so there is no confirm screen.

---

## Tests

Run on a Linux box, not on the NUC being fixed.

```bash
bash t/tpmfix-test.sh               # crypttab repair, keyslots, initrd checks (no root, no TPM)
sudo bash t/tpmfix-test.sh          # + real dm-crypt mapping renamed while mounted
sudo bash t/swtpm-e2e-test.sh       # provision.sh + tpmfix.sh phase 2 against a software TPM
```

`swtpm-e2e-test.sh` needs docker. It runs real Ubuntu 22.04 `tpm2-tools`, `clevis` and
`cryptsetup` against `swtpm`, exposed through the kernel's vTPM proxy and mounted over
`/dev/tpmrm0` inside the container only — the host's TPM is never used.
