#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";
import { createApiClient, credentialsFromEnv } from "./app-store-connect/api.mjs";
import {
  APP_INFO_FIELDS,
  EDITABLE_STATES,
  VERSION_LOCALIZATION_FIELDS,
  diffFields,
  findPlaceholders,
  loadConfig,
  missingCreateFields,
  parseArgs,
  pickFields,
  screenshotSetMatches,
} from "./app-store-connect/config.mjs";
import { confirmExact } from "./release-helpers.mjs";

const HELP = `App Store Connect metadata sync

Usage:
  npm run asc:check -- --config app-store-connect/ios/3.1.8.json
  npm run asc:plan  -- --config app-store-connect/ios/3.1.8.json [--include-screenshots]
  npm run asc:sync  -- --config app-store-connect/ios/3.1.8.json [--include-screenshots] [--replace-screenshots] [--yes]

Modes:
  --check                 Validate JSON, field limits, URLs, and local screenshot files. No credentials needed.
  --plan                  Read App Store Connect and print changes. This is the default and never writes.
  --apply                 Apply the printed metadata changes. Does not submit the version for review.

Screenshot safety:
  --include-screenshots   Include configured screenshot sets in the plan/apply run.
  --replace-screenshots   Permit deleting and recreating a non-matching existing screenshot set.

Credentials (team API key):
  ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH
`;

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

function isEditable(resource) {
  return EDITABLE_STATES.has(resourceState(resource));
}

function chooseAppInfo(appInfos) {
  const editable = appInfos.filter(isEditable);
  if (editable.length > 1) {
    throw new Error(`App Store Connect returned multiple editable App Info resources: ${editable.map((item) => item.id).join(", ")}`);
  }
  return editable[0] ?? appInfos[0] ?? null;
}

function indexByLocale(resources) {
  return new Map(resources.map((resource) => [resource.attributes.locale, resource]));
}

function shortValue(value) {
  if (value === null) return "null";
  const flattened = String(value).replace(/\s+/gu, " ").trim();
  const shortened = flattened.length > 72 ? `${flattened.slice(0, 69)}…` : flattened;
  return JSON.stringify(shortened);
}

function printFieldChanges(changes, current = {}) {
  for (const [field, value] of Object.entries(changes)) {
    console.log(`      ${field}: ${shortValue(current[field])} -> ${shortValue(value)}`);
  }
}

function versionCreateAttributes(app) {
  const optional = ["copyright", "releaseType", "earliestReleaseDate", "usesIdfa"];
  return {
    platform: app.platform,
    versionString: app.versionString,
    ...Object.fromEntries(optional.filter((field) => field in app).map((field) => [field, app[field]])),
  };
}

async function findApp(api, bundleId) {
  const apps = await api.list(query("/v1/apps", { "filter[bundleId]": bundleId, limit: 50 }));
  if (apps.length !== 1) {
    throw new Error(
      apps.length === 0
        ? `No App Store Connect app found for bundle ID ${bundleId}.`
        : `Multiple App Store Connect apps found for bundle ID ${bundleId}.`
    );
  }
  return apps[0];
}

async function findVersion(api, appId, { platform, versionString }) {
  const versions = await api.list(
    query(`/v1/apps/${appId}/appStoreVersions`, {
      "filter[platform]": platform,
      "filter[versionString]": versionString,
      limit: 200,
    })
  );
  if (versions.length > 1) {
    throw new Error(`Multiple ${platform} App Store versions named ${versionString} were returned.`);
  }
  return versions[0] ?? null;
}

async function listAppInfos(api, appId) {
  return api.list(query(`/v1/apps/${appId}/appInfos`, { limit: 50 }));
}

async function listAppInfoLocalizations(api, appInfoId) {
  return api.list(query(`/v1/appInfos/${appInfoId}/appInfoLocalizations`, { limit: 200 }));
}

async function listVersionLocalizations(api, versionId) {
  return api.list(query(`/v1/appStoreVersions/${versionId}/appStoreVersionLocalizations`, { limit: 200 }));
}

