#!/usr/bin/env bash
# TSME6 verification in a Wine/Docker box, built from the R&S manuals:
#   TSME6 User Manual 4900.0033.02-08 (network, firewall, troubleshooting)
#   ViCom User Manual 1505.1329.42-26 (package layout, loader, sample apps)
#
# How the scanner is reached (from those manuals):
#   app -> ViCom DLLs (CViComLoader<...>) -> RuSProcessPhysicalLayer.exe
#       -> UDP: PC->TSME6 5140/16962, TSME6->PC 17476, multicast 239.192.1.7
#   The TSME6 does NOT answer ping. Options (K21 WCDMA, K23 GSM ...) live on
#   the scanner; the ViCom sample apps show them as "Option Mask" after Load.
#
# Read-only except: packet captures, UDP probes to the scanner, and starting
# the exes you name. Nothing is installed or changed on the system; fixes are
# printed as commands for you to run.
set -u

usage() {
  cat <<'EOF'
usage: ./verify.sh <step>

  --status    read-only: what is set and installed, what the last runs found
  net         NIC, subnet, MTU 9000, multicast route, firewall ports, ARP, VPN, other TSME apps
  discover    capture while you press Search/Refresh in the TSME Device Manager
  probe       re-send that discovery from this box and wait for the scanner (no Wine)
  sdk         check the ViCom / TSME Tools install: versions, required DLLs,
              Phylis kernel, firmware files, VC++ 2008/2013 runtimes, VICOM_HOME
  tsmeping    run R&S TsmePing.exe under Wine (the manual's connection test)
  scan        GSM (2G) then WCDMA (3G) with the ViCom sample apps under Wine,
              collect LogFiles\ViComMeasurements.txt
  all         net, discover, probe, sdk, tsmeping, scan

environment:
  TSME_TOOLS_DIR  folder holding the R&S software: the ViCom folder (C:\RuS\ViCom_<ver>)
                  and/or TSME Tools (C:\Program Files\Rohde-Schwarz\TSME Tools); unix or C:\ path
  TSME_IP         scanner IP (default 192.168.0.2, the factory address)
  IFACE           NIC wired to the scanner (default: route to TSME_IP)
  DM_EXE          TSME Device Manager exe; 'discover' starts it if set
  GSM_EXE / WCDMA_EXE   override the sample apps (e.g. your scanner_main)
  GSM_ARGS / WCDMA_ARGS arguments for console exes
  SCAN_SECS       max seconds per scan (default 600 for GUI samples, 120 console)
  DISCOVER_SECS   capture length (default 60)
  WINEPREFIX, WINE, OUT
EOF
}

STEP=${1:-}
case $STEP in ''|-h|--help|help) usage; exit 0 ;; esac

HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$PWD/tsme6_verify_out}
WINE=${WINE:-wine}
export WINEPREFIX=${WINEPREFIX:-$HOME/.wine}
TSME_IP=${TSME_IP:-192.168.0.2}
IFACE=${IFACE:-}
DM_EXE=${DM_EXE:-}
GSM_EXE=${GSM_EXE:-}; WCDMA_EXE=${WCDMA_EXE:-}
GSM_ARGS=${GSM_ARGS:-}; WCDMA_ARGS=${WCDMA_ARGS:-}
SCAN_SECS=${SCAN_SECS:-}
DISCOVER_SECS=${DISCOVER_SECS:-60}
TSME6_MCAST=239.192.1.7
TEST_MCAST=239.192.1.5
RX_PORT=17476
TX_PORTS="5140 16962"
mkdir -p "$OUT"
SUMMARY="$OUT/summary_${STEP#--}_$(date +%H%M%S).txt"

say()  { printf '[%s] %s\n' "$1" "$2" | tee -a "$SUMMARY"; }
have() { command -v "$1" >/dev/null 2>&1; }
root() { [ "$(id -u)" -eq 0 ]; }
pyjson() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print($2)" "$1" 2>/dev/null; }

