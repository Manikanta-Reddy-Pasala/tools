# tools

Small, self-contained sysadmin toolkits. Each directory stands alone — clone the repo
(or copy just the folder you need) onto the target machine and run it.

| Directory | What it is |
|---|---|
| [`tpm/`](tpm/) | TPM 2.0 lockout recovery and hardening for Linux. Diagnose `inLockout`, escape a lost lockout password, clear an Intel PTT firmware TPM, re-enroll LUKS afterwards. |

## Conventions

- Bash, `set -euo pipefail`, no dependencies beyond what each toolkit's
  `install-deps.sh` pulls in.
- Numbered scripts run in order; `00-*` is always read-only diagnosis.
- Anything destructive says so in its header, requires a typed confirmation, and has a
  read-only preflight script next to it.
- No secrets in the repo, and no script writes a password to disk.
- Where parsing logic exists, there is an offline `t/selftest.sh` with recorded
  fixtures so it can be tested without the hardware.
