#!/usr/bin/env bash
# End-to-end test of ../provision.sh and ../tpmfix.sh (phase 2) against a SOFTWARE TPM,
# with real jammy tpm2-tools, clevis and cryptsetup. Never touches the host's TPM.
#
#   sudo bash t/swtpm-e2e-test.sh        # Linux host with docker; loads tpm_vtpm_proxy
#
# How: swtpm runs behind the kernel's vtpm proxy inside an ubuntu:22.04 container and is
# bind-mounted over /dev/tpmrm0 in the container's mount namespace only. That is needed
# because jammy clevis ignores TPM2TOOLS_TCTI and always opens /dev/tpmrm? - a plain
# swtpm socket would leave clevis sealing to the host's real TPM.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

if [[ "${1:-}" != --inside ]]; then
  [[ $(id -u) -eq 0 ]] || { echo "run as root"; exit 2; }
  command -v docker >/dev/null || { echo "needs docker"; exit 2; }
  loaded=0
  lsmod | grep -q '^tpm_vtpm_proxy' || { modprobe tpm_vtpm_proxy || exit 2; loaded=1; }
  docker run --rm --privileged -v /dev:/dev -v "$HERE/..":/w:ro ubuntu:22.04 \
    bash /w/t/swtpm-e2e-test.sh --inside
  rc=$?
  (( loaded )) && modprobe -r tpm_vtpm_proxy
  exit "$rc"
fi

# ------------------------------------------------------------------ inside the container
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends swtpm swtpm-tools tpm2-tools clevis clevis-luks clevis-tpm2 clevis-initramfs cryptsetup-bin >/dev/null 2>&1 \
  || { echo "apt-get install failed"; exit 2; }
dpkg -l tpm2-tools clevis swtpm | awk '/^ii/ { print "  " $2, $3 }'

