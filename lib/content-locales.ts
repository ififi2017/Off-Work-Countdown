// 长内容页（FAQ / how-it-works / about / download）只做中英两种语言——这是刻意的取舍，不是尚未译完：
// 长文案的翻译质量与维护成本远高于 UI 字符串，铺到 19 种语言反而会产出大量
// 无人校对的稿子。应用界面本身仍是 19 种语言。
//
// 这个模块不含任何 Node 专属 API，客户端组件也能引入。

export const contentLocales = ["en", "zh-CN"] as const;

export type ContentLocale = (typeof contentLocales)[number];

export const defaultContentLocale: ContentLocale = "en";

/**
 * 把界面语言映射到内容页语言：中文用户（含繁体）看中文，其余看英文。
 * 用于在应用内生成指向内容页的链接，避免先跳转再重定向。
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
