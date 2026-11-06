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
apt-get install -y -qq --no-install-recommends swtpm swtpm-tools tpm2-tools clevis clevis-luks clevis-tpm2 clevis-initramfs cryptsetup-bin dmsetup >/dev/null 2>&1 \
  || { echo "apt-get install failed"; exit 2; }
dpkg -l tpm2-tools clevis swtpm | awk '/^ii/ { print "  " $2, $3 }'

pass=0 fail=0
ok()  { pass=$((pass+1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf 'FAIL %s\n' "$1"; }
W="$(mktemp -d)"
cleanup() {  # by image path: new_luks runs in $(...), so it cannot record into a variable
  local f; for f in "$W"/luks*.img; do [[ -e "$f" ]] && losetup -j "$f" | cut -d: -f1 | xargs -r -n1 losetup -d; done
  umount /target 2>/dev/null; umount -R "$W/chroot/dev" 2>/dev/null; for d in w sys proc etc usr; do umount "$W/chroot/$d" 2>/dev/null; done; umount "$W/chroot$W" 2>/dev/null; umount "$W/chroot/var/cache" 2>/dev/null
  rm -f /etc/systemd/system/tpm-provision.service /etc/systemd/system/multi-user.target.wants/tpm-provision.service /usr/local/sbin/tpm-provision
  rmdir /target 2>/dev/null; pkill swtpm 2>/dev/null; sleep 1; umount /dev/tpmrm0 2>/dev/null; rm -rf "$W"
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
  # real firmware measures Secure Boot into PCR 7; a fresh swtpm reads all zeros, which the
  # scripts rightly treat as "bank not in use"
  tpm2_pcrextend 7:sha1=$(printf '%040d' 7),sha256=$(printf '%064d' 7)
}
new_luks() {  # prints a loop device holding a fresh LUKS2 volume, passphrase xxxxxx
  local img="$W/luks$RANDOM.img"
  truncate -s 40M "$img"
  printf 'xxxxxx' | cryptsetup luksFormat -q --type luks2 --pbkdf pbkdf2 --pbkdf-force-iterations 1000 "$img" --key-file=-
  losetup -f --show "$img"
}
mkdir -p "$W/bin"; printf '#!/bin/sh\nexit 0\n' > "$W/bin/update-initramfs"; chmod +x "$W/bin/update-initramfs"
# provision.sh lists every LUKS volume before a TPM clear; the test chooses which it sees
printf '#!/bin/sh\n[ -n "$BLKID_OUT" ] && printf "%%s\\n" "$BLKID_OUT"\nexit 0\n' > "$W/bin/blkid"; chmod +x "$W/bin/blkid"
prov() {  # prov DEV [VAR=value ...] - provision.sh takes no arguments
  local dev="$1"; shift
  # SB_VAR: the host's /sys is visible in here; tests pick the Secure Boot state themselves
  env PATH="$W/bin:$PATH" DEV="$dev" SB_VAR="$W/nosb" "$@" bash /w/provision.sh </dev/null 2>&1
}
nslots() { clevis luks list -d "$1" 2>/dev/null | grep -c .; }
da() { tpm2_getcap properties-variable | sed -n "s/^[[:space:]]*$1:[[:space:]]*//p"; }
: > "$W/crypttab"

# ---- fresh TPM, fresh disk
start_tpm; L="$(new_luks)"
out="$(prov "$L" LUKS_PASS=xxxxxx)"; rc=$?
# provision.sh itself prints nothing; clevis's own entropy warning on swtpm is not ours
own="$(grep -v '^Warning: Value .* entropy range' <<<"$out")"
[[ $rc == 0 && -z "$own" ]] && ok "fresh: exits 0, prints nothing of its own" || { bad "fresh: rc=$rc"; echo "$out"; }
[[ "$(da TPM2_PT_MAX_AUTH_FAIL)" == 0x20 ]]    && ok "fresh: maxTries 32"          || bad "maxTries $(da TPM2_PT_MAX_AUTH_FAIL)"
[[ "$(da TPM2_PT_LOCKOUT_INTERVAL)" == 0x3C ]] && ok "fresh: recovery 60s"         || bad "interval"
[[ "$(da TPM2_PT_LOCKOUT_RECOVERY)" == 0x3C ]] && ok "fresh: lockoutRecovery 60s"  || bad "lockout recovery"
clevis luks list -d "$L" | grep -q '"pcr_ids":"7"' && ok "fresh: bound with pcr_ids 7" || bad "no pcr_ids"
S="$(clevis luks list -d "$L" | awk -F: '/pcr_ids/ { print $1 }')"
clevis luks pass -d "$L" -s "$S" | cryptsetup open --test-passphrase "$L" --key-file=- \
  && ok "fresh: TPM-released key opens the volume" || bad "released key does not open the volume"

# ---- re-run without a passphrase: nothing added, nothing asked
n="$(nslots "$L")"; out="$(prov "$L")"; rc=$?
[[ $rc == 0 && "$(nslots "$L")" == "$n" && -z "$out" ]] \
  && ok "re-run: keeps the slot, asks for nothing, prints nothing" || { bad "re-run: rc=$rc"; echo "$out"; }

# ---- PCR 7 changes: sealing is real
tpm2_pcrextend 7:sha256=0000000000000000000000000000000000000000000000000000000000000001
clevis luks pass -d "$L" -s "$S" >/dev/null 2>&1 && bad "PCR 7 change still unseals" || ok "PCR 7 change blocks unseal"

# ---- a slot that exists but no longer unseals must not count as bound
out="$(prov "$L" LUKS_PASS=xxxxxx)"; rc=$?
[[ $rc == 0 ]] && ok "stale slot: re-binds against the new PCR state" || { bad "stale slot: rc=$rc"; echo "$out"; }
np="$(clevis luks list -d "$L" | grep -c '"pcr_ids":"7"')"
[[ "$np" == 1 ]] && ok "stale slot: the dead slot was removed, exactly one pinned slot left" \
  || bad "stale slot: $np pinned slots"
S3="$(clevis luks list -d "$L" | awk -F: '/pcr_ids/ { print $1 }')"
clevis luks pass -d "$L" -s "$S3" >/dev/null 2>&1 \
  && ok "stale slot: the new slot unseals" || bad "stale slot: nothing unseals"

# ---- takes no arguments: anything on the command line must not provision
out="$(env DEV="$L" bash /w/provision.sh --status 2>&1)"; rc=$?
[[ $rc == 64 && -z "$out" ]] && ok "arguments: refused, nothing done" || { bad "arguments: rc=$rc"; echo "$out"; }

# ---- a binding with no pcr_ids does not count as bound: a pinned slot is added beside it
L2="$(new_luks)"
echo -e "xxxxxx" | clevis luks bind -d "$L2" tpm2 '{"pcr_bank":"sha256"}' >/dev/null 2>&1
out="$(prov "$L2" LUKS_PASS=xxxxxx)"; rc=$?
[[ $rc == 0 ]] && ok "old binding: exits 0" || { bad "old binding: rc=$rc"; echo "$out"; }
clevis luks list -d "$L2" | grep -q '"pcr_ids":"7"' && ok "old binding: pinned slot added" || bad "old binding: no pinned slot"
printf 'xxxxxx' | cryptsetup open --test-passphrase "$L2" --key-file=- && ok "old binding: passphrase still opens" || bad "passphrase lost"

# ---- wrong passphrase: fails, nothing bound
L3="$(new_luks)"
out="$(prov "$L3" LUKS_PASS=wrong)"; rc=$?
[[ $rc != 0 && "$(nslots "$L3")" == 0 ]] \
  && ok "wrong passphrase: fails, nothing bound" || { bad "wrong passphrase: rc=$rc"; echo "$out"; }

# ---- lockoutAuth set (what Windows leaves): never tries a password, queues a PPI clear
start_tpm
tpm2_changeauth -c l windowsSecret
L4="$(new_luks)"
mkdir -p "$W/ppi"; printf ' 5 4: User not required\n' > "$W/ppi/tcg_operations"; : > "$W/ppi/request"
out="$(prov "$L4" LUKS_PASS=xxxxxx PPI="$W/ppi")"; rc=$?
[[ $rc == 10 && "$(cat "$W/ppi/request")" == 5 && "$out" == *Reboot* ]] \
  && ok "lockoutAuth set: PPI clear (op 5) queued, exit 10" || { bad "lockoutAuth set: rc=$rc"; echo "$out"; }
[[ "$(nslots "$L4")" == 0 ]] && ok "lockoutAuth set: nothing bound" || bad "lockoutAuth set: bound anyway"
[[ "$(da TPM2_PT_LOCKOUT_COUNTER)" == 0x0 ]] && ok "lockoutAuth set: no auth failure counted" || bad "failure counted"
: > "$W/ppi/request"
out="$(prov "$L4" LUKS_PASS=wrong PPI="$W/ppi")"; rc=$?
[[ $rc == 2 && ! -s "$W/ppi/request" ]] && ok "lockoutAuth set, wrong passphrase: nothing queued" || { bad "wrong pass: rc=$rc"; echo "$out"; }
printf 5 > "$W/ppi/request"
out="$(prov "$L4" LUKS_PASS=xxxxxx PPI="$W/ppi")"; rc=$?
[[ $rc == 10 && "$out" == *"already queued"* ]] && ok "lockoutAuth set: clear already pending, not queued again" || { bad "pending: rc=$rc"; echo "$out"; }
: > "$W/ppi/request"; printf '5 4294967295: General Failure\n' > "$W/ppi/response"
out="$(prov "$L4" LUKS_PASS=xxxxxx PPI="$W/ppi")"; rc=$?
[[ $rc == 3 && ! -s "$W/ppi/request" ]] && ok "lockoutAuth set: last clear failed -> BIOS, no re-queue loop" || { bad "failed clear: rc=$rc"; echo "$out"; }
rm -f "$W/ppi/response"
out="$(prov "$L4" LUKS_PASS=xxxxxx PPI="$W/ppi" BLKID_OUT="$L4
$L")"; rc=$?
[[ $rc == 2 && "$out" == *"$L also unlocks via the TPM"* && ! -s "$W/ppi/request" ]] \
  && ok "lockoutAuth set, another TPM-unlocked volume: refuses to clear" || { bad "other volume: rc=$rc"; echo "$out"; }
out="$(prov "$L4" LUKS_PASS=xxxxxx PPI="$W/noppi")"; rc=$?
[[ $rc == 3 && "$out" == *BIOS* ]] && ok "lockoutAuth set, no PPI: says clear in BIOS, exit 3" || { bad "no PPI: rc=$rc"; echo "$out"; }

# ---- ownerAuth set: clevis can never seal, so the same PPI clear
start_tpm
tpm2_changeauth -c o windowsOwner
L5="$(new_luks)"; : > "$W/ppi/request"
out="$(prov "$L5" LUKS_PASS=xxxxxx PPI="$W/ppi")"; rc=$?
[[ $rc == 10 && "$(cat "$W/ppi/request")" == 5 && "$(nslots "$L5")" == 0 ]] \
  && ok "ownerAuth set: PPI clear queued, nothing bound" || { bad "ownerAuth set: rc=$rc"; echo "$out"; }

# ---- no LUKS device found: says so
out="$(env PATH="$W/bin:$PATH" DEV= bash -c 'blkid() { return 2; }; export -f blkid; bash /w/provision.sh' 2>&1 </dev/null)"; rc=$?
[[ $rc == 2 && "$out" == *"need one LUKS device"* ]] && ok "no LUKS device: exit 2 with a message" || { bad "no LUKS: rc=$rc"; echo "$out"; }

# ---- lockout hierarchy locked by an earlier wrong password (the 0x921 in the field)
start_tpm
tpm2_dictionarylockout -s -n 32 -t 60 -l 1000 >/dev/null
tpm2_dictionarylockout -c -p wrongpass >/dev/null 2>&1
L8="$(new_luks)"
out="$(prov "$L8" LUKS_PASS=xxxxxx)"; rc=$?
[[ $rc == 75 && "$out" == *1000s* ]] && ok "lockout locked: exit 75, says wait 1000s" || { bad "lockout locked: rc=$rc"; echo "$out"; }
[[ "$(nslots "$L8")" == 0 ]] && ok "lockout locked: nothing bound" || bad "lockout locked: bound anyway"

# ---- DA lockout (inLockout=1, blocks clevis unlock too): cleared, then provisioned
start_tpm
tpm2_dictionarylockout -s -n 1 -t 1000 -l 60 >/dev/null
tpm2_createprimary -Q -C o -c "$W/p.ctx"
echo hi | tpm2_create -Q -C "$W/p.ctx" -p good -i- -u "$W/s.pub" -r "$W/s.priv"
tpm2_load -Q -C "$W/p.ctx" -u "$W/s.pub" -r "$W/s.priv" -c "$W/s.ctx"
tpm2_unseal -c "$W/s.ctx" -p bad >/dev/null 2>&1; tpm2_flushcontext -t >/dev/null 2>&1
[[ "$(da inLockout)" == 1 ]] && ok "DA lockout: set up (inLockout 1)" || bad "DA lockout: not in lockout"
L9="$(new_luks)"
out="$(prov "$L9" LUKS_PASS=xxxxxx)"; rc=$?
[[ $rc == 0 && "$(da inLockout)" == 0 && "$(da TPM2_PT_MAX_AUTH_FAIL)" == 0x20 ]] \
  && ok "DA lockout: cleared, 32/60/60 set, exit 0" || { bad "DA lockout: rc=$rc inLockout=$(da inLockout)"; echo "$out"; }
clevis luks list -d "$L9" | grep -q '"pcr_ids":"7"' && ok "DA lockout: bound with pcr_ids 7" || bad "DA lockout: not bound"

# ---- offline box, clevis missing: fails, binds nothing, installs nothing
start_tpm; L7="$(new_luks)"
mkdir -p "$W/nobin"
for t in bash id blkid grep sed awk head cut printf cryptsetup tpm2_getcap tpm2_dictionarylockout tpm2_pcrread; do
  p="$(command -v "$t")" && ln -sf "$p" "$W/nobin/$t"
done   # everything provision.sh runs EXCEPT clevis
ln -sf "$W/bin/update-initramfs" "$W/nobin/update-initramfs"
out="$(env PATH="$W/nobin" DEV="$L7" LUKS_PASS=xxxxxx bash /w/provision.sh 2>&1)"; rc=$?
[[ $rc != 0 && "$(nslots "$L7")" == 0 ]] \
  && ok "offline: missing clevis fails, nothing bound" || { bad "offline: rc=$rc"; echo "$out"; }

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

# ---- installer hand-off (autoinstall late-commands): binds nothing, stages a first-boot run
# /target bind-mounted so /proc/mounts looks like the installer's; the first boot runs with
# STAGE pointing into that tree. systemctl is faked: it records the reboot.
nkeys() { cryptsetup luksDump "$1" | grep -cE '^[[:space:]]+[0-9]+: luks2'; }
printf '#!/bin/sh\necho "$*" >> "%s/systemctl.log"\n' "$W" > "$W/bin/systemctl"; chmod +x "$W/bin/systemctl"
start_tpm; L10="$(new_luks)"
mkdir -p "$W/root/usr/bin" /target; mount --bind "$W/root" /target
mkdir -p "$W/root/usr/sbin"
for t in clevis clevis-luks-bind clevis-encrypt-tpm2 tpm2_pcrread; do install -m 755 /dev/null "$W/root/usr/bin/$t"; done
install -m 755 /dev/null "$W/root/usr/sbin/update-initramfs"   # sbin, like the real one
out="$(prov "$L10" LUKS_PASS=wrong STAGE=/stage)"; rc=$?
[[ $rc == 2 && ! -e "$W/root/stage/key" && "$(nkeys "$L10")" == 1 ]] \
  && ok "installer, wrong passphrase: exit 2, nothing staged" || { bad "installer wrong pass: rc=$rc"; echo "$out"; }
mv "$W/root/usr/bin/clevis" "$W/clevis.off"
out="$(prov "$L10" LUKS_PASS=xxxxxx STAGE=/stage)"; rc=$?
[[ $rc == 2 && "$out" == *"clevis missing"* && "$(nkeys "$L10")" == 1 ]] \
  && ok "installer: clevis missing in the target: exit 2, no key slot added" || { bad "installer no clevis: rc=$rc"; echo "$out"; }
mv "$W/clevis.off" "$W/root/usr/bin/clevis"
out="$(prov "$L10" LUKS_PASS=xxxxxx STAGE=/stage)"; rc=$?
[[ $rc == 0 && "$(nslots "$L10")" == 0 && "$out" == *"left to the first boot"* ]] && ok "installer (live shell): exit 0, says so, nothing bound to the TPM" || { bad "installer: rc=$rc"; echo "$out"; }
[[ -s "$W/root/stage/key" && -x "$W/root/usr/local/sbin/tpm-provision" && "$(grep ^STAGE= "$W/root/stage/env")" == STAGE=/stage \
   && -L "$W/root/etc/systemd/system/multi-user.target.wants/tpm-provision.service" \
   && "$(grep ^DEV= "$W/root/stage/env")" == "DEV=/dev/disk/by-uuid/$(cryptsetup luksUUID "$L10")" ]] \
  && ok "installer: key, script, enabled unit, env with DEV by UUID" || { bad "installer: files"; ls -lR "$W/root"; }
cryptsetup open --test-passphrase "$L10" --key-file="$W/root/stage/key" \
  && ok "installer: one-time key opens the disk" || bad "installer: key does not open"
out="$(prov "$L10" LUKS_PASS=xxxxxx STAGE=/stage)"; rc=$?
[[ $rc == 0 && "$(nkeys "$L10")" == 2 ]] && ok "installer re-run: no extra key slot" || { bad "installer re-run: rc=$rc keys=$(nkeys "$L10")"; echo "$out"; }
umount /target
cp "$W/root/stage/key" "$W/oldkey"
out="$(prov "$L10" STAGE="$W/root/stage" INVOCATION_ID=t)"; rc=$?
own="$(grep -v '^Warning: Value .* entropy range' <<<"$out")"
[[ $rc == 0 && -z "$own" ]] && ok "first boot: exit 0 with no passphrase given" || { bad "first boot: rc=$rc"; echo "$out"; }
clevis luks list -d "$L10" | grep -q '"pcr_ids":"7"' && ok "first boot: bound with pcr_ids 7" || bad "first boot: not bound"
cryptsetup open --test-passphrase "$L10" --key-file="$W/oldkey" 2>/dev/null \
  && bad "first boot: one-time key still opens the disk" || ok "first boot: one-time key slot removed"
[[ ! -e "$W/root/stage" && "$(nkeys "$L10")" == 2 ]] \
  && ok "first boot: stage dir gone, passphrase + TPM slot left" || bad "first boot: leftovers, keys=$(nkeys "$L10")"
printf 'xxxxxx' | cryptsetup open --test-passphrase "$L10" --key-file=- && ok "first boot: passphrase still opens" || bad "first boot: passphrase lost"

# ---- first boot, Windows left lockoutAuth: queues the clear and reboots for it (bounded)
start_tpm; tpm2_changeauth -c l windowsSecret; L11="$(new_luks)"
: > "$W/ppi/request"; rm -f "$W/ppi/response" "$W/systemctl.log"
mount --bind "$W/root" /target
prov "$L11" LUKS_PASS=xxxxxx STAGE=/stage >/dev/null; umount /target
out="$(prov "$L11" STAGE="$W/root/stage" INVOCATION_ID=t PPI="$W/ppi")"; rc=$?
[[ $rc == 10 && "$(cat "$W/ppi/request")" == 5 && "$(cat "$W/systemctl.log" 2>/dev/null)" == *reboot* \
   && "$(cat "$W/root/stage/reboots")" == 1 ]] \
  && ok "first boot, lockoutAuth set: clear queued, reboot asked" || { bad "first boot lockout: rc=$rc"; echo "$out"; }
echo 3 > "$W/root/stage/reboots"; rm -f "$W/systemctl.log"
out="$(prov "$L11" STAGE="$W/root/stage" INVOCATION_ID=t PPI="$W/ppi")"; rc=$?
[[ $rc == 10 && ! -e "$W/systemctl.log" ]] && ok "first boot: no 4th reboot" || { bad "reboot loop: rc=$rc"; echo "$out"; }
rm -f "$W/systemctl.log"
out="$(prov "$L11" STAGE="$W/root/stage" PPI="$W/ppi")"; rc=$?
[[ $rc == 10 && ! -e "$W/systemctl.log" ]] && ok "by hand (not systemd): never reboots" || { bad "manual reboot: rc=$rc"; echo "$out"; }

# ---- curtin in-target: a chroot whose / is not PID 1's root. Binds right there, leaves the
# first-boot check; the first boot (outside the chroot) finds the slot unseals and cleans up.
# /dev rbind: /dev/tpmrm0 is a bind mount of the swtpm device. $W bound at the same path: the
# fake update-initramfs and the PPI files.
start_tpm; L12="$(new_luks)"; C="$W/chroot"
mkdir -p "$C"/{usr,etc,dev,proc,sys,w,var/lib,tmp,run} "$C$W"
for d in usr etc proc sys w; do mount --bind "/$d" "$C/$d"; done
mount --rbind /dev "$C/dev"; mount --bind "$W" "$C$W"
mkdir -p "$C/var/cache"; mount --bind /var/cache "$C/var/cache"   # clevis key generation reads the cracklib dict
# no kernel in the container, so no initramfs-tools: the installer check wants the file present
[[ -e /usr/sbin/update-initramfs ]] || cp "$W/bin/update-initramfs" /usr/sbin/update-initramfs
for l in bin sbin lib lib32 lib64 libx32; do [[ -L /$l ]] && ln -sfn "$(readlink /$l)" "$C/$l"; done
inchroot() { chroot "$C" env PATH="$W/bin:/usr/sbin:/usr/bin:/sbin:/bin" SB_VAR="$W/nosb" "$@" bash /w/provision.sh 2>&1; }
printf 'xxxxxx\n' > "$W/luks.pass"
out="$(inchroot DEV="$L12" LUKS_PASS_FILE="$W/luks.pass")"; rc=$?
own="$(grep -v -e '^Warning: Value .* entropy range' -e 'Locking directory' <<<"$out")"
[[ $rc == 0 && -z "$own" ]] && ok "in-target chroot (LUKS_PASS_FILE): exit 0, prints nothing of its own" || { bad "in-target: rc=$rc"; echo "$out"; }
clevis luks list -d "$L12" | grep -q '"pcr_ids":"7"' && ok "in-target chroot: bound to the TPM in the installer" || bad "in-target: not bound"
[[ -s "$C/var/lib/tpm-provision/key" && -L /etc/systemd/system/multi-user.target.wants/tpm-provision.service ]] \
  && ok "in-target chroot: first-boot check staged" || bad "in-target: not staged"
[[ "$(nkeys "$L12")" == 3 ]] && ok "in-target chroot: passphrase + one-time key + TPM slot" || bad "in-target: keys=$(nkeys "$L12")"
n="$(nslots "$L12")"
out="$(prov "$L12" STAGE="$C/var/lib/tpm-provision")"; rc=$?
[[ $rc == 0 && "$(nslots "$L12")" == "$n" && ! -e "$C/var/lib/tpm-provision" && "$(nkeys "$L12")" == 2 ]] \
  && ok "in-target -> first boot: slot already unseals, no rebind, one-time key removed" || { bad "in-target first boot: rc=$rc keys=$(nkeys "$L12")"; echo "$out"; }

# ---- curtin in-target, Windows left lockoutAuth: clear queued, install still succeeds
start_tpm; tpm2_changeauth -c l windowsSecret; L14="$(new_luks)"
: > "$W/ppi/request"; rm -f "$W/ppi/response"
out="$(inchroot DEV="$L14" LUKS_PASS=xxxxxx PPI="$W/ppi")"; rc=$?
[[ $rc == 0 && "$(cat "$W/ppi/request")" == 5 && "$out" == *"left to the first boot"* \
   && -s "$C/var/lib/tpm-provision/key" && "$(nslots "$L14")" == 0 ]] \
  && ok "in-target, lockoutAuth set: clear queued, exit 0, first boot staged" || { bad "in-target lockout: rc=$rc"; echo "$out"; }
# disk boot reads another PCR 7 than the installer did: first boot rebinds, drops the stale slot
start_tpm; L15="$(new_luks)"; rm -rf "$C/var/lib/tpm-provision"
inchroot DEV="$L15" LUKS_PASS=xxxxxx >/dev/null
old="$(clevis luks list -d "$L15" | awk -F: '/pcr_ids/ { print $1 }')"
tpm2_pcrextend 7:sha256=0000000000000000000000000000000000000000000000000000000000000002
out="$(prov "$L15" STAGE="$C/var/lib/tpm-provision")"; rc=$?
new="$(clevis luks list -d "$L15" | awk -F: '/pcr_ids/ { print $1 }')"
[[ $rc == 0 && -n "$new" && "$(wc -l <<<"$new")" == 1 && "$(nkeys "$L15")" == 2 ]] && clevis luks pass -d "$L15" -s "$new" >/dev/null 2>&1 \
  && ok "in-target, PCR 7 differs at first boot: rebound, stale slot + one-time key gone" || { bad "PCR mismatch: rc=$rc old=$old new=$new keys=$(nkeys "$L15")"; echo "$out"; }

# a TPM step fails in the installer (here: a PCR bank the TPM lacks): install still succeeds
start_tpm; L16="$(new_luks)"; rm -rf "$C/var/lib/tpm-provision"
out="$(inchroot DEV="$L16" LUKS_PASS=xxxxxx PCR_BANK=sha384)"; rc=$?
[[ $rc == 0 && "$out" == *"left to the first boot"* && -s "$C/var/lib/tpm-provision/key" ]] \
  && ok "in-target, TPM step fails: exit 0, says so, first boot staged" || { bad "in-target fail: rc=$rc"; echo "$out"; }

# NO_INSTALLER=1: a normal run even in a chroot
start_tpm; L17="$(new_luks)"; rm -rf "$C/var/lib/tpm-provision"
out="$(inchroot DEV="$L17" LUKS_PASS=xxxxxx NO_INSTALLER=1)"; rc=$?
[[ $rc == 0 && ! -e "$C/var/lib/tpm-provision" && "$(nkeys "$L17")" == 2 ]] \
  && ok "NO_INSTALLER=1 in a chroot: binds, stages nothing" || { bad "NO_INSTALLER: rc=$rc"; echo "$out"; }
umount "$C/var/cache"; umount -R "$C/dev"; for d in w sys proc etc usr; do umount "$C/$d"; done; umount "$C$W"
rm -f /etc/systemd/system/tpm-provision.service /etc/systemd/system/multi-user.target.wants/tpm-provision.service /usr/local/sbin/tpm-provision

# ---- Secure Boot off: still binds (PCR 7 has a value), but says so; on: silent
start_tpm; L13="$(new_luks)"
printf '\x06\x00\x00\x00\x00' > "$W/sb_off"; printf '\x06\x00\x00\x00\x01' > "$W/sb_on"
out="$(prov "$L13" LUKS_PASS=xxxxxx SB_VAR="$W/sb_off")"; rc=$?
[[ $rc == 0 && "$out" == *"Secure Boot is off"* ]] && clevis luks list -d "$L13" | grep -q '"pcr_ids":"7"' \
  && ok "Secure Boot off: warns, still binds" || { bad "SB off: rc=$rc"; echo "$out"; }
out="$(prov "$L13" SB_VAR="$W/sb_on")"; rc=$?
[[ $rc == 0 && "$out" != *"Secure Boot"* ]] && ok "Secure Boot on: no warning" || { bad "SB on: rc=$rc"; echo "$out"; }
out="$(prov "$L13" SB_VAR="$W/sb_off" PCR_IDS=0)"; rc=$?
[[ "$out" != *"Secure Boot"* ]] && ok "Secure Boot off, PCR 7 not used: no warning" || { bad "SB off no pcr7"; echo "$out"; }

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
