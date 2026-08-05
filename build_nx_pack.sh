#!/usr/bin/env bash
# =============================================================================
#  build_nx_pack.sh
#  Builds a clean, ready-to-copy Nintendo Switch CFW SD card layout.
#
#  Components fetched (always latest release):
#   • Atmosphère         • Hekate              • DBI
#   • disable_remap_dlg  • MissionControl       • SaltyNX
#   • theme-patches      • nx-ovlloader         • EdiZon-Overlay
#   • Horizon-OC         • QuickNTP (ppkant.)   • sys-patch (impeeza)
#   • ovl-sysmodules     • FPSLocker (ppkant.)  • Memory-Kit
#   • Alchemist          • Ultrahand-Overlay    • Ultrahand ovlmenu.ovl
#   • Ultrahand lang.zip • ReverseNX-RT         • DNS-MITM_Manager
#   • ldn_mitm           • Quick-Reboot (.nro + .ovl) • emuiibo
#   • Status-Monitor-Overlay • sphaira          • Lockpick_RCMaster
#
#  Generated config files:
#   • exosphere.ini              (atmosphere/ — PRODINFO blanking)
#   • bootloader/hekate_ipl.ini  (Hekate boot menu — CFW EMUMMC entry)
#     └─ kernel= atmosphere/mesosphere_1.85MB_1.11.bin
#     └─ kip1=   atmosphere/kips/hoc.kip  (shipped by Horizon-OC; see note below)
#
#  ⚠  HOC-Toolkit (ppkantorski) is intentionally NOT included.
#     hoc.kip is the Horizon-OC kernel patch shipped by Horizon-OC/Horizon-OC.
#
#  Repo assets copied:
#   • bootloader/res/emummc.bmp             (from assets/ in this repo)
#   • atmosphere/mesosphere_1.85MB_1.11.bin (from ppkantorski/Memory-Kit repo tree)
#
#  Requirements (all standard on ubuntu-latest):
#    curl  unzip  python3
#
#  Env vars:
#    GITHUB_TOKEN   – raises GH API rate-limit from 60 to 5000 req/hr (set automatically in Actions)
#    OUTPUT_DIR     – override default output path (./SD_Card_Output)
#    KEEP_DOWNLOADS – set to 1 to keep the _downloads/ cache between runs
# =============================================================================

set -euo pipefail
shopt -s dotglob

# ── Logging — GitHub Actions workflow commands ─────────────────────────────────
info()  { echo "::notice::$*"; }
warn()  { echo "::warning::$*"; }
die()   { echo "::error::$*" >&2; exit 1; }
log()   { echo "$*"; }

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
    info "GitHub token set — using authenticated requests."
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
        log "  cached: $(basename "$dest")"
        return 0
    fi
    log "  downloading: $(basename "$dest")"
    local tag_safe_url="${url//+/%2B}"
    if ! curl -sL --max-time 120 --retry 3 \
              -H "User-Agent: build_nx_pack/1.0" \
              "$tag_safe_url" -o "$dest"; then
        warn "Download failed: $url"
        return 1
    fi
    local size
    size=$(wc -c < "$dest")
    if (( size < 512 )); then
        warn "Suspiciously small file ($size bytes) — may be an error page: $url"
        cat "$dest" >> "$LOG_FILE"
        return 1
    fi
    log "  $(basename "$dest") (${size} bytes)"
}

