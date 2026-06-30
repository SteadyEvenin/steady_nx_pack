#!/usr/bin/env bash
# =============================================================================
#  build_nx_pack.sh
#  Builds a clean, ready-to-copy Nintendo Switch CFW SD card layout.
#
#  Components fetched (always latest release):
#   • Atmosphère         • Hekate              • DBI
#   • disable_remap_dlg  • MissionControl       • SaltyNX
#   • theme-patches      • nx-ovlloader         • EdiZon-Overlay
#   • Horizon-OC         • QuickNTP (ppkant.)   • sys-patch
#   • ovl-sysmodules     • FPSLocker (ppkant.)  • Memory-Kit
#   • Alchemist          • Ultrahand-Overlay    • Ultrahand ovlmenu.ovl
#   • Ultrahand lang.zip • ReverseNX-RT         • DNS-MITM_Manager
#   • ldn_mitm           • Quick-Reboot (.nro + .ovl) • emuiibo
#   • Status-Monitor-Overlay • sphaira
#
#  Generated config files:
#   • exosphere.ini              (atmosphere/ — PRODINFO blanking)
#   • bootloader/hekate_ipl.ini  (Hekate boot menu — CFW EMUMMC entry)
#     └─ kernel= atmosphere/mesosphere_1.85MB_1.11.bin
#     └─ kip1=   atmosphere/kips/hoc.kip  (shipped by Horizon-OC; see note below)
#
#  ⚠  HOC-Toolkit (ppkantorski/HOC-Toolkit) is intentionally NOT included.
#     hoc.kip referenced in hekate_ipl.ini is the Horizon-OC kernel patch
#     shipped directly by Horizon-OC/Horizon-OC — not HOC-Toolkit.
#     HOC-Toolkit (a switch/.packages Ultrahand addon) is excluded by design.
#
#  Repo assets copied:
#   • bootloader/res/emummc.bmp             (from assets/ in this repo)
#   • atmosphere/mesosphere_1.85MB_1.11.bin (from ppkantorski/Memory-Kit repo tree)
#
#  Requirements (all standard on Ubuntu/Debian):
#    curl  unzip  python3
#
#  Usage:
#    chmod +x build_nx_pack.sh
#    ./build_nx_pack.sh [OUTPUT_DIR]
#
#  Optional env vars:
#    GITHUB_TOKEN   – raises GH API rate-limit from 60 to 5000 req/hr
#    OUTPUT_DIR     – override default output path (./SD_Card_Output)
#    KEEP_DOWNLOADS – set to 1 to keep the _downloads/ cache between runs
# =============================================================================

set -euo pipefail

# ── FIX: Ensure wildcards (*) match hidden files/folders (e.g., .overlays) ──
shopt -s dotglob

# ── Colour helpers ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }
section() { echo -e "\n${BOLD}${CYAN}── $* ──────────────────────────────────────────${NC}"; }

# ── Dependency check ───────────────────────────────────────────────────────────
for cmd in curl unzip python3; do
    command -v "$cmd" &>/dev/null || die "Required tool not found: $cmd"
done

# ── Paths ──────────────────────────────────────────────────────────────────────
OUTPUT_DIR="${1:-${OUTPUT_DIR:-$(pwd)/SD_Card_Output}}"
DL_DIR="$(pwd)/_downloads"
LOG_FILE="$(pwd)/build_nx_pack.log"
FAILED=()
DONE=0

mkdir -p "$OUTPUT_DIR" "$DL_DIR"
: > "$LOG_FILE"

# ── Changelog tracking ─────────────────────────────────────────────────────────
CHANGELOG_ENTRIES=()
BUILD_DATE=$(date -u '+%Y-%m-%d %H:%M UTC')

# ── GitHub helpers ─────────────────────────────────────────────────────────────
GH_HEADERS=(-H "User-Agent: build_nx_pack/1.0" -H "Accept: text/html")
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    GH_HEADERS+=(-H "Authorization: Bearer $GITHUB_TOKEN")
    info "GitHub token set – using authenticated requests."
else
    warn "No GITHUB_TOKEN set. Limited to 60 API requests/hour."
fi

# Returns the latest release tag for owner/repo
get_latest_tag() {
    local repo="$1"
    local location
    location=$(curl -sI "${GH_HEADERS[@]}" \
                    "https://github.com/$repo/releases/latest" \
               | grep -i '^location:' | sed 's|.*/tag/||' | tr -d '\r\n' || true)
    echo "$location"
}

