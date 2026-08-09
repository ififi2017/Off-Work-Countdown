export interface GitHubReleaseAsset {
  name: string;
  browser_download_url: string;
  size: number;
}

export interface GitHubRelease {
  tag_name: string;
  html_url: string;
  published_at: string | null;
  assets: GitHubReleaseAsset[];
}

export interface DownloadAsset {
  name: string;
  url: string;
  size: number;
}

export interface LatestReleaseDownloads {
  tagName: string;
  version: string;
  releaseUrl: string;
  publishedAt: string | null;
  downloads: {
    windowsX64: DownloadAsset | null;
    windowsArm64: DownloadAsset | null;
    macosAppleSilicon: DownloadAsset | null;
    macosIntel: DownloadAsset | null;
    linuxX64: DownloadAsset | null;
  };
}

function toDownloadAsset(asset: GitHubReleaseAsset | undefined): DownloadAsset | null {
  if (!asset) return null;
  return {
    name: asset.name,
    url: asset.browser_download_url,
    size: asset.size,
  };
}

function firstMatch(
  assets: GitHubReleaseAsset[],
  patterns: RegExp[]
): GitHubReleaseAsset | undefined {
  for (const pattern of patterns) {
    const match = assets.find((asset) => pattern.test(asset.name));
    if (match) return match;
  }
}

/**
 * Tauri 会把版本号写进安装包文件名，因此网页不能拼一个固定 URL。
 * 这里按平台和架构识别最新 Release 的资产，并优先选择用户最熟悉的安装格式。
 */
export function parseLatestRelease(
  release: GitHubRelease
): LatestReleaseDownloads {
  const assets = release.assets.filter(
    (asset) => !/\.(sig|json|sha256|txt)$/i.test(asset.name)
  );

  return {
    tagName: release.tag_name,
    version: release.tag_name.replace(/^(?:desktop-)?v/i, ""),
    releaseUrl: release.html_url,
    publishedAt: release.published_at,
    downloads: {
      windowsX64: toDownloadAsset(
        firstMatch(assets, [
          /(?:x64|x86_64)[^/]*setup\.exe$/i,
          /(?:x64|x86_64)[^/]*\.msi$/i,
          /(?:x64|x86_64)[^/]*\.exe$/i,
        ])
      ),
      windowsArm64: toDownloadAsset(
        firstMatch(assets, [
          /(?:arm64|aarch64)[^/]*setup\.exe$/i,
          /(?:arm64|aarch64)[^/]*\.msi$/i,
          /(?:arm64|aarch64)[^/]*\.exe$/i,
        ])
      ),
      macosAppleSilicon: toDownloadAsset(
        firstMatch(assets, [/(?:aarch64|arm64)[^/]*\.dmg$/i])
      ),
      macosIntel: toDownloadAsset(
        firstMatch(assets, [/(?:x64|x86_64)[^/]*\.dmg$/i])
      ),
      linuxX64: toDownloadAsset(
        firstMatch(assets, [
          /(?:amd64|x64|x86_64)[^/]*\.appimage$/i,
          /(?:amd64|x64|x86_64)[^/]*\.deb$/i,
        ])
      ),
    },
  };
}
