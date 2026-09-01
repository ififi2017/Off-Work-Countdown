#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";
import { createApiClient, credentialsFromEnv } from "./app-store-connect/api.mjs";
import { loadIapConfig, localizationChanges, parseIapArgs } from "./app-store-connect/iap-config.mjs";
import { confirmExact } from "./release-helpers.mjs";

const HELP = `App Store Connect IAP localization sync

Usage:
  npm run asc:iap:check
  npm run asc:iap:plan
  npm run asc:iap:sync -- --yes

Modes:
  --check                 Validate JSON, field limits, and the review screenshot. No credentials needed.
  --plan                  Read App Store Connect and print changes. This is the default and never writes.
  --apply                 Apply the printed localization, review note, and screenshot changes.

  --skip-screenshot       Do not read or upload the review screenshot.
  --replace-screenshot    Replace an existing review screenshot when it differs.

Credentials (team API key):
  ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH
`;

function query(path, parameters = {}) {
  const url = new URL(path, "https://api.appstoreconnect.apple.com");
  for (const [key, value] of Object.entries(parameters)) {
    if (value !== undefined && value !== null) url.searchParams.set(key, String(value));
  }
  return `${url.pathname}${url.search}`;
}

function indexByLocale(resources) {
  return new Map((resources ?? []).filter(Boolean).map((resource) => [resource.attributes.locale, resource]));
}

function isDuplicateLocaleError(error) {
  const message = error instanceof Error ? error.message : String(error);
  return /DUPLICATE|ENTITY_ERROR\.ATTRIBUTE\.INVALID/u.test(message) && /locale/iu.test(message);
}

function screenshotState(resource) {
  return resource?.attributes?.assetDeliveryState?.state ?? resource?.attributes?.assetDeliveryState ?? null;
}

function summarizeShot(resource) {
  if (!resource) return "missing";
  return `${resource.attributes.fileName ?? "uploaded"} (${screenshotState(resource) ?? "unknown"})`;
}

async function createLocalizationOrUseExisting({
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
  const existing = (await listResources()).find((item) => item.attributes.locale === locale);
  if (existing) return { resource: existing, created: false };
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
    for (let attempt = 0; attempt < 6; attempt += 1) {
      const recovered = (await listResources()).find((item) => item.attributes.locale === locale);
      if (recovered) return { resource: recovered, created: false };
      if (attempt < 5) await delay(500 * 2 ** attempt);
    }
    throw error;
  }
}

async function findApp(api, bundleId) {
  const apps = await api.list(query("/v1/apps", { "filter[bundleId]": bundleId, limit: 5 }));
  if (apps.length !== 1) throw new Error(`Expected one app for ${bundleId}, found ${apps.length}.`);
  return apps[0];
}

async function listGroupLocalizations(api, groupId) {
  return api.list(`/v1/subscriptionGroups/${groupId}/subscriptionGroupLocalizations`);
}

async function listSubscriptionLocalizations(api, subscriptionId) {
  return api.list(`/v1/subscriptions/${subscriptionId}/subscriptionLocalizations`);
}

async function listIapLocalizations(api, iapId) {
  return api.list(`/v2/inAppPurchases/${iapId}/inAppPurchaseLocalizations`);
}

async function readScreenshot(api, path) {
  const response = await api.request(path);
  return response?.data ?? null;
}

