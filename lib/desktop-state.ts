import {
  calculateTimelineProgress,
  calculateTimelinePayRatio,
  getShiftStartAtMs,
  getShiftEndAtMs,
  getShiftRemainingMs,
  getActiveBreakEndAtMs,
  isValidShiftTimeline,
  type ShiftTimeline,
} from "./countdown";

const IS_DESKTOP_BUILD = process.env.NEXT_PUBLIC_BUILD_TARGET === "desktop";

export const DESKTOP_STORE_PATH = "desktop-state.json";
export const DESKTOP_COUNTDOWN_KEY = "countdown";

export type DesktopNotificationMode = "off" | "simple" | "milestones";
export type DesktopMiniSkin = "standard" | "woodfish";

export interface DesktopNotificationMessages {
  milestone50: string[];
  milestone75: string[];
  milestone90: string[];
  milestone95: string[];
  milestone100: string[];
}

export interface DesktopCountdownState extends ShiftTimeline {
  running: boolean;
  nextShift: ShiftTimeline | null;
  notificationMode: DesktopNotificationMode;
  notificationTitle: string;
  notificationMessages: DesktopNotificationMessages;
  showSalary: boolean;
  hideEarnings: boolean;
  dailySalary: number | null;
  lang: string;
  countdownNotStarted: string;
  nextShiftLabel: string;
  lunchStartNotification: string;
  lunchEndNotification: string;
  lunchNotificationEnabled: boolean;
  lunchEndNotificationEnabled: boolean;
  microBreakEnabled: boolean;
  microBreakIntervalMinutes: number;
  /** 轮换用的健康提醒文案；喝水与起身混在同一个池子里。 */
  microBreakMessages: string[];
  miniSkin: DesktopMiniSkin;
  woodfishSoundEnabled: boolean;
  /** 迷你面板眼睛按钮的无障碍描述，随界面语言走。 */
  showEarningsLabel: string;
  hideEarningsLabel: string;
}

export interface DesktopCountdownView {
  time: string;
  progress: number;
  earned: number | null;
  phase: "idle" | "before" | "working" | "break" | "between" | "done";
}

const EMPTY_STATE: DesktopCountdownState = {
  segments: [],
  plannedEndAtMs: 0,
  overtimeEndAtMs: null,
  running: false,
  nextShift: null,
  notificationMode: "off",
  notificationTitle: "Off work reminder",
  notificationMessages: {
    milestone50: ["Halfway there."],
    milestone75: ["The hardest part is behind you."],
    milestone90: ["Almost there."],
    milestone95: ["Just a little longer."],
    milestone100: ["Off work time!"],
  },
  showSalary: false,
  hideEarnings: false,
  dailySalary: null,
  lang: "en",
  countdownNotStarted: "Countdown not started",
  nextShiftLabel: "Next shift in __TIME__",
  lunchStartNotification: "Lunch break has started. The countdown is paused.",
  lunchEndNotification: "Lunch break is over. Ready when you are.",
  lunchNotificationEnabled: false,
  lunchEndNotificationEnabled: false,
  microBreakEnabled: false,
  microBreakIntervalMinutes: 60,
  microBreakMessages: [
    "You've been at it for {{minutes}} minutes. Go get some water.",
    "{{minutes}} minutes straight. Stand up and stretch.",
  ],
  miniSkin: "standard",
  woodfishSoundEnabled: false,
  showEarningsLabel: "Show amount",
  hideEarningsLabel: "Hide amount",
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
  countdownNotStarted = "Countdown not started",
  labels?: { showEarnings: string; hideEarnings: string }
): DesktopCountdownState {
  // 停止状态下眼睛按钮不显示，但把标签一起带上，免得「有的字段本地化、
  // 有的不本地化」这种不对称留在状态里让人猜。
  return {
    ...EMPTY_STATE,
    lang,
    countdownNotStarted,
    ...(labels && {
      showEarningsLabel: labels.showEarnings,
      hideEarningsLabel: labels.hideEarnings,
    }),
  };
}

