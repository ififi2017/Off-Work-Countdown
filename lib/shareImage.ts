import QRCode from "qrcode";
import type { Mood } from "./moods";

// Client-side share-image generator. Draws a polished card on an offscreen
// <canvas> (2x DPR for retina crispness) with the mood gradient, emoji,
// countdown text, an optional progress bar, plus the site logo, QR code and URL.
// Never draws salary/earnings — it only receives the values passed below.

export type ShareFormat = "square" | "story";

export interface ShareImageOptions {
  timeLeft: string;
  headline: string;
  siteName: string;
  url: string; // encoded into the QR and shown as text
  mood: Mood;
  format: ShareFormat;
  progress?: number; // 0-100, optional thin bar
  logoSrc?: string;
}

export interface ShareImageResult {
  blob: Blob;
  objectUrl: string;
  width: number;
  height: number;
}

const SANS =
  '-apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif';
const EMOJI_FONT =
  '"Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji", sans-serif';

interface Layout {
  w: number;
  h: number;
  panel: { x: number; y: number; w: number; h: number; r: number };
  emojiY: number;
  emojiSize: number;
  headlineY: number;
  headlineSize: number;
  timeY: number;
  timeStartSize: number;
  timeMaxWidth: number;
  bar: { x: number; y: number; w: number; h: number } | null;
  logo: { x: number; y: number; r: number };
  nameX: number;
  nameSize: number;
  qr: { x: number; y: number; size: number };
  urlY: number;
  urlSize: number;
}

const LAYOUTS: Record<ShareFormat, Layout> = {
  square: {
    w: 1080,
    h: 1080,
    panel: { x: 90, y: 150, w: 900, h: 620, r: 48 },
    emojiY: 300,
    emojiSize: 168,
    headlineY: 440,
    headlineSize: 46,
    timeY: 560,
    timeStartSize: 116,
    timeMaxWidth: 760,
    bar: { x: 200, y: 680, w: 680, h: 16 },
    logo: { x: 150, y: 905, r: 44 },
    nameX: 214,
    nameSize: 38,
    qr: { x: 812, y: 838, size: 150 },
    urlY: 1012,
    urlSize: 30,
  },
  story: {
    w: 1080,
    h: 1920,
    panel: { x: 90, y: 430, w: 900, h: 800, r: 56 },
    emojiY: 640,
    emojiSize: 210,
    headlineY: 830,
    headlineSize: 54,
    timeY: 990,
    timeStartSize: 132,
    timeMaxWidth: 780,
    bar: { x: 200, y: 1130, w: 680, h: 18 },
    logo: { x: 160, y: 1580, r: 50 },
    nameX: 236,
    nameSize: 44,
    qr: { x: 790, y: 1500, size: 170 },
    urlY: 1740,
    urlSize: 34,
  },
};

function loadImage(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.crossOrigin = "anonymous";
    img.onload = () => resolve(img);
    img.onerror = reject;
    img.src = src;
  });
}

function roundRectPath(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  w: number,
  h: number,
  r: number
) {
  const radius = Math.min(r, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + radius, y);
  ctx.arcTo(x + w, y, x + w, y + h, radius);
  ctx.arcTo(x + w, y + h, x, y + h, radius);
  ctx.arcTo(x, y + h, x, y, radius);
  ctx.arcTo(x, y, x + w, y, radius);
  ctx.closePath();
}

function drawSoftBlob(
  ctx: CanvasRenderingContext2D,
  cx: number,
  cy: number,
  r: number,
  alpha: number
) {
  const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, r);
  g.addColorStop(0, `rgba(255,255,255,${alpha})`);
  g.addColorStop(1, "rgba(255,255,255,0)");
  ctx.fillStyle = g;
  ctx.beginPath();
  ctx.arc(cx, cy, r, 0, Math.PI * 2);
  ctx.fill();
}

function fitFontSize(
  ctx: CanvasRenderingContext2D,
  text: string,
  maxWidth: number,
  startPx: number,
  weight: string
): number {
  let size = startPx;
  while (size > 28) {
    ctx.font = `${weight} ${size}px ${SANS}`;
    if (ctx.measureText(text).width <= maxWidth) break;
    size -= 4;
  }
  return size;
}

function canvasToBlob(canvas: HTMLCanvasElement): Promise<Blob> {
  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (blob) resolve(blob);
      else reject(new Error("canvas.toBlob returned null"));
    }, "image/png");
  });
}

