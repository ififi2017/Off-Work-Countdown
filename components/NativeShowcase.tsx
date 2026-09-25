"use client";

import { useEffect, useRef, useState } from "react";
import { useReducedMotion } from "framer-motion";
import { useTranslation } from "react-i18next";
import { locales } from "@/i18n-config";

// 网页版首屏以下的原生 App 展示：一个 iPhone 图位轮播四张商店图，旁边列出
// 四条说明（当前那条高亮、可点选），下面是一张电脑主窗。
// 只由 off-work-countdown.tsx 在 isWebPage 时渲染，桌面导出、iOS 壳和 PWA
// 独立窗口都没有它；图片也不进 Service Worker 预缓存（见 next.config）。
// 图由 scripts/marketing-shots/web-showcase.mjs 从本机商店图产物导出。

// 3.2.0 商店图只有 17 种商店语言：香港用台湾繁中那套，马拉地语用印地语那套。
const IPHONE_LOCALES = new Set([
  "ar", "de", "en", "es", "fr", "hi-IN", "id", "it", "ja",
  "ko", "pt", "ru", "th", "tr", "vi", "zh-CN", "zh-TW",
]);
const IPHONE_LOCALE_FALLBACK: Record<string, string> = {
  "zh-HK": "zh-TW",
  "mr-IN": "hi-IN",
};

function iphoneLocale(lang: string) {
  const mapped = IPHONE_LOCALE_FALLBACK[lang] ?? lang;
  return IPHONE_LOCALES.has(mapped) ? mapped : "en";
}

// 顺序即轮播顺序；文件名与导出脚本一致。
const IPHONE_SHOTS = [
  ["countdown", "Countdown"],
  ["widgets", "Widgets"],
  ["calendar", "Calendar"],
  ["watch", "Watch"],
] as const;

// 每张停留的时间。只在图位可见、没有悬停或键盘焦点、没开「减少动态效果」时轮播。
const ROTATE_MS = 4500;

const SHOT_FRAME =
  "h-auto w-full bg-white shadow-[0_1px_2px_rgba(15,23,42,0.05),0_10px_30px_-12px_rgba(15,23,42,0.18)] ring-1 ring-black/[0.06] dark:bg-white/[0.04] dark:shadow-none dark:ring-white/[0.08]";

export function NativeShowcase({ lang }: { lang: string }) {
  const { t } = useTranslation();
  const reduceMotion = useReducedMotion();
  const phone = iphoneLocale(lang);
  const desktop = (locales as readonly string[]).includes(lang) ? lang : "en";
  const slotRef = useRef<HTMLDivElement>(null);
  const [active, setActive] = useState(0);
  const [visible, setVisible] = useState(false);
  const [held, setHeld] = useState(false);

  useEffect(() => {
    const slot = slotRef.current;
    if (!slot) return;
    const io = new IntersectionObserver(([entry]) => setVisible(entry.isIntersecting), {
      threshold: 0.4,
    });
    io.observe(slot);
    return () => io.disconnect();
  }, []);

  // active 也在依赖里：手动点选后从头计时，不会刚点完就被切走。
  useEffect(() => {
    if (reduceMotion || held || !visible) return;
    const timer = window.setTimeout(
      () => setActive((index) => (index + 1) % IPHONE_SHOTS.length),
      ROTATE_MS
    );
    return () => window.clearTimeout(timer);
  }, [active, held, reduceMotion, visible]);

  return (
    <section aria-labelledby="native-showcase-title" className="mt-20">
      <div className="mx-auto max-w-2xl text-center">
        <h2
          id="native-showcase-title"
          className="text-xl font-semibold tracking-tight text-gray-950 dark:text-white sm:text-2xl"
        >
          {t("webShowcaseTitle")}
        </h2>
        <p className="mt-3 text-sm leading-6 text-gray-600 dark:text-gray-400 sm:text-base sm:leading-7">
          {t("webShowcaseBody")}
        </p>
      </div>

      <div
        className="mx-auto mt-10 grid max-w-3xl items-center gap-8 sm:grid-cols-[15rem_1fr] sm:gap-12"
        onMouseEnter={() => setHeld(true)}
        onMouseLeave={() => setHeld(false)}
        onFocus={() => setHeld(true)}
        onBlur={() => setHeld(false)}
      >
        <div
          ref={slotRef}
          className={`${SHOT_FRAME} relative mx-auto aspect-[480/1043] max-w-[15rem] overflow-hidden rounded-[1.25rem]`}
        >
          {IPHONE_SHOTS.map(([file, key], index) => (
            // WebP 已按显示宽度的 2 倍导出，不再经 next/image 处理。四张叠放交叉淡入，
            // alt 都留在 HTML 里；读屏只读当前那张。
            // eslint-disable-next-line @next/next/no-img-element
            <img
              key={file}
              src={`/showcase/${phone}/iphone-${file}.webp`}
              width={480}
              height={1043}
              loading="lazy"
              decoding="async"
              alt={t(`webShowcase${key}Alt`)}
              aria-hidden={index !== active}
              className={`absolute inset-0 h-full w-full transition-opacity duration-500 ease-out motion-reduce:transition-none ${
                index === active ? "opacity-100" : "opacity-0"
              }`}
            />
          ))}
        </div>

        <ul className="space-y-1">
          {IPHONE_SHOTS.map(([file, key], index) => (
            <li key={file}>
              <button
                type="button"
                aria-pressed={index === active}
                onClick={() => setActive(index)}
                className={`flex w-full items-start gap-3 rounded-xl px-3 py-2.5 text-start text-sm leading-6 transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-gray-400 ${
                  index === active
                    ? "bg-white/70 text-gray-900 dark:bg-white/[0.04] dark:text-gray-100"
                    : "text-gray-500 hover:text-gray-800 dark:text-gray-400 dark:hover:text-gray-200"
                }`}
              >
                <span
                  aria-hidden="true"
                  className={`mt-[0.6rem] h-1.5 w-1.5 shrink-0 rounded-full transition-colors ${
                    index === active ? "bg-orange-500" : "bg-gray-300 dark:bg-white/20"
                  }`}
                />
                {t(`webShowcase${key}Caption`)}
              </button>
            </li>
          ))}
        </ul>
      </div>

      {/* 电脑主窗与上面同一套两列：图在左列，说明在右列。 */}
      <figure className="mx-auto mt-12 grid max-w-3xl items-center gap-5 sm:grid-cols-[15rem_1fr] sm:gap-12">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={`/showcase/${desktop}/desktop.webp`}
          width={600}
          height={600}
          loading="lazy"
          decoding="async"
          alt={t("webShowcaseDesktopAlt")}
          className={`${SHOT_FRAME} mx-auto w-full max-w-[15rem] rounded-2xl`}
        />
        {/* 左内边距 = 上面按钮的 px-3 + 圆点 + 间距，文字与上面四条对齐。 */}
        <figcaption className="px-3 text-center text-sm leading-6 text-gray-600 dark:text-gray-400 sm:ps-[1.875rem] sm:text-start">
          {t("webShowcaseDesktopCaption")}
        </figcaption>
      </figure>
    </section>
  );
}