# Returns all asset download URLs for a given release tag
get_release_assets() {
    local repo="$1" tag="$2"
    local tag_enc="${tag//+/%2B}"
    curl -s "${GH_HEADERS[@]}" \
         "https://github.com/$repo/releases/expanded_assets/$tag_enc" \
    | python3 -c "
import sys, re
c = sys.stdin.read()
links = re.findall(r'href=\"(/[^\"]+/releases/download/[^\"]+)\"', c)
for l in links:
    print('https://github.com' + l)
"
}

# Downloads a file (skips if already cached)
download_file() {
    local url="$1" dest="$2"
    if [[ -f "$dest" ]] && [[ $(wc -c < "$dest") -gt 512 ]]; then
        info "   Cached: $(basename "$dest")"
        return 0
    fi
    info "   Downloading: $(basename "$dest")"
    local tag_safe_url="${url//+/%2B}"
    if ! curl -sL --max-time 120 --retry 3 \
              -H "User-Agent: build_nx_pack/1.0" \
              "$tag_safe_url" -o "$dest"; then
        warn "   Download failed: $url"
        return 1
    fi
    local size
    size=$(wc -c < "$dest")
    if (( size < 512 )); then
        warn "   Suspiciously small ($size bytes) – may be an error page"
        cat "$dest" >> "$LOG_FILE"
        return 1
    fi
    ok "   $(basename "$dest") ($size bytes)"
}

# ── Main processing function ────────────────────────────────────────────────────
process() {
    local label="$1" repo="$2" pattern="$3" action="$4"
    shift 4
    local extra_args=("$@")

    echo -e "\n${BOLD}▸ $label${NC}  (github.com/$repo)"

    local url="" filename="" version=""

    if [[ "$pattern" == SOURCE:* ]]; then
        local branch="${pattern#SOURCE:}"
        url="https://codeload.github.com/$repo/zip/refs/heads/$branch"
        filename="${repo//\//_}_${branch}.zip"
        version="latest (${branch} branch)"
    else
        local tag
        tag=$(get_latest_tag "$repo")
        if [[ -z "$tag" ]]; then
            warn "   Could not resolve latest tag for $repo"
            FAILED+=("$label")
            CHANGELOG_ENTRIES+=("$label|$repo|unknown|n/a|FAILED – could not resolve tag")
            return
        fi
        version="$tag"
        info "   Tag: $tag"

        local assets
        assets=$(get_release_assets "$repo" "$tag")
        
        url=$(echo "$assets" | grep -i "$pattern" | head -1 || true)
        if [[ -z "$url" ]]; then
            warn "   No asset matching '$pattern' found in release $tag"
            echo "   Available:" ; echo "$assets" | sed 's/^/    /'
            FAILED+=("$label")
            CHANGELOG_ENTRIES+=("$label|$repo|$tag|n/a|FAILED – asset not matched")
            return
        fi
        filename="$(basename "$url")"
        filename="${filename//%2B/+}"
    fi

    # ── Allow caller to force a unique cache filename to avoid collisions ──────
    # Pass PROCESS_FILENAME_OVERRIDE=name before calling process() to rename the
    # downloaded file in _downloads/.  Cleared automatically after each call.
    if [[ -n "${PROCESS_FILENAME_OVERRIDE:-}" ]]; then
        filename="$PROCESS_FILENAME_OVERRIDE"
        PROCESS_FILENAME_OVERRIDE=""
    fi

    local dest="$DL_DIR/$filename"
    if ! download_file "$url" "$dest"; then
        FAILED+=("$label")
        CHANGELOG_ENTRIES+=("$label|$repo|$version|$filename|FAILED – download error")
        return
    fi

    case "$action" in
        unzip_root)
            info "   Extracting → SD root"
            unzip -oq "$dest" -d "$OUTPUT_DIR" 2>>"$LOG_FILE"
            ;;

        unzip_to)
            local target_path="${extra_args[0]}"
            mkdir -p "$OUTPUT_DIR/$target_path"
            info "   Extracting → $target_path/"
            unzip -oq "$dest" -d "$OUTPUT_DIR/$target_path" 2>>"$LOG_FILE"
            ;;

        copy_to)
            local target_path="${extra_args[0]}"
            local target_name="${extra_args[1]:-$(basename "$dest")}"
            mkdir -p "$OUTPUT_DIR/$target_path"
            info "   Copying → $target_path/$target_name"
            cp "$dest" "$OUTPUT_DIR/$target_path/$target_name"
            ;;

        zip_subfolder)
            local sub_path="${extra_args[0]}"
            local dest_path="${extra_args[1]}"
            mkdir -p "$OUTPUT_DIR/$dest_path"
            info "   Extracting subfolder '$sub_path' → $dest_path/"
            local entries
            entries=$(unzip -Z1 "$dest" 2>/dev/null | grep "^$sub_path" || true)
            while IFS= read -r entry; do
                local rel="${entry#"$sub_path/"}"
                [[ -z "$rel" ]] && continue
                unzip -oqj "$dest" "$entry" -d "$OUTPUT_DIR/$dest_path" 2>>"$LOG_FILE"
            done <<< "$entries"
            ;;

        *)
            warn "   Unknown action: $action"
            FAILED+=("$label")
            CHANGELOG_ENTRIES+=("$label|$repo|$version|$filename|FAILED – unknown action")
            return
            ;;
    esac

    ok "   Done."
    CHANGELOG_ENTRIES+=("$label|$repo|$version|$filename|OK")
    (( DONE++ )) || true
}

