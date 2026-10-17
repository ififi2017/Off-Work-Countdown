#!/usr/bin/env node

import { createHash, createSign } from "node:crypto";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import { confirmExact } from "./release-helpers.mjs";

const HELP = `Google Play store listing sync

Usage:
  npm run play:listing:check -- --config play-store/3.2.2.json
  npm run play:listing:plan  -- --config play-store/3.2.2.json [--text-only]
  npm run play:listing:sync  -- --config play-store/3.2.2.json [--text-only] [--changes-not-sent-for-review] [--yes]

Modes:
  --check                        Validate JSON, character limits and local images. No credentials needed.
  --plan                         Read the Play listing through a temporary edit and print changes. Default; never commits.
  --apply                        Write the printed changes in one edit, validate it and commit it.

Options:
  --text-only                    Ignore images; compare and write title and descriptions only.
  --changes-not-sent-for-review  Commit with changesNotSentForReview=true (send for review later in Play Console).
  --yes                          Skip the typed confirmation.

Credentials (service account with "Manage store presence"):
  PLAY_SERVICE_ACCOUNT_KEY_PATH  Path to the service-account JSON key (falls back to GOOGLE_APPLICATION_CREDENTIALS).
`;

const API_ROOT = "https://androidpublisher.googleapis.com";
const SCOPE = "https://www.googleapis.com/auth/androidpublisher";

// The app's 19 UI locales (public/locales) and the Play listing language each one fills.
export const APP_LOCALE_TO_PLAY = Object.freeze({
  ar: "ar",
  de: "de-DE",
  en: "en-US",
  es: "es-ES",
  fr: "fr-FR",
  "hi-IN": "hi-IN",
  id: "id",
  it: "it-IT",
  ja: "ja-JP",
  ko: "ko-KR",
  "mr-IN": "mr-IN",
  pt: "pt-BR",
  ru: "ru-RU",
  th: "th",
  tr: "tr-TR",
  vi: "vi",
  "zh-CN": "zh-CN",
  "zh-HK": "zh-HK",
  "zh-TW": "zh-TW",
});

// en-GB and es-419 are the regional variants the Android app also ships (locales_config.xml).
export const PLAY_LANGUAGES = new Set([...Object.values(APP_LOCALE_TO_PLAY), "en-GB", "es-419"]);

export const TEXT_LIMITS = Object.freeze({ title: 30, shortDescription: 80, fullDescription: 4000 });
const TEXT_FIELDS = Object.keys(TEXT_LIMITS);

const MB = 1024 * 1024;
const SCREENSHOT_RULE = { kind: "screenshots", formats: ["png", "jpeg"], maxBytes: 8 * MB, min: 0, max: 8 };

// Play Console image requirements (support.google.com/googleplay/android-developer/answer/9866151).
export const IMAGE_TYPES = Object.freeze({
  phoneScreenshots: { ...SCREENSHOT_RULE, min: 2 },
  sevenInchScreenshots: SCREENSHOT_RULE,
  tenInchScreenshots: SCREENSHOT_RULE,
  featureGraphic: { kind: "single", formats: ["png", "jpeg"], maxBytes: 15 * MB, width: 1024, height: 500, alpha: false },
  icon: { kind: "single", formats: ["png"], maxBytes: 1024 * 1024, width: 512, height: 512 },
});

const IMAGE_EXTENSIONS = new Set([".png", ".jpg", ".jpeg"]);

export function textLength(value) {
  return [...value].length;
}

export function parseArgs(argv) {
  const options = {
    mode: "plan",
    configPath: null,
    textOnly: false,
    changesNotSentForReview: false,
    yes: false,
    help: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--check" || arg === "--plan" || arg === "--apply") options.mode = arg.slice(2);
    else if (arg === "--config") options.configPath = argv[++index];
    else if (arg.startsWith("--config=")) options.configPath = arg.slice("--config=".length);
    else if (arg === "--text-only") options.textOnly = true;
    else if (arg === "--changes-not-sent-for-review") options.changesNotSentForReview = true;
    else if (arg === "--yes") options.yes = true;
    else if (arg === "--help" || arg === "-h") options.help = true;
    else throw new Error(`Unknown option ${arg}. Run with --help.`);
  }
  if (!options.help && !options.configPath) throw new Error("Pass --config play-store/<version>.json.");
  return options;
}

