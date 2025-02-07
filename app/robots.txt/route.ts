import { siteConfig } from "@/config/site";

export function GET() {
  const robotsTxt = `# *
User-agent: *
Allow: /

Sitemap: ${siteConfig.baseUrl}/sitemap.xml
Sitemap: ${siteConfig.baseUrl}/hreflang-sitemap.xml`;

  return new Response(robotsTxt, {
    headers: {
      "Content-Type": "text/plain",
      "Cache-Control": "public, max-age=3600",
    },
  });
}

export const dynamic = "force-dynamic";
