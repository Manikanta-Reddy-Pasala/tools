# How to test the TSME6 under Wine: step by step

Follow these steps in order on the Linux machine that runs the Wine container,
with the TSME6 powered on and wired to it. Each step ends with a `SUMMARY`
block. Screenshot it, then go to the next step.

- **Time:** about 30 minutes. The first scanner connect can take 1–3 minutes
  while it downloads calibration data.
- **Changes:** the scripts only read and capture. Anything that changes the
  system is printed as a command for you to run yourself.

Background (ports, versions, why each check exists) is in [README.md](README.md).

---

## 0. One-time setup

### On the host (outside the container)

```bash
# NIC wired to the TSME6 (example: enp3s0)
sudo ip addr add 192.168.0.1/24 dev enp3s0       # scanner factory IP is 192.168.0.2
sudo ip link set enp3s0 mtu 9000 up              # 9k jumbo frames are mandatory
sudo sysctl -w net.core.rmem_max=67108864 net.core.rmem_default=67108864
```

Disconnect any VPN. The manual says the TSME6 does not work over VPN.

### Start the container on the host network

Use your own image name. The important flag is `--network host`.

```bash
docker run -it --rm --network host --cap-add NET_ADMIN --cap-add NET_RAW \
  -e DISPLAY=$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v /opt/tsme:/opt/tsme  <your-wine-image> bash
```

### Inside the container

```bash
apt-get update && apt-get install -y git iproute2 tcpdump python3 ethtool winetricks
git clone https://github.com/Manikanta-Reddy-Pasala/tools.git
cd tools/tsme6

export WINEPREFIX=/opt/tsme                      # your Wine prefix
export TSME_TOOLS_DIR='C:\RuS'                   # folder holding ViCom_<version>
export TSME_IP=192.168.0.2
export DM_EXE='C:\Program Files\Rohde-Schwarz\TSME Tools\<Device Manager exe>'   # optional
```

If ViCom was copied rather than installed into the prefix, install it now:

```bash
wine 'C:\path\setup-RS-ViCom-<version>.exe'      # same version as the working Windows PC
wine 'C:\path\setup-RS-TsmeTools-<version>.exe'
winetricks -q vcrun2008 vcrun2013
```

### Self-test the kit (optional)

No scanner is needed for this:

```bash
bash t/test_tsme_net.sh                          # expect: tsme6 tests: PASS
```

---

## 1. Settings

```bash
./verify.sh --status
```

**Pass:** `ip`, `tcpdump` and `python3` are installed, and the line
`running as root` appears.

---

## 2. Network

```bash
./verify.sh net
```

**Pass:** every line is `[OK]` or `[INFO]`, in particular:
- `PC in 192.168.0.0/24`
- `MTU 9000`
- `multicast 239.192.1.7 leaves via <your NIC>`
- `no other TSME program running`

**If it fails:** fix each `[FAIL]` with the command printed next to it, then
run this step again. Nothing later works until this step passes.

---

## 3. Discovery (Device Manager)

```bash
./verify.sh discover
```

While the 60 s capture runs, press **Search/Refresh** in the TSME Device Manager
and open the **Options** tab. Then **close the Device Manager**: only one
program may use the scanner at a time.

**Pass:**
- `scanner seen: 192.168.0.2`
- the scanner's MAC address
- traffic on ports 5140, 16962 or 17476, or multicast 239.192.1.7

Also screenshot the Device Manager's **Device Info** tab (firmware version)
and **Options** tab.

---

## 4. Network without Wine

```bash
./verify.sh probe
```

**Pass:** `RESULT: PASS - scanner answers multicast discovery from this host`.

**If it fails:** the network is the problem, not Wine. Go back to step 2.

---

## 5. ViCom install

```bash
./verify.sh sdk
```

**Pass:**
- `ViCom folder: ...` and a `ViComLoaderManager.dll <version> x86` line
- `all common + GSM + WCDMA ViCom files present`
- `PhylisKernelRouting folder present`
- `bin folder writable`
- `msvcr120.dll native`
- `VC++ 2008 runtime`
- `VICOM_HOME set`

**Version rule:** if the firmware from step 3 is **05.08.10.00 or newer**, ViCom
must be **21.0 or newer**.

---

## 6. Vendor connection test

```bash
./verify.sh tsmeping
```

**Pass:** TsmePing reports the scanner. If it opens a window, screenshot the
window too.

---

## 7. 2G and 3G scan with the vendor sample apps

```bash
./verify.sh scan
```

The GSM sample opens first, then the WCDMA sample. In each window:

1. Set **Type = TSME**, then press **Load**. Wait; the first time takes 1–3 min.
2. **Screenshot the "Firmware Version" and "Option Mask" values.** This is the
   options read.
3. Enter the frequencies in Hz, one per line:
   - **GSM:** e.g. `935200000` (GSM 900) or `1805200000` (GSM 1800)
   - **WCDMA:** e.g. `2112800000` (band I)
4. Select **Store Results**, then **Start Measurement**, then
   **Get Result Counters**, then **Get 100 Results**, then **Stop Measurement**.
5. Close the window. The script moves on.

**Pass, for each of GSM and WCDMA:**
- `RuSProcessPhysicalLayer.exe started`
- `new data in ViComMeasurements.txt`
- `N result lines`
- `packets from scanner` greater than 0

### Then your own app

```bash
GSM_EXE='C:\RuS\ViCom_<version>\bin\scanner_main.exe' GSM_ARGS='<its args>' \
SCAN_MODE=console ./verify.sh scan
```

Copy `scanner_main.exe` into the ViCom `bin` folder first. The manual says the
exe must sit next to the ViCom DLLs.

---

## 8. Compare with the working Windows PC (optional but useful)

On the Windows PC, run the same `SampleForViComGSM.exe`, press Load, and
screenshot the Firmware Version and Option Mask. If the Option Mask matches
step 7, the options are read correctly under Wine.

---

## What to send back

| # | Screenshot |
|---|---|
| 1 | `--status` SUMMARY |
| 2 | `net` SUMMARY |
| 3 | `discover` SUMMARY + Device Manager Device Info and Options tabs |
| 4 | `probe` SUMMARY |
| 5 | `sdk` SUMMARY |
| 6 | `tsmeping` SUMMARY (and its window, if any) |
| 7 | `scan` SUMMARY + sample-app window after Load (GSM and WCDMA) |
| 8 | Windows sample-app window after Load (optional) |

Everything is also saved in `./tsme6_verify_out/`. It contains captures and
device data, so keep it local and never commit it.