export function readImageInfo(buffer) {
  if (buffer.length >= 26 && buffer.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) {
    const colorType = buffer[25];
    // Colour types 4 and 6 carry an alpha channel; a tRNS chunk before IDAT adds transparency to the rest.
    let hasAlpha = colorType === 4 || colorType === 6;
    for (let offset = 8; !hasAlpha && offset + 8 <= buffer.length; ) {
      const type = buffer.toString("latin1", offset + 4, offset + 8);
      if (type === "IDAT" || type === "IEND") break;
      hasAlpha = type === "tRNS";
      offset += 12 + buffer.readUInt32BE(offset);
    }
    return { format: "png", width: buffer.readUInt32BE(16), height: buffer.readUInt32BE(20), hasAlpha };
  }
  if (buffer.length >= 4 && buffer[0] === 0xff && buffer[1] === 0xd8) {
    let offset = 2;
    while (offset + 9 < buffer.length) {
      if (buffer[offset] !== 0xff) break;
      const marker = buffer[offset + 1];
      const length = buffer.readUInt16BE(offset + 2);
      const isFrame = marker >= 0xc0 && marker <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(marker);
      if (isFrame) {
        return { format: "jpeg", width: buffer.readUInt16BE(offset + 7), height: buffer.readUInt16BE(offset + 5), hasAlpha: false };
      }
      offset += 2 + length;
    }
  }
  return null;
}

export function validateImage(imageType, asset) {
  const rule = IMAGE_TYPES[imageType];
  const label = `${asset.language} ${imageType} ${asset.fileName}`;
  const info = asset.info;
  if (!info) return [`${label}: not a PNG or JPEG file.`];
  const errors = [];
  if (!rule.formats.includes(info.format)) errors.push(`${label}: must be ${rule.formats.join(" or ").toUpperCase()}.`);
  if (asset.bytes > rule.maxBytes) errors.push(`${label}: ${asset.bytes} bytes exceeds ${rule.maxBytes}.`);
  if (rule.kind === "screenshots") {
    const short = Math.min(info.width, info.height);
    const long = Math.max(info.width, info.height);
    if (short < 320 || long > 3840) errors.push(`${label}: ${info.width}×${info.height}; each side must be 320–3840 px.`);
    if (long > short * 2) errors.push(`${label}: ${info.width}×${info.height}; the long side may be at most twice the short side.`);
  } else {
    if (info.width !== rule.width || info.height !== rule.height) {
      errors.push(`${label}: ${info.width}×${info.height}; must be ${rule.width}×${rule.height}.`);
    }
    if (rule.alpha === false && info.hasAlpha) errors.push(`${label}: must not have an alpha channel.`);
  }
  return errors;
}

export function validateConfig(config) {
  const errors = [];
  if (config?.schemaVersion !== 1) errors.push("schemaVersion must be 1.");
  if (typeof config?.packageName !== "string" || !/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/u.test(config.packageName)) {
    errors.push("packageName must be an Android application ID.");
  }
  if (config?.imageBaseDir !== undefined && typeof config.imageBaseDir !== "string") errors.push("imageBaseDir must be a string.");
  const listings = config?.listings;
  if (!listings || typeof listings !== "object" || Object.keys(listings).length === 0) {
    errors.push("listings must contain at least one language.");
    return errors;
  }
  for (const [language, listing] of Object.entries(listings)) {
    if (!PLAY_LANGUAGES.has(language)) {
      errors.push(`listings.${language}: not one of the app's Play languages (${[...PLAY_LANGUAGES].join(", ")}).`);
      continue;
    }
    for (const key of Object.keys(listing ?? {})) {
      if (!TEXT_FIELDS.includes(key)) errors.push(`listings.${language}.${key}: unknown field.`);
    }
    for (const [field, limit] of Object.entries(TEXT_LIMITS)) {
      const value = listing?.[field];
      if (value === undefined) continue;
      if (typeof value !== "string" || value.trim() === "") {
        errors.push(`listings.${language}.${field}: must be a non-empty string.`);
      } else if (textLength(value) > limit) {
        errors.push(`listings.${language}.${field}: ${textLength(value)} characters exceeds ${limit}.`);
      }
    }
  }
  return errors;
}

function readAsset(language, filePath) {
  const content = readFileSync(filePath);
  return {
    language,
    fileName: path.basename(filePath),
    filePath,
    bytes: content.length,
    sha256: createHash("sha256").update(content).digest("hex"),
    info: readImageInfo(content),
  };
}

function imageFiles(directory) {
  return readdirSync(directory)
    .filter((name) => IMAGE_EXTENSIONS.has(path.extname(name).toLowerCase()) && !name.startsWith("."))
    .sort((a, b) => a.localeCompare(b, "en", { numeric: true }))
    .map((name) => path.join(directory, name));
}

