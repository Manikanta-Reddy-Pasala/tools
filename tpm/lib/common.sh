#!/usr/bin/env bash
# Shared helpers for the tpm/ scripts. Source, do not execute.

set -euo pipefail

# ---------- output ----------
if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
  C_BLU=$'\033[34m'; C_BLD=$'\033[1m';  C_OFF=$'\033[0m'
else
  C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_BLD=""; C_OFF=""
fi

info() { printf '%s[*]%s %s\n' "$C_BLU" "$C_OFF" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
err()  { printf '%s[x]%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; }
die()  { err "$*"; exit 1; }
hdr()  { printf '\n%s== %s ==%s\n' "$C_BLD" "$*" "$C_OFF"; }

have() { command -v "$1" >/dev/null 2>&1; }

need_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "run as root: sudo $0 $*"
}

# Require literal confirmation for destructive steps.
confirm_typed() {
  local phrase="$1" answer
  printf '%s\n' "$C_YEL"
  printf 'Type exactly: %s%s%s\n' "$C_BLD" "$phrase" "$C_OFF"
  read -r -p '> ' answer
  [[ "$answer" == "$phrase" ]] || die "not confirmed, aborting"
}

# ---------- tpm plumbing ----------
detect_tcti() {
  if [[ -n "${TPM2TOOLS_TCTI:-}" ]]; then
    echo "$TPM2TOOLS_TCTI"; return
  fi
  if [[ -c /dev/tpmrm0 ]]; then
    echo "device:/dev/tpmrm0"
  elif [[ -c /dev/tpm0 ]]; then
    echo "device:/dev/tpm0"
  elif have tpm2_startup && systemctl is-active --quiet tpm2-abrmd 2>/dev/null; then
    echo "tabrmd:"
  else
    die "no TPM device found (/dev/tpmrm0, /dev/tpm0 missing). TPM disabled in BIOS, or driver not loaded (check: dmesg | grep -i tpm)"
  fi
}

setup_tpm_env() {
  have tpm2_getcap || die "tpm2-tools not installed. Run: ./install-deps.sh"
  TPM2TOOLS_TCTI="$(detect_tcti)"
  export TPM2TOOLS_TCTI
}

tools_major() {
  local v
  v="$(tpm2_getcap --version 2>/dev/null | sed -n 's/.*version="\([0-9]*\)\..*/\1/p' | head -n1)"
  [[ -n "$v" ]] || v="$(tpm2 version 2>/dev/null | sed -n 's/^version: \([0-9]*\).*/\1/p' | head -n1)"
  echo "${v:-0}"
}

# Cache of `tpm2_getcap properties-variable`
TPM_VARCAP=""
load_varcap() {
  TPM_VARCAP="$(tpm2_getcap properties-variable 2>/dev/null)" \
    || die "tpm2_getcap failed. Permission problem? Try sudo. Or TPM is not responding."
}

# prop <key> -> first matching value, hex or decimal, as decimal.
prop() {
  local key="$1" raw
  [[ -n "$TPM_VARCAP" ]] || load_varcap
  raw="$(printf '%s\n' "$TPM_VARCAP" \
        | sed -n "s/^[[:space:]]*${key}:[[:space:]]*\([^[:space:]]*\).*/\1/p" \
        | head -n1)"
  [[ -n "$raw" ]] || { echo ""; return; }
  if [[ "$raw" == 0x* || "$raw" == 0X* ]]; then
    printf '%d\n' "$raw"
  else
    printf '%s\n' "$raw"
  fi
}

human_secs() {
  local s="${1:-0}"
  if [[ -z "$s" || "$s" == 0 ]]; then echo "0 (clears on TPM reset / full power cycle)"; return; fi
  local d=$(( s / 86400 )) h=$(( (s % 86400) / 3600 )) m=$(( (s % 3600) / 60 ))
  local out=""
  (( d > 0 )) && out+="${d}d "
  (( h > 0 )) && out+="${h}h "
  (( m > 0 )) && out+="${m}m"
  echo "${s}s (${out:-<1m})"
}

# Build the auth argument for tpm2-tools. Empty auth -> no flag.
# usage: auth_args <flag> <value>   e.g. auth_args -p "$LOCKOUT_AUTH"
auth_args() {
  local flag="$1" val="${2:-}"
  [[ -z "$val" ]] && return 0
  if [[ "$val" == *:* ]]; then
    printf '%s\n%s\n' "$flag" "$val"          # already prefixed (str:, hex:, file:)
  else
    printf '%s\nstr:%s\n' "$flag" "$val"
  fi
}

# Explain a tpm2-tools return code seen in stderr.
explain_rc() {
  case "${1:-}" in
    *0x921*)  echo "TPM_RC_LOCKOUT: TPM is in dictionary-attack lockout. Auth-gated commands refused until recovery." ;;
    *0x98e*|*0x9a2*) echo "TPM_RC_AUTH_FAIL: wrong password. Each failure raises the lockout counter." ;;
    *0x18b*)  echo "TPM_RC_BAD_AUTH: auth value rejected (no counter increment)." ;;
    *0x184*)  echo "TPM_RC_HIERARCHY: that hierarchy is disabled. Platform hierarchy is usually dropped by firmware before OS handover." ;;
    *0x143*)  echo "TPM_RC_HANDLE / hierarchy handle rejected." ;;
    *0x9a5*)  echo "TPM_RC_BAD_TAG or session problem." ;;
    *)        echo "" ;;
  esac
}