async function listScreenshotSets(api, localizationId) {
  return api.list(
    query(`/v1/appStoreVersionLocalizations/${localizationId}/appScreenshotSets`, { limit: 200 })
  );
}

async function listScreenshots(api, setId) {
  return api.list(query(`/v1/appScreenshotSets/${setId}/appScreenshots`, { limit: 200 }));
}

async function readRemoteSnapshot(api, config, { includeScreenshots }) {
  const app = await findApp(api, config.app.bundleId);
  const version = await findVersion(api, app.id, config.app);
  const appInfos = await listAppInfos(api, app.id);
  const appInfo = chooseAppInfo(appInfos);
  const appInfoLocalizations = appInfo ? await listAppInfoLocalizations(api, appInfo.id) : [];
  const versionLocalizations = version ? await listVersionLocalizations(api, version.id) : [];
  const screenshotSets = new Map();

  if (includeScreenshots && version) {
    for (const localization of versionLocalizations) {
      if (!config.localizations[localization.attributes.locale]?.screenshots) continue;
      const sets = await listScreenshotSets(api, localization.id);
      const seen = new Set();
      for (const set of sets) {
        const displayType = set.attributes.screenshotDisplayType;
        if (seen.has(displayType)) throw new Error(`Duplicate screenshot set ${displayType} for ${localization.attributes.locale}.`);
        seen.add(displayType);
        const screenshots = await listScreenshots(api, set.id);
        screenshotSets.set(`${localization.attributes.locale}\u0000${displayType}`, { set, screenshots });
      }
    }
  }

  return {
    app,
    version,
    appInfo,
    appInfoLocalizations: indexByLocale(appInfoLocalizations),
    versionLocalizations: indexByLocale(versionLocalizations),
    screenshotSets,
  };
}

