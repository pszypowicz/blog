import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "tests/visual",
  fullyParallel: true,
  retries: 0,
  reporter: "list",
  use: {
    baseURL: process.env.BASE_URL ?? "http://127.0.0.1:1380",
    trace: "off",
    video: "off",
    screenshot: "off",
    reducedMotion: "reduce",
    // Disable fonts so snapshots reflect the system-stack first paint that
    // the charter promises. Cascadia is progressive and its swap is a
    // separate visual state we can capture later if needed.
    extraHTTPHeaders: {},
  },
  expect: {
    toHaveScreenshot: {
      maxDiffPixelRatio: 0.001,
      animations: "disabled",
    },
  },
  projects: [
    { name: "chromium-mobile", use: { ...devices["Desktop Chrome"], viewport: { width: 375, height: 667 } } },
    { name: "chromium-tablet", use: { ...devices["Desktop Chrome"], viewport: { width: 768, height: 1024 } } },
    { name: "chromium-desktop", use: { ...devices["Desktop Chrome"], viewport: { width: 1440, height: 900 } } },
    { name: "firefox-mobile", use: { ...devices["Desktop Firefox"], viewport: { width: 375, height: 667 } } },
    { name: "firefox-tablet", use: { ...devices["Desktop Firefox"], viewport: { width: 768, height: 1024 } } },
    { name: "firefox-desktop", use: { ...devices["Desktop Firefox"], viewport: { width: 1440, height: 900 } } },
    { name: "webkit-mobile", use: { ...devices["Desktop Safari"], viewport: { width: 375, height: 667 } } },
    { name: "webkit-tablet", use: { ...devices["Desktop Safari"], viewport: { width: 768, height: 1024 } } },
    { name: "webkit-desktop", use: { ...devices["Desktop Safari"], viewport: { width: 1440, height: 900 } } },
  ],
});
