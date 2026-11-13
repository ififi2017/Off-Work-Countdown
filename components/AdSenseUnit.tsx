"use client";

import { usePathname } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { ADSENSE_CLIENT_ID, ADSENSE_INLINE_SLOT } from "@/lib/ads";
import { adsAllowedHere } from "@/components/AdSenseLoader";

type AdsQueue = unknown[];

/**
 * One responsive in-page ad. Renders nothing on the server, in an installed
 * PWA, on Desktop or off the production host (same gate as AdSenseLoader), so
 * the app shell never gets an empty box. No height is reserved: every placement
 * sits below the first screen or after the main content, so a late ad does not
 * move what the reader is looking at, and a blocked script leaves no gap. The
 * wrapper collapses entirely if Google returns no ad.
 */
export function AdSenseUnit({ className = "" }: { className?: string }) {
  const pathname = usePathname();
  const [enabled, setEnabled] = useState(false);
  const ins = useRef<HTMLModElement>(null);

  useEffect(() => {
    setEnabled(adsAllowedHere(pathname));
  }, [pathname]);

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

  if (!enabled) return null;

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
