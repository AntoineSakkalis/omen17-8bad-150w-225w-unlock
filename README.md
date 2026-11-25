# HP OMEN 17 (`8BAD`) — 150W CPU + 225W RTX 4080 Laptop Unlock & Tuning Stack

Complete, reproducible scripts and configs to bypass the OEM Embedded Controller (EC) **130 W CPU clamp** and NVIDIA **175 W GPU TGP ceiling** on the **HP OMEN 17 (`17-ck2xxx`, board `8BAD`, BIOS `F.14`, Core i7-13700HX + RTX 4080 Laptop)**—without HP OMEN Gaming Hub or Intel XTU background bloat.

> Tested hardware: **HP OMEN 17 (`8BAD`, `78.36`, BIOS `F.14`)**, **Core i7-13700HX**, **RTX 4080 Laptop** (`VEN_10DE&DEV_27E0&SUBSYS_8BAD103C`, vBIOS `95.04.3c.00.79`, NVIDIA Driver `616.92`), `2x16 GB DDR5-4800`.

---

## What Problems This Solves

1. **EC / BIOS 130 W (or 100 W concurrent) CPU clamp on HP Omen `8BAD`**
   - OMEN's firmware clamps CPU `PL1` back down unless BIOS thermal `FanMode` is set to **`Performance` (`0x31`)** *and* active `OmenMon` fan programs declare `<FanMode>Performance</FanMode>` instead of `Default`.
   - Enforcing `-Bios FanMode=Performance Cpu:PL1=150 Gpu=Maximum` + `ThrottleStop` (`PL1=150 W`, `PL2=150 W`, `SyncMMIO=1`) holds **150 W sustained CPU power**.

2. **Random 1-minute / 6-minute Fan Drops in `OmenMon-Reborn v1.6.2`**
   - **Cause 1 (GPU fan drop):** When `FanProgramSharedTemperature` is `false`, uneven CPU vs GPU cooling/sensors cause one fan to drop mid-load. Set `<FanProgramSharedTemperature>true</FanProgramSharedTemperature>`.
   - **Cause 2 (~6 min drop of both fans):** When `FanProgramModeCheckFirst` is `true`, `OmenMon-Reborn` skips re-sending BIOS `SetFanMode(Performance)` on each `30 s` tick, allowing the EC watchdog timer (`CountdownReg=99`) to expire back to stock curve. Set `<FanProgramModeCheckFirst>false</FanProgramModeCheckFirst>` alongside `<FanCountdownExtendAlways>true</FanCountdownExtendAlways>`.

3. **RTX 4080 Laptop `175 W -> 225 W` TGP Unlock (and why `MIXED` state happens)**
   - Upstream `NvpwrControl` unlocks the NVIDIA kernel power policy (`175 W` stock = `150 W` base + `25 W` DB -> up to **`225 W`**, i.e. `175 W` + `50 W` DB).
   - **Key catch on HP OMEN + High Performance power plan:** If Windows is on `High performance` (min CPU state `100%`), NVPCF stays in `MIXED` state and `NvpwrCtl.exe set` refuses or caps early.
   - **Fix implemented in `scripts/`:** Briefly switch the active Windows power plan to `Power saver` (`162e1a7b-6914-4ca1-b348-634f73e08a53`) for ~1–2 s until `NvpwrCtl.exe status` settles into `STOCK_BASELINE` (`175.0 W`), execute `NvpwrCtl.exe set 4080 <targetW>`, then immediately restore `High performance`.
   - Includes a live **Power Slider GUI (`150 W – 225 W`)** (`RTX4080-PowerSlider.bat`), boot auto-start (`AutoStart-MaxPerf.ps1`), and a 1-click **Restore 175 W + Disable Test-Signing** script (`3-Restore-Stock-175W-And-Disable-TestMode.bat`) for kernel anti-cheat games.

4. **MSI Afterburner V/F Curve Tuning (200 W Capped vs 225 W Uncapped)**
   - At `225 W`, the stock flat-cap at `1.020 V` leaves headroom unused. Two ready-to-apply profiles for `DEV_27E0&SUBSYS_8BAD103C` are in `configs/afterburner/`:
     - `VEN_10DE_200W_capped_1.020V.cfg`: `+237 MHz` Core flat-capped @ `2745 MHz / 1.020 V`, `+347 MHz` Mem (`9348 MHz`). Cooler & efficient for `200 W`.
     - `VEN_10DE_225W_uncapped.cfg`: `+237 MHz` below `1.020 V`, `+252 MHz` uncapped `1.020–1.110 V` (~`2805–2862 MHz` peak), `+347 MHz` Mem (`9348 MHz`).

