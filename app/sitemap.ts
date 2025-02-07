import { locales } from "@/i18n-config";
import { siteConfig } from "@/config/site";

export default async function sitemap() {
  const routes = locales.map((locale) => ({
    url: `${siteConfig.baseUrl}/${locale}`,
    lastModified: new Date().toISOString(),
  }));

  return [
    {
      url: siteConfig.baseUrl,
      lastModified: new Date().toISOString(),
    },
    ...routes,
  ];
}
