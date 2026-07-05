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

// Build the promoted site URL with UTM params so shares are measurable in analytics.
export function buildShareUrl(medium: ShareMedium): string {
  const url = new URL(siteConfig.baseUrl);
  url.searchParams.set("utm_source", "share");
  url.searchParams.set("utm_medium", medium);
  url.searchParams.set("utm_campaign", "countdown");
  return url.toString();
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
