#!/usr/bin/env bash
set -euo pipefail

# Step-by-step, modular sha256 updater for PKGBUILD files.
# Supports generic GitHub repos via CLI options and a dry-run mode.
#
# Quick examples:
#   ./update-sha256sums.sh                         # uses PKGBUILD next to this script
#   ./update-sha256sums.sh -p /path/to/PKGBUILD    # explicit PKGBUILD
#   ./update-sha256sums.sh -r Firstp1ck/Pacsea     # explicit repo
#   ./update-sha256sums.sh -r owner/repo -a bin    # explicit repo + asset
#   ./update-sha256sums.sh -v 1.2.3                # version -> tag=v1.2.3
#   ./update-sha256sums.sh -t v1.2.3               # exact tag
#   ./update-sha256sums.sh -n                      # dry run (no file edits)
#
# Notes:
# - Defaults and behavior:
#   1) Use --tag or --version if provided; if both are unset, read pkgver from PKGBUILD
#   2) If only version is known, build tag as TAG_PREFIX+version (default prefix: 'v'); if only tag is known, derive version by stripping TAG_PREFIX
#   3) Deduce repo from PKGBUILD url (if not given)
#   4) Download release asset (default name 'Pacsea') and tagged source tarball
#   5) Update two-entry sha256sums array (binary on header line, source on next line)
#
# Requirements: curl, sha256sum, sed, grep, awk, find

#############################################
# Defaults
#############################################
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
PKGFILE="./PKGBUILD"
REPO="Firstp1ck/Pacsea"                 # owner/repo
ASSET_NAME="Pacsea"     # release asset file name
VERSION=""              # e.g. 0.4.0
TAG=""                  # e.g. v0.4.0
TAG_PREFIX="v"          # used when TAG is not provided
BINARY_URL=""           # optional explicit URL override
SOURCE_URL=""           # optional explicit URL override
DRY_RUN=false

STEP=0

#############################################
# Helpers
#############################################
usage() {
  cat <<'EOF'
Usage:
  update-sha256sums.sh [options]

Options:
  -p, --pkgbuild PATH         Path to PKGBUILD (default: ./PKGBUILD or interactive selection under $AUR_BASE; default AUR_BASE: $HOME/aur-packages)
  -r, --repo OWNER/REPO       GitHub repo in owner/repo form (auto-detected from PKGBUILD url if possible)
  -a, --asset NAME            Release asset filename (default: Pacsea)
  -v, --version X.Y.Z         Version; if TAG is unset, tag = TAG_PREFIX+version (default prefix: 'v')
  -t, --tag TAG               Exact tag (e.g. v0.4.0); if VERSION is unset, version is derived by stripping TAG_PREFIX
      --tag-prefix PFX        Tag prefix used to build/strip tags (default: v)
      --binary-url URL        Override binary download URL (disables repo/asset inference)
      --source-url URL        Override source tarball URL (disables repo inference)
  -n, --dry-run               Show actions and computed hashes but do not modify files
  -h, --help                  Show this help

Examples:
  ./update-sha256sums.sh -p ./PKGBUILD
  ./update-sha256sums.sh -r Firstp1ck/Pacsea -a Pacsea -v 0.4.0
  ./update-sha256sums.sh -t v0.4.0

After updating, regenerate .SRCINFO:
  makepkg --printsrcinfo > .SRCINFO
EOF
}

log_step() {
  STEP=$((STEP+1))
  echo "[$STEP] ℹ️ $*" >&2
}

die() {
  echo "❌ Error: $*" >&2
  exit 1
}

require_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    echo "✅ Found required command: $1" >&2
  else
    die "Missing required command: $1"
  fi
}

