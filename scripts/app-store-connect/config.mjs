import { createHash } from "node:crypto";
import { existsSync, readFileSync, statSync } from "node:fs";
import { basename, isAbsolute, resolve } from "node:path";

export const APP_INFO_FIELDS = [
  "name",
  "subtitle",
  "privacyPolicyUrl",
  "privacyChoicesUrl",
];

export const VERSION_LOCALIZATION_FIELDS = [
  "promotionalText",
  "description",
  "keywords",
  "supportUrl",
  "marketingUrl",
  "whatsNew",
];

export const EDITABLE_STATES = new Set([
  "PREPARE_FOR_SUBMISSION",
  "READY_FOR_REVIEW",
  "INVALID_BINARY",
  "REJECTED",
  "METADATA_REJECTED",
  "DEVELOPER_REJECTED",
]);

const PLATFORMS = new Set(["IOS", "MAC_OS", "TV_OS", "VISION_OS"]);
const RELEASE_TYPES = new Set(["MANUAL", "AFTER_APPROVAL", "SCHEDULED"]);
const SCREENSHOT_TYPES = new Set([
  "APP_IPHONE_69",
  "APP_IPHONE_67",
  "APP_IPHONE_61",
  "APP_IPHONE_65",
  "APP_IPHONE_58",
  "APP_IPHONE_55",
  "APP_IPHONE_47",
  "APP_IPHONE_40",
  "APP_IPHONE_35",
  "APP_IPAD_PRO_3GEN_129",
  "APP_IPAD_PRO_3GEN_11",
  "APP_IPAD_PRO_129",
  "APP_IPAD_105",
  "APP_IPAD_97",
  "APP_DESKTOP",
  "APP_WATCH_ULTRA",
  "APP_WATCH_SERIES_10",
  "APP_WATCH_SERIES_7",
  "APP_WATCH_SERIES_4",
  "APP_WATCH_SERIES_3",
  "APP_APPLE_TV",
  "APP_APPLE_VISION_PRO",
]);
// App preview sets still use the older PreviewType names. IPHONE_67 is the
// 6.9" slot; 886×1920 is the accepted portrait size for 6.1–6.9".
const PREVIEW_TYPES = new Set([
  "IPHONE_67",
  "IPHONE_65",
  "IPHONE_61",
  "IPHONE_58",
  "IPHONE_55",
  "IPHONE_47",
  "IPHONE_40",
  "IPHONE_35",
  "IPAD_PRO_3GEN_129",
  "IPAD_PRO_3GEN_11",
  "IPAD_PRO_129",
  "IPAD_105",
  "IPAD_97",
  "DESKTOP",
  "APPLE_TV",
  "APPLE_VISION_PRO",
]);

const PLACEHOLDER_PATTERN = /\bYOUR(?:\b|_)|^填写|^WHAT(?:'S| IS)\b/u;

function fail(message) {
  throw new Error(`Invalid App Store Connect config: ${message}`);
}

function expectObject(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(`${label} must be an object.`);
  }
}

function expectString(value, label, { nullable = false, required = false } = {}) {
  if (value === undefined && !required) return;
  if (value === null && nullable) return;
  if (typeof value !== "string" || (required && value.trim() === "")) {
    fail(`${label} must be ${nullable ? "a string or null" : "a non-empty string"}.`);
  }
}

function codePointLength(value) {
  return [...value].length;
}

function validateLength(value, label, maximum) {
  if (typeof value === "string" && codePointLength(value) > maximum) {
    fail(`${label} is ${codePointLength(value)} characters; the maximum is ${maximum}.`);
  }
}

function validateUrl(value, label) {
  if (value === undefined || value === null) return;
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" && url.protocol !== "http:") throw new Error();
  } catch {
    fail(`${label} must be an http or https URL.`);
  }
}

function validateKnownKeys(value, allowed, label) {
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) fail(`${label} contains unknown property ${JSON.stringify(key)}.`);
  }
}

