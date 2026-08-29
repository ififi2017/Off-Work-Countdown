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
import {
  buildShiftReminders,
  shiftRemindersRevision,
  type ReminderMilestoneMessages,
  type ReminderMilestoneTitles,
  type ReminderNotificationMode,
  type ShiftReminder,
} from "./reminders";
import {
  defaultLocale,
  getBaseLanguage,
  locales,
  type Locale,
} from "../i18n-config";

const IS_DESKTOP_BUILD = process.env.NEXT_PUBLIC_BUILD_TARGET === "desktop";
const IS_GITHUB_DESKTOP_BUILD =
  IS_DESKTOP_BUILD &&
  process.env.NEXT_PUBLIC_DESKTOP_CHANNEL === "github";
const IS_MSSTORE_BUILD =
  IS_DESKTOP_BUILD &&
  process.env.NEXT_PUBLIC_DESKTOP_CHANNEL === "msstore";
const IS_MAC_APP_STORE_BUILD =
  IS_DESKTOP_BUILD &&
  process.env.NEXT_PUBLIC_DESKTOP_CHANNEL === "macappstore";

export const DESKTOP_STORE_PATH = "desktop-state.json";
export const DESKTOP_COUNTDOWN_KEY = "countdown";
/** 改名说明只对「更新前就已经有快照」的桌面用户弹一次。 */
export const DESKTOP_BRAND_RENAME_NOTICE_KEY = "brandRenameNoticeSeen";

export function shouldOfferBrandRenameNotice({
  noticeSeen,
  hadExistingCountdown,
}: {
  noticeSeen: boolean;
  hadExistingCountdown: boolean;
}): boolean {
  return hadExistingCountdown && !noticeSeen;
}

// 这三个形状的唯一定义在 lib/reminders.ts —— 提醒文案最终是给那个纯函数消费的，
// 各自声明一份迟早会漂。这里只保留桌面端惯用的名字。
export type DesktopNotificationMode = ReminderNotificationMode;
export type DesktopMiniSkin = "standard" | "woodfish";

export type DesktopNotificationMessages = ReminderMilestoneMessages;

/**
 * 里程碑通知的标题。带上剩余百分比，否则 90% 和 95% 两条只有措辞差别，
 * 看不出自己走到哪儿了。由 JS 侧按当前语言排好版推过来。
 */
export type DesktopNotificationTitles = ReminderMilestoneTitles;