async function loadRemote(api, config) {
  const app = await findApp(api, config.bundleId);
  const groups = await api.list(query(`/v1/apps/${app.id}/subscriptionGroups`, { limit: 50 }));
  const group = groups.find((item) => item.attributes.referenceName === config.subscriptionGroup);
  if (!group) throw new Error(`Subscription group ${config.subscriptionGroup} was not found.`);
  const subscriptions = await api.list(query(`/v1/subscriptionGroups/${group.id}/subscriptions`, { limit: 50 }));
  const iaps = await api.list(query(`/v1/apps/${app.id}/inAppPurchasesV2`, { limit: 50 }));

  const products = {};
  for (const [productId, product] of Object.entries(config.products)) {
    if (product.kind === "subscription") {
      const resource = subscriptions.find((item) => item.attributes.productId === productId);
      if (!resource) throw new Error(`Subscription ${productId} was not found.`);
      products[productId] = {
        kind: "subscription",
        resource,
        localizations: indexByLocale(await listSubscriptionLocalizations(api, resource.id)),
        screenshot: await readScreenshot(api, `/v1/subscriptions/${resource.id}/appStoreReviewScreenshot`),
      };
    } else {
      const resource = iaps.find((item) => item.attributes.productId === productId);
      if (!resource) throw new Error(`In-app purchase ${productId} was not found.`);
      products[productId] = {
        kind: "nonConsumable",
        resource,
        localizations: indexByLocale(await listIapLocalizations(api, resource.id)),
        screenshot: await readScreenshot(api, `/v2/inAppPurchases/${resource.id}/appStoreReviewScreenshot`),
      };
    }
  }

  return {
    app,
    group,
    groupLocalizations: indexByLocale(await listGroupLocalizations(api, group.id)),
    products,
  };
}

function buildPlan(config, remote, screenshot, { skipScreenshot }) {
  const changes = [];
  const blockers = [];

  for (const [locale, desired] of Object.entries(config.groupLocalizations)) {
    const current = remote.groupLocalizations.get(locale);
    if (!current) {
      changes.push({ type: "create-group-loc", locale, desired });
      continue;
    }
    const next = localizationChanges(current.attributes, desired);
    if (Object.keys(next).length > 0) {
      changes.push({ type: "update-group-loc", locale, id: current.id, desired: next, current: current.attributes });
    }
  }

  for (const [productId, product] of Object.entries(config.products)) {
    const remoteProduct = remote.products[productId];
    const reviewNote = remoteProduct.resource.attributes.reviewNote ?? "";
    if (reviewNote !== config.reviewNote) {
      changes.push({
        type: "update-review-note",
        productId,
        kind: product.kind,
        id: remoteProduct.resource.id,
        current: reviewNote || null,
      });
    }

    for (const [locale, desired] of Object.entries(product.localizations)) {
      const current = remoteProduct.localizations.get(locale);
      if (!current) {
        changes.push({ type: "create-product-loc", productId, kind: product.kind, locale, desired });
        continue;
      }
      const next = localizationChanges(current.attributes, desired);
      if (Object.keys(next).length > 0) {
        changes.push({
          type: "update-product-loc",
          productId,
          kind: product.kind,
          locale,
          id: current.id,
          desired: next,
          current: current.attributes,
        });
      }
    }

    if (!skipScreenshot) {
      const currentShot = remoteProduct.screenshot;
      if (!currentShot) {
        changes.push({ type: "upload-screenshot", productId, kind: product.kind, id: remoteProduct.resource.id });
      } else if (currentShot.attributes.sourceFileChecksum !== screenshot.checksum) {
        changes.push({
          type: "replace-screenshot",
          productId,
          kind: product.kind,
          id: remoteProduct.resource.id,
          screenshotId: currentShot.id,
          current: summarizeShot(currentShot),
        });
      }
    }
  }

  return { changes, blockers };
}

function printPlan(plan) {
  if (plan.blockers.length > 0) {
    console.log("Blocked:");
    for (const blocker of plan.blockers) console.log(`  - ${blocker}`);
  }
  if (plan.changes.length === 0) {
    console.log("No IAP metadata changes.");
    return;
  }
  console.log(`${plan.changes.length} change(s):`);
  for (const change of plan.changes) {
    if (change.type === "create-group-loc") {
      console.log(`  + group ${change.locale}: ${change.desired.name}`);
    } else if (change.type === "update-group-loc") {
      console.log(`  ~ group ${change.locale}: ${change.current.name} -> ${change.desired.name ?? change.current.name}`);
    } else if (change.type === "create-product-loc") {
      console.log(`  + ${change.productId} ${change.locale}: ${change.desired.name}`);
    } else if (change.type === "update-product-loc") {
      console.log(`  ~ ${change.productId} ${change.locale}`);
    } else if (change.type === "update-review-note") {
      console.log(`  ~ ${change.productId} review note`);
    } else if (change.type === "upload-screenshot") {
      console.log(`  + ${change.productId} review screenshot`);
    } else if (change.type === "replace-screenshot") {
      console.log(`  ~ ${change.productId} review screenshot (${change.current})`);
    }
  }
}

