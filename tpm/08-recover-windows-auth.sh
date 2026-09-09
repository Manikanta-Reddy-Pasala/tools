#!/usr/bin/env bash
# Read-only. Answers "lockoutAuthSet=1 but I never set a password - who did?"
#
# The usual answer is Windows. Windows calls the TPM 2.0 LOCKOUT hierarchy "the TPM
# owner password", provisions it automatically on first boot with a random value, and
# saves that value base64-encoded in the SYSTEM registry hive:
#
#   HKLM\SYSTEM\CurrentControlSet\Services\TPM\WMI\Admin  ->  OwnerAuthFull
#
# So a dual-boot or ex-Windows machine can hand the password back instead of needing
# a destructive TPM clear. This script finds it. It does NOT try it against the TPM
# unless you pass --try, because a wrong guess raises lockoutCounter.
set -euo pipefail
HERE="$(dirname "$(readlink -f "$0")")"
source "$HERE/lib/common.sh"

TRY=0
[[ "${1:-}" == "--try" ]] && TRY=1
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { sed -n '2,15p' "$0"; exit 0; }

setup_tpm_env
load_varcap

OA="$(prop ownerAuthSet)"; EA="$(prop endorsementAuthSet)"; LA="$(prop lockoutAuthSet)"

hdr "1. auth fingerprint"
printf '    ownerAuthSet       = %s\n' "${OA:-?}"
printf '    endorsementAuthSet = %s\n' "${EA:-?}"
printf '    lockoutAuthSet     = %s\n' "${LA:-?}"

if [[ "$LA" != "1" ]]; then
  ok "lockoutAuth is empty. Nothing to recover - hierarchy commands take no password."
  exit 0
fi
if [[ "$OA" == "0" && "$EA" == "0" ]]; then
  warn "lockout set, owner+endorsement empty -> classic Windows auto-provisioning signature."
  info "Linux tools (clevis, systemd-cryptenroll, tpm2-pkcs11) never touch the lockout hierarchy."
else
  info "owner and/or endorsement auth also set -> something took full ownership (old tpm2_takeownership, BIOS provisioning, a management agent)."
fi

hdr "2. local suspects"
FOUND_LOCAL=0
for f in /var/lib/tpm2-tss /etc/tpm2-tss /var/lib/tpm; do
  [[ -e "$f" ]] && { info "present: $f"; FOUND_LOCAL=1; }
done
if have journalctl; then
  J="$(journalctl -b --no-pager 2>/dev/null | grep -icE 'tpm2_changeauth|dictionarylockout|takeownership' || true)"
  [[ "${J:-0}" != 0 ]] && { warn "$J TPM-auth log line(s) this boot: journalctl -b | grep -iE 'changeauth|dictionarylockout'"; FOUND_LOCAL=1; }
fi
for h in /root/.bash_history "$HOME/.bash_history" /root/.zsh_history; do
  [[ -r "$h" ]] || continue
  N="$(grep -cE 'tpm2_changeauth|takeownership|dictionarylockout' "$h" 2>/dev/null || true)"
  [[ "${N:-0}" != 0 ]] && { warn "$h has $N matching command(s) - somebody did set it from this box:"; grep -nE 'tpm2_changeauth|takeownership|dictionarylockout' "$h" | tail -5 | sed 's/^/      /'; FOUND_LOCAL=1; }
done
(( FOUND_LOCAL == 0 )) && ok "no local evidence that any Linux tool set it"

hdr "3. Windows registry hives"
have hivexget || warn "hivexget missing - apt install libhivex-bin   (or chntpw for 'reged')"
HIVES=()
while read -r h; do [[ -n "$h" ]] && HIVES+=("$h"); done < <(find_windows_hives)
if (( ${#HIVES[@]} == 0 )); then
  NTFS="$(unmounted_ntfs)"
  if [[ -n "$NTFS" ]]; then
    warn "NTFS partition(s) found but not mounted. Mount read-only, then re-run:"
    for d in $NTFS; do echo "      sudo mkdir -p /mnt/win && sudo mount -o ro $d /mnt/win"; done
  else
    info "no Windows partition on this machine"
    info "If Windows was WIPED, the password is gone with it -> the only reset is a TPM clear."
  fi
fi

AUTH_B64=""
for hive in ${HIVES[@]+"${HIVES[@]}"}; do
  info "hive: $hive"
  have hivexget || continue
  V="$(windows_ownerauth_b64 "$hive")"
  if [[ -n "$V" ]]; then
    ok "Services\\TPM\\WMI\\Admin\\OwnerAuthFull found"
    AUTH_B64="$V"
    break
  fi
done

if [[ -z "$AUTH_B64" ]]; then
  hdr "verdict"
  err "no recoverable Windows lockout password found."
  cat <<'MSG'

Remaining options for lockoutAuthSet=1 with an unknown password:

  1. Windows still boots?  Run there, as Administrator:
       (Get-Tpm).OwnerAuth
     Paste it back here:  sudo ./03-clear-lockout.sh 'hex:<decoded>'
  2. Accept it. lockoutAuth only gates TPM2_DictionaryAttackParameters /
     LockReset. Sealing, unsealing, clevis and systemd-cryptenroll all use the
     OWNER hierarchy and keep working. You lose the ability to tune DA params.
  3. Clear the TPM (destroys every sealed key):
       sudo ./01-preflight-safety.sh && sudo ./04-clear-tpm.sh
MSG
  exit 1
fi

hdr "4. decoded"
HEXV="$(printf '%s' "$AUTH_B64" | base64 -d 2>/dev/null | od -An -tx1 | tr -d ' \n' || true)"
if [[ -z "$HEXV" ]]; then
  err "value is not valid base64: $AUTH_B64"
  exit 1
fi
BYTES=$(( ${#HEXV} / 2 ))
info "base64 : $AUTH_B64"
info "hex    : $HEXV  (${BYTES} bytes)"
case "$BYTES" in
  20) info "20 bytes = SHA-1 sized. Windows carried the TPM 1.2 format forward; still valid as a TPM2 auth value." ;;
  32) info "32 bytes = SHA-256 sized, the usual TPM 2.0 shape." ;;
  *)  warn "unusual length - it may still be right, try it." ;;
esac

cat <<MSG

Use it (non-destructive, resets the lockout counter):
    sudo $HERE/03-clear-lockout.sh 'hex:$HEXV'
Then set sane DA params so this cannot happen again:
    sudo RECOVERY=0 $HERE/05-set-lockout-params.sh 'hex:$HEXV'
And finally hand ownership back to yourself (empty lockout auth):
    sudo $HERE/06-set-hierarchy-auth.sh lockout "" 'hex:$HEXV'
MSG

(( TRY == 0 )) && exit 0

hdr "5. --try : one attempt against the TPM"
CNT="$(prop TPM2_PT_LOCKOUT_COUNTER)"; MAXF="$(prop TPM2_PT_MAX_AUTH_FAIL)"
HEADROOM=$(( ${MAXF:-0} - ${CNT:-0} ))
info "lockoutCounter=$CNT  maxAuthFail=$MAXF  headroom=$HEADROOM"
[[ "$(prop inLockout)" == "1" ]] && die "inLockout=1 - a failed attempt restarts lockoutRecovery. Refusing."
(( HEADROOM >= 2 )) || die "headroom < 2 failed attempts. Refusing to spend one. Wait out lockoutInterval first."
need_root "$@"
exec "$HERE/03-clear-lockout.sh" "hex:$HEXV"
