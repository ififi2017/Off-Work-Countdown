export type BuildTarget = "web" | "desktop";

// next.config.mjs validates BUILD_TARGET and injects this public value. Keep a
// defensive Web fallback for tests and tooling that import client modules
// without running a Next build.
const injectedTarget = process.env.NEXT_PUBLIC_BUILD_TARGET;

export const BUILD_TARGET: BuildTarget =
  injectedTarget === "desktop" ? "desktop" : "web";

export const IS_WEB_BUILD = BUILD_TARGET === "web";
export const IS_DESKTOP_BUILD = BUILD_TARGET === "desktop";
