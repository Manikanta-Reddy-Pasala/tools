# tpm/

Recovery and hardening scripts for TPM 2.0 on Linux — built for the case where a
`tpm2_dictionarylockout` password was set, then lost, and the TPM refuses every
command that would undo it.

Target: Ubuntu / Debian, `tpm2-tools` 4.x or 5.x. Developed and tested on **Ubuntu
22.04 (jammy)** — tpm2-tools 5.2, clevis 18, `libhivex-bin` for the Windows
password recovery — against an **ASUS NUC 15 Pro** (Intel PTT firmware TPM).
Nothing is board-specific except `bios-nuc15-pro.md`.

It also covers the neighbouring question **"`lockoutAuthSet = 1` but nobody set a
password"** — see [`docs/who-set-lockoutauth.md`](docs/who-set-lockoutauth.md). Short
answer: no Linux disk-encryption tool touches the lockout hierarchy, Windows does, and
Windows keeps a copy you can read back.

## The problem these solve

`TPM2_DictionaryAttackParameters` and `TPM2_DictionaryAttackLockReset` are authorized
by the **lockout hierarchy**. When the TPM is in lockout it refuses exactly those
commands — so the fix is gated behind the thing that is broken. Full explanation in
[`docs/lockout-explained.md`](docs/lockout-explained.md).

## Start here

```bash
sudo ./install-deps.sh              # tpm2-tools, once
sudo ./tpm-doctor.sh                # reads state, prints the exact next command
sudo ./paste-me.sh | tee tpm.txt    # one compact block to share when asking for help
```

`paste-me.sh` is read-only and never attempts a password — a failed lockout-auth
attempt restarts the `lockoutRecovery` timer and makes the situation worse.

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
| `08-recover-windows-auth.sh` | no | find out who set `lockoutAuth`, and get it back from Windows |
| `09-clevis.sh` | partly | clevis TPM2 bindings: status / rescue / rebind / unbind / bind / verify |
| `10-ppi-clear.sh` | **YES** (next boot) | ask the firmware to clear the TPM via the TCG Physical Presence Interface |
| `paste-me.sh` | no | compact, chat-pasteable state dump (no secrets, no auth attempts) |
| `decode-rc.sh` | no | explain a TPM return code (`0x921`, `0x184`, …) |
| `99-collect-report.sh` | no | one text file with everything, for sharing |
| `t/selftest.sh` | no | offline test of the parsers — needs no TPM |

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
2. `sudo ./08-recover-windows-auth.sh` — non-destructive, and on an ex-Windows box it
   usually just hands you the password.
3. Full power cycle — shutdown, unplug, hold power 15 s, boot. Clears the lockout
   outright when `lockoutRecovery == 0`.
4. Wait out `lockoutRecovery` idle: `sudo ./02-wait-out-lockout.sh`
5. `sudo ./09-clevis.sh rescue` then `unbind`, if a Clevis binding holds your disk key.
6. `sudo ./01-preflight-safety.sh` then `sudo ./04-clear-tpm.sh`
7. `sudo ./10-ppi-clear.sh` — firmware-side clear. **This is the one for a board with
   no "Clear TPM" menu item**, which includes every Intel PTT NUC.
8. BIOS: Intel PTT off → boot → on. See [`bios-nuc15-pro.md`](bios-nuc15-pro.md)
9. BIOS security jumper → Maintenance Mode. Same doc.

## Clevis

`clevis luks bind` uses the **owner** hierarchy, never the lockout one, so
`lockoutAuthSet = 1` does not block it. What it does block is `05-set-lockout-params.sh`
and `03-clear-lockout.sh`, nothing else.

Two things worth checking on an existing binding:

```bash
sudo ./09-clevis.sh status     # flags a binding with no pcr_ids
sudo ./09-clevis.sh rescue     # reads the passphrase back out, before any TPM clear
```

A config of `'{"pcr_bank":"sha256"}'` with **no `pcr_ids`** seals to nothing. The TPM
hands the key over in any boot state at all — a different kernel, Secure Boot turned
off, an attacker's USB stick. It is not disk encryption at that point, it is a key
printed on the motherboard.

### Fixing an unpinned binding without the passphrase

You do not need the LUKS passphrase to repair this, and you must not unbind first.
The still-working binding *is* the key: `clevis luks pass` asks the TPM to unseal it
and hands you back a full LUKS passphrase for the volume.

```bash
sudo PCR_IDS=7 ./09-clevis.sh rebind
sudo update-initramfs -u -k all
```

`rebind` runs the only safe order — recover the key from the live binding, add a new
PCR-sealed slot, **verify that new slot unseals**, and only then drop the unpinned
ones. It refuses to remove anything if the new slot fails to bind or fails to unseal,
and it refuses to leave fewer than two keyslots. Unbinding first would strand the box
on manual unlock if the rebind then failed.

`bind` is the path for when there is no working binding left to harvest — after a TPM
clear, or on a fresh volume. It prompts for the passphrase rather than taking it on
the command line, because `echo -e "pw" | clevis luks bind ...` leaves your disk
passphrase in shell history and, briefly, in `/proc/<pid>/cmdline`.

### Two clevis traps this hit for real

`clevis luks pass --help` **exits 1 even where the subcommand exists** — the
subcommands parse with `getopts ":d:s:"`, so `--help` is not a flag and falls into
`usage()`. Probing with it reports Ubuntu 22.04's perfectly good clevis 18 as "too
old". `--summary` is the argument every clevis subcommand handles and exits 0 on.

`clevis luks bind` without `-k -` reads the passphrase with an unguarded
`IFS= read -r -s -p ...` inside a `#!/bin/bash -e` script. Pipe it a key whose last
line has no newline and `read` returns 1 at EOF, killing clevis before it binds
anything. `-k -` is the guarded, documented non-interactive path.

## Afterwards

```bash
sudo RECOVERY=0 ./05-set-lockout-params.sh
```

`lockoutRecovery = 0` keeps brute-force protection but guarantees a power cycle
always gets you out. Firmware defaults of 24 h are what turn a typo into a day of
downtime.

## Tests

```bash
./t/selftest.sh
```

Runs the `properties-variable` parser, `human_secs`, the return-code decoder and the
auth-argument builder against recorded `tpm2_getcap` fixtures. No TPM required, so it
works on any machine — 27 assertions.

## Notes

- Scripts need bash 4+ (`mapfile`, `${x,,}`). Ubuntu is fine; macOS `/bin/bash` 3.2 is
  not — run them on the target machine.
- Reading `/dev/tpmrm0` needs root or membership of the `tss` group. The scripts warn
  when the device is present but not accessible.
- TCTI is auto-detected: `/dev/tpmrm0`, then `/dev/tpm0`, then `tabrmd`. Override with
  `TPM2TOOLS_TCTI=...`.
- No script writes a password to disk or to the report.
