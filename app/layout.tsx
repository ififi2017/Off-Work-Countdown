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
  title: "Off Work Countdown | Productivity Timer | Work Time Management App - 下班倒计时 | 职场效率工具 | 工作时间管理应用",
  
  // 描述优化：更详细，包含更多关键词，突出应用价值
  description: "Track your workday progress with Off Work Countdown, a Next.js powered web app designed to help professionals manage time efficiently. Visualize your remaining work hours through interactive countdown timers and progress bars, enhancing workplace productivity and work-life balance. - 使用下班倒计时应用，全方位追踪工作日进度。这款基于 Next.js 的网页应用通过交互式倒计时和进度条，帮助职场人士高效管理时间，提升工作效率和生活平衡。",
  
  // 关键词：虽然不直接写在 meta 中，但可以通过描述间接包含
  keywords: "work countdown, productivity timer, time management, workplace efficiency, work progress tracker, Next.js app",
  
  applicationName: "Off Work Countdown - 职场效率管理工具",
  
  appleWebApp: {
    capable: true,
    title: "Off Work Countdown | Time Tracker",
  },
  
  formatDetection: {
    telephone: false,
  },
  
  // 主题色可以选择更有活力的颜色
  themeColor: "#4A90E2",
  
  viewport: "width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no",
  
  // 添加开放图谱（Open Graph）信息，有助于社交媒体分享
  openGraph: {
    title: "Off Work Countdown - Boost Your Work Productivity",
    description: "Efficiently track and manage your work hours with our intuitive countdown app.",
    type: "website",
    locale: "en_US",
    // 如果有应用的预览图，可以添加 images 字段
    images: [{ url: 'https://github.com/ififi2017/Off-Work-Countdown/raw/main/readme_image/off_EN.JPEG' }]
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