async function waitForScreenshot(api, type, id, fileName) {
  const path =
    type === "subscriptionAppStoreReviewScreenshots"
      ? `/v1/subscriptionAppStoreReviewScreenshots/${id}`
      : `/v1/inAppPurchaseAppStoreReviewScreenshots/${id}`;
  for (let attempt = 0; attempt < 90; attempt += 1) {
    const response = await api.request(path);
    const state = screenshotState(response.data);
    if (state === "COMPLETE") return response.data;
    if (state === "FAILED") {
      throw new Error(`Apple failed to process ${fileName}: ${JSON.stringify(response.data.attributes.assetDeliveryState)}`);
    }
    await delay(2000);
  }
  throw new Error(`Timed out waiting for Apple to process ${fileName}.`);
}

async function uploadReviewScreenshot(api, { kind, parentId, screenshot, existingId, replaceScreenshot }) {
  const collection =
    kind === "subscription" ? "/v1/subscriptionAppStoreReviewScreenshots" : "/v1/inAppPurchaseAppStoreReviewScreenshots";
  const type =
    kind === "subscription" ? "subscriptionAppStoreReviewScreenshots" : "inAppPurchaseAppStoreReviewScreenshots";
  const relationshipName = kind === "subscription" ? "subscription" : "inAppPurchaseV2";
  const parentType = kind === "subscription" ? "subscriptions" : "inAppPurchases";
  const itemPath = kind === "subscription"
    ? "/v1/subscriptionAppStoreReviewScreenshots"
    : "/v1/inAppPurchaseAppStoreReviewScreenshots";

  if (existingId) {
    if (!replaceScreenshot) {
      throw new Error("An existing review screenshot differs; rerun with --replace-screenshot.");
    }
    await api.request(`${itemPath}/${existingId}`, { method: "DELETE" });
  }

  const content = readFileSync(screenshot.path);
  const reservation = await api.request(collection, {
    method: "POST",
    body: {
      data: {
        type,
        attributes: { fileName: screenshot.fileName, fileSize: screenshot.fileSize },
        relationships: { [relationshipName]: { data: { type: parentType, id: parentId } } },
      },
    },
  });
  const resource = reservation.data;
  const operations = resource.attributes.uploadOperations ?? [];
  if (operations.length === 0) throw new Error(`Apple returned no upload operations for ${screenshot.fileName}.`);
  await api.uploadParts(operations, content);
  await api.request(`${itemPath}/${resource.id}`, {
    method: "PATCH",
    body: {
      data: {
        type,
        id: resource.id,
        attributes: { uploaded: true, sourceFileChecksum: screenshot.checksum },
      },
    },
  });
  await waitForScreenshot(api, type, resource.id, screenshot.fileName);
}

