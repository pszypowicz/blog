# blog.szypowi.cz - performance charter

This blog exists to be **the fastest possible static page on the internet**. Design, content, and aesthetics serve performance - never the other way around. The north star: cold-load an article in a **single network round-trip after the TLS handshake**, anywhere on Earth.

This charter is the contract. Every change in this repo is evaluated against it. If a change violates a budget or principle here, it does not ship.

## The 14 KB rule (non-negotiable)

Linux's default TCP initial congestion window is **10 segments** (RFC 6928). With an Ethernet MSS of 1460 bytes, the first TCP flight after the handshake carries **~14,600 bytes** of payload. Anything larger pays at least one additional round-trip.

The critical path of every page on this site - HTML, inline critical CSS, and any inlined SVG - **must fit under 14 KB, Brotli-q11 compressed**. External CSS, web fonts, images, and any JavaScript are deferred and cannot block first paint.

This is measured by `scripts/bench.sh` on every build. A build that violates the 14 KB rule is a failed build.

## Hard byte budgets

Enforced by `scripts/budget.sh`:

| Artifact                              | Budget                    | Why                                        |
| ------------------------------------- | ------------------------- | ------------------------------------------ |
| `index.html` minified, Brotli-q11     | <= 6,000 B                | Leaves room for inline CSS in first flight |
| Any post HTML minified, Brotli-q11    | <= 10,000 B               | Worst-case long posts                      |
| Inline critical CSS, Brotli-q11       | <= 8,000 B                | Render-unblock the above-fold              |
| **HTML + inline critical CSS (br11)** | **<= 14,000 B hard fail** | The 14 KB rule                             |
| Total transferred first paint         | <= 20 KB                  | HTML + critical CSS only                   |
| JavaScript shipped on first paint     | **0 B**                   | No exceptions                              |
| Deferred CSS (rest of site styles)    | <= 25 KB Brotli-q11       |                                            |
| Web fonts shipped on first paint      | **0 B**                   | System stack first; fonts are progressive  |
| Total page weight including fonts     | <= 150 KB                 | All assets, all requests, cumulative       |
| Number of requests on first paint     | <= 2                      | HTML + (optional) one hashed sprite        |

## Lighthouse budgets (Moto G4 / slow 4G profile)

Enforced by `scripts/lighthouse.sh` via `lhci`. Each audited page must meet:

- Performance score: **100**
- First Contentful Paint: **<= 600 ms**
- Largest Contentful Paint: **<= 800 ms**
- Speed Index: **<= 800 ms**
- Total Blocking Time: **<= 50 ms**
- Cumulative Layout Shift: **<= 0.01**
- Time To Interactive: **<= 800 ms**
- Server response time (TTFB): **<= 200 ms**

If a change drops any score, either the change is reverted or the charter is amended **before** merging - never after.

## Build stack

- **Hugo extended** (0.160+ for the asset pipeline: `resources.PostCSS`, `resources.Minify`, `resources.Fingerprint`, `resources.ExecuteAsTemplate`).
- **Theme: `hugo-theme-pager`** (personal theme, owned by me) as a git submodule at `themes/pager`. CSS and layout live inside the theme - there is no site-level override. The theme is versioned independently (see `Bump theme to vX.Y.Z` commits) and pinned per blog commit.
- **Hugo flags on every build**: `hugo --minify --gc`. No exceptions.
- **PostCSS + cssnano** for additional CSS minification beyond Hugo's built-in minifier.
- **Brotli-q11** precompression of every static asset in CI, shipped alongside the raw files. Cloudflare Pages serves the precompressed files when the client's `Accept-Encoding` header permits it.

## CSS strategy

1. **Inline critical CSS in `<head>`**. `themes/pager/assets/scss/critical.scss` pulls only above-fold partials (reset, grid, menu, sidebar, article cards, layout/article, Cascadia fonts) and is compiled + fingerprinted + inlined as `<style>` by `themes/pager/layouts/_partials/head/style.html`.
2. **Defer non-critical CSS** (`themes/pager/assets/scss/rest.scss`) as a hashed external stylesheet via the standard trick:
   ```html
   <link
     rel="preload"
     href="/scss/rest.min.<hash>.css"
     as="style"
     onload="this.onload=null;this.rel='stylesheet'"
   />
   <noscript
     ><link rel="stylesheet" href="/scss/rest.min.<hash>.css"
   /></noscript>
   ```
   Contents: footer, pagination, widgets, listing-page layout, 404 page, and the ~860-line chroma syntax-highlight block. `_headers` sets `Cache-Control: public, max-age=31536000, immutable` on `/*.css` so returning visitors hit the browser cache on every page after the first.
