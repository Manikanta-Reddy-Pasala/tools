#!/usr/bin/env python3
"""TSME6 network checks that do not need the R&S protocol spec.

  analyze <capture.pcap> [--out discovery.json]
      Read a capture taken while the TSME Device Manager searched for the
      scanner. Find the discovery request (our host -> multicast/broadcast),
      the scanner's replies, multicast streams and IGMP joins.

  probe <discovery.json> [--iface-ip IP] [--tsme-ip IP] [--timeout S] [--same-port]
      Re-send the exact discovery request the Device Manager sent and listen
      for answers. Proves multicast discovery works from this host/container
      without Wine. Also joins any multicast group the scanner streamed to.

  pever <file.dll|exe> ...
      Print the Windows file version of PE files (ViCom version = DLL file version).

  selftest
      Build a synthetic capture and check the parser.

Known values from the R&S TSME6 user manual (4900.0033.02-08, "Firewall configuration"):
  RxPort TSME6->PC 17476/udp, TxPort PC->TSME6 5140 and 16962/udp,
  multicast TSME6 239.192.1.7, TSME 224.17.4.76, connection test 239.192.1.5:16962.
  The TSME6 does not answer ICMP ping.

Standard library only. Python 3.6+.
"""
import argparse
import collections
import ipaddress
import json
import os
import socket
import struct
import subprocess
import sys
import tempfile
import time

KNOWN_GROUPS = {"239.192.1.7": "TSME6 multicast", "224.17.4.76": "TSME multicast",
                "239.192.1.5": "TSME connection-test multicast"}
KNOWN_PORTS = {17476: "RxPort TSME6->PC", 5140: "TxPort PC->TSME6", 16962: "TxPort PC->TSME6"}


def label(ip, port):
    tags = [t for t in (KNOWN_GROUPS.get(ip), KNOWN_PORTS.get(port)) if t]
    return "  [" + ", ".join(tags) + "]" if tags else ""


# ------------------------------------------------------------------ pcap
def read_pcap(path):
    with open(path, "rb") as f:
        data = f.read()
    magics = {
        b"\xd4\xc3\xb2\xa1": ("<", 1e6), b"\xa1\xb2\xc3\xd4": (">", 1e6),
        b"\x4d\x3c\xb2\xa1": ("<", 1e9), b"\xa1\xb2\x3c\x4d": (">", 1e9),
    }
    if data[:4] not in magics:
        sys.exit("%s: not a classic pcap file (capture with: tcpdump -w file.pcap)" % path)
    en, div = magics[data[:4]]
    linktype = struct.unpack(en + "I", data[20:24])[0]
    off = 24
    while off + 16 <= len(data):
        ts, tsf, incl, orig = struct.unpack(en + "IIII", data[off:off + 16])
        off += 16
        yield ts + tsf / div, linktype, data[off:off + incl], orig
        off += incl


def ip_payload(linktype, pkt):
    """Return (IPv4 packet, source MAC or None) inside a link-layer frame, or (None, None)."""
    mac = None
    if linktype == 1:                       # Ethernet
        if len(pkt) < 14:
            return None, None
        mac = ":".join("%02x" % b for b in pkt[6:12])
        et, off = struct.unpack("!H", pkt[12:14])[0], 14
        while et in (0x8100, 0x88A8) and len(pkt) >= off + 4:   # VLAN tags
            et, off = struct.unpack("!H", pkt[off + 2:off + 4])[0], off + 4
    elif linktype == 113:                   # Linux cooked (tcpdump -i any)
        if len(pkt) < 16:
            return None, None
        if struct.unpack("!H", pkt[4:6])[0] == 6:
            mac = ":".join("%02x" % b for b in pkt[6:12])
        et, off = struct.unpack("!H", pkt[14:16])[0], 16
    elif linktype == 276:                   # Linux cooked v2
        if len(pkt) < 20:
            return None, None
        if pkt[11] == 6:
            mac = ":".join("%02x" % b for b in pkt[12:18])
        et, off = struct.unpack("!H", pkt[0:2])[0], 20
    elif linktype in (101, 228):            # raw IPv4
        et, off = 0x0800, 0
    else:
        return None, None
    return (pkt[off:], mac) if et == 0x0800 else (None, None)