export async function writeDesktopCountdownState(
  state: DesktopCountdownState
): Promise<void> {
  const store = await getDesktopStore();
  if (!store) return;
  await store.set(DESKTOP_COUNTDOWN_KEY, state);
}

type PersistedDesktopCountdownState = Partial<DesktopCountdownState> & {
  /** 3.0.x Store 迁移字段，只读不再写。 */
  startAtMs?: number;
  endAtMs?: number;
  /** 3.0.x 通知字段，只用于迁移。 */
  reminder?: boolean;
  leadReminderArmed?: boolean;
  leadNotificationBody?: string;
  completionNotificationBody?: string;
};

/**
 * 把 3.0.x 的单段快照提升为 3.1 分段模型。迁移只把既有绝对时间戳包成一个
 * segment，不推导跨夜或工作日，因此没有把业务规则复制到持久化层。
 */
export function normalizeDesktopCountdownState(
  persisted: PersistedDesktopCountdownState
): DesktopCountdownState {
  const {
    startAtMs,
    endAtMs,
    reminder,
    leadReminderArmed: _leadReminderArmed,
    leadNotificationBody: _leadNotificationBody,
    completionNotificationBody: _completionNotificationBody,
    ...current
  } = persisted;
  const merged: DesktopCountdownState = {
    ...EMPTY_STATE,
    ...current,
    segments: Array.isArray(current.segments) ? current.segments : [],
    overtimeEndAtMs: current.overtimeEndAtMs ?? null,
    notificationMode:
      current.notificationMode ?? (reminder ? "simple" : "off"),
    notificationMessages: {
      ...EMPTY_STATE.notificationMessages,
      ...current.notificationMessages,
    },
    microBreakMessages:
      Array.isArray(current.microBreakMessages) &&
      current.microBreakMessages.length > 0
        ? current.microBreakMessages
        : EMPTY_STATE.microBreakMessages,
  };
  merged.nextShift =
    merged.nextShift && isValidShiftTimeline(merged.nextShift)
      ? merged.nextShift
      : null;

  if (isValidShiftTimeline(merged)) return merged;

  if (
    Number.isFinite(startAtMs) &&
    Number.isFinite(endAtMs) &&
    (endAtMs ?? 0) > (startAtMs ?? 0)
  ) {
    return {
      ...merged,
      segments: [{ startAtMs: startAtMs!, endAtMs: endAtMs! }],
      plannedEndAtMs: endAtMs!,
      overtimeEndAtMs: null,
    };
  }

  return {
    ...merged,
    segments: [],
    plannedEndAtMs: 0,
    overtimeEndAtMs: null,
    running: false,
  };
}

