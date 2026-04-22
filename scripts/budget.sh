#!/usr/bin/env bash
#
# budget.sh - enforce the performance budgets defined in docs/PERFORMANCE.md.
#
# Builds the site fresh, measures brotli-q11 sizes for every page, and
# fails loudly on any violation. Intended for pre-commit and CI.
#
# Exit codes:
#   0  all budgets met
#   1  one or more budgets exceeded (violation)
#   2  environment / build error (hugo missing, build failed, etc.)
#
# Budgets are single source of truth; docs/PERFORMANCE.md describes their
# rationale.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

HUGO=${HUGO:-hugo}
BROTLI=${BROTLI:-brotli}

# ---- budget constants (keep in sync with docs/PERFORMANCE.md) ----------------
# HTML and CSS are measured together because critical CSS is inlined into
# <head>, so the two are part of the same first-flight payload.
BUDGET_SINGLE_PACKET_BR=14000       # HTML + render-blocking CSS, brotli-q11 (14 KB rule)
BUDGET_HOME_HTML_BR=6100            # homepage HTML+inline-CSS brotli (PERFORMANCE.md target 6,000 B; 100 B headroom for minor content churn)
BUDGET_POST_HTML_BR=10000           # any post (/p/... or /post/...) HTML+inline-CSS brotli
BUDGET_JS_FIRST_PAINT=0             # render-blocking <script> bytes on first paint
INITCWND_BYTES=14600
# Advisory only (printed, not enforced): total deploy size.
ADVISORY_TOTAL_PUBLIC=2000000
# ------------------------------------------------------------------------------

red()   { printf '\033[31m%s\033[0m' "$*"; }
green() { printf '\033[32m%s\033[0m' "$*"; }
bold()  { printf '\033[1m%s\033[0m' "$*"; }

violations=0
fail() {
    printf '  %s %s\n' "$(red FAIL)" "$*"
    violations=$((violations + 1))
}
pass() {
    printf '  %s %s\n' "$(green OK  )" "$*"
}

require() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "ERROR: required tool '$1' not found in PATH" >&2
        exit 2
    }
}

require "$HUGO"
require "$BROTLI"
require python3

printf '==> %s\n' "$(bold "Building site: hugo --minify --gc")"
rm -rf public resources/_gen
if ! "$HUGO" --minify --gc --quiet; then
    echo "ERROR: hugo build failed" >&2
    exit 2
fi

if [[ ! -d public ]]; then
    echo "ERROR: public/ not created" >&2
    exit 2
fi

# For each HTML file, return four numbers on one line:
#   <html_br> <css_br> <total_br> <render_blocking_script_bytes>
measure_page() {
    python3 - "$1" <<'PY'
import re, subprocess, sys, os

html_path = sys.argv[1]

# locate public/ root
head = os.path.abspath(html_path)
public_root = None
while head and head != '/':
    if os.path.basename(head) == 'public':
        public_root = head
        break
    head = os.path.dirname(head)
public_root = public_root or os.path.dirname(html_path)

with open(html_path, 'rb') as f:
    html_bytes = f.read()

stylesheet_re = re.compile(
    rb'<link\b[^>]*\brel\s*=\s*["\']?stylesheet["\']?[^>]*>',
    re.I,
)
href_re = re.compile(rb'\bhref\s*=\s*["\']([^"\']+)["\']', re.I)
nonblocking_re = re.compile(
    rb'\bmedia\s*=\s*["\']print["\']|\bonload\s*=',
    re.I,
)

script_re = re.compile(rb'<script\b[^>]*>', re.I)
src_re = re.compile(rb'\bsrc\s*=\s*["\']([^"\']+)["\']', re.I)
async_re = re.compile(rb'\b(async|defer)\b', re.I)
module_re = re.compile(rb'\btype\s*=\s*["\']module["\']', re.I)

def resolve(href: str) -> str:
    if href.startswith(('http://', 'https://', '//')):
        return ''
    return os.path.join(public_root, href.lstrip('/'))

# Render-blocking CSS
css_paths = []
for m in stylesheet_re.finditer(html_bytes):
    tag = m.group(0)
    if nonblocking_re.search(tag):
        continue
    hm = href_re.search(tag)
    if not hm:
        continue
    p = resolve(hm.group(1).decode('utf-8', 'replace'))
    if p and os.path.isfile(p):
        css_paths.append(p)

css_concat = b''
for p in css_paths:
    with open(p, 'rb') as f:
        css_concat += f.read()

# Render-blocking scripts (any <script src=...> that is neither async/defer nor a module)
script_bytes = 0
for m in script_re.finditer(html_bytes):
    tag = m.group(0)
    if async_re.search(tag) or module_re.search(tag):
        continue
    sm = src_re.search(tag)
    if not sm:
        continue
    p = resolve(sm.group(1).decode('utf-8', 'replace'))
    if p and os.path.isfile(p):
        script_bytes += os.path.getsize(p)

def br11(data: bytes) -> int:
    if not data:
        return 0
    p = subprocess.run(
        ['brotli', '-cq', '11'],
        input=data, capture_output=True, check=True,
    )
    return len(p.stdout)

html_br = br11(html_bytes)
css_br = br11(css_concat)
total_br = br11(html_bytes + css_concat)

print(f'{html_br} {css_br} {total_br} {script_bytes}')
PY
}