export function buildMetadataPlan(config, snapshot) {
  const changes = [];
  const unchanged = [];
  const blockers = [];
  const creatingVersion = !snapshot.version && config.app.createVersionIfMissing;

  if (!snapshot.version) {
    if (config.app.createVersionIfMissing) {
      changes.push({ type: "createVersion", attributes: versionCreateAttributes(config.app) });
    } else {
      blockers.push(`Version ${config.app.platform} ${config.app.versionString} does not exist and createVersionIfMissing is false.`);
    }
  }

  for (const [locale, localization] of Object.entries(config.localizations)) {
    const desiredAppInfo = pickFields(localization, APP_INFO_FIELDS);
    const appInfoLocalization = snapshot.appInfoLocalizations.get(locale);
    if (!appInfoLocalization) {
      const missing = missingCreateFields(localization, "appInfo");
      if (missing.length > 0) blockers.push(`${locale} needs ${missing.join(", ")} to create its App Info localization.`);
      else if (!creatingVersion && !isEditable(snapshot.appInfo)) {
        blockers.push(`${locale} App Info localization is missing, but App Info state ${resourceState(snapshot.appInfo) ?? "UNKNOWN"} is not editable.`);
      } else {
        changes.push({ type: "createAppInfoLocalization", locale, desired: desiredAppInfo });
      }
    } else {
      const fieldChanges = diffFields(appInfoLocalization.attributes, desiredAppInfo);
      if (Object.keys(fieldChanges).length === 0) unchanged.push(`${locale} app info`);
      else if (!creatingVersion && !isEditable(snapshot.appInfo)) {
        blockers.push(`${locale} App Info has changes, but state ${resourceState(snapshot.appInfo) ?? "UNKNOWN"} is not editable.`);
      } else {
        changes.push({
          type: "updateAppInfoLocalization",
          locale,
          id: appInfoLocalization.id,
          current: appInfoLocalization.attributes,
          desired: fieldChanges,
        });
      }
    }

    const desiredVersion = pickFields(localization, VERSION_LOCALIZATION_FIELDS);
    const versionLocalization = snapshot.versionLocalizations.get(locale);
    if (!versionLocalization) {
      const missing = missingCreateFields(localization, "version");
      if (missing.length > 0) blockers.push(`${locale} needs ${missing.join(", ")} to create its version localization.`);
      else if (snapshot.version && !isEditable(snapshot.version)) {
        blockers.push(`${locale} version localization is missing, but version state ${resourceState(snapshot.version) ?? "UNKNOWN"} is not editable.`);
      } else {
        changes.push({ type: "createVersionLocalization", locale, desired: desiredVersion });
      }
    } else {
      const fieldChanges = diffFields(versionLocalization.attributes, desiredVersion);
      const nonPromotionalChanges = Object.keys(fieldChanges).filter((field) => field !== "promotionalText");
      if (Object.keys(fieldChanges).length === 0) unchanged.push(`${locale} version metadata`);
      else if (snapshot.version && !isEditable(snapshot.version) && nonPromotionalChanges.length > 0) {
        blockers.push(
          `${locale} changes ${nonPromotionalChanges.join(", ")}, but version state ${resourceState(snapshot.version) ?? "UNKNOWN"} only permits promotionalText updates.`
        );
      } else {
        changes.push({
          type: "updateVersionLocalization",
          locale,
          id: versionLocalization.id,
          current: versionLocalization.attributes,
          desired: fieldChanges,
        });
      }
    }
  }

  if (snapshot.version) {
    const configuredLocales = new Set(Object.keys(config.localizations));
    const effectiveAppInfoLocales = new Set([...snapshot.appInfoLocalizations.keys(), ...configuredLocales]);
    const effectiveVersionLocales = new Set([...snapshot.versionLocalizations.keys(), ...configuredLocales]);
    const missingFromVersion = [...effectiveAppInfoLocales].filter((locale) => !effectiveVersionLocales.has(locale));
    const missingFromAppInfo = [...effectiveVersionLocales].filter((locale) => !effectiveAppInfoLocales.has(locale));
    if (missingFromVersion.length > 0) {
      blockers.push(
        `Version metadata is missing App Info locales: ${missingFromVersion.join(", ")}. Add them to this config so App Store submission will accept the localization set.`
      );
    }
    if (missingFromAppInfo.length > 0) {
      blockers.push(
        `App Info is missing version locales: ${missingFromAppInfo.join(", ")}. Add them to this config so App Store submission will accept the localization set.`
      );
    }
  }
  return { changes, unchanged, blockers };
}

export function addScreenshotPlan(config, snapshot, assetsBySet, plan, options) {
  if (!options.includeScreenshots) return;
  const versionIsEditable = !snapshot.version || isEditable(snapshot.version);
  for (const [locale, localization] of Object.entries(config.localizations)) {
    for (const displayType of Object.keys(localization.screenshots ?? {})) {
      const key = `${locale}\u0000${displayType}`;
      const assets = assetsBySet.get(key) ?? [];
      const remote = snapshot.screenshotSets.get(key);
      if (!versionIsEditable) {
        plan.blockers.push(`${locale} ${displayType} screenshots cannot change in version state ${resourceState(snapshot.version)}.`);
      } else if (!remote || remote.screenshots.length === 0) {
        plan.changes.push({ type: "uploadScreenshotSet", locale, displayType, count: assets.length });
      } else if (screenshotSetMatches(remote.screenshots, assets)) {
        plan.unchanged.push(`${locale} ${displayType} screenshots`);
      } else if (!options.replaceScreenshots) {
        plan.blockers.push(
          `${locale} ${displayType} has different remote screenshots; inspect the plan and rerun with --replace-screenshots to replace the whole set.`
        );
      } else {
        plan.changes.push({
          type: "replaceScreenshotSet",
          locale,
          displayType,
          count: assets.length,
          remoteCount: remote.screenshots.length,
          destructive: true,
        });
      }
    }
  }
}

