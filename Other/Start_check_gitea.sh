#!/usr/bin/env bash
# Compare GitHub repositories with Gitea repositories and report migration/mirror status
#
# Requirements:
# - bash, curl, jq
#
# Usage examples:
# Start_check_gitea.sh \
# --github-user "<USERNAME>" \
# --gitea-user  "<USERNAME>" \
# --gitea-url   "<GITEA_URL>" \
# --github-token-file "$HOME/Path/To/Github_PAT.token" \
# --gitea-token-file  "$HOME/Path/To/Gitea_PAT.token" \
# --include-forks
#
# Start_check_gitea.sh \
#   --github-org "<github_org>" \
#   --gitea-org  "<gitea_org>" \
#   --gitea-url  "https://gitea.example.local" \
#   --github-token "$GITHUB_TOKEN" \
#   --gitea-token  "$GITEA_TOKEN"
#
# Notes:
# - Use Personal Access Tokens (single-line), NOT SSH keys. Do not point to id_ed25519 files.
# - If a GitHub token is provided, private repos can be included.
# - If a Gitea token is provided, private repos can be included.
# - Mirror detection on Gitea is best-effort: uses the "mirror" boolean when present in the API response.

set -euo pipefail
IFS=$'\n\t'

# --------------- Defaults / Config ---------------
GITHUB_API_BASE=${GITHUB_API_BASE:-"https://api.github.com"}
GITEA_BASE_URL=${GITEA_BASE_URL:-""}         # e.g. https://gitea.nas.local
GITEA_API_BASE=""

GITHUB_USER=${GITHUB_USER:-""}
GITHUB_ORG=${GITHUB_ORG:-""}
GITEA_USER=${GITEA_USER:-""}
GITEA_ORG=${GITEA_ORG:-""}

GITHUB_TOKEN=${GITHUB_TOKEN:-""}
GITEA_TOKEN=${GITEA_TOKEN:-""}
GITHUB_TOKEN_FILE=${GITHUB_TOKEN_FILE:-""}
GITEA_TOKEN_FILE=${GITEA_TOKEN_FILE:-""}

INCLUDE_FORKS=${INCLUDE_FORKS:-0}
INCLUDE_ARCHIVED=${INCLUDE_ARCHIVED:-1}

# Output directory defaults to Documents/Gitea_Migration relative to repo root (script/..)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT_DIR_DEFAULT="$REPO_ROOT/Documents/Gitea_Migration"
REPORT_DIR=${REPORT_DIR:-"$REPORT_DIR_DEFAULT"}
mkdir -p "$REPORT_DIR"

# --------------- Helpers ---------------
error() { echo "[ERROR] $*" >&2; }
info()  { echo "[INFO]  $*" >&2; }
warn()  { echo "[WARN]  $*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { error "Missing dependency: $1"; exit 2; }
}

read_secret_from_file_if_needed() {
  local var_name="$1" file_var_name="$2"
  local current_value file_path
  current_value="${!var_name:-}"
  file_path="${!file_var_name:-}"
  if [[ -z "$current_value" && -n "$file_path" ]]; then
    if [[ -r "$file_path" ]]; then
      local raw content first_line
      raw="$(<"$file_path")"
      # Normalize newlines and strip CR
      content="$(printf '%s' "$raw" | tr -d '\r')"
      # Reject obvious SSH keys to avoid breaking Authorization header
      if printf '%s' "$content" | grep -qE -- '-----BEGIN .*PRIVATE KEY-----|^ssh-'; then
        warn "File looks like an SSH key, not an API token: $file_path. Ignoring."
        # shellcheck disable=SC2163
        export "$var_name"=""
        return 0
      fi
      # Take first non-empty line (tokens must be single-line)
      first_line="$(printf '%s' "$content" | awk 'NF {print; exit}')"
      if [[ -z "$first_line" ]]; then
        warn "Token file appears empty: $file_path"
        # shellcheck disable=SC2163
        export "$var_name"=""
        return 0
      fi
      if printf '%s' "$content" | awk 'NR>1 && NF {exit 0} END{exit 1}'; then
        warn "Token file has multiple lines; using the first non-empty line: $file_path"
      fi
      # Warn if token contains whitespace
      if printf '%s' "$first_line" | grep -q '[[:space:]]'; then
        warn "Token contains whitespace; this may be invalid."
      fi
      # shellcheck disable=SC2163
      export "$var_name"="$first_line"
    else
      warn "Token file not readable: $file_path"
    fi
  fi
}

