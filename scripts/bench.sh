#!/usr/bin/env bash
#
# bench.sh - build the blog and print a performance report.
#
# Reports only; does not fail on budget violations. For hard enforcement
# see scripts/budget.sh. Both read the same constants below.
#
# Usage:
#   scripts/bench.sh            # full report
#   scripts/bench.sh --quiet    # machine-readable: single JSON line
#
# Requires: hugo (extended), brotli, gzip, python3 (for the HTML linkscan).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

HUGO=${HUGO:-hugo}
BROTLI=${BROTLI:-brotli}

# Budgets (reported, not enforced - see budget.sh for enforcement)
BUDGET_HOME_HTML_BR=${BUDGET_HOME_HTML_BR:-6000}
BUDGET_POST_HTML_BR=${BUDGET_POST_HTML_BR:-10000}
BUDGET_SINGLE_PACKET_BR=${BUDGET_SINGLE_PACKET_BR:-14000}
BUDGET_TOTAL_BYTES=${BUDGET_TOTAL_BYTES:-150000}
INITCWND_BYTES=${INITCWND_BYTES:-14600}   # 10 * MSS 1460, RFC 6928
export BUDGET_HOME_HTML_BR BUDGET_POST_HTML_BR BUDGET_SINGLE_PACKET_BR BUDGET_TOTAL_BYTES INITCWND_BYTES

QUIET=0
if [[ "${1:-}" == "--quiet" ]]; then
    QUIET=1
fi

log() {
    if [[ $QUIET -eq 0 ]]; then
        printf '%s\n' "$*"
    fi
}

require() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "ERROR: required tool '$1' not found in PATH" >&2
        exit 2
    }
}

require "$HUGO"
require "$BROTLI"
require gzip
require python3

log "==> Building site (hugo --minify --gc)"
rm -rf public resources/_gen
"$HUGO" --minify --gc --quiet

if [[ ! -d public ]]; then
    echo "ERROR: public/ not created by hugo" >&2
    exit 2
fi

# Sum the brotli-compressed size of the HTML plus every CSS file the page
# links render-blockingly (rel=stylesheet, no media=print, no onload).
# Prints "<html_br> <css_br> <total_br> <css_files_count>" on one line.
measure_page() {
    local html="$1"
    python3 - "$html" <<'PY'
import re, subprocess, sys, os

html_path = sys.argv[1]
root = os.path.join(os.path.dirname(html_path).split('/public')[0], 'public') \
       if '/public/' in html_path else os.path.dirname(html_path)
# Simpler: walk up to find public/
head = html_path
while head and os.path.basename(head) != 'public':
    head = os.path.dirname(head)
public_root = head or os.path.dirname(html_path)

with open(html_path, 'rb') as f:
    html_bytes = f.read()

link_re = re.compile(
    rb'<link\b[^>]*\brel\s*=\s*["\']?stylesheet["\']?[^>]*>',
    re.I,
)
href_re = re.compile(rb'\bhref\s*=\s*["\']([^"\']+)["\']', re.I)
block_re = re.compile(rb'\bmedia\s*=\s*["\']print["\']|\bonload\s*=', re.I)

css_paths = []
for m in link_re.finditer(html_bytes):
    tag = m.group(0)
    if block_re.search(tag):
        continue  # non-blocking (deferred) stylesheet
    href_m = href_re.search(tag)
    if not href_m:
        continue
    href = href_m.group(1).decode('utf-8', 'replace')
    if href.startswith('http://') or href.startswith('https://') or href.startswith('//'):
        continue  # third-party (should not exist, but skip)
    if href.startswith('/'):
        href = href.lstrip('/')
    css_path = os.path.join(public_root, href)
    if os.path.isfile(css_path):
        css_paths.append(css_path)

def br11(data: bytes) -> int:
    p = subprocess.run(
        ['brotli', '-cq', '11'],
        input=data, capture_output=True, check=True,
    )
    return len(p.stdout)

html_br = br11(html_bytes)

css_concat = b''
for p in css_paths:
    with open(p, 'rb') as f:
        css_concat += f.read()
css_br = br11(css_concat) if css_concat else 0

# Concat-then-compress is the realistic first-flight size (correlated streams)
total_br = br11(html_bytes + css_concat)

print(f'{html_br} {css_br} {total_br} {len(css_paths)}')
PY
}

