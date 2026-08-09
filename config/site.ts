export const siteConfig = {
  name: "Off Work Countdown",
  baseUrl: process.env.NEXT_PUBLIC_BASE_URL || "https://off.rainif.com",
  github: "https://github.com/ififi2017/Off-Work-Countdown",
  githubOwner: "ififi2017",
  githubRepo: "Off-Work-Countdown",
  releases: "https://github.com/ififi2017/Off-Work-Countdown/releases",
  themeColor: "#F3F4F6",
} as const;

export type SiteConfig = typeof siteConfig;
