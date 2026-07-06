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
  if (
    pathSegments.length > 1 &&
    pathSegments[1] &&
    locales.includes(pathSegments[1] as (typeof locales)[number])
  ) {
    return pathSegments[1];
  }

  // 优先读取用户已选择的语言（localStorage > cookie）
  try {
    const storedLang =
      window.localStorage.getItem("i18nextLng") ||
      document.cookie
        .split("; ")
        .find((row) => row.startsWith("i18nextLng="))
        ?.split("=")[1];
    if (storedLang) {
      const baseLanguage = getBaseLanguage(storedLang);
      if (locales.includes(baseLanguage as any)) {
        return baseLanguage;
      }
    }
  } catch {
    // ignore storage access issues
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
      // 用构建 ID 作为版本号：每次部署 URL 变化一次，强制刷新翻译；
      // 同一部署内 URL 稳定，仍可被缓存/离线使用。配合 SW 的 NetworkFirst 策略。
      const buildId = process.env.NEXT_PUBLIC_BUILD_ID || "";
      const v = buildId ? `?v=${encodeURIComponent(buildId)}` : "";
      const [translation, seo] = await Promise.all([
        fetch(`${baseUrl}/locales/${lng}/translation.json${v}`).then((r) => {
          if (!r.ok) throw new Error(`translation ${r.status}`);
          return r.json();
        }),
        fetch(`${baseUrl}/locales/${lng}/seo.json${v}`).then((r) => {
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

// 初始加载语言资源（仅在浏览器中）。
// 服务端渲染/构建期不通过 HTTP 拉取翻译：那会去请求生产域名
// (off.rainif.com)，构建时可能返回 403，且毫无必要——页面文案在客户端
// 挂载后加载，SEO/metadata 走 lib/server/i18n.ts 的文件系统读取。
if (typeof window !== "undefined") {
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
}

export default i18n;
