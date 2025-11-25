"use client";

import i18n from "i18next";
import { initReactI18next } from "react-i18next";
import { defaultLocale, getBaseLanguage, locales } from "./i18n-config";
import { Callback } from "i18next";

interface Resources {
  translation: Record<string, string>;
  seo: Record<string, string>;
}

// 资源加载状态跟踪
const loadingResources: { [key: string]: Promise<Resources> | null } = {};

// 获取初始语言
function getInitialLanguage(): string {
  if (typeof window === "undefined") return defaultLocale;

  // 从 URL 路径中获取语言
  const pathSegments = window.location.pathname.split("/");
  if (pathSegments.length > 1 && pathSegments[1]) {
    return pathSegments[1];
  }

  // 从浏览器语言设置中获取语言
  const browserLang = navigator.language || (navigator as any).userLanguage;
  if (browserLang) {
    const baseLanguage = getBaseLanguage(browserLang);
    if (locales.includes(baseLanguage as any)) {
      return baseLanguage;
    }
  }

  return defaultLocale;
}

// 获取基础 URL
function getBaseUrl() {
  if (typeof window !== "undefined") {
    return "";
  }
  if (process.env.NEXT_PUBLIC_BASE_URL) return process.env.NEXT_PUBLIC_BASE_URL;
  if (process.env.VERCEL_URL) return `https://${process.env.VERCEL_URL}`;
  return "http://localhost:3000";
}

// 加载指定语言的资源
async function loadLanguageResources(lng: string): Promise<Resources> {
  // 如果已经在加载中，返回现有的 Promise
  if (loadingResources[lng]) {
    return loadingResources[lng]!;
  }

  const baseUrl = getBaseUrl();

  // 创建新的加载 Promise
  const loadingPromise = (async () => {
    try {
      const [translation, seo] = await Promise.all([
        fetch(`${baseUrl}/locales/${lng}/translation.json`).then((r) => {
          if (!r.ok) throw new Error(`translation ${r.status}`);
          return r.json();
        }),
        fetch(`${baseUrl}/locales/${lng}/seo.json`).then((r) => {
          if (!r.ok) throw new Error(`seo ${r.status}`);
          return r.json();
        }),
      ]);

      return { translation, seo };
    } catch (e) {
      console.error(`Failed to load resources for ${lng}:`, e);
      // 如果加载失败且不是默认语言，尝试加载默认语言
      if (lng !== defaultLocale) {
        console.warn(`Falling back to default locale (${defaultLocale})`);
        return loadLanguageResources(defaultLocale);
      }
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
const initialLanguage = getInitialLanguage();

i18n.use(initReactI18next).init({
  lng: initialLanguage,
  fallbackLng: defaultLocale,
  ns: ["translation", "seo"],
  defaultNS: "translation",
  interpolation: {
    escapeValue: false,
  },
  react: {
    useSuspense: false,
  },
  load: "currentOnly",
  detection: {
    order: ["path", "querystring", "cookie", "localStorage", "navigator"],
    lookupQuerystring: "lng",
    lookupCookie: "i18nextLng",
    lookupLocalStorage: "i18nextLng",
    caches: ["localStorage", "cookie"],
  },
});

// 添加语言切换处理
const originalChangeLanguage = i18n.changeLanguage.bind(i18n);
i18n.changeLanguage = async (lng: string | undefined, callback?: Callback) => {
  if (!lng) return originalChangeLanguage(lng, callback);

  try {
    // 检查是否已加载该语言资源
    if (!i18n.hasResourceBundle(lng, "translation")) {
      const resources = await loadLanguageResources(lng);
      i18n.addResourceBundle(
        lng,
        "translation",
        resources.translation,
        true,
        true
      );
      i18n.addResourceBundle(lng, "seo", resources.seo, true, true);
    }

    return originalChangeLanguage(lng, callback);
  } catch (error) {
    console.error(`Error changing language to ${lng}:`, error);
    return originalChangeLanguage(defaultLocale, callback);
  }
};

// 初始加载语言资源
loadLanguageResources(initialLanguage).then((resources) => {
  i18n.addResourceBundle(
    initialLanguage,
    "translation",
    resources.translation,
    true,
    true
  );
  i18n.addResourceBundle(initialLanguage, "seo", resources.seo, true, true);
});

export default i18n;
