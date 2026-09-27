import assert from "node:assert/strict";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const out = resolve(root, "build/chrome-extension");
const read = (path) => readFileSync(resolve(out, path), "utf8");
const manifest = JSON.parse(read("manifest.json"));
assert.equal(manifest.manifest_version, 3);
assert.equal(
  manifest.version,
  JSON.parse(readFileSync(resolve(root, "package.json"), "utf8")).version,
);
assert.equal(manifest.action.default_popup, "popup.html");
assert.deepEqual(Object.keys(manifest.icons), ["16", "32", "48", "128"]);
for (const key of [
  "permissions",
  "host_permissions",
  "optional_permissions",
  "content_scripts",
  "background",
  "externally_connectable",
  "web_accessible_resources",
]) {
  assert.equal(
    manifest[key],
    undefined,
    `Unexpected extension capability: ${key}`,
  );
}
assert.match(
  manifest.content_security_policy.extension_pages,
  /script-src 'self';/,
);
assert.match(
  manifest.content_security_policy.extension_pages,
  /connect-src 'none';/,
);
const html = read("popup.html");
assert.match(html, /<script defer src="bootstrap.js"><\/script>/);
assert.doesNotMatch(
  html,
  /(?:src|href)="(?:popup\.(?:js|css)|fonts\/)|rel="(?:preload|modulepreload)"/,
);
assert.doesNotMatch(html, /<script[^>]*>[\s\S]*?\S[\s\S]*?<\/script>|\son\w+=/);
const bootstrap = read("bootstrap.js");
assert.ok(
  Buffer.byteLength(bootstrap) < 3_000,
  "Only the small bootstrap may block popup display",
);
assert.ok(
  Buffer.byteLength(read("bootstrap.css")) < 2_000,
  "Bootstrap styles exceed their 2 kB budget",
);
assert.doesNotMatch(read("bootstrap.css"), /url\s*\(|@import/);
assert.doesNotMatch(
  bootstrap,
  /requestAnimationFrame|React|react\.production|react-dom/,
);
for (const locale of readdirSync(resolve(out, "_locales"))) {
  const messages = JSON.parse(read(`_locales/${locale}/messages.json`));
  for (const key of ["description", "loadError", "reload"]) {
    assert.ok(
      typeof messages[key]?.message === "string" &&
        messages[key].message.trim(),
      `Missing Chrome message: ${locale}/${key}`,
    );
  }
}
const js = read("popup.js");
assert.ok(
  Buffer.byteLength(js) < 700_000,
  "Popup script exceeds its 700 kB startup budget",
);
assert.ok(
  Buffer.byteLength(read("popup.css")) < 55_000,
  "Popup CSS exceeds its 55 kB budget",
);
assert.doesNotMatch(
  js,
  /\beval\s*\(|\bnew Function\s*\(|__TAURI_INTERNALS__|vitals\.vercel|va\.vercel|https:\/\/[^"\s]*\.(?:js|woff)/,
);
for (const path of [
  "popup.css",
  "fonts/GeistVF.woff",
  "fonts/LICENSE.txt",
  ...Object.values(manifest.icons),
  ...Object.values(manifest.action.default_icon),
  "_locales/en/messages.json",
]) {
  assert.ok(
    existsSync(resolve(out, path)),
    `Missing packaged resource: ${path}`,
  );
}
console.log(
  "Extension package checks passed (MV3, local assets, CSP, no permissions or analytics).",
);
