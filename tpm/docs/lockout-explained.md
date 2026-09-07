# Why a TPM lockout is a one-way door

## The mechanism

A TPM 2.0 defends against password brute force with three parameters:

| Parameter | Meaning |
|---|---|
| `maxAuthFail` | failed auth attempts tolerated before the TPM locks |
| `lockoutInterval` | seconds after which the failure counter drops by one |
| `lockoutRecovery` | seconds the TPM stays locked after a failed **lockoutAuth** attempt |

Failures against ordinary objects bump `lockoutCounter`. Once it reaches
`maxAuthFail`, `inLockout` flips to 1 and the TPM refuses every command that needs
DA-protected authorization.

## The trap

`TPM2_DictionaryAttackLockReset` and `TPM2_DictionaryAttackParameters` — the two
commands that would fix the situation — are themselves authorized by the **lockout
hierarchy**. So:

- In lockout → you cannot reset the lockout.
- Wrong lockout password → `lockoutRecovery` seconds of hard lock, timer restarts on
  every further wrong guess.

That is intentional. Otherwise the lockout would be trivially bypassable.

## The three exits

1. **Time.** Stay idle for `lockoutRecovery`. Any further failed auth restarts it.
2. **Power cycle** — but *only* if `lockoutRecovery == 0`, in which case the lock
   clears on TPM reset. A warm reboot is not always a TPM reset: shut down, unplug,
   hold the power button 15 s, boot.
3. **`TPM2_Clear`** via the platform hierarchy or the firmware setup. Destroys all
   seeds and every key sealed to the TPM.

## Sane parameters for a workstation

```bash
sudo MAXTRIES=32 INTERVAL=7200 RECOVERY=0 ./05-set-lockout-params.sh
```

`RECOVERY=0` keeps brute-force protection (you still get locked after 32 failures)
while guaranteeing a power cycle always gets you back in. `RECOVERY=86400` — a
common firmware default — is what turns a typo into a day of downtime.

## Return codes

| Code | Name | Meaning |
|---|---|---|
| `0x921` | TPM_RC_LOCKOUT | in lockout; wait, power-cycle or clear |
| `0x98e` / `0x9a2` | TPM_RC_AUTH_FAIL | wrong password, counter incremented |
| `0x18b` | TPM_RC_BAD_AUTH | rejected, counter *not* incremented |
| `0x184` | TPM_RC_HIERARCHY | hierarchy disabled (usually `phEnable = 0`) |

`./decode-rc.sh 0x921` prints these locally.