3. **No `@import` in CSS**. Concatenate at build time.
4. **Purge unused rules** against the actual rendered HTML. Today this is done at source inside `themes/pager/assets/scss/` - `critical.scss` imports only the partials needed for first paint, and `tokens.scss` holds the design tokens. Nothing is pulled in just to be stripped later. Revisit PurgeCSS if more aggressive trimming is needed.
5. **Scoped styles** only where actually needed.

## JavaScript strategy

**Zero JS on first paint.** No frameworks, no jQuery, no analytics pixel. The site is HTML and CSS.

If an interaction genuinely demands JS (search, theme toggle, copy-code buttons), it is gated behind user intent:

- `<script type="module" async>` only.
- Loaded on `pointerenter` / `pointerdown` / `input focus`, never on `DOMContentLoaded`.
- Budget: <= 10 KB gzipped across all deferred scripts combined.

The theme ships no JS by default. Any feature that would need JS (search, theme toggle, copy-code buttons) must justify its bytes against a user benefit, not against "it's nice to have."

## Font strategy (the bells and whistles)

**System stack renders first paint. Always.**

```css
font-family:
  ui-sans-serif,
  system-ui,
  -apple-system,
  BlinkMacSystemFont,
  "Segoe UI",
  Roboto,
  "Helvetica Neue",
  Arial,
  sans-serif;
```

Cascadia Code (the nerdy flavor) is a **progressive enhancement**:

- Loaded via `<link rel="preload" as="font" type="font/woff2" crossorigin>` only **after** the first paint completes - deferred by a tiny loader or `requestIdleCallback`.
- `@font-face` declarations use `font-display: optional`. On a slow first visit, Cascadia is simply not used; the system stack stays. On a fast visit or any subsequent visit, Cascadia is already in the HTTP cache and swaps in with zero layout shift.
- `size-adjust`, `ascent-override`, `descent-override` are tuned so Cascadia's metrics **match** the fallback system monospace, guaranteeing zero CLS when the swap eventually happens.
- Only **two** files: `cascadia-code-wght-normal.woff2` (variable, ~48 KB) and italic (~54 KB). Subset to Latin only. No Nerd Font glyphs - not used in content.

The site must score Lighthouse 100 **with fonts disabled in the network panel**. If the font is the thing that makes a page "fast enough," the page is broken.

## Image strategy

- **LCP image (hero / avatar)**: `fetchpriority="high"`, `decoding="async"`, dimensions set to prevent CLS, preloaded in `<head>`.
- **Everything else**: `loading="lazy"` and `decoding="async"`.
- **Format priority**: AVIF -> WebP -> JPEG, emitted via Hugo's image pipeline. `<picture>` element with type-sorted `<source>`.
- **Responsive srcset** at 1x, 2x for every image. Hugo generates them deterministically.
- **No decorative images** on the home page or post headers. Text is enough.
- **SVG for icons**, inlined in the HTML when small, sprited when shared across pages.

## Cache strategy

- Hashed, content-addressable filenames for every asset (`style.<sha256>.css`, `cascadia-code.<sha256>.woff2`). Hugo's `resources.Fingerprint` handles this.
- `Cache-Control: public, max-age=31536000, immutable` on all hashed assets (1 year, never revalidated).
- `Cache-Control: public, s-maxage=300, stale-while-revalidate=60` on HTML, paired with a zone-level **Cache Rule** (`blog html edge cache`) that marks HTML paths on `blog.szypowi.cz` as eligible for edge caching with "use cache-control header from origin". Without the Cache Rule, CF's default cache level skips HTML regardless of the directive. With both in place, CF edge caches HTML for 5 minutes and emits `Last-Modified`, so browser revalidation via `If-Modified-Since` returns `304 Not Modified` - typically 0 bytes over the wire after the first visit. `stale-while-revalidate` lets the edge refresh in the background so deploys propagate within one client request after the TTL lapses.
- `_headers` file in the repo root configured for Cloudflare Pages.

## DNS, TLS, and transport

- **DNS**: authoritative on Cloudflare. `blog` record is a CNAME to `pages.dev` (or direct Cloudflare Pages hostname), proxied (orange cloud) in production.
- **TTL**: 60s during any cutover, 3600s in steady state.
- **HTTPS / SVCB records (RFC 9460)**: auto-published by Cloudflare. Carries ALPN hints (`h2`, `h3`) and the ECH config. Reduces first-connect round-trips for capable clients.
- **TLS 1.3 minimum** at the edge. 0-RTT resumption enabled (safe for GET-only static content).
- **HTTP/3 + QUIC** enabled at the edge. Advertised via `Alt-Svc: h3=":443"; ma=86400`.
- **Brotli precompressed** assets served with `Content-Encoding: br`. Gzip kept as fallback.

