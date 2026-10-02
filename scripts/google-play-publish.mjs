#!/usr/bin/env node

// 用 Google Play Developer API（v3）给 Android 版传包。
//
//   node scripts/google-play-publish.mjs --status              # 只读：各轨道的版本和下一个可用的 versionCode
//   node scripts/google-play-publish.mjs --next-version-code   # 只打印下一个 versionCode（给工作流用）
//   node scripts/google-play-publish.mjs --upload <aab>        # 上传 AAB，挂到封闭测试轨道的草稿版本
//   node scripts/google-play-publish.mjs --upload <aab> --track <轨道>
//                                                              # 换轨道；默认 alpha（Console 里的「封闭式测试」）
//
// ⚠️ --upload 只建草稿，不会发给测试人员：版本说明、审核和「开始发布」都在 Play Console
// 里手动点。和 Chrome 扩展、微软商店一样，传包和对外发布是两步。
//
// 凭据放在仓库之外，默认读 ~/.config/doneat/google-play.env（也可直接用同名环境变量）：
//   PLAY_SERVICE_ACCOUNT_JSON   服务账号 JSON 密钥的内容（CI 用 GitHub Secret 传）
//   PLAY_SERVICE_ACCOUNT_KEY    或者该 JSON 文件的路径（本机用）
// 该服务账号要先在 Play Console「用户和权限」里加入，并对这个应用授予发布到测试轨道的权限。
// 脚本不打印任何凭据或访问令牌。
//
// versionCode 不写回仓库：Play 才是事实来源。下一个值取「Play 上已有的最大值 + 1」和
// app/build.gradle.kts 里默认值中较大的那个，再经 Gradle 属性 doneatVersionCode 传给构建。

import { createSign } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { basename, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const root = resolve(import.meta.dirname, "..");
const PACKAGE_NAME = "com.rainif.doneat";
const API = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE_NAME}`;
const UPLOAD_API = `https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/${PACKAGE_NAME}`;
const SCOPE = "https://www.googleapis.com/auth/androidpublisher";
const GRADLE_FILE = join(root, "src-mobile/android/app/build.gradle.kts");

/** app/build.gradle.kts 里的 versionName 和 versionCode 默认值。 */
export function gradleVersions(source) {
  const versionName = source.match(/versionName\s*=\s*"([^"]+)"/)?.[1];
  const versionCode = Number(
    source.match(/versionCode\s*=\s*providers\.gradleProperty\("doneatVersionCode"\)\.orElse\("(\d+)"\)/)?.[1] ??
      source.match(/versionCode\s*=\s*(\d+)/)?.[1],
  );
  if (!versionName || !Number.isInteger(versionCode)) {
    throw new Error("在 app/build.gradle.kts 里找不到 versionName / versionCode");
  }
  return { versionName, versionCode };
}

/** Play 上传过的包（含没进任何轨道的）和所有轨道版本里出现过的 versionCode。 */
export function usedVersionCodes(bundles = [], tracks = []) {
  const codes = bundles.map((bundle) => Number(bundle.versionCode));
  for (const track of tracks) {
    for (const release of track.releases ?? []) {
      codes.push(...(release.versionCodes ?? []).map(Number));
    }
  }
  return codes.filter(Number.isInteger);
}

export function nextVersionCode(used, localDefault) {
  return Math.max(localDefault, ...used.map((code) => code + 1));
}

/**
 * 写回轨道的版本列表：保留正在发布 / 已完成 / 已暂停的版本，旧草稿换成这一个。
 * tracks.update 会用请求里的列表替换整条轨道，漏掉的版本会被撤下。
 */
export function releasesWithDraft(existing = [], draft) {
  return [...existing.filter((release) => release.status !== "draft"), { ...draft, status: "draft" }];
}

function credentials() {
  const file = join(process.env.HOME ?? "", ".config/doneat/google-play.env");
  const values = { ...process.env };
  if (existsSync(file)) {
    for (const line of readFileSync(file, "utf8").split("\n")) {
      const match = line.match(/^\s*([A-Z_]+)\s*=\s*(.*?)\s*$/);
      if (match) values[match[1]] ??= match[2].replace(/^["']|["']$/g, "");
    }
  }
  if (values.PLAY_SERVICE_ACCOUNT_JSON) return JSON.parse(values.PLAY_SERVICE_ACCOUNT_JSON);
  if (values.PLAY_SERVICE_ACCOUNT_KEY) return JSON.parse(readFileSync(values.PLAY_SERVICE_ACCOUNT_KEY, "utf8"));
  throw new Error(`缺少凭据 PLAY_SERVICE_ACCOUNT_JSON 或 PLAY_SERVICE_ACCOUNT_KEY；放进 ${file} 或设为环境变量`);
}

async function accessToken(key) {
  // 服务账号：用私钥签一个 JWT，换一小时有效的访问令牌。
  const now = Math.floor(Date.now() / 1000);
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const unsigned = `${encode({ alg: "RS256", typ: "JWT" })}.${encode({
    iss: key.client_email,
    scope: SCOPE,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  })}`;
  const signature = createSign("RSA-SHA256").update(unsigned).sign(key.private_key, "base64url");
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsigned}.${signature}`,
    }),
  });
  if (!response.ok) {
    // 不回显响应体：里面可能带着请求参数。
    throw new Error(`取访问令牌失败：HTTP ${response.status}`);
  }
  return (await response.json()).access_token;
}