# =============================================================================
#  COMPONENT DOWNLOAD & PLACEMENT STEPS
# =============================================================================
section "Downloading & extracting components"

# 1. Atmosphère
process "Atmosphère" "atmosphere-nx/atmosphere" "atmosphere-" "unzip_root"

# 2. Hekate
process "Hekate" "ctcaer/hekate" "hekate_ctcaer.*_Nyx_" "unzip_root"

{
    tag=$(get_latest_tag "ctcaer/hekate")
    if [[ -n "$tag" ]]; then
        assets=$(get_release_assets "ctcaer/hekate" "$tag")
        bin_url=$(echo "$assets" | grep -v "ram8GB" | grep '\.bin$' | head -1 || true)
        if [[ -n "$bin_url" ]]; then
            bin_file="$DL_DIR/$(basename "$bin_url")"
            download_file "$bin_url" "$bin_file"
            mkdir -p "$OUTPUT_DIR/bootloader/payloads" "$OUTPUT_DIR/atmosphere"
            cp "$bin_file" "$OUTPUT_DIR/hekate.bin"
            cp "$bin_file" "$OUTPUT_DIR/payload.bin"
            cp "$bin_file" "$OUTPUT_DIR/atmosphere/reboot_to_payload.bin"
            cp "$bin_file" "$OUTPUT_DIR/bootloader/payloads/hekate.bin"
            info "   Hekate payload → mapped to root (hekate.bin, payload.bin), atmosphere, and payloads folder."
        fi
    fi
} 2>>"$LOG_FILE" || warn "Could not place Hekate .bin payload"

# 3. DBI
process "DBI" "rashevskyv/dbi" "DBI.nro" "copy_to" "switch/DBI"

{
    tag=$(get_latest_tag "rashevskyv/dbi")
    if [[ -n "$tag" ]]; then
        assets=$(get_release_assets "rashevskyv/dbi" "$tag")
        cfg_url=$(echo "$assets" | grep -i "dbi.config" | head -1 || true)
        if [[ -n "$cfg_url" ]]; then
            cfg_file="$DL_DIR/dbi.config"
            download_file "$cfg_url" "$cfg_file"
            mkdir -p "$OUTPUT_DIR/switch/DBI"
            cp "$cfg_file" "$OUTPUT_DIR/switch/DBI/dbi.config"
            info "   dbi.config → switch/DBI/dbi.config"
        fi
    fi
} 2>>"$LOG_FILE" || warn "Could not place dbi.config"

# 4. disable_remap_dialog
process "disable_remap_dialog" "ndeadly/disable_remap_dialog" "disable_remap_dialog.zip" "unzip_root"

# 5. MissionControl
process "MissionControl" "ndeadly/MissionControl" "MissionControl-" "unzip_root"

# 6. SaltyNX
process "SaltyNX" "masagrator/SaltyNX" "SaltyNX\.zip" "unzip_root"

# 7. theme-patches
process "theme-patches" "exelix11/theme-patches" "SOURCE:master" "zip_subfolder" "theme-patches-master/systemPatches" "themes/systemPatches"

