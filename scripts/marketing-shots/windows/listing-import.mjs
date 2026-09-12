// 生成微软商店「导入列表」用的文件夹：一份 CSV 加一个 images/。
//
//   node scripts/marketing-shots/windows/listing-import.mjs \
//     ~/Downloads/listingData-9PM0HJ2PP2LJ-<submission>.csv ~/Downloads/doneat-msstore-3.1.9
//
// 第一个参数是 Partner Center「导出列表」下载的 CSV，第二个是要生成的根文件夹。
// 在合作伙伴中心选「导入列表 → 导入文件夹」，选这个根文件夹即可。
//
// 规则来自 import-and-export-store-listings：
// - 文件夹里只能有一个 CSV，图片放同目录或子目录；
// - 图片字段写「根文件夹名/子路径」，导入后会变成 Partner Center 的 URL。路径是相对
//   根文件夹的**上一级**算的，尽管上传的就是那个根文件夹、CSV 也在里面：实测
//   `images/x.png` 会被拒（同样是一句没有细节的错误），`<根文件夹>/images/x.png` 才通过；
// - 某语言字段留空会回退到 default 列（这里是空的），所以要填的都显式写上；
// - 图片字段留空不会删除旧图，所以五个截图槽位全部重写；
// - 表头加一列语言代码就能新开该语言的商品页。Field / ID / Type 三列不能动。
//
// 包里声明了全部 19 个语言（src-tauri/msstore/Package.appxmanifest），所以新语言
// 不需要指定 Title —— 只有「包里没有的语言」才必须从保留名称里挑一个。
//
// ⚠️ 写出来的 CSV 不带 BOM。Partner Center 导出的文件是 UTF-8 with BOM，而它自己的
// 导入端处理不了：带 BOM 的文件——哪怕是刚导出、一个字没改的那份——只会报一句没有
// 任何细节的错误。去掉 BOM 才能导入。

import { copyFileSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { basename, join, resolve } from "node:path";
import { LISTINGS, SHOTS } from "./listing-copy.mjs";

/** RFC 4180：字段可以带引号，引号内允许逗号、换行和成对的双引号。 */
function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = "";
  let quoted = false;
  for (let i = 0; i < text.length; i += 1) {
    const char = text[i];
    if (quoted) {
      if (char !== '"') field += char;
      else if (text[i + 1] === '"') { field += '"'; i += 1; }
      else quoted = false;
    } else if (char === '"') {
      quoted = true;
    } else if (char === ",") {
      row.push(field); field = "";
    } else if (char === "\r" || char === "\n") {
      if (char === "\r" && text[i + 1] === "\n") i += 1;
      row.push(field); rows.push(row); row = []; field = "";
    } else {
      field += char;
    }
  }
  if (field !== "" || row.length > 0) { row.push(field); rows.push(row); }
  return rows;
}

/** CRLF、仅在必要时加引号，且不写 BOM（见文件开头）。 */
function serializeCsv(rows) {
  return rows.map((row) => row.map((value) => (
    /[",\r\n]/.test(value) ? `"${value.replaceAll('"', '""')}"` : value
  )).join(",")).join("\r\n");
}

const [sourceCsv, outRoot] = process.argv.slice(2);
if (!sourceCsv || !outRoot) {
  throw new Error("usage: listing-import.mjs <exported.csv> <output folder>");
}

const rootPath = resolve(outRoot);
const pathPrefix = `${basename(rootPath)}/images`;
const shotsDir = new URL("out/", import.meta.url).pathname;

const rows = parseCsv(readFileSync(resolve(sourceCsv), "utf8").replace(/^﻿/, ""));
const header = rows[0];
for (const locale of Object.keys(LISTINGS)) {
  if (!header.includes(locale)) header.push(locale);
}
for (const row of rows.slice(1)) {
  while (row.length < header.length) row.push("");
}
const column = Object.fromEntries(Object.keys(LISTINGS).map((locale) => [locale, header.indexOf(locale)]));

const byField = new Map();
for (const row of rows) if (row[0]) byField.set(row[0], row);
function set(field, locale, value) {
  const row = byField.get(field);
  if (!row) throw new Error(`field not found in the exported CSV: ${field}`);
  row[column[locale]] = value;
}

if (existsSync(rootPath)) rmSync(rootPath, { recursive: true });
const imagesDir = join(rootPath, "images");
mkdirSync(imagesDir, { recursive: true });

let copied = 0;
for (const [locale, listing] of Object.entries(LISTINGS)) {
  SHOTS.forEach((shot, index) => {
    const order = String(index + 1).padStart(2, "0");
    const source = join(shotsDir, `${listing.appLanguage}-${order}-${shot}.png`);
    if (!existsSync(source)) {
      throw new Error(`missing screenshot: ${source}. Run npm run shots:windows first.`);
    }
    const name = `${locale}-${order}-${shot}.png`;
    copyFileSync(source, join(imagesDir, name));
    copied += 1;
    set(`DesktopScreenshot${index + 1}`, locale, `${pathPrefix}/${name}`);
    set(`DesktopScreenshotCaption${index + 1}`, locale, listing.captions[index]);
  });

  set("Description", locale, listing.description);
  set("ReleaseNotes", locale, listing.releaseNotes);
  set("Feature15", locale, listing.feature15);

  if (!listing.isNewLanguage) continue;
  // 新开的语言：原本整列都是空的，连这些不随版本变化的字段也要补上。
  set("ShortDescription", locale, listing.shortDescription);
  set("DevStudio", locale, "fi_niaR Studio");
  set("CopyrightTrademarkInformation", locale, "MIT License");
  listing.features.forEach((feature, index) => set(`Feature${index + 1}`, locale, feature));
  listing.searchTerms.forEach((term, index) => set(`SearchTerm${index + 1}`, locale, term));
}

const outCsv = join(rootPath, basename(sourceCsv));
writeFileSync(outCsv, serializeCsv(rows));

const added = Object.values(LISTINGS).filter((listing) => listing.isNewLanguage).length;
console.log(`wrote ${outCsv}`);
console.log(`copied ${copied} screenshots into ${imagesDir}`);
console.log(`languages: ${Object.keys(LISTINGS).length} (${Object.keys(LISTINGS).length - added} existing + ${added} new)`);
