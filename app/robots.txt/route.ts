import { siteConfig } from "@/config/site";

export function GET() {
  // 只声明一份 sitemap：hreflang 信息已合并进 app/sitemap.ts 的 alternates。
  const robotsTxt = `# *
User-agent: *
Allow: /

Sitemap: ${siteConfig.baseUrl}/sitemap.xml`;

  return new Response(robotsTxt, {
    headers: {
      "Content-Type": "text/plain",
      "Cache-Control": "public, max-age=3600",
    },
  });
}
