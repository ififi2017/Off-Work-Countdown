#!/usr/bin/env node

/**
 * macOS 商店渠道的 App Group 标识符。
 *
 * iOS 继续用注册过的 `group.com.rainif.offworkcountdown.macappstore`。
 * Mac App Store 校验要求每项以 Team ID（或已写入描述文件的 `group`）开头，
 * 宿主又是 Tauri 签名、描述文件只有 `<TeamID>.*`，因此商店 / automatic
 * 构建必须写成 `<TeamID>.group.com.rainif.offworkcountdown.macappstore`。
 *
 * 取值必须与 src-tauri/build.rs 的 macos_app_group_identifier() 保持一致：
 * 那边决定宿主往哪个容器写快照，这边决定 entitlements 签进去什么。
 */

import { execFileSync } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

export const DEFAULT_IOS_STYLE_APP_GROUP =
  "group.com.rainif.offworkcountdown.macappstore";

export function resolveMacosAppGroupIdentifier({
  identifier = process.env.OWC_APP_GROUP_IDENTIFIER ?? DEFAULT_IOS_STYLE_APP_GROUP,
  teamId = process.env.OWC_APPLE_TEAM_ID ?? "",
  signingMode = process.env.OWC_WIDGET_SIGNING_MODE ?? "adhoc",
} = {}) {
  if (!identifier || /[^A-Za-z0-9.-]/.test(identifier)) {
    throw new Error(`Invalid OWC_APP_GROUP_IDENTIFIER: ${identifier}`);
  }

  let resolved = identifier;
  if (resolved.startsWith("group.") && teamId) {
    resolved = `${teamId}.${resolved}`;
  }

  if (signingMode === "automatic" || signingMode === "distribution") {
    if (!teamId) {
      throw new Error(
        `OWC_APPLE_TEAM_ID is required for OWC_WIDGET_SIGNING_MODE=${signingMode}`
      );
    }
    if (!resolved.startsWith(`${teamId}.`)) {
      throw new Error(
        `OWC_APP_GROUP_IDENTIFIER (${resolved}) must start with ${teamId}. ` +
          "Mac App Store rejects iOS-style group.* identifiers (409)."
      );
    }
  }

  return resolved;
}

export function parseAppGroups(text) {
  const groups = new Set();
  const xmlBlock = text.match(
    /<key>com\.apple\.security\.application-groups<\/key>\s*<array>([\s\S]*?)<\/array>/
  );
  if (xmlBlock) {
    for (const match of xmlBlock[1].matchAll(/<string>([^<]*)<\/string>/g)) {
      groups.add(match[1]);
    }
  }
  for (const match of text.matchAll(/\[String\]\s+(\S*group\S*)/g)) {
    groups.add(match[1]);
  }
  return [...groups];
}

export function profileAuthorizesAppGroup(group, allowedPatterns) {
  // 只拿「签进去的那一串」去对描述文件。不要把 group.foo 当成已被
  // TEAMID.* 授权——那会让未加前缀的签名在本地过关、上传被 409。
  return allowedPatterns.some((pattern) => {
    if (pattern === group) return true;
    if (pattern.endsWith("*")) {
      return group.startsWith(pattern.slice(0, -1));
    }
    return false;
  });
}

export function iosStyleAppGroupMessage(groups, { source, teamId = "" }) {
  const bad = groups.filter((group) => group.startsWith("group."));
  if (bad.length === 0) return null;
  const expected = teamId ? `${teamId}.${bad[0]}` : `<TeamID>.${bad[0]}`;
  return (
    `${source} carries iOS-style App Group(s) that Mac App Store rejects (409):\n` +
    `  signed:   ${bad.join(", ")}\n` +
    `  expected: ${expected}\n` +
    "  Rebuild with OWC_APPLE_TEAM_ID set; automatic/distribution builds prefix group.* automatically."
  );
}

export function assertNoIosStyleAppGroups(groups, options) {
  const message = iosStyleAppGroupMessage(groups, options);
  if (message) throw new Error(message);
}

export function pluginBundles(appBundle) {
  const dir = join(appBundle, "Contents/PlugIns");
  if (!existsSync(dir)) return [];
  return readdirSync(dir)
    .filter((name) => name.endsWith(".appex"))
    .map((name) => join(dir, name));
}

export function readSignedAppGroups(bundle) {
  const dump = execFileSync("codesign", ["-d", "--entitlements", "-", bundle], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  });
  return parseAppGroups(dump);
}

export function assertBundleHasMacosAppGroups(
  appPath,
  teamId = process.env.OWC_APPLE_TEAM_ID ?? ""
) {
  for (const bundle of [appPath, ...pluginBundles(appPath)]) {
    assertNoIosStyleAppGroups(readSignedAppGroups(bundle), {
      source: bundle,
      teamId,
    });
  }
}

function parseArgs(argv) {
  const args = { positional: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--resolve") args.resolve = true;
    else if (arg === "--check-bundle") args.checkBundle = argv[++i];
    else if (arg === "--identifier") args.identifier = argv[++i];
    else if (arg === "--team-id") args.teamId = argv[++i];
    else if (arg === "--signing-mode") args.signingMode = argv[++i];
    else args.positional.push(arg);
  }
  return args;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.checkBundle) {
    assertBundleHasMacosAppGroups(args.checkBundle, args.teamId);
    return;
  }
  if (args.resolve || args.positional.length === 0) {
    process.stdout.write(
      `${resolveMacosAppGroupIdentifier({
        identifier: args.identifier,
        teamId: args.teamId,
        signingMode: args.signingMode,
      })}\n`
    );
    return;
  }
  console.error(
    "Usage: macos-app-group-identifier.mjs --resolve [--identifier <id>] [--team-id <id>] [--signing-mode <mode>]\n" +
      "       macos-app-group-identifier.mjs --check-bundle <App.app> [--team-id <id>]"
  );
  process.exit(1);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    process.exit(1);
  }
}
