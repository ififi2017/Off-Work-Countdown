import { ReactNode } from 'react';
import { locales } from '@/i18n-config';
import { Metadata } from 'next';
import path from 'path';
import fs from 'fs/promises';
import { siteConfig } from '@/config/site';
import { I18nProvider } from '@/components/I18nProvider';

async function getTranslations(lang: string, ns: string) {
  try {
    const filePath = path.join(process.cwd(), 'public', 'locales', lang, `${ns}.json`);
    const content = await fs.readFile(filePath, 'utf8');
    return JSON.parse(content);
  } catch (error) {
    console.error(`Failed to load translations for ${lang}/${ns}:`, error);
    // 如果找不到翻译文件，返回英文翻译
    const enFilePath = path.join(process.cwd(), 'public', 'locales', 'en', `${ns}.json`);
    const enContent = await fs.readFile(enFilePath, 'utf8');
    return JSON.parse(enContent);
  }
}

export async function generateMetadata({ params }: { params: { lang: string } }): Promise<Metadata> {
  const seo = await getTranslations(params.lang, 'seo');

  return {
    title: seo.title,
    description: seo.description,
    keywords: seo.keywords,
    applicationName: seo.siteName,
    appleWebApp: {
      capable: true,
      title: seo.title,
      statusBarStyle: 'default'
    },
    formatDetection: {
      telephone: false,
    },
    openGraph: {
      title: seo.title,
      description: seo.description,
      type: "website",
      locale: params.lang,
      url: `${siteConfig.baseUrl}/${params.lang}`,
      siteName: seo.siteName,
      images: [{ 
        url: "https://github.com/ififi2017/Off-Work-Countdown/raw/main/readme_image/demo.jpg",
        width: 1200,
        height: 630,
        alt: seo.imageAlt
      }]
    },
    twitter: {
      card: 'summary_large_image',
      title: seo.title,
      description: seo.description,
      images: ['https://github.com/ififi2017/Off-Work-Countdown/raw/main/readme_image/demo.jpg'],
    },
    alternates: {
      canonical: `${siteConfig.baseUrl}/${params.lang}`,
      languages: Object.fromEntries(
        locales.map(l => [
          l,
          `${siteConfig.baseUrl}/${l}`
        ])
      )
    },
  };
}

export async function generateStaticParams() {
  return locales.map((lang) => ({ lang }));
}

export default function Layout({
  children,
  params,
}: {
  children: ReactNode;
  params: { lang: string };
}) {
  return (
    <I18nProvider lang={params.lang}>
      {children}
    </I18nProvider>
  );
} 