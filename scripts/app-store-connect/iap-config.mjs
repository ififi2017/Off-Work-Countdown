import { existsSync, readFileSync, statSync } from "node:fs";
import { createHash } from "node:crypto";
import { basename, isAbsolute, resolve } from "node:path";

export const STORE_LOCALES = [
  "ar-SA",
  "de-DE",
  "en-US",
  "es-ES",
  "fr-FR",
  "hi",
  "id",
  "it",
  "ja",
  "ko",
  "pt-BR",
  "ru",
  "th",
  "tr",
  "vi",
  "zh-Hans",
  "zh-Hant",
];

export const PRODUCT_IDS = {
  monthly: "com.rainif.offworkcountdown.plus.monthly",
  yearly: "com.rainif.offworkcountdown.plus.yearly",
  lifetime: "com.rainif.offworkcountdown.plus.lifetime",
};

const NAME_MAX = 30;
const DESCRIPTION_MAX = 45;
const REVIEW_NOTE_MAX = 4000;
const KINDS = new Set(["subscription", "nonConsumable"]);

function fail(message) {
  throw new Error(`Invalid IAP config: ${message}`);
}

function expectObject(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(`${label} must be an object.`);
  }
}

function expectString(value, label) {
  if (typeof value !== "string" || value.trim() === "") {
    fail(`${label} must be a non-empty string.`);
  }
}

function codePointLength(value) {
  return [...value].length;
}

function validateLength(value, label, maximum) {
  const length = codePointLength(value);
  if (length > maximum) fail(`${label} is ${length} characters; the maximum is ${maximum}.`);
}

export function parseIapArgs(argv) {
  const options = {
    mode: null,
    configPath: null,
    skipScreenshot: false,
    replaceScreenshot: false,
    yes: false,
    help: false,
  };
  const positional = [];

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (["--check", "--plan", "--apply"].includes(argument)) {
      const nextMode = argument.slice(2);
      if (options.mode && options.mode !== nextMode) {
        throw new Error("Choose only one of --check, --plan, or --apply.");
      }
      options.mode = nextMode;
    } else if (argument === "--config") {
      options.configPath = argv[index + 1];
      index += 1;
      if (!options.configPath) throw new Error("--config requires a path.");
    } else if (argument.startsWith("--config=")) {
      options.configPath = argument.slice("--config=".length);
    } else if (argument === "--skip-screenshot") {
      options.skipScreenshot = true;
    } else if (argument === "--replace-screenshot") {
      options.replaceScreenshot = true;
    } else if (argument === "--yes" || argument === "-y") {
      options.yes = true;
    } else if (argument === "--help" || argument === "-h") {
      options.help = true;
    } else if (argument.startsWith("-")) {
      throw new Error(`Unknown option: ${argument}`);
    } else {
      positional.push(argument);
    }
  }

  if (positional.length > 1 || (positional.length === 1 && options.configPath)) {
    throw new Error("Pass exactly one config path, either positionally or with --config.");
  }
  options.configPath = options.configPath ?? positional[0] ?? "app-store-connect/iap.json";
  options.mode = options.mode ?? "plan";
  if (options.replaceScreenshot && options.skipScreenshot) {
    throw new Error("--replace-screenshot cannot be combined with --skip-screenshot.");
  }
  if (options.mode === "check" && (options.replaceScreenshot || options.yes)) {
    throw new Error("--check does not accept mutation flags.");
  }
  return options;
}

function validateLocalizationMap(map, label, { descriptionRequired }) {
  expectObject(map, label);
  const locales = Object.keys(map).sort();
  if (locales.join(",") !== STORE_LOCALES.join(",")) {
    fail(`${label} must include exactly the 17 App Store locales.`);
  }
  for (const locale of locales) {
    const localization = map[locale];
    expectObject(localization, `${label}.${locale}`);
    expectString(localization.name, `${label}.${locale}.name`);
    validateLength(localization.name, `${label}.${locale}.name`, NAME_MAX);
    if (codePointLength(localization.name) < 2) {
      fail(`${label}.${locale}.name must be at least 2 characters.`);
    }
    if (descriptionRequired) {
      expectString(localization.description, `${label}.${locale}.description`);
      validateLength(localization.description, `${label}.${locale}.description`, DESCRIPTION_MAX);
    } else if (localization.description !== undefined) {
      fail(`${label}.${locale} does not accept a description.`);
    }
  }
}

export function validateIapConfig(config) {
  expectObject(config, "root");
  if (config.schemaVersion !== 1) fail("schemaVersion must be 1.");
  expectString(config.bundleId, "bundleId");
  expectString(config.subscriptionGroup, "subscriptionGroup");
  expectString(config.reviewScreenshot, "reviewScreenshot");
  expectString(config.reviewNote, "reviewNote");
  validateLength(config.reviewNote, "reviewNote", REVIEW_NOTE_MAX);
  validateLocalizationMap(config.groupLocalizations, "groupLocalizations", { descriptionRequired: false });
  expectObject(config.products, "products");
  const expected = [PRODUCT_IDS.monthly, PRODUCT_IDS.yearly, PRODUCT_IDS.lifetime];
  if (Object.keys(config.products).sort().join(",") !== expected.slice().sort().join(",")) {
    fail(`products must be ${expected.join(", ")}.`);
  }
  for (const [productId, product] of Object.entries(config.products)) {
    expectObject(product, `products.${productId}`);
    if (!KINDS.has(product.kind)) fail(`products.${productId}.kind must be subscription or nonConsumable.`);
    const expectedKind = productId === PRODUCT_IDS.lifetime ? "nonConsumable" : "subscription";
    if (product.kind !== expectedKind) {
      fail(`products.${productId}.kind must be ${expectedKind}.`);
    }
    validateLocalizationMap(product.localizations, `products.${productId}.localizations`, {
      descriptionRequired: true,
    });
  }
}

export function loadIapConfig(configPath, { requireScreenshot = true } = {}) {
  const resolved = isAbsolute(configPath) ? configPath : resolve(configPath);
  if (!existsSync(resolved)) fail(`file not found: ${resolved}`);
  const config = JSON.parse(readFileSync(resolved, "utf8"));
  validateIapConfig(config);
  const screenshotPath = isAbsolute(config.reviewScreenshot)
    ? config.reviewScreenshot
    : resolve(config.reviewScreenshot);
  if (requireScreenshot && !existsSync(screenshotPath)) {
    fail(`review screenshot not found: ${screenshotPath}`);
  }
  const screenshot = existsSync(screenshotPath)
    ? {
        path: screenshotPath,
        fileName: basename(screenshotPath),
        fileSize: statSync(screenshotPath).size,
        checksum: createHash("md5").update(readFileSync(screenshotPath)).digest("hex"),
      }
    : null;
  return { config, screenshot };
}

export function localizationChanges(current, desired) {
  const changes = {};
  for (const field of Object.keys(desired)) {
    if ((current?.[field] ?? null) !== desired[field]) changes[field] = desired[field];
  }
  return changes;
}
