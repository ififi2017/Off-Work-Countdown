import { describe, expect, it } from "vitest";
import {
  buildExport,
  chooseAppInfoForVersion,
  imageAssetUrl,
  parseExportArgs,
} from "./app-store-connect-export.mjs";

function resource(type, id, attributes) {
  return { type, id, attributes };
}

describe("App Store Connect export arguments", () => {
  it("builds a new-version export with safe defaults", () => {
    expect(
      parseExportArgs(["--source-version", "3.1.6", "--target-version=3.1.7", "--download-screenshots"])
    ).toMatchObject({
      bundleId: "com.rainif.offworkcountdown.macappstore",
      platform: "IOS",
      sourceVersion: "3.1.6",
      targetVersion: "3.1.7",
      outputPath: "app-store-connect/ios/3.1.7.json",
      screenshotsDir: "app-store-connect/screenshots/3.1.6",
      downloadScreenshots: true,
      force: false,
    });
  });

  it("requires a source version", () => {
    expect(() => parseExportArgs([])).toThrow(/source-version/u);
    expect(() => parseExportArgs(["--screenshots-dir", "shots", "--source-version", "1.0"])).toThrow(
      /download-screenshots/u
    );
  });
});

describe("App Store Connect export resources", () => {
  it("chooses the live App Info when exporting a live version", () => {
    const live = resource("appInfos", "live", { state: "READY_FOR_DISTRIBUTION" });
    const draft = resource("appInfos", "draft", { state: "PREPARE_FOR_SUBMISSION" });
    const version = resource("appStoreVersions", "version", { appVersionState: "READY_FOR_SALE" });
    expect(chooseAppInfoForVersion([draft, live], version)).toBe(live);
  });

  it("expands Apple's image template at the original dimensions", () => {
    expect(
      imageAssetUrl(
        {
          templateUrl: "https://example.com/{w}x{h}bb.{f}",
          width: 1284,
          height: 2778,
        },
        "screen.png"
      )
    ).toBe("https://example.com/1284x2778bb.png");
    expect(
      imageAssetUrl(
        {
          templateUrl: "https://example.com/%7Bw%7Dx%7Bh%7D.%7Bf%7D",
          width: 2064,
          height: 2752,
        },
        "screen.jpeg"
      )
    ).toBe("https://example.com/2064x2752.jpg");
  });

  it("exports managed fields into a config targeting the next version", async () => {
    const responses = [
      [resource("apps", "app", { bundleId: "com.example.app" })],
      [
        resource("appStoreVersions", "version", {
          platform: "IOS",
          versionString: "3.1.6",
          appVersionState: "READY_FOR_DISTRIBUTION",
          copyright: "© 2026 Example",
          usesIdfa: false,
        }),
      ],
      [resource("appInfos", "info", { state: "READY_FOR_DISTRIBUTION" })],
      [
        resource("appInfoLocalizations", "info-en", {
          locale: "en-US",
          name: "Example",
          subtitle: "A small helper",
          privacyPolicyUrl: "https://example.com/privacy",
          privacyChoicesUrl: null,
        }),
      ],
      [
        resource("appStoreVersionLocalizations", "version-en", {
          locale: "en-US",
          promotionalText: "Hello",
          description: "Description",
          keywords: "timer,helper",
          supportUrl: "https://example.com/support",
          marketingUrl: null,
          whatsNew: "Previous notes",
        }),
      ],
    ];
    const api = { list: async () => responses.shift() };
    const options = {
      bundleId: "com.example.app",
      platform: "IOS",
      sourceVersion: "3.1.6",
      targetVersion: "3.1.7",
      outputPath: "app-store-connect/ios/3.1.7.json",
    };
    const exported = await buildExport(api, options, {
      cwd: "/repo",
      now: new Date("2026-08-28T01:00:00.000Z"),
    });
    expect(exported.config).toMatchObject({
      exportedFrom: { platform: "IOS", versionString: "3.1.6" },
      app: {
        bundleId: "com.example.app",
        versionString: "3.1.7",
        createVersionIfMissing: true,
        releaseType: "MANUAL",
      },
      localizations: {
        "en-US": {
          name: "Example",
          description: "Description",
          whatsNew: "Previous notes",
        },
      },
    });
  });
});
