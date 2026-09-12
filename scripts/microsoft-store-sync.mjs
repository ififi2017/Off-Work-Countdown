#!/usr/bin/env node

// 用微软商店提交 API 同步商品页：文案 + 截图。
//
//   node scripts/microsoft-store-sync.mjs --plan     # 只读，打印当前提交与将要发生的改动
//   node scripts/microsoft-store-sync.mjs --apply    # 写入文案、上传截图 ZIP（不提交审核）
//   node scripts/microsoft-store-sync.mjs --commit   # 真正提交，会进入预处理与认证
//
// 为什么不用网页端的「导入列表」：那条路要求语言必须先存在于商品页语言集里，
// 而且图片要靠浏览器逐张传。API 这边语言直接写在提交 JSON 里，图片打成一个 ZIP
// 一次传完。踩过的坑见 scripts/marketing-shots/README.md。
//
// ⚠️ 标题不能在这里改。API 接受带 title 的 PUT 并返回 200，但读回来仍是主名称——
// 每个语言用哪个保留名，只能在合作伙伴中心网页端的「产品名称」下拉框里选。
// 选好标题再用 API 写这个提交可能会被 409 拒掉（见下），所以顺序是：
// 先跑 --apply，再去网页端选标题，最后在网页端提交。
//
// ⚠️ --commit 不是「保存草稿」。它把提交推进到 CommitStarted → PreProcessing →
// Certification，等于把这一版交上去。所以它是独立的一步，--apply 不会代劳。
//
// 凭据放在仓库之外，默认读 ~/.config/doneat/msstore.env（也可直接用同名环境变量）：
//   MSSTORE_TENANT_ID / MSSTORE_CLIENT_ID / MSSTORE_CLIENT_SECRET / MSSTORE_SELLER_ID
// 脚本不打印凭据，也不打印 Azure 返回的上传地址（那是带签名的 SAS）。

import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, copyFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { LISTINGS, SHOTS } from "./marketing-shots/windows/listing-copy.mjs";

const STORE_ID = "9PM0HJ2PP2LJ";
const API = "https://manage.devcenter.microsoft.com/v1.0/my";
const IMAGES_DIR = new URL("marketing-shots/windows/out/", import.meta.url).pathname;

// 截图没变时加 --text-only：那一百兆的 ZIP 不必重传一遍。
const textOnly = process.argv.includes("--text-only");
const mode = process.argv.includes("--apply") ? "apply"
  : process.argv.includes("--commit") ? "commit"
  : "plan";

