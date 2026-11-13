"use client";

import { usePathname } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { X } from "lucide-react";
import { useTranslation } from "react-i18next";
import { AD_CLOSED_EVENT, ADSENSE_CLIENT_ID, ADSENSE_INLINE_SLOT } from "@/lib/ads";
import { adsAllowedHere } from "@/components/AdSenseLoader";
import {
  DESKTOP_INVITE_CLOSED,
  desktopInviteWillShow,
} from "@/components/DesktopDownloadInvite";

type AdsQueue = unknown[];

/**
 * Wide, tall windows where a skyscraper fits beside the 448 px timer card
 * without touching it or the window edge. Below this the rails are not
 * rendered at all (never requested hidden, which AdSense rejects).
 */
export const AD_RAIL_MEDIA = "(min-width: 1024px) and (min-height: 720px)";
const AD_RAIL_WIDE_MEDIA = "(min-width: 1280px)";

type RailSize = { width: number; height: number };

/**
 * One in-page ad. Renders nothing on the server, in an installed PWA, on
 * Desktop or off the production host (same gate as AdSenseLoader), so the app
 * shell never gets an empty box. The wrapper collapses if Google returns no ad.
 *
 * - `inline` (default): responsive, no reserved height. Placements sit below
 *   the first screen or after the main content, so a late ad does not move
 *   what the reader is looking at and a blocked script leaves no gap.
 * - `rail`: a fixed 160×600 or 300×600 unit beside the first-screen card on
 *   wide screens. It scrolls with the page; it is not sticky, because AdSense
 *   forbids mirrored sticky units on both sides of the content. A close
 *   button above it removes it for the current page view.
 */
export function AdSenseUnit({
  className = "",
  variant = "inline",
  avoidDesktopInvite = false,
}: {
  className?: string;
  variant?: "inline" | "rail";
  /** The bottom-right desktop invite would cover this rail: load after it closes. */
  avoidDesktopInvite?: boolean;
}) {
  const pathname = usePathname();
  const [enabled, setEnabled] = useState(false);
  const [railSize, setRailSize] = useState<RailSize | null>(null);
  const [closed, setClosed] = useState(false);
  const { t } = useTranslation();
  const ins = useRef<HTMLModElement>(null);

  useEffect(() => {
    if (!adsAllowedHere(pathname)) return setEnabled(false);
    if (variant === "rail") {
      // Size is chosen once at load: AdSense cannot resize a filled unit.
      if (!window.matchMedia(AD_RAIL_MEDIA).matches) return setEnabled(false);
      const wide = window.matchMedia(AD_RAIL_WIDE_MEDIA).matches;
      setRailSize({ width: wide ? 300 : 160, height: 600 });
    }
    // Ads must never sit under page UI, and hiding a loaded ad is not allowed
    // either, so a covered rail is requested only once the invite has closed.
    if (avoidDesktopInvite && desktopInviteWillShow()) {
      const show = () => setEnabled(true);
      window.addEventListener(DESKTOP_INVITE_CLOSED, show, { once: true });
      return () => window.removeEventListener(DESKTOP_INVITE_CLOSED, show);
    }
    setEnabled(true);
  }, [pathname, variant, avoidDesktopInvite]);

  useEffect(() => {
    const el = ins.current;
    // Push once per <ins>; React may run effects twice in development.
    if (!enabled || !el || el.getAttribute("data-adsbygoogle-status")) return;
    try {
      const w = window as Window & { adsbygoogle?: AdsQueue };
      (w.adsbygoogle = w.adsbygoogle || []).push({});
    } catch {
      // An ad request failing must never break the timer.
    }
  }, [enabled]);

  if (!enabled || closed) return null;

  if (variant === "rail" && railSize) {
    return (
      <div
        // Keep Google's own auto side rails from overlapping this unit.
        {...{ "google-side-rail-overlap": "false" }}
        className={`[&:has(ins[data-ad-status=unfilled])]:hidden ${className}`}
        style={railSize}
      >
        {/* AdSense lets visitors close a unit "by clicking a box". The button
            sits above the ad with a gap, never over it or its AdChoices icon,
            so it cannot cause accidental ad clicks. Closing removes the unit
            for this page view only; the next visit shows it again. */}
        <button
          type="button"
          onClick={() => {
            setClosed(true);
            window.dispatchEvent(new Event(AD_CLOSED_EVENT));
          }}
          aria-label={t("close")}
          title={t("close")}
          className="absolute -top-8 end-0 grid h-6 w-6 place-items-center rounded-full text-gray-400 transition-colors hover:bg-black/5 hover:text-gray-700 focus:outline-none focus-visible:ring-2 focus-visible:ring-gray-400 dark:text-gray-500 dark:hover:bg-white/10 dark:hover:text-gray-200"
        >
          <X className="h-3.5 w-3.5" aria-hidden="true" />
        </button>
        <ins
          ref={ins}
          className="adsbygoogle"
          style={{ display: "inline-block", ...railSize }}
          data-ad-client={ADSENSE_CLIENT_ID}
          data-ad-slot={ADSENSE_INLINE_SLOT}
        />
      </div>
    );
  }

  return (
    <div
      className={`w-full [&:has(ins[data-ad-status=unfilled])]:hidden ${className}`}
    >
      <ins
        ref={ins}
        className="adsbygoogle"
        style={{ display: "block" }}
        data-ad-client={ADSENSE_CLIENT_ID}
        data-ad-slot={ADSENSE_INLINE_SLOT}
        data-ad-format="auto"
        data-full-width-responsive="true"
      />
    </div>
  );
}
