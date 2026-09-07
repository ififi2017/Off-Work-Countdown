import { siteConfig } from "@/config/site";
import { defaultLocale } from "@/i18n-config";
import {
  contentLocales,
  contentSlugs,
  defaultContentLocale,
  resolveContentLocale,
  type ContentSlug,
} from "@/lib/content-locales";

export function isContentSlug(slug: string): slug is ContentSlug {
  return (contentSlugs as readonly string[]).includes(slug);
}

export function officialHomeUrl(lang: string): string {
  // Hall pages exist for every UI locale (`/ja`, `/zh-TW`, …).
  return `${siteConfig.officialSiteUrl}/${lang}`;
}

export function officialPageUrl(lang: string, slug: ContentSlug): string {
  // Support pages are en / zh-CN only.
  return `${siteConfig.officialSiteUrl}/${resolveContentLocale(lang)}/${slug}`;
}

export function officialContentAlternates(
  slug: ContentSlug
): Record<string, string> {
  return {
    ...Object.fromEntries(
      contentLocales.map((lang) => [lang, officialPageUrl(lang, slug)])
    ),
    "x-default": officialPageUrl(defaultContentLocale, slug),
  };
}

export function webAppPageUrl(lang: string, path = ""): string {
  const suffix = path ? `/${path}` : "";
  return `${siteConfig.webAppUrl}/${lang}${suffix}`;
}

/** HTML 与 sitemap 共用的 hreflang 表。x-default 必须落在 /en，不能指向会 307 的裸域。 */
export function webAppAlternates(
  langs: readonly string[],
  path = ""
): Record<string, string> {
  return {
    ...Object.fromEntries(
      langs.map((lang) => [lang, webAppPageUrl(lang, path)])
    ),
    "x-default": webAppPageUrl(defaultLocale, path),
  };
}