urlencode() {
  # URL-encode a string
  local LC_ALL=C
  local str="$1"
  local out=""
  local c
  for (( i=0; i<${#str}; i++ )); do
    c=${str:$i:1}
    case "$c" in
      [a-zA-Z0-9.~_-]) out+="$c" ;;
      *) printf -v out '%s%%%02X' "$out" "'""$c""'" ;;
    esac
  done
  printf '%s' "$out"
}

# --------------- HTTP wrappers ---------------
http_get_github() {
  local url="$1"
  if [[ -n "$GITHUB_TOKEN" ]]; then
    curl -fsSL -H "Authorization: token $GITHUB_TOKEN" \
         -H 'Accept: application/vnd.github+json' \
         "$url"
  else
    curl -fsSL -H 'Accept: application/vnd.github+json' "$url"
  fi
}

http_get_gitea() {
  local url="$1"
  if [[ -n "$GITEA_TOKEN" ]]; then
    # Gitea supports GitHub-like token auth header
    curl -fsSL -H "Authorization: token $GITEA_TOKEN" -H 'Accept: application/json' "$url"
  else
    curl -fsSL -H 'Accept: application/json' "$url"
  fi
}

# --------------- Pagination fetchers ---------------
# Returns a JSON array of repos for GitHub
fetch_github_repos() {
  local scope="$1" # user|org|authuser
  local name="$2"  # username or org name (ignored for authuser)
  local page=1
  local per_page=100
  local all_json='[]'
  local endpoint

  while :; do
    case "$scope" in
      authuser)
        # Uses token to fetch all repos owned by the authenticated user
        endpoint="$GITHUB_API_BASE/user/repos?per_page=$per_page&page=$page&affiliation=owner&sort=full_name&direction=asc"
        ;;
      user)
        endpoint="$GITHUB_API_BASE/users/$(urlencode "$name")/repos?per_page=$per_page&page=$page&type=owner&sort=full_name&direction=asc"
        ;;
      org)
        endpoint="$GITHUB_API_BASE/orgs/$(urlencode "$name")/repos?per_page=$per_page&page=$page&type=all&sort=full_name&direction=asc"
        ;;
      *) error "Unknown GitHub scope: $scope"; return 1 ;;
    esac

    local page_json
    if ! page_json="$(http_get_github "$endpoint")"; then
      error "Failed to fetch GitHub repos (scope=$scope name=$name page=$page)"
      return 1
    fi

    local count
    count="$(jq 'if type=="array" then length else 0 end' <<<"$page_json")"
    all_json="$(printf '%s\n%s' "$all_json" "$page_json" | jq -c -s 'add')"
    if (( count < per_page )); then
      break
    fi
    ((page++))
  done

  # Optional filtering
  local filter='.[]'
  if (( ! INCLUDE_FORKS )); then
    filter+=" | select(.fork == false)"
  fi
  if (( ! INCLUDE_ARCHIVED )); then
    filter+=" | select(.archived == false)"
  fi

  jq -c "[$filter]" <<<"$all_json"
}

# Returns a JSON array of repos for Gitea
fetch_gitea_repos() {
  local scope="$1" # user|org
  local name="$2"
  local page=1
  local limit=50
  local all_json='[]'
  local endpoint

  while :; do
    case "$scope" in
      user)
        endpoint="$GITEA_API_BASE/user/repos?limit=$limit&page=$page&sort=alphabetically"
        ;;
      org)
        endpoint="$GITEA_API_BASE/orgs/$(urlencode "$name")/repos?limit=$limit&page=$page&sort=alphabetically"
        ;;
      *) error "Unknown Gitea scope: $scope"; return 1 ;;
    esac

    local page_json
    if ! page_json="$(http_get_gitea "$endpoint")"; then
      error "Failed to fetch Gitea repos (scope=$scope name=$name page=$page)"
      return 1
    fi

    local count
    count="$(jq 'if type=="array" then length else 0 end' <<<"$page_json")"
    all_json="$(printf '%s\n%s' "$all_json" "$page_json" | jq -c -s 'add')"
    if (( count < limit )); then
      break
    fi
    ((page++))
  done

  jq -c '.' <<<"$all_json"
}

# --------------- Comparison ---------------
# Build maps keyed by lowercased repo name for easy comparison
build_map_from_repolist() {
  # stdin: JSON array of repos
  # stdout: JSON object map: name_lower -> { name, full_name, private, fork, archived, html_url, ssh_url, language }
  jq -c '
    map({
      key: (.name | ascii_downcase),
      value: {
        name, full_name, private, fork, archived,
        html_url, ssh_url, language
      }
    }) | from_entries'
}

build_gitea_map_with_mirror() {
  # stdin: JSON array of repos
  # stdout: JSON object map: name_lower -> { name, full_name, private, fork, empty, mirror, html_url, ssh_url }
  jq -c '
    map({
      key: (.name | ascii_downcase),
      value: {
        name, full_name, private, fork, empty,
        mirror: (if has("mirror") then .mirror else null end),
        html_url, ssh_url
      }
    }) | from_entries'
}

