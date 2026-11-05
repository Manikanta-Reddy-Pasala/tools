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

echo "tsme6 tests: PASS"