5. **Intel i7-13700HX Single-Core Boost (`Core 4* & Core 6*`) + Disabling VBS / Hyper-V**
   - Uses **ThrottleStop 9.7.3+** (`UsePerCore=1`, `PerCore4=51/52`, `PerCore6=51/52`, `OneAD_EAX0=0x32323333` for `51x` or `0x32323434` for `52x`, keeping `3–8` active cores at `50x`)—no Intel XTU background service (`XTU3SERVICE`) needed.
   - Disabling Windows VBS & Hyper-V (`VirtualizationBasedSecurityStatus=0`, `HypervisorPresent=False`) removes the ~3–4% virtualization/SLAT tax on 1-core/2-core/memory latency and unblocks `MSR 0x150` FIVR undervolt/ratio writes. Reversible via `Restore-Hypervisor-And-WSL.bat`.

---

## Upstream Tools Required (Not Bundled)

Download these directly from their upstream projects:

1. **OmenMon-Reborn v1.6.2+** + **PawnIO v2.2.0+** (replaces HP OMEN Gaming Hub & legacy WinRing0):
   - Repo: <https://github.com/seakyy/OmenMon-Reborn> (GPL-3.0, fork of <https://github.com/OmenMon/OmenMon>)
2. **NvpwrControl** (GPU TGP unlocker, `v1.8.0` for NVIDIA driver `616.92`, or `v2.0`+):
   - Repo: <https://github.com/timmyy123/nvidia-power-control>
   - Site/Downloads: <https://www.nvpwrcontrol.site>
   - Extract `NvpwrControl.exe`, `NvpwrCtl.exe`, `Nvpwr.sys`, `Nvpwr.cer` into [`nvpwr/`](nvpwr/README.md).
3. **ThrottleStop 9.7.3+**:
   - <https://www.techpowerup.com/download/techpowerup-throttlestop/>
4. **MSI Afterburner**:
   - <https://www.msi.com/Landing/afterburner/graphics-cards>

---

## Quick Start

> **Important Pre-Requisites:**
> - **Uninstall / disable HP OMEN Gaming Hub (`hpqcaslwmiex`, `shpamsvc`, `HPOmenCap`) and Intel XTU (`XTU3SERVICE`)** before using OmenMon + ThrottleStop, otherwise HP services fight EC fan control and reset `PL1`.
> - **Disable Secure Boot in BIOS** if using `Nvpwr.sys` (`v1.8.0` requires Windows `testsigning on` to load `Nvpwr.sys`; note `NvpwrControl v2.0+` may differ—check upstream).
> - Kernel anti-cheat games (**FACEIT AC, Riot Vanguard, EA Anti-Cheat**) require `testsigning off` + Secure Boot enabled. Run `scripts/3-Restore-Stock-175W-And-Disable-TestMode.bat` and re-enable Secure Boot before playing those.

### Step 1: Configure `OmenMon-Reborn` (`150 W` CPU + Zero Fan Drops)
1. Install PawnIO + `OmenMon-Reborn v1.6.2+` (e.g. `C:\OmenMon\OmenMon.exe` or `%USERPROFILE%\Desktop\omen\OmenMon.exe`).
2. Update your `OmenMon.xml` using [`configs/omenmon/OmenMon-8BAD-Reference.xml`](configs/omenmon/OmenMon-8BAD-Reference.xml):
   - `<FanProgramModeCheckFirst>false</FanProgramModeCheckFirst>`
   - `<FanProgramSharedTemperature>true</FanProgramSharedTemperature>`
   - `<FanCountdownExtendAlways>true</FanCountdownExtendAlways>`
   - `<FanMode>Performance</FanMode>` and `<GpuPower>Maximum</GpuPower>` inside your AC fan programs (`Power`, `SilentPower`).

### Step 2: Configure `ThrottleStop 9.7.3+`
- Enable `TPL -> SyncMMIO`, set `PL1 = 150 W`, `PL2 = 150 W` (or use `OmenMon -Bios FanMode=Performance Cpu:PL1=150`).
- Apply your safe stable FIVR undervolt (e.g. `-45 mV` Core & P-Cache, `48x` Cache). See [`configs/throttlestop/ThrottleStop-13700HX-150W-OC-Reference.ini`](configs/throttlestop/ThrottleStop-13700HX-150W-OC-Reference.ini).
- *(Optional +0.1 GHz / +0.2 GHz on favored P-cores `Core 4 & Core 6` + Disable VBS/Hyper-V):*
  Run `scripts\Apply-CPU-OC-And-Disable-VBS.bat` as Administrator and reboot. Switch between `50x` / `51x` / `52x` anytime with `scripts\Set-Core46-Target.bat` (or restore WSL2/Hyper-V with `scripts\Restore-Hypervisor-And-WSL.bat`).