# 8. nx-ovlloader
# Using ppkantorski's fork (v2.x), not the original WerWolv/nx-ovlloader (last: v1.0.7, unmaintained).
# ppkantorski's fork is the active upstream for the Ultrahand ecosystem: dynamic heap sizing,
# HOS-version-aware defaults, live heap change detection, and nx-ovlreloader support.
# emuiibo's README references WerWolv's original because it predates this fork becoming standard.
# Both ship nx-ovlloader.zip with the same atmosphere/contents/420000000007E51A/ layout.
process "nx-ovlloader" "ppkantorski/nx-ovlloader" "nx-ovlloader.zip" "unzip_root"

# 9. EdiZon-Overlay
process "EdiZon-Overlay" "proferabg/EdiZon-Overlay" "ovlEdiZon.ovl" "copy_to" "switch/.overlays"

# 10. Horizon-OC
process "Horizon-OC" "Horizon-OC/Horizon-OC" "dist\.zip" "unzip_root"

# 11. QuickNTP (ppkantorski fork)
# Replaces nedex/QuickNTP (which shipped sdout.zip requiring a filename override to avoid
# collision with Ultrahand's sdout.zip).  ppkantorski's fork is a libultrahand rebuild
# shipping a standalone QuickNTP.ovl — cleaner, no collision risk, actively maintained.
process "QuickNTP" "ppkantorski/QuickNTP" "QuickNTP.ovl" "copy_to" "switch/.overlays"

# 12. sys-patch
process "sys-patch" "borntohonk/sys-patch" "sys-patch-" "unzip_root"

# 13. ovl-sysmodules (ppkantorski)
process "ovl-sysmodules" "ppkantorski/ovl-sysmodules" "ovlSysmodules.ovl" "copy_to" "switch/.overlays"

# 14. FPSLocker (ppkantorski fork)
process "FPSLocker (ppkantorski)" "ppkantorski/FPSLocker" "FPSLocker.ovl" "copy_to" "switch/.overlays"

# 15. Memory-Kit
# Memory.Kit.zip extracts the Ultrahand package to switch/.packages/Memory Kit/.
# The mesosphere kernel binaries live only in the repo tree (not in the release zip)
# and must be fetched from raw.githubusercontent.com.  mesosphere_1.85MB_1.11.bin
# is placed at atmosphere/ so Hekate can find it via the kernel= entry in hekate_ipl.ini.
process "Memory-Kit" "ppkantorski/Memory-Kit" "Memory.Kit.zip" "unzip_root"

echo -e "\n${BOLD}▸ Memory-Kit mesosphere kernel${NC}  (repo tree → atmosphere/)"
_MESO_URL="https://raw.githubusercontent.com/ppkantorski/Memory-Kit/main/Memory%20Kit/data/mesosphere_1.85MB_1.11.bin"
_MESO_DEST="$DL_DIR/mesosphere_1.85MB_1.11.bin"
mkdir -p "$OUTPUT_DIR/atmosphere"
if download_file "$_MESO_URL" "$_MESO_DEST" 2>>"$LOG_FILE"; then
    cp "$_MESO_DEST" "$OUTPUT_DIR/atmosphere/mesosphere_1.85MB_1.11.bin"
    ok "   mesosphere_1.85MB_1.11.bin → atmosphere/"
    CHANGELOG_ENTRIES+=("Memory-Kit mesosphere|ppkantorski/Memory-Kit|main|mesosphere_1.85MB_1.11.bin|OK")
    (( DONE++ )) || true
else
    warn "   Failed to download mesosphere_1.85MB_1.11.bin — hekate_ipl.ini kernel= entry will be broken."
    FAILED+=("Memory-Kit mesosphere")
    CHANGELOG_ENTRIES+=("Memory-Kit mesosphere|ppkantorski/Memory-Kit|main|mesosphere_1.85MB_1.11.bin|FAILED – download error")
fi

# 16. Alchemist
process "Alchemist" "ppkantorski/Alchemist" "Alchemist.zip" "unzip_root"

# 17. Ultrahand-Overlay
# sdout.zip previously collided with nedex/QuickNTP's sdout.zip, requiring a filename
# override.  QuickNTP is now ppkantorski/QuickNTP (step 11) which ships a standalone
# .ovl — no collision risk remains.  PROCESS_FILENAME_OVERRIDE kept for safety in case
# another repo ever ships sdout.zip in future.
PROCESS_FILENAME_OVERRIDE="ultrahand_sdout.zip"
process "Ultrahand-Overlay" "ppkantorski/Ultrahand-Overlay" "sdout.zip" "unzip_root"

