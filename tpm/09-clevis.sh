#!/usr/bin/env bash
# Clevis + TPM2 LUKS bindings: inspect, rescue, unbind, re-bind, verify.
#
# 07-reenroll-luks.sh covers systemd-cryptenroll. This covers the other half.
# Clevis keeps its state in LUKS2 tokens, so `systemd-cryptenroll --wipe-slot=tpm2`
# does not see it and a TPM clear leaves a keyslot that can never be satisfied again.
set -euo pipefail
HERE="$(dirname "$(readlink -f "$0")")"
source "$HERE/lib/common.sh"

PCR_IDS="${PCR_IDS:-7}"      # 7 = Secure Boot state. 0,2,4 also cover firmware and
                             # bootloader, but change on every update and re-lock you.
PCR_BANK="${PCR_BANK:-sha256}"

usage() {
  cat <<'MSG'
usage: sudo ./09-clevis.sh <command> [device]

  status   [dev]   list TPM2 bindings and flag unsafe ones          (read-only)
  rescue   [dev]   print the passphrase a binding is holding, while the TPM still
                   works. Do this BEFORE clearing the TPM.          (read-only)
  rebind   [dev]   fix an unpinned binding with NO passphrase needed: recover the
                   key from the live binding, add a PCR-sealed slot, verify it,
                   and only then drop the old slots. Use this one.
  unbind   [dev]   remove stale/all clevis TPM2 bindings
  bind     [dev]   create a binding, PCR-sealed, passphrase read from a prompt
  verify   [dev]   prove the TPM really unseals it, without rebooting

  device is optional when the system has exactly one LUKS container.

env: PCR_IDS=7  PCR_BANK=sha256
flags: -y   skip the typed confirmation (rebind/unbind)
MSG
}

CMD=""; DEV=""; ASSUME_YES=0
for a in "$@"; do
  case "$a" in
    -y|--yes)     ASSUME_YES=1 ;;
    -h|--help)    usage; exit 0 ;;
    *) if [[ -z "$CMD" ]]; then CMD="$a"; elif [[ -z "$DEV" ]]; then DEV="$a"; fi ;;
  esac
done
[[ -n "$CMD" ]] || { usage; exit 0; }

confirm_or_yes() {
  if (( ASSUME_YES == 1 )); then warn "-y given, skipping confirmation"; return 0; fi
  confirm_typed "$1"
}

have clevis || die "clevis not installed: apt install clevis clevis-luks clevis-tpm2 clevis-initramfs"
[[ -n "$DEV" ]] || DEV="$(pick_luks_device)"
cryptsetup isLuks "$DEV" || die "$DEV is not a LUKS device"

show_status() {
  hdr "bindings on $DEV"
  local any=0 slot pin cfg
  local slots; slots="$(luks_keyslot_count "$DEV")"
  info "$slots keyslot(s) total"
  while read -r slot pin cfg; do
    [[ -n "${slot:-}" ]] || continue
    any=1
    printf '    slot %-3s pin=%-6s %s\n' "$slot" "$pin" "$cfg"
    if [[ "$pin" == tpm2 ]] && ! clevis_cfg_has_pcrs "$cfg"; then
      err "slot $slot has NO pcr_ids -> unseals in ANY boot state."
      warn "     Anyone who powers this box on gets the disk: an attacker can boot their"
      warn "     own kernel, or disable Secure Boot, and the TPM still hands the key over."
      warn "     Fix: $0 unbind $DEV && PCR_IDS=7 $0 bind $DEV"
    fi
  done < <(clevis_slots "$DEV")
  (( any == 0 )) && ok "no clevis bindings"
  if (( any == 1 )) && [[ "$slots" -le "$(clevis_slots "$DEV" | wc -l)" ]]; then
    err "no passphrase-only keyslot left - a TPM clear would make $DEV unopenable forever"
  fi
}

# clevis-luks-bind reads the existing passphrase two ways. With no -k it runs
#   IFS= read -r -s -p "Enter existing LUKS password: " existing_key
# unguarded, inside a `#!/bin/bash -e` script: pipe it a key with no trailing newline
# and read returns 1 at EOF, killing clevis before it binds anything. The `-k -` branch
# is the guarded one (`||:`), and it is the documented non-interactive path.
clevis_bind_with_key() {
  local key="$1" dev="$2"
  printf '%s' "$key" | clevis luks bind -y -k - -d "$dev" tpm2 \
      "{\"pcr_bank\":\"$PCR_BANK\",\"pcr_ids\":\"$PCR_IDS\"}"
}

case "$CMD" in

status)
  show_status
  ;;

