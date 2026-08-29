const DEFAULT_WEB_APP_URL = "https://off.rainif.com";
const DEFAULT_OFFICIAL_SITE_URL = "https://doneat.app";

function publicOrigin(
  value: string | undefined,
  fallback: string
): string {
  const raw = value?.trim();
  if (!raw) return fallback;
  return raw.replace(/\/$/, "");
}

const webAppUrl = publicOrigin(
  process.env.NEXT_PUBLIC_WEB_APP_URL || process.env.NEXT_PUBLIC_BASE_URL,
  DEFAULT_WEB_APP_URL
);

export const siteConfig = {
  // 显示名固定为 DoneAt，不随界面语言翻译。`name` 与 `brandName` 同一取值，
  // 给仍按旧字段读产品名的调用点一个明确别名。
  brandName: "DoneAt",
  name: "DoneAt",
  // 可交互 Web App / PWA / 分享落地。预览可用 NEXT_PUBLIC_WEB_APP_URL；
  // NEXT_PUBLIC_BASE_URL 是拆域前的旧名，只作为 webAppUrl 的兼容回退。
  webAppUrl,
  // 拆域前的字段名。新代码读 webAppUrl；留下别名以免旧调用和本地 worktree 立刻断。
  baseUrl: webAppUrl,
  officialSiteUrl: publicOrigin(
    process.env.NEXT_PUBLIC_OFFICIAL_SITE_URL,
    DEFAULT_OFFICIAL_SITE_URL
  ),
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
  supportEmail: "hello@doneat.app",
  themeColor: "#F3F4F6",
} as const;

export type SiteConfig = typeof siteConfig;