# ── Ultrahand companion assets: ovlmenu.ovl + lang.zip ───────────────────────
# These are separate release assets alongside sdout.zip.  They run in the main
# shell (not a subshell) so CHANGELOG_ENTRIES is updated correctly.
echo -e "\n${BOLD}▸ Ultrahand-Overlay companion assets${NC}  (ovlmenu.ovl + lang.zip)"

_uh_tag=$(get_latest_tag "ppkantorski/Ultrahand-Overlay" 2>>"$LOG_FILE" || true)

if [[ -z "$_uh_tag" ]]; then
    warn "   Could not resolve Ultrahand tag for companion assets."
    FAILED+=("Ultrahand ovlmenu.ovl")
    CHANGELOG_ENTRIES+=("Ultrahand ovlmenu.ovl|ppkantorski/Ultrahand-Overlay|unknown|n/a|FAILED – could not resolve tag")
else
    _uh_assets=$(get_release_assets "ppkantorski/Ultrahand-Overlay" "$_uh_tag" 2>>"$LOG_FILE" || true)

    # ovlmenu.ovl — the overlay menu binary; lands at switch/.overlays/ovlmenu.ovl
    _ovl_url=$(echo "$_uh_assets" | grep "ovlmenu\.ovl" | head -1 || true)
    if [[ -n "$_ovl_url" ]]; then
        if download_file "$_ovl_url" "$DL_DIR/ovlmenu.ovl" 2>>"$LOG_FILE"; then
            mkdir -p "$OUTPUT_DIR/switch/.overlays"
            cp "$DL_DIR/ovlmenu.ovl" "$OUTPUT_DIR/switch/.overlays/ovlmenu.ovl"
            ok "   ovlmenu.ovl → switch/.overlays/ovlmenu.ovl"
            CHANGELOG_ENTRIES+=("Ultrahand ovlmenu.ovl|ppkantorski/Ultrahand-Overlay|$_uh_tag|ovlmenu.ovl|OK")
            (( DONE++ )) || true
        else
            warn "   Failed to download ovlmenu.ovl"
            FAILED+=("Ultrahand ovlmenu.ovl")
            CHANGELOG_ENTRIES+=("Ultrahand ovlmenu.ovl|ppkantorski/Ultrahand-Overlay|$_uh_tag|ovlmenu.ovl|FAILED – download error")
        fi
    else
        warn "   ovlmenu.ovl not found in release assets for $_uh_tag"
        FAILED+=("Ultrahand ovlmenu.ovl")
        CHANGELOG_ENTRIES+=("Ultrahand ovlmenu.ovl|ppkantorski/Ultrahand-Overlay|$_uh_tag|n/a|FAILED – asset not matched")
    fi

    # lang.zip — UI language files; optional, non-fatal if absent
    _lang_url=$(echo "$_uh_assets" | grep "lang\.zip" | head -1 || true)
    if [[ -n "$_lang_url" ]]; then
        if download_file "$_lang_url" "$DL_DIR/ultrahand_lang.zip" 2>>"$LOG_FILE"; then
            mkdir -p "$OUTPUT_DIR/config/ultrahand/lang"
            unzip -oq "$DL_DIR/ultrahand_lang.zip" \
                  -d "$OUTPUT_DIR/config/ultrahand/lang" 2>>"$LOG_FILE"
            ok "   lang.zip → config/ultrahand/lang/"
            CHANGELOG_ENTRIES+=("Ultrahand lang.zip|ppkantorski/Ultrahand-Overlay|$_uh_tag|lang.zip|OK")
            (( DONE++ )) || true
        else
            warn "   Failed to download lang.zip (non-fatal)"
            CHANGELOG_ENTRIES+=("Ultrahand lang.zip|ppkantorski/Ultrahand-Overlay|$_uh_tag|lang.zip|FAILED – download error")
        fi
    else
        info "   lang.zip not present in this release — skipping."
    fi
fi

# 18. ReverseNX-RT (ppkantorski fork of masagrator/ReverseNX-RT)
# Real-time handheld/docked mode switcher overlay.  Requires SaltyNX (step 6).
# Asset is named ReverseNX-RT-ovl.ovl — renamed to ReverseNX-RT.ovl on copy
# to match the conventional .ovl naming used by all other overlays in this pack.
process "ReverseNX-RT" "ppkantorski/ReverseNX-RT" "ReverseNX-RT-ovl\.ovl" "copy_to" "switch/.overlays" "ReverseNX-RT.ovl"

