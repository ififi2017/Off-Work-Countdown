export const defaultLocale = 'en'

export const locales = [
  'en',
  'zh-CN',
  'zh-TW',
  'zh-HK',
  'tr',
  'ja',
  'ko',
  'fr',
  'de',
  'es',
  'it',
  'pt',
  'ru',
  'ar',
  'hi-IN',
  'mr-IN',
  'th',
  'id',
  'vi'
] as const

export type Locale = (typeof locales)[number]

// 语言代码映射
export const languageMapping: { [key: string]: string } = {
  'zh': 'zh-CN',
  'zh-Hans': 'zh-CN',
  'zh-Hans-CN': 'zh-CN',
  'zh-Hans-SG': 'zh-CN',
  'zh-Hans-HK': 'zh-CN',
  'zh-Hans-MO': 'zh-CN',
  'zh-SG': 'zh-CN',
  'zh-Hant': 'zh-TW',
  'zh-Hant-TW': 'zh-TW',
  'zh-Hant-HK': 'zh-HK',
  'zh-Hant-MO': 'zh-HK',
  'zh-HK': 'zh-HK',
  'zh-MO': 'zh-HK',
  'mr': 'mr-IN',
  'hi': 'hi-IN'
}

// 语言名称映射
export const languageNames: { [key: string]: string } = {
  'en': 'English',
  'zh-CN': '简体中文',
  'zh-TW': '繁體中文（台灣）',
  'zh-HK': '繁體中文（香港）',
  'ja': '日本語',
  'ko': '한국어',
  'fr': 'Français',
  'de': 'Deutsch',
  'es': 'Español',
  'it': 'Italiano',
  'pt': 'Português',
  'ru': 'Русский',
  'hi-IN': 'हिन्दी',
  'mr-IN': 'मराठी',
  'tr': 'Türkçe',
  'ar': 'اَلْعَرَبِيَّةُ',
  'th': 'ไทย',
  'id': 'Bahasa Indonesia',
  'vi': 'Tiếng Việt'
} 