export interface DesktopCountdownState extends ShiftTimeline {
  /** 共享偏好有明确写入来源；0 表示 3.1.5 及更早版本留下的旧快照。 */
  preferencesVersion: number;
  running: boolean;
  nextShift: ShiftTimeline | null;
  notificationMode: DesktopNotificationMode;
  notificationTitle: string;
  notificationTitles: DesktopNotificationTitles;
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

export type DesktopIdlePreferences = Pick<
  DesktopCountdownState,
  "showSalary" | "hideEarnings" | "miniSkin" | "woodfishSoundEnabled"
>;

/** 旧快照缺少偏好字段时会被默认值补齐，只有带版本的新快照才可覆盖本地偏好。 */
export function hasAuthoritativeDesktopPreferences(
  state: Pick<DesktopCountdownState, "preferencesVersion">
): boolean {
  return state.preferencesVersion >= 1;
}

const EMPTY_STATE: DesktopCountdownState = {
  preferencesVersion: 0,
  segments: [],
  plannedEndAtMs: 0,
  overtimeEndAtMs: null,
  running: false,
  nextShift: null,
  notificationMode: "off",
  notificationTitle: "Off work reminder",
  notificationTitles: {
    milestone50: "50% left today",
    milestone75: "25% left today",
    milestone90: "10% left today",
    milestone95: "5% left today",
    milestone100: "Off work time!",
  },
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
  miniSkin: "woodfish",
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
    const storePathPromise = IS_MAC_APP_STORE_BUILD
      ? import("@tauri-apps/api/core").then(({ invoke }) =>
          invoke<string>("get_desktop_store_path")
        )
      : Promise.resolve(DESKTOP_STORE_PATH);
    storePromise = Promise.all([
      import("@tauri-apps/plugin-store"),
      storePathPromise,
    ])
      .then(([{ load }, storePath]) => load(storePath, { autoSave: 100 }))
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
  labels?: { showEarnings: string; hideEarnings: string },
  preferences?: DesktopIdlePreferences
): DesktopCountdownState {
  // 停止状态下眼睛按钮不显示，但隐藏偏好仍必须留在共享 Store 里。否则用户
  // 返回设置或重启应用时，空快照会把隐藏状态覆盖成默认的「显示」。
  return {
    ...EMPTY_STATE,
    ...preferences,
    preferencesVersion: 1,
    lang,
    countdownNotStarted,
    ...(labels && {
      showEarningsLabel: labels.showEarnings,
      hideEarningsLabel: labels.hideEarnings,
    }),
  };
}

/**
 * 快照有效期的下界，只为满足「过期必须晚于生成」这条不变量。
 * 取得很小是刻意的：取大了会把有效期推过真实边界，例如下次上班只剩 20 分钟时
 * 反而声称还能用一小时。
 */
const WIDGET_SNAPSHOT_MIN_VALIDITY_MS = 60 * 1000;
/** 没有可依据的下一个边界时的兜底有效期。 */
const WIDGET_SNAPSHOT_IDLE_VALIDITY_MS = 24 * 60 * 60 * 1000;

/**
 * 快照活到哪一刻。
 *
 * ⚠️ 别写成 `max(生成时刻 + 1h, 班次结束 + 1h)`。那个式子在**下班之后**生成时会
 * 塌缩：此时前一项恒大于后一项，有效期退化成「从现在起一小时」。而
 * writeDesktopCountdownState 只在班次/偏好变化时被调用，不是定时器——于是下班一
 * 小时后小组件就翻成「打开应用以刷新」的空态，哪怕应用开着、哪怕「今日已下班」
 * 依然完全正确。反差最明显的是 running=false 反而能拿到 24 小时。
 *
 * 正确的下一个边界是**下次上班时间**：done 相位一路倒数到那时，与主界面的
 * 「距下次上班」一致。
 */
function widgetSnapshotExpiryMs(
  state: DesktopCountdownState,
  generatedAtMs: number
): number {
  if (!state.running || !isValidShiftTimeline(state)) {
    return generatedAtMs + WIDGET_SNAPSHOT_IDLE_VALIDITY_MS;
  }

  const nextShiftStartAtMs =
    state.nextShift && isValidShiftTimeline(state.nextShift)
      ? getShiftStartAtMs(state.nextShift)
      : null;
  // 内容保持正确的下一个边界就是下次上班：在那之前，「工作中」和「今日已下班」
  // 都还成立；到了那一刻，班次有没有真的开始只有主应用说了算，小组件不该替它
  // 猜，所以到期切空态。下次上班未知（未配置工作日，或 14 天内没有工作日）时
  // 退回兜底值，而不是让有效期缩回一小时。
  const boundaryAtMs =
    nextShiftStartAtMs !== null && nextShiftStartAtMs > generatedAtMs
      ? nextShiftStartAtMs
      : generatedAtMs + WIDGET_SNAPSHOT_IDLE_VALIDITY_MS;

  return Math.max(
    generatedAtMs + WIDGET_SNAPSHOT_MIN_VALIDITY_MS,
    boundaryAtMs
  );
}

/**
 * 落盘时附加的派生字段。
 *
 * 与 WidgetSnapshot 同一个套路：业务规则留在前端投影，消费方只读结果。
 * Rust 的托盘计时器据此判断「到点了没」，不再自己从班次推导提醒时刻——
 * 见 lib/reminders.ts 开头。
 *
 * 刻意不进 `DesktopCountdownState`：那是界面构造的输入形状，多一个必填字段
 * 就要在每个构造点手工填一次，而这两个值永远只能由 state 本身算出来。
 */
type PersistedWithReminders = DesktopCountdownState & {
  reminders: ShiftReminder[];
  remindersRevision: string;
};

function projectReminders(state: DesktopCountdownState): PersistedWithReminders {
  const shift = state.running ? state : null;
  return {
    ...state,
    reminders: buildShiftReminders(shift, {
      mode: state.notificationMode,
      fallbackTitle: state.notificationTitle,
      milestoneTitles: state.notificationTitles,
      milestoneMessages: state.notificationMessages,
      lunchStartEnabled: state.lunchNotificationEnabled,
      lunchStartBody: state.lunchStartNotification,
      lunchEndEnabled: state.lunchEndNotificationEnabled,
      lunchEndBody: state.lunchEndNotification,
      microBreakEnabled: state.microBreakEnabled,
      microBreakIntervalMinutes: state.microBreakIntervalMinutes,
      microBreakMessages: state.microBreakMessages,
    }),
    remindersRevision: shiftRemindersRevision(shift),
  };
}

export async function writeDesktopCountdownState(
  state: DesktopCountdownState
): Promise<void> {
  const store = await getDesktopStore();
  if (!store) return;
  await store.set(DESKTOP_COUNTDOWN_KEY, projectReminders(state));

  if (IS_MAC_APP_STORE_BUILD) {
    // WidgetSnapshot 由前端业务层投影；Rust 只负责把 JSON 原子写进 App Group。
    // 小组件同步失败不能回滚已经成功的主应用 Store 写入。
    try {
      const generatedAtMs = Date.now();
      const { createWidgetSnapshot, serializeWidgetSnapshot } = await import(
        "./widget-snapshot"
      );
      const snapshot = createWidgetSnapshot({
        running: state.running,
        shift: state.running ? state : null,
        nextShift: state.running ? state.nextShift : null,
        locale: state.lang,
        generatedAtMs,
        expiresAtMs: widgetSnapshotExpiryMs(state, generatedAtMs),
      });
      const { invoke } = await import("@tauri-apps/api/core");
      await invoke("write_widget_snapshot", {
        snapshotJson: serializeWidgetSnapshot(snapshot),
      });
    } catch {
      // 未配置 App Group 的本地包仍可运行主应用；Widget 会显示保守空态。
    }
  }
}

type PersistedDesktopCountdownState = Partial<DesktopCountdownState> & {
  /** 写盘时投影出的派生字段，读回时丢弃。 */
  reminders?: ShiftReminder[];
  remindersRevision?: string;
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
    // 派生字段只在写盘那一刻投影（见 projectReminders），读回时丢掉：
    // 留在内存里的那份永远是上一次写盘时的快照，早晚会被误当成当前值。
    reminders: _reminders,
    remindersRevision: _remindersRevision,
    ...current
  } = persisted;
  const merged: DesktopCountdownState = {
    ...EMPTY_STATE,
    ...current,
    segments: Array.isArray(current.segments) ? current.segments : [],
    overtimeEndAtMs: current.overtimeEndAtMs ?? null,
    notificationMode:
      current.notificationMode ?? (reminder ? "simple" : "off"),
    notificationTitles: {
      ...EMPTY_STATE.notificationTitles,
      ...current.notificationTitles,
    },
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
 * 必须在本会话第一次写入 countdown 之前调用。新装此时还没有快照，
 * 当场记下「不必再弹」，否则第二次启动会把刚写下的快照当成存量用户。
 */
export async function loadBrandRenameNoticeOffer(): Promise<boolean> {
  const store = await getDesktopStore();
  if (!store) return false;
  const noticeSeen =
    (await store.get<boolean>(DESKTOP_BRAND_RENAME_NOTICE_KEY)) === true;
  if (noticeSeen) return false;
  const countdown = await store.get(DESKTOP_COUNTDOWN_KEY);
  if (countdown != null) return true;
  await store.set(DESKTOP_BRAND_RENAME_NOTICE_KEY, true);
  return false;
}

export async function markBrandRenameNoticeSeen(): Promise<void> {
  const store = await getDesktopStore();
  if (!store) return;
  await store.set(DESKTOP_BRAND_RENAME_NOTICE_KEY, true);
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

/**
 * ⚠️ 必须向下取整，不能用 `Math.ceil`。
 *
 * 应用里有四个地方显示同一个倒计时：主窗口、迷你窗、托盘/原生面板、桌面小组件。
 * 小组件由系统的 `Text(date, style: .timer)` 渲染，**我们改不了它的取整方式**，
 * 而它与主窗口一致（都相当于向下取整）。这里原本用 ceil，于是只要剩余毫秒不是
 * 整千——也就是几乎总是——迷你窗就恒定比另外两处多显示一秒。实测截图里主窗口和
 * 小组件同为 12:22:13，迷你窗却是 12:22:14。
 *
 * 这与计时器精度无关：ceil 和 floor 的差值是恒定的 1，对齐计时器解决不了。
 */
export function formatDesktopDuration(remainingMs: number): string {
  const totalSeconds = Math.max(0, Math.floor(remainingMs / 1000));
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
export const UPDATE_MIRROR_HOST = IS_GITHUB_DESKTOP_BUILD
  ? "gh-proxy.com"
  : "";

/**
 * 直连 GitHub 下载失败后，改走镜像清单重新检查、下载并安装更新。
 *
 * 整条链路在 Rust 侧完成：JS 的 `check()` 无法改写安装包地址（`proxy` 参数是
 * HTTP 代理，而镜像是 URL 前缀重写）。安装包的 minisign 签名照常校验。
 */
export async function installDesktopUpdateViaMirror(): Promise<void> {
  if (!IS_GITHUB_DESKTOP_BUILD) return;
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("install_update_via_mirror");
}

/**
 * 打开本应用的微软商店详情页，供商店版的「检查更新」使用。
 *
 * 走 Rust 命令而不是 `openUrl`：`ms-windows-store:` 不是 http scheme，前端那条
 * 路要在 capability 白名单里逐条声明。见 docs/PLAN-MSSTORE.md 决策 2。
 */
export async function openMicrosoftStoreListing(): Promise<void> {
  if (!IS_MSSTORE_BUILD) return;
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("open_microsoft_store_listing");
}

/** Windows 自绘标题栏：最小化。 */
export async function minimizeDesktopMainWindow(): Promise<void> {
  if (!IS_DESKTOP_BUILD) return;
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("minimize_main_window");
}

/** Windows 自绘标题栏：关闭（隐藏，不退出）。 */
export async function hideDesktopMainWindow(): Promise<void> {
  if (!IS_DESKTOP_BUILD) return;
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("hide_main_window");
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
  /** macOS 菜单栏最左侧的应用名与「关于」面板的名称。 */
  appName: string;
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

/**
 * 操作系统当前的界面语言，归一到本项目支持的 locale。
 *
 * 托盘、macOS 应用菜单和「关于」面板都用它，而不是用户在应用内选的语言：这些
 * 是操作系统的外壳，应当和系统其余部分说同一种语言。应用名同理，只不过那条走
 * 的是 bundle 里本地化的 CFBundleName / CFBundleDisplayName（见
 * scripts/generate-macos-lproj.mjs），同样跟随系统语言。
 *
 * 取不到时回退默认语言，让调用方不必各自兜底。
 */
export async function getDesktopSystemLocale(): Promise<string> {
  if (!IS_DESKTOP_BUILD) return defaultLocale;
  try {
    const { locale } = await import("@tauri-apps/plugin-os");
    const systemLocale = await locale();
    if (!systemLocale) return defaultLocale;
    const resolved = getBaseLanguage(systemLocale);
    return locales.includes(resolved as Locale) ? resolved : defaultLocale;
  } catch {
    return defaultLocale;
  }
}

export async function updateDesktopMenus(
  labels: DesktopMenuLabels
): Promise<void> {
  if (!IS_DESKTOP_BUILD) return;
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("update_desktop_menus", { labels });
}

export async function stopDesktopCountdown(
  lang: string,
  countdownNotStarted: string,
  labels: { showEarnings: string; hideEarnings: string },
  preferences: DesktopIdlePreferences
): Promise<void> {
  if (!IS_DESKTOP_BUILD) return;
  await writeDesktopCountdownState(
    emptyDesktopCountdownState(lang, countdownNotStarted, labels, preferences)
  );
  const { invoke } = await import("@tauri-apps/api/core");
  await invoke("clear_desktop_countdown_display");
}

/**
 * 自启动的真实状态。
 *
 * `locked` 表示这个开关被系统接管了，应用改不动——只有商店版会出现：MSIX 的
 * `windows.startupTask` 一旦被用户在「设置 → 应用 → 启动」里关掉，应用请求打开
 * 不会报错，只是什么都不会发生。GitHub 版写注册表 Run 键，永远是 false。
 */
export type DesktopAutostartState = {
  enabled: boolean;
  locked: boolean;
};

/**
 * 两条渠道都走同一个 Rust 命令，实现差异在 Rust 侧按 feature 二选一
 * （见 docs/PLAN-MSSTORE.md 决策 3）。前端不需要知道自己跑在哪条上。
 */
export async function getDesktopAutostartState(): Promise<DesktopAutostartState> {
  if (!IS_DESKTOP_BUILD) return { enabled: false, locked: false };
  const { invoke } = await import("@tauri-apps/api/core");
  return invoke<DesktopAutostartState>("get_autostart_state");
}

/**
 * 返回值是写完之后的**真实**状态，不是入参的回声——被系统锁住时它会是
 * `{ enabled: false, locked: true }`。照着返回值渲染，才不会出现「开关是开的、
 * 开机却不启动」。
 */
export async function setDesktopAutostartEnabled(
  enabled: boolean
): Promise<DesktopAutostartState> {
  if (!IS_DESKTOP_BUILD) return { enabled: false, locked: false };
  const { invoke } = await import("@tauri-apps/api/core");
  return invoke<DesktopAutostartState>("set_autostart_enabled", { enabled });
}
