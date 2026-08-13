export const siteConfig = {
  name: "Off Work Countdown",
  baseUrl: process.env.NEXT_PUBLIC_BASE_URL || "https://off.rainif.com",
  github: "https://github.com/ififi2017/Off-Work-Countdown",
  githubOwner: "ififi2017",
  githubRepo: "Off-Work-Countdown",
  releases: "https://github.com/ififi2017/Off-Work-Countdown/releases",
  // 支持与隐私问询邮箱。也是 Partner Center 的商店 listing 必填项，
  // 两处必须是同一个地址（见 docs/PLAN-M6-MSSTORE.md §3）。
  supportEmail: "offwork@rainif.com",
  themeColor: "#F3F4F6",
} as const;

export type SiteConfig = typeof siteConfig;