run_tpm() {
  local out rc=0
  out="$("$@" 2>&1)" || rc=$?
  printf '%s\n' "$out"
  if (( rc != 0 )); then
    local hint; hint="$(explain_rc "$out")"
    [[ -n "$hint" ]] && warn "$hint"
  fi
  return $rc
}

# ---------- disk helpers ----------
# All LUKS containers, whatever they sit on (partition, whole disk, LVM, mdraid).
luks_devices() {
  local seen=""
  if have blkid; then
    while read -r d; do
      [[ -n "$d" ]] && { echo "$d"; seen="$seen $d"; }
    done < <(blkid -t TYPE=crypto_LUKS -o device 2>/dev/null || true)
  fi
  if have lsblk && have cryptsetup; then
    while read -r d t; do
      case "$t" in part|disk|lvm|raid*|dm*) ;; *) continue ;; esac
      [[ " $seen " == *" $d "* ]] && continue
      [[ -b "$d" ]] || continue
      cryptsetup isLuks "$d" 2>/dev/null && echo "$d"
    done < <(lsblk -pnro NAME,TYPE 2>/dev/null || true)
  fi
}

# Warn early when the TPM device exists but is unreadable by this user.
check_tpm_access() {
  local dev=""
  [[ -c /dev/tpmrm0 ]] && dev=/dev/tpmrm0
  [[ -z "$dev" && -c /dev/tpm0 ]] && dev=/dev/tpm0
  [[ -z "$dev" ]] && return 0
  if [[ ! -r "$dev" || ! -w "$dev" ]]; then
    warn "$dev not read/write for uid $(id -u). Re-run with sudo, or: sudo usermod -aG tss \"$USER\" && newgrp tss"
  fi
}

# ---------- clevis helpers ----------
# Clevis binds LUKS keyslots to a TPM policy. Unlike systemd-cryptenroll it stores
# its state in LUKS2 tokens, so it needs its own detection and its own re-bind path.

# clevis subcommands parse with `getopts ":d:s:"`, so `--help` is NOT a flag: it falls
# through to usage() and exits 1. Probing with --help therefore reports a perfectly
# good clevis as "too old" - which is exactly what it did on Ubuntu 22.04's clevis 18.
# `--summary` is the one argument every clevis subcommand handles, and it exits 0.
has_clevis_subcmd() {
  command -v "clevis-luks-$1" >/dev/null 2>&1 && return 0
  clevis luks "$1" --summary >/dev/null 2>&1
}

# Parse `clevis luks list` from stdin. Split out from clevis_slots so the parser can
# be tested with no clevis and no TPM. Real output looks like:
#   1: tpm2 '{"hash":"sha256","key":"ecc","pcr_bank":"sha256","pcr_ids":"7"}'
parse_clevis_list() {
  sed -n "s/^\([0-9]\{1,\}\):[[:space:]]*\([a-z0-9]\{1,\}\)[[:space:]]*'\(.*\)'[[:space:]]*$/\1 \2 \3/p"
}

