#!/usr/bin/env bash
#
# lighthouse.sh - run Lighthouse CI against the site.
#
# Two modes:
#   scripts/lighthouse.sh          # local: build, serve public/ via python, run lhci
#   scripts/lighthouse.sh --prod   # prod: run lhci against the deployed URL, no local server
#
# Local mode uses .lighthouserc.local.json (server-dependent audits demoted to warn
# because python's http.server does not compress or send cache headers).
# Prod mode uses .lighthouserc.prod.json (strict, asserts Brotli and long-cache-ttl).
#
# Requires: hugo (local only), lhci (`npm i -g @lhci/cli`), Google Chrome.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

HUGO=${HUGO:-hugo}
LHCI=${LHCI:-lhci}
PORT=${PORT:-1380}

MODE=local
if [[ "${1:-}" == "--prod" ]]; then
    MODE=prod
fi

CONFIG=".lighthouserc.${MODE}.json"

require() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "ERROR: required tool '$1' not found in PATH" >&2
        exit 2
    }
}

require "$LHCI"

if [[ -z "${CHROME_PATH:-}" && -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]]; then
    export CHROME_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
fi

if [[ "$MODE" == "prod" ]]; then
    echo "==> Running lhci autorun against production ($CONFIG)"
    "$LHCI" autorun --config="$CONFIG"
    exit $?
fi

require "$HUGO"

cleanup() {
    if [[ -n "${SERVER_PID:-}" ]]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

echo "==> Building site (hugo --minify --gc)"
rm -rf public resources/_gen
"$HUGO" --minify --gc --quiet

if [[ ! -d public ]]; then
    echo "ERROR: public/ not created" >&2
    exit 2
fi

echo "==> Serving public/ on http://127.0.0.1:$PORT/"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory public >/dev/null 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 40); do
    if curl -s -o /dev/null "http://127.0.0.1:$PORT/"; then
        break
    fi
    sleep 0.25
done

if ! curl -s -o /dev/null "http://127.0.0.1:$PORT/"; then
    echo "ERROR: local server did not come up on :$PORT" >&2
    exit 2
fi

echo "==> Running lhci autorun ($CONFIG)"
"$LHCI" autorun --config="$CONFIG"