export async function readDesktopCountdownState(): Promise<DesktopCountdownState | null> {
  const store = await getDesktopStore();
  if (!store) return null;
  const persisted = await store.get<PersistedDesktopCountdownState>(
    DESKTOP_COUNTDOWN_KEY
  );
  return persisted ? normalizeDesktopCountdownState(persisted) : null;
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
  return store.onKeyChange<PersistedDesktopCountdownState>(
    DESKTOP_COUNTDOWN_KEY,
    (value) => listener(value ? normalizeDesktopCountdownState(value) : null)
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
  if (!state?.running || !isValidShiftTimeline(state)) {
    return { time: "--:--:--", progress: 0, earned: null, phase: "idle" };
  }

  const progress = calculateTimelineProgress(state, nowMs);
  const startAtMs = getShiftStartAtMs(state);
  const endAtMs = getShiftEndAtMs(state);
  const breakEndAtMs = getActiveBreakEndAtMs(state, nowMs);
  let phase: DesktopCountdownView["phase"] = "working";
  let time = formatDesktopDuration(getShiftRemainingMs(state, nowMs));
  if (nowMs < startAtMs) {
    phase = "before";
    time = formatDesktopDuration(startAtMs - nowMs);
  } else if (breakEndAtMs !== null) {
    // 午休时下班倒计时是冻住的，显示它等于让界面看起来卡死；
    // 改成距午休结束还有多久，进度条那边再用掠光表示「在待命」。
    phase = "break";
    time = formatDesktopDuration(breakEndAtMs - nowMs);
  } else if (nowMs >= endAtMs) {
    const nextStart = state.nextShift
      ? getShiftStartAtMs(state.nextShift)
      : 0;
    if (nextStart > nowMs) {
      phase = "between";
      time = formatDesktopDuration(nextStart - nowMs);
    } else {
      phase = "done";
      time = "0:00:00";
    }
  }
  const earned =
    state.showSalary && !state.hideEarnings && state.dailySalary !== null
      ? state.dailySalary * calculateTimelinePayRatio(state, nowMs)
      : null;

  return {
    time,
    progress,
    earned,
    phase,
  };
}

export interface MiniWindowSettings {
  platform: "macos" | "windows" | "other";
  alwaysOnTop: boolean;
}

export interface DesktopGlobalShortcutSettings {
  enabled: boolean;
  accelerator: string;
}

export async function getDesktopGlobalShortcutSettings(): Promise<DesktopGlobalShortcutSettings> {
  const { invoke } = await import("@tauri-apps/api/core");
  return invoke<DesktopGlobalShortcutSettings>("get_global_shortcut_settings");
}

export async function updateDesktopGlobalShortcutSettings(
  settings: DesktopGlobalShortcutSettings
): Promise<DesktopGlobalShortcutSettings> {
  const { invoke } = await import("@tauri-apps/api/core");
  return invoke<DesktopGlobalShortcutSettings>(
    "update_global_shortcut_settings",
    { enabled: settings.enabled, accelerator: settings.accelerator }
  );
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

export async function toggleDesktopFloatingTimer(): Promise<void> {
  if (!IS_DESKTOP_BUILD) return;
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("toggle_floating_timer");
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

/** 迷你窗工具条上的主窗口按钮：显示 ↔ 隐藏来回切。 */
export async function toggleDesktopMainWindow(): Promise<void> {
  if (!IS_DESKTOP_BUILD) return;
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("toggle_main_window_visibility");
}

/** 迷你窗工具条上的皮肤切换；与设置页共享同一个 miniSkin。 */
export async function toggleDesktopMiniSkin(): Promise<void> {
  if (!IS_DESKTOP_BUILD) return;
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("toggle_mini_skin");
}

/** 迷你窗工具条上的声音开关；与设置页共享同一个 woodfishSoundEnabled。 */
export async function toggleDesktopWoodfishSound(): Promise<void> {
  if (!IS_DESKTOP_BUILD) return;
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("toggle_woodfish_sound");
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

export interface DesktopMenuLabels {
  show: string;
  mini: string;
  quit: string;
  file: string;
  edit: string;
  view: string;
  window: string;
  help: string;
  about: string;
  services: string;
  hideApp: string;
  hideOthers: string;
  closeWindow: string;
  undo: string;
  redo: string;
  cut: string;
  copy: string;
  paste: string;
  selectAll: string;
  toggleFullScreen: string;
  minimize: string;
  zoom: string;
  bringAllToFront: string;
}

export async function updateDesktopMenus(
  labels: DesktopMenuLabels
): Promise<void> {
  if (!IS_DESKTOP_BUILD) return;
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("update_desktop_menus", { labels });
}

export async function stopDesktopCountdown(
  lang = "en",
  countdownNotStarted = "Countdown not started",
  labels?: { showEarnings: string; hideEarnings: string }
): Promise<void> {
  if (!IS_DESKTOP_BUILD) return;
  await writeDesktopCountdownState(
    emptyDesktopCountdownState(lang, countdownNotStarted, labels)
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