# ── Main processing function ────────────────────────────────────────────────────
process() {
    local label="$1" repo="$2" pattern="$3" action="$4"
    shift 4
    local extra_args=("$@")

    log ""
    log "[ $label ] github.com/$repo"

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
            warn "$label: could not resolve latest tag for $repo"
            FAILED+=("$label")
            CHANGELOG_ENTRIES+=("$label|$repo|unknown|n/a|FAILED – could not resolve tag")
            return
        fi
        version="$tag"
        log "  tag: $tag"

        local assets
        assets=$(get_release_assets "$repo" "$tag")

        url=$(echo "$assets" | grep -i "$pattern" | head -1 || true)
        if [[ -z "$url" ]]; then
            warn "$label: no asset matching '$pattern' in release $tag"
            echo "$assets" | sed 's/^/  available: /' >> "$LOG_FILE"
            FAILED+=("$label")
            CHANGELOG_ENTRIES+=("$label|$repo|$tag|n/a|FAILED – asset not matched")
            return
        fi
        filename="$(basename "$url")"
        filename="${filename//%2B/+}"
    fi

    # Allow caller to force a unique cache filename to avoid collisions between
    # repos that ship assets with the same name (e.g. sdout.zip).
    # Set PROCESS_FILENAME_OVERRIDE before calling process(); cleared automatically.
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
            log "  extracting to SD root"
            unzip -oq "$dest" -d "$OUTPUT_DIR" 2>>"$LOG_FILE"
            ;;
        unzip_to)
            local target_path="${extra_args[0]}"
            mkdir -p "$OUTPUT_DIR/$target_path"
            log "  extracting to $target_path/"
            unzip -oq "$dest" -d "$OUTPUT_DIR/$target_path" 2>>"$LOG_FILE"
            ;;
        copy_to)
            local target_path="${extra_args[0]}"
            local target_name="${extra_args[1]:-$(basename "$dest")}"
            mkdir -p "$OUTPUT_DIR/$target_path"
            log "  copying to $target_path/$target_name"
            cp "$dest" "$OUTPUT_DIR/$target_path/$target_name"
            ;;
        zip_subfolder)
            local sub_path="${extra_args[0]}"
            local dest_path="${extra_args[1]}"
            mkdir -p "$OUTPUT_DIR/$dest_path"
            log "  extracting subfolder '$sub_path' to $dest_path/"
            local entries
            entries=$(unzip -Z1 "$dest" 2>/dev/null | grep "^$sub_path" || true)
            while IFS= read -r entry; do
                local rel="${entry#"$sub_path/"}"
                [[ -z "$rel" ]] && continue
                unzip -oqj "$dest" "$entry" -d "$OUTPUT_DIR/$dest_path" 2>>"$LOG_FILE"
            done <<< "$entries"
            ;;
        *)
            warn "$label: unknown action '$action'"
            FAILED+=("$label")
            CHANGELOG_ENTRIES+=("$label|$repo|$version|$filename|FAILED – unknown action")
            return
            ;;
    esac

    log "  done."
    CHANGELOG_ENTRIES+=("$label|$repo|$version|$filename|OK")
    (( DONE++ )) || true
}

# =============================================================================
#  COMPONENT DOWNLOAD & PLACEMENT
# =============================================================================
log "== Downloading components =="

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
            log "  Hekate payload mapped: hekate.bin, payload.bin, atmosphere/reboot_to_payload.bin, bootloader/payloads/hekate.bin"
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
            log "  dbi.config → switch/DBI/dbi.config"
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
# Using ppkantorski's fork (v2.x) — WerWolv/nx-ovlloader is unmaintained (last: v1.0.7).
# Same atmosphere/contents/420000000007E51A/ layout; active upstream for the Ultrahand ecosystem.
process "nx-ovlloader" "ppkantorski/nx-ovlloader" "nx-ovlloader.zip" "unzip_root"

# 9. EdiZon-Overlay
process "EdiZon-Overlay" "proferabg/EdiZon-Overlay" "ovlEdiZon.ovl" "copy_to" "switch/.overlays"

# 10. Horizon-OC
process "Horizon-OC" "Horizon-OC/Horizon-OC" "dist\.zip" "unzip_root"

# 11. QuickNTP (ppkantorski fork)
# Replaces nedex/QuickNTP (sdout.zip). Ships a standalone QuickNTP.ovl — no collision risk.
process "QuickNTP" "ppkantorski/QuickNTP" "QuickNTP.ovl" "copy_to" "switch/.overlays"

# 12. sys-patch
process "sys-patch" "impeeza/sys-patch" "sys-patch-" "unzip_root"

# 13. ovl-sysmodules
process "ovl-sysmodules" "ppkantorski/ovl-sysmodules" "ovlSysmodules.ovl" "copy_to" "switch/.overlays"

# 14. FPSLocker (ppkantorski fork)
process "FPSLocker" "ppkantorski/FPSLocker" "FPSLocker.ovl" "copy_to" "switch/.overlays"

