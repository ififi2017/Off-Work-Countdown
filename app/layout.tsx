import localFont from "next/font/local";
import "./globals.css";
import { ServiceWorkerRegistration } from "@/components/ServiceWorkerRegistration";
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
  title: "下班倒计时",
  description: "倒计时显示距离下班还有多长时间",
  applicationName: "下班倒计时",
  appleWebApp: {
    capable: true,
    title: "下班倒计时",
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
      </body>
    </html>
  );
}
