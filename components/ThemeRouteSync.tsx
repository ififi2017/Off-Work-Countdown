"use client";

import { usePathname } from "next/navigation";
import { useLayoutEffect } from "react";
import type { Theme } from "@/components/ThemeToggle";

const themes: Theme[] = ["light", "dark", "auto", "cyberpunk", "sunset"];

function readTheme(): Theme {
  try {
    const savedTheme = localStorage.getItem("theme");
    return themes.includes(savedTheme as Theme) ? (savedTheme as Theme) : "auto";
  } catch {
    return "auto";
  }
}

function applySavedTheme(prefersDark: boolean) {
  const theme = readTheme();
  const root = document.documentElement;

  root.classList.remove("dark", "theme-cyberpunk", "theme-sunset");
  document.body.classList.remove("theme-cyberpunk", "theme-sunset");

  if (theme === "dark" || (theme === "auto" && prefersDark)) {
    root.classList.add("dark");
  } else if (theme === "cyberpunk") {
    root.classList.add("dark", "theme-cyberpunk");
    document.body.classList.add("theme-cyberpunk");
  } else if (theme === "sunset") {
    root.classList.add("theme-sunset");
    document.body.classList.add("theme-sunset");
  }
}

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
