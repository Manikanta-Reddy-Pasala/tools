# Clearing the TPM on an ASUS NUC 15 Pro (and other fTPM/PTT boxes)

## Why there is no "Clear TPM" button

The NUC 15 Pro has **no discrete TPM chip**. It uses **Intel PTT** (Platform Trust
Technology) — a firmware TPM that lives inside the Management Engine and stores its
state in flash. Vendors that ship a discrete TPM usually expose
`Security → TPM → Pending Operation → TPM Clear`. Firmware-TPM boards typically
do not: the equivalent action is disabling the fTPM, which discards its NV store.

Confirm you are on PTT:

```bash
sudo tpm2_getcap properties-fixed | grep -A2 TPM2_PT_MANUFACTURER
# value: "INTC"   -> Intel PTT (firmware TPM)
# value: "IFX"/"NTC"/"STM"  -> discrete chip, look for a real Clear TPM menu item
```

## Method 0 — ask the firmware to clear it (TCG Physical Presence)

**Try this before touching BIOS menus.** The absence of a "Clear TPM" item does not
mean the firmware cannot clear the TPM — it means it will not do it from a menu. The
Physical Presence Interface is the standard way an OS *requests* the clear: you park
an opcode in firmware-owned NV, reboot, and the firmware puts up its own full-screen
confirmation. It needs no lockout password and it works while `inLockout = 1`,
because the firmware performs `TPM2_Clear` as the platform, not as an authorised user.

Ubuntu 22.04's kernel exposes it at `/sys/class/tpm/tpm0/ppi/`:

```bash
ls /sys/class/tpm/tpm0/ppi/           # version request response transition_action tcg_operations
cat /sys/class/tpm/tpm0/ppi/tcg_operations | grep -iE '^\s*(5|14|21|22):'
sudo ./10-ppi-clear.sh                # queues the request, after the safety check
sudo reboot                           # then ACCEPT the firmware prompt, at the machine
```

**Check whether you get a confirmation screen at all.** `tcg_operations` prints one
line per opcode as `<op> <status>: <text>`, and the status is what matters:

| status | meaning |
|---|---|
| 0 | not implemented |
| 1 | firmware only — the OS cannot request it |
| 2 | blocked for the OS by firmware |
| 3 | allowed, **firmware prompts** for physical presence |
| 4 | allowed, **no prompt** — the reboot clears the TPM silently |

Measured on this hardware, opcodes 5 / 14 / 21 / 22 all report **`4: User not
required`**. So on an Intel PTT NUC there is *no* "are you sure" screen: the moment
you reboot, the TPM is gone. `10-ppi-clear.sh` prints this status and shouts about it
before it writes anything, and it runs `01-preflight-safety.sh` first. Withdraw a
queued request with `sudo ./10-ppi-clear.sh --cancel`.

Where the status is `3` instead, the firmware puts up its own full-screen "A
configuration change was requested to clear the TPM" page and waits for a keypress at
the machine — that one cannot be answered over SSH, and declining it is safe.

If nothing happened at boot, read `/sys/class/tpm/tpm0/ppi/response` afterwards — it
carries the firmware's result code, e.g. `22 0: Success` — and fall through to
Method 1.

## Method 1 — PTT off/on (this is the clear)

> This destroys everything sealed to the TPM. Run `./01-preflight-safety.sh` first
> and make sure you can unlock your disk with a passphrase.

1. `F2` at boot.
2. Switch out of the simplified view if present — `F7` toggles Visual/Advanced mode on
   NUC firmware. You need **Advanced**.
3. Find the setting. Depending on BIOS build it sits at one of:
   - `Advanced → Security → Security Features → Intel Platform Trust Technology`
   - `Advanced → PCH-FW Configuration → PTT Configuration → TPM Device Selection`
   - `Advanced → Trusted Computing → Security Device Support`
4. Set it to **Disabled**.
5. `F10` save and exit. **Let the machine boot all the way into the OS**, then reboot.
   The ME clears its TPM store during that transition — skipping the boot can leave
   the old state intact.
6. `F2` again, set the same option back to **Enabled**. `F10`.
7. Boot, then verify:

```bash
sudo ./00-status.sh
# expect: lockoutAuthSet = 0, inLockout = 0, ownerAuthSet = 0
```

### If the option is greyed out

- A **BIOS supervisor/administrator password** is set: `Security → Administrator
  Password` — clear it first, then the TPM items unlock.
- You are still in Visual/simplified mode — press `F7`.
- Some builds hide the entry until `Advanced → Security → Security Features` is
  entered directly rather than through the summary page.

## Method 2 — BIOS security jumper (Maintenance Mode)

NUC boards carry a yellow **BIOS configuration jumper** on the board. Moving it puts
firmware into Maintenance Mode, which exposes password clearing and TPM/ME options
that are hidden in normal mode.

1. Power off, unplug, hold the power button 15 s.
2. Open the chassis. Locate the 3-pin BIOS jumper (silkscreened `BIOS_CFG` /
   `Security`; check the NUC 15 Pro technical product specification PDF for the exact
   position on your board revision).
3. Move it from pins 1-2 (Normal) to the maintenance position, or remove it entirely.
4. Power on. The board boots straight into the BIOS Maintenance/Configuration menu.
5. Clear the TPM / clear passwords.
6. Power off, restore the jumper, reboot.

## Method 3 — ME / BIOS update

Flashing BIOS sometimes resets PTT state as a side effect. Unreliable as a deliberate
fix, but if you are updating anyway, check TPM state afterwards.

## After any of the above

```bash
sudo ./00-status.sh                        # confirm all auths empty
sudo RECOVERY=0 ./05-set-lockout-params.sh # never brick yourself again
sudo ./07-reenroll-luks.sh /dev/nvmeXn1pY  # systemd-cryptenroll disk unlock
sudo ./09-clevis.sh bind && sudo ./09-clevis.sh verify   # clevis disk unlock
```

`RECOVERY=0` is the important one: it means a failed lockout auth locks the TPM only
until the next power cycle, instead of for hours.
