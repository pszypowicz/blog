// @ts-check

/**
 * Dev-only layout debug overlay. Renders live box-model measurements for
 * `.page`, `.sidebar-col`, and `.main`. Tap to copy the current snapshot
 * as JSON. Only loaded by `themes/pager/layouts/_partials/debug.html`
 * when `hugo.IsServer` or on a CF Pages preview branch.
 */

(() => {
  const el = /** @type {HTMLElement | null} */ (document.getElementById("dbg"));
  if (!el) return;

  /** @type {Record<string, string>} */
  let last = {};

  /** @param {string} selector */
  const rect = (selector) => {
    const e = document.querySelector(selector);
    return e ? e.getBoundingClientRect() : null;
  };

  const snap = () => {
    const p = rect(".page");
    const s = rect(".sidebar-col");
    const m = rect(".main");
    const pageEl = document.querySelector(".page");
    const grid = pageEl ? getComputedStyle(pageEl).gridTemplateColumns : "";
    const nav = /** @type {PerformanceNavigationTiming | undefined} */ (
      performance.getEntriesByType("navigation")[0]
    );
    last = {
      ua: navigator.userAgent,
      url: location.pathname,
      vp: `${innerWidth}x${innerHeight}@${devicePixelRatio}`,
      nav: nav ? nav.type : "",
      page: p ? `${p.left | 0}+${p.width | 0}` : "",
      sbar: s ? `${s.left | 0}+${s.width | 0}` : "",
      main: m ? `${m.left | 0}+${m.width | 0}` : "",
      grid,
    };
    const visible = ["vp", "nav", "page", "sbar", "main", "grid"];
    el.textContent = visible.map((k) => `${k}: ${last[k]}`).join("\n");
    console.log("[dbg]", JSON.stringify(last));
  };

  /** @param {string} msg */
  const flash = (msg) => {
    const prev = el.textContent;
    el.textContent = msg;
    setTimeout(() => {
      el.textContent = prev;
    }, 900);
  };

  /** Fallback clipboard path for browsers without `navigator.clipboard`. */
  /** @param {string} text */
  const fallbackCopy = (text) => {
    const ta = document.createElement("textarea");
    ta.value = text;
    ta.style.position = "fixed";
    ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.select();
    try {
      document.execCommand("copy");
      flash("copied");
    } catch {
      flash("copy failed");
    }
    document.body.removeChild(ta);
  };

  el.addEventListener("click", () => {
    const txt = JSON.stringify(last, null, 2);
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard
        .writeText(txt)
        .then(() => flash("copied"))
        .catch(() => flash("copy failed"));
    } else {
      fallbackCopy(txt);
    }
  });

  addEventListener("load", snap);
  addEventListener("resize", snap);
  addEventListener("pageshow", snap);
  setTimeout(snap, 0);
})();
