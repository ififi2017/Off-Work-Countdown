const IS_DESKTOP_BUILD = process.env.NEXT_PUBLIC_BUILD_TARGET === "desktop";

export const DESKTOP_STORE_PATH = "desktop-state.json";
export const DESKTOP_COUNTDOWN_KEY = "countdown";

export interface DesktopCountdownState {
  startAtMs: number;
  endAtMs: number;
  running: boolean;
  reminder: boolean;
  leadReminderArmed: boolean;
  notificationTitle: string;
  leadNotificationBody: string;
  completionNotificationBody: string;
  showSalary: boolean;
  hideEarnings: boolean;
  dailySalary: number | null;
  lang: string;
}

export interface DesktopCountdownView {
  time: string;
  progress: number;
  earned: number | null;
}

const EMPTY_STATE: DesktopCountdownState = {
  startAtMs: 0,
  endAtMs: 0,
  running: false,
  reminder: false,
  leadReminderArmed: false,
  notificationTitle: "Off work reminder",
  leadNotificationBody: "Fifteen minutes left!",
  completionNotificationBody: "Off work time!",
  showSalary: false,
  hideEarnings: false,
  dailySalary: null,
  lang: "en",
};

type DesktopStore = Awaited<
  ReturnType<typeof import("@tauri-apps/plugin-store")["load"]>
>;

let storePromise: Promise<DesktopStore> | null = null;

async function getDesktopStore(): Promise<DesktopStore | null> {
  if (!IS_DESKTOP_BUILD) return null;

  if (!storePromise) {
    storePromise = import("@tauri-apps/plugin-store")
      .then(({ load }) => load(DESKTOP_STORE_PATH, { autoSave: 100 }))
      .catch((error) => {
        storePromise = null;
        throw error;
      });
  }
  return storePromise;
}

export function emptyDesktopCountdownState(lang = "en"): DesktopCountdownState {
  return { ...EMPTY_STATE, lang };
}

export async function writeDesktopCountdownState(
  state: DesktopCountdownState
): Promise<void> {
  const store = await getDesktopStore();
  if (!store) return;
  await store.set(DESKTOP_COUNTDOWN_KEY, state);
}

export async function readDesktopCountdownState(): Promise<DesktopCountdownState | null> {
  const store = await getDesktopStore();
  if (!store) return null;
  return (await store.get<DesktopCountdownState>(DESKTOP_COUNTDOWN_KEY)) ?? null;
}

export async function subscribeToDesktopCountdown(
  listener: (state: DesktopCountdownState | null) => void
): Promise<() => void> {
  const store = await getDesktopStore();
  if (!store) return () => {};
  return store.onKeyChange<DesktopCountdownState>(
    DESKTOP_COUNTDOWN_KEY,
    (value) => listener(value ?? null)
  );
}

export function formatDesktopDuration(remainingMs: number): string {
  const totalSeconds = Math.max(0, Math.ceil(remainingMs / 1000));
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  return `${hours}:${minutes.toString().padStart(2, "0")}:${seconds
    .toString()
    .padStart(2, "0")}`;
}

export function getDesktopCountdownView(
  state: DesktopCountdownState | null,
  nowMs: number
): DesktopCountdownView {
  if (!state?.running || state.endAtMs <= state.startAtMs) {
    return { time: "--:--:--", progress: 0, earned: null };
  }

  const duration = state.endAtMs - state.startAtMs;
  const elapsed = Math.min(duration, Math.max(0, nowMs - state.startAtMs));
  const progress = (elapsed / duration) * 100;
  const earned =
    state.showSalary && !state.hideEarnings && state.dailySalary !== null
      ? (state.dailySalary * progress) / 100
      : null;

  return {
    time: formatDesktopDuration(state.endAtMs - nowMs),
    progress,
    earned,
  };
}

export interface MiniWindowSettings {
  platform: "macos" | "windows" | "other";
  alwaysOnTop: boolean;
}

export async function getMiniWindowSettings(): Promise<MiniWindowSettings> {
  const { invoke } = await import("@tauri-apps/api/core");
  return invoke<MiniWindowSettings>("get_mini_window_settings");
}

export async function setMiniAlwaysOnTop(alwaysOnTop: boolean): Promise<void> {
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("set_mini_always_on_top", { alwaysOnTop });
}

export async function stopDesktopCountdown(lang = "en"): Promise<void> {
  if (!IS_DESKTOP_BUILD) return;
  await writeDesktopCountdownState(emptyDesktopCountdownState(lang));
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("clear_desktop_countdown_display");
}

export async function getDesktopAutostartEnabled(): Promise<boolean> {
  if (!IS_DESKTOP_BUILD) return false;
  const { isEnabled } = await import("@tauri-apps/plugin-autostart");
  return isEnabled();
}

export async function setDesktopAutostartEnabled(
  enabled: boolean
): Promise<void> {
  if (!IS_DESKTOP_BUILD) return;
  const { enable, disable } = await import("@tauri-apps/plugin-autostart");
  await (enabled ? enable() : disable());
}
