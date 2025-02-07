export const defaultLocale = "en";

// 支持的语言列表
export const locales = [
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
] as const;

export type Locale = (typeof locales)[number];

// 语言代码映射
export const languageMapping: { [key: string]: string } = {
  zh: "zh-CN",
  "zh-Hans": "zh-CN",
  "zh-Hans-CN": "zh-CN",
  "zh-Hans-SG": "zh-CN",
  "zh-Hans-HK": "zh-CN",
  "zh-Hans-MO": "zh-CN",
  "zh-SG": "zh-CN",
  "zh-Hant": "zh-TW",
  "zh-Hant-TW": "zh-TW",
  "zh-Hant-HK": "zh-HK",
  "zh-Hant-MO": "zh-HK",
  "zh-HK": "zh-HK",
  "zh-MO": "zh-HK",
  mr: "mr-IN",
  hi: "hi-IN",
};

// 语言名称映射
export const languageNames: { [key: string]: string } = {
  ar: "العربية",
  de: "Deutsch",
  en: "English",
  es: "Español",
  fr: "Français",
  "hi-IN": "हिन्दी",
  id: "Bahasa Indonesia",
  it: "Italiano",
  ja: "日本語",
  ko: "한국어",
  "mr-IN": "मराठी",
  pt: "Português",
  ru: "Русский",
  th: "ไทย",
  tr: "Türkçe",
  vi: "Tiếng Việt",
  "zh-CN": "简体中文",
  "zh-HK": "繁體中文（香港）",
  "zh-TW": "繁體中文（台灣）"
};

// 获取基础语言代码
export function getBaseLanguage(lang: string): string {
  // 首先检查完整的语言代码是否在映射中
  if (languageMapping[lang]) {
    return languageMapping[lang];
  }

  // 然后检查基础语言代码是否在映射中
  const baseLang = lang.split("-")[0];
  if (languageMapping[baseLang]) {
    return languageMapping[baseLang];
  }

  // 如果语言代码包含区域（如 de-DE），返回基础语言代码（如 de）
  if (lang.includes("-") && locales.includes(baseLang as Locale)) {
    return baseLang;
  }

  // 返回原始语言代码
  return lang;
}