parse_repo_from_url() {
  # Extract owner/repo from a URL like https://github.com/Owner/Repo
  # Returns via echo or empty if not parsable
  local url_line repo
  url_line=$(grep -E '^[[:space:]]*url=' "$PKGFILE" | head -n1 | cut -d '=' -f2- | tr -d '"' | tr -d "'")
  if [[ -n "${url_line:-}" ]]; then
    repo=$(echo "$url_line" | sed -nE 's#^.*/github\.com/([^/]+)/([^/]+)/?$#\1/\2#p')
    [[ -n "${repo:-}" ]] && echo "$repo"
  fi
}

#############################################
# Parse args
#############################################
if [[ $# -gt 0 ]]; then
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--pkgbuild)
        PKGFILE="$2"; shift 2;;
      -r|--repo)
        REPO="$2"; shift 2;;
      -a|--asset)
        ASSET_NAME="$2"; shift 2;;
      -v|--version)
        VERSION="$2"; shift 2;;
      -t|--tag)
        TAG="$2"; shift 2;;
      --tag-prefix)
        TAG_PREFIX="$2"; shift 2;;
      --binary-url)
        BINARY_URL="$2"; shift 2;;
      --source-url)
        SOURCE_URL="$2"; shift 2;;
      -n|--dry-run)
        DRY_RUN=true; shift;;
      -h|--help)
        usage; exit 0;;
      *)
        # Backward-compat: allow a single positional PKGBUILD path
        if [[ "$1" != -* && "$#" -eq 1 ]]; then
          PKGFILE="$1"; shift
        else
          echo "Unknown option: $1" >&2
          usage
          exit 2
        fi
        ;;
    esac
  done
fi

#############################################
# Validations & discovery
#############################################
require_cmd curl
require_cmd sha256sum
require_cmd sed
require_cmd grep
require_cmd awk
require_cmd find

