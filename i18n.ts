'use client';

import i18n from "i18next";
import { initReactI18next } from "react-i18next";
import { defaultLocale } from './i18n-config';
import { Callback } from 'i18next';

interface Resources {
  translation: Record<string, string>;
  seo: Record<string, string>;
}

// 资源加载状态跟踪
const loadingResources: { [key: string]: Promise<Resources> | null } = {};

// 加载指定语言的资源
async function loadLanguageResources(lng: string): Promise<Resources> {
  // 如果已经在加载中，返回现有的 Promise
  if (loadingResources[lng]) {
    return loadingResources[lng]!;
  }

  // 创建新的加载 Promise
  const loadingPromise = (async () => {
    try {
      const [translation, seo] = await Promise.all([
        fetch(`/locales/${lng}/translation.json`).then(r => r.json()),
        fetch(`/locales/${lng}/seo.json`).then(r => r.json())
      ]);
      
      return { translation, seo };
    } catch (e) {
      console.error(`Failed to load resources for ${lng}:`, e);
      return { translation: {}, seo: {} };
    } finally {
      // 加载完成后清除状态
      loadingResources[lng] = null;
    }
  })();

  // 保存加载状态
  loadingResources[lng] = loadingPromise;
  return loadingPromise;
}

// 初始化 i18n
i18n
  .use(initReactI18next)
  .init({
    lng: defaultLocale,
    fallbackLng: defaultLocale,
    ns: ["translation", "seo"],
    defaultNS: "translation",
    interpolation: {
      escapeValue: false
    },
    react: {
      useSuspense: false
    }
  });

// 添加语言切换处理
const originalChangeLanguage = i18n.changeLanguage.bind(i18n);
i18n.changeLanguage = async (lng: string | undefined, callback?: Callback) => {
  if (!lng) return originalChangeLanguage(lng, callback);

  // 检查是否已加载该语言资源
  if (!i18n.hasResourceBundle(lng, 'translation')) {
    const resources = await loadLanguageResources(lng);
    i18n.addResourceBundle(lng, 'translation', resources.translation);
    i18n.addResourceBundle(lng, 'seo', resources.seo);
  }

  return originalChangeLanguage(lng, callback);
};

// 初始加载默认语言资源
loadLanguageResources(defaultLocale).then(resources => {
  i18n.addResourceBundle(defaultLocale, 'translation', resources.translation);
  i18n.addResourceBundle(defaultLocale, 'seo', resources.seo);
});

export default i18n;
