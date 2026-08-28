#!/usr/bin/env node

import { createHash } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, extname, isAbsolute, relative, resolve } from "node:path";
import { createApiClient, credentialsFromEnv } from "./app-store-connect/api.mjs";
import {
  APP_INFO_FIELDS,
  EDITABLE_STATES,
  VERSION_LOCALIZATION_FIELDS,
  pickFields,
  validateConfig,
} from "./app-store-connect/config.mjs";

const HELP = `Export App Store Connect metadata

Usage:
  npm run asc:export -- --source-version 3.1.6 --target-version 3.1.7 \\
    --output app-store-connect/ios/3.1.7.json [--download-screenshots] [--force]

Options:
  --bundle-id ID            Defaults to com.rainif.offworkcountdown.macappstore.
  --platform PLATFORM       Defaults to IOS.
  --source-version VERSION  Existing App Store version to read. Required.
  --target-version VERSION  Version written into the sync config. Defaults to the source version.
  --output PATH             JSON output path. Defaults to app-store-connect/ios/VERSION.json.
  --download-screenshots    Download every source screenshot and add it to the config.
  --screenshots-dir PATH    Defaults to app-store-connect/screenshots/SOURCE_VERSION.
  --force                   Overwrite the output and downloaded files.

The export is read-only in App Store Connect. It never creates a version or review submission.
`;

const DEFAULT_BUNDLE_ID = "com.rainif.offworkcountdown.macappstore";
const PLATFORMS = new Set(["IOS", "MAC_OS", "TV_OS", "VISION_OS"]);

function valueAfter(argv, index, flag) {
  const value = argv[index + 1];
  if (!value || value.startsWith("-")) throw new Error(`${flag} requires a value.`);
  return value;
}

export function parseExportArgs(argv) {
  const options = {
    bundleId: DEFAULT_BUNDLE_ID,
    platform: "IOS",
    sourceVersion: null,
    targetVersion: null,
    outputPath: null,
    downloadScreenshots: false,
    screenshotsDir: null,
    force: false,
    help: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    const inline = argument.match(/^(--[^=]+)=(.*)$/u);
    const flag = inline?.[1] ?? argument;
    const next = () => inline?.[2] || valueAfter(argv, index, flag);
    const consume = () => {
      if (!inline) index += 1;
    };
    if (flag === "--bundle-id") {
      options.bundleId = next();
      consume();
    } else if (flag === "--platform") {
      options.platform = next();
      consume();
    } else if (flag === "--source-version") {
      options.sourceVersion = next();
      consume();
    } else if (flag === "--target-version") {
      options.targetVersion = next();
      consume();
    } else if (flag === "--output") {
      options.outputPath = next();
      consume();
    } else if (flag === "--screenshots-dir") {
      options.screenshotsDir = next();
      consume();
    } else if (argument === "--download-screenshots") {
      options.downloadScreenshots = true;
    } else if (argument === "--force") {
      options.force = true;
    } else if (argument === "--help" || argument === "-h") {
      options.help = true;
    } else {
      throw new Error(`Unknown option: ${argument}`);
    }
  }

  if (options.help) return options;
  if (!options.sourceVersion) throw new Error("--source-version is required.");
  if (!PLATFORMS.has(options.platform)) throw new Error(`Unsupported platform: ${options.platform}.`);
  options.targetVersion = options.targetVersion ?? options.sourceVersion;
  const platformName = options.platform === "IOS" ? "ios" : options.platform.toLowerCase().replaceAll("_", "-");
  options.outputPath = options.outputPath ?? `app-store-connect/${platformName}/${options.targetVersion}.json`;
  options.screenshotsDir = options.screenshotsDir ?? `app-store-connect/screenshots/${options.sourceVersion}`;
  if (options.screenshotsDir && !options.downloadScreenshots && argv.some((item) => item.startsWith("--screenshots-dir"))) {
    throw new Error("--screenshots-dir requires --download-screenshots.");
  }
  return options;
}

function query(path, parameters) {
  const url = new URL(path, "https://api.appstoreconnect.apple.com");
  for (const [key, value] of Object.entries(parameters)) {
    if (value !== undefined && value !== null) url.searchParams.set(key, String(value));
  }
  return `${url.pathname}${url.search}`;
}

function resourceState(resource) {
  return resource?.attributes?.state ?? resource?.attributes?.appVersionState ?? resource?.attributes?.appStoreState;
}

async function findSingle(api, path, label) {
  const resources = await api.list(path);
  if (resources.length !== 1) {
    throw new Error(`${resources.length === 0 ? "No" : "Multiple"} ${label} found.`);
  }
  return resources[0];
}

