import { generateKeyPairSync, createHash, createVerify } from "node:crypto";
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it, vi } from "vitest";
import {
  APP_LOCALE_TO_PLAY,
  PLAY_LANGUAGES,
  applyChanges,
  buildPlan,
  createPlayClient,
  fetchAccessToken,
  loadConfig,
  loadImages,
  parseArgs,
  readImageInfo,
  readRemote,
  textLength,
  validateConfig,
  validateImages,
} from "./play-store-listing-sync.mjs";

function png(width, height, colorType = 2) {
  const ihdr = Buffer.alloc(25);
  ihdr.writeUInt32BE(13, 0);
  ihdr.write("IHDR", 4, "latin1");
  ihdr.writeUInt32BE(width, 8);
  ihdr.writeUInt32BE(height, 12);
  ihdr[16] = 8;
  ihdr[17] = colorType;
  const iend = Buffer.from([0, 0, 0, 0, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82]);
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), ihdr, iend]);
}

function jpeg(width, height) {
  const sof = Buffer.from([0xff, 0xc0, 0x00, 0x11, 0x08, height >> 8, height & 0xff, width >> 8, width & 0xff, 0x03]);
  return Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x04, 0x00, 0x00]), sof, Buffer.alloc(16)]);
}

function sha256(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

function config(listings = { "en-US": { title: "DoneAt", shortDescription: "Short", fullDescription: "Full" } }) {
  return { schemaVersion: 1, packageName: "com.rainif.doneat", imageBaseDir: "images", listings };
}

function asset(content, fileName = "01.png", filePath = fileName) {
  return { language: "en-US", fileName, filePath, bytes: content.length, sha256: sha256(content), info: readImageInfo(content) };
}

function jsonResponse(status, body) {
  return { ok: status >= 200 && status < 300, status, statusText: String(status), text: async () => (body ? JSON.stringify(body) : "") };
}

describe("locale mapping", () => {
  it("maps every app UI locale to a distinct Play language", () => {
    const appLocales = readdirSync("public/locales").sort();
    expect(Object.keys(APP_LOCALE_TO_PLAY).sort()).toEqual(appLocales);
    expect(new Set(Object.values(APP_LOCALE_TO_PLAY)).size).toBe(appLocales.length);
    expect(APP_LOCALE_TO_PLAY.en).toBe("en-US");
    expect(APP_LOCALE_TO_PLAY.pt).toBe("pt-BR");
    expect(APP_LOCALE_TO_PLAY["zh-CN"]).toBe("zh-CN");
  });

  it("also accepts the Android regional variants", () => {
    expect(PLAY_LANGUAGES.has("en-GB")).toBe(true);
    expect(PLAY_LANGUAGES.has("es-419")).toBe(true);
    expect(PLAY_LANGUAGES.has("en")).toBe(false);
  });
});

describe("config validation", () => {
  it("accepts the committed release config", () => {
    const file = readdirSync("play-store").filter((name) => name.endsWith(".json")).sort().at(-1);
    const parsed = JSON.parse(readFileSync(path.join("play-store", file), "utf8"));
    expect(validateConfig(parsed)).toEqual([]);
  });

  it("counts Unicode characters against Play limits", () => {
    expect(textLength("下班👋")).toBe(3);
    const errors = validateConfig(
      config({
        "en-US": { title: "x".repeat(31), shortDescription: "👋".repeat(80), fullDescription: "y".repeat(4001) },
      })
    );
    expect(errors).toEqual([
      "listings.en-US.title: 31 characters exceeds 30.",
      "listings.en-US.fullDescription: 4001 characters exceeds 4000.",
    ]);
  });

  it("rejects unknown languages, fields and empty text", () => {
    const errors = validateConfig(config({ en: { title: "A" }, "zh-CN": { title: " ", video: "x" } }));
    expect(errors).toHaveLength(3);
    expect(errors[0]).toMatch(/^listings\.en: not one of/u);
    expect(errors).toContain("listings.zh-CN.video: unknown field.");
    expect(errors).toContain("listings.zh-CN.title: must be a non-empty string.");
  });

  it("parses modes and flags", () => {
    expect(parseArgs(["--config", "a.json"]).mode).toBe("plan");
    expect(parseArgs(["--apply", "--config=a.json", "--changes-not-sent-for-review", "--text-only"])).toMatchObject({
      mode: "apply",
      configPath: "a.json",
      changesNotSentForReview: true,
      textOnly: true,
    });
    expect(() => parseArgs(["--plan"])).toThrow(/--config/u);
  });
});

describe("image validation", () => {
  it("reads PNG and JPEG dimensions", () => {
    expect(readImageInfo(png(1080, 1920))).toEqual({ format: "png", width: 1080, height: 1920, hasAlpha: false });
    expect(readImageInfo(png(512, 512, 6)).hasAlpha).toBe(true);
    expect(readImageInfo(jpeg(1024, 500))).toEqual({ format: "jpeg", width: 1024, height: 500, hasAlpha: false });
    expect(readImageInfo(Buffer.from("GIF89a"))).toBeNull();
  });

  it("checks counts, sizes, ratio and alpha", () => {
    const images = new Map([
      [
        "en-US",
        new Map([
          ["phoneScreenshots", [asset(png(1080, 2400), "tall.png")]],
          ["featureGraphic", [asset(png(1024, 500, 6), "featureGraphic.png")]],
          ["icon", [asset(jpeg(512, 512), "icon.jpg")]],
        ]),
      ],
    ]);
    expect(validateImages(images)).toEqual([
      "en-US phoneScreenshots: 1 files; Play accepts 2–8.",
      "en-US phoneScreenshots tall.png: 1080×2400; the long side may be at most twice the short side.",
      "en-US featureGraphic featureGraphic.png: must not have an alpha channel.",
      "en-US icon icon.jpg: must be PNG.",
    ]);
  });

  it("loads per-language folders in file-name order and leaves missing types unmanaged", () => {
    const root = mkdtempSync(path.join(tmpdir(), "play-listing-"));
    const phone = path.join(root, "images", "en-US", "phoneScreenshots");
    mkdirSync(phone, { recursive: true });
    writeFileSync(path.join(phone, "10-last.png"), png(1080, 1920));
    writeFileSync(path.join(phone, "2-first.png"), png(1080, 1920));
    writeFileSync(path.join(phone, "notes.txt"), "ignored");
    writeFileSync(path.join(root, "images", "en-US", "featureGraphic.jpg"), jpeg(1024, 500));
    writeFileSync(path.join(root, "play.json"), JSON.stringify(config()));

    const loaded = loadConfig("play.json", { cwd: root });
    const byType = loaded.images.get("en-US");
    expect([...byType.keys()]).toEqual(["phoneScreenshots", "featureGraphic"]);
    expect(byType.get("phoneScreenshots").map((item) => item.fileName)).toEqual(["2-first.png", "10-last.png"]);
    expect(loadImages({ ...config(), imageBaseDir: undefined }, root).size).toBe(0);
  });
});

describe("plan", () => {
  const shot = png(1080, 1920);
  const local = new Map([["en-US", new Map([["phoneScreenshots", [asset(shot, "a.png"), asset(png(1080, 1921), "b.png")]]])]]);

  it("reports matches, text updates and unmanaged languages", () => {
    const remote = {
      listings: new Map([
        ["en-US", { language: "en-US", title: "DoneAt", shortDescription: "Old", fullDescription: "Full", video: "https://youtu.be/x" }],
        ["fr-FR", { language: "fr-FR", title: "DoneAt" }],
      ]),
      images: new Map(),
    };
    const plan = buildPlan(config(), new Map(), remote);
    expect(plan.changes).toEqual([
      expect.objectContaining({ kind: "listing", action: "update", language: "en-US", fields: { shortDescription: "Short" } }),
    ]);
    expect(plan.unmanaged).toEqual(["fr-FR"]);
  });

  it("creates complete new listings and blocks partial ones", () => {
    const remote = { listings: new Map(), images: new Map() };
    const plan = buildPlan(
      config({ "en-US": { title: "A", shortDescription: "B", fullDescription: "C" }, "zh-CN": { title: "下班" } }),
      new Map(),
      remote
    );
    expect(plan.changes.map((change) => [change.language, change.action])).toEqual([["en-US", "create"]]);
    expect(plan.blockers).toEqual(["zh-CN: a new listing needs shortDescription, fullDescription."]);
  });

  it("compares image sets by SHA-256 and order", () => {
    const listings = new Map([["en-US", { language: "en-US", title: "DoneAt", shortDescription: "Short", fullDescription: "Full" }]]);
    const [a, b] = local.get("en-US").get("phoneScreenshots");
    const same = { listings, images: new Map([["en-US\u0000phoneScreenshots", [{ sha256: a.sha256.toUpperCase() }, { sha256: b.sha256 }]]]) };
    expect(buildPlan(config(), local, same).changes).toEqual([]);

    const reordered = { listings, images: new Map([["en-US\u0000phoneScreenshots", [{ sha256: b.sha256 }, { sha256: a.sha256 }]]]) };
    expect(buildPlan(config(), local, reordered).changes).toEqual([
      expect.objectContaining({ kind: "images", action: "replace", imageType: "phoneScreenshots" }),
    ]);
    expect(buildPlan(config(), local, reordered, { textOnly: true }).changes).toEqual([]);
  });
});

describe("Google Play API client", () => {
  it("signs a service-account JWT for the androidpublisher scope", async () => {
    const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
    const key = { client_email: "sync@example.iam.gserviceaccount.com", private_key: privateKey.export({ type: "pkcs8", format: "pem" }) };
    const fetchImpl = vi.fn(async () => ({ ok: true, json: async () => ({ access_token: "token" }) }));
    await expect(fetchAccessToken(key, { fetchImpl, now: 1_000_000 })).resolves.toBe("token");

    const assertion = fetchImpl.mock.calls[0][1].body.get("assertion");
    const [header, payload, signature] = assertion.split(".");
    expect(JSON.parse(Buffer.from(payload, "base64url"))).toMatchObject({
      iss: key.client_email,
      scope: "https://www.googleapis.com/auth/androidpublisher",
      iat: 1000,
      exp: 4600,
    });
    expect(createVerify("RSA-SHA256").update(`${header}.${payload}`).verify(publicKey, signature, "base64url")).toBe(true);
  });

  it("reads listings and images, then writes changes in one edit", async () => {
    const calls = [];
    const shot = png(1080, 1920);
    const directory = mkdtempSync(path.join(tmpdir(), "play-upload-"));
    writeFileSync(path.join(directory, "a.png"), shot);
    const fetchImpl = vi.fn(async (url, init) => {
      const { pathname, search } = new URL(url);
      calls.push(`${init.method} ${pathname.replace("/androidpublisher/v3/applications/com.rainif.doneat", "")}${search}`);
      if (pathname.endsWith("/listings") && init.method === "GET") {
        return jsonResponse(200, { listings: [{ language: "en-US", title: "Old", shortDescription: "Short", fullDescription: "Full" }] });
      }
      if (pathname.endsWith("/phoneScreenshots") && init.method === "GET") {
        return jsonResponse(200, { images: [{ id: "1", sha256: "00" }] });
      }
      return jsonResponse(200, {});
    });
    const client = createPlayClient({ accessToken: "token", packageName: "com.rainif.doneat", fetchImpl });
    const images = new Map([["en-US", new Map([["phoneScreenshots", [asset(shot, "a.png", path.join(directory, "a.png"))]]])]]);

    const remote = await readRemote(client, "edit1", config(), images);
    const plan = buildPlan(config(), images, remote);
    vi.spyOn(console, "log").mockImplementation(() => {});
    await applyChanges(client, "edit1", plan);
    await client.commitEdit("edit1", { changesNotSentForReview: true });

    expect(calls).toEqual([
      "GET /edits/edit1/listings",
      "GET /edits/edit1/listings/en-US/phoneScreenshots",
      "PATCH /edits/edit1/listings/en-US",
      "DELETE /edits/edit1/listings/en-US/phoneScreenshots",
      "POST /upload/edits/edit1/listings/en-US/phoneScreenshots?uploadType=media",
      "POST /edits/edit1:commit?changesNotSentForReview=true",
    ]);
    expect(JSON.parse(fetchImpl.mock.calls[2][1].body)).toEqual({ language: "en-US", title: "DoneAt" });
    expect(fetchImpl.mock.calls[4][1].headers["Content-Type"]).toBe("image/png");
    expect(fetchImpl.mock.calls[0][1].headers.Authorization).toBe("Bearer token");
  });

  it("surfaces Google error messages with the status", async () => {
    const fetchImpl = async () => jsonResponse(403, { error: { message: "The caller does not have permission" } });
    const client = createPlayClient({ accessToken: "token", packageName: "com.rainif.doneat", fetchImpl });
    await expect(client.insertEdit()).rejects.toMatchObject({
      status: 403,
      message: expect.stringContaining("HTTP 403 The caller does not have permission"),
    });
  });
});
