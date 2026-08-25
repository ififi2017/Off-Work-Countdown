import { ReactNode } from 'react';
import localFont from 'next/font/local';
import '../globals.css';
import { SpeedInsights } from '@vercel/speed-insights/next';
import { Analytics } from '@vercel/analytics/react';
import { locales, getTextDirection } from '@/i18n-config';
import { Metadata, Viewport } from 'next';
import { siteConfig } from '@/config/site';
import { getTranslations } from '@/lib/server/i18n';
import { ThemeRouteSync } from '@/components/ThemeRouteSync';
import {
  IS_DESKTOP_BUILD,
  IS_MOBILE_BUILD,
  IS_WEB_BUILD,
} from '@/lib/build-target';

const geistSans = localFont({
  src: '../fonts/GeistVF.woff',
  variable: '--font-geist-sans',
  weight: '100 900',
});
const geistMono = localFont({
  src: '../fonts/GeistMonoVF.woff',
  variable: '--font-geist-mono',
  weight: '100 900',
});

// 在首次绘制前把主题类打到 <html> 上，避免深色/自定义主题用户看到一帧浅色。
// 必须与 off-work-countdown.tsx 的 applyTheme 保持一致。
const themeInitScript = `(function(){try{var t=localStorage.getItem('theme')||'auto';var d=window.matchMedia('(prefers-color-scheme: dark)').matches;var r=document.documentElement;if(t==='dark'||(t==='auto'&&d)){r.classList.add('dark')}else if(t==='cyberpunk'){r.classList.add('dark','theme-cyberpunk')}else if(t==='sunset'){r.classList.add('theme-sunset')}}catch(e){}})();`;

export const viewport: Viewport = {
  themeColor: siteConfig.themeColor,
  width: 'device-width',
  initialScale: 1,
  viewportFit: 'cover',
};

export async function generateMetadata({ params }: { params: Promise<{ lang: string }> }): Promise<Metadata> {
  const { lang } = await params;
  const seo = await getTranslations(lang, 'seo');

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
      locale: lang,
      url: `${siteConfig.baseUrl}/${lang}`,
      siteName: seo.siteName,
      // og:image / twitter:image 由 opengraph-image.tsx 自动注入，托管在自有
      // 域名下。不再指向 GitHub raw：那是外部依赖，且原图是 894x1092 的竖图，
      // 与此处声明的 1200x630 不符。
    },
    twitter: {
      card: 'summary_large_image',
      title: seo.title,
      description: seo.description,
    },
    alternates: {
      canonical: `${siteConfig.baseUrl}/${lang}`,
      // Next.js 会据此渲染 hreflang link 标签，无需再手写一份（此前 root
      // layout 手动输出过，导致每个 hreflang 重复两次）。
      languages: {
        ...Object.fromEntries(
          locales.map(l => [l, `${siteConfig.baseUrl}/${l}`])
        ),
        'x-default': siteConfig.baseUrl,
      }
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

export default async function Layout({
  children,
  params,
}: {
  children: ReactNode;
  params: Promise<{ lang: string }>;
}) {
  const { lang } = await params;

  return (
    <html
      lang={lang}
      dir={getTextDirection(lang)}
      className={
        IS_DESKTOP_BUILD
          ? "desktop-shell"
          : IS_MOBILE_BUILD
            ? "mobile-shell"
            : undefined
      }
      suppressHydrationWarning
    >
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeInitScript }} />
        {IS_WEB_BUILD && (
          <link
            rel="manifest"
            href={`/manifest.json?lang=${lang}`}
            crossOrigin="use-credentials"
          />
        )}
      </head>
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased${
          IS_DESKTOP_BUILD
            ? " desktop-shell"
            : IS_MOBILE_BUILD
              ? " mobile-shell"
              : ""
        }`}
      >
        <ThemeRouteSync />
        {children}
        {/* Vercel 的访问统计与性能采集只服务于 Web 端。桌面端不回传任何数据
            （见 plans/003-tauri-desktop.md 决策 5），这里用构建期常量剔除——
            桌面构建下整个分支是死代码，压缩阶段会被移除。 */}
        {IS_WEB_BUILD && (
          <>
            <Analytics />
            <SpeedInsights />
          </>
        )}
      </body>
    </html>
  );
}