async function api(url, token, options = {}) {
  const response = await fetch(url, {
    ...options,
    headers: { Authorization: `Bearer ${token}`, ...options.headers },
  });
  const text = await response.text();
  if (!response.ok) {
    const path = url.replace(/^.*\/applications\/[^/]+/, "").replace(/\?.*$/, "");
    throw new Error(`${options.method ?? "GET"} ${path || "/"} 失败：HTTP ${response.status} ${text}`);
  }
  return text ? JSON.parse(text) : {};
}

const json = (method, body) => ({
  method,
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify(body),
});

function describe(track) {
  const releases = (track.releases ?? [])
    .map((release) => `${release.name ?? "未命名"}（${release.status}，${(release.versionCodes ?? []).join("/") || "无包"}）`)
    .join("、");
  return `${track.track}：${releases || "无版本"}`;
}

function option(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

async function main() {
  const mode = process.argv.includes("--upload") ? "upload"
    : process.argv.includes("--next-version-code") ? "next"
    : "status";
  const local = gradleVersions(readFileSync(GRADLE_FILE, "utf8"));
  const token = await accessToken(credentials());

  // 所有读写都在一次「编辑」里；没提交的编辑（只读模式或中途失败）最后删掉，不留痕迹。
  const edit = await api(`${API}/edits`, token, json("POST", {}));
  const editUrl = `${API}/edits/${edit.id}`;
  let committed = false;
  try {
    const { bundles = [] } = await api(`${editUrl}/bundles`, token);
    const { tracks = [] } = await api(`${editUrl}/tracks`, token);
    const next = nextVersionCode(usedVersionCodes(bundles, tracks), local.versionCode);

    if (mode === "next") {
      console.log(next);
      return;
    }
    if (mode === "status") {
      for (const track of tracks) console.log(describe(track));
      console.log(`本地版本：${local.versionName}；下一个 versionCode：${next}`);
      return;
    }

    const aab = option("--upload");
    const track = option("--track") ?? "alpha";
    if (!aab || !existsSync(aab)) throw new Error(`找不到要上传的 AAB：${aab ?? "（未指定）"}`);

    console.log(`上传 ${basename(aab)} …`);
    const bundle = await api(`${UPLOAD_API}/edits/${edit.id}/bundles?uploadType=media`, token, {
      method: "POST",
      headers: { "Content-Type": "application/octet-stream" },
      body: readFileSync(aab),
    });
    // 包里的版本以 Play 解析出来的为准，防止构建时没吃到 doneatVersionCode。
    if (usedVersionCodes(bundles, tracks).includes(Number(bundle.versionCode))) {
      throw new Error(`versionCode ${bundle.versionCode} 已经在 Play 上用过了`);
    }

    const current = tracks.find((item) => item.track === track);
    const releases = releasesWithDraft(current?.releases, {
      name: `${local.versionName} (${bundle.versionCode})`,
      versionCodes: [String(bundle.versionCode)],
    });
    await api(`${editUrl}/tracks/${track}`, token, json("PUT", { track, releases }));
    await api(`${editUrl}:commit`, token, { method: "POST" });
    committed = true;
    console.log(`已上传 ${local.versionName} (${bundle.versionCode}) 到 ${track} 轨道草稿。`);
    console.log("在 Play Console 里补版本说明、检查后点「开始发布」。");
  } finally {
    if (!committed) await api(editUrl, token, { method: "DELETE" }).catch(() => {});
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
