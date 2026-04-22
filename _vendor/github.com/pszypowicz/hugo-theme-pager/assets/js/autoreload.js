// @ts-check

/**
 * Dev-only auto-reload. Polls the current URL at a 5 s interval, parses
 * the modeline SHA out of the response, and reloads the page only when
 * the remote SHA differs from the local one. State is persisted in
 * localStorage so the toggle survives reloads. Only loaded by
 * `themes/pager/layouts/_partials/debug.html` when `hugo.IsServer` or
 * on a CF Pages preview branch.
 */

(() => {
  const STORAGE_KEY = "dbg-autoreload";
  const POLL_MS = 5000;

  const button = /** @type {HTMLElement | null} */ (
    document.getElementById("dbg-reload")
  );
  if (!button) return;

  const localShaEl = document.querySelector(".modeline__sha");
  const localSha = (localShaEl ? localShaEl.textContent || "" : "").replace(
    /\s+/g,
    "",
  );

  let on = localStorage.getItem(STORAGE_KEY) === "1";
  /** @type {ReturnType<typeof setInterval> | null} */
  let timer = null;

  const render = () => {
    button.textContent = on
      ? `auto-reload: on (${localSha || "?"})`
      : "auto-reload: off";
    button.style.background = on ? "#0a4c0a" : "#000c";
  };

  const poll = () => {
    fetch(`${location.pathname}?_=${Date.now()}`, { cache: "no-cache" })
      .then((r) => r.text())
      .then((html) => {
        const doc = new DOMParser().parseFromString(html, "text/html");
        const remote =
          doc.querySelector(".modeline__sha")?.textContent?.replace(
            /\s+/g,
            "",
          ) || "";
        if (remote && localSha && remote !== localSha) {
          button.textContent = `reloading (${remote})`;
          setTimeout(() => location.reload(), 200);
        }
      })
      .catch(() => {
        /* network hiccup; try again on next tick */
      });
  };

  const sync = () => {
    if (timer) {
      clearInterval(timer);
      timer = null;
    }
    if (on) {
      timer = setInterval(poll, POLL_MS);
      poll();
    }
  };

  button.addEventListener("click", () => {
    on = !on;
    localStorage.setItem(STORAGE_KEY, on ? "1" : "0");
    render();
    sync();
  });

  render();
  sync();
})();