# 15. Memory-Kit
# Release zip goes to switch/.packages/Memory Kit/. The mesosphere binary is not in
# the zip — fetched separately from the repo tree below.
process "Memory-Kit" "ppkantorski/Memory-Kit" "Memory.Kit.zip" "unzip_root"

log ""
log "[ Memory-Kit mesosphere kernel ] repo tree → atmosphere/"
_MESO_URL="https://raw.githubusercontent.com/ppkantorski/Memory-Kit/main/Memory%20Kit/data/mesosphere_1.85MB_1.11.bin"
_MESO_DEST="$DL_DIR/mesosphere_1.85MB_1.11.bin"
mkdir -p "$OUTPUT_DIR/atmosphere"
if download_file "$_MESO_URL" "$_MESO_DEST" 2>>"$LOG_FILE"; then
    cp "$_MESO_DEST" "$OUTPUT_DIR/atmosphere/mesosphere_1.85MB_1.11.bin"
    log "  mesosphere_1.85MB_1.11.bin → atmosphere/"
    CHANGELOG_ENTRIES+=("Memory-Kit mesosphere|ppkantorski/Memory-Kit|main|mesosphere_1.85MB_1.11.bin|OK")
    (( DONE++ )) || true
else
    warn "Failed to download mesosphere_1.85MB_1.11.bin — hekate_ipl.ini kernel= entry will be broken"
    FAILED+=("Memory-Kit mesosphere")
    CHANGELOG_ENTRIES+=("Memory-Kit mesosphere|ppkantorski/Memory-Kit|main|mesosphere_1.85MB_1.11.bin|FAILED – download error")
fi

# 16. Alchemist
process "Alchemist" "ppkantorski/Alchemist" "Alchemist.zip" "unzip_root"

# 17. Ultrahand-Overlay
# PROCESS_FILENAME_OVERRIDE avoids any future sdout.zip collision in _downloads/.
PROCESS_FILENAME_OVERRIDE="ultrahand_sdout.zip"
process "Ultrahand-Overlay" "ppkantorski/Ultrahand-Overlay" "sdout.zip" "unzip_root"

# Ultrahand companion assets: ovlmenu.ovl + lang.zip
# Fetched in the main shell (not a subshell) so CHANGELOG_ENTRIES is updated correctly.
log ""
log "[ Ultrahand companion assets ] ovlmenu.ovl + lang.zip"

_uh_tag=$(get_latest_tag "ppkantorski/Ultrahand-Overlay" 2>>"$LOG_FILE" || true)

if [[ -z "$_uh_tag" ]]; then
    warn "Ultrahand: could not resolve tag for companion assets"
    FAILED+=("Ultrahand ovlmenu.ovl")
    CHANGELOG_ENTRIES+=("Ultrahand ovlmenu.ovl|ppkantorski/Ultrahand-Overlay|unknown|n/a|FAILED – could not resolve tag")