pass=0 fail=0
ok()  { pass=$((pass+1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf 'FAIL %s\n' "$1"; }
W="$(mktemp -d)"
cleanup() {  # by image path: new_luks runs in $(...), so it cannot record into a variable
  local f; for f in "$W"/luks*.img; do [[ -e "$f" ]] && losetup -j "$f" | cut -d: -f1 | xargs -r -n1 losetup -d; done
  pkill swtpm 2>/dev/null; sleep 1; umount /dev/tpmrm0 2>/dev/null; rm -rf "$W"
}
trap cleanup EXIT
export TPM2TOOLS_TCTI="device:/dev/tpmrm0"

start_tpm() {  # fresh swtpm, visible to clevis as /dev/tpmrm0
  pkill swtpm 2>/dev/null; sleep 1; umount /dev/tpmrm0 2>/dev/null
  rm -rf "$W/tpm"; mkdir -p "$W/tpm"
  local before after new
  before="$(ls /sys/class/tpmrm)"
  swtpm chardev --tpm2 --vtpm-proxy --tpmstate dir="$W/tpm" --flags startup-clear --daemon >"$W/swtpm.out" 2>&1
  sleep 2
  after="$(ls /sys/class/tpmrm)"
  new="$(comm -13 <(sort <<<"$before") <(sort <<<"$after") | head -n1)"
  [[ -n "$new" && -c "/dev/$new" ]] || { echo "vtpm did not appear: $(cat "$W/swtpm.out")"; exit 2; }
  mount --bind "/dev/$new" /dev/tpmrm0
  # refuse to go on unless it really is the software TPM
  tpm2_getcap properties-fixed | grep -A2 MANUFACTURER | grep -q '"IBM"' || { echo "tpmrm0 is not swtpm"; exit 2; }
}
new_luks() {  # prints a loop device holding a fresh LUKS2 volume, passphrase xxxxxx
  local img="$W/luks$RANDOM.img"
  truncate -s 40M "$img"
  printf 'xxxxxx' | cryptsetup luksFormat -q --type luks2 --pbkdf pbkdf2 --pbkdf-force-iterations 1000 "$img" --key-file=-
  losetup -f --show "$img"
}
prov() {  # prov DEV [VAR=value ...] [script args ...]
  local dev="$1" a envs=() args=(); shift
  for a in "$@"; do if [[ "$a" == *=* ]]; then envs+=("$a"); else args+=("$a"); fi; done
  env SKIP_APT=1 NO_INITRAMFS=1 CRYPTTAB="$W/crypttab" DEV="$dev" "${envs[@]}" \
    bash /w/provision.sh "${args[@]}" </dev/null 2>&1
}
nslots() { clevis luks list -d "$1" 2>/dev/null | grep -c .; }
da() { tpm2_getcap properties-variable | sed -n "s/^[[:space:]]*$1:[[:space:]]*//p"; }
: > "$W/crypttab"

# ---- fresh TPM, fresh disk
start_tpm; L="$(new_luks)"
out="$(prov "$L" LUKS_PASS=xxxxxx)"; rc=$?
[[ $rc == 0 ]] && ok "fresh: exits 0" || { bad "fresh: rc=$rc"; echo "$out"; }
[[ "$(da TPM2_PT_MAX_AUTH_FAIL)" == 0x20 ]]    && ok "fresh: maxTries 32"          || bad "maxTries $(da TPM2_PT_MAX_AUTH_FAIL)"
[[ "$(da TPM2_PT_LOCKOUT_INTERVAL)" == 0x3C ]] && ok "fresh: recovery 60s"         || bad "interval"
[[ "$(da TPM2_PT_LOCKOUT_RECOVERY)" == 0x3C ]] && ok "fresh: lockoutRecovery 60s"  || bad "lockout recovery"
clevis luks list -d "$L" | grep -q '"pcr_ids":"7"' && ok "fresh: bound with pcr_ids 7" || bad "no pcr_ids"
S="$(clevis luks list -d "$L" | awk -F: '/pcr_ids/ { print $1 }')"
clevis luks pass -d "$L" -s "$S" | cryptsetup open --test-passphrase "$L" --key-file=- \
  && ok "fresh: TPM-released key opens the volume" || bad "released key does not open the volume"

# ---- re-run: nothing added
n="$(nslots "$L")"; out="$(prov "$L")"; rc=$?
[[ $rc == 0 && "$(nslots "$L")" == "$n" && "$out" == *"already unseals"* ]] \
  && ok "re-run: keeps the working slot, asks for nothing" || { bad "re-run: rc=$rc"; echo "$out"; }

# ---- PCR 7 changes: sealing is real
tpm2_pcrextend 7:sha256=0000000000000000000000000000000000000000000000000000000000000001
clevis luks pass -d "$L" -s "$S" >/dev/null 2>&1 && bad "PCR 7 change still unseals" || ok "PCR 7 change blocks unseal"

# ---- the old command's binding (no pcr_ids) is replaced
L2="$(new_luks)"
echo -e "xxxxxx" | clevis luks bind -d "$L2" tpm2 '{"pcr_bank":"sha256"}' >/dev/null 2>&1
out="$(prov "$L2" LUKS_PASS=xxxxxx)"; rc=$?
[[ $rc == 0 ]] && ok "old binding: exits 0" || { bad "old binding: rc=$rc"; echo "$out"; }
clevis luks list -d "$L2" | grep -q "tpm2 '{\"pcr_bank\":\"sha256\"}'" && bad "unpinned slot left" || ok "old binding: unpinned slot removed"
clevis luks list -d "$L2" | grep -q '"pcr_ids":"7"' && ok "old binding: pinned slot present" || bad "old binding: no pinned slot"
printf 'xxxxxx' | cryptsetup open --test-passphrase "$L2" --key-file=- && ok "old binding: passphrase still opens" || bad "passphrase lost"

# ---- wrong passphrase: nothing bound
L3="$(new_luks)"
out="$(prov "$L3" LUKS_PASS=wrong)"; rc=$?
[[ $rc != 0 && "$out" == *"does not open"* && "$(nslots "$L3")" == 0 ]] \
  && ok "wrong passphrase: refused, nothing bound" || { bad "wrong passphrase: rc=$rc"; echo "$out"; }

# ---- lockoutAuth set (what Windows leaves) with other DA values: stops before binding
start_tpm
tpm2_changeauth -c l windowsSecret
L4="$(new_luks)"
out="$(prov "$L4" LUKS_PASS=xxxxxx)"; rc=$?
[[ $rc != 0 && "$out" == *"lockoutAuth is already set"* && "$out" == *tpmfix.sh* ]] \
  && ok "lockoutAuth set: refuses and points at tpmfix.sh" || { bad "lockoutAuth set: rc=$rc"; echo "$out"; }
[[ "$(nslots "$L4")" == 0 ]] && ok "lockoutAuth set: nothing bound" || bad "lockoutAuth set: bound anyway"

# ---- lockoutAuth set AFTER our values were applied: nothing to change, carries on
start_tpm
tpm2_dictionarylockout --setup-parameters --max-tries=32 --recovery-time=60 --lockout-recovery-time=60
tpm2_changeauth -c l windowsSecret
out="$(prov "$L4" LUKS_PASS=xxxxxx)"; rc=$?
[[ $rc == 0 && "$out" == *"nothing needs changing"* ]] \
  && ok "lockoutAuth set, values already right: proceeds" || { bad "values already right: rc=$rc"; echo "$out"; }

# ---- crypttab keyscript is called out; --status changes nothing
L5="$(new_luks)"
printf 'dm_crypt-0 UUID=%s none luks,keyscript=/usr/local/sbin/tpm2-getkey\n' "$(blkid -s UUID -o value "$L5")" > "$W/crypttab"
out="$(prov "$L5" --status)"; rc=$?
[[ $rc == 0 && "$out" == *"NO passphrase prompt"* ]] && ok "--status: keyscript warning" || { bad "--status: rc=$rc"; echo "$out"; }
[[ "$(nslots "$L5")" == 0 ]] && ok "--status: nothing bound" || bad "--status bound something"

# ---- tpmfix.sh phase 2 (lockoutAuthSet=0): already configured with the old command
# update-initramfs is faked - there is no kernel in the container; the initrd check is
# covered by t/tpmfix-test.sh against real unmkinitramfs.
start_tpm
: > "$W/crypttab"
mkdir -p "$W/bin"; printf '#!/bin/sh\necho "fake update-initramfs $*"\n' > "$W/bin/update-initramfs"; chmod +x "$W/bin/update-initramfs"
L6="$(new_luks)"
echo -e "xxxxxx" | clevis luks bind -d "$L6" tpm2 '{"pcr_bank":"sha256"}' >/dev/null 2>&1
out="$(printf 'xxxxxx\n' | env PATH="$W/bin:$PATH" CRYPTTAB="$W/crypttab" DEV="$L6" STATE="$W/state" bash /w/tpmfix.sh 2>&1)"; rc=$?
[[ $rc == 0 && "$out" == *"PHASE 2"* ]] && ok "tpmfix phase 2: exits 0" || { bad "tpmfix phase 2: rc=$rc"; echo "$out"; }
[[ "$(da TPM2_PT_MAX_AUTH_FAIL)/$(da TPM2_PT_LOCKOUT_INTERVAL)/$(da TPM2_PT_LOCKOUT_RECOVERY)" == 0x20/0x3C/0x3C ]] \
  && ok "tpmfix phase 2: DA 32/60/60 (same as provision.sh)" || bad "tpmfix DA: $(da TPM2_PT_MAX_AUTH_FAIL)/$(da TPM2_PT_LOCKOUT_INTERVAL)/$(da TPM2_PT_LOCKOUT_RECOVERY)"
clevis luks list -d "$L6" | grep -q '"pcr_ids":"7"' && ok "tpmfix phase 2: PCR-7 slot bound" || bad "tpmfix: no pinned slot"
clevis luks list -d "$L6" | grep -q "tpm2 '{\"pcr_bank\":\"sha256\"}'" && bad "tpmfix: unpinned slot left" || ok "tpmfix phase 2: unpinned slot removed"
S6="$(clevis luks list -d "$L6" | awk -F: '/pcr_ids/ { print $1 }')"
clevis luks pass -d "$L6" -s "$S6" | cryptsetup open --test-passphrase "$L6" --key-file=- \
  && ok "tpmfix phase 2: TPM-released key opens the volume" || bad "tpmfix: released key does not open"
n="$(nslots "$L6")"; out="$(env PATH="$W/bin:$PATH" CRYPTTAB="$W/crypttab" DEV="$L6" STATE="$W/state" bash /w/tpmfix.sh </dev/null 2>&1)"; rc=$?
[[ $rc == 0 && "$(nslots "$L6")" == "$n" && "$out" == *"already unseals"* ]] \
  && ok "tpmfix phase 2 re-run: nothing added, no passphrase asked" || { bad "tpmfix re-run: rc=$rc"; echo "$out"; }

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
