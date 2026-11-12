"use client";

import { usePathname } from "next/navigation";
import { useEffect } from "react";
import { siteConfig } from "@/config/site";
import { ADSENSE_SRC, shouldLoadAds } from "@/lib/ads";

const SCRIPT_ID = "adsense-loader";

/** True for an installed PWA (any platform) or a Play-installed web wrapper. */
function isInstalledApp(): boolean {
  const modes = ["standalone", "fullscreen", "minimal-ui", "window-controls-overlay"];
  return (
    modes.some((mode) => window.matchMedia(`(display-mode: ${mode})`).matches) ||
    (navigator as Navigator & { standalone?: boolean }).standalone === true ||
    document.referrer.startsWith("android-app://")
  );
}

/**
 * Loads AdSense once, after hydration, so an installed PWA is detected before
 * any ad request is made. Client navigation keeps the script loaded.
 */
export function AdSenseLoader() {
  const pathname = usePathname();

  useEffect(() => {
    if (document.getElementById(SCRIPT_ID)) return;
    const load = shouldLoadAds({
      pathname,
      hostname: window.location.hostname,
      productionHostname: new URL(siteConfig.webAppUrl).hostname,
      installedApp: isInstalledApp(),
    });
    if (!load) return;
    const script = document.createElement("script");
    script.id = SCRIPT_ID;
    script.async = true;
    script.src = ADSENSE_SRC;
    script.crossOrigin = "anonymous";
    document.head.appendChild(script);
  }, [pathname]);

  return null;
}