async function findApp(api, bundleId) {
  return findSingle(api, query("/v1/apps", { "filter[bundleId]": bundleId, limit: 50 }), `apps for ${bundleId}`);
}

async function findVersion(api, appId, options) {
  return findSingle(
    api,
    query(`/v1/apps/${appId}/appStoreVersions`, {
      "filter[platform]": options.platform,
      "filter[versionString]": options.sourceVersion,
      limit: 200,
    }),
    `${options.platform} versions named ${options.sourceVersion}`
  );
}

function equivalentState(left, right) {
  const live = new Set(["READY_FOR_SALE", "READY_FOR_DISTRIBUTION"]);
  return left === right || (live.has(left) && live.has(right));
}

export function chooseAppInfoForVersion(appInfos, version) {
  const versionState = resourceState(version);
  const matching = appInfos.filter((appInfo) => equivalentState(resourceState(appInfo), versionState));
  if (matching.length === 1) return matching[0];
  if (EDITABLE_STATES.has(versionState)) {
    const editable = appInfos.filter((appInfo) => EDITABLE_STATES.has(resourceState(appInfo)));
    if (editable.length === 1) return editable[0];
  }
  if (appInfos.length === 1) return appInfos[0];
  throw new Error(
    `Cannot choose App Info for version state ${versionState ?? "UNKNOWN"}; candidates: ${appInfos
      .map((item) => `${item.id}:${resourceState(item)}`)
      .join(", ")}`
  );
}

function indexByLocale(resources) {
  return new Map(resources.map((resource) => [resource.attributes.locale, resource]));
}

function portablePath(path, cwd) {
  if (!isAbsolute(path)) return path.replaceAll("\\", "/");
  const local = relative(cwd, path);
  return (local.startsWith("..") ? path : local).replaceAll("\\", "/");
}

function schemaPath(outputPath, cwd) {
  const schema = resolve(cwd, "app-store-connect/metadata.schema.json");
  const path = relative(dirname(outputPath), schema).replaceAll("\\", "/");
  return path.startsWith(".") ? path : `./${path}`;
}

export function imageAssetUrl(imageAsset, fileName) {
  if (!imageAsset?.templateUrl || !imageAsset.width || !imageAsset.height) {
    throw new Error(`Screenshot ${fileName} has no downloadable imageAsset.`);
  }
  const extension = extname(fileName).slice(1).toLowerCase();
  const format = extension === "jpeg" ? "jpg" : extension || "png";
  const replacements = { w: imageAsset.width, h: imageAsset.height, f: format };
  let url = imageAsset.templateUrl;
  for (const [token, value] of Object.entries(replacements)) {
    url = url.replace(new RegExp(`\\{${token}\\}|%7B${token}%7D`, "giu"), String(value));
  }
  if (/\{[whf]\}|%7B[whf]%7D/iu.test(url)) {
    throw new Error(`Unsupported imageAsset URL template for ${fileName}.`);
  }
  return url;
}

function safeFileName(value, index) {
  const fileName = basename(value || `${String(index + 1).padStart(2, "0")}.png`).replace(/[^0-9A-Za-z._-]+/gu, "-");
  return fileName || `${String(index + 1).padStart(2, "0")}.png`;
}

function atomicWrite(path, content, { force }) {
  if (existsSync(path) && !force) throw new Error(`Refusing to overwrite ${path}; pass --force after inspecting it.`);
  mkdirSync(dirname(path), { recursive: true });
  const temporary = `${path}.tmp-${process.pid}`;
  try {
    writeFileSync(temporary, content);
    renameSync(temporary, path);
  } catch (error) {
    if (existsSync(temporary)) unlinkSync(temporary);
    throw error;
  }
}

async function downloadScreenshot(screenshot, destination, options, fetchImpl = fetch) {
  const url = imageAssetUrl(screenshot.attributes.imageAsset, screenshot.attributes.fileName);
  const response = await fetchImpl(url, { headers: { Accept: "image/*" } });
  if (!response.ok) {
    throw new Error(`Failed to download ${screenshot.attributes.fileName} (${response.status}).`);
  }
  const content = Buffer.from(await response.arrayBuffer());
  if (content.length === 0) throw new Error(`Downloaded screenshot is empty: ${screenshot.attributes.fileName}.`);
  atomicWrite(destination, content, options);
  return {
    byteLength: content.length,
    checksum: createHash("md5").update(content).digest("hex"),
  };
}