# Prefer ./PKGBUILD; if missing and -p not provided, interactively choose under $AUR_BASE (default: $HOME/aur-packages)
if [[ ! -f "$PKGFILE" ]]; then
  AUR_BASE="${AUR_BASE:-$HOME/aur-packages}"
  echo "ℹ️ Looking for PKGBUILD under: $AUR_BASE" >&2
  if [[ ! -d "$AUR_BASE" ]]; then
    die "PKGBUILD not found in current directory and AUR_BASE directory does not exist: $AUR_BASE"
  fi
  mapfile -t _pkgs < <(find "$AUR_BASE" -maxdepth 2 -type f -name PKGBUILD 2>/dev/null | sort)
  if [[ ${#_pkgs[@]} -eq 0 ]]; then
    die "No PKGBUILD files found under: $AUR_BASE"
  fi
  echo "Please select a package to use:" >&2
  for i in "${!_pkgs[@]}"; do
    d=$(dirname "${_pkgs[$i]}")
    printf "  [%d] %s\n" "$((i+1))" "$d" >&2
  done
  while true; do
    read -r -p "Enter selection [1-${#_pkgs[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#_pkgs[@]} )); then
      sel_dir=$(dirname "${_pkgs[$((choice-1))]}")
      PKGFILE="$sel_dir/PKGBUILD"
      break
    else
      echo "Invalid selection. Try again." >&2
    fi
  done
fi
echo "✅ Using PKGBUILD: $PKGFILE" >&2

# Determine VERSION/TAG
if [[ -z "${VERSION:-}" && -z "${TAG:-}" ]]; then
  log_step "Reading pkgver from $PKGFILE"
  VERSION=$(grep -E '^[[:space:]]*pkgver=' "$PKGFILE" | head -n1 | cut -d '=' -f2 || true)
  [[ -n "${VERSION:-}" ]] || die "Failed to read pkgver from $PKGFILE. Provide --version or --tag."
fi

# If only VERSION is known, build TAG from it
if [[ -z "${TAG:-}" && -n "${VERSION:-}" ]]; then
  TAG="${TAG_PREFIX}${VERSION}"
fi

# If only TAG is known, derive VERSION from it (strip TAG_PREFIX if present)
if [[ -z "${VERSION:-}" && -n "${TAG:-}" ]]; then
  if [[ -n "${TAG_PREFIX:-}" && "$TAG" == ${TAG_PREFIX}* ]]; then
    VERSION="${TAG#${TAG_PREFIX}}"
  else
    VERSION="${TAG}"
  fi
fi

if [[ -z "${REPO:-}" && -z "${BINARY_URL:-}" ]]; then
  log_step "Trying to deduce repo from PKGBUILD url"
  REPO=$(parse_repo_from_url || true)
fi

if [[ -z "${BINARY_URL:-}" ]]; then
  if [[ -z "${REPO:-}" ]]; then
    die "Repo could not be determined. Provide --repo OWNER/REPO or --binary-url/--source-url."
  fi
  BINARY_URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET_NAME}"
fi

if [[ -z "${SOURCE_URL:-}" ]]; then
  if [[ -z "${REPO:-}" ]]; then
    die "Source URL could not be determined. Provide --repo or --source-url."
  fi
  SOURCE_URL="https://github.com/${REPO}/archive/refs/tags/${TAG}.tar.gz"
fi

echo "ℹ️ Repo:       ${REPO:-"(n/a) (custom URLs)"}" >&2
console_output=""
echo "ℹ️ Version:    ${VERSION}" >&2
console_output+=""
echo "ℹ️ Tag:        ${TAG}" >&2
console_output+=""
echo "ℹ️ Asset:      ${ASSET_NAME}" >&2
echo "ℹ️ Binary URL: ${BINARY_URL}" >&2
echo "ℹ️ Source URL: ${SOURCE_URL}" >&2

#############################################
# Download artifacts and compute hashes
#############################################
log_step "Downloading artifacts for ${TAG}"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

bin_path="$tmpdir/${ASSET_NAME}"
src_path="$tmpdir/src-${TAG}.tar.gz"

curl -fsSL -o "$bin_path" "$BINARY_URL" || die "Failed to download binary from $BINARY_URL"
echo "✅ Downloaded binary artifact" >&2
curl -fsSL -o "$src_path" "$SOURCE_URL" || die "Failed to download source from $SOURCE_URL"
echo "✅ Downloaded source tarball" >&2

log_step "Computing sha256 sums"
sha_bin=$(sha256sum "$bin_path" | awk '{print $1}')
sha_src=$(sha256sum "$src_path" | awk '{print $1}')

echo "ℹ️ binary:  $sha_bin" >&2
echo "ℹ️ source:  $sha_src" >&2

#############################################
# Update PKGBUILD
#############################################
log_step "Locating sha256sums=( in $PKGFILE"
sha_line=$(grep -nE '^[[:space:]]*sha256sums=\(' "$PKGFILE" | head -n1 | cut -d: -f1 || true)
[[ -n "${sha_line:-}" ]] || die "Could not find sha256sums=( in $PKGFILE"

if $DRY_RUN; then
  echo "ℹ️ [dry-run] Would update $PKGFILE at line $sha_line and the next line with the following values:" >&2
  echo "ℹ️ [dry-run]   first entry (binary): $sha_bin" >&2
  echo "ℹ️ [dry-run]   second entry (source): $sha_src" >&2
else
  log_step "Updating sha256sums entries"
  # Replace quoted content on the sha256sums header line (first entry) and the next line (second entry).
  sed -i "${sha_line}s/'[^']*'/'${sha_bin//\//\/}'/" "$PKGFILE"
  sed -i "$((sha_line+1))s/'[^']*'/'${sha_src//\//\/}'/" "$PKGFILE"
  echo "✅ Updated sha256sums in $PKGFILE" >&2
fi

echo >&2
echo "ℹ️ Next steps:" >&2
echo "  ℹ️ makepkg --printsrcinfo > .SRCINFO" >&2
echo "  ℹ️ git add . && git commit -m 'Update checksums for ${TAG}'" >&2

exit 0