function printPlan(config, snapshot, plan, options) {
  console.log(`\nApp: ${config.app.bundleId}`);
  console.log(`Target: ${config.app.platform} ${config.app.versionString}`);
  console.log(`Remote version: ${snapshot.version ? `${snapshot.version.id} (${resourceState(snapshot.version)})` : "not created"}`);
  console.log(`Screenshots: ${options.includeScreenshots ? "included" : "skipped (pass --include-screenshots)"}`);
  console.log("\nPlanned changes:");
  if (plan.changes.length === 0) console.log("  none");
  for (const action of plan.changes) {
    switch (action.type) {
      case "createVersion":
        console.log(`  + create ${action.attributes.platform} version ${action.attributes.versionString}`);
        break;
      case "createAppInfoLocalization":
        console.log(`  + ${action.locale}: create app info localization`);
        printFieldChanges(action.desired);
        break;
      case "updateAppInfoLocalization":
        console.log(`  ~ ${action.locale}: update app info localization`);
        printFieldChanges(action.desired, action.current);
        break;
      case "createVersionLocalization":
        console.log(`  + ${action.locale}: create version localization`);
        printFieldChanges(action.desired);
        break;
      case "updateVersionLocalization":
        console.log(`  ~ ${action.locale}: update version localization`);
        printFieldChanges(action.desired, action.current);
        break;
      case "uploadScreenshotSet":
        console.log(`  + ${action.locale}: upload ${action.count} screenshots to ${action.displayType}`);
        break;
      case "replaceScreenshotSet":
        console.log(
          `  ! ${action.locale}: replace ${action.remoteCount} screenshots with ${action.count} in ${action.displayType}`
        );
        break;
    }
  }
  console.log(`\nUnchanged groups: ${plan.unchanged.length}`);
  if (plan.blockers.length > 0) {
    console.log("\nBlocked:");
    for (const blocker of plan.blockers) console.log(`  - ${blocker}`);
  }
}

async function createVersion(api, appId, appConfig) {
  const response = await api.request("/v1/appStoreVersions", {
    method: "POST",
    body: {
      data: {
        type: "appStoreVersions",
        attributes: versionCreateAttributes(appConfig),
        relationships: { app: { data: { type: "apps", id: appId } } },
      },
    },
  });
  console.log(`Created ${appConfig.platform} version ${appConfig.versionString}.`);
  return response.data;
}

async function waitForEditableAppInfo(api, appId) {
  for (let attempt = 0; attempt < 6; attempt += 1) {
    const appInfo = chooseAppInfo(await listAppInfos(api, appId));
    if (appInfo && isEditable(appInfo)) return appInfo;
    if (attempt < 5) await delay(1000);
  }
  throw new Error("The new version exists, but App Store Connect has not exposed an editable App Info resource yet. Retry in a minute.");
}

async function appInfoForApply(api, appId, config) {
  let appInfo = chooseAppInfo(await listAppInfos(api, appId));
  if (!appInfo) throw new Error("App Store Connect returned no App Info resource.");
  let localizations = indexByLocale(await listAppInfoLocalizations(api, appInfo.id));
  const needsMutation = Object.entries(config.localizations).some(([locale, localization]) => {
    const current = localizations.get(locale);
    return !current || Object.keys(diffFields(current.attributes, pickFields(localization, APP_INFO_FIELDS))).length > 0;
  });
  if (needsMutation && !isEditable(appInfo)) {
    appInfo = await waitForEditableAppInfo(api, appId);
    localizations = indexByLocale(await listAppInfoLocalizations(api, appInfo.id));
  }
  return { appInfo, localizations };
}

function isDuplicateLocaleError(error) {
  return (
    error instanceof Error &&
    error.message.includes("(409)") &&
    error.message.includes("ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE")
  );
}

