#!/usr/bin/env node

/**
 * 由 tauri-action 产出的 latest.json 派生一份 latest-cn.json：内容完全相同，
 * 只把每个平台的安装包地址加上反代前缀。
 *
 * 为什么需要单独一份清单：安装包的真实地址写在清单**内部**，光把清单换成
 * 镜像地址没有用——客户端拿到的仍然是 github.com 的直链。所以镜像通道必须
 * 有一份 URL 已经改写好的清单。
 *
 * 签名不用动：Tauri 的 minisign 签名覆盖的是压缩包的字节内容，与它从哪个
 * 地址下载无关。因此镜像下来的包依然会被客户端内置的公钥验证，反代无法
 * 替换成别的东西。
 */

/** 与 src-tauri/src/lib.rs 的 MIRROR_UPDATER_ENDPOINT 使用同一个反代。 */
export const MIRROR_PREFIX = "https://gh-proxy.com/";

/**
 * 只有这些主机上的地址才值得走反代；其余原样保留。
 *
 * `api.github.com` 必须在列：tauri-action 写进 latest.json 的其实是
 * `https://api.github.com/repos/<owner>/<repo>/releases/assets/<id>` 这种
 * 资产 API 地址，而不是 `github.com/.../releases/download/...`。漏掉它的话
 * 改写会变成一次静默的空操作——清单照常生成，却一个地址都没换。
 */
const MIRRORABLE_HOSTS = new Set([
  "api.github.com",
  "github.com",
  "objects.githubusercontent.com",
  "release-assets.githubusercontent.com",
]);

export function mirrorUrl(url, prefix = MIRROR_PREFIX) {
  if (typeof url !== "string" || url.length === 0) {
    throw new Error("Manifest entry has no download URL.");
  }
  if (url.startsWith(prefix)) return url;

  let host;
  try {
    host = new URL(url).host;
  } catch {
    throw new Error(`Manifest entry has a malformed URL: ${url}`);
  }
  return MIRRORABLE_HOSTS.has(host) ? `${prefix}${url}` : url;
}

export function buildMirrorManifest(manifest, prefix = MIRROR_PREFIX) {
  const platforms = manifest?.platforms;
  if (!platforms || Object.keys(platforms).length === 0) {
    // 静默产出一份空清单会让镜像通道永远报「没有可用更新」，
    // 那种失败远比在发版流水线里直接失败更难排查。
    throw new Error("latest.json has no platforms; refusing to build a mirror manifest.");
  }

  return {
    ...manifest,
    platforms: Object.fromEntries(
      Object.entries(platforms).map(([target, entry]) => [
        target,
        { ...entry, url: mirrorUrl(entry?.url, prefix) },
      ])
    ),
  };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const { readFileSync, writeFileSync } = await import("node:fs");
  const [input, output] = process.argv.slice(2);
  if (!input || !output) {
    console.error("Usage: node scripts/mirror-manifest.mjs <latest.json> <latest-cn.json>");
    process.exit(1);
  }
  const manifest = JSON.parse(readFileSync(input, "utf8"));
  const mirrored = buildMirrorManifest(manifest);
  writeFileSync(output, `${JSON.stringify(mirrored, null, 2)}\n`);
  const targets = Object.keys(mirrored.platforms).join(", ");
  console.log(`Wrote ${output} for ${targets}.`);
}