export function parseArgs(argv) {
  const options = {
    mode: null,
    configPath: null,
    includeScreenshots: false,
    replaceScreenshots: false,
    includePreviews: false,
    replacePreviews: false,
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
    } else if (argument === "--include-screenshots") {
      options.includeScreenshots = true;
    } else if (argument === "--replace-screenshots") {
      options.replaceScreenshots = true;
    } else if (argument === "--include-previews") {
      options.includePreviews = true;
    } else if (argument === "--replace-previews") {
      options.replacePreviews = true;
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
  options.configPath = options.configPath ?? positional[0] ?? "app-store-connect/ios.json";
  options.mode = options.mode ?? "plan";
  if (options.replaceScreenshots && !options.includeScreenshots) {
    throw new Error("--replace-screenshots requires --include-screenshots.");
  }
  if (options.replacePreviews && !options.includePreviews) {
    throw new Error("--replace-previews requires --include-previews.");
  }
  if (options.mode === "check" && (options.replaceScreenshots || options.replacePreviews || options.yes)) {
    throw new Error("--check does not accept mutation flags.");
  }
  return options;
}

export function validateConfig(config) {
  expectObject(config, "root");
  validateKnownKeys(
    config,
    new Set([
      "$schema",
      "schemaVersion",
      "exportedFrom",
      "screenshotBaseDir",
      "previewBaseDir",
      "app",
      "localizations",
    ]),
    "root"
  );
  if (config.schemaVersion !== 1) fail("schemaVersion must be 1.");
  expectString(config.screenshotBaseDir, "screenshotBaseDir");
  expectString(config.previewBaseDir, "previewBaseDir");
  if (config.exportedFrom !== undefined) {
    expectObject(config.exportedFrom, "exportedFrom");
    validateKnownKeys(
      config.exportedFrom,
      new Set(["platform", "versionString", "exportedAt"]),
      "exportedFrom"
    );
    if (!PLATFORMS.has(config.exportedFrom.platform)) {
      fail(`unsupported exportedFrom.platform ${config.exportedFrom.platform}.`);
    }
    expectString(config.exportedFrom.versionString, "exportedFrom.versionString", { required: true });
    expectString(config.exportedFrom.exportedAt, "exportedFrom.exportedAt", { required: true });
    if (Number.isNaN(Date.parse(config.exportedFrom.exportedAt))) {
      fail("exportedFrom.exportedAt must be an ISO-8601 date-time.");
    }
  }

  expectObject(config.app, "app");
  validateKnownKeys(
    config.app,
    new Set([
      "bundleId",
      "platform",
      "versionString",
      "createVersionIfMissing",
      "releaseType",
      "earliestReleaseDate",
      "copyright",
      "usesIdfa",
    ]),
    "app"
  );
  expectString(config.app.bundleId, "app.bundleId", { required: true });
  expectString(config.app.versionString, "app.versionString", { required: true });
  if (!PLATFORMS.has(config.app.platform)) fail(`unsupported platform ${config.app.platform}.`);
  if (
    config.app.createVersionIfMissing !== undefined &&
    typeof config.app.createVersionIfMissing !== "boolean"
  ) {
    fail("app.createVersionIfMissing must be a boolean.");
  }
  if (config.app.releaseType !== undefined && !RELEASE_TYPES.has(config.app.releaseType)) {
    fail(`unsupported releaseType ${config.app.releaseType}.`);
  }
  expectString(config.app.copyright, "app.copyright");
  expectString(config.app.earliestReleaseDate, "app.earliestReleaseDate");
  if (config.app.releaseType === "SCHEDULED" && !config.app.earliestReleaseDate) {
    fail("app.earliestReleaseDate is required for SCHEDULED releaseType.");
  }
  if (config.app.earliestReleaseDate && Number.isNaN(Date.parse(config.app.earliestReleaseDate))) {
    fail("app.earliestReleaseDate must be an ISO-8601 date-time.");
  }
  if (config.app.usesIdfa !== undefined && typeof config.app.usesIdfa !== "boolean") {
    fail("app.usesIdfa must be a boolean.");
  }

  expectObject(config.localizations, "localizations");
  const locales = Object.entries(config.localizations);
  if (locales.length === 0) fail("localizations must contain at least one locale.");

  const allowedLocalizationKeys = new Set([
    ...APP_INFO_FIELDS,
    ...VERSION_LOCALIZATION_FIELDS,
    "screenshots",
    "previews",
  ]);

  for (const [locale, localization] of locales) {
    if (!/^[a-z]{2,3}(?:-[A-Za-z0-9]+)*$/u.test(locale)) {
      fail(`invalid locale ${JSON.stringify(locale)}.`);
    }
    expectObject(localization, `localizations.${locale}`);
    validateKnownKeys(localization, allowedLocalizationKeys, `localizations.${locale}`);

    for (const field of APP_INFO_FIELDS) {
      expectString(localization[field], `localizations.${locale}.${field}`, {
        nullable: field !== "name",
      });
    }
    for (const field of VERSION_LOCALIZATION_FIELDS) {
      expectString(localization[field], `localizations.${locale}.${field}`, {
        nullable: ["promotionalText", "marketingUrl", "whatsNew"].includes(field),
      });
    }
    validateLength(localization.name, `localizations.${locale}.name`, 30);
    validateLength(localization.subtitle, `localizations.${locale}.subtitle`, 30);
    validateLength(localization.promotionalText, `localizations.${locale}.promotionalText`, 170);
    validateLength(localization.description, `localizations.${locale}.description`, 4000);
    validateLength(localization.whatsNew, `localizations.${locale}.whatsNew`, 4000);
    validateLength(localization.keywords, `localizations.${locale}.keywords`, 100);
    for (const field of ["privacyPolicyUrl", "privacyChoicesUrl", "supportUrl", "marketingUrl"]) {
      validateUrl(localization[field], `localizations.${locale}.${field}`);
    }

    if (localization.screenshots !== undefined) {
      expectObject(localization.screenshots, `localizations.${locale}.screenshots`);
      for (const [displayType, paths] of Object.entries(localization.screenshots)) {
        if (!SCREENSHOT_TYPES.has(displayType)) {
          fail(`localizations.${locale}.screenshots uses unsupported display type ${displayType}.`);
        }
        if (!Array.isArray(paths) || paths.length < 1 || paths.length > 10) {
          fail(`localizations.${locale}.screenshots.${displayType} must contain 1 to 10 paths.`);
        }
        if (new Set(paths).size !== paths.length) {
          fail(`localizations.${locale}.screenshots.${displayType} contains duplicate paths.`);
        }
        for (const path of paths) expectString(path, `${locale}.${displayType} screenshot`, { required: true });
      }
    }
    if (localization.previews !== undefined) {
      expectObject(localization.previews, `localizations.${locale}.previews`);
      for (const [previewType, paths] of Object.entries(localization.previews)) {
        if (!PREVIEW_TYPES.has(previewType)) {
          fail(`localizations.${locale}.previews uses unsupported preview type ${previewType}.`);
        }
        if (!Array.isArray(paths) || paths.length < 1 || paths.length > 3) {
          fail(`localizations.${locale}.previews.${previewType} must contain 1 to 3 paths.`);
        }
        if (new Set(paths).size !== paths.length) {
          fail(`localizations.${locale}.previews.${previewType} contains duplicate paths.`);
        }
        for (const path of paths) expectString(path, `${locale}.${previewType} preview`, { required: true });
      }
    }
  }

  return config;
}

function mediaPath(config, path, cwd, baseDirKey) {
  if (isAbsolute(path)) return path;
  return resolve(cwd, config[baseDirKey] ?? ".", path);
}

export function loadConfig(configPath, { cwd = process.cwd(), requireFiles = true } = {}) {
  const absoluteConfigPath = resolve(cwd, configPath);
  if (!existsSync(absoluteConfigPath)) {
    throw new Error(
      `Config not found: ${absoluteConfigPath}\nCopy app-store-connect/ios.example.json and fill in the metadata first.`
    );
  }
  const config = validateConfig(JSON.parse(readFileSync(absoluteConfigPath, "utf8")));
  const screenshots = new Map();
  const previews = new Map();

  for (const [locale, localization] of Object.entries(config.localizations)) {
    for (const [displayType, paths] of Object.entries(localization.screenshots ?? {})) {
      const assets = paths.map((path) => {
        const absolutePath = mediaPath(config, path, cwd, "screenshotBaseDir");
        if (requireFiles && !existsSync(absolutePath)) {
          fail(`screenshot not found: ${absolutePath}. Run npm run shots:ios first.`);
        }
        if (!requireFiles) return { path: absolutePath, fileName: basename(absolutePath) };
        const extension = absolutePath.toLowerCase().match(/\.(png|jpe?g)$/u)?.[1];
        if (!extension) fail(`screenshot must be PNG or JPEG: ${absolutePath}.`);
        const size = statSync(absolutePath).size;
        if (size === 0) fail(`screenshot is empty: ${absolutePath}.`);
        const content = readFileSync(absolutePath);
        return {
          path: absolutePath,
          fileName: basename(absolutePath),
          fileSize: size,
          checksum: createHash("md5").update(content).digest("hex"),
        };
      });
      screenshots.set(`${locale}\u0000${displayType}`, assets);
    }
    for (const [previewType, paths] of Object.entries(localization.previews ?? {})) {
      const assets = paths.map((path) => {
        const absolutePath = mediaPath(config, path, cwd, "previewBaseDir");
        if (requireFiles && !existsSync(absolutePath)) {
          fail(`preview not found: ${absolutePath}.`);
        }
        if (!requireFiles) return { path: absolutePath, fileName: basename(absolutePath) };
        const extension = absolutePath.toLowerCase().match(/\.(mov|mp4|m4v)$/u)?.[1];
        if (!extension) fail(`preview must be MOV or MP4: ${absolutePath}.`);
        const size = statSync(absolutePath).size;
        if (size === 0) fail(`preview is empty: ${absolutePath}.`);
        const content = readFileSync(absolutePath);
        return {
          path: absolutePath,
          fileName: basename(absolutePath),
          fileSize: size,
          checksum: createHash("md5").update(content).digest("hex"),
          mimeType: extension === "mp4" || extension === "m4v" ? "video/mp4" : "video/quicktime",
        };
      });
      previews.set(`${locale}\u0000${previewType}`, assets);
    }
  }

  return { config, absoluteConfigPath, screenshots, previews };
}

export function findPlaceholders(config) {
  const placeholders = [];
  const visit = (value, path) => {
    if (typeof value === "string" && PLACEHOLDER_PATTERN.test(value)) placeholders.push(path);
    else if (Array.isArray(value)) value.forEach((item, index) => visit(item, `${path}[${index}]`));
    else if (value && typeof value === "object") {
      for (const [key, item] of Object.entries(value)) visit(item, path ? `${path}.${key}` : key);
    }
  };
  visit(config, "");
  return placeholders;
}

export function pickFields(value, fields) {
  return Object.fromEntries(fields.filter((field) => field in value).map((field) => [field, value[field]]));
}

export function diffFields(current, desired) {
  return Object.fromEntries(
    Object.entries(desired).filter(([key, value]) => (current ?? {})[key] !== value)
  );
}

export function screenshotSetMatches(remoteScreenshots, localAssets) {
  if (remoteScreenshots.length !== localAssets.length) return false;
  return remoteScreenshots.every((remote, index) => {
    const attributes = remote.attributes ?? {};
    return (
      attributes.fileName === localAssets[index].fileName &&
      attributes.sourceFileChecksum?.toLowerCase() === localAssets[index].checksum?.toLowerCase() &&
      (attributes.assetDeliveryState?.state ?? attributes.assetDeliveryState) === "COMPLETE"
    );
  });
}

export function missingCreateFields(localization, resource) {
  const required = resource === "appInfo" ? ["name"] : ["description", "keywords", "supportUrl"];
  return required.filter((field) => typeof localization[field] !== "string" || localization[field] === "");
}
