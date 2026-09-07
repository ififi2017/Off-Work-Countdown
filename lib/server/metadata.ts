import type { Metadata } from "next";
import { siteConfig } from "@/config/site";
import { officialPageUrl } from "@/lib/site-urls";

export function localizedSocialMetadata({
  lang,
  path,
  title,
  description,
  type = "website",
  pageOrigin = siteConfig.webAppUrl,
}: {
  lang: string;
  path: string;
  title: string;
  description: string;
  type?: "website" | "article";
  pageOrigin?: string;
}): Pick<Metadata, "openGraph" | "twitter"> {
  const url = `${pageOrigin}/${lang}/${path}`;
  const image = `${siteConfig.webAppUrl}/${lang}/opengraph-image`;

  return {
    openGraph: {
      title,
      description,
      type,
      locale: lang,
      url,
      siteName: siteConfig.brandName,
      images: [{ url: image, width: 1200, height: 630, alt: title }],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: [image],
    },
  };
}

export function buildWebAppJsonLd({
  lang,
  description,
}: {
  lang: string;
  description: string;
}) {
  const pageUrl = `${siteConfig.webAppUrl}/${lang}`;
  const official = siteConfig.officialSiteUrl;
  const organizationId = `${official}/#organization`;
  const officialSite = {
    "@type": "WebSite",
    name: siteConfig.brandName,
    url: official,
  };

  return {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "Organization",
        "@id": organizationId,
        name: siteConfig.brandName,
        url: official,
        sameAs: [siteConfig.github],
      },
      {
        "@type": "WebSite",
        name: siteConfig.brandName,
        alternateName: "Off Work Countdown",
        url: pageUrl,
        inLanguage: lang,
        isPartOf: officialSite,
        publisher: { "@id": organizationId },
      },
      {
        "@type": "WebApplication",
        name: siteConfig.brandName,
        alternateName: "Off Work Countdown",
        description,
        url: pageUrl,
        inLanguage: lang,
        applicationCategory: "UtilitiesApplication",
        operatingSystem: "Web browser",
        browserRequirements: "Requires JavaScript",
        isAccessibleForFree: true,
        offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
        license: "https://opensource.org/licenses/MIT",
        codeRepository: siteConfig.github,
        publisher: { "@id": organizationId },
        isPartOf: officialSite,
        sameAs: [official],
        downloadUrl: officialPageUrl(lang, "download"),
      },
    ],
  };
}