function credentials() {
  const file = join(process.env.HOME ?? "", ".config/doneat/msstore.env");
  const values = { ...process.env };
  if (existsSync(file)) {
    for (const line of readFileSync(file, "utf8").split("\n")) {
      const match = line.match(/^\s*([A-Z_]+)\s*=\s*(.*?)\s*$/);
      if (match) values[match[1]] ??= match[2].replace(/^["']|["']$/g, "");
    }
  }
  const missing = ["MSSTORE_TENANT_ID", "MSSTORE_CLIENT_ID", "MSSTORE_CLIENT_SECRET"]
    .filter((name) => !values[name]);
  if (missing.length > 0) {
    throw new Error(`缺少凭据 ${missing.join(", ")}；放进 ${file} 或设为环境变量`);
  }
  return values;
}

async function token({ MSSTORE_TENANT_ID, MSSTORE_CLIENT_ID, MSSTORE_CLIENT_SECRET }) {
  const response = await fetch(`https://login.microsoftonline.com/${MSSTORE_TENANT_ID}/oauth2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "client_credentials",
      client_id: MSSTORE_CLIENT_ID,
      client_secret: MSSTORE_CLIENT_SECRET,
      resource: "https://manage.devcenter.microsoft.com",
    }),
  });
  if (!response.ok) {
    // 不回显响应体：里面可能带着请求参数。
    throw new Error(`取访问令牌失败：HTTP ${response.status}`);
  }
  return (await response.json()).access_token;
}

async function api(path, accessToken, options = {}) {
  const response = await fetch(`${API}${path}`, {
    ...options,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
      ...options.headers,
    },
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`${options.method ?? "GET"} ${path} → HTTP ${response.status}\n${text.slice(0, 800)}`);
  return text ? JSON.parse(text) : null;
}

const accessToken = await token(credentials());
const app = await api(`/applications/${STORE_ID}`, accessToken);

// 商店的商品页可以脱离包体单独更新：新建的提交是上一个已发布提交的克隆，
// 里面的安装包原样带过来（fileStatus 仍是 Uploaded），不必重传。
//
// ⚠️ 一个在合作伙伴中心里建出来的待处理提交，API 往往整份不可写——原样 PUT
// 回去也会 409 InvalidState，报的状态是 'None'。那种情况只能删掉它再新建，
// 所以这里宁可自己建，也不去改网页端留下的那一个。
let submissionId = app.pendingApplicationSubmission?.id ?? null;
let submission;
if (submissionId) {
  submission = await api(`/applications/${STORE_ID}/submissions/${submissionId}`, accessToken);
} else if (mode === "plan") {
  submissionId = app.lastPublishedApplicationSubmission?.id;
  if (!submissionId) throw new Error("既没有待处理的提交，也没有已发布的提交。");
  submission = await api(`/applications/${STORE_ID}/submissions/${submissionId}`, accessToken);
  console.log("（当前没有待处理提交，以下以最近已发布的那个作为预览底稿）");
} else if (mode === "commit") {
  throw new Error("没有待处理的提交可提交；先跑 --apply。");
} else {
  submission = await api(`/applications/${STORE_ID}/submissions`, accessToken, { method: "POST" });
  submissionId = submission.id;
  console.log(`已新建提交 ${submissionId}（克隆自上一个已发布的提交）`);
}

const locales = Object.keys(submission.listings ?? {});
console.log(`应用: ${app.primaryName ?? STORE_ID}`);
console.log(`待处理提交: ${submissionId}  状态: ${submission.status}`);
console.log(`提交里现有语言 (${locales.length}): ${locales.join(", ")}`);
console.log(`包: ${(submission.applicationPackages ?? []).length} 个`);

const sample = submission.listings?.[locales[0]]?.baseListing;
if (sample) {
  console.log(`\n以 ${locales[0]} 为样本，baseListing 的字段: ${Object.keys(sample).join(", ")}`);
  console.log(`截图条目 ${sample.images?.length ?? 0} 个，示例: ${JSON.stringify(sample.images?.[0] ?? null)}`);
}

console.log(`\n本地文案覆盖 ${Object.keys(LISTINGS).length} 个语言，每个 ${SHOTS.length} 张截图`);
const missingImages = [];
for (const [locale, listing] of Object.entries(LISTINGS)) {
  for (const [index, shot] of SHOTS.entries()) {
    const file = join(IMAGES_DIR, `${listing.appLanguage}-${String(index + 1).padStart(2, "0")}-${shot}.png`);
    if (!existsSync(file)) missingImages.push(file);
  }
}
if (missingImages.length > 0) {
  console.log(`⚠️ 缺 ${missingImages.length} 张截图，先跑 npm run shots:windows`);
}

function baseListingFor(locale, listing) {
  // 新语言以 en-us 为底：隐私政策、支持邮箱、网址、标题这些是共享的，逐个重填没意义。
  const current = submission.listings?.[locale]?.baseListing;
  const template = current ?? submission.listings?.["en-us"]?.baseListing ?? {};
  return {
    ...template,
    description: listing.description,
    releaseNotes: listing.releaseNotes,
    features: [...(listing.features ?? template.features ?? []), listing.feature15],
    keywords: listing.searchTerms ?? template.keywords ?? [],
    shortDescription: listing.shortDescription ?? template.shortDescription ?? "",
    copyrightAndTrademarkInfo: template.copyrightAndTrademarkInfo || "MIT License",
    devStudio: template.devStudio || "fi_niaR Studio",
    images: SHOTS.map((shot, index) => ({
      fileName: `${locale}-${String(index + 1).padStart(2, "0")}-${shot}.png`,
      fileStatus: "PendingUpload",
      description: listing.captions[index],
      imageType: "Screenshot",
    })),
  };
}

// CSV 那条路的印尼语必须写成 id-id（列名 id 会和 CSV 自带的 ID 列撞名），
// API 这边没有这个问题，用商店惯用的 id。
const apiLocale = (locale) => (locale === "id-id" ? "id" : locale);

const created = [];
const updated = [];
for (const [locale, listing] of Object.entries(LISTINGS)) {
  const key = apiLocale(locale);
  (submission.listings?.[key] ? updated : created).push(key);
  submission.listings ??= {};
  submission.listings[key] = {
    ...submission.listings[key],
    baseListing: baseListingFor(key, listing),
  };
}

console.log(`\n将新建 ${created.length} 个语言: ${created.join(", ") || "无"}`);
console.log(`将更新 ${updated.length} 个语言: ${updated.join(", ")}`);
console.log(`每个语言写入 ${SHOTS.length} 张截图，共 ${Object.keys(LISTINGS).length * SHOTS.length} 张`);

// 商店限制：一个语言的所有搜索词加起来不超过 21 个词（不是每条 21 个）。
const overLimit = Object.entries(LISTINGS)
  .filter(([, listing]) => listing.searchTerms)
  .map(([locale, listing]) => [locale, listing.searchTerms.reduce((n, t) => n + t.trim().split(/\s+/).length, 0)])
  .filter(([, words]) => words > 21);
if (overLimit.length > 0) {
  throw new Error(`搜索词超限（每个语言总词数 ≤ 21）：${overLimit.map(([l, w]) => `${l}=${w}`).join(", ")}`);
}

if (mode === "plan") {
  console.log("\n只读模式，未做任何改动。确认无误后用 --apply 写入文案并上传截图。");
  process.exit(0);
}

if (mode === "commit") {
  const result = await api(`/applications/${STORE_ID}/submissions/${submissionId}/commit`, accessToken, { method: "POST" });
  console.log(`\n已提交，状态: ${result.status}`);
  for (let attempt = 0; attempt < 20; attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 15000));
    const { status, statusDetails } = await api(`/applications/${STORE_ID}/submissions/${submissionId}/status`, accessToken);
    console.log(`  ${status}`);
    const errors = statusDetails?.errors ?? [];
    if (errors.length > 0) console.log(`  错误: ${JSON.stringify(errors).slice(0, 600)}`);
    if (!["CommitStarted", "PendingCommit", "PreProcessing"].includes(status)) break;
  }
  process.exit(0);
}

// --apply：先写提交数据，再把图片打成一个 ZIP 传到那次提交的上传地址。
await api(`/applications/${STORE_ID}/submissions/${submissionId}`, accessToken, {
  method: "PUT",
  body: JSON.stringify(submission),
});
console.log("\n提交数据已写入（文案 + 截图清单）。");

if (textOnly) {
  console.log("--text-only：跳过截图上传（沿用这次提交里已上传的那批）。");
  process.exit(0);
}

const staging = mkdtempSync(join(tmpdir(), "msstore-upload-"));
let packed = 0;
for (const [locale, listing] of Object.entries(LISTINGS)) {
  SHOTS.forEach((shot, index) => {
    const order = String(index + 1).padStart(2, "0");
    const source = join(IMAGES_DIR, `${listing.appLanguage}-${order}-${shot}.png`);
    copyFileSync(source, join(staging, `${apiLocale(locale)}-${order}-${shot}.png`));
    packed += 1;
  });
}
const zipPath = join(staging, "upload.zip");
execFileSync("zip", ["-X", "-q", zipPath, ...SHOTS.flatMap((shot, index) =>
  Object.keys(LISTINGS).map((locale) => `${apiLocale(locale)}-${String(index + 1).padStart(2, "0")}-${shot}.png`))],
  { cwd: staging });
const zipSize = statSync(zipPath).size;
console.log(`已打包 ${packed} 张截图，${(zipSize / 1048576).toFixed(1)} MB，开始上传…`);

// 单次 PUT 即可：块 blob 的单请求上限是 256 MB，这个 ZIP 远小于它。
const upload = await fetch(submission.fileUploadUrl.replace("+", "%2B"), {
  method: "PUT",
  headers: { "x-ms-blob-type": "BlockBlob", "Content-Length": String(zipSize) },
  body: readFileSync(zipPath),
});
rmSync(staging, { recursive: true, force: true });
if (!upload.ok) throw new Error(`上传 ZIP 失败：HTTP ${upload.status}`);
console.log("截图已上传。");
console.log("\n下一步：确认无误后跑 --commit。它会把这一版推进到预处理与认证。");
