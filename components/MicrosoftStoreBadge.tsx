"use client";

import { createElement, useEffect, useRef, useState } from "react";
import Script from "next/script";
import { siteConfig } from "@/config/site";
import { track } from "@/lib/track";

const IS_DESKTOP_BUILD =
  process.env.NEXT_PUBLIC_BUILD_TARGET === "desktop";

interface MicrosoftStoreBadgeProps {
  className?: string;
}

export function MicrosoftStoreBadge({ className }: MicrosoftStoreBadgeProps) {
  const [badgeTheme, setBadgeTheme] = useState<"light" | "dark">();
  const badgeRef = useRef<HTMLElement>(null);

  useEffect(() => {
    if (IS_DESKTOP_BUILD) return;

    const syncTheme = () => {
      // theme 描述的是徽章本身，而不是页面背景：深色页面用浅色徽章，反之亦然。
      setBadgeTheme(
        document.documentElement.classList.contains("dark") ? "light" : "dark"
      );
    };
    const observer = new MutationObserver(syncTheme);

    syncTheme();
    observer.observe(document.documentElement, {
      attributeFilter: ["class"],
      attributes: true,
    });

    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    const badge = badgeRef.current;
    if (!badge || !badgeTheme) return;

    // 组件注册完成后 React 会优先写同名 property，但微软组件只会响应 attribute。
    // 直接更新标准属性，同时重申 small，避免主题切换后回退到默认 large。
    badge.setAttribute("size", "small");
    badge.setAttribute("theme", badgeTheme);
  }, [badgeTheme]);

  if (IS_DESKTOP_BUILD) return null;

  return (
    <>
      <Script
        src="https://get.microsoft.com/badge/ms-store-badge.bundled.js"
        strategy="afterInteractive"
      />
      <div
        className={className}
        onClickCapture={() => track("desktop_download_msstore")}
      >
        {createElement("ms-store-badge", {
          ref: badgeRef,
          productid: siteConfig.microsoftStoreProductId,
          productname: siteConfig.name,
          "window-mode": "direct",
          size: "small",
          animation: "on",
        })}
        <noscript>
          <a
            href={siteConfig.microsoftStore}
            target="_blank"
            rel="noopener noreferrer"
          >
            Microsoft Store
          </a>
        </noscript>
      </div>
    </>
  );
}
