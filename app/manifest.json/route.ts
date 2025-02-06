import { NextResponse } from 'next/server';
import { defaultLocale } from '@/i18n-config';
import path from 'path';
import fs from 'fs/promises';
import { siteConfig } from '@/config/site';

async function getTranslations(lang: string, ns: string) {
  try {
    const filePath = path.join(process.cwd(), 'public', 'locales', lang, `${ns}.json`);
    const content = await fs.readFile(filePath, 'utf8');
    return JSON.parse(content);
  } catch (error) {
    console.error(`Failed to load translations for ${lang}/${ns}:`, error);
    const enFilePath = path.join(process.cwd(), 'public', 'locales', 'en', `${ns}.json`);
    const enContent = await fs.readFile(enFilePath, 'utf8');
    return JSON.parse(enContent);
  }
}

export async function GET(request: Request) {
  // 从 URL 查询参数中获取语言代码
  const { searchParams } = new URL(request.url);
  let lang = searchParams.get('lang') || defaultLocale;

  // 如果没有从查询参数获取到语言，尝试从 Referer 获取
  if (!searchParams.has('lang')) {
    const referer = request.headers.get('referer');
    if (referer) {
      const refererUrl = new URL(referer);
      const pathParts = refererUrl.pathname.split('/');
      if (pathParts.length > 1 && pathParts[1]) {
        lang = pathParts[1];
      }
    }
  }

  console.log('Manifest requested with language:', lang);
  console.log('Request URL:', request.url);
  console.log('Referer:', request.headers.get('referer'));

  // 获取当前语言的翻译
  const seo = await getTranslations(lang, 'seo');

  const manifest = {
    name: seo.siteName,
    short_name: seo.siteName,
    description: seo.description,
    id: `/${lang}`,
    start_url: `/${lang}`,
    scope: '/',
    display: "standalone",
    background_color: siteConfig.themeColor,
    theme_color: siteConfig.themeColor,
    orientation: "portrait",
    icons: [
      {
        src: "/icon-192x192.png",
        sizes: "192x192",
        type: "image/png",
        purpose: "any maskable"
      },
      {
        src: "/icon-512x512.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "any maskable"
      }
    ],
    related_applications: [
      {
        platform: "webapp",
        url: `${siteConfig.baseUrl}/manifest.json?lang=${lang}`
      }
    ],
    shortcuts: [
      {
        name: seo.siteName,
        url: `/${lang}`,
        icons: [
          {
            src: "/icon-192x192.png",
            sizes: "192x192",
            type: "image/png"
          }
        ]
      }
    ]
  };

  return new NextResponse(JSON.stringify(manifest), {
    headers: {
      'content-type': 'application/json',
      'Cache-Control': 'public, max-age=3600',
    },
  });
}

export const dynamic = 'force-dynamic'; 