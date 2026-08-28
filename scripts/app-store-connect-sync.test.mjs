import { readFileSync } from "node:fs";
import { describe, expect, it, vi } from "vitest";
import {
  addScreenshotPlan,
  buildMetadataPlan,
  createLocalizationOrUseExisting,
} from "./app-store-connect-sync.mjs";

function config(fields = {}) {
  return {
    app: {
      bundleId: "com.example.app",
      platform: "IOS",
      versionString: "2.0.0",
      createVersionIfMissing: false,
    },
    localizations: {
      "en-US": {
        name: "Example",
        description: "Description",
        keywords: "timer",
        supportUrl: "https://example.com/support",
        ...fields,
      },
    },
  };
}

function resource(type, id, attributes) {
  return { type, id, attributes };
}

function snapshot({ versionState = "PREPARE_FOR_SUBMISSION", versionLocalization } = {}) {
  return {
    version: resource("appStoreVersions", "version", {
      appVersionState: versionState,
      platform: "IOS",
      versionString: "2.0.0",
    }),
    appInfo: resource("appInfos", "info", { state: versionState }),
    appInfoLocalizations: new Map([
      ["en-US", resource("appInfoLocalizations", "info-en", { locale: "en-US", name: "Example" })],
    ]),
    versionLocalizations: new Map([
      [
        "en-US",
        resource("appStoreVersionLocalizations", "version-en", {
          locale: "en-US",
          description: "Description",
          keywords: "timer",
          supportUrl: "https://example.com/support",
          ...versionLocalization,
        }),
      ],
    ]),
  };
}

describe("App Store Connect metadata plan", () => {
  it("contains no endpoint that creates or submits an App Review submission", () => {
    const source = readFileSync(new URL("./app-store-connect-sync.mjs", import.meta.url), "utf8");
    expect(source).not.toMatch(/reviewSubmissions|reviewSubmissionItems|appStoreVersionSubmissions/u);
  });

  it("is empty when configured fields already match", () => {
    const plan = buildMetadataPlan(config(), snapshot());
    expect(plan.changes).toEqual([]);
    expect(plan.blockers).toEqual([]);
  });

  it("allows promotional text updates on a live version", () => {
    const plan = buildMetadataPlan(
      config({ promotionalText: "A fresh message" }),
      snapshot({ versionState: "READY_FOR_DISTRIBUTION", versionLocalization: { promotionalText: "Old" } })
    );
    expect(plan.blockers).toEqual([]);
    expect(plan.changes).toEqual([
      expect.objectContaining({
        type: "updateVersionLocalization",
        desired: { promotionalText: "A fresh message" },
      }),
    ]);
  });

  it("blocks non-promotional edits on a live version", () => {
    const plan = buildMetadataPlan(
      config({ description: "Changed" }),
      snapshot({ versionState: "READY_FOR_DISTRIBUTION" })
    );
    expect(plan.blockers.join(" ")).toMatch(/only permits promotionalText/u);
  });

  it("requires matching app-info and version localization sets", () => {
    const current = snapshot();
    current.appInfoLocalizations.set(
      "zh-Hans",
      resource("appInfoLocalizations", "info-zh", { locale: "zh-Hans", name: "示例" })
    );
    const plan = buildMetadataPlan(config(), current);
    expect(plan.blockers.join(" ")).toMatch(/missing App Info locales: zh-Hans/u);
  });

  it("plans creation of a missing version when explicitly enabled", () => {
    const nextConfig = config();
    nextConfig.app.createVersionIfMissing = true;
    const current = snapshot();
    current.version = null;
    current.appInfo = resource("appInfos", "info", { state: "READY_FOR_DISTRIBUTION" });
    current.versionLocalizations = new Map();
    const plan = buildMetadataPlan(nextConfig, current);
    expect(plan.blockers).toEqual([]);
    expect(plan.changes.map((action) => action.type)).toContain("createVersion");
    expect(plan.changes.map((action) => action.type)).toContain("createVersionLocalization");
  });

  it("blocks a different screenshot set unless replacement is explicit", () => {
    const nextConfig = config({ screenshots: { APP_IPHONE_65: ["new.png"] } });
    const current = snapshot();
    current.screenshotSets = new Map([
      [
        "en-US\u0000APP_IPHONE_65",
        {
          screenshots: [
            {
              attributes: {
                fileName: "old.png",
                sourceFileChecksum: "old",
                assetDeliveryState: { state: "COMPLETE" },
              },
            },
          ],
        },
      ],
    ]);
    const assets = new Map([
      ["en-US\u0000APP_IPHONE_65", [{ fileName: "new.png", checksum: "new" }]],
    ]);
    const guarded = buildMetadataPlan(nextConfig, current);
    addScreenshotPlan(nextConfig, current, assets, guarded, {
      includeScreenshots: true,
      replaceScreenshots: false,
    });
    expect(guarded.blockers.join(" ")).toMatch(/--replace-screenshots/u);

    const permitted = buildMetadataPlan(nextConfig, current);
    addScreenshotPlan(nextConfig, current, assets, permitted, {
      includeScreenshots: true,
      replaceScreenshots: true,
    });
    expect(permitted.changes).toContainEqual(
      expect.objectContaining({ type: "replaceScreenshotSet", destructive: true })
    );
  });
});

describe("App Store Connect localization creation", () => {
  const parameters = (api, listResources) => ({
    api,
    listResources,
    collectionPath: "/v1/appStoreVersionLocalizations",
    resourceType: "appStoreVersionLocalizations",
    relationshipName: "appStoreVersion",
    parentType: "appStoreVersions",
    parentId: "version",
    locale: "ar-SA",
    desired: { description: "Description" },
  });

  it("uses a localization Apple already created instead of posting a duplicate", async () => {
    const existing = resource("appStoreVersionLocalizations", "version-ar", { locale: "ar-SA" });
    const api = { request: vi.fn() };

    const result = await createLocalizationOrUseExisting(parameters(api, async () => [existing]));

    expect(result).toEqual({ resource: existing, created: false });
    expect(api.request).not.toHaveBeenCalled();
  });

  it("recovers an Apple-created localization after a duplicate response", async () => {
    const existing = resource("appStoreVersionLocalizations", "version-ar", { locale: "ar-SA" });
    const api = {
      request: vi.fn().mockRejectedValue(
        new Error(
          "App Store Connect POST /v1/appStoreVersionLocalizations failed (409): ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE"
        )
      ),
    };
    const listResources = vi.fn().mockResolvedValueOnce([]).mockResolvedValueOnce([existing]);

    const result = await createLocalizationOrUseExisting(parameters(api, listResources));

    expect(result).toEqual({ resource: existing, created: false });
    expect(api.request).toHaveBeenCalledOnce();
  });
});
