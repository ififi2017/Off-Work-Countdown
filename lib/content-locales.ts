// 长文（FAQ / how-it-works / about / download / privacy）已经迁到官网。
// 本模块负责：
// 1. 把界面语言映射到官网长文语言（只有 en / zh-CN）
// 2. 定义预设页支持的语言（所有 19 种 UI 语言）
// 与 translation.json / seo.json 同目录的 UI 仍是 19 种语言。
//
// 这个模块不含任何 Node 专属 API，客户端组件也能引入。

import { locales } from "@/i18n-config";

// 官网长文页面只有中英两版（FAQ / how-it-works / about / download / privacy）
export const longFormLocales = ["en", "zh-CN"] as const;

export type LongFormLocale = (typeof longFormLocales)[number];

export const defaultLongFormLocale: LongFormLocale = "en";

// 为保持向后兼容，保留 contentLocales 别名
export const contentLocales = longFormLocales;
export type ContentLocale = LongFormLocale;
export const defaultContentLocale = defaultLongFormLocale;

// 预设页（996、9-to-5、9-to-6、night-shift）支持所有 19 种 UI 语言
export const presetLocales = locales;

export type PresetLocale = (typeof presetLocales)[number];

export const defaultPresetLocale: PresetLocale = "en";

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
