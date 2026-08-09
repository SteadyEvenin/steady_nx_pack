![Project Banner](https://raw.githubusercontent.com/SteadyEvenin/steady_nx_pack/main/.desc/bg.png)
# steady_nx_pack

A shell script and GitHub Actions pipeline that pulls the latest release of each listed component from GitHub, assembles them into a bootable Nintendo Switch CFW SD card layout, and publishes the result as a downloadable zip.

This is a personal build, not a recommendation. Component selection reflects one specific setup. Read the source before flashing anything to your console.

## How it works

`build_nx_pack.sh` runs a fixed sequence of `process()` calls. Each one:

1. Resolves the latest release tag via the GitHub API.
2. Matches a release asset by filename pattern.
3. Downloads it to `_downloads/`. Filenames that collide across repos (e.g. `sdout.zip`) are renamed per-call via an override so neither is silently dropped.
4. Places the asset using one of four modes: extract zip to SD root, extract to a subfolder, extract a specific subfolder from inside a zip, or copy a single file to a fixed destination. Extraction is `unzip -o` directly into the output directory.
5. Appends a result record to an in-memory list written as `CHANGELOG.md` and `CHANGELOG.txt` at the end of the run.

Three components require steps outside the standard `process()` flow:

- **Ultrahand-Overlay**: `ovlmenu.ovl` and `lang.zip` are separate assets in the same release and are fetched individually after the main zip.
- **Memory-Kit**: the release zip does not include the mesosphere kernel binary. `mesosphere_1.85MB_1.11.bin` is pulled directly from the repo source tree and placed at `atmosphere/`.
- **emummc.bmp**: pulled from this repo's own `assets/` folder and placed at `bootloader/res/`.

After all components are placed, the script writes:

- `exosphere.ini` at the SD root with PRODINFO blanking enabled.
- `bootloader/hekate_ipl.ini` with a single `CFW (EMUMMC)` boot entry. The `kernel=` line references the mesosphere binary above. The `kip1=` line references `atmosphere/kips/hoc.kip`, shipped by Horizon-OC.
- `atmosphere/config/system_settings.ini` with the settings listed below.

The Hekate payload binary is copied to `hekate.bin`, `payload.bin`, `atmosphere/reboot_to_payload.bin`, and `bootloader/payloads/hekate.bin`. Lockpick RCM is placed at `bootloader/payloads/Lockpick_RCM.bin`.

## Components

| Component | Repository | Notes |
|---|---|---|
| Atmosphère | [Atmosphere-NX/Atmosphere](https://github.com/Atmosphere-NX/Atmosphere) | |
| Hekate | [CTCaer/hekate](https://github.com/CTCaer/hekate) | |
| DBI | [rashevskyv/dbi](https://github.com/rashevskyv/dbi) | |
| disable_remap_dialog | [ndeadly/disable_remap_dialog](https://github.com/ndeadly/disable_remap_dialog) | |
| MissionControl | [ndeadly/MissionControl](https://github.com/ndeadly/MissionControl) | |
| SaltyNX | [masagrator/SaltyNX](https://github.com/masagrator/SaltyNX) | |
| theme-patches | [exelix11/theme-patches](https://github.com/exelix11/theme-patches) | No releases; pulled from master branch source archive |
| nx-ovlloader | [ppkantorski/nx-ovlloader](https://github.com/ppkantorski/nx-ovlloader) | Active fork; WerWolv/nx-ovlloader is unmaintained |
| EdiZon-Overlay | [proferabg/EdiZon-Overlay](https://github.com/proferabg/EdiZon-Overlay) | |
| Horizon-OC | [Horizon-OC/Horizon-OC](https://github.com/Horizon-OC/Horizon-OC) | Ships `hoc.kip` referenced in `hekate_ipl.ini` |
| QuickNTP | [ppkantorski/QuickNTP](https://github.com/ppkantorski/QuickNTP) | Fork of nedex/QuickNTP |
| sys-patch | [impeeza/sys-patch](https://github.com/impeeza/sys-patch) | Applied automatically at boot |
| ovl-sysmodules | [ppkantorski/ovl-sysmodules](https://github.com/ppkantorski/ovl-sysmodules) | |
| FPSLocker | [ppkantorski/FPSLocker](https://github.com/ppkantorski/FPSLocker) | Fork |
| Memory-Kit | [ppkantorski/Memory-Kit](https://github.com/ppkantorski/Memory-Kit) | Mesosphere binary fetched from repo source tree, not release zip |
| Alchemist | [ppkantorski/Alchemist](https://github.com/ppkantorski/Alchemist) | |
| Ultrahand-Overlay | [ppkantorski/Ultrahand-Overlay](https://github.com/ppkantorski/Ultrahand-Overlay) | `ovlmenu.ovl` and `lang.zip` fetched as separate assets |
| ReverseNX-RT | [ppkantorski/ReverseNX-RT](https://github.com/ppkantorski/ReverseNX-RT) | Requires SaltyNX (included) |
| DNS-MITM_Manager | [sthetix/DNS-MITM_Manager](https://github.com/sthetix/DNS-MITM_Manager) | |
| ldn_mitm | [spacemeowx2/ldn_mitm](https://github.com/spacemeowx2/ldn_mitm) | |
| Quick-Reboot | [eradicatinglove/Quick-Reboot](https://github.com/eradicatinglove/Quick-Reboot) | `.nro` and `.ovl` fetched as separate assets |
| emuiibo | [XorTroll/emuiibo](https://github.com/XorTroll/emuiibo) | |
| Status-Monitor-Overlay | [ppkantorski/Status-Monitor-Overlay](https://github.com/ppkantorski/Status-Monitor-Overlay) | |
| sphaira | [NaGaa95/sphaira](https://github.com/NaGaa95/sphaira) | Homebrew menu replacement |
| NXThemesInstaller | [exelix11/SwitchThemeInjector](https://github.com/exelix11/SwitchThemeInjector) | Theme installer homebrew |
| sys-con | [o0Zz/sys-con](https://github.com/o0Zz/sys-con) | Third-party controller support via USB |
| Lockpick RCM | [THZoria/Lockpick_RCMaster](https://github.com/THZoria/Lockpick_RCMaster) | Key dumping payload, placed at `bootloader/payloads/` |

## Generated configuration

### `atmosphere/config/system_settings.ini`

| Section | Key | Value | Effect |
|---|---|---|---|
| `[usb]` | `usb30_force_enabled` | `1` | Forces USB 3.0 superspeed for homebrew transfers |
| `[atmosphere]` | `dmnt_cheats_enabled_by_default` | `0` | Cheats off by default on game launch |
| `[atmosphere]` | `dmnt_always_save_cheat_toggles` | `1` | Always saves cheat toggle state between launches |
| `[atmosphere]` | `enable_dns_mitm` | `1` | Enables Atmosphere DNS MITM (required by DNS-MITM_Manager) |
| `[atmosphere]` | `add_defaults_to_dns_hosts` | `1` | Applies default Nintendo domain redirections alongside hosts file |
| `[atmosphere]` | `enable_external_bluetooth_db` | `1` | Stores Bluetooth pairing database on SD card, shared across sysmmc/emummc |
| `[ns.notification]` | all entries | disabled / max interval | Disables Nintendo network update checks, eShop sync, and telemetry tasks |
| `[olsc]` | `enable_olsc_communication_block` | `1` | Blocks Nintendo online save cloud sync |
| `[olsc]` | `default_auto_download_global_setting` | `0` | Auto cloud download off |
| `[olsc]` | `default_auto_upload_global_setting` | `0` | Auto cloud upload off |
| `[am.gpu]` | `gpu_scheduling_enabled` | `0` | Disables GPU scheduling (stability over throughput) |

All other settings in the file are present as commented-out reference entries and have no effect unless uncommented.

### `bootloader/hekate_ipl.ini`

Single boot entry `CFW (EMUMMC)` with:

```
kernel=atmosphere/mesosphere_1.85MB_1.11.bin
kip1=atmosphere/kips/hoc.kip
secmon=atmosphere/exosphere.bin
emummcforce=1
icon=bootloader/res/emummc.bmp
```

### `exosphere.ini`

PRODINFO blanking enabled on both sysmmc and emummc (`blank_prodinfo_sysmmc=1`, `blank_prodinfo_emummc=1`). Debug mode off.

## Running locally

```bash
chmod +x build_nx_pack.sh
./build_nx_pack.sh [OUTPUT_DIR]
```

Requires `curl`, `unzip`, `python3`.

| Variable | Effect |
|---|---|
| `GITHUB_TOKEN` | Raises the API rate limit from 60 to 5000 requests/hour. A full run without it can exhaust the unauthenticated limit. |
| `OUTPUT_DIR` | Output path. Defaults to `./SD_Card_Output`. |
| `KEEP_DOWNLOADS` | Set to `1` to keep `_downloads/` between runs. |

Copy the contents of `SD_Card_Output/` to the root of an exFAT formatted SD card.

## GitHub Actions

### `release.yml`

Triggered by a `v*` tag push, by `poll_upstreams.yml`, or manually. Runs as two jobs: `build` produces and uploads the zip and release body as artifacts; `release` downloads them and publishes the GitHub Release. Split so a publish failure can be retried without rebuilding. The release body identifies what triggered the build and, when triggered by the poller, which components changed.

### `poll_upstreams.yml`

Runs every 6 hours. Queries each tracked repo for its latest release tag (or latest commit SHA for repos with no releases). Compares against a baseline stored as `.upstream-tags.json` on an orphan branch named `upstream-state`. If anything changed, commits the updated baseline and dispatches `release.yml` with the list of changed components.

Requires the repo's Actions permissions set to **Read and write** under Settings > Actions > General.

## Caveats

- Change detection is tag-based. A repo retagging an existing release without a new tag will not trigger a rebuild.
- No checksum or signature verification is performed on downloaded assets. The script trusts the repos listed above.
- This works for one specific console setup. It may not work for yours.