def parse_ipv4(ip):
    if len(ip) < 20 or ip[0] >> 4 != 4:
        return None
    ihl = (ip[0] & 0x0F) * 4
    total = struct.unpack("!H", ip[2:4])[0]
    frag = struct.unpack("!H", ip[6:8])[0]
    p = {
        "proto": ip[9],
        "src": socket.inet_ntoa(ip[12:16]),
        "dst": socket.inet_ntoa(ip[16:20]),
        "len": total,
        "fragment": bool(frag & 0x3FFF),
        "first_fragment": (frag & 0x1FFF) == 0,
    }
    body = ip[ihl:]
    if p["proto"] == 17 and p["first_fragment"] and len(body) >= 8:
        p["sport"], p["dport"] = struct.unpack("!HH", body[0:4])
        p["payload"] = body[8:]
    elif p["proto"] == 2 and len(body) >= 8:
        p["igmp_type"] = body[0]
        p["igmp_group"] = socket.inet_ntoa(body[4:8])
    return p


def local_ips():
    ips = set(["127.0.0.1"])
    try:
        out = subprocess.run(["ip", "-o", "-4", "addr"], stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, universal_newlines=True).stdout
        for line in out.splitlines():
            parts = line.split()
            if "inet" in parts:
                ips.add(parts[parts.index("inet") + 1].split("/")[0])
    except OSError:
        pass
    return ips


def is_group(ip):
    a = ipaddress.ip_address(ip)
    return a.is_multicast or ip == "255.255.255.255" or ip.endswith(".255")


# ------------------------------------------------------------------ analyze
def analyze(pcap, out, mine=None):
    mine = mine or local_ips()
    flows = collections.OrderedDict()
    igmp = collections.Counter()
    macs = {}
    frags = 0
    total = 0
    for _, lt, pkt, orig in read_pcap(pcap):
        ip, mac = ip_payload(lt, pkt)
        p = parse_ipv4(ip) if ip else None
        if not p:
            continue
        total += 1
        if mac and p["src"] not in mine:
            macs.setdefault(p["src"], mac)
        frags += p["fragment"]
        if "igmp_group" in p:
            igmp[(p["src"], p["igmp_group"], p["igmp_type"])] += 1
            continue
        if "sport" not in p:
            continue
        k = (p["src"], p["sport"], p["dst"], p["dport"])
        f = flows.setdefault(k, {"count": 0, "max_len": 0, "first_payload": p["payload"]})
        f["count"] += 1
        f["max_len"] = max(f["max_len"], p["len"])

    requests, replies, streams, other = [], [], [], []
    for (s, sp, d, dp), f in flows.items():
        row = {"src": s, "sport": sp, "dst": d, "dport": dp, "count": f["count"], "max_len": f["max_len"]}
        if s in mine and is_group(d):
            row["payload_hex"] = f["first_payload"].hex()
            requests.append(row)
        elif s not in mine and is_group(d):
            streams.append(row)
        elif s not in mine and d in mine:
            replies.append(row)
        else:
            other.append(row)
    req_ports = set(r["sport"] for r in requests) | set(r["dport"] for r in requests)
    for r in replies:
        r["answers_discovery"] = r["dport"] in req_ports or r["sport"] in req_ports
    scanners = set(r["src"] for r in replies if r["answers_discovery"])
    # the manual's fixed ports/groups identify the scanner even without a request
    scanners |= set(r["src"] for r in replies + streams if r["sport"] in KNOWN_PORTS or r["dport"] in KNOWN_PORTS
                    or r["dst"] in KNOWN_GROUPS)
    scanners = sorted(scanners)

    res = {
        "capture": pcap, "ipv4_packets": total, "fragments": frags, "local_ips": sorted(mine),
        "discovery_requests": requests, "replies_to_us": replies, "multicast_streams": streams,
        "igmp": [{"host": h, "group": g, "type": hex(t), "count": c} for (h, g, t), c in igmp.items()],
        "scanner_candidates": scanners,
        "scanner_macs": {ip: macs.get(ip) for ip in scanners},
    }
    if out:
        with open(out, "w") as fh:
            json.dump(res, fh, indent=2)

    print("IPv4 packets %d, IP fragments %d, local IPs %s" % (total, frags, ", ".join(sorted(mine))))
    print("\n-- discovery requests sent by this host (multicast/broadcast):")
    for r in requests:
        print("   %s:%d -> %s:%d  x%d  %d bytes%s" % (r["src"], r["sport"], r["dst"], r["dport"], r["count"], r["max_len"],
                                                 label(r["dst"], r["dport"])))
    if not requests:
        print("   NONE: start the capture BEFORE pressing search/refresh in the Device Manager")
    print("\n-- replies to this host:")
    for r in replies:
        print("   %s:%d -> %s:%d  x%d  max %d bytes %s%s" % (r["src"], r["sport"], r["dst"], r["dport"], r["count"],
                                                           r["max_len"], "<- answers discovery" if r["answers_discovery"] else "",
                                                           label(r["dst"], r["sport"])))
    if not replies:
        print("   NONE")
    print("\n-- multicast/broadcast from other hosts:")
    for r in streams[:15]:
        print("   %s:%d -> %s:%d  x%d  max %d bytes%s" % (r["src"], r["sport"], r["dst"], r["dport"], r["count"], r["max_len"],
                                                     label(r["dst"], r["dport"])))
    if not streams:
        print("   NONE")
    print("\n-- IGMP (multicast group joins):")
    for (h, g, t), c in igmp.items():
        print("   %s joins/reports %s (type %s) x%d%s" % (h, g, hex(t), c, label(g, 0)))
    if not igmp:
        print("   NONE")
    print("\nSCANNER CANDIDATES: %s" % (", ".join("%s (mac %s)" % (ip, macs.get(ip) or "?") for ip in scanners)
                                       or "none found"))
    if frags:
        print("NOTE: IP fragments seen -> MTU on this path is below what the scanner sends (needs 9k jumbo).")
    return res


