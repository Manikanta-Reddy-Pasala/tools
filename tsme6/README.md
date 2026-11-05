# tsme6: check an R&S TSME6 scanner from a Wine/Docker box

Step-by-step check that the box can find the scanner over multicast, reach it,
and run 2G (GSM) and 3G (WCDMA) scans with the vendor's own TSME tools under
Wine.

Nothing from R&S is stored here. You point the scripts at your TSME tools
folder. `.gitignore` blocks DLLs, exes, headers and captures. This repo is
public.

| File | What |
|---|---|
| `verify.sh` | Runs the steps below and prints a `SUMMARY` block for a screenshot |
| `tsme_net.py` | Reads captures and replays the discovery request (standard-library Python 3) |
| `t/test_tsme_net.sh` | Tests; run on a Linux box |

## Before you start

- Container started with `--network host`. Multicast does not cross the
  Docker bridge.
- Run as root, with `iproute2 tcpdump python3 iputils-ping wine` installed.
- On the host: NIC wired to the scanner set to MTU 9000. The TSME6 needs 9k
  jumbo frames.

```bash
export TSME_TOOLS_DIR='/opt/tsme/drive_c/Program Files/<vendor>/TSME Tools'   # or a C:\ path
export WINEPREFIX=/opt/tsme
export DM_EXE='C:\...\TSME Device Manager.exe'
export TSME_IP=<scanner ip>        # leave unset at first; discover finds it
```

## Steps

| # | Command | What it proves |
|---|---|---|
| 0 | `./verify.sh --status` | Tools installed, what is set. Read-only |
| 1 | `./verify.sh net` | Interface up, MULTICAST flag, multicast route, MTU, rp_filter, not a Docker bridge, ping 8972 |
| 2 | `./verify.sh discover` | Captures 60 s while you press **Search** and open **Options** in the Device Manager. Shows the multicast group/port and which IP answers |
| 3 | `./verify.sh probe` | Re-sends that exact discovery packet **without Wine** and waits for the scanner. PASS means multicast works from this box |
| 4 | `./verify.sh sdk` | Lists DLL/exe (with 32/64-bit), headers, sample projects, manuals and config files in the tools folder, plus the API names from the headers |
| 5 | `./verify.sh scan` | Runs a GSM exe, then a WCDMA exe, under Wine. Collects ARFCN/BSIC/RSSI (2G) and UARFCN/PSC/RSCP/Ec/Io (3G) lines and counts packets from the scanner |

Step 5 picks the first `*gsm*` and `*wcdma*`/`*umts*` exe it finds. To choose:

```bash
GSM_EXE='C:\...\<gsm sample>.exe'     GSM_ARGS='<scanner ip>' \
WCDMA_EXE='C:\...\<wcdma sample>.exe' WCDMA_ARGS='<scanner ip>' \
SCAN_SECS=120 ./verify.sh scan
```

Your own `scanner_main` works too: set it as `GSM_EXE` with its arguments.

Output goes to `./tsme6_verify_out/`. Do not commit it.

## Reading the results

| Result | Meaning |
|---|---|
| discover sees no request | Capture started too late, or the Device Manager uses another NIC |
| request seen, no reply | Network: bridge, wrong NIC, firewall, not the same subnet |
| probe PASS, scan has no packets from the scanner | Network is fine; the problem is in Wine or the DLLs |
| scan shows `err:module ... not found` | A DLL is missing from the prefix |
| scan output shows no results but the scanner sends data | Options/licence for that technology missing on the scanner, or a jumbo/MTU problem |

## Tests

```bash
bash tsme6/t/test_tsme_net.sh      # on a Linux box
```
