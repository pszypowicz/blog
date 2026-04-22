# blog.szypowi.cz

Source for [blog.szypowi.cz](https://blog.szypowi.cz/).

Built with [Hugo](https://gohugo.io/) on [pager](https://github.com/pszypowicz/hugo-theme-pager),
a zero-JS monospace theme written specifically for this site. Hosted on
Cloudflare Pages with Brotli, HTTP/3, and 0-RTT TLS.

## Performance charter

Every page must cold-load in a single TCP round-trip after the TLS
handshake - HTML + inline critical CSS must fit the 14,600 B initcwnd
window compressed with Brotli-q11. Zero JavaScript, zero web fonts
(system stack only). Details and the full byte-budget table live in
[`docs/PERFORMANCE.md`](./docs/PERFORMANCE.md).

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

## Layout

- `content/` - posts and pages
- `config/_default/` - Hugo config split by concern (hugo, params, menu, markup, module, languages)
- `_vendor/` - Hugo Modules vendored tree (theme lives here; pinned in `go.mod`)
- `scripts/` - budget and perf verification
- `docs/` - public performance charter

## Contribution workflow

`main` is branch-protected. Direct pushes are rejected. Every change lands through a pull request.

```sh
git checkout -b <topic>             # branch off main
# edit, commit (pre-commit runs the perf budget on staged files)
git push -u origin <topic>
gh pr create --fill                 # opens PR against main
```

Opening the PR triggers:

- **GitHub Actions** (`.github/workflows/perf.yml`) - runs `budget` and `lighthouse` jobs. Required to pass before merge.
- **Cloudflare Pages preview** - auto-deploys the branch to `https://<branch>.blog-szypowicz.pages.dev/`. Open it on the iPad / desktop to visually verify.

Once green:

```sh
gh pr merge --squash --delete-branch
```

Production (`main` on Cloudflare Pages) rebuilds automatically from the merged commit.

Theme changes happen in the [`hugo-theme-pager`](https://github.com/pszypowicz/hugo-theme-pager) repo. After a theme release, bump the pin here via:

```sh
hugo mod get github.com/pszypowicz/hugo-theme-pager@vX.Y.Z
hugo mod vendor
# commit go.mod, go.sum, and _vendor/ in a blog PR
```

## License

Split license:

- **Code** (Hugo config, templates, scripts, CI, tooling) - [MIT](./LICENSE).
- **Content** (posts under `content/`, images under `images/`) - [CC BY 4.0](./LICENSE-CONTENT).
