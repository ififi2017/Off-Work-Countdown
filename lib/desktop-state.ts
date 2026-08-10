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
  countdownNotStarted: string;
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
  countdownNotStarted: "Countdown not started",
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

export function emptyDesktopCountdownState(
  lang = "en",
  countdownNotStarted = "Countdown not started"
): DesktopCountdownState {
  return { ...EMPTY_STATE, lang, countdownNotStarted };
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

/**
 * 订阅倒计时状态的变化。
 *
 * store 插件的 `store://change` 事件按「路径」共享同一个 resourceId，因此
 * 主窗口、迷你窗和 Rust 侧的写入彼此都能收到——跨窗口同步只需要这一条通道。
 */
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

export async function toggleDesktopMiniTimer(): Promise<void> {
  if (!IS_DESKTOP_BUILD) return;
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("toggle_mini_timer");
}

export async function hideDesktopMiniTimer(): Promise<void> {
  if (!IS_DESKTOP_BUILD) return;
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("hide_mini_timer");
}

export async function showDesktopMainWindow(): Promise<void> {
  if (!IS_DESKTOP_BUILD) return;
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("show_main_window");
}

/**
 * 更新镜像的主机名，仅用于向用户说明「安装包会从哪里下来」。
 * 真正的地址在 src-tauri/src/lib.rs 的 MIRROR_UPDATER_ENDPOINT，改那边要同步这里。
 */
export const UPDATE_MIRROR_HOST = "gh-proxy.com";

/**
 * 直连 GitHub 下载失败后，改走镜像清单重新检查、下载并安装更新。
 *
 * 整条链路在 Rust 侧完成：JS 的 `check()` 无法改写安装包地址（`proxy` 参数是
 * HTTP 代理，而镜像是 URL 前缀重写）。安装包的 minisign 签名照常校验。
 */
export async function installDesktopUpdateViaMirror(): Promise<void> {
  if (!IS_DESKTOP_BUILD) return;
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("install_update_via_mirror");
}

/**
 * 翻转「隐藏金额」。两个迷你窗都走这里，由 Rust 统一改写 store，
 * 主窗口通过 {@link subscribeToDesktopCountdown} 收到同一份状态。
 */
export async function toggleDesktopSalaryVisibility(): Promise<void> {
  if (!IS_DESKTOP_BUILD) return;
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("toggle_salary_visibility");
}

export async function updateDesktopTrayMenu(labels: {
  show: string;
  mini: string;
  quit: string;
}): Promise<void> {
  if (!IS_DESKTOP_BUILD) return;
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("update_tray_menu", {
    showLabel: labels.show,
    miniLabel: labels.mini,
    quitLabel: labels.quit,
  });
}

export async function stopDesktopCountdown(
  lang = "en",
  countdownNotStarted = "Countdown not started"
): Promise<void> {
  if (!IS_DESKTOP_BUILD) return;
  await writeDesktopCountdownState(
    emptyDesktopCountdownState(lang, countdownNotStarted)
  );
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