# --------------- Reporting ---------------
write_csv_report() {
  local csv_path="$1"
  local gh_file="$2"
  local gt_file="$3"

  printf 'GitHub Full Name,GitHub Private,GitHub Fork,GitHub Archived,Language,Gitea Exists,Gitea Full Name,Gitea Private,Gitea Mirror\n' > "$csv_path"

  # Iterate over GitHub repos
  local key
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue

    local gh
    gh="$(jq -c --arg k "$key" '.[$k]' "$gh_file")"
    local gh_full gh_priv gh_fork gh_arch gh_lang
    gh_full="$(jq -r '.full_name' <<<"$gh")"
    gh_priv="$(jq -r '.private'    <<<"$gh")"
    gh_fork="$(jq -r '.fork'       <<<"$gh")"
    gh_arch="$(jq -r '.archived'   <<<"$gh")"
    gh_lang="$(jq -r '.language // ""' <<<"$gh")"

    local gt_exists gt gt_full gt_priv gt_mirror
    gt_exists="false"
    if jq -e --arg k "$key" 'has($k)' "$gt_file" >/dev/null; then
      gt_exists="true"
      gt="$(jq -c --arg k "$key" '.[$k]' "$gt_file")"
      gt_full="$(jq -r '.full_name' <<<"$gt")"
      gt_priv="$(jq -r '.private'   <<<"$gt")"
      gt_mirror="$(jq -r '.mirror // "unknown"' <<<"$gt")"
    else
      gt_full=""
      gt_priv=""
      gt_mirror=""
    fi

    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$gh_full" "$gh_priv" "$gh_fork" "$gh_arch" "$gh_lang" \
      "$gt_exists" "$gt_full" "$gt_priv" "$gt_mirror" \
      >> "$csv_path"
  done < <(jq -r 'keys[]' "$gh_file")
}

print_summary() {
  # Args: GH_MAP_FILE, GT_MAP_FILE
  local gh_file="$1" gt_file="$2"

  local total_github total_gitea matched missing
  total_github="$(jq 'length' "$gh_file")"
  total_gitea="$(jq 'length' "$gt_file")"

  matched="$(jq -n \
    --slurpfile gh "$gh_file" \
    --slurpfile gt "$gt_file" \
    '($gh[0]|keys) as $gk | ($gt[0]|keys) as $tk | (($gk - ($gk - $tk)) | length)')"
  missing=$(( total_github - matched ))

  info "GitHub repos considered: $total_github"
  info "Gitea repos available:   $total_gitea"
  info "Already on Gitea:        $matched"
  info "Missing on Gitea:        $missing"
}

# --------------- CLI parsing ---------------
usage() {
  cat >&2 <<'USAGE'
Usage: Start_check_gitea.sh [options]

GitHub source (choose one or combine):
  --github-user NAME          GitHub username (public repos without token; private require token)
  --github-org  NAME          GitHub organization name

Gitea target (choose one):
  --gitea-user  NAME          Gitea username (list repos under this user)
  --gitea-org   NAME          Gitea organization name
  --gitea-url   URL           Base URL of your Gitea (e.g. https://gitea.nas.local)

Tokens:
  --github-token TOKEN        GitHub API token (env GITHUB_TOKEN also honored)
  --gitea-token  TOKEN        Gitea API token (env GITEA_TOKEN also honored)
  --github-token-file PATH    Read GitHub token from file
  --gitea-token-file  PATH    Read Gitea token from file

Options:
  --include-forks             Include forked repositories (default: off)
  --exclude-archived          Exclude archived repositories (default: include)
  --report-dir DIR            Output directory for reports (default: Documents/Gitea_Migration)
  -h, --help                  Show this help
USAGE
}

ARGS=()
while (( "$#" )); do
  case "$1" in
    --github-user)        GITHUB_USER="${2:-}"; shift 2;;
    --github-org)         GITHUB_ORG="${2:-}"; shift 2;;
    --gitea-user)         GITEA_USER="${2:-}"; shift 2;;
    --gitea-org)          GITEA_ORG="${2:-}"; shift 2;;
    --gitea-url)          GITEA_BASE_URL="${2:-}"; shift 2;;
    --github-token)       GITHUB_TOKEN="${2:-}"; shift 2;;
    --gitea-token)        GITEA_TOKEN="${2:-}"; shift 2;;
    --github-token-file)  GITHUB_TOKEN_FILE="${2:-}"; shift 2;;
    --gitea-token-file)   GITEA_TOKEN_FILE="${2:-}"; shift 2;;
    --include-forks)      INCLUDE_FORKS=1; shift;;
    --exclude-archived)   INCLUDE_ARCHIVED=0; shift;;
    --report-dir)         REPORT_DIR="${2:-}"; mkdir -p "$REPORT_DIR"; shift 2;;
    -h|--help)            usage; exit 0;;
    --) shift; break;;
    *) ARGS+=("$1"); shift;;
  esac
