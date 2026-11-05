#!/usr/bin/env bash
# Run on a Linux box: bash tsme6/t/test_tsme_net.sh
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
echo "work dir: $work"

python3 "$here/tsme_net.py" selftest | tail -n 1 | grep -q 'SELFTEST: PASS'
bash -n "$here/verify.sh"
"$here/verify.sh" --help | grep -q 'tsmeping'
OUT="$work/out_status" "$here/verify.sh" --status >/dev/null

# fake ViCom install: the sdk step must find it, read the version, and see no missing files
bin="$work/RuS/ViCom_21.0/bin"
mkdir -p "$bin/PhylisKernelRouting" "$work/RuS/ViCom_21.0/inc" "$work/prefix/drive_c/windows/system32"
printf '#arch=win32\n' > "$work/prefix/system.reg"
fake_pe() {  # $1 path: MZ header pointing at a PE/i386 header, plus a VS_FIXEDFILEINFO 21.0.3.7
  python3 - "$1" <<'EOF'
import struct, sys
d = bytearray(b"MZ" + b"\0" * 58 + struct.pack("<I", 64) + b"PE\0\0" + struct.pack("<H", 0x14c) + b"\0" * 30)
d += b"\xbd\x04\xef\xfe" + b"\0\0\1\0" + struct.pack("<II", 21 << 16, (3 << 16) | 7)
open(sys.argv[1], "wb").write(d)
EOF
}
for f in ViComLoaderManager.dll ViComResourceManager.dll TsmeWorker.dll TsmeAdmin.dll TsmeTools.dll \
         TsmeParameters.dll TsmeResultProcessor.dll ServiceExtension_TSME.dll log4cxx.dll RSToolbox.dll \
         RuSProcessPhysicalLayer.exe ViComGSM.dll ViComGSMe.dll GS3Worker.dll GsmDemodulator.dll \
         ViComWCDMA.dll ViComWCDMAe.dll UmtsDemodulator.dll SampleForViComGSM.exe SampleForViComWCDMA.exe; do
  fake_pe "$bin/$f"
done
touch "$bin/tsme_05081000.bin"
out="$work/out_sdk"
OUT=$out WINEPREFIX="$work/prefix" TSME_TOOLS_DIR="$work/RuS" "$here/verify.sh" sdk > "$work/sdk.log" 2>&1 || true
grep -q 'ViComLoaderManager.dll 21.0.3.7 x86' "$work/sdk.log"
grep -q 'all common + GSM + WCDMA ViCom files present' "$work/sdk.log"
grep -q 'PhylisKernelRouting folder present' "$work/sdk.log"
grep -q 'tsme_05081000.bin' "$work/sdk.log"
grep -q 'msvcr120.dll missing' "$work/sdk.log"
grep -q 'VICOM_HOME not set' "$work/sdk.log"

# one missing file must be reported
rm "$bin/ViComGSMe.dll"
OUT=$out WINEPREFIX="$work/prefix" TSME_TOOLS_DIR="$work/RuS" "$here/verify.sh" sdk > "$work/sdk2.log" 2>&1 || true
grep -q 'missing in bin: ViComGSMe.dll' "$work/sdk2.log"

# faked files like a hand-made bin: symlink to another DLL, 19-byte exe, mixed versions
fake_pe "$bin/ViComGSMe.dll"
rm "$bin/ViComResourceManager.dll"; ln -s ViComLoaderManager.dll "$bin/ViComResourceManager.dll"
printf '#!/bin/sh\nexit 0\n' > "$bin/RuSProcessPhysicalLayer.exe"
python3 - "$bin/TsmeWorker.dll" <<'PY'
import struct, sys
d = bytearray(b"MZ" + b"\0" * 58 + struct.pack("<I", 64) + b"PE\0\0" + struct.pack("<H", 0x14c) + b"\0" * 30)
d += b"\xbd\x04\xef\xfe" + b"\0\0\1\0" + struct.pack("<II", 26 << 16, 4428)
open(sys.argv[1], "wb").write(d)
PY
OUT=$out WINEPREFIX="$work/prefix" TSME_TOOLS_DIR="$work/RuS" "$here/verify.sh" sdk > "$work/sdk3.log" 2>&1 || true
grep -q 'ViComResourceManager.dll is a SYMLINK' "$work/sdk3.log"
grep -q 'RuSProcessPhysicalLayer.exe is not a 32-bit Windows binary' "$work/sdk3.log"
grep -q 'MIXED ViCom versions' "$work/sdk3.log"
grep -q 'ViCom install is broken' "$work/sdk3.log"
grep -q 'Phylis runtime DLLs missing' "$work/sdk3.log"
grep -q 'tsme6 kit ' "$work/sdk3.log"

# probe with beacons only (no Device Manager request) must be PARTIAL, never PASS
cat > "$work/beacon.json" <<'JS'
{"discovery_requests": [], "multicast_streams": [{"src": "10.0.0.9", "sport": 17476, "dst": "239.192.1.7", "dport": 17476, "count": 5, "max_len": 286}]}
JS
python3 "$here/tsme_net.py" probe "$work/beacon.json" --timeout 1 > "$work/probe.log" 2>&1 || true
grep -q 'send path is untested\|SEND path is untested' "$work/probe.log"
! grep -q '^RESULT: PASS' "$work/probe.log"

echo "tsme6 tests: PASS"
