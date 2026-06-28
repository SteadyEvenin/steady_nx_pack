# build_nx_pack

`build_nx_pack.sh` is a shell script utility designed to automate the construction of a standardized Nintendo Switch Custom Firmware (CFW) SD card layout. It retrieves, validates, and stages binaries from upstream repositories to ensure a consistent, conflict-free filesystem state.

## Technical Design

### Repository-Aware Caching
Downloads are stored in `_downloads/` using a unique key derived from the repository owner, project name, and release tag. This prevents filename collisions inherent in projects that reuse generic assets (e.g., `sdout.zip`).

### Staged Synchronization
Assets are not extracted directly into the output directory. They are unpacked into isolated staging sub-directories; `rsync` is then used to perform an additive merge into the final structure. This preserves existing directories and prevents destructive file overwrites.

### Version Control & Verification
Each build generates `CHANGELOG.md` and `CHANGELOG.txt`, cataloging the exact component versions retrieved from the GitHub API.

### Dot-File Integrity
The script utilizes `shopt -s dotglob` to ensure hidden directories (e.g., `switch/.overlays`) are processed correctly.

## Prerequisites

- **Environment**: POSIX-compliant shell.
- **Dependencies**: `curl`, `unzip`, `python3`, `rsync`.

## Usage

1. Set execution permissions:
   ```bash
   chmod +x build_nx_pack.sh
   ```
2. Run the script:
   ```bash
   ./build_nx_pack.sh [OUTPUT_DIR]
   ```

## Configuration

| Variable | Description |
| :--- | :--- |
| `GITHUB_TOKEN` | Optional. Provides authentication to bypass GitHub API rate limits (60 to 5000 req/hr). |
| `OUTPUT_DIR` | Optional. Overrides the default `./SD_Card_Output` destination. |
| `KEEP_DOWNLOADS` | Optional. Set to `1` to persist the `_downloads/` cache across multiple runs. |

## Component Credits

The following repositories are utilized to construct the SD pack:

| Component | Author / Repository |
| :--- | :--- |
| Atmosphère | atmosphere-nx/atmosphere |
| Hekate | ctcaer/hekate |
| DBI | rashevskyv/dbi |
| disable_remap_dialog | ndeadly/disable_remap_dialog |
| MissionControl | ndeadly/MissionControl |
| SaltyNX | masagrator/SaltyNX |
| theme-patches | exelix11/theme-patches |
| nx-ovlloader | ppkantorski/nx-ovlloader |
| EdiZon-Overlay | proferabg/EdiZon-Overlay |
| Horizon-OC | Horizon-OC/Horizon-OC |
| FPSLocker | masagrator/FPSLocker |
| QuickNTP | nedex/QuickNTP |
| sys-patch | borntohonk/sys-patch |
| ovl-sysmodules | ppkantorski/ovl-sysmodules |
| FPSLocker (fork) | ppkantorski/FPSLocker |
| Memory-Kit | ppkantorski/Memory-Kit |
| Alchemist | ppkantorski/Alchemist |
| HOC-Toolkit | ppkantorski/HOC-Toolkit |
| Ultrahand-Overlay | ppkantorski/Ultrahand-Overlay |
| emuiibo | XorTroll/emuiibo |
| Status-Monitor-Overlay | ppkantorski/Status-Monitor-Overlay |