// Images live in <imageBaseDir>/<language>/: a folder per screenshot type and featureGraphic/icon files.
// Only image types present locally are managed; everything else on Play is left alone.
export function loadImages(config, baseDir) {
  const images = new Map();
  if (!config.imageBaseDir) return images;
  const root = path.resolve(baseDir, config.imageBaseDir);
  for (const language of Object.keys(config.listings)) {
    const directory = path.join(root, language);
    if (!existsSync(directory)) continue;
    const byType = new Map();
    for (const [imageType, rule] of Object.entries(IMAGE_TYPES)) {
      if (rule.kind === "screenshots") {
        const folder = path.join(directory, imageType);
        if (existsSync(folder) && statSync(folder).isDirectory()) {
          byType.set(imageType, imageFiles(folder).map((file) => readAsset(language, file)));
        }
      } else {
        const matches = imageFiles(directory).filter((file) => path.parse(file).name === imageType);
        if (matches.length > 1) throw new Error(`${language}: more than one ${imageType} file.`);
        if (matches.length === 1) byType.set(imageType, [readAsset(language, matches[0])]);
      }
    }
    if (byType.size > 0) images.set(language, byType);
  }
  return images;
}

export function validateImages(images) {
  const errors = [];
  for (const [language, byType] of images) {
    for (const [imageType, assets] of byType) {
      const rule = IMAGE_TYPES[imageType];
      if (rule.kind === "screenshots" && (assets.length < rule.min || assets.length > rule.max)) {
        errors.push(`${language} ${imageType}: ${assets.length} files; Play accepts ${rule.min}–${rule.max}.`);
      }
      for (const asset of assets) errors.push(...validateImage(imageType, asset));
    }
  }
  return errors;
}

export function loadConfig(configPath, { cwd = process.cwd() } = {}) {
  const absoluteConfigPath = path.resolve(cwd, configPath);
  const config = JSON.parse(readFileSync(absoluteConfigPath, "utf8"));
  const errors = validateConfig(config);
  if (errors.length > 0) throw new Error(`Invalid ${configPath}:\n${errors.map((error) => `  - ${error}`).join("\n")}`);
  const images = loadImages(config, cwd);
  const imageErrors = validateImages(images);
  if (imageErrors.length > 0) throw new Error(`Invalid images:\n${imageErrors.map((error) => `  - ${error}`).join("\n")}`);
  return { config, absoluteConfigPath, images };
}

export function readServiceAccount(env = process.env) {
  const keyPath = env.PLAY_SERVICE_ACCOUNT_KEY_PATH || env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!keyPath) throw new Error("Set PLAY_SERVICE_ACCOUNT_KEY_PATH to the service-account JSON key path.");
  const key = JSON.parse(readFileSync(keyPath, "utf8"));
  if (key.type !== "service_account" || !key.client_email || !key.private_key) {
    throw new Error("PLAY_SERVICE_ACCOUNT_KEY_PATH does not point to a service-account JSON key.");
  }
  return key;
}

export async function fetchAccessToken(key, { fetchImpl = fetch, now = Date.now() } = {}) {
  const issuedAt = Math.floor(now / 1000);
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const unsigned = `${encode({ alg: "RS256", typ: "JWT" })}.${encode({
    iss: key.client_email,
    scope: SCOPE,
    aud: key.token_uri || "https://oauth2.googleapis.com/token",
    iat: issuedAt,
    exp: issuedAt + 3600,
  })}`;
  const signature = createSign("RSA-SHA256").update(unsigned).sign(key.private_key, "base64url");
  const response = await fetchImpl(key.token_uri || "https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsigned}.${signature}`,
    }),
  });
  // The response body may echo the request, so only the status is reported.
  if (!response.ok) throw new Error(`Google OAuth token request failed: HTTP ${response.status}.`);
  return (await response.json()).access_token;
}

