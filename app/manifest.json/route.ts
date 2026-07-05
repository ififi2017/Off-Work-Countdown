import { NextResponse } from "next/server";
import { defaultLocale, locales, Locale } from "@/i18n-config";
import { siteConfig } from "@/config/site";
import { getTranslations } from "@/lib/server/i18n";

export async function GET(request: Request) {
  // 从 URL 查询参数中获取语言代码
  const { searchParams } = new URL(request.url);
  let lang = searchParams.get("lang") || defaultLocale;

  // 验证语言代码
  if (!locales.includes(lang as Locale)) {
    lang = defaultLocale;
  }

  // 如果没有从查询参数获取到语言，尝试从 Referer 获取
  if (!searchParams.has("lang")) {
    const referer = request.headers.get("referer");
    if (referer) {
      try {
        const refererUrl = new URL(referer);
        const pathParts = refererUrl.pathname.split("/");
        if (pathParts.length > 1 && pathParts[1]) {
          const refererLang = pathParts[1];
          if (locales.includes(refererLang as Locale)) {
            lang = refererLang;
          }
        }
      } catch {
        // 畸形 Referer 头，忽略即可
      }
    }
  }

  //   console.log('Manifest requested with language:', lang);
  //   console.log('Request URL:', request.url);
  //   console.log('Referer:', request.headers.get('referer'));

  // 获取当前语言的翻译
  const seo = await getTranslations(lang, "seo");

  const manifest = {
    name: seo.siteName,
    short_name: seo.siteName,
    description: seo.description,
    id: `/${lang}`,
    start_url: `/${lang}`,
    scope: "/",
    display: "standalone",
    background_color: siteConfig.themeColor,
    theme_color: siteConfig.themeColor,
    orientation: "portrait",
    icons: [
      {
        src: "/icon-192x192.png",
        sizes: "192x192",
        type: "image/png",
        purpose: "any maskable",
      },
      {
        src: "/icon-512x512.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "any maskable",
      },
    ],
    related_applications: [
      {
        platform: "webapp",
        url: `${siteConfig.baseUrl}/manifest.json?lang=${lang}`,
      },
    ],
    shortcuts: [
      {
        name: seo.siteName,
        url: `/${lang}`,
        icons: [
          {
            src: "/icon-192x192.png",
            sizes: "192x192",
            type: "image/png",
          },
        ],
      },
    ],
  };

  return new NextResponse(JSON.stringify(manifest), {
    headers: {
      "content-type": "application/json",
      "Cache-Control": "public, max-age=3600",
    },
  });
}

export const dynamic = "force-dynamic";
