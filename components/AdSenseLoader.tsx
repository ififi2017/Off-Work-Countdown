"use client";

import { usePathname } from "next/navigation";
import { useEffect } from "react";
import { siteConfig } from "@/config/site";
import { AD_CLOSED_EVENT, ADSENSE_SRC, shouldLoadAds } from "@/lib/ads";

const SCRIPT_ID = "adsense-loader";
/** Height of Google's bottom anchor ad while it is on screen, for fixed UI to sit above. */
const ANCHOR_VAR = "--ad-anchor-h";
/** Phones and small tablets: the bottom anchor bar. Wider screens follow the console (off). */
const ANCHOR_MEDIA = "(max-width: 1023px)";

/** True for an installed PWA (any platform) or a Play-installed web wrapper. */
export function isInstalledApp(): boolean {
  const modes = ["standalone", "fullscreen", "minimal-ui", "window-controls-overlay"];
  return (
    modes.some((mode) => window.matchMedia(`(display-mode: ${mode})`).matches) ||
    (navigator as Navigator & { standalone?: boolean }).standalone === true ||
    document.referrer.startsWith("android-app://")
  );
}

/** The single client-side gate shared by the loader and every ad unit. */
export function adsAllowedHere(pathname: string): boolean {
  return shouldLoadAds({
    pathname,
    hostname: window.location.hostname,
    productionHostname: new URL(siteConfig.webAppUrl).hostname,
    installedApp: isInstalledApp(),
  });
}

/**
 * Publishes the on-screen height of Google's anchor ad as `--ad-anchor-h` on
 * <html> (0 when absent, closed or off screen). Fixed bottom UI adds it to its
 * offset so it never covers the ad and the ad never covers it. Google appends
 * the anchor to <html> (observed 2026-11: 139 px on a phone incl. the close
 * handle, 25 px of handle left after closing); only that element is observed.
 */
function trackAnchorHeight(): () => void {
  const root = document.documentElement;
  let anchor: HTMLElement | null = null;
  let announcedClose = false;
  const update = () => {
    // The visitor closed the bar with Google's own handle (we may not add a
    // close button to Google's ad): offer the ad-free apps, as for side rails.
    if (!announcedClose && anchor?.getAttribute("data-anchor-status") === "dismissed") {
      announcedClose = true;
      window.dispatchEvent(new Event(AD_CLOSED_EVENT));
    }
    let h = 0;
    if (anchor?.isConnected && getComputedStyle(anchor).display !== "none") {
      const top = anchor.getBoundingClientRect().top;
      if (top < window.innerHeight) h = Math.round(window.innerHeight - top);
    }
    root.style.setProperty(ANCHOR_VAR, `${h}px`);
  };
  const resize = new ResizeObserver(update);
  const attrs = new MutationObserver(update);
  const find = () => {
    const next = document.querySelector<HTMLElement>(
      ":root > ins[data-anchor-status], body > ins[data-anchor-status]",
    );
    if (next && next !== anchor) {
      anchor = next;
      resize.observe(next);
      attrs.observe(next, { attributes: true, attributeFilter: ["style", "data-anchor-status"] });
      // Google slides the bar in and out; settle after the transition too.
      next.addEventListener("transitionend", update);
    }
    update();
  };
  const children = new MutationObserver(find);
  children.observe(root, { childList: true });
  children.observe(document.body, { childList: true });
  // Google may mark the element as an anchor after inserting it; it slides in
  // on scroll, so re-check then as well (a cheap child-selector lookup).
  window.addEventListener("scroll", find, { passive: true });
  window.addEventListener("resize", update);
  find();
  return () => {
    children.disconnect();
    resize.disconnect();
    attrs.disconnect();
    window.removeEventListener("scroll", find);
    window.removeEventListener("resize", update);
  };
}

/**
 * Loads AdSense once, after hydration, so an installed PWA is detected before
 * any ad request is made. Client navigation keeps the script loaded.
 *
 * `data-overlays="collapsed-bottom"` limits anchor ads to Google's regular,
 * short bottom bar: no top anchor and no collapsible anchor (which opens
 * large and left a tall blank band at the page bottom). Visitors can close it;
 * it returns on the next page load. It overrides the console's anchor setting,
 * so it is set only below 1024 px; wide screens keep the console setting (off)
 * so a desktop bar cannot cover the side rails.
 */
export function AdSenseLoader() {
  const pathname = usePathname();

  useEffect(() => {
    if (document.getElementById(SCRIPT_ID)) return;
    if (!adsAllowedHere(pathname)) return;
    const script = document.createElement("script");
    script.id = SCRIPT_ID;
    script.async = true;
    script.src = ADSENSE_SRC;
    script.crossOrigin = "anonymous";
    if (window.matchMedia(ANCHOR_MEDIA).matches) script.dataset.overlays = "collapsed-bottom";
    document.head.appendChild(script);
  }, [pathname]);

  useEffect(() => {
    if (!adsAllowedHere(pathname)) return;
    return trackAnchorHeight();
  }, [pathname]);

  return null;
}