# 19. DNS-MITM_Manager
# Tesla/Ultrahand overlay for managing Atmosphere's DNS MITM hosts file entries
# without rebooting.  Zip ships the switch/.overlays/ path internally → unzip_root.
process "DNS-MITM_Manager" "sthetix/DNS-MITM_Manager" "DNS-MITM_Manager.zip" "unzip_root"

# 20. ldn_mitm
# LAN-play sysmodule: replaces the system ldn service with UDP LAN emulation.
# Zip ships full SD layout per its Makefile:
#   atmosphere/contents/4200000000000010/  (exefs.nsp + toolbox.json + flags/boot2.flag)
#   switch/ldnmitm_config/ldnmitm_config.nro
#   switch/.overlays/ldnmitm_config.ovl
process "ldn_mitm" "spacemeowx2/ldn_mitm" "ldn_mitm_" "unzip_root"

# 21 & 22. Quick-Reboot (.nro hbmenu app + .ovl Ultrahand overlay)
# Two separate assets from the same release — fetched with two process() calls.
# .nro → switch/ (standard hbmenu app location)
# .ovl → switch/.overlays/ (Tesla/Ultrahand overlay)
process "Quick-Reboot (app)" "eradicatinglove/Quick-Reboot" "Quick-Reboot\.nro" "copy_to" "switch"
process "Quick-Reboot (overlay)" "eradicatinglove/Quick-Reboot" "Quick-Reboot\.ovl" "copy_to" "switch/.overlays"

# 23. emuiibo
# emuiibo.zip is a root-extract archive.  It places:
#   atmosphere/contents/0100000000000352/exefs.nsp  — sysmodule binary
#   atmosphere/contents/0100000000000352/flags/      — boot2.flag (auto-start)
#   switch/.overlays/emuiibo.ovl                    — Tesla/Ultrahand overlay
#   emuiibo/overlay/lang/                           — overlay UI translations
# This matches the layout specified in the emuiibo README exactly.
# ovlmenu.ovl (Tesla-Menu equivalent) is already provided by Ultrahand-Overlay (step 18).
# nx-ovlloader is already provided by step 8 — no duplication needed.
process "emuiibo" "XorTroll/emuiibo" "emuiibo.zip" "unzip_root"

# 24. Status-Monitor-Overlay
process "Status-Monitor-Overlay" "ppkantorski/Status-Monitor-Overlay" "Status-Monitor-Overlay.ovl" "copy_to" "switch/.overlays"

# 25. sphaira
# Homebrew menu replacement.  sphaira.zip extracts to switch/sphaira/sphaira.nro
# (its own subfolder, consistent with hbmenu conventions).
# Features: app installer (NSP/XCI/NSZ), FTP/MTP server, file browser,
# theme support, appstore integration.
process "sphaira" "ITotalJustice/sphaira" "sphaira.zip" "unzip_root"

# =============================================================================
#  GENERATE CONFIGURATION FILES
# =============================================================================
section "Generating system configurations"

info "Writing exosphere.ini template to root..."
cat << 'EOF' > "$OUTPUT_DIR/exosphere.ini"
[exosphere]
debugmode=1
debugmode_user=0
disable_user_exception_handlers=0
enable_user_pmu_access=0
enable_mem_mode=0
blank_prodinfo_sysmmc=1
blank_prodinfo_emummc=1
allow_writing_to_cal_sysmmc=0
log_port=0
log_baud_rate=115200
log_inverted=0
EOF
ok "exosphere.ini written with PRODINFO blanking active."

# ── hekate_ipl.ini ──────────────────────────────────────────────────────────
info "Writing bootloader/hekate_ipl.ini..."
mkdir -p "$OUTPUT_DIR/bootloader"
cat << 'EOF' > "$OUTPUT_DIR/bootloader/hekate_ipl.ini"
[config]
autoboot=0
autoboot_list=0
bootwait=0
backlight=108
noticker=0
autohosoff=2
autonogc=1
updater2p=1
bootprotect=0

