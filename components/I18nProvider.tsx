"use client";

import { ReactNode, useEffect } from "react";
import { I18nextProvider, initReactI18next } from "react-i18next";
import { createInstance, type i18n as I18nInstance } from "i18next";
import clientI18n from "@/i18n";
import { defaultLocale } from "@/i18n-config";

// 用 type 而非 interface：i18next 的 Resource 依赖索引签名，
// TypeScript 只为 type alias 推导隐式索引签名，interface 不会。
export type I18nBundles = {
  translation: Record<string, string>;
  seo: Record<string, string>;
};

interface I18nProviderProps {
  children: ReactNode;
  lang: string;
  /**
   * 服务端从文件系统读出的翻译（见 lib/server/i18n.ts）。注入后首屏——SSR 与
   * 静态导出都算——才能渲染真实文案而不是 i18n key。这是页面能被爬虫收录的
   * 前提：客户端的 i18n 单例是通过 fetch 异步加载翻译的，服务端拿不到。
   */
  resources: I18nBundles;
}

const baseOptions = {
  fallbackLng: defaultLocale,
  ns: ["translation", "seo"],
  defaultNS: "translation",
  interpolation: { escapeValue: false },
  react: { useSuspense: false },
  load: "currentOnly" as const,
};

// 服务端：每次渲染新建实例。i18n 单例在 Node 进程内跨请求共享，并发请求若
// 共用同一个实例会互相改写 language，导致语言串台。
function createServerInstance(
  lang: string,
  resources: I18nBundles
): I18nInstance {
  const instance = createInstance();
  instance.use(initReactI18next).init({
    ...baseOptions,
    lng: lang,
    resources: { [lang]: resources },
  });
  return instance;
}

// 客户端：复用单例，但必须在渲染期同步灌入资源（而非放进 effect），否则首帧
// 文案与 SSR 输出不一致，会触发 hydration 不匹配和一次文字闪烁。
function seedClientInstance(lang: string, resources: I18nBundles) {
  if (!clientI18n.hasResourceBundle(lang, "translation")) {
    clientI18n.addResourceBundle(
      lang,
      "translation",
      resources.translation,
      true,
      true
    );
  }
  if (!clientI18n.hasResourceBundle(lang, "seo")) {
    clientI18n.addResourceBundle(lang, "seo", resources.seo, true, true);
  }
}

export function I18nProvider({ children, lang, resources }: I18nProviderProps) {
  let instance: I18nInstance;

  if (typeof window === "undefined") {
    instance = createServerInstance(lang, resources);
  } else {
    seedClientInstance(lang, resources);
    instance = clientI18n;
  }

  // 客户端软导航切换语言时的兜底：首次硬加载时 i18n.ts 已按 URL 路径初始化
  // 了正确的语言，这里只处理路由跳转后的同步。
  useEffect(() => {
    if (clientI18n.language !== lang) {
      clientI18n.changeLanguage(lang);
    }
  }, [lang]);

  return <I18nextProvider i18n={instance}>{children}</I18nextProvider>;
}
