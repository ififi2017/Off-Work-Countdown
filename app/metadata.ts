import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "下班倒计时",
  description: "倒计时显示距离下班还有多长时间",
  applicationName: "下班倒计时",
  appleWebApp: {
    capable: true,
    title: "下班倒计时",
    statusBarStyle: "black-translucent",
  },
  formatDetection: {
    telephone: false,
  },
  themeColor: "#F3F4F6",
  viewport: "width=device-width, initial-scale=1, maximum-scale=1",
};