### Step 3: Unlock GPU to `200–225 W` (`NvpwrControl` + Power Saver Baseline Dip)
1. Put the extracted `NvpwrControl` files into `nvpwr/`.
2. Run `scripts\1-Enable-TestMode-Before-Reboot.bat` as Administrator (installs `Nvpwr.cer`, runs `bcdedit /set testsigning on`), then **reboot**.
3. After rebooting, run `scripts\2-Apply-GPU-TGP-After-Reboot.bat` as Administrator (automatically dips to `Power saver` so NVPCF enters `STOCK_BASELINE`, applies `225 W` — or `200 W` if passed as argument — and restores `High performance`).
4. *(Optional live slider)* Launch `scripts\RTX4080-PowerSlider.bat` to slide dynamically between `150 W` and `225 W`.

### Step 4: Apply Tuned MSI Afterburner V/F Curve
- Run `scripts\4-Apply-Afterburner-Curve.bat` as Administrator, pick **`[1] 225 W Uncapped`** or **`[2] 200 W Capped (1.020 V)`** (automatically backs up your existing `.cfg` into `backups/`).
- ⚠️ **Silicon lottery warning:** `+237/+252 MHz` Core and `+347 MHz` Mem are tuned for a specific sample. If you see artifacts or DXGI/driver crashes, back Core down by `-15` to `-30 MHz` or Mem to `+200–250 MHz`.

### Step 5: Persist Everything Automatically on Boot
- Run `scripts\6-Install-Boot-AutoStart.bat` as Administrator to register `Nvpwr MaxPerf AutoUnlock` at logon, running [`scripts/AutoStart-MaxPerf.ps1`](scripts/AutoStart-MaxPerf.ps1).

---

## Safety, Thermals & Power Brick Warning

> **USE AT YOUR OWN RISK.** Raising CPU + GPU power ceilings generates significantly more heat and draws higher current through your motherboard VRMs and AC adapter.

- **330 W OEM Power Adapter Budget:** `150 W` CPU + `225 W` GPU = `375 W` theoretical simultaneous peak, which exceeds a 330 W brick if you run synthetic CPU+GPU burn tests (like Prime95 + FurMark) at the same time.
  - For **combined heavy gaming / mixed CPU+GPU loads**, `200 W` GPU + `150 W` CPU (or normal game CPU ~50–80 W + `225 W` GPU) stays comfortably inside adapter limits.
  - Use **`Power` (100% fans)** during heavy `225 W` benchmarks, and monitor **GPU temp (`<= 87 °C` TJMax), GPU Hotspot, VRAM, and CPU package temps** in HWiNFO64.

---

## Repository Structure

```text
.
├── README.md
├── LICENSE
├── .gitignore
├── configs/
│   ├── afterburner/
│   │   ├── VEN_10DE_200W_capped_1.020V.cfg
│   │   └── VEN_10DE_225W_uncapped.cfg
│   ├── omenmon/
│   │   └── OmenMon-8BAD-Reference.xml
│   └── throttlestop/
│       └── ThrottleStop-13700HX-150W-OC-Reference.ini
├── nvpwr/
│   └── README.md
└── scripts/
    ├── 1-Enable-TestMode-Before-Reboot.bat
    ├── 2-Apply-GPU-TGP-After-Reboot.bat
    ├── 3-Restore-Stock-175W-And-Disable-TestMode.bat
    ├── 4-Apply-Afterburner-Curve.bat
    ├── 5-Restore-Afterburner-Backup.bat
    ├── 6-Install-Boot-AutoStart.bat
    ├── Apply-CPU-OC-And-Disable-VBS.bat
    ├── Apply-CPU-OC-And-Disable-VBS.ps1
    ├── AutoStart-MaxPerf.ps1
    ├── Common-Paths.ps1
    ├── Restore-Hypervisor-And-WSL.bat
    ├── Restore-Hypervisor-And-WSL.ps1
    ├── RTX4080-PowerSlider.bat
    ├── RTX4080-PowerSlider.ps1
    ├── Set-Core46-Target.bat
    └── Set-Core46-Target.ps1
```
