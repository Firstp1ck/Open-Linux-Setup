#!/usr/bin/env bash
#
# netcheck.sh - diagnose connectivity to a given host/service
# Usage: ./netcheck.sh
#
# Requires: bash, gum, ping, dig, curl, traceroute or tracepath

set -u

TIMEOUT_CONNECT=10
PING_COUNT=3

# Colors for gum
COLOR_OK="212"      # Green
COLOR_FAIL="196"    # Red
COLOR_WARN="214"    # Orange
COLOR_INFO="81"     # Cyan
COLOR_SKIP="245"    # Gray
COLOR_CAUSE="201"   # Magenta
COLOR_HINT="220"    # Yellow
COLOR_NOTE="147"    # Light purple
COLOR_HEADER="99"   # Purple
COLOR_BLOCK="160"   # Dark red for blocking indicators

# Blocking detection globals
BLOCK_INDICATORS=()
UA_BLOCK_DETECTED=0
GEO_BLOCK_DETECTED=0
RATE_LIMIT_DETECTED=0
CAPTCHA_DETECTED=0
BOT_BLOCK_DETECTED=0
TLS_BLOCK_DETECTED=0

check_gum() {
  if ! command -v gum >/dev/null 2>&1; then
    echo "Error: gum is not installed."
    echo "Install it with: pacman -S gum  (Arch) or see https://github.com/charmbracelet/gum"
    exit 1
  fi
}

banner() {
  echo
  gum style \
    --foreground "$COLOR_HEADER" \
    --border double \
    --border-foreground "$COLOR_HEADER" \
    --padding "0 2" \
    --margin "0" \
    --bold \
    "$1"
  echo
}

status() {
  local level="$1"
  shift
  local color
  local icon

  case "$level" in
    OK)
      color="$COLOR_OK"
      icon="✓"
      ;;
    FAIL)
      color="$COLOR_FAIL"
      icon="✗"
      ;;
    WARN)
      color="$COLOR_WARN"
      icon="⚠"
      ;;
    INFO)
      color="$COLOR_INFO"
      icon="ℹ"
      ;;
    SKIP)
      color="$COLOR_SKIP"
      icon="○"
      ;;
    CAUSE)
      color="$COLOR_CAUSE"
      icon="⚡"
      ;;
    HINT)
      color="$COLOR_HINT"
      icon="💡"
      ;;
    NOTE)
      color="$COLOR_NOTE"
      icon="📝"
      ;;
    BLOCK)
      color="$COLOR_BLOCK"
      icon="🚫"
      ;;
    *)
      color="255"
      icon="•"
      ;;
  esac

  gum style --foreground "$color" "$icon $(printf '[%-6s]' "$level") $*"
}

detail() {
  gum style --foreground "250" --margin "0 0 0 4" "$*"
}

add_block_indicator() {
  BLOCK_INDICATORS+=("$1")
}

get_hostname() {
  banner "🌐 NETWORK DIAGNOSTIC TOOL"

  gum style --foreground "$COLOR_INFO" "Enter the hostname or domain to diagnose:"
  echo

  TARGET=$(gum input \
    --placeholder "e.g., archlinux.org, google.com" \
    --prompt "→ " \
    --prompt.foreground "$COLOR_HEADER" \
    --cursor.foreground "$COLOR_OK" \
    --width 50)

  if [[ -z "$TARGET" ]]; then
    gum style --foreground "$COLOR_FAIL" "✗ No hostname provided. Exiting."
    exit 1
  fi

  echo
  gum style --foreground "$COLOR_OK" "✓ Target set to: $TARGET"
}

