// next.config.mjs 不能直接 import TypeScript。这份列表必须与 i18n-config.ts
// 的 locales、lib/content-locales.ts 的 contentSlugs / resolveContentLocale
// 保持一致；lib/official-content-redirects.test.ts 会核对。

export const DEFAULT_OFFICIAL_SITE_URL = "https://doneat.app";

export const UI_LOCALES = [
  "en",
  "zh-CN",
  "zh-TW",
  "zh-HK",
  "ja",
  "ko",
  "fr",
  "de",
  "es",
  "it",
  "pt",
  "ru",
  "hi-IN",
  "mr-IN",
  "tr",
  "ar",
  "th",
  "id",
  "vi",
];

export const CONTENT_SLUGS = [
  "faq",
  "how-it-works",
  "about",
  "download",
  "privacy",
];

export function resolveOfficialContentLocale(lang) {
  return String(lang).toLowerCase().startsWith("zh") ? "zh-CN" : "en";
}

export function officialContentPath(lang, slug) {
  return `/${resolveOfficialContentLocale(lang)}/${slug}`;
}

export function buildOfficialContentRedirects({
  officialSiteUrl = DEFAULT_OFFICIAL_SITE_URL,
  locales = UI_LOCALES,
} = {}) {
  const origin = String(officialSiteUrl).replace(/\/$/, "");
  return locales.flatMap((lang) =>
    CONTENT_SLUGS.map((slug) => ({
      source: `/${lang}/${slug}`,
      destination: `${origin}${officialContentPath(lang, slug)}`,
      statusCode: 301,
    }))
  );
}