export async function generateShareImage(
  opts: ShareImageOptions
): Promise<ShareImageResult> {
  const L = LAYOUTS[opts.format];
  const dpr = 2;

  const canvas = document.createElement("canvas");
  canvas.width = L.w * dpr;
  canvas.height = L.h * dpr;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("2D canvas context unavailable");
  ctx.scale(dpr, dpr);

  // Make sure any web fonts are ready before measuring/drawing text.
  try {
    await document.fonts?.ready;
  } catch {
    // ignore — falls back to system fonts
  }

  // Generate the QR (dark on white) and load the logo + mood emoji up front.
  const [qrDataUrl, logo, emojiImg] = await Promise.all([
    QRCode.toDataURL(opts.url, {
      margin: 1,
      width: 320,
      color: { dark: "#111827", light: "#ffffff" },
    }),
    loadImage(opts.logoSrc ?? "/icon-512x512.png").catch(() => null),
    loadImage(`/emoji/${opts.mood.code}.png`).catch(() => null),
  ]);
  const qrImg = await loadImage(qrDataUrl).catch(() => null);

  // 1) Mood gradient background
  const grad = ctx.createLinearGradient(0, 0, L.w, L.h);
  const stops = opts.mood.gradient;
  stops.forEach((c, i) =>
    grad.addColorStop(stops.length === 1 ? 0 : i / (stops.length - 1), c)
  );
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, L.w, L.h);

  // 2) Decorative soft light
  drawSoftBlob(ctx, L.w * 0.82, L.h * 0.12, L.w * 0.55, 0.18);
  drawSoftBlob(ctx, L.w * 0.1, L.h * 0.92, L.w * 0.5, 0.1);

  // 3) Translucent "glass" panel
  ctx.save();
  roundRectPath(ctx, L.panel.x, L.panel.y, L.panel.w, L.panel.h, L.panel.r);
  ctx.fillStyle = "rgba(255,255,255,0.14)";
  ctx.fill();
  ctx.lineWidth = 2;
  ctx.strokeStyle = "rgba(255,255,255,0.35)";
  ctx.stroke();
  ctx.restore();

  ctx.textAlign = "center";
  ctx.textBaseline = "middle";

  // 4) Emoji — bundled PNG for reliable rendering across devices (system emoji
  //    do not rasterize to canvas on iOS Safari). Fall back to text if missing.
  if (emojiImg) {
    const size = L.emojiSize;
    ctx.drawImage(emojiImg, L.w / 2 - size / 2, L.emojiY - size / 2, size, size);
  } else {
    ctx.font = `${L.emojiSize}px ${EMOJI_FONT}`;
    ctx.fillStyle = "#ffffff";
    ctx.fillText(opts.mood.emoji, L.w / 2, L.emojiY);
  }

  // 5) Headline (localized "Off work in")
  ctx.font = `600 ${L.headlineSize}px ${SANS}`;
  ctx.fillStyle = "rgba(255,255,255,0.85)";
  ctx.fillText(opts.headline, L.w / 2, L.headlineY);

  // 6) Countdown time (auto-fit, with a soft shadow for legibility)
  const timeSize = fitFontSize(ctx, opts.timeLeft, L.timeMaxWidth, L.timeStartSize, "800");
  ctx.font = `800 ${timeSize}px ${SANS}`;
  ctx.fillStyle = "#ffffff";
  ctx.shadowColor = "rgba(0,0,0,0.18)";
  ctx.shadowBlur = 24;
  ctx.shadowOffsetY = 6;
  ctx.fillText(opts.timeLeft, L.w / 2, L.timeY);
  ctx.shadowColor = "transparent";
  ctx.shadowBlur = 0;
  ctx.shadowOffsetY = 0;

  // 7) Optional progress bar
  if (L.bar && typeof opts.progress === "number") {
    const p = Math.max(0, Math.min(100, opts.progress)) / 100;
    roundRectPath(ctx, L.bar.x, L.bar.y, L.bar.w, L.bar.h, L.bar.h / 2);
    ctx.fillStyle = "rgba(255,255,255,0.3)";
    ctx.fill();
    if (p > 0) {
      roundRectPath(ctx, L.bar.x, L.bar.y, Math.max(L.bar.h, L.bar.w * p), L.bar.h, L.bar.h / 2);
      ctx.fillStyle = "#ffffff";
      ctx.fill();
    }
  }

  // 8) Footer — logo + site name (left)
  if (logo) {
    ctx.save();
    ctx.beginPath();
    ctx.arc(L.logo.x, L.logo.y, L.logo.r, 0, Math.PI * 2);
    ctx.closePath();
    ctx.clip();
    ctx.drawImage(
      logo,
      L.logo.x - L.logo.r,
      L.logo.y - L.logo.r,
      L.logo.r * 2,
      L.logo.r * 2
    );
    ctx.restore();
  }
  ctx.textAlign = "left";
  ctx.font = `700 ${L.nameSize}px ${SANS}`;
  ctx.fillStyle = "#ffffff";
  ctx.fillText(opts.siteName, L.nameX, L.logo.y);

  // Footer — QR (white rounded backing) + URL (right/bottom)
  if (qrImg) {
    ctx.save();
    roundRectPath(ctx, L.qr.x - 14, L.qr.y - 14, L.qr.size + 28, L.qr.size + 28, 20);
    ctx.fillStyle = "#ffffff";
    ctx.fill();
    ctx.drawImage(qrImg, L.qr.x, L.qr.y, L.qr.size, L.qr.size);
    ctx.restore();
  }

  // URL text: clean display (drop protocol, query/UTM and trailing slash);
  // the full tracked URL still lives in the QR code above.
  const prettyUrl = opts.url
    .replace(/^https?:\/\//, "")
    .replace(/[?#].*$/, "")
    .replace(/\/$/, "");
  ctx.textAlign = "center";
  ctx.font = `500 ${L.urlSize}px ${SANS}`;
  ctx.fillStyle = "rgba(255,255,255,0.9)";
  ctx.fillText(prettyUrl, L.w / 2, L.urlY);

  const blob = await canvasToBlob(canvas);
  return {
    blob,
    objectUrl: URL.createObjectURL(blob),
    width: L.w,
    height: L.h,
  };
}
