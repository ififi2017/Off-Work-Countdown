"use client";

import { usePathname } from "next/navigation";
import { useLayoutEffect } from "react";
import { applySavedTheme } from "@/lib/theme";

/**
 * The inline script in the layout restores the theme for a full page load.
 * Next.js language links use client navigation, though, and reconciling the
 * new route can replace the theme classes on <html> without rerunning that
 * script. Reapply the stored theme before paint after every route change.
 */
export function ThemeRouteSync() {
  const pathname = usePathname();

  useLayoutEffect(() => {
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const syncTheme = () => applySavedTheme(media.matches);

    syncTheme();
    window.addEventListener("storage", syncTheme);
    media.addEventListener("change", syncTheme);

    return () => {
      window.removeEventListener("storage", syncTheme);
      media.removeEventListener("change", syncTheme);
    };
  }, [pathname]);

  return null;
}
