import type { Theme } from "@/components/ThemeToggle";

export const themes: Theme[] = ["light", "dark", "auto", "cyberpunk", "sunset"];

export function readStoredTheme(): Theme {
  try {
    const savedTheme = localStorage.getItem("theme");
    return themes.includes(savedTheme as Theme) ? (savedTheme as Theme) : "auto";
  } catch {
    return "auto";
  }
}

/**
 * Put the stored theme on `<html>` (and `<body>` for the two custom themes).
 *
 * One implementation, because two would drift: the inline script in the layout,
 * the route-change sync and the iOS Settings screen all have to leave the
 * document in exactly the same state.
 */
export function applySavedTheme(prefersDark: boolean) {
  const theme = readStoredTheme();
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
