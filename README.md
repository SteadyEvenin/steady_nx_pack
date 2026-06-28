`build_nx_pack.sh` is a utility for generating a standardized Nintendo Switch Custom Firmware (CFW) SD card layout. It automates the retrieval, validation, and staging of binaries from upstream repositories to produce a clean, conflict-free boot-ready CFW pack.

## Purpose

The goal of this project is to provide a "copy-paste" ready SD card layout that maintains strict integrity with upstream sources. By automating the build process, the script ensures that the filesystem remains consistent, and provides a verifiable audit trail of component versions.

## Technical Architecture

### Upstream Sourcing
The script fetches binaries directly from official repositories. This ensures that the final SD card contains original code rather than modified or potentially compromised "re-packs."

### Github Workflow-built
Fetching, construction, and release management are handled via GitHub Actions. The primary workflow is located at .github/workflows/release.yml, ensuring that every release is built in a clean, isolated environment and follows a traceable lifecycle.

### Staged Merging
To prevent filesystem corruption or destructive overwrites, assets are not extracted directly into the output directory. 
1. Assets are unpacked into isolated, temporary staging directories.
2. `rsync` is used to perform an additive merge into the final layout.
3. This preserves existing directory structures and ensures that only intended files are updated.

### Caching & Determinism
Downloads are indexed using a unique key (Owner + Project + Tag). This prevents collisions between projects using identical filenames. A `CHANGELOG` is generated for every build to record the specific versions of all components retrieved via the GitHub API.

## Components/Credits

The following repositories are used to construct the SD layout:

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