# ------------------------------------------------------------------ pever
def pe_version(path):
    """FileVersion from VS_FIXEDFILEINFO, e.g. '21.0.0.123', or None."""
    with open(path, "rb") as f:
        data = f.read()
    i = data.find(b"\xbd\x04\xef\xfe")
    if i < 0 or i + 16 > len(data):
        return None
    ms, ls = struct.unpack("<II", data[i + 8:i + 16])
    return "%d.%d.%d.%d" % (ms >> 16, ms & 0xFFFF, ls >> 16, ls & 0xFFFF)


def pever(paths):
    for p in paths:
        try:
            print("%s\t%s" % (pe_version(p) or "-", p))
        except OSError as e:
            print("?\t%s (%s)" % (p, e))
    return 0


# ------------------------------------------------------------------ probe
def probe(disc_path, iface_ip, tsme_ip, timeout, same_port):
    with open(disc_path) as fh:
        disc = json.load(fh)
    reqs = disc.get("discovery_requests", [])
    ok = False
    beacons = [st for st in disc.get("multicast_streams", []) if st["dst"] in KNOWN_GROUPS or st["sport"] in KNOWN_PORTS]
    if not reqs and not beacons:
        print("FAIL: no discovery request and no scanner beacon in %s. Capture again while the Device Manager searches." % disc_path)
        return 1
    if not reqs:
        print("NOTE: no discovery request captured (Device Manager did not search during the capture).")
        print("      Only the RECEIVE path (scanner beacons) can be tested; the SEND path is untested.")
    seen = set()
    for r in reqs:
        key = (r["dst"], r["dport"], r["payload_hex"])
        if key in seen:
            continue
        seen.add(key)
        payload = bytes.fromhex(r["payload_hex"])
        targets = [(r["dst"], r["dport"])]
        if tsme_ip:
            targets.append((tsme_ip, r["dport"]))
        for dst in targets:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 4)
            s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_LOOP, 0)
            if iface_ip:
                s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(iface_ip))
            bind_port = r["sport"] if same_port else 0
            try:
                s.bind((iface_ip or "", bind_port))
            except OSError as e:
                print("   bind %s:%d failed (%s), using a random port" % (iface_ip or "*", bind_port, e))
                s.bind((iface_ip or "", 0))
            s.settimeout(0.3)
            print("\n-> sending captured discovery (%d bytes) from port %d to %s:%d"
                  % (len(payload), s.getsockname()[1], dst[0], dst[1]))
            answers = collections.Counter()
            sample = {}
            t_end = time.time() + timeout
            for _ in range(3):
                try:
                    s.sendto(payload, dst)
                except OSError as e:
                    print("   send failed: %s" % e)
                    break
                time.sleep(0.2)
            while time.time() < t_end:
                try:
                    data, addr = s.recvfrom(65535)
                except socket.timeout:
                    continue
                answers[addr] += 1
                sample.setdefault(addr, (len(data), data[:24].hex()))
            s.close()
            if answers:
                ok = True
                for addr, c in answers.items():
                    print("   ANSWER from %s:%d x%d, %d bytes, starts %s" % (addr[0], addr[1], c, sample[addr][0], sample[addr][1]))
            else:
                print("   no answer within %.0fs" % timeout)

    for st in disc.get("multicast_streams", []):
        if not ipaddress.ip_address(st["dst"]).is_multicast:
            continue
        print("\n-> joining multicast %s:%d (scanner sent to it during capture)" % (st["dst"], st["dport"]))
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            s.bind(("", st["dport"]))
            mreq = socket.inet_aton(st["dst"]) + socket.inet_aton(iface_ip or "0.0.0.0")
            s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
        except OSError as e:
            print("   join failed: %s" % e)
            s.close()
            continue
        s.settimeout(0.5)
        n, t_end = 0, time.time() + timeout
        while time.time() < t_end:
            try:
                s.recvfrom(65535)
                n += 1
            except socket.timeout:
                pass
        s.close()
        print("   received %d packets in %.0fs" % (n, timeout))
        ok = ok or n > 0

    if ok and not reqs:
        print("\nRESULT: PARTIAL - scanner beacons received on this host; send path not tested (rerun discover with the Device Manager searching)")
        return 3
    print("\nRESULT: %s" % ("PASS - scanner answers multicast discovery from this host"
                            if ok else "FAIL - no answer (check --network host, MTU, firewall, rp_filter, same subnet)"))
    return 0 if ok else 2