export async function createLocalizationOrUseExisting({
  api,
  listResources,
  collectionPath,
  resourceType,
  relationshipName,
  parentType,
  parentId,
  locale,
  desired,
}) {
  const findCurrent = async () => indexByLocale(await listResources()).get(locale) ?? null;
  const current = await findCurrent();
  if (current) return { resource: current, created: false };

  try {
    const response = await api.request(collectionPath, {
      method: "POST",
      body: {
        data: {
          type: resourceType,
          attributes: { locale, ...desired },
          relationships: { [relationshipName]: { data: { type: parentType, id: parentId } } },
        },
      },
    });
    return { resource: response.data, created: true };
  } catch (error) {
    if (!isDuplicateLocaleError(error)) throw error;
    // Adding one side of an App Store localization can cause Apple to create
    // its matching App Info/version localization. Recover that server-created
    // resource instead of failing an otherwise safe, repeatable sync.
    for (let attempt = 0; attempt < 6; attempt += 1) {
      const recovered = await findCurrent();
      if (recovered) return { resource: recovered, created: false };
      if (attempt < 5) await delay(500 * 2 ** attempt);
    }
    throw error;
  }
}

async function applyMetadata(api, config, app, version) {
  const { appInfo, localizations: appInfoLocalizations } = await appInfoForApply(api, app.id, config);
  const versionLocalizations = indexByLocale(await listVersionLocalizations(api, version.id));

  for (const [locale, localization] of Object.entries(config.localizations)) {
    const desiredAppInfo = pickFields(localization, APP_INFO_FIELDS);
    let appInfoLocalization = appInfoLocalizations.get(locale);
    if (!appInfoLocalization) {
      const result = await createLocalizationOrUseExisting({
        api,
        listResources: () => listAppInfoLocalizations(api, appInfo.id),
        collectionPath: "/v1/appInfoLocalizations",
        resourceType: "appInfoLocalizations",
        relationshipName: "appInfo",
        parentType: "appInfos",
        parentId: appInfo.id,
        locale,
        desired: desiredAppInfo,
      });
      appInfoLocalization = result.resource;
      appInfoLocalizations.set(locale, appInfoLocalization);
      console.log(`${result.created ? "Created" : "Found Apple-created"} ${locale} App Info localization.`);
    }
    const appInfoChanges = diffFields(appInfoLocalization.attributes, desiredAppInfo);
    if (Object.keys(appInfoChanges).length > 0) {
      await api.request(`/v1/appInfoLocalizations/${appInfoLocalization.id}`, {
        method: "PATCH",
        body: { data: { type: "appInfoLocalizations", id: appInfoLocalization.id, attributes: appInfoChanges } },
      });
      console.log(`Updated ${locale} App Info: ${Object.keys(appInfoChanges).join(", ")}.`);
    }

    const desiredVersion = pickFields(localization, VERSION_LOCALIZATION_FIELDS);
    let versionLocalization = versionLocalizations.get(locale);
    if (!versionLocalization) {
      const result = await createLocalizationOrUseExisting({
        api,
        listResources: () => listVersionLocalizations(api, version.id),
        collectionPath: "/v1/appStoreVersionLocalizations",
        resourceType: "appStoreVersionLocalizations",
        relationshipName: "appStoreVersion",
        parentType: "appStoreVersions",
        parentId: version.id,
        locale,
        desired: desiredVersion,
      });
      versionLocalization = result.resource;
      versionLocalizations.set(locale, versionLocalization);
      console.log(`${result.created ? "Created" : "Found Apple-created"} ${locale} version localization.`);
    }
    const versionChanges = diffFields(versionLocalization.attributes, desiredVersion);
    if (Object.keys(versionChanges).length > 0) {
      await api.request(`/v1/appStoreVersionLocalizations/${versionLocalization.id}`, {
        method: "PATCH",
        body: {
          data: { type: "appStoreVersionLocalizations", id: versionLocalization.id, attributes: versionChanges },
        },
      });
      console.log(`Updated ${locale} version metadata: ${Object.keys(versionChanges).join(", ")}.`);
    }
  }
  return versionLocalizations;
}

async function createScreenshotSet(api, localizationId, displayType) {
  const response = await api.request("/v1/appScreenshotSets", {
    method: "POST",
    body: {
      data: {
        type: "appScreenshotSets",
        attributes: { screenshotDisplayType: displayType },
        relationships: {
          appStoreVersionLocalization: {
            data: { type: "appStoreVersionLocalizations", id: localizationId },
          },
        },
      },
    },
  });
  return response.data;
}