rescue)
  need_root "$@"
  hdr "recovering passphrases held by clevis on $DEV"
  info "this reads them out of the TPM while it still works, so a clear cannot strand you"
  has_clevis_subcmd pass \
    || die "this clevis has no 'clevis luks pass'. Fall back to: add a known passphrase with 'cryptsetup luksAddKey $DEV' before clearing."
  while read -r slot pin cfg; do
    [[ "${pin:-}" == tpm2 ]] || continue
    echo
    info "slot $slot:"
    clevis luks pass -d "$DEV" -s "$slot" || err "slot $slot did not unseal"
  done < <(clevis_slots "$DEV")
  cat <<'MSG'

Write that down somewhere you can reach from a rescue shell. It is a full LUKS
passphrase - treat it exactly like the one you typed at install time.
MSG
  ;;

rebind)
  need_root "$@"
  setup_tpm_env; load_varcap
  [[ "$(prop inLockout)" == "1" ]] && die "TPM is in lockout - nothing will unseal. Run ./tpm-doctor.sh"
  has_clevis_subcmd pass || die "'clevis luks pass' unavailable - cannot recover the key without your passphrase. Use: $0 bind $DEV"

  show_status
  mapfile -t ROWS < <(clevis_slots "$DEV")
  (( ${#ROWS[@]} > 0 )) || die "no clevis bindings on $DEV - nothing to rebind. Use: $0 bind $DEV"

  # Only slots that are already unsafe need replacing. A correctly pinned slot is left alone.
  OLD=()
  for row in "${ROWS[@]}"; do
    set -- $row
    [[ "$2" == tpm2 ]] || continue
    clevis_cfg_has_pcrs "${*:3}" || OLD+=("$1")
  done
  (( ${#OLD[@]} > 0 )) || { ok "every tpm2 binding is already PCR-sealed - nothing to do"; exit 0; }
  info "slots to replace: ${OLD[*]}"

  hdr "1/4 recover the key from the live binding"
  info "this is why no passphrase is needed: the TPM still unseals the OLD binding,"
  info "and what it releases is a full LUKS passphrase for this volume."
  SRC="${OLD[0]}"
  KEY="$(clevis luks pass -d "$DEV" -s "$SRC" 2>/dev/null || true)"
  [[ -n "$KEY" ]] || die "slot $SRC did not unseal. If the TPM was already cleared, the key is gone - you need the passphrase: $0 bind $DEV"
  ok "recovered the key held by slot $SRC (${#KEY} chars, not printed)"

  hdr "2/4 add a PCR-sealed slot"
  info "PCR bank=$PCR_BANK ids=$PCR_IDS - added as a NEW slot, the old ones stay put"
  BEFORE="$(clevis_slots "$DEV" | wc -l)"
  clevis_bind_with_key "$KEY" "$DEV"
  AFTER="$(clevis_slots "$DEV" | wc -l)"
  (( AFTER > BEFORE )) || die "bind did not add a slot - refusing to remove anything"
  NEWSLOT="$(clevis_slots "$DEV" | while read -r sl pin cfg; do
      clevis_cfg_has_pcrs "$cfg" && echo "$sl"; done | head -n1)"
  ok "new PCR-sealed slot: ${NEWSLOT:-?}"

  hdr "3/4 verify the new slot unseals"
  [[ -n "$NEWSLOT" ]] || die "cannot identify the new slot - stopping with the old bindings intact"
  clevis luks pass -d "$DEV" -s "$NEWSLOT" >/dev/null 2>&1 \
    || die "the new slot did NOT unseal. Old bindings left intact; remove slot $NEWSLOT by hand: clevis luks unbind -d $DEV -s $NEWSLOT"
  ok "slot $NEWSLOT unseals against the current PCR $PCR_IDS state"
  unset KEY

  hdr "4/4 drop the unpinned slots"
  warn "about to remove slot(s): ${OLD[*]}"
  REMAIN=$(( $(luks_keyslot_count "$DEV") - ${#OLD[@]} ))
  (( REMAIN >= 2 )) || die "that would leave $REMAIN keyslot(s). Keep a passphrase slot AND the new binding."
  confirm_or_yes "DROP UNPINNED SLOTS ${OLD[*]} ON $DEV"
  for sl in "${OLD[@]}"; do
    info "unbinding slot $sl"
    clevis luks unbind -d "$DEV" -s "$sl" -f || warn "slot $sl failed"
  done
  show_status
  cat <<'MSG'

Regenerate the initramfs, or boot still uses the old JWEs:
  sudo update-initramfs -u -k all

PCR 7 is the Secure Boot state. Enrolling keys, toggling Secure Boot or a firmware
update can change it, and then this stops unsealing - by design. Your passphrase
keyslot is what gets you back in, so confirm it still works before you walk away:
  sudo cryptsetup open --test-passphrase DEVICE
MSG
  ;;

unbind)
  need_root "$@"
  show_status
  mapfile -t ROWS < <(clevis_slots "$DEV")
  (( ${#ROWS[@]} > 0 )) || { ok "nothing to unbind"; exit 0; }
  REMAIN=$(( $(luks_keyslot_count "$DEV") - ${#ROWS[@]} ))
  (( REMAIN >= 1 )) || die "that would leave 0 keyslots on $DEV. Add a passphrase first: cryptsetup luksAddKey $DEV"
  warn "about to remove ${#ROWS[@]} clevis binding(s). $REMAIN keyslot(s) will remain."
  warn "if you are replacing an unpinned binding, '$0 rebind $DEV' is safer:"
  warn "it binds and verifies the new slot BEFORE removing the old one, and needs no passphrase."
  confirm_or_yes "UNBIND CLEVIS FROM $DEV"
  for row in "${ROWS[@]}"; do
    set -- $row
    info "unbinding slot $1 ($2)"
    clevis luks unbind -d "$DEV" -s "$1" -f || warn "slot $1 failed"
  done
  ok "done"
  info "regenerate the initramfs so it stops waiting on a binding that is gone:"
  info "  sudo update-initramfs -u -k all"
  ;;

bind)
  need_root "$@"
  load_varcap 2>/dev/null || true
  hdr "pre-checks"
  setup_tpm_env
  load_varcap
  [[ "$(prop inLockout)" == "1" ]] && die "TPM is in lockout - binding will fail. Run ./tpm-doctor.sh"
  if [[ "$(prop ownerAuthSet)" == "1" ]]; then
    warn "ownerAuthSet=1: clevis calls tpm2_createprimary -C o with EMPTY auth and will fail."
    warn "Clear the owner auth first: sudo ./06-set-hierarchy-auth.sh owner \"\" 'current-owner-pw'"
  fi
  cryptsetup open --test-passphrase "$DEV" </dev/null >/dev/null 2>&1 || true
  info "PCR bank=$PCR_BANK  ids=$PCR_IDS"
  cat <<'MSG'

Sealing to PCR 7 means the key is released only while the Secure Boot state is
what it is right now. Change Secure Boot settings, enroll new keys, or boot
something unsigned, and it stops unsealing - that is the point. Keep a
passphrase keyslot, always.
MSG
  hdr "existing"
  show_status
  echo
  # Read the passphrase from a prompt, never argv: `echo pw | clevis ...` leaves the
  # disk passphrase in shell history and in /proc/<pid>/cmdline of the echo.
  read -r -s -p "existing LUKS passphrase for $DEV: " PASS; echo
  [[ -n "$PASS" ]] || die "empty passphrase"
  printf '%s' "$PASS" | cryptsetup open --test-passphrase "$DEV" - >/dev/null 2>&1 \
    || die "that passphrase does not open $DEV - refusing to bind"
  ok "passphrase verified"
  clevis_bind_with_key "$PASS" "$DEV"
  unset PASS
  ok "bound"
  show_status
  cat <<'MSG'

Now regenerate the initramfs, or nothing unlocks at boot:
  sudo update-initramfs -u -k all      # Debian/Ubuntu
  sudo dracut -f                       # Fedora/RHEL
Then verify without gambling a reboot:
  sudo ./09-clevis.sh verify
MSG
  ;;

verify)
  need_root "$@"
  hdr "unseal test on $DEV"
  info "asks the TPM for the key exactly as the initramfs will, into a throwaway mapping"
  if has_clevis_subcmd pass; then
    RC=0
    while read -r sl pin cfg; do
      [[ "${pin:-}" == tpm2 ]] || continue
      if clevis luks pass -d "$DEV" -s "$sl" >/dev/null 2>&1; then
        if clevis_cfg_has_pcrs "$cfg"; then ok "slot $sl unseals (PCR-sealed)"
        else warn "slot $sl unseals - but it has no pcr_ids, so it would unseal in any boot state"; fi
      else
        err "slot $sl did NOT unseal"; RC=1
      fi
    done < <(clevis_slots "$DEV")
    (( RC == 0 )) || exit 1
    ok "every tpm2 binding on $DEV releases its key from this TPM"
    exit 0
  fi
  NAME="tpmverify$$"
  if clevis luks unlock -d "$DEV" -n "$NAME" >/dev/null 2>&1; then
    ok "TPM released the key - this volume will auto-unlock at boot"
    cryptsetup close "$NAME" 2>/dev/null || true
  else
    err "TPM did NOT release the key"
    cat <<'MSG'

Causes, most likely first:
  - PCR values differ from bind time (firmware update, Secure Boot toggled,
    a different kernel/bootloader measured into the sealed PCRs)
  - the TPM was cleared after binding: the SRK is gone, the JWE is undecryptable
  - TPM in lockout: ./tpm-doctor.sh
Rebind with:  sudo ./09-clevis.sh unbind && sudo ./09-clevis.sh bind
MSG
    exit 1
  fi
  ;;

*) usage; exit 1 ;;
esac