# ------------------------------------------------------------------ selftest
def _udp_frame(src, dst, sport, dport, payload, dst_mac=b"\x01\x00\x5e\x00\x00\x01"):
    udp = struct.pack("!HHHH", sport, dport, 8 + len(payload), 0) + payload
    ip = struct.pack("!BBHHHBBH4s4s", 0x45, 0, 20 + len(udp), 1, 0, 64, 17, 0,
                     socket.inet_aton(src), socket.inet_aton(dst)) + udp
    return dst_mac + b"\x02\x00\x00\x00\x00\x01" + b"\x08\x00" + ip


def selftest():
    frames = [
        _udp_frame("192.168.0.10", "239.192.1.7", 50000, 16962, b"HELLO"),
        _udp_frame("192.168.0.2", "192.168.0.10", 16962, 50000, b"I-AM-TSME" * 10),
        _udp_frame("192.168.0.2", "239.9.9.9", 5000, 5001, b"x" * 100),
    ]
    fd, path = tempfile.mkstemp(suffix=".pcap")
    with os.fdopen(fd, "wb") as f:
        f.write(struct.pack("<IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))
        for i, fr in enumerate(frames):
            f.write(struct.pack("<IIII", 1700000000 + i, 0, len(fr), len(fr)) + fr)
    try:
        res = analyze(path, None, mine={"192.168.0.10", "127.0.0.1"})
    finally:
        os.unlink(path)
    checks = [
        ("request found", len(res["discovery_requests"]) == 1 and res["discovery_requests"][0]["payload_hex"] == b"HELLO".hex()),
        ("reply found", len(res["replies_to_us"]) == 1 and res["replies_to_us"][0]["answers_discovery"]),
        ("stream found", len(res["multicast_streams"]) == 1),
        ("scanner candidate", res["scanner_candidates"] == ["192.168.0.2"]),
        ("scanner mac", res["scanner_macs"].get("192.168.0.2") == "02:00:00:00:00:01"),
    ]
    fd, pe = tempfile.mkstemp(suffix=".dll")
    with os.fdopen(fd, "wb") as f:
        f.write(b"MZ" + b"\0" * 100 + b"\xbd\x04\xef\xfe" + b"\0\0\1\0" + struct.pack("<II", (21 << 16) | 0, (3 << 16) | 7))
    try:
        checks.append(("pe version", pe_version(pe) == "21.0.3.7"))
    finally:
        os.unlink(pe)
    bad = [n for n, good in checks if not good]
    print("\nSELFTEST:", "PASS" if not bad else "FAIL " + ", ".join(bad))
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd")
    a = sub.add_parser("analyze")
    a.add_argument("pcap")
    a.add_argument("--out", default="discovery.json")
    p = sub.add_parser("probe")
    p.add_argument("discovery")
    p.add_argument("--iface-ip")
    p.add_argument("--tsme-ip")
    p.add_argument("--timeout", type=float, default=5)
    p.add_argument("--same-port", action="store_true")
    v = sub.add_parser("pever")
    v.add_argument("files", nargs="+")
    sub.add_parser("selftest")
    args = ap.parse_args()
    if args.cmd == "analyze":
        analyze(args.pcap, args.out)
        return 0
    if args.cmd == "probe":
        return probe(args.discovery, args.iface_ip, args.tsme_ip, args.timeout, args.same_port)
    if args.cmd == "pever":
        return pever(args.files)
    if args.cmd == "selftest":
        return selftest()
    ap.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
