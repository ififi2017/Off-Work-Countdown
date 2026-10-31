import type { Metadata } from "next";
import { siteConfig } from "@/config/site";
import { localizedSocialMetadata } from "@/lib/server/metadata";
import { getPageAlternates, pageUrl, type ToolPage } from "./pages";

export function toolPageMetadata(page: ToolPage): Metadata {
  return {
    metadataBase: new URL(siteConfig.webAppUrl), title: page.title, description: page.description,
    keywords: null,
    alternates: { canonical: pageUrl(page), languages: getPageAlternates(page) },
    robots: { index: page.status === "published", follow: page.status === "published", googleBot: { index: page.status === "published", follow: page.status === "published" } },
    ...localizedSocialMetadata({ lang: page.lang, path: page.path.slice(`/${page.lang}/`.length), title: page.title, description: page.description }),
  };
}
export function toolPageJsonLd(page: ToolPage) {
  const breadcrumb = { "@type": "BreadcrumbList", itemListElement: [
    { "@type": "ListItem", position: 1, name: "DoneAt", item: `${siteConfig.webAppUrl}/${page.lang}` },
    ...(page.kind === "salary" ? [{ "@type": "ListItem", position: 2, name: page.lang === "zh-CN" ? "工具库" : "Tools", item: `${siteConfig.webAppUrl}/${page.lang}/tools` }] : []),
    { "@type": "ListItem", position: page.kind === "salary" ? 3 : 2, name: page.title, item: pageUrl(page) },
  ] };
  return { "@context": "https://schema.org", "@graph": [breadcrumb, ...(page.kind === "salary" ? [{
    "@type": "WebApplication", name: page.title, url: pageUrl(page), description: page.description,
    inLanguage: page.lang, applicationCategory: "UtilitiesApplication", operatingSystem: "Any",
    isAccessibleForFree: true, offers: { "@type": "Offer", price: "0", priceCurrency: page.market === "cn" ? "CNY" : "USD" },
    publisher: { "@id": `${siteConfig.officialSiteUrl}/#organization` },
  }] : [])] };
}
