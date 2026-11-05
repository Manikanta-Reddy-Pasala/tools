#!/usr/bin/env bash
# TSME6 verification in the Wine/Docker box: network -> multicast discovery ->
# ViCom SDK contents -> 2G (GSM) and 3G (WCDMA) scans with the vendor's own exes.
#
# Read-only except: packet captures, UDP probes to the scanner, and starting
# the exes you name. Nothing is installed or changed on the system.
# Output: $OUT (default ./tsme6_verify_out). Never commit that folder.
set -u

usage() {
  cat <<'EOF'
usage: ./verify.sh <step>

  --status    read-only: what is set, what is installed, what the last run found
  net         interface, MTU, multicast route, rp_filter, Docker bridge, ping
  discover    capture while you press Search/Refresh in the TSME Device Manager
  probe       re-send that discovery from this box and wait for the scanner (no Wine)
  sdk         list the ViCom SDK in TSME_TOOLS_DIR: DLLs, headers, samples, manuals
  scan        run the GSM (2G) and WCDMA (3G) scan exes under Wine, collect results
  all         net + discover + probe + sdk + scan

environment:
  TSME_TOOLS_DIR   folder with the TSME tools / ViCom files (unix or C:\ path)  [required for sdk/scan]
  TSME_IP          scanner IP if known (discover finds it otherwise)
  IFACE            NIC wired to the scanner (default: route to TSME_IP, else default route)
  DM_EXE           TSME Device Manager exe; discover starts it if set
  GSM_EXE          exe that runs a 2G scan   (default: first *gsm* exe found by sdk)
  WCDMA_EXE        exe that runs a 3G scan   (default: first *wcdma*/*umts* exe found)
  GSM_ARGS / WCDMA_ARGS   arguments for those exes (e.g. the scanner IP)
  SCAN_SECS        seconds per scan (default 120)
  DISCOVER_SECS    capture length (default 60)
  WINEPREFIX, WINE, OUT
EOF
}

STEP=${1:-}
case $STEP in ''|-h|--help|help) usage; exit 0 ;; esac

HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$PWD/tsme6_verify_out}
WINE=${WINE:-wine}
export WINEPREFIX=${WINEPREFIX:-$HOME/.wine}
TSME_IP=${TSME_IP:-}
IFACE=${IFACE:-}
DM_EXE=${DM_EXE:-}
GSM_EXE=${GSM_EXE:-}; WCDMA_EXE=${WCDMA_EXE:-}
GSM_ARGS=${GSM_ARGS:-}; WCDMA_ARGS=${WCDMA_ARGS:-}
SCAN_SECS=${SCAN_SECS:-120}
DISCOVER_SECS=${DISCOVER_SECS:-60}
mkdir -p "$OUT"
SUMMARY="$OUT/summary_${STEP#--}_$(date +%H%M%S).txt"

say()  { printf '[%s] %s\n' "$1" "$2" | tee -a "$SUMMARY"; }
have() { command -v "$1" >/dev/null 2>&1; }
root() { [ "$(id -u)" -eq 0 ]; }

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

pick_iface() {
  [ -n "$IFACE" ] && return
  if [ -n "$TSME_IP" ] && have ip; then
    IFACE=$(ip route get "$TSME_IP" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1)
  fi
  [ -z "$IFACE" ] && have ip && IFACE=$(ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1)
}
iface_ip() { have ip && ip -o -4 addr show dev "$1" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1; }

# ---------------------------------------------------------------- status
step_status() {
  say INFO "OUT=$OUT  WINEPREFIX=$WINEPREFIX  wine=$("$WINE" --version 2>/dev/null || echo missing)"
  say INFO "TSME_TOOLS_DIR=${TSME_TOOLS_DIR:-unset} -> ${TOOLS:-unset}  TSME_IP=${TSME_IP:-unset}  IFACE=${IFACE:-auto}"
  for t in ip tcpdump python3 ping ss timeout; do
    if have "$t"; then say OK "$t installed"; else say WARN "$t missing (apt-get install -y iproute2 tcpdump python3 iputils-ping)"; fi
  done
  root && say OK "running as root (needed for tcpdump)" || say WARN "not root: discover/scan packet capture will be skipped"
  [ -f "$OUT/discovery.json" ] && say INFO "last discovery: $(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print("scanners", d["scanner_candidates"], "requests", len(d["discovery_requests"]))' "$OUT/discovery.json" 2>/dev/null)"
  ls "$OUT"/scan_* >/dev/null 2>&1 && say INFO "scan runs: $(find "$OUT" -maxdepth 1 -name 'scan_*' -printf '%f ')"
  return 0
}

# ---------------------------------------------------------------- net
step_net() {
  pick_iface
  if [ -z "$IFACE" ]; then say FAIL "No interface found. Set IFACE."; return 1; fi
  local flags mtu ip rp mdev
  flags=$(ip -o link show dev "$IFACE" 2>/dev/null)
  mtu=$(cat "/sys/class/net/$IFACE/mtu" 2>/dev/null)
  ip=$(iface_ip "$IFACE")
  say INFO "interface $IFACE ip=$ip mtu=$mtu"
  case $flags in *MULTICAST*) say OK "$IFACE has MULTICAST flag" ;; *) say FAIL "$IFACE has no MULTICAST flag: sudo ip link set $IFACE multicast on" ;; esac
  case $flags in *LOWER_UP*) say OK "$IFACE link up" ;; *) say FAIL "$IFACE link down (cable/scanner power?)" ;; esac
  [ "${mtu:-0}" -ge 9000 ] && say OK "MTU $mtu (jumbo)" || say WARN "MTU $mtu: TSME6 needs 9k jumbo frames -> on host: sudo ip link set $IFACE mtu 9000"
  mdev=$(ip route get 239.255.255.250 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1)
  if [ "$mdev" = "$IFACE" ]; then say OK "multicast goes out $IFACE"
  else say WARN "multicast goes out '${mdev:-none}', not $IFACE -> sudo ip route add 224.0.0.0/4 dev $IFACE"; fi
  rp=$(cat "/proc/sys/net/ipv4/conf/$IFACE/rp_filter" 2>/dev/null)
  [ "${rp:-0}" = 1 ] && say WARN "rp_filter=1 (strict) on $IFACE: replies from another subnet get dropped -> sysctl -w net.ipv4.conf.$IFACE.rp_filter=2"
  case $ip in 172.1[6-9].*|172.2[0-9].*|172.3[01].*) say FAIL "IP $ip looks like Docker bridge: multicast does not cross it. Use docker run --network host" ;; esac
  say INFO "multicast groups joined on $IFACE: $(awk -v i="$IFACE" '$2==i{f=1;next} /^[0-9]/{f=0} f{print $1}' /proc/net/igmp 2>/dev/null | tr '\n' ' ')"
  if have iptables && root; then
    iptables -S INPUT 2>/dev/null | head -n 1 | grep -q DROP && say WARN "iptables INPUT policy DROP: allow UDP from the scanner"
  fi
  if [ -n "$TSME_IP" ] && have ping; then
    for s in 56 1472 8972; do
      if ping -c 2 -W 1 -M "do" -s "$s" "$TSME_IP" >/dev/null 2>&1; then say OK "ping $TSME_IP $s bytes no-fragment"
      else say WARN "ping $TSME_IP $s bytes no-fragment FAILED"; fi
    done
  fi
}

# ---------------------------------------------------------------- discover
step_discover() {
  pick_iface
  if ! have tcpdump || ! root; then say FAIL "discover needs tcpdump and root"; return 1; fi
  if ! have python3; then say FAIL "discover needs python3"; return 1; fi
  local pcap="$OUT/discover.pcap" tp dmp=""
  tcpdump -i "$IFACE" -nn -s 0 -w "$pcap" 'udp or igmp' >/dev/null 2>"$OUT/tcpdump_discover.err" &
  tp=$!
  sleep 1
  if [ -n "$DM_EXE" ]; then
    local dm; dm=$(to_unix "$DM_EXE")
    ( cd "$(dirname "$dm")" && exec "$WINE" "$dm" ) >"$OUT/dm_stdout.log" 2>&1 &
    dmp=$!
    say INFO "started Device Manager"
  fi
  say INFO "capturing ${DISCOVER_SECS}s on $IFACE: press Search / Refresh in the TSME Device Manager NOW, and open the Options tab"
  sleep "$DISCOVER_SECS"
  kill -INT "$tp" 2>/dev/null; wait "$tp" 2>/dev/null
  [ -n "$dmp" ] && kill "$dmp" 2>/dev/null
  python3 "$HERE/tsme_net.py" analyze "$pcap" --out "$OUT/discovery.json" | tee "$OUT/discovery.txt"
  local cand
  cand=$(python3 -c 'import json,sys;print(" ".join(json.load(open(sys.argv[1]))["scanner_candidates"]))' "$OUT/discovery.json" 2>/dev/null)
  if [ -n "$cand" ]; then say OK "scanner answered discovery: $cand"
  else say FAIL "no scanner answer seen (see discovery.txt)"; fi
}

# ---------------------------------------------------------------- probe
step_probe() {
  pick_iface
  [ -f "$OUT/discovery.json" ] || { say FAIL "run 'discover' first"; return 1; }
  local ip; ip=$(iface_ip "$IFACE")
  python3 "$HERE/tsme_net.py" probe "$OUT/discovery.json" --iface-ip "$ip" ${TSME_IP:+--tsme-ip "$TSME_IP"} --timeout 5 | tee "$OUT/probe.txt"
  if grep -q '^RESULT: PASS' "$OUT/probe.txt"; then say OK "multicast discovery works from this box without Wine"
  else
    say WARN "random source port got no answer; retrying from the Device Manager's own source port"
    python3 "$HERE/tsme_net.py" probe "$OUT/discovery.json" --iface-ip "$ip" ${TSME_IP:+--tsme-ip "$TSME_IP"} --timeout 5 --same-port | tee -a "$OUT/probe.txt"
    grep -q '^RESULT: PASS' "$OUT/probe.txt" && say OK "works only from the original source port (scanner replies to a fixed port)" \
      || say FAIL "scanner does not answer from this box: network problem, not Wine"
  fi
}

# ---------------------------------------------------------------- sdk
step_sdk() {
  [ -n "$TOOLS" ] && [ -d "$TOOLS" ] || { say FAIL "set TSME_TOOLS_DIR to the TSME tools folder"; return 1; }
  local f="$OUT/sdk_inventory.txt" n
  {
    echo "## DLL / EXE (arch, size, name)"
    find "$TOOLS" -type f \( -iname '*.dll' -o -iname '*.exe' \) | sort | while IFS= read -r x; do
      printf '%s\t%s\t%s\n' "$(pe_arch "$x")" "$(stat -c %s "$x")" "${x#"$TOOLS"/}"
    done
    echo "## headers";        find "$TOOLS" -type f \( -iname '*.h' -o -iname '*.hpp' \) | sed "s|^$TOOLS/||" | sort
    echo "## import libs";    find "$TOOLS" -type f -iname '*.lib' | sed "s|^$TOOLS/||" | sort
    echo "## sample projects"; find "$TOOLS" -type f \( -iname '*.sln' -o -iname '*.vcxproj' -o -iname '*.vcproj' -o -iname '*.cpp' \) | sed "s|^$TOOLS/||" | sort
    echo "## manuals";        find "$TOOLS" -type f \( -iname '*.pdf' -o -iname '*.chm' -o -iname '*.htm*' \) | sed "s|^$TOOLS/||" | sort
    echo "## config / licence-like files"; find "$TOOLS" -type f \( -iname '*.ini' -o -iname '*.xml' -o -iname '*.cfg' -o -iname '*.lic' -o -iname '*.key' -o -iname '*.json' \) | sed "s|^$TOOLS/||" | sort
  } > "$f"
  for kind in "DLL / EXE" headers "import libs" "sample projects" manuals "config / licence-like files"; do
    n=$(awk -v k="## $kind" '$0==k{f=1;next} /^## /{f=0} f' "$f" | grep -c .)
    say INFO "$kind: $n"
  done
  say INFO "exe candidates for 2G/3G:"
  awk '/^## DLL/{f=1;next} /^## /{f=0} f' "$f" | grep -iE '\.exe$' | grep -iE 'gsm|wcdma|umts|scan|sample|example|demo|vicom' | head -n 20 \
    | while IFS= read -r l; do say INFO "   $l"; done
  awk '/^## DLL/{f=1;next} /^## /{f=0} f' "$f" | cut -f1 | sort | uniq -c | while read -r c a; do say INFO "   arch $a: $c files"; done
  # API surface: class and method NAMES only, from the vendor headers (for writing our own scan client)
  find "$TOOLS" -type f \( -iname '*.h' -o -iname '*.hpp' \) -print0 2>/dev/null \
    | xargs -0 grep -hoE '(class|struct)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' 2>/dev/null | awk '{print $2}' | sort -u > "$OUT/sdk_types.txt"
  find "$TOOLS" -type f \( -iname '*.h' -o -iname '*.hpp' \) -print0 2>/dev/null \
    | xargs -0 grep -hoE '[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(' 2>/dev/null | tr -d ' (' \
    | grep -iE 'gsm|wcdma|umts|lte|scan|connect|option|licen|start|stop|measure|result|device|init|channel|band|freq|config|request|callback' \
    | sort | uniq -c | sort -rn | awk '{print $2}' | head -n 200 > "$OUT/sdk_functions.txt"
  say INFO "API names: $(wc -l < "$OUT/sdk_types.txt") types (sdk_types.txt), $(wc -l < "$OUT/sdk_functions.txt") functions (sdk_functions.txt)"
  say INFO "   screenshot sdk_types.txt + sdk_functions.txt + the 'sample projects' list in sdk_inventory.txt"
}

# ---------------------------------------------------------------- scan
find_exe() {  # $1 = grep pattern
  [ -f "$OUT/sdk_inventory.txt" ] || step_sdk >/dev/null
  awk '/^## DLL/{f=1;next} /^## /{f=0} f' "$OUT/sdk_inventory.txt" | cut -f3 | grep -iE '\.exe$' | grep -iE "$1" | head -n1 \
    | while IFS= read -r r; do printf '%s/%s\n' "$TOOLS" "$r"; done
}

run_scan() {  # $1 label  $2 exe  $3 args  $4 result regex
  local label=$1 exe=$2 args=$3 rx=$4 dir tp="" rc lines from big
  if [ -z "$exe" ] || [ ! -f "$exe" ]; then say FAIL "$label: no exe (set ${label}_EXE)"; return 1; fi
  dir="$OUT/scan_${label}_$(date +%H%M%S)"; mkdir -p "$dir"
  if [ -n "$TSME_IP" ] && have tcpdump && root; then
    tcpdump -i "${IFACE:-any}" -nn -s 128 -w "$dir/scan.pcap" host "$TSME_IP" >/dev/null 2>&1 &
    tp=$!; sleep 1
  fi
  say INFO "$label scan: $(basename "$exe") $args  (${SCAN_SECS}s, arch $(pe_arch "$exe"))"
  ( cd "$(dirname "$exe")" && WINEDEBUG=err+all,+loaddll exec timeout -k 10 "$SCAN_SECS" "$WINE" "$exe" $args ) \
    >"$dir/stdout.log" 2>"$dir/trace.log"
  rc=$?
  [ -n "$tp" ] && { kill -INT "$tp" 2>/dev/null; wait "$tp" 2>/dev/null; }
  case $rc in 124) say INFO "$label: stopped after ${SCAN_SECS}s (normal for a continuous scan)" ;;
              0)   say OK "$label: exe exited 0" ;;
              *)   say WARN "$label: exe exit code $rc" ;; esac
  tr -d '\r' < "$dir/stdout.log" > "$dir/output.txt"
  lines=$(grep -ciE "$rx" "$dir/output.txt")
  grep -iE "$rx" "$dir/output.txt" | head -n 400 > "$dir/results.txt"
  if [ "$lines" -gt 0 ]; then say OK "$label: $lines result lines (results.txt)"
  else say FAIL "$label: no result lines in program output"; fi
  say INFO "$label: last output lines:"
  tail -n 15 "$dir/output.txt" | cut -c1-160 | while IFS= read -r l; do say INFO "   $l"; done
  grep -E 'err:module:.*not found' "$dir/trace.log" | sed -E 's/^[0-9a-f]+://' | sort -u | head -n 5 | while IFS= read -r l; do say FAIL "   $l"; done
  grep -qE 'Unhandled exception|page fault' "$dir/trace.log" && say FAIL "$label: crashed (trace.log)"
  if [ -f "$dir/scan.pcap" ]; then
    from=$(tcpdump -nn -r "$dir/scan.pcap" "src host $TSME_IP" 2>/dev/null | wc -l)
    big=$(tcpdump -nn -r "$dir/scan.pcap" "src host $TSME_IP and greater 1514" 2>/dev/null | wc -l)
    say INFO "$label: packets from scanner $from (jumbo $big)"
    [ "$from" -eq 0 ] && say FAIL "$label: scanner sent nothing during the scan"
  fi
}

step_scan() {
  [ -n "$TOOLS" ] && [ -d "$TOOLS" ] || { say FAIL "set TSME_TOOLS_DIR"; return 1; }
  pick_iface
  local g w
  if [ -n "$GSM_EXE" ]; then g=$(to_unix "$GSM_EXE"); else g=$(find_exe 'gsm'); fi
  if [ -n "$WCDMA_EXE" ]; then w=$(to_unix "$WCDMA_EXE"); else w=$(find_exe 'wcdma|umts'); fi
  # result keywords: 2G = ARFCN/BSIC/RSSI/C/I, 3G = UARFCN/PSC/scrambling/RSCP/Ec/Io
  run_scan GSM   "$g" "$GSM_ARGS"   'arfcn|bsic|rssi|c/i|bcch|mcc|lac|cell'
  run_scan WCDMA "$w" "$WCDMA_ARGS" 'uarfcn|psc|scrambl|rscp|ec/?io|cpich|mcc|cell'
}

case $STEP in
  --status) step_status ;;
  net)      step_net ;;
  discover) step_discover ;;
  probe)    step_probe ;;
  sdk)      step_sdk ;;
  scan)     step_scan ;;
  all)      step_net; step_discover && step_probe; step_sdk; step_scan ;;
  *)        usage; exit 1 ;;
esac
echo
echo "===== SUMMARY (screenshot this) ====="
cat "$SUMMARY"
echo "Output: $OUT"