async function exportScreenshots(api, versionLocalizations, config, options, cwd) {
  const screenshotRoot = resolve(cwd, options.screenshotsDir);
  let downloaded = 0;
  for (const localization of versionLocalizations) {
    const locale = localization.attributes.locale;
    const sets = await api.list(
      query(`/v1/appStoreVersionLocalizations/${localization.id}/appScreenshotSets`, { limit: 200 })
    );
    for (const set of sets.sort((left, right) =>
      left.attributes.screenshotDisplayType.localeCompare(right.attributes.screenshotDisplayType)
    )) {
      const displayType = set.attributes.screenshotDisplayType;
      const screenshots = await api.list(query(`/v1/appScreenshotSets/${set.id}/appScreenshots`, { limit: 200 }));
      const usedNames = new Set();
      const paths = [];
      for (const [index, screenshot] of screenshots.entries()) {
        let fileName = safeFileName(screenshot.attributes.fileName, index);
        if (usedNames.has(fileName)) fileName = `${String(index + 1).padStart(2, "0")}-${fileName}`;
        usedNames.add(fileName);
        const relativePath = `${locale}/${displayType}/${fileName}`;
        const destination = resolve(screenshotRoot, relativePath);
        await downloadScreenshot(screenshot, destination, options);
        paths.push(relativePath);
        downloaded += 1;
        console.log(`  downloaded ${locale}/${displayType}/${fileName}`);
      }
      if (paths.length > 0) {
        config.localizations[locale].screenshots ??= {};
        config.localizations[locale].screenshots[displayType] = paths;
      }
    }
  }
  config.screenshotBaseDir = portablePath(screenshotRoot, cwd);
  return downloaded;
}

export async function buildExport(api, options, { cwd = process.cwd(), now = new Date() } = {}) {
  const app = await findApp(api, options.bundleId);
  const version = await findVersion(api, app.id, options);
  const appInfos = await api.list(query(`/v1/apps/${app.id}/appInfos`, { limit: 50 }));
  const appInfo = chooseAppInfoForVersion(appInfos, version);
  const appInfoLocalizations = indexByLocale(
    await api.list(query(`/v1/appInfos/${appInfo.id}/appInfoLocalizations`, { limit: 200 }))
  );
  const versionLocalizations = await api.list(
    query(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations`, { limit: 200 })
  );
  const localizations = {};
  for (const localization of [...versionLocalizations].sort((left, right) =>
    left.attributes.locale.localeCompare(right.attributes.locale)
  )) {
    const locale = localization.attributes.locale;
    localizations[locale] = {
      ...pickFields(appInfoLocalizations.get(locale)?.attributes ?? {}, APP_INFO_FIELDS),
      ...pickFields(localization.attributes, VERSION_LOCALIZATION_FIELDS),
    };
  }
  const attributes = version.attributes ?? {};
  const config = {
    $schema: schemaPath(resolve(cwd, options.outputPath), cwd),
    schemaVersion: 1,
    exportedFrom: {
      platform: options.platform,
      versionString: options.sourceVersion,
      exportedAt: now.toISOString(),
    },
    app: {
      bundleId: options.bundleId,
      platform: options.platform,
      versionString: options.targetVersion,
      createVersionIfMissing: options.targetVersion !== options.sourceVersion,
      releaseType: "MANUAL",
      ...(attributes.copyright ? { copyright: attributes.copyright } : {}),
      ...(typeof attributes.usesIdfa === "boolean" ? { usesIdfa: attributes.usesIdfa } : {}),
    },
    localizations,
  };
  validateConfig(config);
  return { config, versionLocalizations };
}

async function main() {
  const options = parseExportArgs(process.argv.slice(2));
  if (options.help) {
    console.log(HELP);
    return;
  }
  const cwd = process.cwd();
  const outputPath = resolve(cwd, options.outputPath);
  if (existsSync(outputPath) && !options.force) {
    throw new Error(`Refusing to overwrite ${outputPath}; pass --force after inspecting it.`);
  }
  const api = createApiClient({ credentials: credentialsFromEnv() });
  console.log(`Reading ${options.platform} ${options.sourceVersion} from App Store Connect...`);
  const exported = await buildExport(api, options, { cwd });
  let downloaded = 0;
  if (options.downloadScreenshots) {
    downloaded = await exportScreenshots(api, exported.versionLocalizations, exported.config, options, cwd);
  }
  validateConfig(exported.config);
  atomicWrite(outputPath, `${JSON.stringify(exported.config, null, 2)}\n`, options);
  console.log(
    `Exported ${Object.keys(exported.config.localizations).length} locales${
      options.downloadScreenshots ? ` and ${downloaded} screenshots` : ""
    } to ${outputPath}.`
  );
  if (options.targetVersion !== options.sourceVersion) {
    console.log(
      `The config targets ${options.targetVersion}; review copied whatsNew text and copyright before running asc:sync.`
    );
  }
  console.log("No App Store Connect data was changed and no review submission was created.");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    console.error(`\n${error instanceof Error ? error.message : error}`);
    process.exitCode = 1;
  });
}
