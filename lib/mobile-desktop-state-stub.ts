// Mobile compiles the same React state owner while its native persistence and
// reminder bridges are introduced. Desktop-only Tauri modules must not enter
// the iOS archive; every call here indicates a missing build-target guard.

const unavailable = (): never => {
  throw new Error("desktop shell API is unavailable in the iOS build");
};

export const UPDATE_MIRROR_HOST = "";
export const emptyDesktopCountdownState = unavailable;
export const hasAuthoritativeDesktopPreferences = unavailable;
export const getDesktopAutostartState = unavailable;
export const getDesktopGlobalShortcutSettings = unavailable;
export const getMiniWindowSettings = unavailable;
export const hideDesktopMainWindow = unavailable;
export const minimizeDesktopMainWindow = unavailable;
export const readDesktopCountdownState = unavailable;
export const loadBrandRenameNoticeOffer = unavailable;
export const markBrandRenameNoticeSeen = unavailable;
export const setDesktopAutostartEnabled = unavailable;
export const updateDesktopGlobalShortcutSettings = unavailable;
export const installDesktopUpdateViaMirror = unavailable;
export const openMicrosoftStoreListing = unavailable;
export const stopDesktopCountdown = unavailable;
export const subscribeToDesktopCountdown = unavailable;
export const toggleDesktopFloatingTimer = unavailable;
export const updateDesktopMenus = unavailable;
export const getDesktopSystemLocale = unavailable;
export const writeDesktopCountdownState = unavailable;
