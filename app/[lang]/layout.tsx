import { ReactNode } from 'react';
import { locales } from '@/i18n-config';
import { I18nProvider } from '@/components/I18nProvider';
import { Metadata, Viewport } from 'next';
import { siteConfig } from '@/config/site';
import { getTranslations } from '@/lib/server/i18n';

export const viewport: Viewport = {
  themeColor: siteConfig.themeColor,
};

export async function generateMetadata({ params }: { params: { lang: string } }): Promise<Metadata> {
  const seo = await getTranslations(params.lang, 'seo');

  return {
    metadataBase: new URL(siteConfig.baseUrl),
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
    robots: {
      index: true,
      follow: true,
      googleBot: {
        index: true,
        follow: true,
        'max-video-preview': -1,
        'max-image-preview': 'large',
        'max-snippet': -1,
      },
    },
    verification: {
      other: {
        'baidu-site-verification': 'codeva-SXZydSeYe0'
      }
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