detect_tools() {
  banner "🔧 CHECKING REQUIRED TOOLS"

  REQUIRED=(ping dig curl)
  OPTIONAL=(traceroute tracepath openssl mtr tcpdump ss nft iptables bc)
  MISSING=()
  MISSING_OPTIONAL=()

  for t in "${REQUIRED[@]}"; do
    if command -v "$t" >/dev/null 2>&1; then
      status "OK" "$t is available"
    else
      MISSING+=("$t")
      status "FAIL" "$t is NOT available"
    fi
  done

  local found_tracer=0
  for t in "${OPTIONAL[@]}"; do
    if command -v "$t" >/dev/null 2>&1; then
      status "OK" "$t is available"
      if [[ "$t" == "traceroute" || "$t" == "tracepath" ]]; then
        found_tracer=1
      fi
    else
      MISSING_OPTIONAL+=("$t")
    fi
  done

  if [[ $found_tracer -eq 0 ]]; then
    status "WARN" "Neither traceroute nor tracepath installed (route tests will be skipped)"
  fi

  if ((${#MISSING[@]} > 0)); then
    echo
    status "WARN" "Missing required tools: ${MISSING[*]} (some tests will be skipped)"
  fi
}

resolve_dns() {
  banner "🔍 DNS RESOLUTION"

  if ! command -v dig >/dev/null 2>&1; then
    status "SKIP" "dig not installed; skipping detailed DNS checks"
    DNS_OK=1
    return
  fi

  status "INFO" "Resolving A and AAAA records for $TARGET..."
  echo

  A_RECORDS=$(gum spin --spinner dot --title "Resolving IPv4 (A) records..." -- \
    bash -c "dig +short '$TARGET' A 2>/dev/null | sort -u")

  AAAA_RECORDS=$(gum spin --spinner dot --title "Resolving IPv6 (AAAA) records..." -- \
    bash -c "dig +short '$TARGET' AAAA 2>/dev/null | sort -u")

  if [[ -z "$A_RECORDS" && -z "$AAAA_RECORDS" ]]; then
    status "FAIL" "No A or AAAA records resolved. Possible DNS problem."
    DNS_OK=0
  else
    DNS_OK=1
    if [[ -n "$A_RECORDS" ]]; then
      status "OK" "IPv4 (A) records found:"
      echo "$A_RECORDS" | while read -r ip; do
        detail "→ $ip"
      done
    else
      status "INFO" "No IPv4 (A) records found"
    fi

    if [[ -n "$AAAA_RECORDS" ]]; then
      status "OK" "IPv6 (AAAA) records found:"
      echo "$AAAA_RECORDS" | while read -r ip; do
        detail "→ $ip"
      done
    else
      status "INFO" "No IPv6 (AAAA) records found"
    fi
  fi

  # DNS poisoning check - compare with Google DNS
  echo
  status "INFO" "Checking for DNS inconsistencies..."
  GOOGLE_DNS_RESULT=$(gum spin --spinner dot --title "Querying Google DNS (8.8.8.8)..." -- \
    bash -c "dig +short '$TARGET' A @8.8.8.8 2>/dev/null | sort -u")

  CLOUDFLARE_DNS_RESULT=$(gum spin --spinner dot --title "Querying Cloudflare DNS (1.1.1.1)..." -- \
    bash -c "dig +short '$TARGET' A @1.1.1.1 2>/dev/null | sort -u")

  if [[ -n "$A_RECORDS" && -n "$GOOGLE_DNS_RESULT" && -n "$CLOUDFLARE_DNS_RESULT" ]]; then
    # Check if all three DNS results are the same
    if [[ "$A_RECORDS" == "$GOOGLE_DNS_RESULT" && "$A_RECORDS" == "$CLOUDFLARE_DNS_RESULT" ]]; then
      status "OK" "DNS results consistent across resolvers"
    else
      status "WARN" "DNS results differ between resolvers"
      detail "Local DNS: $A_RECORDS"
      detail "Google DNS: $GOOGLE_DNS_RESULT"
      detail "Cloudflare DNS: $CLOUDFLARE_DNS_RESULT"
      add_block_indicator "DNS results differ between resolvers (possible DNS filtering)"
    fi
  fi
}

ping_tests() {
  banner "📡 PING TESTS"

  if ! command -v ping >/dev/null 2>&1; then
    status "SKIP" "ping not installed; skipping ICMP tests"
    return
  fi

  # IPv4 ping
  status "INFO" "Testing IPv4 connectivity..."
  if gum spin --spinner dot --title "Pinging $TARGET over IPv4..." -- \
    bash -c "ping -4 -c $PING_COUNT -W 2 '$TARGET' >/dev/null 2>&1"; then
    status "OK" "IPv4 ping succeeded (host reachable over IPv4)"
    PING4_OK=1
  else
    status "WARN" "IPv4 ping failed (ICMP may be blocked or IPv4 routing problem)"
    PING4_OK=0
  fi

  # IPv6 ping
  status "INFO" "Testing IPv6 connectivity..."
  if gum spin --spinner dot --title "Pinging $TARGET over IPv6..." -- \
    bash -c "ping -6 -c $PING_COUNT -W 2 '$TARGET' >/dev/null 2>&1"; then
    status "OK" "IPv6 ping succeeded (host reachable over IPv6)"
    PING6_OK=1
  else
    status "WARN" "IPv6 ping failed (ICMPv6 may be blocked or IPv6 routing problem)"
    PING6_OK=0
  fi
}

curl_tests() {
  banner "🌍 HTTP(S) CONNECTIVITY"

  if ! command -v curl >/dev/null 2>&1; then
    status "SKIP" "curl not installed; skipping HTTP(S) checks"
    CURL4_OK=0
    CURL6_OK=0
    return
  fi

  # Force IPv4
  status "INFO" "Testing HTTPS over IPv4..."
  CURL4_OUTPUT=$(gum spin --spinner dot --title "Connecting to https://$TARGET via IPv4..." -- \
    bash -c "curl -4 -I -m $TIMEOUT_CONNECT -sS -w '%{http_code} %{remote_ip} %{remote_port}\n' 'https://$TARGET' -o /dev/null 2>&1")
  CURL4_RC=$?

  if [[ $CURL4_RC -eq 0 ]]; then
    status "OK" "IPv4 HTTPS succeeded"
    detail "Response: $CURL4_OUTPUT"
    CURL4_OK=1
  else
    status "FAIL" "IPv4 HTTPS failed (curl exit $CURL4_RC)"
    detail "Error: $CURL4_OUTPUT"
    CURL4_OK=0
  fi

  # Force IPv6
  status "INFO" "Testing HTTPS over IPv6..."
  CURL6_OUTPUT=$(gum spin --spinner dot --title "Connecting to https://$TARGET via IPv6..." -- \
    bash -c "curl -6 -I -m $TIMEOUT_CONNECT -sS -w '%{http_code} %{remote_ip} %{remote_port}\n' 'https://$TARGET' -o /dev/null 2>&1")
  CURL6_RC=$?

  if [[ $CURL6_RC -eq 0 ]]; then
    status "OK" "IPv6 HTTPS succeeded"
    detail "Response: $CURL6_OUTPUT"
    CURL6_OK=1
  else
    status "FAIL" "IPv6 HTTPS failed (curl exit $CURL6_RC)"
    detail "Error: $CURL6_OUTPUT"
    CURL6_OK=0
  fi
}

# NEW: User-Agent based blocking detection
user_agent_tests() {
  banner "🤖 USER-AGENT BLOCKING DETECTION"

  if ! command -v curl >/dev/null 2>&1; then
    status "SKIP" "curl not installed; skipping User-Agent tests"
    return
  fi

  # Define different User-Agent strings to test
  declare -A USER_AGENTS=(
    ["Chrome"]="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    ["Firefox"]="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0"
    ["Safari"]="Mozilla/5.0 (Macintosh; Intel Mac OS X 14_1) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Safari/605.1.15"
    ["curl"]="curl/8.0.0"
    ["wget"]="Wget/1.21"
    ["Bot"]="Googlebot/2.1 (+http://www.google.com/bot.html)"
    ["Empty"]=""
  )

  local results=()
  local blocked_uas=()

  for ua_name in "${!USER_AGENTS[@]}"; do
    local ua="${USER_AGENTS[$ua_name]}"
    local result

    result=$(gum spin --spinner dot --title "Testing with $ua_name User-Agent..." -- \
      bash -c "curl -s -o /dev/null -w '%{http_code}' -m $TIMEOUT_CONNECT -A '$ua' 'https://$TARGET' 2>/dev/null")

    if [[ "$result" == "200" || "$result" == "301" || "$result" == "302" ]]; then
      status "OK" "$ua_name: HTTP $result"
      results+=("$ua_name:OK")
    elif [[ "$result" == "403" || "$result" == "406" || "$result" == "429" ]]; then
      status "BLOCK" "$ua_name: HTTP $result (potentially blocked)"
      blocked_uas+=("$ua_name")
      results+=("$ua_name:BLOCKED")
    elif [[ "$result" == "000" ]]; then
      status "FAIL" "$ua_name: Connection failed"
      results+=("$ua_name:FAIL")
    else
      status "WARN" "$ua_name: HTTP $result"
      results+=("$ua_name:$result")
    fi
  done

  # Analyze results
  if [[ ${#blocked_uas[@]} -gt 0 ]]; then
    echo
    status "BLOCK" "User-Agent based filtering detected!"
    detail "Blocked User-Agents: ${blocked_uas[*]}"
    add_block_indicator "User-Agent filtering: ${blocked_uas[*]} blocked"
    UA_BLOCK_DETECTED=1
  fi
}

# NEW: Response header analysis for blocking indicators
header_analysis() {
  banner "📋 RESPONSE HEADER ANALYSIS"

  if ! command -v curl >/dev/null 2>&1; then
    status "SKIP" "curl not installed; skipping header analysis"
    return
  fi

  status "INFO" "Fetching response headers..."
  HEADERS=$(gum spin --spinner dot --title "Analyzing response headers..." -- \
    bash -c "curl -sI -m $TIMEOUT_CONNECT 'https://$TARGET' 2>/dev/null")

  if [[ -z "$HEADERS" ]]; then
    status "FAIL" "Could not retrieve headers"
    return
  fi

  # Check for blocking-related headers
  echo
  status "INFO" "Checking for security/blocking headers..."

  # X-Frame-Options
  if echo "$HEADERS" | grep -qi "X-Frame-Options"; then
    local xfo
    xfo=$(echo "$HEADERS" | grep -i "X-Frame-Options" | head -1)
    status "INFO" "X-Frame-Options: $(echo "$xfo" | cut -d: -f2-)"
  fi

  # Rate limiting headers
  if echo "$HEADERS" | grep -qi "X-RateLimit\|RateLimit"; then
    status "WARN" "Rate limiting headers detected"
    echo "$HEADERS" | grep -i "RateLimit" | while read -r line; do
      detail "$line"
    done
    add_block_indicator "Rate limiting headers present"
  fi

  # Cloudflare
  if echo "$HEADERS" | grep -qi "cf-ray\|cloudflare"; then
    status "INFO" "Cloudflare protection detected"
    add_block_indicator "Site uses Cloudflare (may have bot protection)"
  fi

  # AWS WAF
  if echo "$HEADERS" | grep -qi "x-amz-cf\|x-amzn"; then
    status "INFO" "AWS CloudFront/WAF detected"
    add_block_indicator "Site uses AWS CloudFront/WAF"
  fi

  # Akamai
  if echo "$HEADERS" | grep -qi "akamai\|x-akamai"; then
    status "INFO" "Akamai CDN/WAF detected"
    add_block_indicator "Site uses Akamai"
  fi

  # Sucuri
  if echo "$HEADERS" | grep -qi "x-sucuri"; then
    status "INFO" "Sucuri WAF detected"
    add_block_indicator "Site uses Sucuri WAF"
  fi

  # Check for unusual server responses
  local server_header
  server_header=$(echo "$HEADERS" | grep -i "^Server:" | head -1)
  if [[ -n "$server_header" ]]; then
    status "INFO" "Server: $(echo "$server_header" | cut -d: -f2-)"
  fi

  # Check HTTP status
  local http_status
  http_status=$(echo "$HEADERS" | head -1 | awk '{print $2}')
  case "$http_status" in
    403)
      status "BLOCK" "HTTP 403 Forbidden - Access denied"
      add_block_indicator "HTTP 403 Forbidden response"
      ;;
    406)
      status "BLOCK" "HTTP 406 Not Acceptable - Request rejected"
      add_block_indicator "HTTP 406 Not Acceptable response"
      ;;
    429)
      status "BLOCK" "HTTP 429 Too Many Requests - Rate limited"
      RATE_LIMIT_DETECTED=1
      add_block_indicator "HTTP 429 Rate limited"
      ;;
    451)
      status "BLOCK" "HTTP 451 Unavailable For Legal Reasons - Geo/legal block"
      GEO_BLOCK_DETECTED=1
      add_block_indicator "HTTP 451 Legal/Geo restriction"
      ;;
    503)
      status "WARN" "HTTP 503 Service Unavailable - May indicate WAF blocking"
      add_block_indicator "HTTP 503 (possible WAF block)"
      ;;
  esac
}

# NEW: Response body analysis for block pages
body_analysis() {
  banner "📄 RESPONSE BODY ANALYSIS"

  if ! command -v curl >/dev/null 2>&1; then
    status "SKIP" "curl not installed; skipping body analysis"
    return
  fi

  status "INFO" "Analyzing response body for block indicators..."

  BODY=$(gum spin --spinner dot --title "Fetching page content..." -- \
    bash -c "curl -s -m $TIMEOUT_CONNECT -L 'https://$TARGET' 2>/dev/null | head -c 50000")

  if [[ -z "$BODY" ]]; then
    status "WARN" "Could not retrieve page body"
    return
  fi

  local found_indicators=0

  # Check for CAPTCHA indicators
  if echo "$BODY" | grep -qiE "captcha|recaptcha|hcaptcha|turnstile|challenge|verify.+human|are.+you.+human|prove.+human|bot.+check"; then
    status "BLOCK" "CAPTCHA/Challenge detected in response"
    add_block_indicator "CAPTCHA challenge present"
    CAPTCHA_DETECTED=1
    found_indicators=1
  fi

  # Check for access denied messages
  if echo "$BODY" | grep -qiE "access.+denied|forbidden|blocked|not.+allowed|permission.+denied|unauthorized"; then
    status "BLOCK" "Access denied message detected"
    add_block_indicator "Access denied message in page"
    found_indicators=1
  fi

  # Check for geo-blocking messages
  if echo "$BODY" | grep -qiE "not.+available.+in.+your.+(country|region)|geo.?restrict|location.+not.+supported|country.+blocked"; then
    status "BLOCK" "Geographic restriction message detected"
    add_block_indicator "Geographic restriction message"
    GEO_BLOCK_DETECTED=1
    found_indicators=1
  fi

  # Check for rate limiting messages
  if echo "$BODY" | grep -qiE "rate.+limit|too.+many.+requests|slow.+down|try.+again.+later"; then
    status "BLOCK" "Rate limiting message detected"
    add_block_indicator "Rate limiting message"
    RATE_LIMIT_DETECTED=1
    found_indicators=1
  fi

  # Check for bot detection messages
  if echo "$BODY" | grep -qiE "bot.+detected|automated.+access|suspicious.+activity|unusual.+traffic|security.+check"; then
    status "BLOCK" "Bot/automation detection message found"
    add_block_indicator "Bot detection triggered"
    BOT_BLOCK_DETECTED=1
    found_indicators=1
  fi

  # Check for VPN/Proxy blocking
  if echo "$BODY" | grep -qiE "vpn.+detected|proxy.+detected|anonymizer|tor.+exit"; then
    status "BLOCK" "VPN/Proxy detection message found"
    add_block_indicator "VPN/Proxy blocking detected"
    found_indicators=1
  fi

  # Check for JavaScript challenge (common in Cloudflare)
  if echo "$BODY" | grep -qiE "checking.+your.+browser|please.+wait|just.+a.+moment|ddos.+protection|ray.+id"; then
    status "WARN" "JavaScript challenge page detected (DDoS protection)"
    add_block_indicator "JavaScript challenge (DDoS protection)"
    found_indicators=1
  fi

  # Check for IP blocking messages
  if echo "$BODY" | grep -qiE "ip.+blocked|ip.+banned|your.+ip|blacklist"; then
    status "BLOCK" "IP blocking message detected"
    add_block_indicator "IP-based blocking message"
    found_indicators=1
  fi

  if [[ $found_indicators -eq 0 ]]; then
    status "OK" "No obvious blocking indicators found in page content"
  fi
}

# NEW: TLS/SSL analysis
tls_analysis() {
  banner "🔐 TLS/SSL ANALYSIS"

  if ! command -v openssl >/dev/null 2>&1; then
    status "SKIP" "openssl not installed; skipping TLS analysis"
    return
  fi

  if ! command -v timeout >/dev/null 2>&1; then
    status "SKIP" "timeout command not available; skipping TLS analysis"
    return
  fi

  status "INFO" "Testing TLS connectivity and certificate..."

  # Test TLS connection with timeout to prevent hanging
  TLS_INFO=$(gum spin --spinner dot --title "Analyzing TLS connection..." -- \
    bash -c "timeout 10 bash -c 'echo Q | openssl s_client -connect \"$TARGET:443\" -servername \"$TARGET\" 2>/dev/null' || echo ''")

  if [[ -z "$TLS_INFO" ]]; then
    status "FAIL" "Could not establish TLS connection (timeout or refused)"
    add_block_indicator "TLS connection failed"
    TLS_BLOCK_DETECTED=1
    return
  fi

  # Check if connection was actually successful
  if ! echo "$TLS_INFO" | grep -q "CONNECTED"; then
    status "FAIL" "TLS connection failed"
    add_block_indicator "TLS connection failed"
    TLS_BLOCK_DETECTED=1
    return
  fi

  # Extract TLS version
  local tls_version
  tls_version=$(echo "$TLS_INFO" | grep "Protocol" | awk '{print $3}')
  if [[ -n "$tls_version" ]]; then
    status "OK" "TLS Version: $tls_version"
  fi

  # Check certificate
  local cert_subject
  cert_subject=$(echo "$TLS_INFO" | grep "subject=" | head -1)
  if [[ -n "$cert_subject" ]]; then
    status "INFO" "Certificate: ${cert_subject//subject=/}"
  fi

  # Check for certificate errors
  if echo "$TLS_INFO" | grep -qi "certificate verify failed\|self.signed\|expired\|revoked"; then
    status "WARN" "TLS certificate issues detected"
    add_block_indicator "TLS certificate problems"
  fi

  # Test different TLS versions
  echo
  status "INFO" "Testing TLS version compatibility..."

  for tls_ver in "tls1_2" "tls1_3"; do
    local result
    result=$(gum spin --spinner dot --title "Testing $tls_ver..." -- \
      bash -c "timeout 5 bash -c 'echo Q | openssl s_client -connect \"$TARGET:443\" -servername \"$TARGET\" -$tls_ver 2>&1' | grep -c 'CONNECTED' || echo 0")

    if [[ "$result" -gt 0 ]]; then
      status "OK" "$tls_ver: Supported"
    else
      status "INFO" "$tls_ver: Not supported or blocked"
    fi
  done
}

# NEW: Rate limiting detection
rate_limit_test() {
  banner "⏱️  RATE LIMITING DETECTION"

  if ! command -v curl >/dev/null 2>&1; then
    status "SKIP" "curl not installed; skipping rate limit tests"
    return
  fi

  status "INFO" "Sending rapid requests to detect rate limiting..."

  local success_count=0
  local blocked_count=0
  local error_count=0

  for _ in {1..10}; do
    local result
    result=$(curl -s -o /dev/null -w '%{http_code}' -m 5 "https://$TARGET" 2>/dev/null)

    case "$result" in
      200|301|302)
        ((success_count++))
        ;;
      429|503)
        ((blocked_count++))
        ;;
      *)
        ((error_count++))
        ;;
    esac

    # Small delay to avoid being too aggressive
    sleep 0.1
  done

  echo
  status "INFO" "Results: $success_count success, $blocked_count blocked, $error_count errors"

  if [[ $blocked_count -gt 0 ]]; then
    status "BLOCK" "Rate limiting triggered after rapid requests"
    add_block_indicator "Rate limiting triggered ($blocked_count/10 requests blocked)"
    RATE_LIMIT_DETECTED=1
  elif [[ $success_count -eq 10 ]]; then
    status "OK" "No rate limiting detected for 10 rapid requests"
  else
    status "WARN" "Some requests failed (may indicate intermittent blocking)"
  fi
}