export function createPlayClient({ accessToken, packageName, fetchImpl = fetch }) {
  const app = `/applications/${encodeURIComponent(packageName)}`;
  const api = `${API_ROOT}/androidpublisher/v3${app}`;
  const upload = `${API_ROOT}/upload/androidpublisher/v3${app}`;
  const listing = (editId, language) => `/edits/${editId}/listings/${encodeURIComponent(language)}`;

  async function call(method, url, { json, body, contentType } = {}) {
    const headers = { Authorization: `Bearer ${accessToken}` };
    if (json !== undefined) headers["Content-Type"] = "application/json";
    if (contentType) headers["Content-Type"] = contentType;
    const response = await fetchImpl(url, { method, headers, body: json !== undefined ? JSON.stringify(json) : body });
    const text = await response.text();
    const data = text ? JSON.parse(text) : {};
    if (!response.ok) {
      const message = data?.error?.message ?? response.statusText;
      const error = new Error(`Google Play API ${method} ${new URL(url).pathname} failed: HTTP ${response.status} ${message}`);
      error.status = response.status;
      throw error;
    }
    return data;
  }

  return {
    insertEdit: () => call("POST", `${api}/edits`, { json: {} }),
    deleteEdit: (editId) => call("DELETE", `${api}/edits/${editId}`),
    listListings: async (editId) => (await call("GET", `${api}/edits/${editId}/listings`)).listings ?? [],
    listImages: async (editId, language, imageType) =>
      (await call("GET", `${api}${listing(editId, language)}/${imageType}`)).images ?? [],
    updateListing: (editId, language, fields) =>
      call("PUT", `${api}${listing(editId, language)}`, { json: { language, ...fields } }),
    patchListing: (editId, language, fields) =>
      call("PATCH", `${api}${listing(editId, language)}`, { json: { language, ...fields } }),
    deleteAllImages: (editId, language, imageType) => call("DELETE", `${api}${listing(editId, language)}/${imageType}`),
    uploadImage: (editId, language, imageType, content, contentType) =>
      call("POST", `${upload}${listing(editId, language)}/${imageType}?uploadType=media`, { body: content, contentType }),
    validateEdit: (editId) => call("POST", `${api}/edits/${editId}:validate`),
    commitEdit: (editId, { changesNotSentForReview = false } = {}) =>
      call("POST", `${api}/edits/${editId}:commit${changesNotSentForReview ? "?changesNotSentForReview=true" : ""}`),
  };
}

export async function readRemote(client, editId, config, images, { textOnly = false } = {}) {
  const listings = new Map((await client.listListings(editId)).map((item) => [item.language, item]));
  const remoteImages = new Map();
  if (!textOnly) {
    for (const [language, byType] of images) {
      for (const imageType of byType.keys()) {
        // A language without a listing has no images yet.
        const items = listings.has(language) ? await client.listImages(editId, language, imageType) : [];
        remoteImages.set(`${language}\u0000${imageType}`, items);
      }
    }
  }
  return { listings, images: remoteImages };
}

export function imagesMatch(remote, local) {
  return remote.length === local.length && remote.every((image, index) => image.sha256?.toLowerCase() === local[index].sha256);
}

export function buildPlan(config, images, remote, { textOnly = false } = {}) {
  const changes = [];
  const blockers = [];
  for (const [language, listing] of Object.entries(config.listings)) {
    const current = remote.listings.get(language);
    const desired = Object.fromEntries(TEXT_FIELDS.filter((field) => listing[field] !== undefined).map((field) => [field, listing[field]]));
    if (!current) {
      const missing = TEXT_FIELDS.filter((field) => desired[field] === undefined);
      if (missing.length > 0) {
        blockers.push(`${language}: a new listing needs ${missing.join(", ")}.`);
        continue;
      }
      changes.push({ kind: "listing", action: "create", language, fields: desired, current: {} });
    } else {
      const fields = Object.fromEntries(Object.entries(desired).filter(([field, value]) => (current[field] ?? "") !== value));
      if (Object.keys(fields).length > 0) changes.push({ kind: "listing", action: "update", language, fields, current });
    }
    if (textOnly) continue;
    for (const [imageType, local] of images.get(language) ?? []) {
      const existing = remote.images.get(`${language}\u0000${imageType}`) ?? [];
      if (imagesMatch(existing, local)) continue;
      changes.push({ kind: "images", action: existing.length > 0 ? "replace" : "upload", language, imageType, local, remote: existing });
    }
  }
  const unmanaged = [...remote.listings.keys()].filter((language) => !(language in config.listings)).sort();
  return { changes, blockers, unmanaged };
}

function shortValue(value) {
  if (value === undefined || value === null || value === "") return "(empty)";
  const flattened = String(value).replace(/\s+/gu, " ").trim();
  return JSON.stringify(flattened.length > 72 ? `${flattened.slice(0, 69)}…` : flattened);
}

