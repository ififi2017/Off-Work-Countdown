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
  // 标题优化：使用管道符分隔，添加更多关键词
  title: "Off Work Countdown - 下班倒计时",
  
  // 描述优化：更详细，包含更多关键词，突出应用价值
  description: "Track your workday progress with Off Work Countdown. Enhancing workplace productivity and work-life balance. - 使用“下班倒计时”跟踪您的工作日进度。提升职场生产力和工作与生活的平衡。",
  
  // 关键词：虽然不直接写在 meta 中，但可以通过描述间接包含
  keywords: "work countdown, productivity timer, time management, workplace efficiency, work progress tracker, 下班倒计时",
  
  applicationName: "Off Work Countdown - 职场效率管理工具",
  
  appleWebApp: {
    capable: true,
    title: "Off Work Countdown | Time Tracker",
  },
  
  formatDetection: {
    telephone: false,
  },
  
  // 添加开放图谱（Open Graph）信息，有助于社交媒体分享
  openGraph: {
    title: "Off Work Countdown - Boost Your Work Productivity",
    description: "Efficiently track and manage your work hours with our intuitive countdown app.",
    type: "website",
    locale: "en_US",
    url: "https://off.rainif.com",
    // 如果有应用的预览图，可以添加 images 字段
    images: [{ 
      url: "https://github.com/ififi2017/Off-Work-Countdown/raw/main/readme_image/demo.jpg",
      width: 1200,
      height: 630,
      alt: "Off Work Countdown App Interface"
    }]
  },
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
