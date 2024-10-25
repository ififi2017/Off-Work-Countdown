import localFont from "next/font/local";
import "./globals.css";
import { ServiceWorkerRegistration } from "@/components/ServiceWorkerRegistration";
import { Analytics } from "@vercel/analytics/react"
import type { Metadata } from "next";
import { I18nProvider } from "@/components/I18nProvider";

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

export const metadata: Metadata = {
  title: "下班倒计时——Off Work Countdown",
  description: "下班倒计时是一个基于 Next.js的网页应用，帮助您跟踪工作日结束前的剩余时间。通过简洁互动的界面，该应用提供可视化的倒计时和进度条，让您的工作日更易管理。",
  applicationName: "下班倒计时——Off Work Countdown",
  appleWebApp: {
    capable: true,
    title: "下班倒计时——Off Work Countdown",
    // statusBarStyle: "black-translucent",
  },
  formatDetection: {
    telephone: false,
  },
  themeColor: "#FFF",
  viewport: "width=device-width, initial-scale=1, maximum-scale=1",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang={typeof window !== "undefined" ? window.navigator.language : "en"}
    >
      <link rel="manifest" href="/manifest.json" />
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased`}
      >
        <I18nProvider>
          <ServiceWorkerRegistration />
          {children}
        </I18nProvider>
        <Analytics />
      </body>
    </html>
  );
}
