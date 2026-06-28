# steady_nx_pack

`build_nx_pack.sh` is a shell script utility designed to automate the construction of a standardized Nintendo Switch Custom Firmware (CFW) SD card layout. It retrieves, validates, and stages binaries from upstream repositories to ensure a consistent, conflict-free filesystem state.

## Technical Architecture

### Upstream Sourcing

Binaries are fetched directly from official release repositories via the GitHub API. This approach ensures bit-for-bit parity with upstream assets.

### GitHub Actions Integration

Fetching, construction, and release management are executed via GitHub Actions. The primary workflow is defined in `.github/workflows/release.yml`, ensuring that every build occurs in a clean, isolated environment and follows a traceable lifecycle.

### Staged Synchronization

To maintain filesystem integrity, the script does not extract archives directly into the output directory:

1. Assets are unpacked into isolated staging sub-directories.
2. `rsync` performs an additive merge into the final structure, preserving directory hierarchies and preventing destructive file overwrites.

### Caching and Determinism

Downloads are cached in `_downloads/` using a unique key derived from the repository owner, project name, and release tag. This mechanism mitigates filename collisions inherent in projects that reuse generic assets (e.g., `sdout.zip`, `dist.zip`).

### Configuration & Integrity

* **Version Control:** Every build generates `CHANGELOG.md` and `CHANGELOG.txt`, documenting the specific component versions retrieved.
* **System Configuration:**
* The script generates an `exosphere.ini` on the root of the layout to ensure standardized PRODINFO blanking across all installations.
* Integration of `sys-patch` ensures essential system patches are applied at boot, rendering manual sigpatch management unnecessary.


* **Payload Mapping:** Hekate binaries are mapped to `hekate.bin`, `payload.bin`, and `atmosphere/reboot_to_payload.bin` for compatibility with various bootloaders and modchip firmware.

### Required Hekate Configuration

To ensure proper functionality of the included modules (such as Horizon-OC), update your `bootloader/hekate_ipl.ini` file to include the following:

```ini
[CFW]
kip1=atmosphere/kips/hoc.kip
secmon=atmosphere/exosphere.bin

```

## Components and Attribution

The following components are integrated into the SD layout:

| Component | Repository |
| --- | --- |
| **Atmosphère** | [atmosphere-nx/atmosphere](https://github.com/atmosphere-nx/atmosphere) |
| **Hekate** | [ctcaer/hekate](https://github.com/ctcaer/hekate) |
| **DBI** | [rashevskyv/dbi](https://github.com/rashevskyv/dbi) |
| **disable_remap_dialog** | [ndeadly/disable_remap_dialog](https://github.com/ndeadly/disable_remap_dialog) |
| **MissionControl** | [ndeadly/MissionControl](https://github.com/ndeadly/MissionControl) |
| **SaltyNX** | [masagrator/SaltyNX](https://github.com/masagrator/SaltyNX) |
| **theme-patches** | [exelix11/theme-patches](https://github.com/exelix11/theme-patches) |
| **nx-ovlloader** | [ppkantorski/nx-ovlloader](https://github.com/ppkantorski/nx-ovlloader) |
| **EdiZon-Overlay** | [proferabg/EdiZon-Overlay](https://github.com/proferabg/EdiZon-Overlay) |
| **Horizon-OC** | [Horizon-OC/Horizon-OC](https://github.com/Horizon-OC/Horizon-OC) |
| **FPSLocker** | [masagrator/FPSLocker](https://github.com/masagrator/FPSLocker) |
| **QuickNTP** | [nedex/QuickNTP](https://github.com/nedex/QuickNTP) |
| **sys-patch** | [borntohonk/sys-patch](https://github.com/borntohonk/sys-patch) |
| **ovl-sysmodules** | [ppkantorski/ovl-sysmodules](https://www.google.com/search?q=https://github.com/ppkantorski/ovl-sysmodules) |
| **FPSLocker (fork)** | [ppkantorski/FPSLocker](https://www.google.com/search?q=https://github.com/ppkantorski/FPSLocker) |
| **Memory-Kit** | [ppkantorski/Memory-Kit](https://www.google.com/search?q=https://github.com/ppkantorski/Memory-Kit) |
| **Alchemist** | [ppkantorski/Alchemist](https://github.com/ppkantorski/Alchemist) |
| **HOC-Toolkit** | [ppkantorski/HOC-Toolkit](https://www.google.com/search?q=https://github.com/ppkantorski/HOC-Toolkit) |
| **Ultrahand-Overlay** | [ppkantorski/Ultrahand-Overlay](https://github.com/ppkantorski/Ultrahand-Overlay) |
| **emuiibo** | [XorTroll/emuiibo](https://github.com/XorTroll/emuiibo) |
| **Status-Monitor-Overlay** | [ppkantorski/Status-Monitor-Overlay](https://www.google.com/search?q=https://github.com/ppkantorski/Status-Monitor-Overlay) |
