# blog.szypowi.cz

Source for [blog.szypowi.cz](https://blog.szypowi.cz/).

Built with [Hugo](https://gohugo.io/) on [pager](https://github.com/pszypowicz/hugo-theme-pager),
a zero-JS monospace theme written specifically for this site. Hosted on
Cloudflare Pages with Brotli, HTTP/3, and 0-RTT TLS.

## Performance charter

Every page must cold-load in a single TCP round-trip after the TLS
handshake - HTML + inline critical CSS must fit the 14,600 B initcwnd
window compressed with Brotli-q11. Zero JavaScript and zero web fonts
on first paint; Cascadia Code swaps in via `font-display: optional`
once it is cached. Details and the full byte-budget table live in
[`.claude/CLAUDE.md`](./.claude/CLAUDE.md).

## Local development

```sh
hugo server          # live reload at http://localhost:1313
hugo --minify --gc   # production build into public/
```

## Verification

```sh
scripts/bench.sh        # 14 KB single-flight check
scripts/budget.sh       # byte budgets (HTML, critical CSS, deferred CSS, totals)
scripts/lighthouse.sh   # Core Web Vitals on Moto G4 / slow 4G
scripts/http-verify.sh  # post-deploy: TLS 1.3, HTTP/3, Brotli, cache headers
```

`npx playwright test` runs the visual regression suite (3 engines × 3
viewports × 4 pages).

## Layout

- `content/` - posts and pages
- `config/_default/` - Hugo config split by concern (hugo, params, menu, markup, languages)
- `themes/pager/` - theme submodule
- `scripts/` - budget and perf verification
- `tests/visual/` - Playwright snapshots
