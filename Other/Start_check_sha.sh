#!/usr/bin/env bash

# ---------------------------------------------------------------------------
# verify-sha.sh  –  Interactive checksum validator                  2025-06-16
# ---------------------------------------------------------------------------
#  • Select SHA algorithm via NUMBER menu (1 / 2 / 3)
#  • Accepts reference hash WITH or WITHOUT leading “sha256:”
#  • Accepts Unix paths and Windows “C:\…\file.exe” (with or without quotes)
#  • Prints ✅ MATCH or ❌ MISMATCH and returns sensible exit codes
# ---------------------------------------------------------------------------

set -euo pipefail

# ────────────────────────── Helper functions ────────────────────────────────
strip_quotes() {               # remove surrounding "..."
  local s="$1";  s="${s#\"}";  printf '%s' "${s%\"}"
}

win2unix_path() {              # "C:\Dir\File" → "/c/Dir/File"   (Git-Bash)
  local p="$1"
  if [[ $p =~ ^([A-Za-z]):\\ ]]; then
    local drv=${BASH_REMATCH[1],,}
    p="${p//\\//}"                           # back-slashes → /
    if [[ -n ${WSL_DISTRO_NAME-} ]]; then    # inside WSL?
      p="/mnt/$drv/${p:3}"
    else                                     # Git-Bash / MSYS2 / Cygwin
      p="/$drv/${p:3}"
    fi
  fi
  printf '%s' "$p"
}

resolve_file() {               # returns a readable path or aborts
  local cand; cand=$(strip_quotes "$1")
  [[ -f $cand ]] && { printf '%s' "$cand"; return; }

  local alt;  alt=$(win2unix_path "$cand")
  [[ -f $alt ]] && { printf '%s' "$alt"; return; }

  printf 'Error: file not found or unreadable: %s\n' "$1" >&2
  exit 3
}

normalize_hash() {             # strip label, spaces; validate length/hex
  local algo="$1" raw="$2"
  raw=${raw#${algo}:}; raw=${raw//[[:space:]]/}; raw=${raw,,}

  case $algo in
    sha1)   (( ${#raw} == 40  )) ;;
    sha256) (( ${#raw} == 64  )) ;;
    sha512) (( ${#raw} == 128 )) ;;
  esac  || { printf 'Error: wrong length for %s hash\n' "$algo" >&2; exit 4; }

  [[ $raw =~ ^[0-9a-f]+$ ]] || { printf 'Error: hash is not hex\n' >&2; exit 4; }
  printf '%s' "$raw"
}

# ────────────────────────── Select algorithm ────────────────────────────────
printf '\nChoose checksum algorithm:\n'
printf '  1) SHA-1\n'
printf '  2) SHA-256\n'
printf '  3) SHA-512\n'
while true; do
  read -rp 'Enter choice [1-3]: ' choice
  case $choice in
    1) alg=sha1   ; break ;;
    2) alg=sha256 ; break ;;
    3) alg=sha512 ; break ;;
    *) echo "Please type 1, 2 or 3." ;;
  esac
done

# ────────────────────────── Collect user input ──────────────────────────────
read -rp "Official $alg checksum           : " ref_raw
read -rp "Path to file to verify           : " in_path

file_path=$(resolve_file "$in_path")
ref_hash=$(normalize_hash "$alg" "$ref_raw")
sum_cmd="${alg}sum"           # sha1sum / sha256sum / sha512sum

# ────────────────────────── Verify & report ─────────────────────────────────
if printf '%s  %s\n' "$ref_hash" "$file_path" | "$sum_cmd" --check --status
then
  printf '✅ MATCH – file is intact.\n'
  exit 0
else
  printf '❌ MISMATCH – do NOT use this file.\n'
  exit 1
fi
