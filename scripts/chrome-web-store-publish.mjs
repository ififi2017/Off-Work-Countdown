#!/usr/bin/env node

// 用 Chrome Web Store API（V2）给已上架的扩展发新版本。
//
//   node scripts/chrome-web-store-publish.mjs --status    # 只读：商店里已发布 / 审核中的版本和本地版本
//   node scripts/chrome-web-store-publish.mjs --upload    # 构建、打包、上传新版本（不提交审核）
//   node scripts/chrome-web-store-publish.mjs --publish   # 把已上传的版本提交审核，通过后自动发布
//   node scripts/chrome-web-store-publish.mjs --publish --staged
//                                                         # 提交审核，通过后等在后台手动点发布
//
// API 只能给已有条目传包和提交审核：新建条目、商店页文案、截图、宣传图和隐私问卷
// 都只能在开发者后台网页端填（文案见 docs/CHROME-WEB-STORE-LISTING.md，
// 图见 `npm run shots:chrome-web-store`）。所以第一版要在网页端手动上架。
//
// ⚠️ --publish 不是「保存草稿」：它把这一版交给审核，通过后按商店可见性设置对外发布。
// 所以它是独立的一步，--upload 不会代劳。
//
// 凭据放在仓库之外，默认读 ~/.config/doneat/chrome-web-store.env（也可直接用同名环境变量）：
//   CWS_PUBLISHER_ID     开发者后台「发布者 → 设置」里的发布者 ID
//   CWS_ITEM_ID          扩展 ID（后台条目地址里那 32 个字母）
// 以及二选一的认证方式：
//   CWS_SERVICE_ACCOUNT_KEY   服务账号 JSON 密钥文件的路径（推荐；该账号邮箱要先加到后台「账号」页）
//   CWS_CLIENT_ID / CWS_CLIENT_SECRET / CWS_REFRESH_TOKEN   OAuth 客户端与刷新令牌
// 脚本不打印任何凭据或访问令牌。

import { spawnSync } from "node:child_process";
import { createSign } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { packageExtension } from "./package-extension.mjs";

const root = resolve(import.meta.dirname, "..");
const API = "https://chromewebstore.googleapis.com";
const SCOPE = "https://www.googleapis.com/auth/chromewebstore";
const mode = process.argv.includes("--upload") ? "upload"
  : process.argv.includes("--publish") ? "publish"
  : "status";

function credentials() {
  const file = join(process.env.HOME ?? "", ".config/doneat/chrome-web-store.env");
  const values = { ...process.env };
  if (existsSync(file)) {
    for (const line of readFileSync(file, "utf8").split("\n")) {
      const match = line.match(/^\s*([A-Z_]+)\s*=\s*(.*?)\s*$/);
      if (match) values[match[1]] ??= match[2].replace(/^["']|["']$/g, "");
    }
  }
  const oauth = ["CWS_CLIENT_ID", "CWS_CLIENT_SECRET", "CWS_REFRESH_TOKEN"];
  const missing = ["CWS_PUBLISHER_ID", "CWS_ITEM_ID"].filter((name) => !values[name]);
  if (!values.CWS_SERVICE_ACCOUNT_KEY) missing.push(...oauth.filter((name) => !values[name]));
  if (missing.length > 0) {
    throw new Error(
      `缺少凭据 ${missing.join(", ")}；放进 ${file} 或设为环境变量` +
        "（认证用 CWS_SERVICE_ACCOUNT_KEY，或 OAuth 三项）",
    );
  }
  return values;
}

async function tokenRequest(body) {
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(body),
  });
  if (!response.ok) {
    // 不回显响应体：里面可能带着请求参数。
    throw new Error(`取访问令牌失败：HTTP ${response.status}`);
  }
  return (await response.json()).access_token;
}

