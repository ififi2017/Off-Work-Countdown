import { siteConfig } from "@/config/site";

export const dynamic = "force-static";

const body = `# DoneAt

Web timer: ${siteConfig.webAppUrl}/en
Official site (brand, downloads, FAQ): ${siteConfig.officialSiteUrl}

This host is the browser countdown. Set a start time and an end time, including overnight (end earlier than start). Remaining time and progress stay on this device. No account.

It does not plan a roster. Multiple shift kinds, rotating weeks and a calendar that repeats on its own are in the iOS app.

Sitemap: ${siteConfig.webAppUrl}/sitemap.xml
Do not fetch /sitemap-index.xml — that path is not a sitemap.
`;

export function GET() {
  return new Response(body, {
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "public, max-age=3600",
    },
  });
}