done

# --------------- Validate inputs ---------------
need_cmd curl
need_cmd jq

read_secret_from_file_if_needed GITHUB_TOKEN GITHUB_TOKEN_FILE
read_secret_from_file_if_needed GITEA_TOKEN  GITEA_TOKEN_FILE

if [[ -z "$GITEA_BASE_URL" ]]; then
  error "--gitea-url is required (e.g., https://gitea.nas.local)"
  exit 2
fi
GITEA_API_BASE="$GITEA_BASE_URL/api/v1"

if [[ -z "$GITEA_USER" && -z "$GITEA_ORG" ]]; then
  error "Specify either --gitea-user or --gitea-org"
  exit 2
fi

if [[ -z "$GITHUB_USER" && -z "$GITHUB_ORG" && -z "$GITHUB_TOKEN" ]]; then
  warn "No --github-user/--github-org provided and no token. Will try public repos of an explicit user/org only."
fi

# --------------- Fetch repositories ---------------
info "Fetching repositories..."

# GitHub: combine from selected scopes
all_gh='[]'
if [[ -n "$GITHUB_TOKEN" ]]; then
  info "- GitHub (auth user, owned repos)"
  if gh_auth_json="$(fetch_github_repos authuser "")"; then
    all_gh="$(printf '%s\n%s' "$all_gh" "$gh_auth_json" | jq -c -s 'add')"
  else
    warn "Failed to fetch GitHub authenticated user repos"
  fi
fi

if [[ -n "$GITHUB_USER" ]]; then
  info "- GitHub user: $GITHUB_USER"
  gh_u_json="$(fetch_github_repos user "$GITHUB_USER")"
  all_gh="$(printf '%s\n%s' "$all_gh" "$gh_u_json" | jq -c -s 'add')"
fi

if [[ -n "$GITHUB_ORG" ]]; then
  info "- GitHub org: $GITHUB_ORG"
  gh_o_json="$(fetch_github_repos org "$GITHUB_ORG")"
  all_gh="$(printf '%s\n%s' "$all_gh" "$gh_o_json" | jq -c -s 'add')"
fi

# Deduplicate GitHub repos by full_name
all_gh="$(jq -c 'unique_by(.full_name)' <<<"$all_gh")"

# Gitea
all_gt='[]'
if [[ -n "$GITEA_USER" ]]; then
  info "- Gitea user: $GITEA_USER"
  gt_u_json="$(fetch_gitea_repos user "$GITEA_USER")"
  all_gt="$(printf '%s\n%s' "$all_gt" "$gt_u_json" | jq -c -s 'add')"
fi
if [[ -n "$GITEA_ORG" ]]; then
  info "- Gitea org: $GITEA_ORG"
  gt_o_json="$(fetch_gitea_repos org "$GITEA_ORG")"
  all_gt="$(printf '%s\n%s' "$all_gt" "$gt_o_json" | jq -c -s 'add')"
fi
# Deduplicate Gitea repos by full_name
all_gt="$(jq -c 'unique_by(.full_name)' <<<"$all_gt")"

# --------------- Build maps ---------------
info "Preparing comparison..."
GH_MAP="$(build_map_from_repolist <<<"$all_gh")"
GT_MAP="$(build_gitea_map_with_mirror <<<"$all_gt")"

# Write maps to temp files to avoid huge argv to jq
GH_MAP_FILE="$(mktemp)"
GT_MAP_FILE="$(mktemp)"
trap 'rm -f "$GH_MAP_FILE" "$GT_MAP_FILE"' EXIT
printf '%s' "$GH_MAP" > "$GH_MAP_FILE"
printf '%s' "$GT_MAP" > "$GT_MAP_FILE"

# --------------- Report ---------------
timestamp="$(date +%Y%m%d_%H%M%S)"
csv_path="$REPORT_DIR/migration_status_$timestamp.csv"

write_csv_report "$csv_path" "$GH_MAP_FILE" "$GT_MAP_FILE"
print_summary "$GH_MAP_FILE" "$GT_MAP_FILE"

echo
info "CSV report written to: $csv_path"

# Also list missing repos (names) for quick view
missing_list="$(jq -r \
  --slurpfile gt "$GT_MAP_FILE" \
  'keys[] as $k | select(($gt[0] | has($k)) | not) | $k' "$GH_MAP_FILE")"
if [[ -n "$missing_list" ]]; then
  echo
  info "Missing on Gitea (by repo name):"
  echo "$missing_list" | sed 's/^/  - /'
fi

exit 0