# NEW: Compare with known working site
baseline_comparison() {
  banner "📊 BASELINE COMPARISON"

  if ! command -v curl >/dev/null 2>&1; then
    status "SKIP" "curl not installed; skipping baseline comparison"
    return
  fi

  local baseline_sites=("google.com" "cloudflare.com" "github.com")
  local baseline_ok=0

  status "INFO" "Comparing connectivity with known-good sites..."
  echo

  for site in "${baseline_sites[@]}"; do
    local result
    result=$(gum spin --spinner dot --title "Testing $site..." -- \
      bash -c "curl -s -o /dev/null -w '%{http_code}' -m 5 'https://$site' 2>/dev/null")

    if [[ "$result" == "200" || "$result" == "301" || "$result" == "302" ]]; then
      status "OK" "$site: HTTP $result (reachable)"
      baseline_ok=1
    else
      status "FAIL" "$site: HTTP $result"
    fi
  done

  echo
  if [[ $baseline_ok -eq 1 && ${CURL4_OK:-0} -eq 0 && ${CURL6_OK:-0} -eq 0 ]]; then
    status "CAUSE" "Other sites work but $TARGET doesn't"
    detail "→ This strongly suggests $TARGET is specifically blocking your connection"
    detail "→ Or there's a specific routing issue to $TARGET"
    add_block_indicator "Other sites work but target doesn't (targeted blocking likely)"
  elif [[ $baseline_ok -eq 0 ]]; then
    status "CAUSE" "Baseline sites also fail"
    detail "→ This suggests a general connectivity issue, not site-specific blocking"
  fi
}

