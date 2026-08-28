import { generateKeyPairSync, verify } from "node:crypto";
import { mkdirSync, mkdtempSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { createApiClient, createJwt, credentialsFromEnv } from "./api.mjs";
import {
  diffFields,
  findPlaceholders,
  loadConfig,
  parseArgs,
  screenshotSetMatches,
  validateConfig,
} from "./config.mjs";

function validConfig() {
  return {
    schemaVersion: 1,
    screenshotBaseDir: ".",
    app: {
      bundleId: "com.example.app",
      platform: "IOS",
      versionString: "1.2.3",
      createVersionIfMissing: true,
    },
    localizations: {
      "en-US": {
        name: "Example",
        description: "A useful app.",
        keywords: "useful,timer",
        supportUrl: "https://example.com/support",
      },
    },
  };
}

describe("App Store Connect config", () => {
  it("maps every in-app language and covers every App Store-supported locale", () => {
    const config = loadConfig("app-store-connect/ios/3.1.7.json", { requireFiles: false }).config;
    const appToStoreLocale = {
      en: "en-US",
      "zh-CN": "zh-Hans",
      "zh-HK": "zh-Hant",
      "zh-TW": "zh-Hant",
      ja: "ja",
      ko: "ko",
      de: "de-DE",
      es: "es-ES",
      fr: "fr-FR",
      it: "it",
      pt: "pt-BR",
      ru: "ru",
      ar: "ar-SA",
      "hi-IN": "hi",
      "mr-IN": null,
      id: "id",
      th: "th",
      tr: "tr",
      vi: "vi",
    };
    const appLocales = readdirSync("public/locales", { withFileTypes: true })
      .filter((entry) => entry.isDirectory())
      .map((entry) => entry.name)
      .sort();
    expect(Object.keys(appToStoreLocale).sort()).toEqual(appLocales);
    const expected = [...new Set(appLocales.map((locale) => appToStoreLocale[locale]).filter(Boolean))].sort();
    expect(Object.keys(config.localizations).sort()).toEqual(expected);
    expect(Object.entries(appToStoreLocale).filter(([, locale]) => locale === null).map(([locale]) => locale)).toEqual([
      "mr-IN",
    ]);
    expect(Object.values(config.localizations).every(({ name }) => name.startsWith("DoneAt"))).toBe(true);
  });

  it("parses safe-by-default CLI modes", () => {
    expect(parseArgs(["release.json", "--include-screenshots"])).toMatchObject({
      mode: "plan",
      configPath: "release.json",
      includeScreenshots: true,
      replaceScreenshots: false,
    });
    expect(() => parseArgs(["--apply", "--check"])).toThrow(/only one/u);
    expect(() => parseArgs(["--replace-screenshots"])).toThrow(/requires/u);
  });

  it("enforces Apple's character limits without rejecting multibyte keywords", () => {
    const longName = validConfig();
    longName.localizations["en-US"].name = "x".repeat(31);
    expect(() => validateConfig(longName)).toThrow(/maximum is 30/u);

    const multibyteKeywords = validConfig();
    multibyteKeywords.localizations["en-US"].keywords = "下".repeat(34);
    expect(() => validateConfig(multibyteKeywords)).not.toThrow();

    const longKeywords = validConfig();
    longKeywords.localizations["en-US"].keywords = "x".repeat(101);
    expect(() => validateConfig(longKeywords)).toThrow(/maximum is 100/u);
  });

  it("detects scaffold placeholders before an API call", () => {
    const config = validConfig();
    config.localizations["en-US"].description = "YOUR APP DESCRIPTION";
    expect(findPlaceholders(config)).toContain("localizations.en-US.description");
  });

  it("loads screenshot size and MD5 from disk", () => {
    const directory = mkdtempSync(join(tmpdir(), "owc-asc-config-"));
    const imagePath = join(directory, "shot.png");
    writeFileSync(imagePath, Buffer.from("not-a-real-png-but-enough-for-config-io"));
    const config = validConfig();
    config.localizations["en-US"].screenshots = { APP_IPHONE_65: ["shot.png"] };
    const configPath = join(directory, "metadata.json");
    writeFileSync(configPath, JSON.stringify(config));

    const loaded = loadConfig(configPath, { cwd: directory });
    expect(loaded.screenshots.get("en-US\u0000APP_IPHONE_65")).toEqual([
      expect.objectContaining({ fileName: "shot.png", fileSize: 39, checksum: expect.stringMatching(/^[a-f0-9]{32}$/u) }),
    ]);
  });

  it("compares screenshot order, file names, checksums, and delivery state", () => {
    const local = [{ fileName: "one.png", checksum: "abc" }];
    const remote = [
      {
        attributes: {
          fileName: "one.png",
          sourceFileChecksum: "ABC",
          assetDeliveryState: { state: "COMPLETE" },
        },
      },
    ];
    expect(screenshotSetMatches(remote, local)).toBe(true);
    expect(screenshotSetMatches([...remote].reverse(), [...local, local[0]])).toBe(false);
  });

  it("diffs only explicitly desired fields", () => {
    expect(diffFields({ name: "Old", subtitle: "Keep" }, { name: "New" })).toEqual({ name: "New" });
  });
});

describe("App Store Connect JWT", () => {
  it("finds a private key in Apple's conventional local directory", () => {
    const home = mkdtempSync(join(tmpdir(), "owc-asc-home-"));
    const directory = join(home, ".appstoreconnect", "private_keys");
    mkdirSync(directory, { recursive: true });
    writeFileSync(join(directory, "AuthKey_KEY123.p8"), "private-key-content");

    expect(
      credentialsFromEnv({ HOME: home, ASC_KEY_ID: "KEY123", ASC_ISSUER_ID: "issuer-123" })
    ).toEqual({
      keyId: "KEY123",
      issuerId: "issuer-123",
      privateKey: "private-key-content",
    });
  });

  it("creates a verifiable ES256 token with Apple's audience", () => {
    const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
    const token = createJwt({
      keyId: "KEY123",
      issuerId: "issuer-123",
      privateKey,
      nowSeconds: 1_700_000_000,
    });
    const [header, payload, signature] = token.split(".");
    expect(JSON.parse(Buffer.from(header, "base64url").toString("utf8"))).toEqual({
      alg: "ES256",
      kid: "KEY123",
      typ: "JWT",
    });
    expect(JSON.parse(Buffer.from(payload, "base64url").toString("utf8"))).toMatchObject({
      iss: "issuer-123",
      aud: "appstoreconnect-v1",
      exp: 1_700_001_140,
    });
    expect(
      verify(
        "sha256",
        Buffer.from(`${header}.${payload}`),
        { key: publicKey, dsaEncoding: "ieee-p1363" },
        Buffer.from(signature, "base64url")
      )
    ).toBe(true);
  });

  it("uploads exactly the byte ranges Apple reserves", async () => {
    const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
    const uploaded = [];
    const api = createApiClient({
      credentials: { keyId: "KEY123", issuerId: "issuer-123", privateKey },
      fetchImpl: async (_url, options) => {
        uploaded.push(Buffer.from(options.body));
        return new Response(null, { status: 200 });
      },
    });
    await api.uploadParts(
      [
        { method: "PUT", url: "https://upload.example/one", offset: 0, length: 3 },
        { method: "PUT", url: "https://upload.example/two", offset: 3, length: 3 },
      ],
      Buffer.from("abcdef")
    );
    expect(uploaded.map((part) => part.toString("utf8"))).toEqual(["abc", "def"]);
  });
});