# clevis_slots <dev> -> lines of "<slot> <pin> <config-json>"
clevis_slots() {
  local dev="$1"
  have clevis || return 0
  clevis luks list -d "$dev" 2>/dev/null | parse_clevis_list
}

# True when the JSON config has no pcr_ids -> the binding is not tied to boot state.
clevis_cfg_has_pcrs() {
  local cfg="$1"
  [[ "$cfg" == *pcr_ids* ]]
}

# Number of enabled keyslots on a LUKS device (LUKS2 and LUKS1).
luks_keyslot_count() {
  local dump; dump="$(cryptsetup luksDump "$1" 2>/dev/null || true)"
  local n
  n="$(grep -cE '^[[:space:]]+[0-9]+: luks2' <<<"$dump" || true)"
  [[ "${n:-0}" == 0 ]] && n="$(grep -cE '^Key Slot [0-9]+: ENABLED' <<<"$dump" || true)"
  echo "${n:-0}"
}

# Pick the LUKS device when there is exactly one; otherwise make the caller choose.
# Replaces the fragile `lsblk -r | grep -B1 crypt | grep part` idiom.
pick_luks_device() {
  local -a devs=()
  mapfile -t devs < <(luks_devices)
  case "${#devs[@]}" in
    0) die "no LUKS container found on this system" ;;
    1) printf '%s\n' "${devs[0]}" ;;
    *) err "more than one LUKS container - name one explicitly:"
       printf '      %s\n' "${devs[@]}" >&2
       exit 1 ;;
  esac
}

# ---------- TCG Physical Presence Interface ----------
# The kernel prints one line per opcode as "<op> <status>: <text>" (tpm_ppi.c), e.g.
#   5 4: User not required
# Status: 0 not implemented, 1 firmware only, 2 blocked by firmware,
#         3 allowed, physically present user REQUIRED (firmware prompts),
#         4 allowed, physically present user NOT required (firmware does NOT prompt).
# ppi_op_status <opcode> < ops-file  -> the numeric status, or "" if absent
ppi_op_status() {
  local op="$1"
  sed -n "s/^[[:space:]]*${op}[[:space:]]\{1,\}\([0-9]\{1,\}\):.*/\1/p" | head -n1
}

# True when the opcode is usable (status 3 or 4).
ppi_op_allowed() {
  case "${1:-}" in 3|4) return 0 ;; *) return 1 ;; esac
}

ppi_status_text() {
  case "${1:-}" in
    0) echo "not implemented" ;;
    1) echo "firmware only - the OS cannot request it" ;;
    2) echo "blocked for the OS by firmware" ;;
    3) echo "allowed, firmware WILL prompt for physical presence" ;;
    4) echo "allowed, firmware will NOT prompt - the reboot clears it silently" ;;
    *) echo "unknown status" ;;
  esac
}

# ---------- Windows registry (lockout auth provenance) ----------
# Windows calls the TPM2 LOCKOUT hierarchy "the TPM owner password", provisions it
# automatically, and keeps it base64 in the SYSTEM hive. That is why a Linux-only box
# can still show lockoutAuthSet=1.
find_windows_hives() {
  find /mnt /media /run/media /win /windows -maxdepth 6 \
       -ipath '*/Windows/System32/config/SYSTEM' -type f 2>/dev/null || true
}

unmounted_ntfs() {
  have lsblk || return 0
  lsblk -pnro NAME,FSTYPE,MOUNTPOINT 2>/dev/null \
    | awk '($2=="ntfs"||$2=="ntfs3") && $3==""{print $1}'
}

# windows_ownerauth_b64 <hive> -> base64 value, or empty
windows_ownerauth_b64() {
  local hive="$1" cs v
  have hivexget || return 0
  for cs in ControlSet001 ControlSet002 CurrentControlSet; do
    v="$(hivexget "$hive" "$cs\\Services\\TPM\\WMI\\Admin" OwnerAuthFull 2>/dev/null || true)"
    [[ -n "$v" ]] && { printf '%s\n' "$v"; return 0; }
  done
}