printf '\n==> %s\n' "$(bold "Per-page budget checks (brotli -q 11)")"
printf '%-46s  %9s  %9s  %9s  %5s\n' "PAGE" "HTML br" "CSS br" "FIRST br" "JS B"

worst_page=""
worst_total=0

while IFS= read -r html; do
    read -r html_br css_br total_br script_b <<<"$(measure_page "$html")"
    rel=${html#public/}
    printf '%-46s  %9s  %9s  %9s  %5s\n' "$rel" "$html_br" "$css_br" "$total_br" "$script_b"

    if (( total_br > worst_total )); then
        worst_total=$total_br
        worst_page=$rel
    fi

    # per-page single-packet rule (the 14 KB rule)
    if (( total_br > BUDGET_SINGLE_PACKET_BR )); then
        fail "page '$rel' first-paint $total_br B > $BUDGET_SINGLE_PACKET_BR B budget (14 KB rule)"
    fi

    # no render-blocking JS ever
    if (( script_b > BUDGET_JS_FIRST_PAINT )); then
        fail "page '$rel' ships $script_b B of render-blocking JavaScript on first paint (budget: $BUDGET_JS_FIRST_PAINT B)"
    fi

    # per-page-class HTML+inline-CSS budgets from CLAUDE.md
    case "$rel" in
        index.html)
            if (( html_br > BUDGET_HOME_HTML_BR )); then
                fail "home '$rel' $html_br B > $BUDGET_HOME_HTML_BR B home HTML+CSS budget"
            fi
            ;;
        p/*/index.html|post/*/index.html)
            if (( html_br > BUDGET_POST_HTML_BR )); then
                fail "post '$rel' $html_br B > $BUDGET_POST_HTML_BR B post HTML+CSS budget"
            fi
            ;;
    esac
done < <(find public -name '*.html' -type f | sort)

# Enforce "no web fonts, ever" from docs/PERFORMANCE.md. Any font file in
# the build output is a charter violation.
font_files=$(find public -type f \( \
    -name '*.woff2' -o -name '*.woff' \
    -o -name '*.ttf' -o -name '*.otf' \
    -o -name '*.eot' \) 2>/dev/null)
if [[ -n "$font_files" ]]; then
    fail "web font file(s) in build output (docs/PERFORMANCE.md forbids @font-face):"
    while IFS= read -r font_file; do
        printf '    %s\n' "$font_file"
    done <<< "$font_files"
else
    pass "no web fonts shipped"
fi

# Advisory: total deploy size (not a per-visitor metric, but warn if it balloons)
total_public=$(find public -type f -not -path '*/.*' -exec cat {} + 2>/dev/null | wc -c | tr -d ' ')
if (( total_public > ADVISORY_TOTAL_PUBLIC )); then
    printf '  \033[33mWARN\033[0m total public/ size %s B > advisory cap %s B\n' \
        "$total_public" "$ADVISORY_TOTAL_PUBLIC"
else
    pass "total public/ size $total_public B <= $ADVISORY_TOTAL_PUBLIC B advisory"
fi

# Summary
printf '\n==> %s\n' "$(bold "Summary")"
printf '  worst first-paint page : %s\n' "$worst_page"
printf '  worst first-paint bytes: %s B (%s%% of 14 KB initcwnd)\n' "$worst_total" "$(( worst_total * 100 / INITCWND_BYTES ))"
printf '  violations             : %s\n' "$violations"

if (( violations > 0 )); then
    printf '\n%s %s\n' "$(red 'BUDGET FAIL')" "$violations violations - see docs/PERFORMANCE.md for budgets"
    exit 1
fi

printf '\n%s all budgets within limits\n' "$(green 'BUDGET OK')"
exit 0
