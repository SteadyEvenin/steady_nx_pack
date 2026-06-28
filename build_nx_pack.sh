#!/usr/bin/env bash
# =============================================================================
#  build_nx_pack.sh
#  Builds a clean, ready-to-copy Nintendo Switch CFW SD card layout.
#
#  Components fetched (always latest release):
#   • Atmosphère         • Hekate              • DBI
#   • disable_remap_dlg  • MissionControl       • SaltyNX
#   • theme-patches      • nx-ovlloader         • EdiZon-Overlay
#   • Horizon-OC         • FPSLocker (masag.)   • QuickNTP
#   • sys-patch          • ovl-sysmodules       • FPSLocker (ppkant.)
#   • Memory-Kit         • Alchemist            • HOC-Toolkit
#   • Ultrahand-Overlay  • emuiibo              • Status-Monitor-Overlay
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
        info "  Cached: $(basename "$dest")"
        return 0
    fi
    info "  Downloading: $(basename "$dest")"
    local tag_safe_url="${url//+/%2B}"
    if ! curl -sL --max-time 120 --retry 3 \
              -H "User-Agent: build_nx_pack/1.0" \
              "$tag_safe_url" -o "$dest"; then
        warn "  Download failed: $url"
        return 1
    fi
    local size
    size=$(wc -c < "$dest")
    if (( size < 512 )); then
        warn "  Suspiciously small ($size bytes) – may be an error page"
        cat "$dest" >> "$LOG_FILE"
        return 1
    fi
    ok "  $(basename "$dest") ($size bytes)"
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
            warn "  Could not resolve latest tag for $repo"
            FAILED+=("$label")
            CHANGELOG_ENTRIES+=("$label|$repo|unknown|n/a|FAILED – could not resolve tag")
            return
        fi
        version="$tag"
        info "  Tag: $tag"

        local assets
        assets=$(get_release_assets "$repo" "$tag")
        
        url=$(echo "$assets" | grep -i "$pattern" | head -1 || true)
        if [[ -z "$url" ]]; then
            warn "  No asset matching '$pattern' found in release $tag"
            echo "  Available:" ; echo "$assets" | sed 's/^/    /'
            FAILED+=("$label")
            CHANGELOG_ENTRIES+=("$label|$repo|$tag|n/a|FAILED – asset not matched")
            return
        fi
        filename="$(basename "$url")"
        filename="${filename//%2B/+}"
    fi

    local dest="$DL_DIR/$filename"
    if ! download_file "$url" "$dest"; then
        FAILED+=("$label")
        CHANGELOG_ENTRIES+=("$label|$repo|$version|$filename|FAILED – download error")
        return
    fi

    case "$action" in
        unzip_root)
            info "  Extracting → SD root"
            unzip -oq "$dest" -d "$OUTPUT_DIR" 2>>"$LOG_FILE"
            ;;

        unzip_to)
            local target_path="${extra_args[0]}"
            mkdir -p "$OUTPUT_DIR/$target_path"
            info "  Extracting → $target_path/"
            unzip -oq "$dest" -d "$OUTPUT_DIR/$target_path" 2>>"$LOG_FILE"
            ;;

        copy_to)
            local target_path="${extra_args[0]}"
            local target_name="${extra_args[1]:-$(basename "$dest")}"
            mkdir -p "$OUTPUT_DIR/$target_path"
            info "  Copying → $target_path/$target_name"
            cp "$dest" "$OUTPUT_DIR/$target_path/$target_name"
            ;;

        zip_subfolder)
            local sub_path="${extra_args[0]}"
            local dest_path="${extra_args[1]}"
            mkdir -p "$OUTPUT_DIR/$dest_path"
            info "  Extracting subfolder '$sub_path' → $dest_path/"
            local entries
            entries=$(unzip -Z1 "$dest" 2>/dev/null | grep "^$sub_path" || true)
            while IFS= read -r entry; do
                local rel="${entry#"$sub_path/"}"
                [[ -z "$rel" ]] && continue
                unzip -oqj "$dest" "$entry" -d "$OUTPUT_DIR/$dest_path" 2>>"$LOG_FILE"
            done <<< "$entries"
            ;;

        *)
            warn "  Unknown action: $action"
            FAILED+=("$label")
            CHANGELOG_ENTRIES+=("$label|$repo|$version|$filename|FAILED – unknown action")
            return
            ;;
    esac

    ok "  Done."
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
            mkdir -p "$OUTPUT_DIR/bootloader/payloads"
            cp "$bin_file" "$OUTPUT_DIR/hekate.bin"
            cp "$bin_file" "$OUTPUT_DIR/bootloader/payloads/hekate.bin"
            info "  Hekate payload → hekate.bin + bootloader/payloads/hekate.bin"
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
            info "  dbi.config → switch/DBI/dbi.config"
        fi
    fi
} 2>>"$LOG_FILE" || warn "Could not place dbi.config"

# 4. disable_remap_dialog
process "disable_remap_dialog" "ndeadly/disable_remap_dialog" "disable_remap_dialog.zip" "unzip_root"

# 5. MissionControl
process "MissionControl" "ndeadly/MissionControl" "MissionControl-" "unzip_root"

# 6. SaltyNX (FIX: Stripped anchors '^' and '$' to prevent pipeline matching mismatches)
process "SaltyNX" "masagrator/SaltyNX" "SaltyNX\.zip" "unzip_root"

# 7. theme-patches
process "theme-patches" "exelix11/theme-patches" "SOURCE:master" "zip_subfolder" "theme-patches-master/systemPatches" "atmosphere/exefs_patches/theme-patches"

