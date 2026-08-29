// 长文（FAQ / how-it-works / about / download / privacy）已经迁到官网。
// 本模块只负责：把界面语言映射到官网的 en / zh-CN，以及预设页仍只发布中英两版。
// 与 translation.json / seo.json 同目录的 UI 仍是 19 种语言。
//
// 这个模块不含任何 Node 专属 API，客户端组件也能引入。

export const contentLocales = ["en", "zh-CN"] as const;

export type ContentLocale = (typeof contentLocales)[number];

export const defaultContentLocale: ContentLocale = "en";

/**
 * 把界面语言映射到官网长文语言：中文用户（含繁体）看中文，其余看英文。
 */
export function resolveContentLocale(lang: string): ContentLocale {
  return lang.toLowerCase().startsWith("zh") ? "zh-CN" : defaultContentLocale;
}

export const contentSlugs = [
  "faq",
  "how-it-works",
  "about",
  "download",
  "privacy",
] as const;

export type ContentSlug = (typeof contentSlugs)[number];