# NEW: Port variation testing
port_variation_test() {
  banner "🔌 PORT VARIATION TESTING"

  if ! command -v curl >/dev/null 2>&1; then
    status "SKIP" "curl not installed; skipping port tests"
    return
  fi

  status "INFO" "Testing different ports..."

  # Test port 80 (HTTP)
  local http_result
  http_result=$(gum spin --spinner dot --title "Testing HTTP (port 80)..." -- \
    bash -c "curl -s -o /dev/null -w '%{http_code}' -m $TIMEOUT_CONNECT 'http://$TARGET' 2>/dev/null")

  if [[ "$http_result" == "200" || "$http_result" == "301" || "$http_result" == "302" ]]; then
    status "OK" "HTTP (port 80): HTTP $http_result"
  else
    status "WARN" "HTTP (port 80): HTTP $http_result"
  fi

  # Test port 443 (HTTPS)
  local https_result
  https_result=$(gum spin --spinner dot --title "Testing HTTPS (port 443)..." -- \
    bash -c "curl -s -o /dev/null -w '%{http_code}' -m $TIMEOUT_CONNECT 'https://$TARGET' 2>/dev/null")

  if [[ "$https_result" == "200" || "$https_result" == "301" || "$https_result" == "302" ]]; then
    status "OK" "HTTPS (port 443): HTTP $https_result"
  else
    status "WARN" "HTTPS (port 443): HTTP $https_result"
  fi

  # Compare HTTP vs HTTPS
  if [[ "$http_result" =~ ^(200|301|302)$ && ! "$https_result" =~ ^(200|301|302)$ ]]; then
    status "HINT" "HTTP works but HTTPS doesn't - possible TLS filtering"
    add_block_indicator "HTTP works but HTTPS blocked (TLS filtering)"
    TLS_BLOCK_DETECTED=1
  elif [[ ! "$http_result" =~ ^(200|301|302)$ && "$https_result" =~ ^(200|301|302)$ ]]; then
    status "INFO" "HTTPS works but HTTP doesn't - site may force HTTPS"
  fi

  # Test alternative HTTPS port 8443 if standard ports fail
  if [[ ! "$https_result" =~ ^(200|301|302)$ ]]; then
    local alt_result
    alt_result=$(gum spin --spinner dot --title "Testing alternate HTTPS (port 8443)..." -- \
      bash -c "curl -s -o /dev/null -w '%{http_code}' -m $TIMEOUT_CONNECT 'https://$TARGET:8443' 2>/dev/null")

    if [[ "$alt_result" =~ ^(200|301|302)$ ]]; then
      status "OK" "Alternate HTTPS (port 8443): HTTP $alt_result"
      status "HINT" "Standard port 443 blocked but 8443 works"
      add_block_indicator "Port 443 blocked but 8443 works"
    fi
  fi
}

