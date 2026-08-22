import { spawnSync } from "node:child_process";
import { readdirSync, rmSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  defaultLocale,
  desktopLanguageStorageKey,
  languageMapping,
  locales,
} from "../i18n-config.ts";
import { createMobileEntryHtml } from "./mobile-entry.mjs";

const result = spawnSync(
  process.execPath,
  [resolve("node_modules/next/dist/bin/next"), "build"],
  {
    stdio: "inherit",
    env: {
      ...process.env,
      BUILD_TARGET: "mobile",
    },
  }
);

if (result.error) throw result.error;
if (result.status !== 0) process.exit(result.status ?? 1);

// The Mobile shell exposes only the main localized application pages. Public
// assets are copied independently of pageExtensions, so remove Web-only route
// trees and assets before Capacitor sees webDir.
for (const locale of locales) {
  rmSync(resolve("out", locale), { recursive: true, force: true });
}
for (const path of ["out/demo", "out/badges"]) {
  rmSync(resolve(path), { recursive: true, force: true });
}
rmSync(resolve("out/baidu_verify_codeva-SXZydSeYe0.html"), { force: true });
for (const entry of readdirSync(resolve("out"))) {
  if (entry === "sw.js" || entry.startsWith("workbox-")) {
    rmSync(resolve("out", entry), { force: true });
  }
}

writeFileSync(
  resolve("out/index.html"),
  createMobileEntryHtml({
    locales,
    defaultLocale,
    languageMapping,
    preferredLanguageStorageKey: desktopLanguageStorageKey,
  }),
  "utf8"
);
