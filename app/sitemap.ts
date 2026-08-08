import type { MetadataRoute } from "next";
import { locales } from "@/i18n-config";
import { siteConfig } from "@/config/site";
import { getContentLocales } from "@/lib/server/content";

// 单次构建内共用一个时间戳。/sitemap.xml 是静态预渲染的，这个值在构建时即被
// 固化，并非每次抓取都变新；但每次部署仍会刷新全部条目的 lastModified——内容
// 未变时这是噪声。等内容页有独立更新节奏后，再改成按页维护。
const buildTime = new Date().toISOString();

// 内容页路径。与 app/[lang]/ 下的目录名保持一致。
const contentPaths = ["faq", "how-it-works"] as const;

// 所有语言互为 alternate 并指向 x-default。Next.js 会据此在每条 <url> 下生成
// xhtml:link，取代此前手写的 hreflang-sitemap.xml —— 两份维护同一份信息很容易
// 不同步。
const appAlternates: Record<string, string> = {
  ...Object.fromEntries(locales.map((l) => [l, `${siteConfig.baseUrl}/${l}`])),
  "x-default": siteConfig.baseUrl,
};

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  // 内容页只收录文案已就绪的语言，与路由的 generateStaticParams 同源，
  // 避免 sitemap 里出现会 404 的 URL。
  const contentLocales = await getContentLocales();

  const contentEntries = contentPaths.flatMap((slug) => {
    const alternates = Object.fromEntries(
      contentLocales.map((l) => [l, `${siteConfig.baseUrl}/${l}/${slug}`])
    );
    return contentLocales.map((lang) => ({
      url: `${siteConfig.baseUrl}/${lang}/${slug}`,
      lastModified: buildTime,
      alternates: { languages: alternates },
    }));
  });

  return [
    {
      url: siteConfig.baseUrl,
      lastModified: buildTime,
      alternates: { languages: appAlternates },
    },
    ...locales.map((lang) => ({
      url: `${siteConfig.baseUrl}/${lang}`,
      lastModified: buildTime,
      alternates: { languages: appAlternates },
    })),
    ...contentEntries,
  ];
}