async function accessToken(values) {
  if (values.CWS_SERVICE_ACCOUNT_KEY) {
    // 服务账号：用私钥签一个 JWT，换一小时有效的访问令牌。
    const key = JSON.parse(readFileSync(values.CWS_SERVICE_ACCOUNT_KEY, "utf8"));
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
    return tokenRequest({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsigned}.${signature}`,
    });
  }
  return tokenRequest({
    grant_type: "refresh_token",
    client_id: values.CWS_CLIENT_ID,
    client_secret: values.CWS_CLIENT_SECRET,
    refresh_token: values.CWS_REFRESH_TOKEN,
  });
}

async function api(path, token, options = {}) {
  const response = await fetch(`${API}${path}`, {
    ...options,
    headers: { Authorization: `Bearer ${token}`, ...options.headers },
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`${options.method ?? "GET"} ${path.split(":").pop()} 失败：HTTP ${response.status} ${text}`);
  return text ? JSON.parse(text) : {};
}

// 1.10.0 > 1.9.3：按段比数字，不按字符串比。
function newer(a, b) {
  const x = a.split(".").map(Number);
  const y = b.split(".").map(Number);
  for (let i = 0; i < Math.max(x.length, y.length); i += 1) {
    if ((x[i] ?? 0) !== (y[i] ?? 0)) return (x[i] ?? 0) > (y[i] ?? 0);
  }
  return false;
}

const versionsOf = (revision) =>
  (revision?.distributionChannels ?? []).map((channel) => channel.crxVersion).filter(Boolean);

function describe(label, revision) {
  if (!revision) return `${label}：无`;
  const channels = (revision.distributionChannels ?? [])
    .map((channel) => `${channel.crxVersion}（${channel.deployPercentage ?? 100}%）`)
    .join("、");
  return `${label}：${revision.state}${channels ? ` · ${channels}` : ""}`;
}

const values = credentials();
const item = `/v2/publishers/${values.CWS_PUBLISHER_ID}/items/${values.CWS_ITEM_ID}`;
const token = await accessToken(values);
const status = await api(`${item}:fetchStatus`, token);
const localVersion = JSON.parse(readFileSync(join(root, "package.json"), "utf8")).version;

console.log(describe("已发布", status.publishedItemRevisionStatus));
console.log(describe("审核中", status.submittedItemRevisionStatus));
console.log(`最近一次上传：${status.lastAsyncUploadState ?? "无"}`);
console.log(`本地版本：${localVersion}`);
if (status.takenDown || status.warned) {
  console.log(`⚠️ 商店标记：${status.takenDown ? "已下架" : ""}${status.warned ? " 收到政策警告" : ""}，先去后台处理`);
}

if (mode === "upload") {
  // 商店要求新包的版本号高于已发布和审核中的版本，先在本地拦下来。
  const existing = [
    ...versionsOf(status.publishedItemRevisionStatus),
    ...versionsOf(status.submittedItemRevisionStatus),
  ];
  const blocking = existing.find((version) => !newer(localVersion, version));
  if (blocking) {
    throw new Error(`本地版本 ${localVersion} 不高于商店里的 ${blocking}；先按发版流程升版本号`);
  }
  const build = spawnSync("npm", ["run", "build:extension"], { cwd: root, stdio: "inherit" });
  if (build.status !== 0) process.exit(build.status ?? 1);
  const { zip, version } = packageExtension();
  console.log(`\n上传 ${zip} …`);
  let upload = await api(`/upload${item}:upload`, token, {
    method: "POST",
    headers: { "Content-Type": "application/zip" },
    body: readFileSync(zip),
  });
  // 大包会异步处理：轮询 fetchStatus 直到有结果。
  for (let attempt = 0; upload.uploadState === "IN_PROGRESS" && attempt < 30; attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 5000));
    upload = { uploadState: (await api(`${item}:fetchStatus`, token)).lastAsyncUploadState };
  }
  if (upload.uploadState !== "SUCCEEDED") {
    throw new Error(`上传没有成功：${upload.uploadState ?? "未知状态"}`);
  }
  console.log(`已上传 ${version}。确认无误后运行 npm run cws:publish 提交审核。`);
}

if (mode === "publish") {
  const staged = process.argv.includes("--staged");
  const result = await api(`${item}:publish`, token, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ publishType: staged ? "STAGED_PUBLISH" : "DEFAULT_PUBLISH" }),
  });
  console.log(`\n已提交审核：${result.state}`);
  for (const warning of result.warningInfo?.warnings ?? []) {
    console.log(`⚠️ ${warning.reason}: ${warning.description}`);
  }
  console.log(staged
    ? "审核通过后不会自动上线，需要在开发者后台手动发布。"
    : "审核通过后会按商店可见性设置自动发布。");
}
