import localFont from "next/font/local";
import "./globals.css";
import { ServiceWorkerRegistration } from "@/components/ServiceWorkerRegistration";
import { SpeedInsights } from "@vercel/speed-insights/next"
import { Analytics } from "@vercel/analytics/react"
import { I18nProvider } from "@/components/I18nProvider";
import type { Metadata } from "next";
import { locales } from "@/i18n-config";
import fs from 'fs/promises';
import path from 'path';

const geistSans = localFont({
  src: "./fonts/GeistVF.woff",
  variable: "--font-geist-sans",
  weight: "100 900",
});
const geistMono = localFont({
  src: "./fonts/GeistMonoVF.woff",
  variable: "--font-geist-mono",
  weight: "100 900",
});

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

export async function generateMetadata({ params }: { params?: { lang?: string } }): Promise<Metadata> {
  const lang = params?.lang || 'en';
  const seo = await getTranslations(lang, 'seo');

  return {
    metadataBase: new URL('https://off.rainif.com'),
    alternates: {
      canonical: `https://off.rainif.com/${lang}`,
      languages: Object.fromEntries(
        locales.map(l => [
          l,
          `https://off.rainif.com/${l}`
        ])
      )
    },
    title: {
      template: '%s | ' + seo.siteName,
      default: seo.title
    },
    description: seo.description,
    keywords: seo.keywords,
    applicationName: seo.siteName,
    appleWebApp: {
      capable: true,
      title: seo.title,
    },
    formatDetection: {
      telephone: false,
    },
    openGraph: {
      title: seo.title,
      description: seo.description,
      type: "website",
      locale: lang,
      url: `https://off.rainif.com/${lang}`,
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

export default function RootLayout({
  children,
  params,
}: Readonly<{
  children: React.ReactNode;
  params?: { lang?: string };
}>) {
  const lang = params?.lang || 'en';

  return (
    <html lang={lang} suppressHydrationWarning>
      <head>
        <link rel="manifest" href="/manifest.json" />
        {locales.map((lang) => (
          <link
            key={lang}
            rel="alternate"
            hrefLang={lang}
            href={`https://off.rainif.com/${lang}`}
          />
        ))}
        <link
          rel="alternate"
          hrefLang="x-default"
          href="https://off.rainif.com"
        />
      </head>
      <body className={`${geistSans.variable} ${geistMono.variable} antialiased`}>
        <I18nProvider lang={lang}>
          <ServiceWorkerRegistration />
          {children}
        </I18nProvider>
        <Analytics />
        <SpeedInsights/>
      </body>
    </html>
  );
}
