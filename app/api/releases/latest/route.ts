import { NextResponse } from "next/server";
import { siteConfig } from "@/config/site";
import {
  parseLatestRelease,
  type GitHubRelease,
} from "@/lib/github-release";

export const revalidate = 300;
// 明确保持为运行时 Route Handler，避免构建阶段为探测静态响应而请求 GitHub。
export const dynamic = "force-dynamic";

const releaseApiUrl = `https://api.github.com/repos/${siteConfig.githubOwner}/${siteConfig.githubRepo}/releases/latest`;

export async function GET() {
  const headers: HeadersInit = {
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": `${siteConfig.githubOwner}-${siteConfig.githubRepo}-website`,
  };

  // Vercel 可选配置 GITHUB_TOKEN 来提高 GitHub API 限额。公开仓库在没有
  // token 时仍然可用，而 5 分钟 CDN 缓存足以避免每位访客都请求 GitHub。
  if (process.env.GITHUB_TOKEN) {
    headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  }

  try {
    const response = await fetch(releaseApiUrl, {
      headers,
      next: { revalidate },
    });

    if (!response.ok) {
      throw new Error(`GitHub release API returned ${response.status}`);
    }

    const release = (await response.json()) as GitHubRelease;
    const parsed = parseLatestRelease(release);

    // 只允许把官方仓库的下载地址返回给浏览器，避免上游异常数据变成开放跳转。
    const assetPrefix = `${siteConfig.releases}/download/`;
    for (const key of Object.keys(parsed.downloads) as Array<
      keyof typeof parsed.downloads
    >) {
      const download = parsed.downloads[key];
      if (download && !download.url.startsWith(assetPrefix)) {
        parsed.downloads[key] = null;
      }
    }

    return NextResponse.json(parsed, {
      headers: {
        "Cache-Control": "public, s-maxage=300, stale-while-revalidate=3600",
      },
    });
  } catch (error) {
    console.error("Unable to resolve the latest desktop release", error);
    return NextResponse.json(
      { error: "release_unavailable", releaseUrl: siteConfig.releases },
      {
        status: 503,
        headers: { "Cache-Control": "public, s-maxage=60" },
      }
    );
  }
}
