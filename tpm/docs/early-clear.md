# Clearing the TPM from the OS when the platform hierarchy is already disabled

`tpm2_clear -c p` works only while `phEnable = 1`. Most firmware calls
`TPM2_HierarchyControl` to drop the platform hierarchy right before handing off to
the bootloader, so by the time you get a shell it is gone — `tpm2_clear -c p` returns
`0x184` (TPM_RC_HIERARCHY).

Check first:

```bash
sudo tpm2_getcap properties-variable | grep -A5 TPM2_PT_STARTUP_CLEAR
# phEnable: 1  -> the platform hierarchy is still open, just run ./04-clear-tpm.sh
# phEnable: 0  -> nothing in this boot can use it; go to BIOS (bios-nuc15-pro.md)
```

If `phEnable = 0` on a normal boot, running earlier does not help — the hierarchy is
disabled by firmware before any OS code runs. This document exists only to rule the
approach in or out; it is not a workaround for that case.

Where "run earlier" *does* help: setups where a local service (tpm2-abrmd,
clevis, a TPM-using agent) grabs the resource manager and the TPM reports
`TPM_RC_INITIALIZE` or object-slot exhaustion. Then ordering a one-shot before them
is the fix:

```ini
# /etc/systemd/system/tpm-clear-once.service
[Unit]
Description=One-shot TPM clear before any TPM consumer
DefaultDependencies=no
After=systemd-udev-settle.service
Before=tpm2-abrmd.service clevis-luks-askpass.path cryptsetup.target
ConditionPathExists=/etc/tpm-clear-once

[Service]
Type=oneshot
Environment=TPM2TOOLS_TCTI=device:/dev/tpmrm0
ExecStart=/usr/bin/tpm2_clear -c p
ExecStartPost=/bin/rm -f /etc/tpm-clear-once
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target
```

```bash
sudo touch /etc/tpm-clear-once
sudo systemctl enable tpm-clear-once.service
sudo reboot
```

The `ConditionPathExists` + `rm` pair makes it fire exactly once. Remove the unit
afterwards. Same destructive warning as `04-clear-tpm.sh` applies.
