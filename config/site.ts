export const siteConfig = {
  name: "Off Work Countdown",
  baseUrl: process.env.NEXT_PUBLIC_BASE_URL || "https://off.rainif.com",
  github: "https://github.com/ififi2017/Off-Work-Countdown",
  githubOwner: "ififi2017",
  githubRepo: "Off-Work-Countdown",
  releases: "https://github.com/ififi2017/Off-Work-Countdown/releases",
  // 商店产品页与官方徽章共用这个 ID。它还必须与 src-tauri/src/lib.rs 的
  // MICROSOFT_STORE_PRODUCT_ID 保持一致，改动时三处一起核对。
  microsoftStoreProductId: "9PM0HJ2PP2LJ",
  microsoftStore: "https://apps.microsoft.com/detail/9PM0HJ2PP2LJ",
  // 支持与隐私问询邮箱。也是 Partner Center 的商店 listing 必填项，
  // 两处必须是同一个地址（见 docs/PLAN-MSSTORE.md §3）。
  supportEmail: "offwork@rainif.com",
  themeColor: "#F3F4F6",
} as const;

export type SiteConfig = typeof siteConfig;
