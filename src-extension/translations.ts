import type { Locale } from "@/i18n-config";
import copy from "./copy.json";

type Messages = Record<string, string>;

// Each language is its own local chunk, so opening the popup parses only the
// active one. The build filters each file down to translation-keys.json.
const translations: Record<Locale, () => Promise<{ default: object }>> = {
  en: () => import("../public/locales/en/translation.json"),
  "zh-CN": () => import("../public/locales/zh-CN/translation.json"),
  "zh-TW": () => import("../public/locales/zh-TW/translation.json"),
  "zh-HK": () => import("../public/locales/zh-HK/translation.json"),
  ja: () => import("../public/locales/ja/translation.json"),
  ko: () => import("../public/locales/ko/translation.json"),
  fr: () => import("../public/locales/fr/translation.json"),
  de: () => import("../public/locales/de/translation.json"),
  es: () => import("../public/locales/es/translation.json"),
  it: () => import("../public/locales/it/translation.json"),
  pt: () => import("../public/locales/pt/translation.json"),
  ru: () => import("../public/locales/ru/translation.json"),
  "hi-IN": () => import("../public/locales/hi-IN/translation.json"),
  "mr-IN": () => import("../public/locales/mr-IN/translation.json"),
  tr: () => import("../public/locales/tr/translation.json"),
  ar: () => import("../public/locales/ar/translation.json"),
  th: () => import("../public/locales/th/translation.json"),
  id: () => import("../public/locales/id/translation.json"),
  vi: () => import("../public/locales/vi/translation.json"),
};

export const translationLocales = Object.keys(translations) as Locale[];

export async function loadTranslation(lang: Locale): Promise<Messages> {
  const { default: messages } = await translations[lang]();
  return { ...messages, ...copy[lang] } as Messages;
}