[CFW (EMUMMC)]
kip1patch=nosigchk
pkg3=atmosphere/package3
kernel=atmosphere/mesosphere_1.85MB_1.11.bin
; hoc.kip is the Horizon-OC kernel patch shipped by Horizon-OC/Horizon-OC.
; HOC-Toolkit (ppkantorski) is a separate Ultrahand package and is NOT included in this pack.
kip1=atmosphere/kips/hoc.kip
secmon=atmosphere/exosphere.bin
emummcforce=1
icon=bootloader/res/emummc.bmp
EOF
ok "bootloader/hekate_ipl.ini written."

# ── bootloader/res/emummc.bmp ───────────────────────────────────────────────
# Downloaded from this repository's own assets/ folder (not a third-party release).
# GITHUB_REPOSITORY is set automatically in GitHub Actions; fall back to the
# known repo slug when running locally.
info "Fetching emummc.bmp from repo assets..."
_REPO_SLUG="${GITHUB_REPOSITORY:-SteadyEvenin/steady_nx_pack}"
_BMP_URL="https://raw.githubusercontent.com/${_REPO_SLUG}/main/assets/emummc.bmp"
mkdir -p "$OUTPUT_DIR/bootloader/res"
if curl -sL --max-time 30 --retry 3 \
        -H "User-Agent: build_nx_pack/1.0" \
        ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
        "$_BMP_URL" -o "$OUTPUT_DIR/bootloader/res/emummc.bmp" \
   && [[ $(wc -c < "$OUTPUT_DIR/bootloader/res/emummc.bmp") -gt 512 ]]; then
    ok "bootloader/res/emummc.bmp placed."
else
    warn "Could not download emummc.bmp from $_BMP_URL — placeholder omitted."
    rm -f "$OUTPUT_DIR/bootloader/res/emummc.bmp"
fi

# =============================================================================
#  POST-BUILD: ensure essential directories exist
# =============================================================================
section "Finalising directory structure"

# ── FIXED: Automated post-build consolidation of nested 'SdOut' directories ───
for target_sdout in "$OUTPUT_DIR/SdOut" "$OUTPUT_DIR/sdout"; do
    if [[ -d "$target_sdout" ]]; then
        info "Merging nested $(basename "$target_sdout") contents into standard SD layout..."
        # Due to 'shopt -s dotglob' initialized above, this catches all hidden dotfiles flawlessly
        find "$target_sdout" -mindepth 1 -maxdepth 1 -exec cp -r {} "$OUTPUT_DIR/" \; 2>>"$LOG_FILE"
        rm -rf "$target_sdout"
        ok "Redundant $(basename "$target_sdout") folder successfully consolidated."
    fi
done

declare -a ENSURE_DIRS=(
    "atmosphere/contents"
    "atmosphere/exefs_patches"
    "atmosphere/kips"
    "bootloader/payloads"
    "bootloader/res"
    "config"
    "switch"
    "switch/.overlays"
    "switch/.packages"
    "themes/systemPatches"
)
for d in "${ENSURE_DIRS[@]}"; do
    mkdir -p "$OUTPUT_DIR/$d"
done
ok "Directory tree verified."

# =============================================================================
#  CHANGELOG OUTPUT
# =============================================================================
section "Writing changelog"

CHANGELOG_MD="$OUTPUT_DIR/CHANGELOG.md"
CHANGELOG_TXT="$OUTPUT_DIR/CHANGELOG.txt"

pad() { printf "%-${2}s" "$1"; }

W_LABEL=28; W_VERSION=20; W_ASSET=52; W_STATUS=8
TXT_SEP="+$(printf '%0.s-' $(seq 1 $((W_LABEL+2))))+$(printf '%0.s-' $(seq 1 $((W_VERSION+2))))+$(printf '%0.s-' $(seq 1 $((W_ASSET+2))))+$(printf '%0.s-' $(seq 1 $((W_STATUS+2))))+"

