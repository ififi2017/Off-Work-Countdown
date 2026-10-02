#!/usr/bin/env node

/**
 * 为 Play 上传生成「此版本中的新功能」。
 *
 * 只收 Android 相关的已合并 PR：标题 scope 含 android，或改动落在
 * src-mobile/android/。只取用户看得见的 feat / fix / perf，ci、docs、chore 等
 * 不写进去。标题本身就是 Conventional Commits，去掉 `type(scope): ` 前缀和
 * 任务编号后即可当成一行说明。
 *
 *   node scripts/android-release-notes.mjs <base-ref> [head-ref] [out-dir]
 *
 * 写出 <out-dir>/whatsnew-en-US，供 r0adkll/upload-google-play 的
 * whatsNewDirectory 读取。PR 标题只有英文，所以只出 en-US。
 */

import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

/** Play Console 对每种语言的版本说明限 500 个字符。 */
export const PLAY_NOTES_LIMIT = 500;

const USER_FACING = new Set(["feat", "fix", "perf"]);
// 这些平台的 PR 常顺带重新生成 Android 文案资源，不能光凭改到的文件就算进来。
const OTHER_PLATFORMS = new Set(["ios", "desktop", "web", "extension", "msstore", "macos", "windows", "watch"]);
const TITLE = /^(\w+)(?:\(([^)]*)\))?!?:\s*(.+)$/;

/**
 * 从一条 first-parent 提交里取出 PR 标题。
 * 合并提交的标题在正文第一行；squash 合并的标题就是 subject，末尾带 (#N)。
 */
export function prTitle(subject, body) {
  if (/^Merge pull request #\d+/.test(subject)) {
    return body.split("\n").map((line) => line.trim()).find(Boolean) ?? null;
  }
  const squash = subject.match(/^(.+?)\s+\(#\d+\)$/);
  return squash ? squash[1] : null;
}

/**
 * 判断一个 PR 是否该进 Android 版本说明，是的话返回去掉前缀后的一行文案。
 */
export function noteLine(title, files = []) {
  const match = title?.match(TITLE);
  if (!match) return null;
  const [, type, scope = "", text] = match;
  if (!USER_FACING.has(type)) return null;
  const scopes = scope.split(/[,/]/).map((part) => part.trim()).filter(Boolean);
  const isAndroid = scopes.includes("android") || (
    !scopes.some((part) => OTHER_PLATFORMS.has(part)) &&
    files.some((file) => file.startsWith("src-mobile/android/"))
  );
  if (!isAndroid) return null;
  // 「(T19c)」之类是内部任务编号，用户看不懂。
  const clean = text.replace(/\s*\(T\d+[a-z]?\)\s*$/i, "").trim();
  return clean ? clean[0].toUpperCase() + clean.slice(1) : null;
}

/** 拼成 Play 的说明文字；超出 500 字的条目整条丢掉，不截半句。 */
export function formatNotes(lines, limit = PLAY_NOTES_LIMIT) {
  const unique = [...new Set(lines)];
  if (unique.length === 0) return "Bug fixes and improvements.";
  let text = "";
  for (const line of unique) {
    const next = text ? `${text}\n• ${line}` : `• ${line}`;
    if (next.length > limit) break;
    text = next;
  }
  return text;
}

function git(...args) {
  return execFileSync("git", args, { encoding: "utf8" });
}

export function collectLines(base, head = "HEAD") {
  const log = git("log", "--first-parent", "--reverse", "--format=%H%x1f%s%x1f%b%x1e", `${base}..${head}`);
  const lines = [];
  for (const record of log.split("\x1e")) {
    const [sha, subject, body = ""] = record.trim().split("\x1f");
    if (!sha) continue;
    const title = prTitle(subject, body);
    if (!title) continue;
    const files = git("diff", "--name-only", `${sha}^1`, sha).split("\n").filter(Boolean);
    const line = noteLine(title, files);
    if (line) lines.push(line);
  }
  return lines;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const [base, head = "HEAD", outDir = "whatsnew"] = process.argv.slice(2);
  if (!base) {
    console.error("Usage: android-release-notes.mjs <base-ref> [head-ref] [out-dir]");
    process.exit(1);
  }
  const notes = formatNotes(collectLines(base, head));
  mkdirSync(outDir, { recursive: true });
  writeFileSync(join(outDir, "whatsnew-en-US"), notes);
  console.log(notes);
}