## Testing and measurement

Every change goes through the test suite in `scripts/`. A PR that does not run clean is not merged.

- `scripts/bench.sh` - build the site, compute raw/gzip/brotli sizes, print the single-packet fit report. Fails loudly if the 14 KB rule is violated.
- `scripts/budget.sh` - enforce the byte budgets table above. One exit code per budget. CI-friendly.
- `scripts/lighthouse.sh` - spin up a local Hugo server, run Lighthouse via `lhci`, assert the Core Web Vitals thresholds above. Uses `.lighthouserc.local.json` locally and `.lighthouserc.prod.json` when invoked with `--prod`. The two configs differ only on server-dependent audits (`uses-text-compression`, `uses-long-cache-ttl`): strict in prod, `warn` locally because `python3 -m http.server` sends neither Brotli nor cache headers.
- `scripts/http-verify.sh` - against the deployed URL, verify: TLS 1.3 is negotiated, HTTP/3 is advertised, Brotli is served, immutable cache headers are present on hashed assets, ETag revalidation returns 304 on HTML.
- `playwright.config.ts` + `tests/visual/` - visual regression harness. Runs each page against a 3-browser (Chromium, Firefox, WebKit) x 3-viewport (375, 768, 1440) matrix with `maxDiffPixelRatio: 0.001`. Fonts are disabled so snapshots capture the system-stack first paint the charter promises; Cascadia swap is a separate state.
- `.pre-commit-config.yaml` - local enforcement. Runs `scripts/budget.sh` as a `perf-budget` hook whenever `content/`, `static/`, `themes/`, `config/`, or `hugo.toml` changes. Also standard hygiene hooks (trailing whitespace, EOF fixer, YAML/JSON/TOML linting, shellcheck, 200 KB large-file guard with `tests/visual/**-snapshots/*.png` excluded). Install once with `pre-commit install`.

Tooling required (install once):

```
brew install nghttp2 brotli hyperfine curl pre-commit
npm install -g lighthouse @lhci/cli
npm install   # installs local devDependencies from package.json (Playwright today)
npx playwright install
pre-commit install
```

Lighthouse CLI is installed globally. Playwright is the only npm-local dep (pinned in `package.json`). PostCSS/cssnano minification runs through Hugo's built-in pipeline, not a standalone npm install.

The homebrew `curl` formula ships with HTTP/3 (ngtcp2 + nghttp3) enabled; use `/opt/homebrew/opt/curl/bin/curl --http3` for HTTP/3 probes since macOS's system curl does not support it.

## Principles

1. **Measurement beats opinion.** If a change cannot be measured, it cannot be justified. Before writing code, decide which number in `scripts/bench.sh` this change is supposed to move and by how much.
2. **The 14 KB rule is sacred.** Every other rule exists to make it easier to hit.
3. **Subtract before you add.** The default answer to "should we add X" is no. The cost of a feature is not the time to implement it; it is the bytes it puts on the critical path for every visitor forever.
4. **Defer aggressively.** Fonts, JavaScript, non-critical CSS, images below the fold, analytics - all deferred, all optional, all removable without breaking the page.
5. **Progressive enhancement, not progressive degradation.** The page must work with JavaScript disabled, fonts blocked, and images failing. Everything above that is decoration.
6. **No third-party requests on first paint.** Zero. No Google Analytics, no Disqus, no fonts from Google Fonts, no CDN-hosted anything. The browser talks to one origin for the first paint and that is it.
7. **Reject frameworks.** Hugo is the build tool. The output is HTML + CSS. There is no React, no Vue, no Svelte, no Astro, no runtime framework of any kind. If a feature cannot be expressed in those terms, the feature does not belong here.
8. **If it is not in `content/`, it is noise.** Posts are what the reader came for. Navigation, tags, metadata, decoration - all of that is scaffolding that must shrink, not grow.

## When this charter is violated

If a PR (or a suggestion in a Claude Code session) violates any rule above:

1. The violation is called out by name and budget.
2. A concrete plan to bring it back within budget is agreed **before** the change is made.
3. If the plan is not workable, the change is dropped.

"It is only a little over" and "we can optimize later" are not acceptable reasons. Later is now.
