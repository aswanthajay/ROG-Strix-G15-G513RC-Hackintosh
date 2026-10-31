# ASUS ROG Strix G15 (G513RC) - OpenCore EFI for macOS Sequoia 15.x

OpenCore EFI configuration for the **ASUS ROG Strix G15 (2022) G513RC** gaming laptop running **macOS 15 Sequoia (15.8.2 / Build 24H232)** alongside Windows 11.

> [!WARNING]
> **Work in Progress (WIP):** This EFI currently boots cleanly into the **macOS Recovery Environment**, recognizes all internal NVMe drives, and supports full mouse/trackpad interaction. Full Stage 2 installation and post-install hardware tuning are actively being refined.

---

## 💻 Hardware Specifications

| Component | Specification | macOS Status |
| :--- | :--- | :--- |
| **Model** | ASUS ROG Strix G15 (2022) G513RC / G513RC-HN063W | Supported |
| **Processor** | AMD Ryzen 7 6800HS (Zen 3+ Rembrandt, 8C/16T, up to 4.7 GHz) | **Working** (AMD Vanilla Patches) |
| **Integrated GPU** | AMD Radeon 680M (RDNA 2) | **VESA Mode** (No Metal acceleration) |
| **Dedicated GPU** | NVIDIA GeForce RTX 3050 Laptop (4 GB GDDR6) | **Disabled** via SSDT / boot-args |
| **Memory** | 16 GB DDR5 4800 MHz (2x 8 GB Dual Channel) | **Working** |
| **Internal SSD** | Micron 2400 NVMe PCIe 4.0 1 TB | **Working** (APFS Recognized) |
| **Audio** | Realtek ALC294 | **Testing** (AppleALC) |
| **Wireless / BT** | MediaTek MT7922 (Wi-Fi 6E) | **Unsupported** in Recovery (Needs offline setup) |
| **Ethernet** | Realtek RTL8125 2.5GbE | **Supported** (LucyRTL8125Ethernet) |
| **Keyboard** | ASUS RGB Keyboard (I8042 / ATK) | **Known Issue** (Runaway key repeats) |
| **Touchpad** | ASUS Precision Touchpad (I2C HID) | **Working** (VoodooI2C + VoodooI2CHID) |
| **Bootloader** | OpenCore 1.0.4 RELEASE | **Working** |

---

## 🚦 Current Status & Milestones

- [x] **OpenCore 1.0.4 Bootloader:** Boots cleanly with AMD Zen 3+ kernel patches.
- [x] **macOS Recovery:** Boots 100% reliably into macOS 15.8.2 / 15.4 Recovery environment.
- [x] **Internal NVMe:** Micron 2400 SSD recognized by Apple APFS driver in read/write mode.
- [x] **Pointing Devices:** Trackpad and external USB mice function properly.
- [x] **Display:** Native resolution display via VESA framebuffer mode.
- [x] **Offline Installer Staging:** 100% offline installation scripts ready via `startosinstall`.
- [ ] **Internal Keyboard Timing:** Resolving key repeat runaway issue under Recovery.
- [ ] **Stage 2 OS Finalization:** APFS container sealing and Setup Assistant boot.
- [ ] **Audio Tuning:** Finalizing layout-id for Realtek ALC294 speakers and headphone jack.

---

## ⚠️ Known Issues & Important Workarounds

### 1. Internal Keyboard Runaway Key Repeat Bug
* **Symptom:** Pressing any key inside macOS Recovery triggers infinite runaway keystrokes (e.g., `hhhhhhhhhh...`).
* **Root Cause:** Interrupt timing mismatch between ASUS ATK embedded controller firmware and `VoodooPS2Controller` / macOS input stack.
* **Workarounds:**
  1. **Mouse-Driven Workflow (Recommended):** Use the included `start.html` helper inside Safari to copy terminal commands directly to the clipboard, then use Terminal's **Edit &rarr; Paste** with the mouse. Zero typing required.
  2. **External USB Keyboard:** Plug in a standard USB wired keyboard.

### 2. MediaTek MT7922 Wi-Fi Unsupported in Recovery
* **Symptom:** macOS Recovery cannot detect Wi-Fi networks and reports no internet connection.
* **Workaround:** 
  - Do not use online web recovery stubs (`BaseSystem.dmg` alone).
  - Use the full offline 15.66 GB `InstallAssistant.pkg` or `Install macOS Sequoia.app` bundle placed on an exFAT partition or NVMe.
  - Trigger installation locally via `startosinstall --volume /Volumes/macwin --agreetolicense --nointeraction`.

### 3. ACPI Shutdown / Restart Freeze
* **Symptom:** When macOS Recovery attempts to reboot or shutdown, the system halts with a frozen mouse pointer at `Restarting...` or `Finished operation queue`.
* **Root Cause:** ASUS ROG Strix AMD ACPI warm-reset vector incompatibility.
* **Workaround:** Once terminal writes reach 100%, wait 20 seconds for NVMe cache to safely flush, hold the **Power Button for 5 seconds** to power down, then power back on manually.

