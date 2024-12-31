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
  'zh-MO': 'zh-TW',
  'mr': 'mr-IN',
  'hi': 'hi-IN'
};

const i18nConfig: InitOptions = {
  backend: {
    loadPath: `${getBasePath()}/locales/{{lng}}/{{ns}}.json`,
  },
  fallbackLng: "en",
  supportedLngs: ["en", "zh-CN", "zh-TW", "ja", "ko", "fr", "de", "es", "it", "pt", "ru", "mr-IN", "hi-IN"],
  ns: ["translation"],
  defaultNS: "translation",
  detection: {
    order: ["customLanguageDetector", "localStorage", "navigator"],
    caches: ["localStorage"],
    lookupLocalStorage: "i18nextLng",
  },
  interpolation: {
    escapeValue: false
  },
  load: 'currentOnly'
};

// 自定义语言检测器
const customLanguageDetector = {
  name: 'customLanguageDetector',
  lookup() {
    // 检查是否在浏览器环境
    if (typeof window === 'undefined') {
      return 'en'; // 在服务器端返回默认语言
    }

    const detectedLng = localStorage.getItem('i18nextLng') || navigator.language;
    
    // 检查是否是繁体中文变体
    const isTraditionalChinese = detectedLng.startsWith('zh-Hant') || 
                                detectedLng === 'zh-HK' || 
                                detectedLng === 'zh-MO' ||
                                detectedLng.startsWith('zh-Hant-');
    
    if (isTraditionalChinese) {
      return 'zh-TW';
    }
    
    return languageMapping[detectedLng] || detectedLng;
  },
  cacheUserLanguage(lng: string) {
    if (typeof window !== 'undefined') {
      localStorage.setItem('i18nextLng', lng);
    }
  }
};

i18n
  .use(Backend)
  .use(LanguageDetector)
  .use(initReactI18next)
  .init(i18nConfig);

// 添加自定义语言检测器
i18n.services.languageDetector.addDetector(customLanguageDetector);

export default i18n;
