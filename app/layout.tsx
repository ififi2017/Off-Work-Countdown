import localFont from "next/font/local";
import "./globals.css";
import { ServiceWorkerRegistration } from "@/components/ServiceWorkerRegistration";
import { SpeedInsights } from "@vercel/speed-insights/next";
import { Analytics } from "@vercel/analytics/react";
import { ManifestLink } from "@/components/ManifestLink";
import { locales } from "@/i18n-config";
import { siteConfig } from "@/config/site";

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

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html suppressHydrationWarning>
      <head>
        <ManifestLink />
        {locales.map((locale) => (
          <link
            key={locale}
            rel="alternate"
            hrefLang={locale}
            href={`${siteConfig.baseUrl}/${locale}`}
          />
        ))}
        <link rel="alternate" hrefLang="x-default" href={siteConfig.baseUrl} />
      </head>
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased`}
      >
        <ServiceWorkerRegistration />
        {children}
        <Analytics />
        <SpeedInsights />
      </body>
    </html>
  );
}
