import type { Metadata } from "next";
import { siteConfig } from "@/config/site";

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
