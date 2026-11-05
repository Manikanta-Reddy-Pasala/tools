# tsme6: check an R&S TSME6 scanner from a Wine/Docker box

Step-by-step check that a Linux box running the R&S software under Wine can
find the TSME6, read its options, and run 2G (GSM) and 3G (WCDMA) scans.

Everything here is based on two R&S manuals:
- **TSME6 User Manual** 4900.0033.02-08: network, firewall, troubleshooting.
- **ViCom User Manual** 1505.1329.42-26: package layout, loader, sample apps.

Nothing from R&S is stored in this repo. You point the scripts at your
installed R&S software. `.gitignore` blocks DLLs, exes, headers and captures,
because this repo is public.

**To test, follow [TESTING.md](TESTING.md)**: setup, the 8 steps in order, what a pass looks like, what to send back.

| File | What |
|---|---|
| `verify.sh` | The steps below. Each one prints a `SUMMARY` block to screenshot |
| `tsme_net.py` | Capture analysis, discovery replay, PE file version (standard-library Python 3) |
| `TESTING.md` | Step-by-step test guide |
| `t/test_tsme_net.sh` | Tests; run on a Linux box |

## How the PC talks to a TSME6 (from the manuals)

```
your app / sample app
  -> ViCom C++ API: CViComLoader<CViComGSMInterface|CViComWcdmaInterface, ...>
     .Connect() -> GetInterface() -> SetFrequencyTable() -> StartMeasurement()
     -> GetResult() ... -> StopMeasurement() -> Disconnect()
  -> ViCom DLLs in C:\RuS\ViCom_<ver>\bin (loaded at run time, no .lib linking)
  -> RuSProcessPhysicalLayer.exe  ("DLL Loader for PHYLIS Modules", the network process)
  -> Gigabit Ethernet, UDP:
       PC -> TSME6   ports 5140 and 16962
       TSME6 -> PC   port 17476
       multicast     239.192.1.7 (TSME6), 224.17.4.76 (old TSME), test group 239.192.1.5:16962
```

- **Address:** the factory address is **192.168.0.2**. Give the PC 192.168.0.1/24
  with no gateway, or use auto-IP (169.254.x.y). The PC needs its own NIC for
  the scanner.
- **Jumbo frames:** **9k jumbo frames** are required (MTU 9000, "9014 Bytes" in
  Windows).
- **No ping:** the TSME6 **does not answer ping**. The manual's check is
  `TsmePing.exe`, part of TSME Tools.
- **Administrator:** the app must run **as administrator**. Otherwise its
  static ARP entries conflict, and multicast to `239.192.1.5:16962` fails.
- **One app at a time:** only **one application at a time** may use the
  scanner. Close the Device Manager before running your app.
- **Options:** options are licences stored **on the scanner**: K21 = WCDMA,
  K23 = GSM, K29 = LTE, K40 = automatic channel detection. The ViCom sample
  apps show them as **Option Mask** after Load.
- **First connect:** the first connect downloads
  `TSME6_ID_4900.0004K02-<serial>.cal` into the app's `bin` folder, so the
  folder must be writable. If no measurement data comes, delete that file.
- **Firmware:** each app boots the scanner with the firmware its ViCom version
  needs, uploading it if missing (up to 4 are stored). Mixing versions makes the
  scanner reboot or re-flash between apps.

## Which versions to use

1. **Same as the working Windows PC.** Use exactly the same ViCom and TSME Tools
   versions as the PC where scanner_main works:
   - The folder name `C:\RuS\ViCom_<ver>` gives the version.
   - The `sdk` step prints the DLL file versions.
   - The Device Manager's *Device Info* tab shows the scanner firmware.
2. **Firmware 05.08.10.00 or newer needs ViCom 21.0 or newer** (ROMES 21.1).
   Older ViCom with that firmware gives sporadic connect failures.
