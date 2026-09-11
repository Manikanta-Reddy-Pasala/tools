# tools

Small, self-contained sysadmin scripts. Each directory stands alone — clone the repo
(or copy just the file you need) onto the target machine and run it.

| Directory | What it is |
|---|---|
| [`tpm/`](tpm/) | TPM + LUKS auto-unlock for NUCs: `provision.sh` for a new system, `tpmfix.sh` for one already configured (clears a TPM whose lockout password is set, repairs boot). Runbook in [`tpm/README.md`](tpm/README.md). |

## Conventions

- Bash, one file per task, no dependencies between files.
- A read-only `--status` on every script; anything destructive says so, checks first,
  and asks for a typed confirmation.
- No secrets in the repo, and no script writes a password to disk.
- Tests in `t/`, run on a separate Linux box — never on the machine being fixed.
