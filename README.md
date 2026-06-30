![Project Banner](https://raw.githubusercontent.com/SteadyEvenin/steady_nx_pack/main/.desc/bg.png)
# steady_nx_pack

A build script and GitHub Actions pipeline that assembles a Nintendo Switch CFW SD card layout from upstream GitHub releases and publishes it as a downloadable zip.

## What this is

`build_nx_pack.sh` downloads the latest release asset from each upstream repository listed below, extracts it into the correct location on a synthetic SD card filesystem, and writes a changelog recording exactly which version of each component was used. The result is packaged into a zip and published as a GitHub Release.

This is a personal build script, not a curated "best of" list. Component selection reflects one specific setup. Read the source before using it on your own console.

## How it works

`build_nx_pack.sh` runs as a single pass through a fixed list of `process()` calls, one per component. Each call does the following:

1. Resolves the latest release tag for the repo via the GitHub API (`/releases/latest`).
2. Finds the release asset matching a given filename pattern.
3. Downloads it to `_downloads/`, named by `basename` of the asset URL. If two repos ship an asset with the same filename (this happens — `sdout.zip` is used by more than one project), a per-call override forces a unique cache name so neither file is silently dropped.
4. Extracts or copies the asset directly into the output directory using one of four modes: extract the whole zip to the SD root, extract to a specific subfolder, pull one file out of a subfolder inside the zip, or copy a single file/overlay to a fixed destination. Extraction uses `unzip -o`, which overwrites on conflict — there is no staging step and no merge logic beyond what each upstream zip's internal layout already provides.
5. Records the result (component name, repo, resolved tag, target path, success or failure) to an in-memory list that becomes `CHANGELOG.md` and `CHANGELOG.txt` at the end of the run.

A handful of components don't ship everything needed inside their release zip and are handled with explicit extra steps:

- **Ultrahand-Overlay**: `ovlmenu.ovl` and `lang.zip` are separate release assets alongside `sdout.zip` and are fetched individually.
- **Memory-Kit**: the release zip does not include the mesosphere kernel binary it depends on. `mesosphere_1.85MB_1.11.bin` is fetched directly from the repository's source tree (`raw.githubusercontent.com`, not a release asset) and placed at `atmosphere/`.
- **bootloader/res/emummc.bmp**: pulled from this repo's own `assets/` folder, not from any upstream.

After all components are processed, the script generates two config files:

- `exosphere.ini` at the SD root, with PRODINFO blanking enabled.
- `bootloader/hekate_ipl.ini`, containing a single `CFW (EMUMMC)` boot entry. The `kernel=` line points at the mesosphere binary described above; the `kip1=` line points at `atmosphere/kips/hoc.kip`, which is shipped by **Horizon-OC**.

Hekate payload files are copied to four locations for compatibility with different bootloader/payload-launcher conventions: `hekate.bin` and `payload.bin` at the SD root, `atmosphere/reboot_to_payload.bin`, and `bootloader/payloads/hekate.bin`.

`sys-patch` is included so signature patches are applied automatically at boot.

## Components

Fetched from each repo's latest GitHub release unless noted otherwise.

| Component | Repository | Notes |
|---|---|---|
| Atmosphère | [Atmosphere-NX/Atmosphere](https://github.com/Atmosphere-NX/Atmosphere) | |
| Hekate | [CTCaer/hekate](https://github.com/CTCaer/hekate) | |
| DBI | [rashevskyv/dbi](https://github.com/rashevskyv/dbi) | |
| disable_remap_dialog | [ndeadly/disable_remap_dialog](https://github.com/ndeadly/disable_remap_dialog) | |
| MissionControl | [ndeadly/MissionControl](https://github.com/ndeadly/MissionControl) | |
| SaltyNX | [masagrator/SaltyNX](https://github.com/masagrator/SaltyNX) | |
| theme-patches | [exelix11/theme-patches](https://github.com/exelix11/theme-patches) | No GitHub releases; pulled from the `master` branch source archive |
| nx-ovlloader | [ppkantorski/nx-ovlloader](https://github.com/ppkantorski/nx-ovlloader) | Active fork; original (WerWolv/nx-ovlloader) is unmaintained |
| EdiZon-Overlay | [proferabg/EdiZon-Overlay](https://github.com/proferabg/EdiZon-Overlay) | |
| Horizon-OC | [Horizon-OC/Horizon-OC](https://github.com/Horizon-OC/Horizon-OC) | Ships `hoc.kip`, referenced in `hekate_ipl.ini` |
| QuickNTP | [ppkantorski/QuickNTP](https://github.com/ppkantorski/QuickNTP) | Fork |
| sys-patch | [borntohonk/sys-patch](https://github.com/borntohonk/sys-patch) | |
| ovl-sysmodules | [ppkantorski/ovl-sysmodules](https://github.com/ppkantorski/ovl-sysmodules) | |
| FPSLocker | [ppkantorski/FPSLocker](https://github.com/ppkantorski/FPSLocker) | Fork |
| Memory-Kit | [ppkantorski/Memory-Kit](https://github.com/ppkantorski/Memory-Kit) | Mesosphere binary fetched separately from repo source tree |
| Alchemist | [ppkantorski/Alchemist](https://github.com/ppkantorski/Alchemist) | |
| Ultrahand-Overlay | [ppkantorski/Ultrahand-Overlay](https://github.com/ppkantorski/Ultrahand-Overlay) | Includes `ovlmenu.ovl` and `lang.zip`, fetched as separate assets from the same release |
| ReverseNX-RT | [ppkantorski/ReverseNX-RT](https://github.com/ppkantorski/ReverseNX-RT) | Requires SaltyNX(included) |
| DNS-MITM_Manager | [sthetix/DNS-MITM_Manager](https://github.com/sthetix/DNS-MITM_Manager) | |
| ldn_mitm | [spacemeowx2/ldn_mitm](https://github.com/spacemeowx2/ldn_mitm) | |
| Quick-Reboot | [eradicatinglove/Quick-Reboot](https://github.com/eradicatinglove/Quick-Reboot) | Ships both a `.nro` and a `.ovl`, fetched as separate assets |
| emuiibo | [XorTroll/emuiibo](https://github.com/XorTroll/emuiibo) | |
| Status-Monitor-Overlay | [ppkantorski/Status-Monitor-Overlay](https://github.com/ppkantorski/Status-Monitor-Overlay) | |
| sphaira | [ITotalJustice/sphaira](https://github.com/ITotalJustice/sphaira) | Homebrew menu replacement |

## Running it locally

```bash
chmod +x build_nx_pack.sh
./build_nx_pack.sh [OUTPUT_DIR]
```

Requires `curl`, `unzip`, `python3` — all standard on Ubuntu/Debian.

Environment variables:

| Variable | Purpose |
|---|---|
| `GITHUB_TOKEN` | Raises the GitHub API rate limit from 60 to 5000 requests/hour. Without it, a full run can exhaust the unauthenticated limit. |
| `OUTPUT_DIR` | Overrides the default output path (`./SD_Card_Output`). |
| `KEEP_DOWNLOADS` | Set to `1` to keep `_downloads/` between runs instead of clearing it. |

Output:

```
SD_Card_Output/
├── atmosphere/
├── bootloader/
├── switch/
├── config/
├── themes/
├── hekate.bin
├── payload.bin
├── exosphere.ini
├── CHANGELOG.md
└── CHANGELOG.txt
```

Copy the contents of `SD_Card_Output/` to the root of a FAT32/exFAT-formatted SD card.

## GitHub Actions

Two workflows live in `.github/workflows/`.

### `release.yml`

Runs the build, packages the output, and publishes a GitHub Release. Triggered by:

- pushing a tag matching `v*`
- `poll_upstreams.yml` dispatching it automatically (see below)
- manual dispatch from the Actions tab, with an optional tag override

It runs as two jobs — `build` then `release` — so a transient failure publishing the release (API hiccup, rate limit) can be retried without rerunning the entire build. The build job uploads the zip and the changelog excerpt as separate artifacts; the release job downloads both and creates the release. Job and step timeouts are set so a hung download can't block the pipeline indefinitely.

The release body always states what triggered the build and, when triggered by the poller, which components were updated and to what version.

### `poll_upstreams.yml`

Checks every tracked repository every 6 hours for a new release (or, for repos with no GitHub releases, a new commit on `master`). If anything changed, it commits the updated version baseline to a dedicated `upstream-state` branch and dispatches `release.yml`, passing along the list of what changed.

The baseline is a single JSON file on an orphan branch, never merged into `main`. Every update is a separate commit, so the history of "what changed and when" is visible directly in that branch's commit log. No external token or secret beyond the default `GITHUB_TOKEN` is required, but the repo's Action permissions need to be set to "Read and write" for it to commit and dispatch workflows.

## Caveats

- Repos are tracked by GitHub release tag (or commit SHA where there's no release). A repo retagging an existing release without publishing a new one won't be detected as changed.
- No signature or checksum verification is performed on downloaded assets beyond what GitHub's own release infrastructure provides. This script trusts that the repos listed above are what they claim to be.
- Component selection and exclusions reflect one person's personal preference, while this works for me, maybe it will not for you.