3. **Install, don't copy.** Run the installers inside the Wine prefix rather
   than copying folders:
   - `setup-RS-ViCom-<ver>.exe`: sets `VICOM_HOME`, creates `bin` / `inc` / `src` / `tools`.
   - `setup-RS-TsmeTools-<ver>.exe`: Device Manager and TsmePing; in `ViCom tools\TSME`.
   - VC++ runtimes **2008 SP1 and 2013, x86**: `winetricks -q vcrun2008 vcrun2013`,
     or the vcredist files in ViCom `tools\`.
4. **Bitness.** Your app must be **32-bit** if the ViCom `bin` is 32-bit. The
   `sdk` step prints the architecture.

## Before you start

- Container started with `--network host`. Multicast does not cross the Docker
  bridge.
- Run as root, with `iproute2 tcpdump python3 ethtool wine` installed.
- On the host: the scanner NIC has MTU 9000 and an address in the scanner's
  subnet.

```bash
export TSME_TOOLS_DIR='C:\RuS'                 # folder holding ViCom_<ver> (and/or TSME Tools)
export WINEPREFIX=/opt/tsme
export TSME_IP=192.168.0.2                     # factory default
export DM_EXE='C:\Program Files\Rohde-Schwarz\TSME Tools\<Device Manager>.exe'   # optional
```

## Steps

| # | Command | What it shows |
|---|---|---|
| 0 | `./verify.sh --status` | Tools installed, settings. Read-only |
| 1 | `./verify.sh net` | Link, subnet, MTU 9000, multicast route to 239.192.1.7, rp_filter, VPN, flow control, ARP, firewall, other TSME apps running |
| 2 | `./verify.sh discover` | 60 s capture while you press **Search** and open **Options** in the Device Manager. Shows the scanner's IP and MAC and the traffic on the known ports/groups |
| 3 | `./verify.sh probe` | Re-sends that discovery packet **without Wine**. PASS means the network path works |
| 4 | `./verify.sh sdk` | ViCom version, required DLLs, `RuSProcessPhysicalLayer.exe`, `PhylisKernelRouting`, shipped firmware, `.cal` files, bin folder writable, VC++ 2008/2013, `VICOM_HOME`, header names |
| 5 | `./verify.sh tsmeping` | R&S `TsmePing.exe` under Wine |
| 6 | `./verify.sh scan` | `SampleForViComGSM.exe`, then `SampleForViComWCDMA.exe` under Wine (follow the printed steps) |

What step 6 checks:
- the **Firmware Version** and **Option Mask** shown after Load (screenshot them)
- whether `RuSProcessPhysicalLayer.exe` started
- whether a `.cal` file was downloaded
- new lines in `bin\LogFiles\ViComMeasurements.txt`
- packets from the scanner
- Wine stubs, for example static ARP

To test your own app instead:
```bash
GSM_EXE='C:\...\scanner_main.exe' GSM_ARGS='...' SCAN_MODE=console ./verify.sh scan
```
Put it in the ViCom `bin` folder. The manual says the exe must sit next to the
Phylis kernel and `PhylisKernelRouting`.

Example frequencies (Hz, one per line in the sample apps):
- **GSM 900:** 935.2–959.8 MHz, ARFCN n = 935.0 + 0.2·n MHz.
- **GSM 1800:** from 1805.2 MHz.
- **WCDMA band I:** UARFCN 10562–10838, f = UARFCN / 5 MHz, e.g. 2112800000.

Output goes to `./tsme6_verify_out/`. Do not commit it.

## Reading the results

| Result | Meaning |
|---|---|
| `net` FAIL on MTU / multicast route / bridge | Fix the host network first; nothing else works without it |
| discover sees no scanner traffic | Wrong NIC, scanner off, or VPN |
| probe PASS, scan gets no packets from the scanner | Network is fine; the problem is in Wine or the ViCom install |
| `RuSProcessPhysicalLayer.exe never ran` | ViCom could not start its network process: missing files, `VICOM_HOME`, VC++ runtimes |
| Wine stub `CreateIpNetEntry` | ViCom's static ARP is not done under Wine; set it on the host (`ip neigh replace ...`, printed by `discover`) |
| Option Mask 0 / missing technologies | Options not read, or not licensed on this scanner (compare with the Windows PC) |
| Load works but no results | Delete `TSME6_ID_*.cal` in bin and retry; check jumbo frames |

## Field run 1 (2026-11-05): discovery works, scan does not

Setup: VM 10.10.120.13, NIC `enp195s0` (MTU 9000), container on the host
network, scanner at 10.10.120.86.

| Step | Result | Meaning |
|---|---|---|
| `net` | OK | NIC up, MTU 9000, multicast leaves via the scanner NIC, ARP reachable |
| `discover` | OK | Scanner beacons on 239.192.1.7:17476 received (also from its fallback 192.168.0.2, same MAC) |
| `probe` | should be `PARTIAL` | No Device Manager search was captured, so only the receive path is proven |
| `sdk` | **broken install** (passed only on the old, naive check) | See below |
| `scan` | FAIL | No sample exe in the container, and the ViCom bin cannot run anyway |

Why nothing that uses ViCom (sample apps or `scanner_main`) can read options
or scan from that container:

- `RuSProcessPhysicalLayer.exe` was a **19-byte stub**. This is ViCom's
  network process, so nothing can reach the scanner.
- `ViComResourceManager.dll` was a **symlink to `ViComLoaderManager.dll`**.
  `ViComGSM.dll` and `ViComWCDMA.dll` were **symlinks to the `...w` variants**,
  which by the manual's naming are most likely the TSMW model.
- **Two ViCom versions were mixed**: ViCom 20.0.0.1359 DLLs plus later ones.
- **Only 18 files**, and no Phylis runtime (`Phylis*.dll`, `ModulePool.dll`,
  `IMD_Base.dll`, `libfftw3*.dll`).

The `sdk` step now FAILs on all of these (kit `2026-11-05.4`).

### Fix, in order

1. **Pick one ViCom version.** It must match the headers `scanner_main` was
   built with; see `C:\RuS\ViCom_<ver>` on the working Windows PC.
   - If the scanner firmware is 05.08.10.00 or newer, use ViCom 21.0 or newer.
   - The host VM has `RS-ViCom-Pro-26.0.0.4428`. Use it only if `scanner_main`
     is (re)built against the 26 headers.
2. **Move the hand-made folder aside and install properly:**
   ```bash
   mv /home/scanner/wine/drive_c/RuS/ViCom_20.0 /home/scanner/wine/drive_c/RuS/ViCom_20.0.fake
   wine 'Z:\path\setup-RS-ViCom-<ver>.exe'      # or copy the WHOLE bin of that one version
   winetricks -q vcrun2008 vcrun2013
   ```
3. **Check the install:** `./verify.sh sdk` must show no `[FAIL]`.
4. **Re-test discovery:** run `./verify.sh discover` while the Device Manager
   presses Search, then `./verify.sh probe`. Expect `PASS`, not `PARTIAL`.
5. **Give the container a screen** for the GUI samples (see TESTING.md step 7):
   `Xvfb :99 ... & x11vnc ... &`, then `export DISPLAY=:99` and open VNC to
   `<vm>:5900`.
6. **Run `./verify.sh scan`.** Load in the sample window, then screenshot
   **Firmware Version** and **Option Mask**. If no GSM/WCDMA sample exists, the
   RF power scan sample runs instead.
7. **Then your own app:**
   ```bash
   GSM_EXE='C:\RuS\ViCom_<ver>\bin\scanner_main.exe' SCAN_MODE=console ./verify.sh scan
   ```

Send the raw output from an unchanged git clone. Each summary must start with
`tsme6 kit 2026-11-05.4 sha e91cbde17a76`.

## Tests

```bash
bash tsme6/t/test_tsme_net.sh      # on a Linux box
```
