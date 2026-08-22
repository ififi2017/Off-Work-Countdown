export type BuildTarget = "web" | "desktop" | "mobile";

// next.config.mjs validates BUILD_TARGET and injects this public value. Keep a
// defensive Web fallback for tests and tooling that import client modules
// without running a Next build.
const injectedTarget = process.env.NEXT_PUBLIC_BUILD_TARGET;

export const BUILD_TARGET: BuildTarget =
  injectedTarget === "desktop" || injectedTarget === "mobile"
    ? injectedTarget
    : "web";

export const IS_WEB_BUILD = BUILD_TARGET === "web";
export const IS_DESKTOP_BUILD = BUILD_TARGET === "desktop";
export const IS_MOBILE_BUILD = BUILD_TARGET === "mobile";
export const IS_STATIC_SHELL_BUILD = !IS_WEB_BUILD;