function deliveryState(screenshot) {
  const delivery = screenshot?.attributes?.assetDeliveryState;
  return delivery?.state ?? delivery;
}

async function waitForScreenshot(api, id, fileName) {
  for (let attempt = 0; attempt < 90; attempt += 1) {
    const response = await api.request(`/v1/appScreenshots/${id}`);
    const state = deliveryState(response.data);
    if (state === "COMPLETE") return response.data;
    if (state === "FAILED") {
      const errors = response.data.attributes.assetDeliveryState?.errors;
      throw new Error(`Apple failed to process ${fileName}: ${JSON.stringify(errors ?? "unknown error")}`);
    }
    await delay(2000);
  }
  throw new Error(`Timed out waiting for Apple to process ${fileName}. The upload may still finish in App Store Connect.`);
}

async function uploadScreenshot(api, setId, asset) {
  const content = readFileSync(asset.path);
  const reservation = await api.request("/v1/appScreenshots", {
    method: "POST",
    body: {
      data: {
        type: "appScreenshots",
        attributes: { fileName: asset.fileName, fileSize: asset.fileSize },
        relationships: { appScreenshotSet: { data: { type: "appScreenshotSets", id: setId } } },
      },
    },
  });
  const screenshot = reservation.data;
  const operations = screenshot.attributes.uploadOperations ?? [];
  if (operations.length === 0) throw new Error(`Apple returned no upload operations for ${asset.fileName}.`);
  await api.uploadParts(operations, content);
  await api.request(`/v1/appScreenshots/${screenshot.id}`, {
    method: "PATCH",
    body: {
      data: {
        type: "appScreenshots",
        id: screenshot.id,
        attributes: { uploaded: true, sourceFileChecksum: asset.checksum },
      },
    },
  });
  await waitForScreenshot(api, screenshot.id, asset.fileName);
  console.log(`  uploaded ${asset.fileName}`);
  return screenshot.id;
}

async function orderScreenshots(api, setId, screenshotIds) {
  await api.request(`/v1/appScreenshotSets/${setId}/relationships/appScreenshots`, {
    method: "PATCH",
    body: { data: screenshotIds.map((id) => ({ type: "appScreenshots", id })) },
  });
}

async function applyScreenshots(api, config, assetsBySet, versionLocalizations, { replaceScreenshots }) {
  for (const [locale, localization] of Object.entries(config.localizations)) {
    const versionLocalization = versionLocalizations.get(locale);
    if (!versionLocalization) throw new Error(`Missing ${locale} version localization after metadata sync.`);
    const currentSets = await listScreenshotSets(api, versionLocalization.id);
    const byDisplayType = new Map(currentSets.map((set) => [set.attributes.screenshotDisplayType, set]));

    for (const displayType of Object.keys(localization.screenshots ?? {})) {
      const key = `${locale}\u0000${displayType}`;
      const assets = assetsBySet.get(key);
      let set = byDisplayType.get(displayType);
      let screenshots = set ? await listScreenshots(api, set.id) : [];
      if (set && screenshotSetMatches(screenshots, assets)) {
        console.log(`${locale} ${displayType}: screenshots already match.`);
        continue;
      }
      if (set && screenshots.length > 0) {
        if (!replaceScreenshots) {
          throw new Error(`${locale} ${displayType} differs remotely; rerun with --replace-screenshots.`);
        }
        await api.request(`/v1/appScreenshotSets/${set.id}`, { method: "DELETE" });
        console.log(`${locale} ${displayType}: removed the previous ${screenshots.length}-image set.`);
        set = null;
        screenshots = [];
      }
      if (!set) set = await createScreenshotSet(api, versionLocalization.id, displayType);
      console.log(`${locale} ${displayType}: uploading ${assets.length} screenshots...`);
      const ids = [];
      for (const asset of assets) ids.push(await uploadScreenshot(api, set.id, asset));
      await orderScreenshots(api, set.id, ids);
      console.log(`${locale} ${displayType}: upload complete and order synchronized.`);
    }
  }
}