# NEW: Redirect chain analysis
redirect_analysis() {
  banner "🔀 REDIRECT CHAIN ANALYSIS"

  if ! command -v curl >/dev/null 2>&1; then
    status "SKIP" "curl not installed; skipping redirect analysis"
    return
  fi

  status "INFO" "Analyzing redirect chain..."

  REDIRECTS=$(gum spin --spinner dot --title "Following redirects..." -- \
    bash -c "curl -sLI -m $TIMEOUT_CONNECT 'https://$TARGET' 2>/dev/null | grep -i '^location:' | head -10")

  if [[ -z "$REDIRECTS" ]]; then
    status "OK" "No redirects detected"
    return
  fi

  status "INFO" "Redirect chain:"
  echo "$REDIRECTS" | while read -r redirect; do
    local url
    # Remove "Location: " or "location: " prefix (case-insensitive, with optional spaces)
    url="${redirect#*: }"
    url="${url#"${url%%[![:space:]]*}"}"
    detail "→ $url"

    # Check for suspicious redirect patterns
    if echo "$url" | grep -qiE "block|captcha|challenge|verify|banned|denied|error"; then
      status "BLOCK" "Redirect to potential block page detected"
      add_block_indicator "Redirect to block/challenge page: $url"
    fi
  done

  # Check final destination
  FINAL_URL=$(gum spin --spinner dot --title "Checking final destination..." -- \
    bash -c "curl -sL -o /dev/null -w '%{url_effective}' -m $TIMEOUT_CONNECT 'https://$TARGET' 2>/dev/null")

  if [[ -n "$FINAL_URL" ]]; then
    status "INFO" "Final URL: $FINAL_URL"

    # Check if redirected to a different domain
    local final_domain
    final_domain=$(echo "$FINAL_URL" | sed -E 's|https?://([^/]+).*|\1|')
    if [[ "$final_domain" != "$TARGET" && "$final_domain" != "www.$TARGET" ]]; then
      status "WARN" "Redirected to different domain: $final_domain"
      add_block_indicator "Redirected to different domain: $final_domain"
    fi
  fi
}

# NEW: Connection timing analysis
timing_analysis() {
  banner "⏰ CONNECTION TIMING ANALYSIS"

  if ! command -v curl >/dev/null 2>&1; then
    status "SKIP" "curl not installed; skipping timing analysis"
    return
  fi

  status "INFO" "Measuring connection timing..."

  local timing_output
  timing_output=$(gum spin --spinner dot --title "Analyzing connection timing..." -- \
    bash -c "curl -s -o /dev/null -w 'dns:%{time_namelookup}s connect:%{time_connect}s ttfb:%{time_starttransfer}s total:%{time_total}s' -m $TIMEOUT_CONNECT 'https://$TARGET' 2>/dev/null")

  if [[ -z "$timing_output" ]]; then
    status "FAIL" "Could not measure timing"
    return
  fi

  # Parse timing values
  local dns_time connect_time ttfb total_time
  dns_time=$(echo "$timing_output" | grep -oP 'dns:\K[0-9.]+')
  connect_time=$(echo "$timing_output" | grep -oP 'connect:\K[0-9.]+')
  ttfb=$(echo "$timing_output" | grep -oP 'ttfb:\K[0-9.]+')
  total_time=$(echo "$timing_output" | grep -oP 'total:\K[0-9.]+')

  status "INFO" "DNS lookup: ${dns_time}s"
  status "INFO" "TCP connect: ${connect_time}s"
  status "INFO" "Time to first byte: ${ttfb}s"
  status "INFO" "Total time: ${total_time}s"

  # Check for anomalies
  if (( $(echo "$ttfb > 5" | bc -l 2>/dev/null || echo 0) )); then
    status "WARN" "High time to first byte (>5s) - possible throttling"
    add_block_indicator "High TTFB ($ttfb s) - possible throttling"
  fi

  if (( $(echo "$dns_time > 2" | bc -l 2>/dev/null || echo 0) )); then
    status "WARN" "Slow DNS resolution (>2s)"
  fi

  # Compare with baseline
  local baseline_total
  baseline_total=$(gum spin --spinner dot --title "Comparing with baseline (google.com)..." -- \
    bash -c "curl -s -o /dev/null -w '%{time_total}' -m 10 'https://google.com' 2>/dev/null")

  if [[ -n "$baseline_total" && -n "$total_time" ]]; then
    local ratio
    ratio=$(echo "scale=2; $total_time / $baseline_total" | bc 2>/dev/null || echo "0")
    if (( $(echo "$ratio > 5" | bc -l 2>/dev/null || echo 0) )); then
      status "WARN" "Target is ${ratio}x slower than baseline"
      add_block_indicator "Response ${ratio}x slower than baseline (possible throttling)"
    fi
  fi
}

route_tests() {
  banner "🛤️  ROUTING (TRACEROUTE)"

  local tracer=""

  if command -v traceroute >/dev/null 2>&1; then
    tracer="traceroute"
  elif command -v tracepath >/dev/null 2>&1; then
    tracer="tracepath"
  else
    status "SKIP" "Neither traceroute nor tracepath installed; skipping route diagnostics"
    return
  fi

  status "INFO" "Tracing IPv4 route to $TARGET..."
  gum spin --spinner globe --title "Tracing IPv4 route (this may take a while)..." -- \
    bash -c "$tracer -4 '$TARGET' 2>&1 > /tmp/trace4_$$.txt"

  if [[ -f "/tmp/trace4_$$.txt" ]]; then
    gum style --foreground "250" --border normal --border-foreground "240" --padding "1" \
      "$(cat /tmp/trace4_$$.txt)"
    rm -f "/tmp/trace4_$$.txt"
  fi

  echo
  status "INFO" "Tracing IPv6 route to $TARGET..."
  gum spin --spinner globe --title "Tracing IPv6 route (this may take a while)..." -- \
    bash -c "$tracer -6 '$TARGET' 2>&1 > /tmp/trace6_$$.txt"

  if [[ -f "/tmp/trace6_$$.txt" ]]; then
    gum style --foreground "250" --border normal --border-foreground "240" --padding "1" \
      "$(cat /tmp/trace6_$$.txt)"
    rm -f "/tmp/trace6_$$.txt"
  fi
}

