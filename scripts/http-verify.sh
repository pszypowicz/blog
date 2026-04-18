#!/usr/bin/env bash
#
# http-verify.sh - verify a deployed URL honors the CLAUDE.md protocol stack.
#
# Checks (against whatever URL is passed, default: https://blog.szypowi.cz/):
#   - TLS 1.3 is negotiated
#   - HTTP/3 is advertised via Alt-Svc
#   - HTTP/3 actually works when forced
#   - Brotli compression is served when requested
#   - Immutable cache headers are present on at least one hashed asset
#   - HTML revalidation returns 304 on a conditional GET with If-None-Match
#
# Uses homebrew curl (ngtcp2 + nghttp3 required for --http3).

set -euo pipefail

URL=${1:-https://blog.szypowi.cz/}
CURL=${CURL:-/opt/homebrew/opt/curl/bin/curl}

if [[ ! -x "$CURL" ]]; then
    CURL=$(command -v curl)
fi

if ! "$CURL" --version | grep -q 'HTTP3\|ngtcp2\|nghttp3'; then
    echo "WARN: curl at $CURL does not advertise HTTP/3 support; some checks will be skipped" >&2
    HAS_HTTP3=0
else
    HAS_HTTP3=1
fi

pass() { printf '  \033[32mOK\033[0m  %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAILS=$((FAILS+1)); }
FAILS=0

echo "==> Verifying $URL"

# --- TLS 1.3 ---
# %{ssl_version} is missing from some curl bottles; parse -sv stderr instead.
tls_ver=$("$CURL" -sv -o /dev/null "$URL" 2>&1 | awk -F'[ /]' '/^\* SSL connection using/ {print $5; exit}')
if [[ "$tls_ver" == "TLSv1.3" ]]; then
    pass "TLS negotiated: $tls_ver"
else
    fail "TLS negotiated: ${tls_ver:-unknown} (want TLSv1.3)"
fi

# --- HTTP/2 baseline ---
headers=$("$CURL" -sI "$URL")
if echo "$headers" | grep -qi '^alt-svc:.*h3'; then
    pass "Alt-Svc advertises HTTP/3"
else
    fail "Alt-Svc does not advertise HTTP/3"
fi

# --- HTTP/3 probe ---
if [[ "$HAS_HTTP3" -eq 1 ]]; then
    h3=$("$CURL" -sI --http3 -o /dev/null -w '%{http_version}\n' "$URL" 2>/dev/null || echo "error")
    if [[ "$h3" == "3" ]]; then
        pass "HTTP/3 negotiated when forced"
    else
        fail "HTTP/3 forced request negotiated http_version='$h3'"
    fi
fi

# --- Brotli ---
enc=$("$CURL" -sI -H 'Accept-Encoding: br' "$URL" | grep -i '^content-encoding:' | awk '{print tolower($2)}' | tr -d '\r\n')
if [[ "$enc" == "br" ]]; then
    pass "Brotli served (content-encoding: br)"
else
    fail "Brotli not served (content-encoding: '$enc')"
fi

# --- Find a hashed asset and check immutable cache ---
home_html=$("$CURL" -s "$URL" || true)
asset=$(echo "$home_html" | grep -oE '/[^" ]+\.(css|js|woff2)' | head -1 || true)
if [[ -n "$asset" ]]; then
    base=${URL%/}
    asset_url="$base$asset"
    cc=$("$CURL" -sI "$asset_url" | grep -i '^cache-control:' | tr -d '\r\n' || true)
    if echo "$cc" | grep -qi 'immutable'; then
        pass "Cache-Control immutable on hashed asset: $asset"
    else
        fail "Asset '$asset' missing 'immutable' in cache-control: $cc"
    fi
else
    fail "No hashed asset found in homepage HTML (looked for .css / .js / .woff2)"
fi

# --- HTML revalidation (304 on If-None-Match) ---
etag=$("$CURL" -sI "$URL" | awk '/^etag:/I {print $2}' | tr -d '\r\n"' || true)
if [[ -n "$etag" ]]; then
    status=$("$CURL" -s -o /dev/null -w '%{http_code}' -H "If-None-Match: \"$etag\"" "$URL")
    if [[ "$status" == "304" ]]; then
        pass "Conditional GET returns 304 on unchanged ETag"
    else
        fail "Conditional GET returned $status, expected 304"
    fi
else
    fail "No ETag header on HTML response"
fi

printf '\n'
if (( FAILS > 0 )); then
    printf '\033[31mHTTP VERIFY FAIL\033[0m (%d checks failed)\n' "$FAILS"
    exit 1
fi
printf '\033[32mHTTP VERIFY OK\033[0m\n'
