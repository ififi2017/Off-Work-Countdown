import { siteConfig } from "@/config/site";

// Pure share helpers: URL/UTM building, text composition, per-platform intent
// URLs, and Web Share API feature detection. Kept framework-free for testing.

export type ShareMedium = "text" | "image";

export type SharePlatform =
  | "x"
  | "facebook"
  | "whatsapp"
  | "telegram"
  | "line"
  | "reddit"
  | "weibo";

export interface Shift {
  start: string;
  end: string;
}

// 班次在 URL 里的紧凑表示："0900-1800"。
// 只编码上下班时间——薪资属于敏感信息，绝不进入可被转发的链接。
export function encodeShift({ start, end }: Shift): string {
  return `${start.replace(":", "")}-${end.replace(":", "")}`;
}

const SHIFT_PATTERN = /^([0-2]\d)([0-5]\d)-([0-2]\d)([0-5]\d)$/;

// 严格解析，任何不合法的输入一律返回 null 走默认值。链接来自外部转发，
// 必须当成不可信输入处理。
export function decodeShift(raw: string | null | undefined): Shift | null {
  if (!raw) return null;
  const m = SHIFT_PATTERN.exec(raw);
  if (!m) return null;

  const [, sh, sm, eh, em] = m;
  if (Number(sh) > 23 || Number(eh) > 23) return null;

  const start = `${sh}:${sm}`;
  const end = `${eh}:${em}`;
  // 起止相同无法构成班次，应用本身也会拒绝这种输入。
  if (start === end) return null;

  return { start, end };
}

// Build the promoted site URL with UTM params so shares are measurable in analytics.
// 指向根路径而非某个语言：middleware 会把接收者带到他自己的语言版本。
// 带上班次后，对方打开即可直接看到同一个倒计时，而不是一个空表单。
export function buildShareUrl(medium: ShareMedium, shift?: Shift): string {
  const url = new URL(siteConfig.webAppUrl);
  url.searchParams.set("utm_source", "share");
  url.searchParams.set("utm_medium", medium);
  url.searchParams.set("utm_campaign", "countdown");
  if (shift) {
    url.searchParams.set("s", encodeShift(shift));
    url.searchParams.set("from", "share");
  }
  return url.toString();
}

export const SHARE_IMAGE_FILENAME = "doneat.png";

/** 卡片上印的地址：去掉协议、查询和末尾斜杠。二维码仍编码完整带 UTM 的链接。 */
export function formatShareDisplayUrl(url: string): string {
  return url
    .replace(/^https?:\/\//, "")
    .replace(/[?#].*$/, "")
    .replace(/\/$/, "");
}

// Compose the text-share body: emoji + localized message + site URL.
export function buildShareText(params: {
  emoji: string;
  message: string;
  url: string;
}): string {
  return `${params.emoji} ${params.message} ${params.url}`.trim();
}

const enc = encodeURIComponent;

// Per-platform share intents. All carry text + URL only (no image file — the
// image is shared via the Web Share API / download / copy instead).
export const platformShareUrl: Record<
  SharePlatform,
  (text: string, url: string) => string
> = {
  x: (t, u) => `https://twitter.com/intent/tweet?text=${enc(t)}&url=${enc(u)}`,
  facebook: (t, u) =>
    `https://www.facebook.com/sharer/sharer.php?u=${enc(u)}&quote=${enc(t)}`,
  whatsapp: (t, u) => `https://wa.me/?text=${enc(`${t} ${u}`)}`,
  telegram: (t, u) => `https://t.me/share/url?url=${enc(u)}&text=${enc(t)}`,
  line: (t, u) =>
    `https://social-plugins.line.me/lineit/share?url=${enc(u)}&text=${enc(t)}`,
  reddit: (t, u) => `https://www.reddit.com/submit?url=${enc(u)}&title=${enc(t)}`,
  weibo: (t, u) =>
    `https://service.weibo.com/share/share.php?url=${enc(u)}&title=${enc(t)}`,
};

// Web Share API detection.
export function canNativeShare(): boolean {
  return typeof navigator !== "undefined" && typeof navigator.share === "function";
}

// Level 2 Web Share (attach files, e.g. the generated image) — mobile mainly.
export function canNativeShareFiles(files: File[]): boolean {
  if (typeof navigator === "undefined") return false;
  const nav = navigator as Navigator & {
    canShare?: (data?: ShareData) => boolean;
  };
  return (
    typeof nav.share === "function" &&
    typeof nav.canShare === "function" &&
    nav.canShare({ files })
  );
}