### 4. APFS Container Architecture for Dual-Booting
* **Symptom:** OpenCore only displays `macwin (dmg)` and never offers `macOS Installer` or `macwin`.
* **Root Cause:** Modern macOS (macOS 11+) requires specific APFS auxiliary volume roles:
  - System Volume (e.g., `macwin`)
  - Preboot Volume (`-role B`)
  - Recovery Volume (`-role R`)
* **Fix:** Ensure the container has the auxiliary roles created via `diskutil apfs addVolume <Container> apfs Preboot -role B` before executing `startosinstall`.

### 5. Graphics Acceleration (RDNA 2 Radeon 680M)
* macOS does not natively include Metal drivers for AMD RDNA 2 integrated graphics. Display runs in software VESA mode. NVIDIA RTX 3050 dGPU is disabled via SSDT to prevent kernel panics.

---

## 🛠️ EFI Architecture

### ACPI Tables (`EFI/OC/ACPI/`)
* `SSDT-EC-USBX-LAPTOP.aml`: Embedded Controller and USB power injection.
* `SSDT-HPET.aml`: High Precision Event Timer IRQ conflict resolution.
* `SSDT-PLUG-ALT.aml`: Processor power management for Zen 3+ CPUs.
* `SSDT-PNLF.aml`: Backlight control definitions.
* `SSDT-XOSI.aml`: Windows OS interface simulator for ACPI events.
* `SSDT-DISAURA.aml`: Disables ASUS Aura RGB lighting controller to prevent ACPI loop spam.

### Kexts (`EFI/OC/Kexts/`)
* `Lilu.kext`: Arbitrary kext and process patching engine.
* `VirtualSMC.kext`: Advanced Apple SMC emulator.
* `SMCProcessor.kext`: AMD processor monitoring.
* `SMCBatteryManager.kext`: ASUS laptop battery readout.
* `AppleALC.kext`: Dynamic audio patcher for ALC294.
* `AMDRyzenCPUPowerManagement.kext`: CPU power management for Zen CPUs.
* `RestrictEvents.kext`: Process restraint (`revpatch=sbvmm,cpuname`).
* `ForgedInvariant.kext`: TSC synchronization on AMD hardware.
* `VoodooI2C.kext` & `VoodooI2CHID.kext`: Precision touchpad support.
* `VoodooPS2Controller.kext`: Keyboard and trackpad controller.
* `UTBMap.kext` & `USBToolBox.kext`: Mapped USB ports for ASUS G513.

### Drivers (`EFI/OC/Drivers/`)
* `OpenRuntime.efi`: Essential OpenCore runtime services.
* `OpenHfsPlus.efi`: HFS+ filesystem driver.
* `ToggleSipEntry.efi`: Quick SIP toggle utility in boot picker.
* `apfs.efi`: Apple APFS driver for container handling.

---

## ⚙️ Recommended BIOS Settings

Press `F2` during boot to enter ASUS BIOS setup (`F7` for Advanced Mode):

* **Advanced &rarr; CPU Configuration:**
  - **SVM Mode (AMD-V):** `Enabled`
* **Advanced &rarr; Graphics Configuration:**
  - **Above 4G Decoding:** `Enabled`
* **Advanced &rarr; SATA Configuration:**
  - **SATA Mode:** `AHCI`
* **Security &rarr; Secure Boot:**
  - **OS Type:** `Other OS` / **Secure Boot Control:** `Disabled`
* **Boot &rarr; Boot Configuration:**
  - **Fast Boot:** `Disabled`

---

## 🚀 How to Use

1. Format a USB drive (at least 4 GB) with a FAT32 partition labeled `OPENCORE`.
2. Copy the `EFI` folder to the root of the FAT32 partition.
3. Download the official Apple Recovery files or stage the full 16 GB `InstallAssistant.pkg`.
4. Boot into OpenCore (`F8` or `Esc` on startup) and select **`macOS Recovery (dmg)`**.
5. Use the mouse-driven Safari launcher (`start.html`) to execute offline installation to your dedicated APFS partition.

---

## 🤝 Credits & Acknowledgements
- [Acidanthera](https://github.com/acidanthera) for OpenCore, Lilu, VirtualSMC, AppleALC, RestrictEvents, and VoodooPS2.
- [AMD-OSX](https://github.com/AMD-OSX/AMD_Vanilla) for the vanilla AMD kernel patches.
- [Dortania](https://dortania.github.io/OpenCore-Install-Guide/) for comprehensive Hackintosh guides.
- The Hackintosh community for ongoing research into mobile AMD Rembrandt platforms.