export function formatPlan(config, images, plan, { textOnly = false } = {}) {
  const lines = [`\nPlan for ${config.packageName}:`];
  for (const language of Object.keys(config.listings)) {
    const own = plan.changes.filter((change) => change.language === language);
    lines.push(`  ${language}${own.length === 0 ? ": matches" : ""}`);
    for (const change of own) {
      if (change.kind === "listing") {
        lines.push(`    ${change.action} listing`);
        for (const [field, value] of Object.entries(change.fields)) {
          lines.push(`      ${field} (${textLength(value)}/${TEXT_LIMITS[field]}): ${shortValue(change.current[field])} -> ${shortValue(value)}`);
        }
      } else {
        const verb = change.action === "replace" ? `replace ${change.remote.length} remote image(s) with` : "upload";
        lines.push(`    ${change.imageType}: ${verb} ${change.local.length} local image(s): ${change.local.map((asset) => asset.fileName).join(", ")}`);
      }
    }
    if (!textOnly && !images.has(language)) lines.push("    images: no local folder; remote images left unchanged");
  }
  for (const blocker of plan.blockers) lines.push(`  BLOCKED ${blocker}`);
  if (plan.unmanaged.length > 0) lines.push(`  Not in config, left unchanged: ${plan.unmanaged.join(", ")}`);
  if (textOnly) lines.push("  Images skipped (--text-only).");
  return lines.join("\n");
}

export async function applyChanges(client, editId, plan) {
  for (const change of plan.changes) {
    if (change.kind === "listing") {
      if (change.action === "create") await client.updateListing(editId, change.language, change.fields);
      else await client.patchListing(editId, change.language, change.fields);
      console.log(`  ${change.language}: listing ${change.action}d.`);
      continue;
    }
    if (change.remote.length > 0) await client.deleteAllImages(editId, change.language, change.imageType);
    for (const asset of change.local) {
      const contentType = asset.info.format === "png" ? "image/png" : "image/jpeg";
      await client.uploadImage(editId, change.language, change.imageType, readFileSync(asset.filePath), contentType);
    }
    console.log(`  ${change.language} ${change.imageType}: ${change.local.length} image(s) uploaded in order.`);
  }
}

async function withEdit(client, callback) {
  const edit = await client.insertEdit();
  try {
    return await callback(edit.id);
  } finally {
    // Committed edits no longer exist; deleting an uncommitted one discards it.
    await client.deleteEdit(edit.id).catch((error) => {
      if (error.status !== 404 && error.status !== 400) console.warn(`Warning: could not discard edit ${edit.id}: ${error.message}`);
    });
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log(HELP);
    return;
  }
  const { config, absoluteConfigPath, images } = loadConfig(options.configPath);
  const imageCount = [...images.values()].flatMap((byType) => [...byType.values()]).reduce((total, assets) => total + assets.length, 0);
  console.log(`Validated ${Object.keys(config.listings).length} languages and ${imageCount} images from ${absoluteConfigPath}.`);
  if (options.mode === "check") return;

  const accessToken = await fetchAccessToken(readServiceAccount());
  const client = createPlayClient({ accessToken, packageName: config.packageName });

  await withEdit(client, async (editId) => {
    const remote = await readRemote(client, editId, config, images, options);
    const plan = buildPlan(config, images, remote, options);
    console.log(formatPlan(config, images, plan, options));
    if (options.mode === "plan") {
      console.log("\nRead-only plan: the temporary edit is discarded and nothing was written.");
      return;
    }
    if (plan.blockers.length > 0) throw new Error("The plan is blocked; nothing was written.");
    if (plan.changes.length === 0) {
      console.log("\nEverything already matches. Nothing to write.");
      return;
    }
    const replacements = plan.changes.filter((change) => change.action === "replace").length;
    await confirmExact({
      expected: config.packageName,
      message: `Commit ${plan.changes.length} Google Play listing change(s)${
        replacements ? `, replacing ${replacements} remote image set(s)` : ""
      }${options.changesNotSentForReview ? " without sending them for review" : ""}?`,
      yes: options.yes,
    });
    await applyChanges(client, editId, plan);
    await client.validateEdit(editId);
    await client.commitEdit(editId, options);
    console.log(
      options.changesNotSentForReview
        ? "\nCommitted. Send the changes for review from Play Console when ready."
        : "\nCommitted. Play reviews listing changes before they appear in the store."
    );

    const verification = await withEdit(client, async (verifyEditId) =>
      buildPlan(config, images, await readRemote(client, verifyEditId, config, images, options), options)
    );
    if (verification.changes.length > 0) {
      throw new Error("Commit finished, but a fresh read still differs. Run play:listing:plan to inspect it.");
    }
    console.log("Verified: a fresh edit matches the local listing. No track, release or build was changed.");
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    console.error(`\n${error instanceof Error ? error.message : error}`);
    process.exitCode = 1;
  });
}
