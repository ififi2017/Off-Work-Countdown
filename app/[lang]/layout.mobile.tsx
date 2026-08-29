import type { Metadata, Viewport } from "next";
import localFont from "next/font/local";
import type { ReactNode } from "react";
import { ThemeRouteSync } from "@/components/ThemeRouteSync";
import { getTextDirection, locales } from "@/i18n-config";
import "../globals.css";

const geistSans = localFont({
  src: "../fonts/GeistVF.woff",
  variable: "--font-geist-sans",
  weight: "100 900",
});
const geistMono = localFont({
  src: "../fonts/GeistMonoVF.woff",
  variable: "--font-geist-mono",
  weight: "100 900",
});

const themeInitScript = `(function(){try{var t=localStorage.getItem('theme')||'auto';var d=window.matchMedia('(prefers-color-scheme: dark)').matches;var r=document.documentElement;if(t==='dark'||(t==='auto'&&d)){r.classList.add('dark')}else if(t==='cyberpunk'){r.classList.add('dark','theme-cyberpunk')}else if(t==='sunset'){r.classList.add('theme-sunset')}}catch(e){}})();`;

export const metadata: Metadata = {
  title: "DoneAt",
  applicationName: "DoneAt",
  formatDetection: { telephone: false },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: "#F3F4F6",
};

export function generateStaticParams() {
  return locales.map((lang) => ({ lang }));
}

export default async function MobileLayout({
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
      className="mobile-shell"
      suppressHydrationWarning
    >
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeInitScript }} />
      </head>
      <body
        className={`${geistSans.variable} ${geistMono.variable} mobile-shell antialiased`}
      >
        <ThemeRouteSync />
        {children}
      </body>
    </html>
  );
}