else
    _uh_assets=$(get_release_assets "ppkantorski/Ultrahand-Overlay" "$_uh_tag" 2>>"$LOG_FILE" || true)

    _ovl_url=$(echo "$_uh_assets" | grep "ovlmenu\.ovl" | head -1 || true)
    if [[ -n "$_ovl_url" ]]; then
        if download_file "$_ovl_url" "$DL_DIR/ovlmenu.ovl" 2>>"$LOG_FILE"; then
            mkdir -p "$OUTPUT_DIR/switch/.overlays"
            cp "$DL_DIR/ovlmenu.ovl" "$OUTPUT_DIR/switch/.overlays/ovlmenu.ovl"
            log "  ovlmenu.ovl → switch/.overlays/ovlmenu.ovl"
            CHANGELOG_ENTRIES+=("Ultrahand ovlmenu.ovl|ppkantorski/Ultrahand-Overlay|$_uh_tag|ovlmenu.ovl|OK")
            (( DONE++ )) || true
        else
            warn "Ultrahand: failed to download ovlmenu.ovl"
            FAILED+=("Ultrahand ovlmenu.ovl")
            CHANGELOG_ENTRIES+=("Ultrahand ovlmenu.ovl|ppkantorski/Ultrahand-Overlay|$_uh_tag|ovlmenu.ovl|FAILED – download error")
        fi
    else
        warn "Ultrahand: ovlmenu.ovl not found in release assets for $_uh_tag"
        FAILED+=("Ultrahand ovlmenu.ovl")
        CHANGELOG_ENTRIES+=("Ultrahand ovlmenu.ovl|ppkantorski/Ultrahand-Overlay|$_uh_tag|n/a|FAILED – asset not matched")
    fi

    _lang_url=$(echo "$_uh_assets" | grep "lang\.zip" | head -1 || true)
    if [[ -n "$_lang_url" ]]; then
        if download_file "$_lang_url" "$DL_DIR/ultrahand_lang.zip" 2>>"$LOG_FILE"; then
            mkdir -p "$OUTPUT_DIR/config/ultrahand/lang"
            unzip -oq "$DL_DIR/ultrahand_lang.zip" -d "$OUTPUT_DIR/config/ultrahand/lang" 2>>"$LOG_FILE"
            log "  lang.zip → config/ultrahand/lang/"
            CHANGELOG_ENTRIES+=("Ultrahand lang.zip|ppkantorski/Ultrahand-Overlay|$_uh_tag|lang.zip|OK")
            (( DONE++ )) || true
        else
            warn "Ultrahand: failed to download lang.zip (non-fatal)"
            CHANGELOG_ENTRIES+=("Ultrahand lang.zip|ppkantorski/Ultrahand-Overlay|$_uh_tag|lang.zip|FAILED – download error")
        fi
    else
        log "  lang.zip not present in this release — skipping"
    fi
fi

# 18. ReverseNX-RT
# Asset named ReverseNX-RT-ovl.ovl — renamed on copy to match overlay naming convention.
# Requires SaltyNX (step 6).
process "ReverseNX-RT" "ppkantorski/ReverseNX-RT" "ReverseNX-RT-ovl\.ovl" "copy_to" "switch/.overlays" "ReverseNX-RT.ovl"

# 19. DNS-MITM_Manager
# Tesla/Ultrahand overlay for toggling Atmosphere DNS MITM hosts entries.
process "DNS-MITM_Manager" "sthetix/DNS-MITM_Manager" "DNS-MITM_Manager.zip" "unzip_root"

# 20. ldn_mitm
# LAN-play sysmodule. Zip ships full SD layout:
#   atmosphere/contents/4200000000000010/ + switch/ldnmitm_config/ + switch/.overlays/
process "ldn_mitm" "spacemeowx2/ldn_mitm" "ldn_mitm_" "unzip_root"

# 21 & 22. Quick-Reboot (.nro app + .ovl overlay — two assets from the same release)
process "Quick-Reboot (app)"     "eradicatinglove/Quick-Reboot" "Quick-Reboot\.nro" "copy_to" "switch"
process "Quick-Reboot (overlay)" "eradicatinglove/Quick-Reboot" "Quick-Reboot\.ovl" "copy_to" "switch/.overlays"

# 23. emuiibo
# Zip ships: atmosphere/contents/0100000000000352/ + switch/.overlays/emuiibo.ovl + lang/
# ovlmenu.ovl and nx-ovlloader already provided by steps 17 and 8 respectively.
process "emuiibo" "XorTroll/emuiibo" "emuiibo.zip" "unzip_root"

# 24. Status-Monitor-Overlay
process "Status-Monitor-Overlay" "ppkantorski/Status-Monitor-Overlay" "Status-Monitor-Overlay.ovl" "copy_to" "switch/.overlays"

# 25. sphaira
# Zip extracts to switch/sphaira/sphaira.nro (homebrew menu replacement).
process "sphaira" "ITotalJustice/sphaira" "sphaira.zip" "unzip_root"

# 26. Lockpick_RCMaster
# Standalone .bin payload — fetched directly, placed in bootloader/payloads/.
process "Lockpick_RCMaster" "THZoria/Lockpick_RCMaster" "Lockpick_RCM.bin" "copy_to" "bootloader/payloads"

