import { ImageResponse } from "next/og";
import { locales } from "@/i18n-config";

// 社交卡片图。1200x630 是 X / Facebook / Telegram / Slack 的 summary_large_image
// 标准比例——此前 metadata 里声明 1200x630 但实际指向一张 894x1092 的竖图，
// 大卡会按 2:1 中心裁切，只露出中间一条。
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
export const alt = "Off Work Countdown";

export function generateStaticParams() {
  return locales.map((lang) => ({ lang }));
}

// 刻意做成语言中性：satori 需要内嵌字体才能渲染字形，而 19 种语言涉及
// CJK、阿拉伯、天城体、泰文等多套字形，全量打包代价过高。localized 标题与
// 描述已经由 og:title / og:description 传给平台，由平台用系统字体渲染，
// 图片只承担视觉部分，因此这里只用拉丁字母和数字。
export default async function OpengraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          backgroundColor: "#f97316",
          backgroundImage: "linear-gradient(135deg, #fbbf24 0%, #f97316 55%, #ea580c 100%)",
          fontFamily: "sans-serif",
          padding: "64px 80px",
        }}
      >
        <div
          style={{
            display: "flex",
            fontSize: 30,
            letterSpacing: 14,
            fontWeight: 700,
            color: "rgba(255,255,255,0.82)",
          }}
        >
          OFF WORK COUNTDOWN
        </div>

        <div
          style={{
            display: "flex",
            fontSize: 196,
            fontWeight: 800,
            color: "#ffffff",
            letterSpacing: -6,
            lineHeight: 1.05,
            marginTop: 26,
          }}
        >
          02:13:45
        </div>

        {/* 进度条：轨道 + 已完成部分 */}
        <div
          style={{
            display: "flex",
            width: 840,
            height: 20,
            borderRadius: 999,
            backgroundColor: "rgba(255,255,255,0.28)",
            marginTop: 34,
          }}
        >
          <div
            style={{
              display: "flex",
              width: 604,
              height: 20,
              borderRadius: 999,
              backgroundColor: "#ffffff",
            }}
          />
        </div>

        <div
          style={{
            display: "flex",
            fontSize: 27,
            color: "rgba(255,255,255,0.92)",
            marginTop: 44,
          }}
        >
          19 languages · Free · Works offline · Open source
        </div>

        <div
          style={{
            display: "flex",
            fontSize: 25,
            fontWeight: 700,
            color: "rgba(255,255,255,0.72)",
            marginTop: 14,
          }}
        >
          off.rainif.com
        </div>
      </div>
    ),
    size
  );
}