HTML_COUNT=0
TOTAL_PUBLIC=$(find public -type f -not -path '*/.*' -exec cat {} + 2>/dev/null | wc -c | tr -d ' ')

log
log "==> Per-page critical-path measurements (brotli -q 11)"
printf '%-44s  %8s  %8s  %8s  %4s\n' "PAGE" "HTML br" "CSS br" "TOTAL br" "/14K"

max_html=0
max_total=0
worst_page=""

while IFS= read -r html; do
    HTML_COUNT=$((HTML_COUNT + 1))
    read -r html_br css_br total_br _css_n <<<"$(measure_page "$html")"
    rel=${html#public/}
    pct=$(( (total_br * 100) / INITCWND_BYTES ))
    printf '%-44s  %8s  %8s  %8s  %3s%%\n' "$rel" "$html_br" "$css_br" "$total_br" "$pct"
    if (( total_br > max_total )); then
        max_total=$total_br
        worst_page=$rel
    fi
    if (( html_br > max_html )); then
        max_html=$html_br
    fi
done < <(find public -name '*.html' -type f | sort)

log
log "==> Totals"
log "  HTML files                   : $HTML_COUNT"
log "  Worst page                   : $worst_page  (total brotli $max_total B, $(( max_total * 100 / INITCWND_BYTES ))% of 14 KB)"
log "  Max HTML brotli              : $max_html B"
log "  Total public/ bytes          : $TOTAL_PUBLIC  (budget: $BUDGET_TOTAL_BYTES)"
log "  14 KB initcwnd target        : $INITCWND_BYTES B (RFC 6928, MSS 1460, initcwnd 10)"
log "  Home HTML brotli budget      : $BUDGET_HOME_HTML_BR B"
log "  Post HTML brotli budget      : $BUDGET_POST_HTML_BR B"
log "  Single-packet budget         : $BUDGET_SINGLE_PACKET_BR B"
log
log "==> Asset breakdown (public/)"
css_total=$(find public -name '*.css' -type f -exec cat {} + 2>/dev/null | wc -c | tr -d ' ')
js_total=$(find public -name '*.js' -type f -exec cat {} + 2>/dev/null | wc -c | tr -d ' ')
font_total=$(find public -type f \( -name '*.woff2' -o -name '*.woff' -o -name '*.ttf' -o -name '*.otf' \) -exec cat {} + 2>/dev/null | wc -c | tr -d ' ')
img_total=$(find public -type f \( -name '*.avif' -o -name '*.webp' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.svg' -o -name '*.gif' \) -exec cat {} + 2>/dev/null | wc -c | tr -d ' ')
log "  CSS   raw   : $css_total B"
log "  JS    raw   : $js_total B"
log "  Fonts raw   : $font_total B"
log "  Images raw  : $img_total B"

if [[ $QUIET -eq 1 ]]; then
    printf '{"html_files":%d,"worst_page":"%s","worst_total_br":%d,"max_html_br":%d,"public_bytes":%s,"css_bytes":%s,"js_bytes":%s,"font_bytes":%s,"img_bytes":%s,"single_packet_budget":%d,"initcwnd":%d}\n' \
        "$HTML_COUNT" "$worst_page" "$max_total" "$max_html" "$TOTAL_PUBLIC" "$css_total" "$js_total" "$font_total" "$img_total" "$BUDGET_SINGLE_PACKET_BR" "$INITCWND_BYTES"
fi