{
cat << MDHEAD
# CFW Pack Changelog

**Built:** ${BUILD_DATE}
**Components:** ${DONE} succeeded / ${#FAILED[@]} failed

---

## Components

| Component | Version | Asset | Repository | Status |
|-----------|---------|-------|------------|--------|
MDHEAD

for entry in "${CHANGELOG_ENTRIES[@]}"; do
    IFS='|' read -r lbl repo ver asset status <<< "$entry"
    gh_url="https://github.com/$repo"
    if [[ "$status" == "OK" ]]; then
        status_md="✅ OK"
    else
        status_md="❌ ${status#FAILED – }"
    fi
    echo "| **$lbl** | \`$ver\` | \`$asset\` | [$repo]($gh_url) | $status_md |"
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo ""
    echo "---"
    echo ""
    echo "## Failed Components"
    echo ""
    for entry in "${CHANGELOG_ENTRIES[@]}"; do
        IFS='|' read -r lbl repo ver asset status <<< "$entry"
        if [[ "$status" != "OK" ]]; then
            echo "- **$lbl** — ${status#FAILED – }"
        fi
    done
fi

cat << MDFOOTER

---

## SD Card Layout

\`\`\`
MDFOOTER

find "$OUTPUT_DIR" -maxdepth 4 -not -name "CHANGELOG*" | sort \
    | sed "s|$OUTPUT_DIR/||" | sed '/^$/d' \
    | python3 -c "
import sys
lines = [l.rstrip() for l in sys.stdin if l.strip()]
for line in lines:
    parts = line.split('/')
    depth = len(parts) - 1
    name  = parts[-1]
    prefix = '    ' * depth
    connector = '└── ' if depth > 0 else ''
    print(prefix + connector + name)
"

echo '```'
} > "$CHANGELOG_MD"

ok "   CHANGELOG.md written."

{
echo "CFW Pack Changelog"
echo "=================="
echo "Built   : ${BUILD_DATE}"
echo "Success : ${DONE} component(s)"
echo "Failed  : ${#FAILED[@]} component(s)"
echo ""
echo "$TXT_SEP"
printf "| %s | %s | %s | %s |\n" \
    "$(pad "Component"  $W_LABEL)" \
    "$(pad "Version"    $W_VERSION)" \
    "$(pad "Asset"      $W_ASSET)" \
    "$(pad "Status"     $W_STATUS)"
echo "$TXT_SEP"

for entry in "${CHANGELOG_ENTRIES[@]}"; do
    IFS='|' read -r lbl repo ver asset status <<< "$entry"
    if [[ "$status" == "OK" ]]; then
        status_short="OK"
    else
        status_short="FAILED"
    fi
    [[ ${#lbl}   -gt $W_LABEL   ]] && lbl="${lbl:0:$((W_LABEL-1))}…"
    [[ ${#ver}   -gt $W_VERSION ]] && ver="${ver:0:$((W_VERSION-1))}…"
    [[ ${#asset} -gt $W_ASSET   ]] && asset="${asset:0:$((W_ASSET-1))}…"
    printf "| %s | %s | %s | %s |\n" \
        "$(pad "$lbl"         $W_LABEL)" \
        "$(pad "$ver"         $W_VERSION)" \
        "$(pad "$asset"       $W_ASSET)" \
        "$(pad "$status_short" $W_STATUS)"
done

echo "$TXT_SEP"

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo ""
    echo "Failed components:"
    for entry in "${CHANGELOG_ENTRIES[@]}"; do
        IFS='|' read -r lbl repo ver asset status <<< "$entry"
        [[ "$status" != "OK" ]] && echo "  - $lbl : ${status#FAILED – }"
    done
fi
} > "$CHANGELOG_TXT"

ok "   CHANGELOG.txt written."
section "Summary"
echo -e "   ${BOLD}Output:${NC}    $OUTPUT_DIR"
echo -e "   ${GREEN}Succeeded:${NC} $DONE component(s)"

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo -e "   ${RED}Failed:${NC}    ${#FAILED[@]} component(s):"
    for f in "${FAILED[@]}"; do
        echo -e "    ${RED}•${NC} $f"
    done
    echo -e "   See $LOG_FILE for details."
else
    echo -e "   ${GREEN}All components processed successfully.${NC}"
fi

echo
echo -e "${BOLD}Final SD card layout:${NC}"
find "$OUTPUT_DIR" -maxdepth 3 -type d | sort | sed "s|$OUTPUT_DIR|  SD:|"

echo
echo -e "${BOLD}Changelog files:${NC}"
echo "  $CHANGELOG_MD"
echo "  $CHANGELOG_TXT"

echo
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Copy everything inside $OUTPUT_DIR/ to the root of your FAT32/exFAT SD card."
echo "  2. Boot via Hekate payload — bootloader/hekate_ipl.ini is already configured."
echo "  3. Select 'CFW (EMUMMC)' from the Hekate boot menu."

if [[ "${KEEP_DOWNLOADS:-0}" != "1" ]]; then
    rm -rf "$DL_DIR"
    info "Download cache cleaned. Set KEEP_DOWNLOADS=1 to preserve it."
fi
