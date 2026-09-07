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
