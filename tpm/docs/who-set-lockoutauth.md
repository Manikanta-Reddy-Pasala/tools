# "`lockoutAuthSet = 1` but nobody set a password"

## It was not your disk encryption

`clevis luks bind ... tpm2` and `systemd-cryptenroll --tpm2-device` both work entirely
in the **owner** (storage) hierarchy: `TPM2_CreatePrimary -C o`, then seal, then
unseal. Neither ever calls `TPM2_HierarchyChangeAuth` on the lockout hierarchy. The
same is true of `tpm2-pkcs11`, `ssh-tpm-agent` and `fwupd`.

So a Linux-only machine that has only ever run `clevis luks bind` cannot arrive at
`lockoutAuthSet = 1` on its own.

## It was almost certainly Windows

Windows calls the TPM 2.0 **lockout** hierarchy "the TPM owner password" — the naming
is Windows', not the TCG's, and it is the whole source of the confusion. Windows
auto-provisions the TPM on first boot, generates a random lockout auth, and stores it
base64-encoded at:

```
HKLM\SYSTEM\CurrentControlSet\Services\TPM\WMI\Admin  ->  OwnerAuthFull
```

The tell is the flag combination:

| ownerAuthSet | endorsementAuthSet | lockoutAuthSet | reading |
|---|---|---|---|
| 0 | 0 | **1** | Windows auto-provisioning. Password is recoverable. |
| 1 | 1 | 1 | full ownership taken — old `tpm2_takeownership`, a management agent, or BIOS provisioning |
| 0 | 0 | 0 | untouched |

Recover it:

```bash
sudo ./08-recover-windows-auth.sh          # reads it out of the registry hive
sudo ./08-recover-windows-auth.sh --try    # and spends one auth attempt on it
```

`--try` refuses to run when `inLockout = 1`, or when fewer than two failed attempts
remain before lockout. A wrong guess costs a counter increment; while in lockout it
costs a full `lockoutRecovery` window, restarted.

From Windows itself, as Administrator:

```powershell
(Get-Tpm).OwnerAuth
```

## How much does it actually cost you?

`lockoutAuth` authorises exactly two commands:

- `TPM2_DictionaryAttackParameters` — set `maxTries` / `lockoutInterval` / `lockoutRecovery`
- `TPM2_DictionaryAttackLockReset` — reset the failure counter

Nothing else. Sealing, unsealing, PCR policies, LUKS auto-unlock, attestation, key
creation — all owner or endorsement hierarchy, all unaffected. If you do not need to
tune the DA parameters, an unknown lockout password is an annoyance, not damage, and
wiping the TPM to clear it is a bad trade.

The reason to care is the second-order one: with an unknown `lockoutAuth` you cannot
set `lockoutRecovery = 0`, so if you ever *do* get into lockout, you are stuck waiting
out whatever the firmware default is — commonly 24 hours.

## If Windows is gone

The password went with the registry hive. Then the only reset is `TPM2_Clear`, in
this order of preference:

1. `sudo ./10-ppi-clear.sh` — firmware does it on the next boot, no password needed,
   works while in lockout, works with no BIOS menu item
2. `sudo ./04-clear-tpm.sh` — only if `phEnable = 1`
3. BIOS PTT off/on — [`../bios-nuc15-pro.md`](../bios-nuc15-pro.md)

Rescue anything sealed to the TPM **first**: `sudo ./09-clevis.sh rescue`.
