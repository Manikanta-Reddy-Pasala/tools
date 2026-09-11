#!/usr/bin/env bash
# shellcheck disable=SC2034  # globals set here are read by the sourced tpmfix.sh functions
# Function-level tests for ../tpmfix.sh: crypttab repair, keyscript slot discovery,
# initrd verification. Real cryptsetup on a LUKS2 image, real unmkinitramfs on
# jammy-shaped initrds (uncompressed early microcode cpio + zstd main cpio).
# Needs NO TPM. Needs: cryptsetup, cpio, zstd, unmkinitramfs, GNU stat.
#   bash t/tpmfix-test.sh           # everything but the live-mapping rename
#   sudo bash t/tpmfix-test.sh      # also opens real dm-crypt mappings and renames one
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
pass=0 fail=0
ok()  { pass=$((pass+1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf 'FAIL %s\n' "$1"; }
eq()  { [[ "$2" == "$3" ]] && ok "$1" || bad "$1: got [$2] want [$3]"; }

TPMFIX_LIB=1 source "$HERE/../tpmfix.sh"
DRY=0 STATE="$W/state"

# ---------------------------------------------------------------- crypttab parsing
UUID_DEV=696358f6-3b3c-4eb5-a198-7c3d3270cafe PARTUUID_DEV=aaaa-bbbb DEV=/dev/null
CT="$W/crypttab"
cat > "$CT" <<'EOF'
# <target> <source> <key> <options>

other UUID=11111111-2222-3333-4444-555555555555 none luks
dm_crypt-0 UUID=696358f6-3b3c-4eb5-a198-7c3d3270cafe none luks,keyscript=/usr/local/sbin/tpm2-getkey
# trailing comment
EOF
chmod 0640 "$CT"
ct_load
eq "entry line"       "$CT_LN"   4
eq "entry name"       "$CT_NAME" dm_crypt-0
eq "entry key"        "$CT_KEY"  none
eq "entry keyscript"  "$CT_KS"   /usr/local/sbin/tpm2-getkey
eq "strip keeps rest" "$(strip_keyscript 'luks,discard,keyscript=/x,tries=3')" "luks,discard,tries=3"
eq "strip empties to luks" "$(strip_keyscript 'keyscript=/x')" "luks"
stock_keyscript decrypt_keyctl && ok "bare name is stock" || bad "bare name is stock"
stock_keyscript /lib/cryptsetup/scripts/passdev && ok "/lib path is stock" || bad "/lib path is stock"
stock_keyscript /usr/local/sbin/tpm2-getkey && bad "custom not stock" || ok "custom not stock"
ks_is_tpm /usr/local/sbin/tpm2-getkey && ok "tpm by name" || bad "tpm by name"

before_other="$(sed -n 3p "$CT")"
out="$(fix_crypttab 2>&1)"; rc=$?
fix_crypttab >/dev/null 2>&1   # second call re-reads: should now be a no-op
eq "fix rc" "$rc" 0
eq "fixed line" "$(sed -n 4p "$CT")" "dm_crypt-0 UUID=696358f6-3b3c-4eb5-a198-7c3d3270cafe none luks"
eq "other line untouched" "$(sed -n 3p "$CT")" "$before_other"
eq "comments kept" "$(sed -n 1p "$CT")" "# <target> <source> <key> <options>"
eq "line count" "$(wc -l < "$CT" | tr -d ' ')" 5
eq "mode kept" "$(stat -c %a "$CT")" 640
eq "one backup" "$(ls "$W"/crypttab.tpmfix-*.bak | wc -l | tr -d ' ')" 1
grep -q 'keyscript=/usr/local/sbin/tpm2-getkey' "$W"/crypttab.tpmfix-*.bak && ok "backup has original" || bad "backup has original"
eq "idempotent (no 2nd change)" "$CT_CHANGED" 0

# key field that was the keyscript's argument becomes none
printf 'root_crypt UUID=%s /some/arg luks,keyscript=/usr/local/sbin/tpm2-getkey,discard\n' "$UUID_DEV" > "$CT"
fix_crypttab >/dev/null 2>&1
eq "key arg -> none" "$(cat "$CT")" "root_crypt UUID=$UUID_DEV none luks,discard"

# PARTUUID and /dev path sources
printf 'x PARTUUID=aaaa-bbbb none luks,keyscript=/opt/tpm-unlock\n' > "$CT"; ct_load
eq "partuuid match" "$CT_NAME" x
printf 'y /dev/null none luks\n' > "$CT"; ct_load
eq "/dev path match" "$CT_NAME" y
printf 'z UUID=deadbeef none luks\n' > "$CT"; ct_load
eq "no match -> empty" "$CT_LN" ""

# stock keyscript left alone, custom non-TPM refused
printf 'a UUID=%s none luks,keyscript=decrypt_keyctl\n' "$UUID_DEV" > "$CT"
fix_crypttab >/dev/null 2>&1; rc=$?
eq "stock rc" "$rc" 0; grep -q decrypt_keyctl "$CT" && ok "stock kept" || bad "stock kept"
printf '#!/bin/sh\ncat /media/usb/key\n' > "$W/usbkey"; chmod +x "$W/usbkey"
printf 'a UUID=%s none luks,keyscript=%s\n' "$UUID_DEV" "$W/usbkey" > "$CT"
fix_crypttab >/dev/null 2>&1; rc=$?
eq "non-tpm custom rc" "$rc" 2; grep -q usbkey "$CT" && ok "non-tpm custom kept" || bad "non-tpm custom kept"

# DRY writes nothing
printf 'a UUID=%s none luks,keyscript=/usr/local/sbin/tpm2-getkey\n' "$UUID_DEV" > "$CT"
DRY=1 fix_crypttab >/dev/null 2>&1
grep -q keyscript "$CT" && ok "DRY left file" || bad "DRY left file"

# ---------------------------------------------------------------- LUKS: slots
IMG="$W/luks.img"; truncate -s 40M "$IMG"
printf 'correct horse' > "$W/pw"
cryptsetup luksFormat -q --type luks2 --pbkdf pbkdf2 --pbkdf-force-iterations 1000 "$IMG" "$W/pw" >/dev/null 2>&1 \
  || { echo "luksFormat failed"; exit 2; }
head -c 32 /dev/urandom > "$W/tpmkey"
cryptsetup luksAddKey -q --pbkdf pbkdf2 --pbkdf-force-iterations 1000 --key-file "$W/pw" "$IMG" "$W/tpmkey" >/dev/null 2>&1
DEV="$IMG"
luks_pass_ok 'correct horse' "$IMG" && ok "passphrase accepted" || bad "passphrase accepted"
eq "passphrase slot" "$PASS_SLOT" 0
luks_pass_ok 'wrong' "$IMG" && bad "wrong rejected" || ok "wrong rejected"
eq "slot list" "$(luks_slots | tr '\n' ' ')" "0 1 "

# a keyscript that emits the TPM key, the way tpm2-getkey would before the clear
mkdir -p "$W/sbin"
printf '#!/bin/sh\n# tpm2_unseal stand-in\n[ "$CRYPTTAB_NAME" = dm_crypt-0 ] || exit 1\ncat %s\n' "$W/tpmkey" > "$W/sbin/tpm2-getkey"
chmod +x "$W/sbin/tpm2-getkey"
CT_KS="$W/sbin/tpm2-getkey" CT_NAME=dm_crypt-0 CT_KEY=none CT_OPTS=luks
eq "keyscript slot found" "$(keyscript_slot)" 1
printf '#!/bin/sh\nexit 1\n' > "$W/sbin/tpm2-getkey"   # after the clear: unseal fails
eq "dead keyscript -> empty" "$(keyscript_slot)" ""

# ---------------------------------------------------------------- initrd verification
mkinitrd() {  # $1 out, $2 crypttab line ("" = no cryptroot dir), $3 1=with clevis hook
  local d; d="$(mktemp -d)"
  mkdir -p "$d/early/kernel/x86/microcode" "$d/main/scripts/local-top" "$d/main/bin"
  head -c 4096 /dev/zero > "$d/early/kernel/x86/microcode/GenuineIntel.bin"
  echo '#!/bin/sh' > "$d/main/init"
  if [[ -n "$2" ]]; then mkdir -p "$d/main/cryptroot"; printf '%s\n' "$2" > "$d/main/cryptroot/crypttab"; fi
  [[ "${3:-0}" == 1 ]] && echo '#!/bin/sh' > "$d/main/scripts/local-top/clevis"
  ( cd "$d/early" && find . | cpio -o -H newc --quiet ) > "$1"
  ( cd "$d/main"  && find . | cpio -o -H newc --quiet | zstd -q -c ) >> "$1"
  rm -rf "$d"
}
CT_NAME=dm_crypt-0 CT_KS="" DEV=/dev/nvme0n1p3
mkinitrd "$W/good" "dm_crypt-0 UUID=$UUID_DEV none luks" 1
verify_initrd "$W/good" >/dev/null 2>&1 && ok "good initrd passes" || bad "good initrd passes"
mkinitrd "$W/ks" "dm_crypt-0 UUID=$UUID_DEV none luks,keyscript=/usr/local/sbin/tpm2-getkey" 1
verify_initrd "$W/ks" >/dev/null 2>&1 && bad "stale keyscript initrd rejected" || ok "stale keyscript initrd rejected"
mkinitrd "$W/none" "" 1
verify_initrd "$W/none" >/dev/null 2>&1 && bad "no cryptroot rejected" || ok "no cryptroot rejected"
mkinitrd "$W/other" "other UUID=x none luks" 1
verify_initrd "$W/other" >/dev/null 2>&1 && bad "wrong target rejected" || ok "wrong target rejected"
mkinitrd "$W/noclevis" "dm_crypt-0 UUID=$UUID_DEV none luks" 0
msg="$(verify_initrd "$W/noclevis" 2>&1)"; rc=$?
eq "no clevis hook still passes" "$rc" 0
[[ "$msg" == *"no clevis hook"* ]] && ok "no clevis hook warned" || bad "no clevis hook warned"
head -c 3000 "$W/good" > "$W/trunc"
verify_initrd "$W/trunc" >/dev/null 2>&1 && bad "truncated rejected" || ok "truncated rejected"
verify_initrd "$W/missing" >/dev/null 2>&1 && bad "missing rejected" || ok "missing rejected"
CT_KS=decrypt_keyctl
mkinitrd "$W/stock" "dm_crypt-0 UUID=$UUID_DEV none luks,keyscript=decrypt_keyctl" 1
verify_initrd "$W/stock" >/dev/null 2>&1 && ok "kept stock keyscript passes" || bad "kept stock keyscript passes"

# ---------------------------------------------------------------- live mapping rename
# Root only: opens real dm-crypt mappings. Mirrors the field failure - the disk was
# unlocked by hand as 'os-vg' while crypttab says 'dm_crypt-0', with a mounted
# filesystem on top (root in the real case), and renamed while in use.
if [[ $(id -u) -eq 0 ]]; then
  A="tpmfixT-live-$$" B="tpmfixT-other-$$" C="tpmfixT-want-$$"
  L1="$(losetup -f --show "$IMG")"
  IMG2="$W/luks2.img"; truncate -s 40M "$IMG2"
  cryptsetup luksFormat -q --type luks2 --pbkdf pbkdf2 --pbkdf-force-iterations 1000 "$IMG2" "$W/pw" >/dev/null 2>&1
  L2="$(losetup -f --show "$IMG2")"
  cryptsetup open --key-file "$W/pw" "$L1" "$A" && cryptsetup open --key-file "$W/pw" "$L2" "$B"
  mkfs.ext4 -q "/dev/mapper/$A" && mkdir -p "$W/mnt" && mount "/dev/mapper/$A" "$W/mnt" && echo before > "$W/mnt/f"

  DEV="$L1" DRY=0
  eq "live name found" "$(live_name)" "$A"
  CT_NAME="$B"
  fix_mapping >/dev/null 2>&1 && bad "refuses rename onto an existing mapping" || ok "refuses rename onto an existing mapping"
  eq "still original name" "$(live_name)" "$A"
  CT_NAME="$C"
  DRY=1 fix_mapping >/dev/null 2>&1
  eq "DRY did not rename" "$(live_name)" "$A"
  fix_mapping >/dev/null 2>&1 && ok "rename while mounted" || bad "rename while mounted"
  eq "live name now crypttab name" "$(live_name)" "$C"
  echo after >> "$W/mnt/f" && sync && ok "fs still writable after rename" || bad "fs still writable after rename"
  # the kernel keeps the old source string; the hook stat -L's it, so it must resolve
  eq "mount keeps old source" "$(findmnt -no SOURCE "$W/mnt")" "/dev/mapper/$A"
  [[ -L "/dev/mapper/$A" ]] && ok "compat link made for direct mount" || bad "compat link made for direct mount"
  eq "old path resolves to renamed node" "$(stat -L -c %t:%T "/dev/mapper/$A" 2>&1)" "$(stat -L -c %t:%T "/dev/mapper/$C")"
  drop_compat_link
  [[ -e "/dev/mapper/$A" ]] && bad "compat link dropped" || ok "compat link dropped"
  msg="$(fix_mapping 2>&1)"; rc=$?
  eq "matching is a no-op" "$rc" 0
  [[ "$msg" == *matching* ]] && ok "matching reported" || bad "matching reported"

  umount "$W/mnt"; cryptsetup close "$C"; cryptsetup close "$B"; losetup -d "$L1" "$L2"
else
  printf 'skip live mapping rename (needs root)\n'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
