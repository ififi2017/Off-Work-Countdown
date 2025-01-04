import { MetadataRoute } from 'next';
import path from 'path';
import fs from 'fs/promises';
import { defaultLocale } from '@/i18n-config';

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

export default async function manifest(): Promise<MetadataRoute.Manifest> {
  // 从请求 URL 中获取语言代码
  const lang = typeof window !== 'undefined' 
    ? window.location.pathname.split('/')[1] 
    : defaultLocale;

  // 获取当前语言的翻译
  const seo = await getTranslations(lang, 'seo');

  return {
    name: seo.siteName,
    short_name: seo.siteName,
    description: seo.description,
    start_url: `/${lang}`,
    display: "standalone",
    background_color: "#F3F4F6",
    theme_color: "#F3F4F6",
    icons: [
      {
        src: "/icon-192x192.png",
        sizes: "192x192",
        type: "image/png"
      },
      {
        src: "/icon-512x512.png",
        sizes: "512x512",
        type: "image/png"
      }
    ]
  };
} 