async function applyPlan(api, config, remote, screenshot, plan, { replaceScreenshot }) {
  for (const change of plan.changes) {
    if (change.type === "create-group-loc") {
      await createLocalizationOrUseExisting({
        api,
        listResources: () => listGroupLocalizations(api, remote.group.id),
        collectionPath: "/v1/subscriptionGroupLocalizations",
        resourceType: "subscriptionGroupLocalizations",
        relationshipName: "subscriptionGroup",
        parentType: "subscriptionGroups",
        parentId: remote.group.id,
        locale: change.locale,
        desired: change.desired,
      });
      console.log(`Created group localization ${change.locale}.`);
    } else if (change.type === "update-group-loc") {
      await api.request(`/v1/subscriptionGroupLocalizations/${change.id}`, {
        method: "PATCH",
        body: {
          data: { type: "subscriptionGroupLocalizations", id: change.id, attributes: change.desired },
        },
      });
      console.log(`Updated group localization ${change.locale}.`);
    } else if (change.type === "create-product-loc" || change.type === "update-product-loc") {
      const remoteProduct = remote.products[change.productId];
      if (change.kind === "subscription") {
        if (change.type === "create-product-loc") {
          await createLocalizationOrUseExisting({
            api,
            listResources: () => listSubscriptionLocalizations(api, remoteProduct.resource.id),
            collectionPath: "/v1/subscriptionLocalizations",
            resourceType: "subscriptionLocalizations",
            relationshipName: "subscription",
            parentType: "subscriptions",
            parentId: remoteProduct.resource.id,
            locale: change.locale,
            desired: change.desired,
          });
        } else {
          await api.request(`/v1/subscriptionLocalizations/${change.id}`, {
            method: "PATCH",
            body: {
              data: { type: "subscriptionLocalizations", id: change.id, attributes: change.desired },
            },
          });
        }
      } else if (change.type === "create-product-loc") {
        await createLocalizationOrUseExisting({
          api,
          listResources: () => listIapLocalizations(api, remoteProduct.resource.id),
          collectionPath: "/v1/inAppPurchaseLocalizations",
          resourceType: "inAppPurchaseLocalizations",
          relationshipName: "inAppPurchaseV2",
          parentType: "inAppPurchases",
          parentId: remoteProduct.resource.id,
          locale: change.locale,
          desired: change.desired,
        });
      } else {
        await api.request(`/v1/inAppPurchaseLocalizations/${change.id}`, {
          method: "PATCH",
          body: {
            data: { type: "inAppPurchaseLocalizations", id: change.id, attributes: change.desired },
          },
        });
      }
      console.log(`${change.type === "create-product-loc" ? "Created" : "Updated"} ${change.productId} ${change.locale}.`);
    } else if (change.type === "update-review-note") {
      if (change.kind === "subscription") {
        await api.request(`/v1/subscriptions/${change.id}`, {
          method: "PATCH",
          body: {
            data: { type: "subscriptions", id: change.id, attributes: { reviewNote: config.reviewNote } },
          },
        });
      } else {
        await api.request(`/v2/inAppPurchases/${change.id}`, {
          method: "PATCH",
          body: {
            data: { type: "inAppPurchases", id: change.id, attributes: { reviewNote: config.reviewNote } },
          },
        });
      }
      console.log(`Updated ${change.productId} review note.`);
    } else if (change.type === "upload-screenshot" || change.type === "replace-screenshot") {
      await uploadReviewScreenshot(api, {
        kind: change.kind,
        parentId: change.id,
        screenshot,
        existingId: change.screenshotId,
        replaceScreenshot,
      });
      console.log(`Uploaded ${change.productId} review screenshot.`);
    }
  }
}

async function main() {
  const options = parseIapArgs(process.argv.slice(2));
  if (options.help) {
    console.log(HELP);
    return;
  }

  const { config, screenshot } = loadIapConfig(options.configPath, {
    requireScreenshot: !options.skipScreenshot,
  });
  if (options.mode === "check") {
    console.log(`IAP config is valid. ${STORE_COUNT(config)} localizations ready.`);
    return;
  }

  const api = createApiClient({ credentials: credentialsFromEnv() });
  const remote = await loadRemote(api, config);
  const plan = buildPlan(config, remote, screenshot, { skipScreenshot: options.skipScreenshot });
  printPlan(plan);
  if (options.mode !== "apply") return;
  if (plan.blockers.length > 0) throw new Error("Resolve the blockers before applying.");
  if (plan.changes.length === 0) return;
  await confirmExact({
    expected: "IAP plus",
    message: `Apply ${plan.changes.length} IAP metadata change(s) to ${config.bundleId}?`,
    yes: options.yes,
  });
  await applyPlan(api, config, remote, screenshot, plan, { replaceScreenshot: options.replaceScreenshot });
  console.log("IAP metadata sync complete.");
}

function STORE_COUNT(config) {
  const productLocales = Object.values(config.products).reduce(
    (sum, product) => sum + Object.keys(product.localizations).length,
    0
  );
  return `${Object.keys(config.groupLocalizations).length} group + ${productLocales} product`;
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
