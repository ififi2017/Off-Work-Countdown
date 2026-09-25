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

/**
 * 按浏览器语言跳转的首页。middleware 把 `/` 307 到 `/{lang}`（保留查询串），
 * 这正是 Google 文档里 hreflang x-default 的典型用法：没有匹配语言的访客
 * 从这里进入，由服务器挑语言。
 */
export function webAppRootUrl(): string {
  return `${siteConfig.webAppUrl}/`;
}

/**
 * HTML 与 sitemap 共用的 hreflang 表。
 *
 * - 首页（无 path）：x-default 指向会按语言跳转的 `/`。此前指向 `/en`，
 *   结果 `/` 被当作一个独立的英文页收录，和 `/en` 分走了英文信号
 *   （见 plans/Web/001-seo-search-growth.md §7-2）。
 * - 其他页（预设页、工时计算器）：`/{path}` 没有对应的按语言跳转页，
 *   x-default 仍落在 `/en/{path}`。
 */
export function webAppAlternates(
  langs: readonly string[],
  path = ""
): Record<string, string> {
  return {
    ...Object.fromEntries(
      langs.map((lang) => [lang, webAppPageUrl(lang, path)])
    ),
    "x-default": path ? webAppPageUrl(defaultLocale, path) : webAppRootUrl(),
  };
}
