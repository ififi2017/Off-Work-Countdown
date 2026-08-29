import type { MetadataRoute } from "next";
import { locales } from "@/i18n-config";
import { siteConfig } from "@/config/site";
import {
  contentLocales,
  defaultContentLocale,
} from "@/lib/content-locales";
import { presetSlugs } from "@/lib/presets";

// Web 构建按 Next.js metadata 约定静态生成 sitemap。桌面构建不把普通
// `.ts` 识别为路由，因此该文件不会进入 Tauri 静态导出。
export const dynamic = "force-static";

// 所有语言互为 alternate 并指向 x-default。Next.js 会据此在每条 <url> 下生成
// xhtml:link，取代此前手写的 hreflang-sitemap.xml —— 两份维护同一份信息很容易
// 不同步。
const appAlternates: Record<string, string> = {
  ...Object.fromEntries(
    locales.map((l) => [l, `${siteConfig.webAppUrl}/${l}`])
  ),
  "x-default": siteConfig.webAppUrl,
};

// 预设页仍在 Web App。五页长文已 301 到官网，不再出现在本域 sitemap。
const presetEntries = presetSlugs.flatMap((slug) => {
  const alternates = {
    ...Object.fromEntries(
      contentLocales.map((l) => [l, `${siteConfig.webAppUrl}/${l}/${slug}`])
    ),
    "x-default": `${siteConfig.webAppUrl}/${defaultContentLocale}/${slug}`,
  };
  return contentLocales.map((lang) => ({
    url: `${siteConfig.webAppUrl}/${lang}/${slug}`,
    alternates: { languages: alternates },
  }));
});

export default function sitemap(): MetadataRoute.Sitemap {
  return [
    ...locales.map((lang) => ({
      url: `${siteConfig.webAppUrl}/${lang}`,
      alternates: { languages: appAlternates },
    })),
    ...presetEntries,
  ];
}