# MTR (My Traceroute) analysis - combines ping and traceroute with statistics
mtr_analysis() {
  banner "📈 MTR NETWORK PATH ANALYSIS"

  if ! command -v mtr >/dev/null 2>&1; then
    status "SKIP" "mtr not installed; skipping MTR analysis"
    detail "Install with: pacman -S mtr (Arch) or apt install mtr (Debian/Ubuntu)"
    return
  fi

  local mtr_count=10
  status "INFO" "Running MTR analysis ($mtr_count probes per hop)..."
  echo

  # Run MTR in report mode with statistics
  local mtr_output
  mtr_output=$(gum spin --spinner globe --title "Running MTR analysis (this takes ~30 seconds)..." -- \
    bash -c "timeout 60 mtr -r -c $mtr_count -w '$TARGET' 2>/dev/null || echo 'MTR_TIMEOUT'")

  if [[ "$mtr_output" == "MTR_TIMEOUT" || -z "$mtr_output" ]]; then
    status "FAIL" "MTR analysis timed out or failed"
    return
  fi

  # Display raw MTR output
  gum style --foreground "250" --border normal --border-foreground "240" --padding "1" \
    "$mtr_output"

  echo
  status "INFO" "Analyzing MTR results..."

  # Parse and analyze the MTR output
  local problem_hops=()
  local high_latency_hops=()
  local packet_loss_hops=()

  while IFS= read -r line; do
    # Skip header lines
    if [[ "$line" =~ ^HOST:|^Start:|^\|-- ]]; then
      continue
    fi

    # Extract hop number, loss%, and avg latency
    # MTR format: "  1.|-- gateway   0.0%    10    0.3   0.3   0.2   0.4   0.0"
    if [[ "$line" =~ ^[[:space:]]*([0-9]+)\.\|--[[:space:]]+([^[:space:]]+)[[:space:]]+([0-9.]+)%[[:space:]]+[0-9]+[[:space:]]+([0-9.]+) ]]; then
      local hop_num="${BASH_REMATCH[1]}"
      local hop_host="${BASH_REMATCH[2]}"
      local loss="${BASH_REMATCH[3]}"
      local avg_latency="${BASH_REMATCH[4]}"

      # Check for packet loss > 5%
      if (( $(echo "$loss > 5" | bc -l 2>/dev/null || echo 0) )); then
        packet_loss_hops+=("Hop $hop_num ($hop_host): ${loss}% packet loss")
        problem_hops+=("$hop_num")
      fi

      # Check for high latency > 100ms
      if (( $(echo "$avg_latency > 100" | bc -l 2>/dev/null || echo 0) )); then
        high_latency_hops+=("Hop $hop_num ($hop_host): ${avg_latency}ms average latency")
      fi

      # Check for timeout/unreachable (???)
      if [[ "$hop_host" == "???" ]]; then
        problem_hops+=("$hop_num")
      fi
    fi
  done <<< "$mtr_output"

  # Report findings
  if [[ ${#packet_loss_hops[@]} -gt 0 ]]; then
    echo
    status "WARN" "Packet loss detected at ${#packet_loss_hops[@]} hop(s):"
    for hop in "${packet_loss_hops[@]}"; do
      detail "→ $hop"
    done
    add_block_indicator "MTR detected packet loss at ${#packet_loss_hops[@]} hops"
  fi

  if [[ ${#high_latency_hops[@]} -gt 0 ]]; then
    echo
    status "WARN" "High latency (>100ms) detected at ${#high_latency_hops[@]} hop(s):"
    for hop in "${high_latency_hops[@]}"; do
      detail "→ $hop"
    done
    add_block_indicator "MTR detected high latency at ${#high_latency_hops[@]} hops"
  fi

  # Check for 100% packet loss at final hop (site blocking)
  local final_line
  final_line=$(echo "$mtr_output" | tail -1)
  if [[ "$final_line" =~ 100\.0% ]]; then
    status "BLOCK" "100% packet loss at destination - site may be blocking ICMP"
    add_block_indicator "MTR shows 100% packet loss at destination"
  fi

  if [[ ${#problem_hops[@]} -eq 0 && ${#high_latency_hops[@]} -eq 0 ]]; then
    status "OK" "Network path looks healthy - no significant issues detected"
  fi

  # Provide interpretation
  echo
  status "INFO" "MTR Legend:"
  detail "Loss%: Packet loss percentage (>5% indicates problems)"
  detail "Snt: Packets sent"
  detail "Last/Avg/Best/Wrst: Latency in milliseconds"
  detail "StDev: Latency variation (high = unstable connection)"
}

# tcpdump packet capture and analysis
tcpdump_analysis() {
  banner "🔬 PACKET CAPTURE ANALYSIS (tcpdump)"

  if ! command -v tcpdump >/dev/null 2>&1; then
    status "SKIP" "tcpdump not installed; skipping packet analysis"
    detail "Install with: pacman -S tcpdump (Arch) or apt install tcpdump (Debian/Ubuntu)"
    return
  fi

  # Check if we have permission to capture
  if ! timeout 2 tcpdump -D >/dev/null 2>&1; then
    status "WARN" "tcpdump requires root privileges for full analysis"
    detail "Run script with sudo for packet capture"

    # Try alternative analysis without capture
    status "INFO" "Running limited analysis without packet capture..."
    tcpdump_limited_analysis
    return
  fi

  # Resolve target IP for capture filter
  local target_ip
  target_ip=$(dig +short "$TARGET" A 2>/dev/null | head -1)

  if [[ -z "$target_ip" ]]; then
    status "FAIL" "Could not resolve target IP for packet capture"
    return
  fi

  status "INFO" "Capturing packets to $TARGET ($target_ip)..."
  detail "Capturing TCP handshake and initial connection..."

  local capture_file="/tmp/tcpdump_$$_capture.pcap"
  local capture_output="/tmp/tcpdump_$$_output.txt"

  # Start packet capture in background, capture for connection analysis
  gum spin --spinner dot --title "Capturing packets (5 seconds)..." -- \
    bash -c "timeout 5 tcpdump -i any -c 50 -w '$capture_file' 'host $target_ip and port 443' 2>/dev/null &
             sleep 1
             curl -s -o /dev/null -m 3 'https://$TARGET' 2>/dev/null
             sleep 3
             wait" 2>/dev/null

  if [[ ! -f "$capture_file" || ! -s "$capture_file" ]]; then
    status "WARN" "No packets captured - connection may be blocked before reaching interface"
    add_block_indicator "tcpdump captured no packets (possible local firewall block)"
    return
  fi

  # Analyze the capture
  status "INFO" "Analyzing captured packets..."

  # Read capture and analyze
  local packet_analysis
  packet_analysis=$(tcpdump -r "$capture_file" -nn 2>/dev/null)

  # Count packet types
  local syn_count ack_count rst_count fin_count total_packets
  syn_count=$(echo "$packet_analysis" | grep -c "Flags \[S\]" || echo 0)
  ack_count=$(echo "$packet_analysis" | grep -c "Flags \[.\]" || echo 0)
  rst_count=$(echo "$packet_analysis" | grep -c "Flags \[R" || echo 0)
  fin_count=$(echo "$packet_analysis" | grep -c "Flags \[F" || echo 0)
  total_packets=$(echo "$packet_analysis" | wc -l)

  echo
  status "INFO" "Packet statistics:"
  detail "Total packets captured: $total_packets"
  detail "SYN packets (connection attempts): $syn_count"
  detail "ACK packets (acknowledgments): $ack_count"
  detail "RST packets (resets): $rst_count"
  detail "FIN packets (connection close): $fin_count"

  # Analyze for blocking patterns
  echo
  status "INFO" "Connection analysis:"

  # Check for SYN without SYN-ACK (connection blocked)
  local synack_count
  synack_count=$(echo "$packet_analysis" | grep -c "Flags \[S.\]" || echo 0)

  if [[ $syn_count -gt 0 && $synack_count -eq 0 ]]; then
    status "BLOCK" "SYN packets sent but no SYN-ACK received"
    detail "→ Connection is being silently dropped (firewall/filter)"
    add_block_indicator "tcpdump: SYN packets dropped (no SYN-ACK response)"
  elif [[ $syn_count -gt 0 && $synack_count -gt 0 ]]; then
    status "OK" "TCP handshake completed successfully"
  fi

  # Check for RST packets (connection rejected)
  if [[ $rst_count -gt 0 ]]; then
    status "WARN" "RST (reset) packets detected"
    detail "→ Connection was forcibly terminated"

    # Check if RST came from target or intermediate
    local rst_from_target
    rst_from_target=$(echo "$packet_analysis" | grep "Flags \[R" | grep -c "$target_ip" || echo 0)

    if [[ $rst_from_target -gt 0 ]]; then
      status "BLOCK" "RST packets originated from target server"
      detail "→ Server is actively rejecting connections"
      add_block_indicator "tcpdump: Server sending RST (active rejection)"
    else
      status "WARN" "RST packets from intermediate device"
      detail "→ Firewall or middlebox may be terminating connection"
      add_block_indicator "tcpdump: Intermediate RST (possible firewall intervention)"
    fi
  fi

  # Check for ICMP unreachable messages
  local icmp_unreachable
  icmp_unreachable=$(tcpdump -r "$capture_file" -nn 2>/dev/null | grep -c "ICMP.*unreachable" || echo 0)

  if [[ $icmp_unreachable -gt 0 ]]; then
    status "BLOCK" "ICMP unreachable messages received"
    detail "→ Destination or port is explicitly blocked"
    add_block_indicator "tcpdump: ICMP unreachable received"
  fi

  # Check TLS handshake if we got past TCP
  if [[ $synack_count -gt 0 ]]; then
    local tls_hello
    tls_hello=$(echo "$packet_analysis" | grep -c "TLS\|SSL\|Client Hello" || echo 0)

    if [[ $tls_hello -gt 0 ]]; then
      status "OK" "TLS handshake initiated"
    elif [[ $total_packets -gt 5 ]]; then
      status "INFO" "Connection established but TLS details not visible in summary"
    fi
  fi

  # Show sample of captured packets
  echo
  status "INFO" "Sample of captured packets:"
  echo "$packet_analysis" | head -10 | while read -r line; do
    detail "$line"
  done

  if [[ $total_packets -gt 10 ]]; then
    detail "... ($((total_packets - 10)) more packets)"
  fi

  # Cleanup
  rm -f "$capture_file" "$capture_output"
}

# Limited tcpdump analysis without capture (no root)
tcpdump_limited_analysis() {
  status "INFO" "Performing connection state analysis..."

  # Use ss/netstat to check connection states
  if command -v ss >/dev/null 2>&1; then
    # Attempt a connection and check state
    local target_ip
    target_ip=$(dig +short "$TARGET" A 2>/dev/null | head -1)

    if [[ -z "$target_ip" ]]; then
      status "FAIL" "Could not resolve target IP"
      return
    fi

    # Start a background connection attempt
    timeout 5 bash -c "curl -s -o /dev/null 'https://$TARGET' 2>/dev/null" &
    local curl_pid=$!
    sleep 1

    # Check connection state
    local conn_state
    conn_state=$(ss -tn state all "dst $target_ip" 2>/dev/null | grep -v "State" | head -5)

    if [[ -n "$conn_state" ]]; then
      status "INFO" "Active connection states to $target_ip:"
      echo "$conn_state" | while read -r line; do
        detail "$line"
      done

      # Analyze states
      if echo "$conn_state" | grep -q "SYN-SENT"; then
        status "WARN" "Connection stuck in SYN-SENT state"
        detail "→ SYN packets may not be reaching destination"
        add_block_indicator "Connection stuck in SYN-SENT (possible filtering)"
      fi

      if echo "$conn_state" | grep -q "ESTAB"; then
        status "OK" "Established connections detected"
      fi

      if echo "$conn_state" | grep -q "TIME-WAIT\|CLOSE-WAIT"; then
        status "INFO" "Connection closing states detected (normal)"
      fi
    else
      status "INFO" "No active connections to target"
    fi

    wait $curl_pid 2>/dev/null
  fi

  # Check for firewall rules that might affect the connection
  echo
  status "INFO" "Checking local firewall rules..."

  if command -v iptables >/dev/null 2>&1; then
    local drop_rules
    drop_rules=$(iptables -L -n 2>/dev/null | grep -i "drop\|reject" | head -5)

    if [[ -n "$drop_rules" ]]; then
      status "WARN" "Local firewall has DROP/REJECT rules:"
      echo "$drop_rules" | while read -r rule; do
        detail "$rule"
      done
    else
      status "OK" "No obvious DROP/REJECT rules in iptables"
    fi
  fi

  if command -v nft >/dev/null 2>&1; then
    local nft_drops
    nft_drops=$(nft list ruleset 2>/dev/null | grep -i "drop\|reject" | head -5)

    if [[ -n "$nft_drops" ]]; then
      status "WARN" "nftables has drop/reject rules:"
      echo "$nft_drops" | while read -r rule; do
        detail "$rule"
      done
    fi
  fi

  # Check for connection tracking issues
  if [[ -f /proc/sys/net/netfilter/nf_conntrack_count ]]; then
    local conntrack_count conntrack_max
    conntrack_count=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo 0)
    conntrack_max=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo 0)

    if [[ $conntrack_max -gt 0 ]]; then
      local usage_percent=$((conntrack_count * 100 / conntrack_max))
      status "INFO" "Connection tracking: $conntrack_count / $conntrack_max ($usage_percent%)"

      if [[ $usage_percent -gt 80 ]]; then
        status "WARN" "Connection tracking table nearly full"
        detail "→ May cause new connections to fail"
        add_block_indicator "Connection tracking table >80% full"
      fi
    fi
  fi
}

blocking_summary() {
  banner "🚫 BLOCKING DETECTION SUMMARY"

  if [[ ${#BLOCK_INDICATORS[@]} -eq 0 ]]; then
    gum style \
      --foreground "$COLOR_OK" \
      --border rounded \
      --border-foreground "$COLOR_OK" \
      --padding "1 2" \
      "✓ NO BLOCKING INDICATORS DETECTED"
    detail "The site appears to be accessible without filtering"
    return
  fi

  gum style \
    --foreground "$COLOR_BLOCK" \
    --border rounded \
    --border-foreground "$COLOR_BLOCK" \
    --padding "1 2" \
    "🚫 POTENTIAL BLOCKING DETECTED (${#BLOCK_INDICATORS[@]} indicators)"

  echo
  status "INFO" "Detected indicators:"
  for indicator in "${BLOCK_INDICATORS[@]}"; do
    detail "• $indicator"
  done

  echo
  # Provide specific recommendations based on detected blocks
  if [[ $UA_BLOCK_DETECTED -eq 1 ]]; then
    status "HINT" "User-Agent blocking detected"
    detail "→ Try using a different browser or User-Agent"
    detail "→ Some sites block curl/wget - use a browser instead"
  fi

  if [[ $GEO_BLOCK_DETECTED -eq 1 ]]; then
    status "HINT" "Geographic/legal restriction detected"
    detail "→ The site may be blocked in your region"
    detail "→ Consider using a VPN to access from a different location"
  fi

  if [[ $RATE_LIMIT_DETECTED -eq 1 ]]; then
    status "HINT" "Rate limiting detected"
    detail "→ Reduce request frequency"
    detail "→ Wait before trying again"
    detail "→ Your IP may be temporarily blocked"
  fi

  if [[ $CAPTCHA_DETECTED -eq 1 ]]; then
    status "HINT" "CAPTCHA/Challenge detected"
    detail "→ The site requires human verification"
    detail "→ Use a regular browser to complete the challenge"
    detail "→ Your IP may be flagged as suspicious"
  fi

  if [[ $BOT_BLOCK_DETECTED -eq 1 ]]; then
    status "HINT" "Bot detection triggered"
    detail "→ The site has anti-automation measures"
    detail "→ Use a regular browser with JavaScript enabled"
    detail "→ Clear cookies and try again"
  fi

  if [[ $TLS_BLOCK_DETECTED -eq 1 ]]; then
    status "HINT" "TLS/HTTPS blocking detected"
    detail "→ There may be TLS inspection/filtering on your network"
    detail "→ Try from a different network"
    detail "→ Check if your ISP or firewall blocks certain TLS traffic"
  fi
}

summary() {
  banner "📊 CONNECTIVITY SUMMARY"

  # DNS
  if [[ ${DNS_OK:-1} -eq 0 ]]; then
    status "CAUSE" "DNS for $TARGET is not resolving"
    detail "Likely DNS misconfiguration or upstream DNS blockage"
    detail "→ Check /etc/resolv.conf"
    detail "→ Check your router DNS settings"
    detail "→ Try another DNS resolver (8.8.8.8, 1.1.1.1)"
    return
  fi

  # High-level quick evaluation matrix
  if [[ ${CURL4_OK:-0} -eq 1 || ${CURL6_OK:-0} -eq 1 ]]; then
    echo
    gum style \
      --foreground "$COLOR_OK" \
      --border rounded \
      --border-foreground "$COLOR_OK" \
      --padding "1 2" \
      "✓ SUCCESS: At least one protocol can establish HTTPS to $TARGET"
    detail "Web service appears reachable"
    detail "Any issues are likely application-level (browser, cookies, JS, etc.)"
  fi

  # Specific cases
  if [[ ${CURL4_OK:-0} -eq 0 && ${CURL6_OK:-0} -eq 0 ]]; then
    echo
    gum style \
      --foreground "$COLOR_FAIL" \
      --border rounded \
      --border-foreground "$COLOR_FAIL" \
      --padding "1 2" \
      "✗ FAILURE: HTTPS fails for both IPv4 and IPv6"
    status "CAUSE" "If other websites work, this suggests:"
    detail "→ A routing or firewall issue between your ISP and $TARGET"
    detail "→ Or the remote host/network silently dropping your connection"
    detail "→ Possible network-level filtering"
  elif [[ ${CURL4_OK:-0} -eq 1 && ${CURL6_OK:-0} -eq 0 ]]; then
    echo
    status "CAUSE" "IPv4 works but IPv6 fails"
    detail "→ Likely an IPv6 path problem"
    detail "→ Misconfigured IPv6 on your side"
    detail "→ Or IPv6 disabled at the remote end"
    echo
    status "HINT" "Workaround: Temporarily disable IPv6 or force IPv4 in your applications"
  elif [[ ${CURL4_OK:-0} -eq 0 && ${CURL6_OK:-0} -eq 1 ]]; then
    echo
    status "CAUSE" "IPv6 works but IPv4 fails"
    detail "→ Likely an IPv4 routing or firewall issue on the path"
    detail "→ Or IPv4 blocked at the server"
  fi

  # Ping hints
  if [[ ${PING4_OK:-0} -eq 0 && ${CURL4_OK:-0} -eq 0 ]]; then
    echo
    status "HINT" "IPv4 ping and HTTPS both fail"
    detail "→ If other IPv4 sites work: remote host or intermediate routers may block your IPv4 traffic"
  fi

  if [[ ${PING6_OK:-0} -eq 0 && ${CURL6_OK:-0} -eq 0 ]]; then
    echo
    status "HINT" "IPv6 ping and HTTPS both fail"
    detail "→ Could be broken IPv6 routing"
    detail "→ Firewall filtering ICMPv6/TCP"
    detail "→ Or partial IPv6 deployment"
  fi

  # HTTP status-based hints (only if success)
  if [[ ${CURL4_OK:-0} -eq 1 ]]; then
    local code4
    code4=$(awk '{print $1}' <<<"$CURL4_OUTPUT")
    case "$code4" in
      403|451)
        echo
        status "CAUSE" "IPv4 HTTP returned $code4 (access denied / legal restriction)"
        detail "→ This can indicate IP-based blocking or geo-restriction for IPv4"
        ;;
      429)
        echo
        status "CAUSE" "IPv4 HTTP returned 429 (too many requests)"
        detail "→ You may be rate-limited; reduce request frequency and try again later"
        ;;
      5??)
        echo
        status "HINT" "IPv4 HTTP returned a 5xx server error"
        detail "→ The remote server is having issues, not your connection"
        ;;
    esac
  fi

  if [[ ${CURL6_OK:-0} -eq 1 ]]; then
    local code6
    code6=$(awk '{print $1}' <<<"$CURL6_OUTPUT")
    case "$code6" in
      403|451)
        echo
        status "CAUSE" "IPv6 HTTP returned $code6 (access denied / legal restriction)"
        detail "→ This can indicate IP-based blocking or geo-restriction for IPv6"
        ;;
      429)
        echo
        status "CAUSE" "IPv6 HTTP returned 429 (too many requests)"
        detail "→ You may be rate-limited; reduce request frequency and try again later"
        ;;
      5??)
        echo
        status "HINT" "IPv6 HTTP returned a 5xx server error"
        detail "→ The remote server is having issues, not your connection"
        ;;
    esac
  fi

}

main() {
  check_gum
  get_hostname
  detect_tools

  # Basic connectivity tests
  resolve_dns
  ping_tests
  curl_tests

  # Blocking detection tests
  user_agent_tests
  header_analysis
  body_analysis
  tls_analysis
  port_variation_test
  redirect_analysis
  timing_analysis
  rate_limit_test
  baseline_comparison

  # Route and network path analysis
  route_tests
  mtr_analysis
  tcpdump_analysis

  # Summaries
  blocking_summary
  summary

  echo
  gum style \
    --foreground "$COLOR_HEADER" \
    --italic \
    "Diagnostic complete for $TARGET"
  echo
}

main