to_unix() {
  local p=$1 u
  case $p in /*|./*|../*) printf '%s\n' "$p"; return ;; esac
  u=$("$WINE" winepath.exe -u "$p" 2>/dev/null | tr -d '\r' | tail -n1)
  [ -n "$u" ] && { printf '%s\n' "$u"; return; }
  p=${p//\\//}
  case $p in [cC]:/*) printf '%s\n' "$WINEPREFIX/drive_c/${p:3}" ;; *) printf '%s\n' "$p" ;; esac
}
TOOLS=""
[ -n "${TSME_TOOLS_DIR:-}" ] && TOOLS=$(to_unix "$TSME_TOOLS_DIR")

pe_arch() {
  local f=$1 off m
  [ "$(od -An -tx2 -N2 "$f" 2>/dev/null | tr -d ' \n')" = 5a4d ] || { echo "-"; return; }
  off=$(od -An -tu4 -j60 -N4 "$f" | tr -d ' \n')
  m=$(od -An -tx2 -j$((off + 4)) -N2 "$f" 2>/dev/null | tr -d ' \n')
  case $m in 014c) echo x86 ;; 8664) echo x64 ;; *) echo "?" ;; esac
}
pe_ver() { python3 "$HERE/tsme_net.py" pever "$1" 2>/dev/null | cut -f1; }

pick_iface() {
  [ -n "$IFACE" ] && return
  have ip && IFACE=$(ip route get "$TSME_IP" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1)
}
iface_ip() { have ip && ip -o -4 addr show dev "$1" 2>/dev/null | awk '{print $4}' | head -n1; }

# ViCom bin = folder holding ViComLoaderManager.dll; TSME Tools = folder holding TsmePing.exe or the Device Manager
find_vicom_bin() {
  [ -n "$TOOLS" ] && [ -d "$TOOLS" ] || return
  find "$TOOLS" -type f -iname 'ViComLoaderManager.dll' 2>/dev/null | head -n1 | xargs -r -d '\n' dirname
}
find_file() { [ -n "$TOOLS" ] && find "$TOOLS" -type f -iname "$1" 2>/dev/null | head -n1; }

other_tsme_apps() {
  pgrep -af 'RuSProcessPhysicalLayer|TSME Device Manager|TsmeDeviceManager|ROMES|Nestor|SampleForViCom|TsmePing' 2>/dev/null \
    | grep -v -e verify.sh -e pgrep
}

# ---------------------------------------------------------------- status
step_status() {
  local vb
  say INFO "OUT=$OUT  WINEPREFIX=$WINEPREFIX  wine=$("$WINE" --version 2>/dev/null || echo missing)"
  say INFO "TSME_TOOLS_DIR=${TSME_TOOLS_DIR:-unset} -> ${TOOLS:-unset}  TSME_IP=$TSME_IP  IFACE=${IFACE:-auto}"
  for t in ip tcpdump python3 ss timeout ethtool; do
    if have "$t"; then say OK "$t installed"; else say WARN "$t missing (apt-get install -y iproute2 tcpdump python3 ethtool)"; fi
  done
  if root; then say OK "running as root (tcpdump works)"; else say WARN "not root: packet capture is skipped"; fi
  vb=$(find_vicom_bin)
  [ -n "$vb" ] && say INFO "ViCom bin: $vb"
  [ -f "$OUT/discovery.json" ] && say INFO "last discovery: scanners $(pyjson "$OUT/discovery.json" 'd["scanner_candidates"]')"
  find "$OUT" -maxdepth 1 -name 'scan_*' -printf '%f\n' 2>/dev/null | while IFS= read -r d; do say INFO "scan run: $d"; done
  return 0
}

# ---------------------------------------------------------------- net
step_net() {
  pick_iface
  if [ -z "$IFACE" ]; then say FAIL "No route to $TSME_IP. Set IFACE, and give the NIC an address in the scanner's subnet."; return 1; fi
  local flags mtu cidr ip rp mdev apps fc neigh
  flags=$(ip -o link show dev "$IFACE" 2>/dev/null)
  mtu=$(cat "/sys/class/net/$IFACE/mtu" 2>/dev/null)
  cidr=$(iface_ip "$IFACE"); ip=${cidr%/*}
  say INFO "TSME_IP=$TSME_IP via $IFACE  ip=$cidr  mtu=$mtu"
  case $IFACE in docker0|br-*|veth*|cni*) say FAIL "$IFACE is a Docker/bridge interface, not the NIC wired to the scanner: start the container with --network host and set IFACE" ;; esac
  case $flags in *LOWER_UP*) say OK "$IFACE link up" ;; *) say FAIL "$IFACE link down (cable, scanner power, LAN LED 2 yellow?)" ;; esac
  case $flags in *MULTICAST*) say OK "$IFACE has MULTICAST" ;; *) say FAIL "$IFACE has no MULTICAST: ip link set $IFACE multicast on" ;; esac
  case $ip in
    192.168.0.2) say FAIL "PC uses 192.168.0.2, the scanner's own address" ;;
    192.168.0.*) say OK "PC in 192.168.0.0/24 (manual: PC 192.168.0.1, scanner 192.168.0.2, no gateway)" ;;
    169.254.*)   say OK "PC on auto-IP 169.254.x.y (full/partial auto-IP mode)" ;;
    172.1[6-9].*|172.2[0-9].*|172.3[01].*) say FAIL "IP $ip is a Docker bridge address: use docker run --network host" ;;
    *)           say WARN "PC IP $ip is not 192.168.0.x or 169.254.x.y: check the scanner's subnet" ;;
  esac
  if [ "${mtu:-0}" -ge 9000 ]; then say OK "MTU $mtu (manual: 9k jumbo frames, 9014 bytes, required)"
  else say FAIL "MTU $mtu: manual requires 9k jumbo frames -> on the host: ip link set $IFACE mtu 9000"; fi
  local g
  for g in "$TSME6_MCAST" "$TEST_MCAST"; do
    mdev=$(ip route get "$g" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1)
    if [ "$mdev" = "$IFACE" ]; then say OK "multicast $g leaves via $IFACE"
    else say FAIL "multicast $g leaves via '${mdev:-none}', not $IFACE -> ip route add 224.0.0.0/4 dev $IFACE"; fi
  done
  rp=$(cat "/proc/sys/net/ipv4/conf/$IFACE/rp_filter" 2>/dev/null)
  [ "${rp:-0}" = 1 ] && say WARN "rp_filter=1 on $IFACE: if replies come from another subnet -> sysctl -w net.ipv4.conf.$IFACE.rp_filter=2"
  ip -o link 2>/dev/null | awk -F': ' '{print $2}' | grep -qE '^(tun|tap|wg|ppp|vpn)' \
    && say WARN "VPN-like interface present: manual says the TSME6 does not work while the PC is on VPN"
  if have ethtool; then
    fc=$(ethtool -a "$IFACE" 2>/dev/null | awk '/^RX:/{rx=$2} /^TX:/{tx=$2} END{print "rx=" rx " tx=" tx}')
    say INFO "flow control $fc (ViCom manual: enable; TSME6 manual: disable if sporadic network issues)"
  fi
  neigh=$(ip neigh show "$TSME_IP" dev "$IFACE" 2>/dev/null)
  say INFO "ARP for $TSME_IP: ${neigh:-none yet}"
  if root && have iptables; then
    if iptables -S INPUT 2>/dev/null | head -n1 | grep -q DROP; then
      say WARN "iptables INPUT policy DROP: allow udp from $TSME_IP (ports $RX_PORT, $TX_PORTS) and multicast"
    else say OK "iptables INPUT not dropping by default"; fi
  fi
  say INFO "multicast groups joined on $IFACE: $(awk -v i="$IFACE" '$2==i{f=1;next} /^[0-9]/{f=0} f{print $1}' /proc/net/igmp 2>/dev/null | tr '\n' ' ')"
  apps=$(other_tsme_apps)
  if [ -n "$apps" ]; then
    say WARN "Other TSME programs running (manual: only ONE app may use the scanner at a time; close the Device Manager before your app):"
    printf '%s\n' "$apps" | cut -c1-150 | while IFS= read -r l; do say WARN "   $l"; done
  else say OK "no other TSME program running"; fi
  say INFO "The TSME6 does not answer ping; use './verify.sh tsmeping' or 'probe' instead"
}

# ---------------------------------------------------------------- discover
step_discover() {
  pick_iface
  if ! have tcpdump || ! root; then say FAIL "discover needs tcpdump and root"; return 1; fi
  if ! have python3; then say FAIL "discover needs python3"; return 1; fi
  if [ -z "$IFACE" ]; then say FAIL "no interface; set IFACE"; return 1; fi
  local pcap="$OUT/discover.pcap" tp dmp="" cand
  tcpdump -i "$IFACE" -nn -s 0 -w "$pcap" 'udp or igmp' >/dev/null 2>"$OUT/tcpdump_discover.err" &
  tp=$!
  sleep 1
  if [ -n "$DM_EXE" ]; then
    local dm; dm=$(to_unix "$DM_EXE")
    ( cd "$(dirname "$dm")" && exec "$WINE" "$dm" ) >"$OUT/dm_stdout.log" 2>&1 &
    dmp=$!
    say INFO "started Device Manager"
  fi
  say INFO "capturing ${DISCOVER_SECS}s on $IFACE: in the TSME Device Manager press Search/Refresh NOW and open the Options tab"
  sleep "$DISCOVER_SECS"
  kill -INT "$tp" 2>/dev/null; wait "$tp" 2>/dev/null
  [ -n "$dmp" ] && kill "$dmp" 2>/dev/null
  python3 "$HERE/tsme_net.py" analyze "$pcap" --out "$OUT/discovery.json" | tee "$OUT/discovery.txt"
  cand=$(pyjson "$OUT/discovery.json" '" ".join(d["scanner_candidates"])')
  if [ -n "$cand" ]; then
    say OK "scanner seen: $cand"
    pyjson "$OUT/discovery.json" '"\n".join("%s %s" % (k, v) for k, v in d["scanner_macs"].items() if v)' \
      | while read -r sip smac; do
          say INFO "   if ARP to the scanner fails (ViCom sets static ARP on Windows): ip neigh replace $sip lladdr $smac dev $IFACE nud permanent"
        done
  else
    say FAIL "no scanner traffic seen (see discovery.txt); expected UDP on $TX_PORTS / $RX_PORT and multicast $TSME6_MCAST"
  fi
}

# ---------------------------------------------------------------- probe
step_probe() {
  pick_iface
  [ -f "$OUT/discovery.json" ] || { say FAIL "run 'discover' first"; return 1; }
  local ip; ip=$(iface_ip "$IFACE"); ip=${ip%/*}
  python3 "$HERE/tsme_net.py" probe "$OUT/discovery.json" --iface-ip "$ip" --tsme-ip "$TSME_IP" --timeout 5 | tee "$OUT/probe.txt"
  if grep -q '^RESULT: PASS' "$OUT/probe.txt"; then say OK "multicast discovery works from this box without Wine"; return 0; fi
  say WARN "no answer from a random port; retrying from the Device Manager's own source port"
  python3 "$HERE/tsme_net.py" probe "$OUT/discovery.json" --iface-ip "$ip" --tsme-ip "$TSME_IP" --timeout 5 --same-port | tee -a "$OUT/probe.txt"
  if grep -q '^RESULT: PASS' "$OUT/probe.txt"; then say OK "works only from the original source port (scanner answers a fixed port)"
  else say FAIL "scanner does not answer this box: network problem (not Wine). Check net step."; fi
}

# ---------------------------------------------------------------- sdk
step_sdk() {
  [ -n "$TOOLS" ] && [ -d "$TOOLS" ] || { say FAIL "set TSME_TOOLS_DIR to the folder with the ViCom and/or TSME Tools install"; return 1; }
  local vb vroot f miss=0 v arch fw cal tp dm
  vb=$(find_vicom_bin)
  if [ -z "$vb" ]; then
    say FAIL "No ViCom bin folder (ViComLoaderManager.dll) under $TOOLS. Apps that use ViCom need C:\\RuS\\ViCom_<version>\\bin."
  else
    vroot=$(dirname "$vb")
    say OK "ViCom folder: $vroot"
    v=$(pe_ver "$vb/ViComLoaderManager.dll"); arch=$(pe_arch "$vb/ViComLoaderManager.dll")
    say INFO "ViCom version (folder) $(basename "$vroot") | ViComLoaderManager.dll $v $arch"
    # required files, ViCom manual tables 4-1 (common), WCDMA, GSM; 'e' variants are the TSME ones
    for f in ViComLoaderManager.dll ViComResourceManager.dll TsmeWorker.dll TsmeAdmin.dll TsmeTools.dll \
             TsmeParameters.dll TsmeResultProcessor.dll ServiceExtension_TSME.dll log4cxx.dll RSToolbox.dll \
             RuSProcessPhysicalLayer.exe \
             ViComGSM.dll ViComGSMe.dll GS3Worker.dll GsmDemodulator.dll \
             ViComWCDMA.dll ViComWCDMAe.dll UmtsDemodulator.dll; do
      if [ -z "$(find "$vb" -maxdepth 1 -iname "$f" -print -quit)" ]; then say FAIL "   missing in bin: $f"; miss=$((miss + 1)); fi
    done
    [ "$miss" -eq 0 ] && say OK "all common + GSM + WCDMA ViCom files present"
    if [ -n "$(find "$vb" -maxdepth 1 -type d -iname PhylisKernelRouting -print -quit)" ]; then say OK "PhylisKernelRouting folder present"
    else say FAIL "PhylisKernelRouting folder missing next to the DLLs (the Phylis kernel needs it)"; fi
    fw=$(find "$vb" -maxdepth 1 -iname 'tsme*.bin' -printf '%f ' 2>/dev/null)
    say INFO "firmware images shipped with this ViCom: ${fw:-none} (the app uploads/boots the one it needs)"
    cal=$(find "$vb" -maxdepth 1 -iname 'TSME6_ID_*.cal' -printf '%f ' 2>/dev/null)
    say INFO "calibration files: ${cal:-none yet (downloaded on first connect)}"
    if [ -w "$vb" ]; then say OK "bin folder writable (needed for the .cal download and LogFiles)"
    else say FAIL "bin folder NOT writable by $(id -un): chown -R $(id -un) \"$vb\""; fi
    find "$vb" -maxdepth 1 -iname 'SampleForViCom*.exe' -printf '%f\n' | sort | while IFS= read -r f; do say INFO "   sample: $f"; done
    for f in inc src doc tools; do [ -d "$vroot/$f" ] && say INFO "   $f/ present"; done
  fi

  tp=$(find_file 'TsmePing.exe'); dm=$(find_file '*Device*Manager*.exe')
  [ -n "$tp" ] && say OK "TsmePing.exe: ${tp#"$TOOLS"/} $(pe_ver "$tp")" || say WARN "TsmePing.exe not found (part of TSME Tools)"
  [ -n "$dm" ] && say OK "Device Manager: ${dm#"$TOOLS"/} $(pe_ver "$dm")" || say INFO "Device Manager exe not under TSME_TOOLS_DIR"

  # VC++ runtimes: ViCom needs VS2008 SP1 and VS2013 (x86)
  local sysd="$WINEPREFIX/drive_c/windows/system32"
  grep -q '^#arch=win64' "$WINEPREFIX/system.reg" 2>/dev/null && sysd="$WINEPREFIX/drive_c/windows/syswow64"
  for f in msvcr120.dll msvcp120.dll; do
    if [ ! -f "$sysd/$f" ]; then say FAIL "$f missing: winetricks -q vcrun2013"
    elif head -c 1024 "$sysd/$f" | grep -qaE 'Wine (builtin|placeholder) DLL'; then say WARN "$f is Wine's built-in: winetricks -q vcrun2013 (or the vcredist_x86 2013 from ViCom tools/)"
    else say OK "$f native ($(pe_ver "$sysd/$f"))"; fi
  done
  if find "$WINEPREFIX/drive_c/windows/winsxs" -maxdepth 1 -iname '*vc90.crt*' 2>/dev/null | grep -q .; then say OK "VC++ 2008 runtime (vc90 CRT) in winsxs"
  else say FAIL "VC++ 2008 SP1 runtime missing: winetricks -q vcrun2008"; fi

  if grep -qi '"VICOM_HOME"' "$WINEPREFIX/system.reg" "$WINEPREFIX/user.reg" 2>/dev/null; then
    say OK "VICOM_HOME set in the Wine registry: $(grep -hi '"VICOM_HOME"' "$WINEPREFIX/system.reg" "$WINEPREFIX/user.reg" | head -n1)"
  else
    say WARN "VICOM_HOME not set in Wine (the ViCom installer sets it). Run setup-RS-ViCom-<ver>.exe inside Wine, or set it: wine reg add 'HKCU\\Environment' /v VICOM_HOME /d 'C:\\RuS\\ViCom_<ver>'"
  fi

  # API names for a custom client (names only)
  find "$TOOLS" -type f -iname 'ViCom*Interface*.h' -printf '%f\n' 2>/dev/null | sort > "$OUT/sdk_headers.txt"
  for f in ViComGSMInterfaceData.h ViComWcdmaInterfaceData.h ViComBasicInterface.h ViComLoader.h; do
    local h; h=$(find_file "$f")
    [ -n "$h" ] || continue
    grep -oE '(struct|class|enum)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*|^[[:space:]]+[A-Za-z_][A-Za-z0-9_:<>*]*[[:space:]]+[*&]?[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?;' "$h" \
      | sed -E 's/^[[:space:]]+//' > "$OUT/sdk_names_${f%.h}.txt"
  done
  say INFO "API name lists: $(find "$OUT" -maxdepth 1 -name 'sdk_names_*' -printf '%f ')"
}

# ---------------------------------------------------------------- tsmeping
step_tsmeping() {
  local tp dir
  tp=$(find_file 'TsmePing.exe')
  [ -n "$tp" ] || { say FAIL "TsmePing.exe not found under TSME_TOOLS_DIR (install R&S TSME Tools)"; return 1; }
  dir="$OUT/tsmeping_$(date +%H%M%S)"; mkdir -p "$dir"
  say INFO "running TsmePing.exe $TSME_IP (60 s max)"
  ( cd "$(dirname "$tp")" && WINEDEBUG=err+all,fixme+all exec timeout -k 5 60 "$WINE" "$tp" "$TSME_IP" ) >"$dir/stdout.log" 2>"$dir/trace.log"
  tr -d '\r' < "$dir/stdout.log" | tail -n 20 | while IFS= read -r l; do say INFO "   $l"; done
  [ -s "$dir/stdout.log" ] || say WARN "TsmePing printed nothing (it may be a GUI tool: check its window)"
  grep -hE 'fixme:(iphlpapi|winsock|ws2_32)' "$dir/trace.log" | sed -E 's/^[0-9a-f]+://' | sort | uniq -c | sort -rn | head -n 5 \
    | while IFS= read -r l; do say WARN "   Wine network stub: $l"; done
}

# ---------------------------------------------------------------- scan
watch_physical_layer() {  # $1 = flag file; runs in background
  while :; do
    pgrep -f 'RuSProcessPhysicalLayer' >/dev/null 2>&1 && echo yes > "$1"
    sleep 3
  done
}

run_scan() {  # $1 label  $2 exe  $3 args  $4 result regex
  local label=$1 exe=$2 args=$3 rx=$4 dir tp="" wp mode secs vb log before=0 rc n from big cal_before cal_after
  if [ -z "$exe" ] || [ ! -f "$exe" ]; then say FAIL "$label: exe not found (set ${label}_EXE)"; return 1; fi
  case $(basename "$exe") in *_cmd*|*_CMD*) mode=console ;; SampleForViCom*) mode=gui ;; *) mode=${SCAN_MODE:-console} ;; esac
  if [ "$mode" = gui ]; then secs=${SCAN_SECS:-600}; else secs=${SCAN_SECS:-120}; fi
  dir="$OUT/scan_${label}_$(date +%H%M%S)"; mkdir -p "$dir"
  vb=$(dirname "$exe")
  log=$(find "$vb" -maxdepth 2 -ipath '*logfiles/vicommeasurements.txt' 2>/dev/null | head -n1)
  [ -n "$log" ] && before=$(stat -c %s "$log")
  cal_before=$(find "$vb" -maxdepth 1 -iname 'TSME6_ID_*.cal' | wc -l)
  if have tcpdump && root; then
    tcpdump -i "${IFACE:-any}" -nn -s 128 -w "$dir/scan.pcap" "host $TSME_IP or net 224.0.0.0/4" >/dev/null 2>&1 &
    tp=$!; sleep 1
  fi
  : > "$dir/physical_layer_seen"
  watch_physical_layer "$dir/physical_layer_seen" & wp=$!

  say INFO "$label: $(basename "$exe") (${mode}, arch $(pe_arch "$exe"), up to ${secs}s)"
  if [ "$mode" = gui ]; then
    say INFO "   in the sample window: Type=TSME -> Load (first time: 1-3 min, downloads calibration)"
    say INFO "   -> SCREENSHOT the 'Firmware Version' and 'Option Mask' it shows (this is the options read)"
    if [ "$label" = GSM ]; then
      say INFO "   -> frequencies in Hz, one per line, e.g. GSM900 935200000..959800000 (ARFCN n: 935.0+0.2n MHz), GSM1800 1805200000.."
    else
      say INFO "   -> frequencies in Hz, one per line, e.g. WCDMA band I 2112800000 (UARFCN/5 MHz, 10562..10838)"
    fi
    say INFO "   -> Store Results -> Start Measurement -> Get Result Counters -> Get 100 Results -> Stop -> close the window"
  fi
  ( cd "$vb" && WINEDEBUG=err+all,fixme+all,+loaddll exec timeout -k 10 "$secs" "$WINE" "$exe" $args ) \
    >"$dir/stdout.log" 2>"$dir/trace.log"
  rc=$?
  kill "$wp" 2>/dev/null; wait "$wp" 2>/dev/null
  [ -n "$tp" ] && { kill -INT "$tp" 2>/dev/null; wait "$tp" 2>/dev/null; }
  case $rc in 124) say INFO "$label: stopped after ${secs}s" ;; 0) say OK "$label: exited 0" ;; *) say WARN "$label: exit code $rc" ;; esac

  # results: console output, plus new lines in LogFiles\ViComMeasurements.txt
  tr -d '\r' < "$dir/stdout.log" > "$dir/output.txt"
  [ -z "$log" ] && log=$(find "$vb" -maxdepth 2 -ipath '*logfiles/vicommeasurements.txt' 2>/dev/null | head -n1)
  if [ -n "$log" ] && [ "$(stat -c %s "$log")" -gt "$before" ]; then
    tail -c +"$((before + 1))" "$log" | tr -d '\r' >> "$dir/output.txt"
    say OK "$label: new data in $(basename "$log")"
  fi
  n=$(grep -ciE "$rx" "$dir/output.txt")
  grep -iE "$rx" "$dir/output.txt" | head -n 500 > "$dir/results.txt"
  if [ "$n" -gt 0 ]; then say OK "$label: $n result lines (results.txt)"; else say FAIL "$label: no results"; fi
  tail -n 12 "$dir/output.txt" | cut -c1-160 | while IFS= read -r l; do say INFO "   $l"; done

  if [ -s "$dir/physical_layer_seen" ]; then say OK "$label: RuSProcessPhysicalLayer.exe started (ViCom's network process)"
  else say FAIL "$label: RuSProcessPhysicalLayer.exe never ran: ViCom could not start its network process (missing files / VICOM_HOME / Wine process start)"; fi
  cal_after=$(find "$vb" -maxdepth 1 -iname 'TSME6_ID_*.cal' | wc -l)
  [ "$cal_after" -gt "$cal_before" ] && say OK "$label: calibration file downloaded from the scanner"
  grep -E 'err:module:.*not found' "$dir/trace.log" | sed -E 's/^[0-9a-f]+://' | sort -u | head -n 5 | while IFS= read -r l; do say FAIL "   $l"; done
  grep -qE 'Unhandled exception|page fault' "$dir/trace.log" && say FAIL "$label: crashed (trace.log)"
  grep -hE 'fixme:(iphlpapi|winsock|ws2_32|ntdll:NtQuerySystemInformation)' "$dir/trace.log" | sed -E 's/^[0-9a-f]+://' \
    | sort | uniq -c | sort -rn | head -n 6 | while IFS= read -r l; do say WARN "   Wine stub used: $l"; done
  if grep -qE 'fixme:iphlpapi:(CreateIpNetEntry|SetIpNetEntry)' "$dir/trace.log"; then
    say WARN "$label: ViCom tried to write a static ARP entry and Wine does not implement it -> on the host: ip neigh replace $TSME_IP lladdr <scanner mac from discover> dev ${IFACE:-<nic>} nud permanent"
  fi
  if [ -f "$dir/scan.pcap" ]; then
    from=$(tcpdump -nn -r "$dir/scan.pcap" "src host $TSME_IP" 2>/dev/null | wc -l)
    big=$(tcpdump -nn -r "$dir/scan.pcap" "src host $TSME_IP and greater 1514" 2>/dev/null | wc -l)
    say INFO "$label: packets from scanner $from (jumbo >1514: $big), to scanner $(tcpdump -nn -r "$dir/scan.pcap" "dst host $TSME_IP" 2>/dev/null | wc -l)"
    [ "$from" -eq 0 ] && say FAIL "$label: scanner sent nothing during the run"
  fi
}

step_scan() {
  [ -n "$TOOLS" ] && [ -d "$TOOLS" ] || { say FAIL "set TSME_TOOLS_DIR"; return 1; }
  pick_iface
  local vb g w apps
  apps=$(other_tsme_apps)
  if [ -n "$apps" ]; then say FAIL "close other TSME programs first (Device Manager etc.): only one app may use the scanner"; printf '%s\n' "$apps" | cut -c1-150; return 1; fi
  vb=$(find_vicom_bin)
  if [ -n "$GSM_EXE" ]; then g=$(to_unix "$GSM_EXE"); elif [ -n "$vb" ]; then g=$(find "$vb" -maxdepth 1 -iname 'SampleForViComGSM.exe' | head -n1); fi
  if [ -n "$WCDMA_EXE" ]; then w=$(to_unix "$WCDMA_EXE"); elif [ -n "$vb" ]; then w=$(find "$vb" -maxdepth 1 -iname 'SampleForViComWCDMA.exe' | head -n1); fi
  # 2G: power/BSIC/cell ids; 3G: Ec/Io, RSCP, scrambling code, cell ids
  run_scan GSM   "${g:-}" "$GSM_ARGS"   'arfcn|bsic|rssi|power|sch|bcch|mcc|lac|cell'
  run_scan WCDMA "${w:-}" "$WCDMA_ARGS" 'uarfcn|psc|scrambl|rscp|ec/?io|cpich|cir|mcc|cell'
}

case $STEP in
  --status) step_status ;;
  net)      step_net ;;
  discover) step_discover ;;
  probe)    step_probe ;;
  sdk)      step_sdk ;;
  tsmeping) step_tsmeping ;;
  scan)     step_scan ;;
  all)      step_net; step_discover && step_probe; step_sdk; step_tsmeping; step_scan ;;
  *)        usage; exit 1 ;;
esac
echo
echo "===== SUMMARY (screenshot this) ====="
cat "$SUMMARY"
echo "Output: $OUT"
