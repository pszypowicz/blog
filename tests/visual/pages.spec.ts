import { test, expect } from "@playwright/test";

const pages = [
  { name: "home", path: "/" },
  { name: "about", path: "/about/" },
  { name: "post-podman", path: "/p/testing-podman-2.1.x-rootless-networking/" },
  { name: "post-wayland", path: "/p/enable-mozilla-firefox-and-thunderbird-on-wayland-in-ubuntu-20.04/" },
];

for (const { name, path } of pages) {
  test(`${name} snapshot`, async ({ page }) => {
    // Block WOFF2 requests so snapshots capture the system-stack fallback
    // the charter promises on first paint.
    await page.route("**/*.woff2", (route) => route.abort());
    await page.goto(path, { waitUntil: "networkidle" });
    await expect(page).toHaveScreenshot(`${name}.png`, { fullPage: true });
  });
}