function checkPackageVersion(config) {
  const packageJson = JSON.parse(readFileSync("package.json", "utf8"));
  if (packageJson.version !== config.app.versionString) {
    console.warn(
      `Warning: config targets ${config.app.versionString}, but package.json is ${packageJson.version}. Run npm run check:version before packaging.`
    );
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log(HELP);
    return;
  }
  const loaded = loadConfig(options.configPath);
  const placeholders = findPlaceholders(loaded.config);
  if (placeholders.length > 0) {
    throw new Error(`Replace scaffold placeholders before continuing:\n${placeholders.map((path) => `  - ${path}`).join("\n")}`);
  }
  checkPackageVersion(loaded.config);
  const screenshotCount = [...loaded.screenshots.values()].reduce((total, assets) => total + assets.length, 0);
  console.log(
    `Validated ${Object.keys(loaded.config.localizations).length} locales and ${screenshotCount} configured screenshots from ${loaded.absoluteConfigPath}.`
  );
  if (options.mode === "check") return;

  const api = createApiClient({ credentials: credentialsFromEnv() });
  let snapshot = await readRemoteSnapshot(api, loaded.config, options);
  const plan = buildMetadataPlan(loaded.config, snapshot);
  addScreenshotPlan(loaded.config, snapshot, loaded.screenshots, plan, options);
  printPlan(loaded.config, snapshot, plan, options);
  if (options.mode === "plan") return;
  if (plan.blockers.length > 0) throw new Error("The plan is blocked; no changes were written.");
  if (plan.changes.length === 0) {
    console.log("\nEverything already matches. Nothing to write.");
    return;
  }

  const replacements = plan.changes.filter((action) => action.destructive).length;
  await confirmExact({
    expected: `${loaded.config.app.platform} ${loaded.config.app.versionString}`,
    message: `Apply ${plan.changes.length} App Store Connect change groups${
      replacements ? `, including ${replacements} destructive screenshot-set replacement(s)` : ""
    }? This does not submit the version for review.`,
    yes: options.yes,
  });

  let version = snapshot.version;
  if (!version) {
    version = await createVersion(api, snapshot.app.id, loaded.config.app);
    await waitForEditableAppInfo(api, snapshot.app.id);
    snapshot = await readRemoteSnapshot(api, loaded.config, options);
    const postCreationPlan = buildMetadataPlan(loaded.config, snapshot);
    addScreenshotPlan(loaded.config, snapshot, loaded.screenshots, postCreationPlan, options);
    if (postCreationPlan.blockers.length > 0) {
      printPlan(loaded.config, snapshot, postCreationPlan, options);
      throw new Error("The version was created, but its inherited metadata produced blockers. No localization fields were written; update the config and rerun.");
    }
    const newlyDiscoveredReplacements = postCreationPlan.changes.filter((action) => action.destructive).length;
    if (newlyDiscoveredReplacements > 0 && replacements === 0) {
      printPlan(loaded.config, snapshot, postCreationPlan, options);
      await confirmExact({
        expected: `REPLACE ${loaded.config.app.platform} ${loaded.config.app.versionString}`,
        message: `The new version inherited ${newlyDiscoveredReplacements} non-matching screenshot set(s). Replace them?`,
        yes: options.yes,
      });
    }
  }
  const versionLocalizations = await applyMetadata(api, loaded.config, snapshot.app, version);
  if (options.includeScreenshots) {
    await applyScreenshots(api, loaded.config, loaded.screenshots, versionLocalizations, options);
  }
  snapshot = await readRemoteSnapshot(api, loaded.config, options);
  const verification = buildMetadataPlan(loaded.config, snapshot);
  addScreenshotPlan(loaded.config, snapshot, loaded.screenshots, verification, options);
  if (verification.changes.length > 0 || verification.blockers.length > 0) {
    throw new Error("Sync finished, but verification still found differences. Run asc:plan to inspect them.");
  }
  console.log("\nApp Store Connect metadata is synchronized. The version was not submitted for review.");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    console.error(`\n${error instanceof Error ? error.message : error}`);
    process.exitCode = 1;
  });
}
