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
  // 同步完成初始化。默认的 initImmediate: true 会把内部的语言加载推迟到下一个
  // tick——那时下面的 changeLanguage 包装器已经装上，但 React 尚未渲染、
  // I18nProvider 还没注入服务端翻译，包装器就会误判资源缺失而多发一次请求。
  // 同步初始化后 i18n.language 在模块加载时即就位，各处的 changeLanguage
  // 守卫也能正确跳过。没有 backend 插件，本就无异步加载可等。
  initImmediate: false,
});

/**
 * 确保某个语言的资源已就位，但**不**切换当前语言。
 *
 * 桌面端的托盘与 macOS 应用菜单跟随系统语言，而界面跟随用户选择的语言，两者
 * 可以不同；这时需要在不影响界面的前提下另外拿到一份系统语言的文案，交给
 * `i18n.getFixedT(lng)` 使用。
 */
export async function ensureLanguageResources(lng: string): Promise<void> {
  if (i18n.hasResourceBundle(lng, "translation")) return;
  const resources = await loadLanguageResources(lng);
  i18n.addResourceBundle(lng, "translation", resources.translation, true, true);
  i18n.addResourceBundle(lng, "seo", resources.seo, true, true);
}

// 添加语言切换处理
const originalChangeLanguage = i18n.changeLanguage.bind(i18n);
i18n.changeLanguage = async (lng: string | undefined, callback?: Callback) => {
  if (!lng) return originalChangeLanguage(lng, callback);

  try {
    await ensureLanguageResources(lng);
    return originalChangeLanguage(lng, callback);
  } catch (error) {
    console.error(`Error changing language to ${lng}:`, error);
    return originalChangeLanguage(defaultLocale, callback);
  }
};

// 这里不再于模块加载时预取翻译。当前语言的资源由服务端读文件后经
// I18nProvider 的 resources prop 在渲染期同步注入（见 components/I18nProvider.tsx），
// 首屏即可用；再 fetch 一遍只是重复请求同一份数据。
// loadLanguageResources 仍保留给上面的 changeLanguage 包装器，用于切到
// 尚未注入过的语言时按需拉取。

export default i18n;