# 8. nx-ovlloader
process "nx-ovlloader" "ppkantorski/nx-ovlloader" "nx-ovlloader.zip" "unzip_root"

# 9. EdiZon-Overlay
process "EdiZon-Overlay" "proferabg/EdiZon-Overlay" "ovlEdiZon.ovl" "copy_to" "switch/.overlays"

# 10. Horizon-OC (FIX: Stripped anchors '^' and '$' to prevent pipeline matching mismatches)
process "Horizon-OC" "Horizon-OC/Horizon-OC" "dist\.zip" "unzip_root"

# 11. FPSLocker (masagrator)
process "FPSLocker (masagrator)" "masagrator/FPSLocker" "FPSLocker.ovl" "copy_to" "switch/.overlays"

# 12. QuickNTP
process "QuickNTP" "nedex/QuickNTP" "sdout.zip" "unzip_root"

# 13. sys-patch
process "sys-patch" "borntohonk/sys-patch" "sys-patch-" "unzip_root"

# 14. ovl-sysmodules (ppkantorski)
process "ovl-sysmodules" "ppkantorski/ovl-sysmodules" "ovlSysmodules.ovl" "copy_to" "switch/.overlays"

# 15. FPSLocker (ppkantorski fork)
process "FPSLocker (ppkantorski)" "ppkantorski/FPSLocker" "FPSLocker.ovl" "copy_to" "switch/.overlays"

# 16. Memory-Kit
process "Memory-Kit" "ppkantorski/Memory-Kit" "Memory.Kit.zip" "unzip_root"

# 17. Alchemist
process "Alchemist" "ppkantorski/Alchemist" "Alchemist.zip" "unzip_root"

# 18. HOC-Toolkit
process "HOC-Toolkit" "ppkantorski/HOC-Toolkit" "hoc-toolkit.zip" "unzip_root"

# 19. Ultrahand-Overlay
process "Ultrahand-Overlay" "ppkantorski/Ultrahand-Overlay" "sdout.zip" "unzip_root"

{
    tag=$(get_latest_tag "ppkantorski/Ultrahand-Overlay")
    if [[ -n "$tag" ]]; then
        assets=$(get_release_assets "ppkantorski/Ultrahand-Overlay" "$tag")
        lang_url=$(echo "$assets" | grep "lang.zip" | head -1 || true)
        if [[ -n "$lang_url" ]]; then
            lang_file="$DL_DIR/ultrahand_lang.zip"
            download_file "$lang_url" "$lang_file"
            
            # ── FIXED: Force flat language files to route into their correct directory ──
            mkdir -p "$OUTPUT_DIR/config/ultrahand/lang"
            unzip -oq "$lang_file" -d "$OUTPUT_DIR/config/ultrahand/lang" 2>>"$LOG_FILE"
            info "  Ultrahand lang.zip extracted into config/ultrahand/lang/"
        fi
    fi
} 2>>"$LOG_FILE" || warn "Could not fetch Ultrahand lang.zip"

# 20. emuiibo
process "emuiibo" "XorTroll/emuiibo" "emuiibo.zip" "unzip_root"

# 21. Status-Monitor-Overlay
process "Status-Monitor-Overlay" "ppkantorski/Status-Monitor-Overlay" "Status-Monitor-Overlay.ovl" "copy_to" "switch/.overlays"

# =============================================================================
#  POST-BUILD: ensure essential directories exist
# =============================================================================
section "Finalising directory structure"

# ── FIXED: Automated post-build consolidation of nested 'SdOut' directories ───
for target_sdout in "$OUTPUT_DIR/SdOut" "$OUTPUT_DIR/sdout"; do
    if [[ -d "$target_sdout" ]]; then
        info "Merging nested $(basename "$target_sdout") contents into standard SD layout..."
        # Safely copy items (including system configurations and hidden files) to the true SD root
        find "$target_sdout" -mindepth 1 -maxdepth 1 -exec cp -r {} "$OUTPUT_DIR/" \; 2>>"$LOG_FILE"
        rm -rf "$target_sdout"
        ok "Redundant $(basename "$target_sdout") folder successfully consolidated."
    fi
done

declare -a ENSURE_DIRS=(
    "atmosphere/contents"
    "atmosphere/exefs_patches"
    "atmosphere/exefs_patches/theme-patches"
    "atmosphere/kips"
    "bootloader/payloads"
    "config"
    "switch"
    "switch/.overlays"
    "switch/.packages"
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

ok "  CHANGELOG.md written."

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

ok "  CHANGELOG.txt written."
section "Summary"
echo -e "  ${BOLD}Output:${NC}    $OUTPUT_DIR"
echo -e "  ${GREEN}Succeeded:${NC} $DONE component(s)"

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo -e "  ${RED}Failed:${NC}    ${#FAILED[@]} component(s):"
    for f in "${FAILED[@]}"; do
        echo -e "    ${RED}•${NC} $f"
    done
    echo -e "  See $LOG_FILE for details."
else
    echo -e "  ${GREEN}All components processed successfully.${NC}"
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
echo "  1. Create bootloader/hekate_ipl.ini with your boot entries (see Hekate wiki)."
echo "  2. Copy everything inside $OUTPUT_DIR/ to the root of your FAT32/exFAT SD card."
echo "  3. Boot via Hekate payload."

if [[ "${KEEP_DOWNLOADS:-0}" != "1" ]]; then
    rm -rf "$DL_DIR"
    info "Download cache cleaned. Set KEEP_DOWNLOADS=1 to preserve it."
fi