import { OffWorkCountdown } from '@/components/off-work-countdown';
import { Metadata } from 'next';
import { locales } from '@/i18n-config';
import path from 'path';
import fs from 'fs/promises';

type Props = {
  params: { lang: string }
};

async function loadSeoData(lang: string) {
  try {
    const filePath = path.join(process.cwd(), 'public', 'locales', lang, 'seo.json');
    const fileContent = await fs.readFile(filePath, 'utf8');
    return JSON.parse(fileContent);
  } catch (error) {
    // 如果找不到指定语言的文件，返回英语版本
    const defaultPath = path.join(process.cwd(), 'public', 'locales', 'en', 'seo.json');
    const defaultContent = await fs.readFile(defaultPath, 'utf8');
    return JSON.parse(defaultContent);
  }
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const lang = params.lang;
  const seo = await loadSeoData(lang);
  
  const languageAlternates = locales.reduce((acc: Record<string, string>, l: string) => ({
    ...acc,
    [l]: `https://off.rainif.com/${l}`
  }), {});

  return {
    title: seo.title,
    description: seo.description,
    keywords: seo.keywords,
    alternates: {
      canonical: `https://off.rainif.com/${lang}`,
      languages: languageAlternates
    },
    openGraph: {
      title: seo.title,
      description: seo.description,
      url: `https://off.rainif.com/${lang}`,
      siteName: seo.siteName,
      locale: lang,
      type: 'website',
      images: [{ 
        url: 'https://github.com/ififi2017/Off-Work-Countdown/raw/main/readme_image/demo.jpg',
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
    }
  };
}

export async function generateStaticParams() {
  return locales.map((lang) => ({ lang }));
}

export default function Page({ params: { lang } }: Props) {
  return <OffWorkCountdown lang={lang} />;
} 