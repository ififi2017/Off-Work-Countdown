"use client";

import { useEffect, useState } from "react";

export type LayoutMode = "portrait" | "landscape" | "wide";

// Both dimensions matter: a phone on its side is 812×375, which is wider than
// an iPad in portrait and must not be given the iPad sidebar.
const WIDE = "(min-width: 768px) and (min-height: 600px)";
// A phone on its side: wide enough for two columns, too short for the portrait
// stack. Height is what actually breaks that layout, so height is what is
// measured — an orientation query would also catch a tall iPad in landscape.
const LANDSCAPE = "(max-height: 520px) and (min-width: 568px)";

/**
 * Which of the three shapes the app is in.
 *
 * Portrait is the design's baseline. The first frame always reports portrait so
 * the static export and the hydrated app agree; the real answer arrives on the
 * effect that follows.
 */
export function useLayoutMode(): LayoutMode {
  const [mode, setMode] = useState<LayoutMode>("portrait");

  useEffect(() => {
    const wide = window.matchMedia(WIDE);
    const landscape = window.matchMedia(LANDSCAPE);
    const resolve = () =>
      setMode(
        wide.matches ? "wide" : landscape.matches ? "landscape" : "portrait"
      );

    resolve();
    wide.addEventListener("change", resolve);
    landscape.addEventListener("change", resolve);
    return () => {
      wide.removeEventListener("change", resolve);
      landscape.removeEventListener("change", resolve);
    };
  }, []);

  return mode;
}