# =============================================================================
#  GENERATE CONFIGURATION FILES
# =============================================================================
log ""
log "== Generating config files =="

log "writing exosphere.ini..."
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
log "exosphere.ini written."

log "writing bootloader/hekate_ipl.ini..."
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
kip1=atmosphere/kips/hoc.kip
secmon=atmosphere/exosphere.bin
emummcforce=1
icon=bootloader/res/emummc.bmp
EOF
log "bootloader/hekate_ipl.ini written."

log "fetching emummc.bmp from repo assets..."
_REPO_SLUG="${GITHUB_REPOSITORY:-SteadyEvenin/steady_nx_pack}"
_BMP_URL="https://raw.githubusercontent.com/${_REPO_SLUG}/main/assets/emummc.bmp"
mkdir -p "$OUTPUT_DIR/bootloader/res"
if curl -sL --max-time 30 --retry 3 \
        -H "User-Agent: build_nx_pack/1.0" \
        ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
        "$_BMP_URL" -o "$OUTPUT_DIR/bootloader/res/emummc.bmp" \
   && [[ $(wc -c < "$OUTPUT_DIR/bootloader/res/emummc.bmp") -gt 512 ]]; then
    log "bootloader/res/emummc.bmp placed."
else
    warn "Could not download emummc.bmp from $_BMP_URL — placeholder omitted."
    rm -f "$OUTPUT_DIR/bootloader/res/emummc.bmp"
fi

# =============================================================================
#  POST-BUILD: directory structure
# =============================================================================
log ""
log "== Finalising directory structure =="

# Merge any nested SdOut/ folder left by sdout.zip extractions
for target_sdout in "$OUTPUT_DIR/SdOut" "$OUTPUT_DIR/sdout"; do
    if [[ -d "$target_sdout" ]]; then
        log "merging nested $(basename "$target_sdout") into SD root..."
        find "$target_sdout" -mindepth 1 -maxdepth 1 -exec cp -r {} "$OUTPUT_DIR/" \; 2>>"$LOG_FILE"
        rm -rf "$target_sdout"
        log "$(basename "$target_sdout") consolidated."
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
log "directory tree verified."

# =============================================================================
#  CHANGELOG OUTPUT
# =============================================================================
log ""
log "== Writing changelog =="

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
        status_md="OK"
    else
        status_md="FAILED: ${status#FAILED – }"
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
log "CHANGELOG.md written."

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
    status_short="OK"
    [[ "$status" != "OK" ]] && status_short="FAILED"
    [[ ${#lbl}   -gt $W_LABEL   ]] && lbl="${lbl:0:$((W_LABEL-1))}…"
    [[ ${#ver}   -gt $W_VERSION ]] && ver="${ver:0:$((W_VERSION-1))}…"
    [[ ${#asset} -gt $W_ASSET   ]] && asset="${asset:0:$((W_ASSET-1))}…"
    printf "| %s | %s | %s | %s |\n" \
        "$(pad "$lbl"          $W_LABEL)" \
        "$(pad "$ver"          $W_VERSION)" \
        "$(pad "$asset"        $W_ASSET)" \
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
log "CHANGELOG.txt written."

# =============================================================================
#  SUMMARY
# =============================================================================
log ""
log "== Summary =="
log "Output:    $OUTPUT_DIR"
log "Succeeded: $DONE component(s)"

if [[ ${#FAILED[@]} -gt 0 ]]; then
    log "Failed:    ${#FAILED[@]} component(s):"
    for f in "${FAILED[@]}"; do
        warn "FAILED: $f"
    done
    log "See $LOG_FILE for details."
else
    log "All components processed successfully."
fi

log ""
log "Directory layout:"
find "$OUTPUT_DIR" -maxdepth 3 -type d | sort | sed "s|$OUTPUT_DIR|  SD:|"

log ""
log "Changelog: $CHANGELOG_MD"
log "Changelog: $CHANGELOG_TXT"

if [[ "${KEEP_DOWNLOADS:-0}" != "1" ]]; then
    rm -rf "$DL_DIR"
    log "Download cache cleared. Set KEEP_DOWNLOADS=1 to preserve."
fi
