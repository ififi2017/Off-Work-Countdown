import i18n from "i18next";
import { InitOptions } from 'i18next';
import { initReactI18next } from "react-i18next";
import LanguageDetector from "i18next-browser-languagedetector";
import Backend from "i18next-http-backend";

// 获取基础URL
const getBasePath = () => {
  if (typeof window !== 'undefined') {
    return window.location.origin;
  }
  return '';
};

// 语言代码映射
const languageMapping: { [key: string]: string } = {
  'zh': 'zh-CN',
  'zh-Hans': 'zh-CN',
  'zh-Hans-CN': 'zh-CN',
  'zh-Hans-SG': 'zh-CN',
  'zh-Hans-HK': 'zh-CN',
  'zh-Hans-MO': 'zh-CN',
  'zh-SG': 'zh-CN',
  'zh-Hant': 'zh-TW',
  'zh-Hant-TW': 'zh-TW',
  'zh-Hant-HK': 'zh-TW',
  'zh-Hant-MO': 'zh-TW',
  'zh-HK': 'zh-TW',
  'zh-MO': 'zh-TW'
};

const i18nConfig: InitOptions = {
  backend: {
    loadPath: `${getBasePath()}/locales/{{lng}}/{{ns}}.json`,
  },
  fallbackLng: "en",
  supportedLngs: ["en", "zh-CN", "zh-TW", "ja", "ko", "fr", "de", "es", "it", "pt", "ru"],
  ns: ["translation"],
  defaultNS: "translation",
  detection: {
    order: ["localStorage", "navigator"],
    caches: ["localStorage"],
    lookupLocalStorage: "i18nextLng",
  },
  interpolation: {
    escapeValue: false
  },
  load: 'currentOnly'
};

i18n
  .use(Backend)
  .use(LanguageDetector)
  .use(initReactI18next)
  .init(i18nConfig);

// 添加语言映射处理
i18n.services.languageDetector.addDetector({
  name: 'customLanguageDetector',
  lookup() {
    const detectedLng = localStorage.getItem('i18nextLng') || navigator.language;
    return languageMapping[detectedLng] || detectedLng;
  },
  cacheUserLanguage(lng: string) {
    localStorage.setItem('i18nextLng', languageMapping[lng] || lng);
  }
});

export default i18n;
