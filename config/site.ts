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
  // Mac App Store 产品页。付费版（见 docs/PLAN-MSSTORE.md 9.9）：桌面小组件是
  // 它与 GitHub 版的差异点，不是同一个包的两种下载方式。
  macAppStore: "https://apps.apple.com/us/app/off-work-countdown/id6802803318",
  // macOS 上由系统 App Store 注册的 URL scheme 直接打开商品页；浏览器链接仍为
  // 其他平台和未完成 hydration 时的安全回退。
  macAppStoreApp: "macappstore://itunes.apple.com/app/id6802803318",
  // 支持与隐私问询邮箱。也是 Partner Center 的商店 listing 必填项，
  // 两处必须是同一个地址（见 docs/PLAN-MSSTORE.md §3）。
  supportEmail: "offwork@rainif.com",
  themeColor: "#F3F4F6",
} as const;

export type SiteConfig = typeof siteConfig;
