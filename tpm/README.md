# TPM + LUKS auto-unlock — runbook

Ubuntu 22.04 on ASUS NUC 15 Pro (Intel PTT) and Dell servers. Disk unlocks at boot through
clevis, sealed to PCR 7 (the Secure Boot state), with a passphrase fallback.

| Script | Run it when | Does |
|---|---|---|
| [`provision.sh`](provision.sh) | `lockoutAuthSet` = `0` (new box, or configured but never touched by Windows) | PCR bank check → lockout parameters → clevis bind to PCR 7 → proves unseal → `update-initramfs`. One run, no reboot. |
| [`tpmfix.sh`](tpmfix.sh) | `lockoutAuthSet` = `1`, or every boot stops at `(initramfs)` | Phase 1 clears the TPM (reboot), phase 2 does what `provision.sh` does and repairs the boot unlock path. |

Both are single offline files: no `apt-get`, no network. `tpmfix.sh` names any missing tool;
`provision.sh` checks nothing and just fails on the first command that is missing
(a missing `tpm2_pcrread` is named).

---

## 1. Standard (apply the same way on every box)

| Decision | Our setting | Why |
|---|---|---|
| Seal to | clevis `tpm2`, `pcr_ids` **7** | Released only in the same Secure Boot state. No `pcr_ids` = released to any kernel. |
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
| `lockoutAuthSet 1` | Lockout password set (Windows) | §5 `tpmfix.sh` |
| `pcr bank sha1` / warning | No SHA-256 bank | Switch BIOS to SHA-256 first |
| `<-- NO pcr_ids` | Old binding, unseals in any state | `tpmfix.sh` removes it; `provision.sh` only adds a pinned one |
| `keyscript ... <-- boot unlock depends on this script` | Boot has no passphrase fallback | `tpmfix.sh` (see §8) |

---

## 4. `lockoutAuthSet` = 0 — `provision.sh`

```bash
read -rs LUKS_PASS && export LUKS_PASS
sudo --preserve-env=LUKS_PASS PCR_BANK=sha256 ./provision.sh
unset LUKS_PASS
```

It runs, in order:

1. Picks the PCR bank. It exits `2` if PCR 7 can't be read from the requested bank or
   (with no `PCR_BANK` set) from sha256 or sha1. An all-zero or all-F value counts as unreadable.
2. `tpm2_dictionarylockout --setup-parameters` 32/60/60. Fails if `lockoutAuthSet` is 1 → nothing bound.
3. `clevis luks bind -y -k - … tpm2 '{"pcr_bank":"…","pcr_ids":"7"}'`. This is skipped if a pinned
   slot already unseals, so re-runs are safe. A pinned slot that no longer unseals is rebound. The
   stale slot is removed only after the new one is proven.
4. `clevis luks pass` — proves the TPM releases the key.
5. `update-initramfs -u -k all`.

Exit 0 = done; `2` = PCR bank problem; `64` = it was given arguments; anything else = the command
that failed (normal output is silenced; its error message still shows).
It does **not** check crypttab, unpack the initrd, or remove unpinned bindings. Use
`tpmfix.sh --status` for those.

Reboot once **at the machine**.

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
