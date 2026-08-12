/**
 * 下载页的镜像加速。GitHub 的 Release 资产在中国大陆常年慢到不可用，这里给出
 * 一个可选的反代前缀。
 *
 * 与另外两处用的是同一个反代，改这里要同步：
 *   - `scripts/mirror-manifest.mjs` 的 `MIRROR_PREFIX`（更新器的 latest-cn.json）
 *   - `src-tauri/src/lib.rs` 的 `MIRROR_UPDATER_ENDPOINT`（客户端内更新）
 *
 * 与更新器的关键差别：那条链路会用 minisign 校验安装包，改包会被当场拒绝；
 * 而手动下载没有任何校验。所以镜像默认关闭，且界面上必须写明这是第三方转发。
 */
export const DOWNLOAD_MIRROR_HOST = "gh-proxy.com";

const MIRROR_PREFIX = `https://${DOWNLOAD_MIRROR_HOST}/`;

/** 只有 GitHub 自己的下载域名值得代理，别的地址原样返回。 */
const MIRRORABLE_HOSTS = new Set([
  "github.com",
  "api.github.com",
  "objects.githubusercontent.com",
  "release-assets.githubusercontent.com",
]);

/** 给 GitHub 下载地址套上反代前缀；已经套过或不该套的原样返回。 */
export function mirroredDownloadUrl(url: string): string {
  if (!url || url.startsWith(MIRROR_PREFIX)) return url;
  let host: string;
  try {
    host = new URL(url).host;
  } catch {
    return url;
  }
  return MIRRORABLE_HOSTS.has(host) ? `${MIRROR_PREFIX}${url}` : url;
}
