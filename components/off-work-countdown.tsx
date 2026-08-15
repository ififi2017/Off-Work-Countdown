"use client";

import {
  useState,
  useEffect,
  useCallback,
  useMemo,
  useRef,
  type KeyboardEvent as ReactKeyboardEvent,
} from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { getTextDirection } from "@/i18n-config";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardFooter,
  CardHeader,
} from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import {
  ArrowLeft,
  Github,
  Coins,
  Keyboard,
  Rocket,
  Settings2,
  ExternalLink,
  Info,
  PictureInPicture2,
  RefreshCw,
  Download,
  Globe,
  BellRing,
  ShieldCheck,
  Coffee,
  GlassWater,
  Palette,
  Minus,
  X,
} from "lucide-react";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { motion, AnimatePresence } from "framer-motion";
import { TimeSelector } from "./TimeSelector";
import { LanguageSelector } from "./LanguageSelector";
import { ThemeToggle, Theme } from "./ThemeToggle";
import { CountdownDisplay } from "./CountdownDisplay";
import { Confetti } from "./Confetti";
import { Background } from "./Background";
import { ShareButton } from "./ShareButton";
import "../i18n";
import {
  languageNames,
  defaultLocale,
  desktopLanguageStorageKey,
  getBaseLanguage,
  locales,
  type Locale,
} from "@/i18n-config";
import {
  buildShiftTimeline,
  calculateTimelinePayRatio,
  calculateTimelineProgress,
  extendShiftWithOvertime,
  findNextShiftTimeline,
  resolveOvertimeEndAtMs,
  suggestOvertimeEndAtMs,
  getShiftDurationMs,
  getPlannedShiftDurationMs,
  getShiftEndAtMs,
  getShiftRemainingMs,
  getActiveBreakEndAtMs,
  getShiftStartAtMs,
  getShiftBounds,
  getDailySalary as calculateDailySalary,
  isValidShiftTimeline,
  type ShiftTimeline,
  DEFAULT_MONTHLY_WORKING_DAYS,
  DEFAULT_WORKDAYS,
  parseWorkdays,
  serializeWorkdays,
  isWorkday,
} from "@/lib/countdown";
import { WorkdaySelector } from "./WorkdaySelector";
import { PeriodSummary } from "./PeriodSummary";
import { MicrosoftStoreBadge } from "./MicrosoftStoreBadge";
import { summarize, startOfWeek, startOfYear } from "@/lib/summary";
import { useTranslation } from "react-i18next";
import { resolveContentLocale } from "@/lib/content-locales";
import { decodeShift } from "@/lib/share";
import { track } from "@/lib/track";
import { siteConfig } from "@/config/site";
import {
  requestNotificationPermission,
  requestNotificationPermissionDetailed,
  openDesktopNotificationSettings,
  showNotification,
} from "@/lib/notify";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  emptyDesktopCountdownState,
  hasAuthoritativeDesktopPreferences,
  getDesktopAutostartState,
  getDesktopGlobalShortcutSettings,
  getMiniWindowSettings,
  hideDesktopMainWindow,
  minimizeDesktopMainWindow,
  readDesktopCountdownState,
  setDesktopAutostartEnabled,
  updateDesktopGlobalShortcutSettings,
  installDesktopUpdateViaMirror,
  openMicrosoftStoreListing,
  stopDesktopCountdown,
  subscribeToDesktopCountdown,
  UPDATE_MIRROR_HOST,
  toggleDesktopFloatingTimer,
  updateDesktopMenus,
  writeDesktopCountdownState,
  type DesktopNotificationMode,
  type DesktopMiniSkin,
} from "@/lib/desktop-state";
import {
  formatDesktopShortcut,
  shortcutFromKeyEvent,
} from "@/lib/shortcut";

/** 下班前多久提醒。与 translation.json 里 "reminder" 的文案保持一致。 */
const REMINDER_LEAD_MS = 15 * 60 * 1000;
const notificationPrimerStorageKey = "desktopNotificationPrimerSeen";

/** 由 next.config.mjs 在构建期注入，见 docs/PLAN-M5-TAURI.md 决策 1 与 7。 */
const IS_DESKTOP_BUILD = process.env.NEXT_PUBLIC_BUILD_TARGET === "desktop";

/**
 * 微软商店渠道。更新由商店负责，应用内不做检查也不做下载——MSIX 的安装目录
 * 只读，装不上。更新入口保留，改为深链到商店详情页。
 * 见 docs/PLAN-MSSTORE.md 决策 2。
 */
const IS_MSSTORE_BUILD =
  IS_DESKTOP_BUILD && process.env.NEXT_PUBLIC_DESKTOP_CHANNEL === "msstore";

type DesktopUpdateStatus =
  | "idle"
  | "checking"
  | "available"
  | "predownloading"
  | "predownloaded"
  | "installing"
  | "latest"
  | "unconfigured"
  // 直连 GitHub 失败（检查或下载）：与一般 error 分开，因为只有这种失败
  // 值得引导用户改走镜像；镜像也失败之后才落到 error。
  | "directFailed"
  | "mirrorInstalling"
  | "error";

const getLocalStorageItem = (key: string, defaultValue: string) => {
  if (typeof window !== "undefined") {
    try {
      return localStorage.getItem(key) ?? defaultValue;
    } catch {
      // localStorage can be unavailable in hardened/private browser contexts.
    }
  }
  return defaultValue;
};

const getOptionalLocalStorageItem = (key: string): string | null => {
  if (typeof window === "undefined") return null;
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
};

/** 每个字段独立落盘，避免一个标签页改提醒时顺手覆盖另一个标签页的隐私偏好。 */
function usePersistedSetting(key: string, value: string, enabled: boolean) {
  useEffect(() => {
    if (!enabled) return;
    try {
      localStorage.setItem(key, value);
    } catch {
      // 存储不可用时保留当前会话状态，不让设置页崩溃。
    }
  }, [enabled, key, value]);
}

export interface OffWorkCountdownProps {
  lang: string;
}

interface SalarySettingsProps {
  desktop?: boolean;
  /** 快捷入口的滚动锚点与高亮标记。 */
  anchor?: string;
  highlighted?: boolean;
  enabled: boolean;
  onEnabledChange: (enabled: boolean) => void;
  salaryType: "monthly" | "daily";
  onSalaryTypeChange: (value: "monthly" | "daily") => void;
  salaryAmount: string;
  onSalaryAmountChange: (value: string) => void;
  monthlyWorkingDays: string;
  onMonthlyWorkingDaysChange: (value: string) => void;
  maskAmountField: boolean;
  onMaskAmountFieldChange: (masked: boolean) => void;
}

function SalarySettings({
  desktop = false,
  anchor,
  highlighted = false,
  enabled,
  onEnabledChange,
  salaryType,
  onSalaryTypeChange,
  salaryAmount,
  onSalaryAmountChange,
  monthlyWorkingDays,
  onMonthlyWorkingDaysChange,
  maskAmountField,
  onMaskAmountFieldChange,
}: SalarySettingsProps) {
  const { t } = useTranslation();

  return (
    <section
      data-setting={anchor}
      className={`${
        desktop
          ? "rounded-xl border border-gray-200/80 bg-white/35 p-3 shadow-sm dark:border-gray-700 dark:bg-black/10"
          : "border-t border-gray-200 pt-3 dark:border-gray-700"
      } ${highlighted ? "setting-highlight" : ""}`}
    >
      <div className="flex items-center justify-between">
        <Label className="flex items-center gap-2 dark:text-gray-200">
          <Coins size={16} />
          {t("salarySettings")}
        </Label>
        <Switch checked={enabled} onCheckedChange={onEnabledChange} />
      </div>

      <AnimatePresence>
        {enabled && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: "auto", opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            className="space-y-3 overflow-hidden pt-3"
          >
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label className="text-xs dark:text-gray-400">
                  {t("salaryType")}
                </Label>
                <Select
                  value={salaryType}
                  onValueChange={(value) =>
                    onSalaryTypeChange(value as "monthly" | "daily")
                  }
                >
                  <SelectTrigger className="w-full dark:border-gray-700 dark:bg-gray-800 dark:text-white">
                    <SelectValue placeholder={t("salaryType")} />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="monthly">{t("monthly")}</SelectItem>
                    <SelectItem value="daily">{t("daily")}</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1.5">
                <Label className="text-xs dark:text-gray-400">
                  {t("amount")}
                </Label>
                <input
                  type="number"
                  min="0"
                  step="0.01"
                  className="w-full rounded-md border bg-background p-2 text-sm dark:border-gray-700 dark:bg-gray-800 dark:text-white"
                  value={maskAmountField ? "" : salaryAmount}
                  onFocus={() => onMaskAmountFieldChange(false)}
                  onBlur={() => onMaskAmountFieldChange(true)}
                  onChange={(event) => {
                    onMaskAmountFieldChange(false);
                    onSalaryAmountChange(event.target.value);
                  }}
                  placeholder={maskAmountField ? "****" : "0.00"}
                />
              </div>
            </div>
            {salaryType === "monthly" && (
              <div className="space-y-1.5">
                <Label className="text-xs dark:text-gray-400">
                  {t("monthlyWorkingDays")}
                </Label>
                <input
                  type="number"
                  min="1"
                  max="31"
                  step="0.25"
                  className="w-full rounded-md border bg-background p-2 text-sm dark:border-gray-700 dark:bg-gray-800 dark:text-white"
                  value={monthlyWorkingDays}
                  onChange={(event) =>
                    onMonthlyWorkingDaysChange(event.target.value)
                  }
                  placeholder={DEFAULT_MONTHLY_WORKING_DAYS.toString()}
                />
              </div>
            )}
          </motion.div>
        )}
      </AnimatePresence>
    </section>
  );
}

export function OffWorkCountdown({ lang }: OffWorkCountdownProps) {
  const router = useRouter();
  const { t, i18n } = useTranslation();
  const [startTime, setStartTime] = useState("09:00");
  const [endTime, setEndTime] = useState("18:00");
  const [reminder, setReminder] = useState(false);
  const [desktopNotificationMode, setDesktopNotificationMode] =
    useState<DesktopNotificationMode>("off");
  const [workdays, setWorkdays] = useState<number[]>(DEFAULT_WORKDAYS);
  const [showCountdown, setShowCountdown] = useState(false);
  const [showDesktopSettings, setShowDesktopSettings] = useState(false);
  const [timeLeft, setTimeLeft] = useState("");
  const [progress, setProgress] = useState(0);
  const [theme, setTheme] = useState<Theme>("auto");
  const [isMounted, setIsMounted] = useState(false);
  // 用自增计数而不是布尔，见 Confetti 组件的说明。
  const [confettiNonce, setConfettiNonce] = useState(0);
  /**
   * 已经为哪一班庆祝过，按该班的结束时间戳去重，并落盘。
   *
   * 只放在内存里会导致「每次打开应用都重放一次」——晚上十点打开看一眼，
   * 又是一场撒花。一次班次只该庆祝一次。
   */
  const celebratedShiftRef = useRef<number | null>(null);
  /** 下班那一刻窗口不可见时保存班次终点，等用户回来再放。 */
  const celebrationPendingRef = useRef<number | null>(null);
  const [showNextShiftStatus, setShowNextShiftStatus] = useState(false);
  /** 客户端允许提前启动：班次开始前显示距上班还有多久，而不是套用网页版报错。 */
  const [showBeforeShiftStatus, setShowBeforeShiftStatus] = useState(false);
  /** 午休中：倒计时暂停，界面改为显示距午休结束还有多久。 */
  const [onLunchBreak, setOnLunchBreak] = useState(false);
  /** 从主界面快捷入口跳进设置页时，短暂高亮目标分组。 */
  const [highlightedSetting, setHighlightedSetting] = useState<string | null>(
    null
  );
  const [formError, setFormError] = useState("");
  const reminderFiredRef = useRef(false);
  const completionTrackedRef = useRef(false);
  const pendingNotificationActionRef = useRef<null | (() => void)>(null);
  /** 自动检查时保存的 update 对象，供用户确认后下载 / 安装。 */
  const pendingUpdateRef = useRef<{
    version: string;
    currentVersion: string;
    download: () => Promise<void>;
    install: () => Promise<void>;
    downloadAndInstall: () => Promise<void>;
  } | null>(null);

  // Salary state
  const [salaryType, setSalaryType] = useState<"monthly" | "daily">("monthly");
  const [salaryAmount, setSalaryAmount] = useState("");
  const [monthlyWorkingDays, setMonthlyWorkingDays] = useState(
    DEFAULT_MONTHLY_WORKING_DAYS.toString()
  );
  const [showSalary, setShowSalary] = useState(false);
  // 是否运行在没有浏览器外壳的容器里——PWA 独立窗口与 Tauri 桌面端同属此列，
  // 二者都应当去掉浏览器版的外边距、让内容铺满窗口。
  //
  // 桌面端由构建期常量直接判定：构建时已知意味着首帧就是正确布局，不会出现
  // 「先渲染成浏览器版、再跳成铺满版」的闪烁；PWA 仍需运行时探测显示模式。
  const [isAppShell, setIsAppShell] = useState(IS_DESKTOP_BUILD);
  const [hideEarnings, setHideEarnings] = useState(false);
  const [maskAmountField, setMaskAmountField] = useState(true);
  const [activeShift, setActiveShift] = useState<ShiftTimeline | null>(null);
  /** 供只建立一次的 Store 订阅读取当前班次，避免闭包停在挂载那一刻。 */
  const activeShiftRef = useRef<ShiftTimeline | null>(null);
  const [lunchEnabled, setLunchEnabled] = useState(false);
  const [lunchStartTime, setLunchStartTime] = useState("12:00");
  const [lunchDurationMinutes, setLunchDurationMinutes] = useState(60);
  const [lunchStartNotificationEnabled, setLunchStartNotificationEnabled] =
    useState(true);
  const [lunchEndNotificationEnabled, setLunchEndNotificationEnabled] =
    useState(false);
  const [overtimeDialogOpen, setOvertimeDialogOpen] = useState(false);
  const [overtimeEndTime, setOvertimeEndTime] = useState("19:00");
  const [microBreakEnabled, setMicroBreakEnabled] = useState(false);
  const [microBreakIntervalMinutes, setMicroBreakIntervalMinutes] = useState(60);
  const [miniSkin, setMiniSkin] = useState<DesktopMiniSkin>("woodfish");
  const [woodfishSoundEnabled, setWoodfishSoundEnabled] = useState(false);
  /** 让周/年汇总即使在两班之间也能于本地午夜自动换期。 */
  const [calendarDateKey, setCalendarDateKey] = useState("");
  const [desktopStateRestored, setDesktopStateRestored] = useState(
    !IS_DESKTOP_BUILD
  );
  const [launchAtLogin, setLaunchAtLogin] = useState(false);
  // 商店版专有：用户在系统「启动」设置里关掉之后，应用无权改回来。
  // 见 docs/PLAN-MSSTORE.md 决策 3。
  const [launchAtLoginLocked, setLaunchAtLoginLocked] = useState(false);
  const [autostartLoaded, setAutostartLoaded] = useState(!IS_DESKTOP_BUILD);
  const [autostartPending, setAutostartPending] = useState(false);
  const [globalShortcutEnabled, setGlobalShortcutEnabled] = useState(true);
  const [globalShortcutAccelerator, setGlobalShortcutAccelerator] = useState(
    "CommandOrControl+Shift+O"
  );
  const [globalShortcutLoaded, setGlobalShortcutLoaded] = useState(
    !IS_DESKTOP_BUILD
  );
  const [globalShortcutPending, setGlobalShortcutPending] = useState(false);
  const [globalShortcutCapturing, setGlobalShortcutCapturing] = useState(false);
  const [globalShortcutError, setGlobalShortcutError] = useState("");
  const globalShortcutButtonRef = useRef<HTMLButtonElement>(null);
  const [desktopSettingError, setDesktopSettingError] = useState("");
  const [notificationDialog, setNotificationDialog] = useState<
    "primer" | "denied" | null
  >(null);
  const [desktopUpdateStatus, setDesktopUpdateStatus] =
    useState<DesktopUpdateStatus>("idle");
  const [desktopCurrentVersion, setDesktopCurrentVersion] = useState("");
  const [desktopLatestVersion, setDesktopLatestVersion] = useState("");
  // 默认按 macOS 算：平台要等 IPC 返回，而这个值决定标题栏区域的留白。
  // 猜错成 macOS 只是 Windows 上多留 16px 一瞬；猜错成非 macOS 则会让
  // 交通灯在首帧压住标题，那个更难看。
  const [desktopPlatform, setDesktopPlatform] = useState<
    "macos" | "windows" | "other"
  >("macos");

  // 通过分享链接进入：班次来自 URL，而不是本人的设置。这种状态下不写
  // localStorage，否则会把对方的班次覆盖掉访问者自己保存的时间。
  const [isSharedView, setIsSharedView] = useState(false);

  // 本地设置是否已读入 state。持久化必须等它为真才能开始，否则挂载后的第一次
  // 提交里，持久化 effect 读到的还是初始默认值（同一次提交中读取 effect 的
  // setState 尚未生效），会先把 09:00/18:00 写回去覆盖用户已存的时间。
  // 平时下一次渲染会用真实值再写一遍、看似自愈；但分享落地时 isSharedView
  // 随即变真、持久化被跳过，那次错误写入就永久留在了 localStorage 里。
  const [settingsLoaded, setSettingsLoaded] = useState(false);

  // 初始化和语言同步
  useEffect(() => {
    setIsMounted(true);
  }, []);

  useEffect(() => {
    if (!isMounted) return;
    const updateDateKey = () => {
      const now = new Date();
      setCalendarDateKey(
        `${now.getFullYear()}-${now.getMonth() + 1}-${now.getDate()}`
      );
    };
    updateDateKey();
    const timer = window.setInterval(updateDateKey, 60_000);
    return () => window.clearInterval(timer);
  }, [isMounted]);

  // The exported desktop bundle boots from its English entry point. Restore a
  // manual choice, or use the OS locale the first time the app is opened.
  useEffect(() => {
    if (!IS_DESKTOP_BUILD || !isMounted) return;

    let cancelled = false;
    void (async () => {
      let preferred: string | null = null;
      try {
        preferred = localStorage.getItem(desktopLanguageStorageKey);
      } catch {
        // Fall through to the OS locale.
      }

      if (!preferred || !locales.includes(preferred as Locale)) {
        const { locale } = await import("@tauri-apps/plugin-os");
        const systemLocale = await locale();
        const resolved = systemLocale
          ? getBaseLanguage(systemLocale)
          : defaultLocale;
        preferred = locales.includes(resolved as Locale)
          ? resolved
          : defaultLocale;
        try {
          localStorage.setItem(desktopLanguageStorageKey, preferred);
        } catch {
          // Routing does not depend on persistence succeeding.
        }
      }

      if (!cancelled && preferred !== lang) {
        router.replace(`/${preferred}`);
      }
    })().catch(() => {
      // If the OS API is unavailable, keep the exported default language.
    });

    return () => {
      cancelled = true;
    };
  }, [isMounted, lang, router]);

  // 同步 i18n 语言及缓存
  useEffect(() => {
    const normalizedLang = lang || defaultLocale;
    if (i18n.language !== normalizedLang) {
      i18n.changeLanguage(normalizedLang);
    }
    if (typeof window !== "undefined") {
      try {
        localStorage.setItem("i18nextLng", normalizedLang);
        document.cookie = `i18nextLng=${normalizedLang}; path=/; max-age=31536000`;
      } catch {
        // ignore storage errors (private mode, etc.)
      }
    }
  }, [i18n, lang]);

  // 托盘与 macOS 应用菜单由 Rust 创建，但文案跟随前端当前语言。托盘项目
  // 原地更新，macOS 菜单则按同一批文案重建，不需要重启客户端。
  useEffect(() => {
    if (!IS_DESKTOP_BUILD) return;
    setDesktopSettingError("");
    void updateDesktopMenus({
      show: t("trayShowApp"),
      mini: t("trayMiniTimer"),
      quit: t("trayQuit"),
      file: t("menuFile"),
      edit: t("menuEdit"),
      view: t("menuView"),
      window: t("menuWindow"),
      help: t("menuHelp"),
      about: t("menuAbout"),
      services: t("menuServices"),
      hideApp: t("menuHideApp"),
      hideOthers: t("menuHideOthers"),
      closeWindow: t("menuCloseWindow"),
      undo: t("menuUndo"),
      redo: t("menuRedo"),
      cut: t("menuCut"),
      copy: t("menuCopy"),
      paste: t("menuPaste"),
      selectAll: t("menuSelectAll"),
      toggleFullScreen: t("menuToggleFullScreen"),
      minimize: t("menuMinimize"),
      zoom: t("menuZoom"),
      bringAllToFront: t("menuBringAllToFront"),
    }).catch((error) => {
      console.error("Failed to localize desktop menus", error);
      setDesktopSettingError(t("desktopSettingError"));
    });
  }, [lang, t]);

  // 加载本地存储的设置
  useEffect(() => {
    if (isMounted) {
      setStartTime(getLocalStorageItem("startTime", "09:00"));
      setEndTime(getLocalStorageItem("endTime", "18:00"));
      const legacyReminder =
        getLocalStorageItem("reminder", "false") === "true";
      setReminder(legacyReminder);
      const storedNotificationMode = getLocalStorageItem(
        "desktopNotificationMode",
        legacyReminder ? "simple" : "off"
      );
      setDesktopNotificationMode(
        storedNotificationMode === "simple" ||
          storedNotificationMode === "milestones"
          ? storedNotificationMode
          : "off"
      );
      // 这里不能用 getLocalStorageItem 的默认值兜底：空字符串是「一天都不上班」
      // 这个合法状态，与「从未设置过」必须区分，交给 parseWorkdays 处理。
      setWorkdays(
        parseWorkdays(getOptionalLocalStorageItem("workdays"))
      );
      const storedSalaryType = getLocalStorageItem("salaryType", "monthly");
      setSalaryType(storedSalaryType === "daily" ? "daily" : "monthly");
      setSalaryAmount(getLocalStorageItem("salaryAmount", ""));
      const storedMonthlyWorkingDays = Number(
        getLocalStorageItem(
          "monthlyWorkingDays",
          DEFAULT_MONTHLY_WORKING_DAYS.toString()
        )
      );
      setMonthlyWorkingDays(
        Number.isFinite(storedMonthlyWorkingDays) &&
          storedMonthlyWorkingDays > 0 &&
          storedMonthlyWorkingDays <= 31
          ? String(storedMonthlyWorkingDays)
          : DEFAULT_MONTHLY_WORKING_DAYS.toString()
      );
      setShowSalary(getLocalStorageItem("showSalary", "false") === "true");
      setHideEarnings(getLocalStorageItem("hideEarnings", "false") === "true");
      setLunchEnabled(getLocalStorageItem("lunchEnabled", "false") === "true");
      setLunchStartTime(getLocalStorageItem("lunchStartTime", "12:00"));
      const storedLunchDuration = Number(
        getLocalStorageItem("lunchDurationMinutes", "60")
      );
      setLunchDurationMinutes(
        Number.isFinite(storedLunchDuration) && storedLunchDuration > 0
          ? storedLunchDuration
          : 60
      );
      setLunchEndNotificationEnabled(
        getLocalStorageItem("lunchEndNotificationEnabled", "false") === "true"
      );
      setMicroBreakEnabled(
        getLocalStorageItem("microBreakEnabled", "false") === "true"
      );
      const storedMicroBreakInterval = Number(
        getLocalStorageItem("microBreakIntervalMinutes", "60")
      );
      setMicroBreakIntervalMinutes(
        Number.isFinite(storedMicroBreakInterval) &&
          storedMicroBreakInterval > 0
          ? storedMicroBreakInterval
          : 60
      );
      setLunchStartNotificationEnabled(
        getLocalStorageItem("lunchStartNotificationEnabled", "true") === "true"
      );
      setMiniSkin(
        // 木鱼是默认皮肤，所以判据反过来：只有显式存过「简约」才不是木鱼。
        getLocalStorageItem("miniSkin", "woodfish") === "standard"
          ? "standard"
          : "woodfish"
      );
      setWoodfishSoundEnabled(
        getLocalStorageItem("woodfishSoundEnabled", "false") === "true"
      );
      setSettingsLoaded(true);
    }
  }, [isMounted]);

  // 桌面端从 Tauri Store 恢复绝对班次。若 Rust 在休眠后发现连 nextShift 也
  // 已经过期，会把 running 置为 false 但保留旧 segments；前端据此继续计算
  // 再下一工作日，而不是让自动排班永久停止。手动停止写的是空 segments，
  // 因而不会被这里误恢复。
  useEffect(() => {
    if (!IS_DESKTOP_BUILD || !settingsLoaded) return;

    let cancelled = false;
    void readDesktopCountdownState()
      .then((state) => {
        if (cancelled || !state) return;
        const hasAuthoritativePreferences =
          hasAuthoritativeDesktopPreferences(state);
        // 3.1.5 及更早的空快照可能把 hideEarnings 写成默认 false。旧快照只
        // 允许把金额收起，不能把 localStorage 中已隐藏的金额重新公开；新格式
        // 有版本标记后，Store 才能作为主窗与迷你窗之间的双向真源。
        setHideEarnings((current) =>
          hasAuthoritativePreferences
            ? state.hideEarnings
            : current || state.hideEarnings
        );
        if (hasAuthoritativePreferences) {
          setWoodfishSoundEnabled(state.woodfishSoundEnabled);
          setMiniSkin(state.miniSkin);
        }
        const hasUpcomingShift = Boolean(
          state.nextShift &&
            isValidShiftTimeline(state.nextShift) &&
            getShiftStartAtMs(state.nextShift) > Date.now()
        );
        if (!isValidShiftTimeline(state)) {
          return;
        }
        const needsScheduleRecovery =
          !state.running && getShiftEndAtMs(state) <= Date.now();
        if (
          !needsScheduleRecovery &&
          (!state.running ||
            (getShiftEndAtMs(state) <= Date.now() && !hasUpcomingShift))
        ) return;
        setActiveShift({
          segments: state.segments,
          plannedEndAtMs: state.plannedEndAtMs,
          overtimeEndAtMs: state.overtimeEndAtMs,
        });
        setDesktopNotificationMode(state.notificationMode);
        reminderFiredRef.current =
          getShiftEndAtMs(state) - Date.now() <= REMINDER_LEAD_MS;
        setShowCountdown(true);
      })
      .catch(() => {
        // Store 不可用时继续显示主界面；下一次状态写入会再次尝试连接。
      })
      .finally(() => {
        if (!cancelled) setDesktopStateRestored(true);
      });

    return () => {
      cancelled = true;
    };
  }, [settingsLoaded]);

  useEffect(() => {
    if (!IS_DESKTOP_BUILD) return;

    let cancelled = false;
    void getDesktopAutostartState()
      .then((state) => {
        if (cancelled) return;
        setLaunchAtLogin(state.enabled);
        setLaunchAtLoginLocked(state.locked);
      })
      .catch(() => {
        if (!cancelled) setDesktopSettingError(t("desktopSettingError"));
      })
      .finally(() => {
        if (!cancelled) setAutostartLoaded(true);
      });

    void getDesktopGlobalShortcutSettings()
      .then((settings) => {
        if (cancelled) return;
        setGlobalShortcutEnabled(settings.enabled);
        setGlobalShortcutAccelerator(settings.accelerator);
      })
      .catch(() => {
        if (!cancelled) setGlobalShortcutError(t("shortcutUpdateFailed"));
      })
      .finally(() => {
        if (!cancelled) setGlobalShortcutLoaded(true);
      });

    // 在 macOS 上验收 Windows 的窗口外观没有别的办法：那套自绘标题栏只在
    // desktopPlatform === "windows" 时才渲染。开发构建下允许用查询参数强制，
    // 正式包不读它（与迷你窗的 OWC_FORCE_WINDOWS_MINI 同一思路）。
    const forcedPlatform =
      process.env.NODE_ENV === "production"
        ? null
        : new URLSearchParams(window.location.search).get("platform");
    const platformOverride =
      forcedPlatform === "windows" ||
      forcedPlatform === "macos" ||
      forcedPlatform === "other"
        ? forcedPlatform
        : null;
    if (platformOverride) setDesktopPlatform(platformOverride);

    void getMiniWindowSettings()
      .then((settings) => {
        // 覆盖生效时不让真实平台把它顶回去；其余初始化照常进行。
        if (!cancelled && !platformOverride) setDesktopPlatform(settings.platform);
      })
      .catch(() => {
        // The shortcut still works if only its platform-specific label fails.
      });

    void import("@tauri-apps/api/app")
      .then(({ getVersion }) => getVersion())
      .then((version) => {
        if (!cancelled) setDesktopCurrentVersion(version);
      })
      .catch(() => {
        // Version metadata is informative; update checks remain usable without it.
      });

    // 启动时只**检查**更新，不下载：安装包有十几 MB，未经用户同意就占用
    // 带宽，与「关于」页对外承诺的「只有当你主动检查或下载更新时才会访问
    // 网络」相冲突。发现新版本仅把设置按钮点亮，下载由用户点击后触发。
    // 任何失败都静默忽略，不打扰启动流程。
    //
    // 商店版整段跳过：更新由商店负责，这里连一次网络请求都不该发。
    if (!IS_MSSTORE_BUILD) {
      void (async () => {
        try {
          const { check } = await import("@tauri-apps/plugin-updater");
          const update = await check({ timeout: 15_000 });
          if (cancelled) return;
          if (!update) {
            setDesktopUpdateStatus("latest");
            return;
          }
          pendingUpdateRef.current = {
            version: update.version,
            currentVersion: update.currentVersion,
            download: () => update.download(),
            install: () => update.install(),
            downloadAndInstall: () => update.downloadAndInstall(),
          };
          setDesktopCurrentVersion(update.currentVersion);
          setDesktopLatestVersion(update.version);
          setDesktopUpdateStatus("available");
        } catch {
          // 静默失败：不干扰启动，也不弹错误。
        }
      })();
    }

    return () => {
      cancelled = true;
    };
  }, [t]);

  useEffect(() => {
    if (globalShortcutCapturing) globalShortcutButtonRef.current?.focus();
  }, [globalShortcutCapturing]);

  // 分享链接落地：URL 里带合法班次就直接进入倒计时，而不是让对方面对一个
  // 空表单——这是分享闭环里此前缺失的一环。声明顺序在上面的 localStorage
  // 读取之后，因此能覆盖掉刚读出来的本人设置。
  useEffect(() => {
    if (!isMounted) return;

    const params = new URLSearchParams(window.location.search);
    const shift = decodeShift(params.get("s"));
    if (!shift) return;

    setStartTime(shift.start);
    setEndTime(shift.end);
    // 与 handleStart 同样的处理：落地时若已不足 15 分钟就不再提醒，
    // 免得页面刚打开就弹「还有十五分钟」。
    const timeline = buildShiftTimeline(shift.start, shift.end, new Date());
    const endAtMs = getShiftEndAtMs(timeline);
    reminderFiredRef.current = endAtMs - Date.now() <= REMINDER_LEAD_MS;
    setActiveShift({
      ...timeline,
    });
    setShowCountdown(true);
    // 只有明确标记来自分享时才提示，直接手输 ?s= 的不打扰。
    const fromShare = params.get("from") === "share";
    setIsSharedView(fromShare);
    // 分享落地与预设页 CTA 都带 ?s=，靠 from 区分，二者的转化路径不同。
    track(fromShare ? "share_land" : "preset_start");
  }, [isMounted]);

  useEffect(() => {
    if (!isMounted) return;

    const navigatorWithStandalone = window.navigator as Navigator & {
      standalone?: boolean;
    };

    const detectPWA = () => {
      const isStandalone = window.matchMedia("(display-mode: standalone)").matches;
      const isFullscreen = window.matchMedia("(display-mode: fullscreen)").matches;
      const isMinimalUi = window.matchMedia("(display-mode: minimal-ui)").matches;
      const isIOSStandalone = navigatorWithStandalone.standalone === true;
      setIsAppShell(
        IS_DESKTOP_BUILD ||
          isStandalone ||
          isFullscreen ||
          isMinimalUi ||
          isIOSStandalone
      );
    };

    detectPWA();

    const mediaQueries = [
      "(display-mode: standalone)",
      "(display-mode: fullscreen)",
      "(display-mode: minimal-ui)",
    ].map((query) => {
      const mq = window.matchMedia(query);
      mq.addEventListener("change", detectPWA);
      return mq;
    });

    window.addEventListener("appinstalled", detectPWA);
    return () => {
      mediaQueries.forEach((mq) => mq.removeEventListener("change", detectPWA));
      window.removeEventListener("appinstalled", detectPWA);
    };
  }, [isMounted]);

  // 每个设置独立落盘。分享链接只借用别人的开始/结束时间，访问者在分享页上
  // 改的隐私、薪资和提醒偏好仍然是自己的，也必须保存。
  const persistOwnSchedule = settingsLoaded && !isSharedView;
  usePersistedSetting("startTime", startTime, persistOwnSchedule);
  usePersistedSetting("endTime", endTime, persistOwnSchedule);
  usePersistedSetting("reminder", String(reminder), settingsLoaded);
  usePersistedSetting(
    "desktopNotificationMode",
    desktopNotificationMode,
    settingsLoaded
  );
  usePersistedSetting("workdays", serializeWorkdays(workdays), settingsLoaded);
  usePersistedSetting("salaryType", salaryType, settingsLoaded);
  usePersistedSetting("salaryAmount", salaryAmount, settingsLoaded);
  usePersistedSetting("monthlyWorkingDays", monthlyWorkingDays, settingsLoaded);
  usePersistedSetting("showSalary", String(showSalary), settingsLoaded);
  usePersistedSetting("hideEarnings", String(hideEarnings), settingsLoaded);
  usePersistedSetting("lunchEnabled", String(lunchEnabled), settingsLoaded);
  usePersistedSetting("lunchStartTime", lunchStartTime, settingsLoaded);
  usePersistedSetting(
    "lunchDurationMinutes",
    String(lunchDurationMinutes),
    settingsLoaded
  );
  usePersistedSetting(
    "lunchEndNotificationEnabled",
    String(lunchEndNotificationEnabled),
    settingsLoaded
  );
  usePersistedSetting("miniSkin", miniSkin, settingsLoaded);
  usePersistedSetting(
    "woodfishSoundEnabled",
    String(woodfishSoundEnabled),
    settingsLoaded
  );
  usePersistedSetting(
    "microBreakEnabled",
    String(microBreakEnabled),
    settingsLoaded
  );
  usePersistedSetting(
    "microBreakIntervalMinutes",
    String(microBreakIntervalMinutes),
    settingsLoaded
  );
  usePersistedSetting(
    "lunchStartNotificationEnabled",
    String(lunchStartNotificationEnabled),
    settingsLoaded
  );

  // 其他标签页改了某一项时只吸收那一项，避免任一旧标签页随后渲染时用整份
  // 过期 state 覆盖回来。当前标签页处于分享视图时，仍不接管本地班次时间。
  useEffect(() => {
    if (!settingsLoaded) return;
    const updateFromStorage = ({ key, newValue }: StorageEvent) => {
      if (key === null || newValue === null) return;
      const enabled = newValue === "true";
      switch (key) {
        case "startTime":
          if (!isSharedView) setStartTime(newValue);
          break;
        case "endTime":
          if (!isSharedView) setEndTime(newValue);
          break;
        case "reminder":
          setReminder(enabled);
          break;
        case "desktopNotificationMode":
          setDesktopNotificationMode(
            newValue === "simple" || newValue === "milestones"
              ? newValue
              : "off"
          );
          break;
        case "workdays":
          setWorkdays(parseWorkdays(newValue));
          break;
        case "salaryType":
          setSalaryType(newValue === "daily" ? "daily" : "monthly");
          break;
        case "salaryAmount":
          setSalaryAmount(newValue);
          break;
        case "monthlyWorkingDays": {
          const days = Number(newValue);
          if (Number.isFinite(days) && days > 0 && days <= 31) {
            setMonthlyWorkingDays(String(days));
          }
          break;
        }
        case "showSalary":
          setShowSalary(enabled);
          break;
        case "hideEarnings":
          setHideEarnings(enabled);
          break;
        case "lunchEnabled":
          setLunchEnabled(enabled);
          break;
        case "lunchStartTime":
          setLunchStartTime(newValue);
          break;
        case "lunchDurationMinutes": {
          const minutes = Number(newValue);
          if (Number.isFinite(minutes) && minutes > 0) {
            setLunchDurationMinutes(minutes);
          }
          break;
        }
        case "lunchEndNotificationEnabled":
          setLunchEndNotificationEnabled(enabled);
          break;
        case "miniSkin":
          setMiniSkin(newValue === "standard" ? "standard" : "woodfish");
          break;
        case "woodfishSoundEnabled":
          setWoodfishSoundEnabled(enabled);
          break;
        case "microBreakEnabled":
          setMicroBreakEnabled(enabled);
          break;
        case "microBreakIntervalMinutes": {
          const minutes = Number(newValue);
          if (Number.isFinite(minutes) && minutes > 0) {
            setMicroBreakIntervalMinutes(minutes);
          }
          break;
        }
        case "lunchStartNotificationEnabled":
          setLunchStartNotificationEnabled(enabled);
          break;
      }
    };
    window.addEventListener("storage", updateFromStorage);
    return () => window.removeEventListener("storage", updateFromStorage);
  }, [isSharedView, settingsLoaded]);

  // 午休整段落在班次之外时 buildTimelineFromBounds 会直接丢弃它，界面上却
  // 看不出任何异常——开关还亮着、时间还显示着。这里显式算一次好给出提示。

  const shiftBuildOptions = useMemo(
    () =>
      IS_DESKTOP_BUILD && lunchEnabled
        ? {
            breakStartTime: lunchStartTime,
            breakDurationMinutes: lunchDurationMinutes,
          }
        : {},
    [lunchEnabled, lunchStartTime, lunchDurationMinutes]
  );

  const lunchWithinShift = useMemo(() => {
    if (!lunchEnabled) return true;
    // 直接问「真正用来计时的那个 timeline 收下这段午休了吗」，而不是另写一遍
    // 判断条件：buildTimelineFromBounds 落在班次外时会静默丢弃午休，只留一个
    // segment。这个警告存在的意义就是揭示那次静默丢弃，自己抄一份规则等于给
    // 它埋下说谎的可能。
    const shift = buildShiftTimeline(
      startTime,
      endTime,
      new Date(),
      shiftBuildOptions
    );
    return shift.segments.length > 1;
  }, [lunchEnabled, startTime, endTime, shiftBuildOptions]);

  const getDailySalary = useCallback(() => {
    // 空输入是用户删掉旧值、准备重输时的正常中间态，placeholder 也约定此时
    // 采用默认计薪天数。其他非空非法值仍交给计算层拒绝。
    const workingDays = monthlyWorkingDays.trim()
      ? Number(monthlyWorkingDays)
      : undefined;
    return calculateDailySalary(
      salaryAmount,
      salaryType,
      workingDays
    );
  }, [salaryAmount, salaryType, monthlyWorkingDays]);

  const configuredDailySalary = showSalary ? getDailySalary() : null;
  // 收益完全由当前班次快照与当前设置推导，不保留一份会跨“返回/重新开始”
  // 残留的副本。清空薪资或关闭显示后，下一次渲染立即不再提供旧金额。
  const moneyEarned =
    activeShift && configuredDailySalary !== null
      ? configuredDailySalary *
        calculateTimelinePayRatio(activeShift, Date.now())
      : null;

  // 将 UI 的运行状态镜像为一个原子快照。Rust 与迷你窗只比较、累加前端已
  // 解析好的绝对 segments，不需要理解跨夜班次、工作日等业务规则。
  useEffect(() => {
    if (!IS_DESKTOP_BUILD || !settingsLoaded || !desktopStateRestored) return;

    const buildNotificationMessages = (shift: ShiftTimeline) => {
      const translatedTones = t("notificationToneMessages", {
        returnObjects: true,
      }) as unknown;
      const tones = Array.isArray(translatedTones)
        ? translatedTones.filter(
            (value): value is string => typeof value === "string"
          )
        : [];
      const safeTones = tones.length > 0 ? tones : [""];
      // 语气前缀和正文之间要不要空格，取决于前缀收尾的标点：中文的「。」
      // 「：」本身就带一个字宽的留白，再补空格会多出一条可见的缝。
      const variants = (body: string) =>
        safeTones.map((tone) => {
          const prefix = tone.trim();
          if (!prefix) return body;
          const glued = /[\u3000-\u303f\uff00-\uffef]$/.test(prefix);
          return glued ? `${prefix}${body}` : `${prefix} ${body}`;
        });

      const todayHours = getShiftDurationMs(shift) / (60 * 60 * 1000);
      const now = new Date();
      const yearHours = summarize({
        periodStart: startOfYear(now),
        asOf: now,
        workdays,
        currentShiftStart: new Date(getShiftStartAtMs(shift)),
        currentShiftEnd: new Date(getShiftEndAtMs(shift)),
        plannedDailyHours:
          getPlannedShiftDurationMs(shift) / (60 * 60 * 1000),
        todayProgress: 100,
        dailySalary: null,
        todayEffectiveHours: todayHours,
      }).hours;
      const hourFormatter = new Intl.NumberFormat(lang, {
        style: "unit",
        unit: "hour",
        unitDisplay: "short",
        maximumFractionDigits: 1,
      });

      return {
        milestone50: variants(t("notificationMilestone50")),
        milestone75: variants(t("notificationMilestone75")),
        milestone90: variants(t("notificationMilestone90")),
        milestone95: variants(t("notificationMilestone95")),
        milestone100: variants(
          t("notificationMilestone100", {
            today: hourFormatter.format(todayHours),
            year: hourFormatter.format(yearHours),
          })
        ),
      };
    };

    const localizedArray = (key: string, fallback: string) => {
      const translated = t(key, { returnObjects: true }) as unknown;
      return Array.isArray(translated)
        ? translated.filter((value): value is string => typeof value === "string")
        : [fallback];
    };

    const state =
      showCountdown && activeShift
        ? {
            preferencesVersion: 1,
            segments: activeShift.segments,
            plannedEndAtMs: activeShift.plannedEndAtMs,
            overtimeEndAtMs: activeShift.overtimeEndAtMs,
            running: true,
            nextShift: findNextShiftTimeline({
              startTime,
              endTime,
              workdays,
              afterMs: Math.max(getShiftEndAtMs(activeShift), Date.now()),
              options: shiftBuildOptions,
            }),
            notificationMode: desktopNotificationMode,
            notificationTitle: t("offWorkReminder"),
            // 标题带剩余百分比：进度走到 90% 和 95% 时，正文那两句
            // 「只剩最后一小段」和「马上就能合上电脑了」是同一个意思的
            // 两种说法，不给数字就分不出自己走到哪儿了。
            notificationTitles: {
              milestone50: t("notificationMilestoneTitle", { percent: 50 }),
              milestone75: t("notificationMilestoneTitle", { percent: 25 }),
              milestone90: t("notificationMilestoneTitle", { percent: 10 }),
              milestone95: t("notificationMilestoneTitle", { percent: 5 }),
              milestone100: t("offWorkTime"),
            },
            notificationMessages: buildNotificationMessages(activeShift),
            showSalary,
            hideEarnings,
            dailySalary: configuredDailySalary,
            lang,
            countdownNotStarted: t("countdownNotStarted"),
            // 这句既用于“本班尚未开始”，也用于“等待下一班”，用不带“下一班”
            // 的短标题可避免用户刚开始计时时误以为当前班次被跳过。
            nextShiftLabel: `${t("nextShiftLabelShort")} __TIME__`,
            lunchStartNotification: t("lunchStartNotification"),
            lunchEndNotification: t("lunchEndNotification"),
            lunchNotificationEnabled: lunchEnabled && lunchStartNotificationEnabled,
            lunchEndNotificationEnabled,
            microBreakEnabled,
            microBreakIntervalMinutes,
            microBreakMessages: localizedArray(
              "microBreakMessages",
              "You've been at it for {{minutes}} minutes. Time for a break."
            ),
            miniSkin,
            woodfishSoundEnabled,
            showEarningsLabel: t("showEarnings"),
            hideEarningsLabel: t("hideEarnings"),
          }
        : {
            ...emptyDesktopCountdownState(
              lang,
              t("countdownNotStarted"),
              {
                showEarnings: t("showEarnings"),
                hideEarnings: t("hideEarnings"),
              },
              {
                showSalary,
                hideEarnings,
                miniSkin,
                woodfishSoundEnabled,
              }
            ),
          };

    void writeDesktopCountdownState(state).catch(() => {
      // 桌面快照失败不应打断 Web 共用的主倒计时界面。
    });
  }, [
    settingsLoaded,
    desktopStateRestored,
    showCountdown,
    activeShift,
    desktopNotificationMode,
    showSalary,
    hideEarnings,
    configuredDailySalary,
    workdays,
    startTime,
    endTime,
    lang,
    t,
    shiftBuildOptions,
    lunchEnabled,
    lunchEndNotificationEnabled,
    microBreakEnabled,
    microBreakIntervalMinutes,
    lunchStartNotificationEnabled,
    miniSkin,
    woodfishSoundEnabled,
  ]);

  // 反向通道：迷你窗的眼睛与 Rust 到点切换下一班都会改写 Store。
  useEffect(() => {
    if (!IS_DESKTOP_BUILD) return;

    let unsubscribe: (() => void) | null = null;
    let cancelled = false;

    void subscribeToDesktopCountdown((state) => {
      if (!state) return;
      // 迷你窗能改这些偏好，主窗口必须跟上——否则主窗口下一次写状态会把
      // 用户刚在迷你窗上做的切换覆盖回去。
      const hasAuthoritativePreferences =
        hasAuthoritativeDesktopPreferences(state);
      setHideEarnings((current) =>
        hasAuthoritativePreferences
          ? state.hideEarnings
          : current || state.hideEarnings
      );
      if (hasAuthoritativePreferences) {
        setWoodfishSoundEnabled(state.woodfishSoundEnabled);
        setMiniSkin(state.miniSkin);
      }
      if (!state.running && isValidShiftTimeline(state)) {
        // Rust 判定“下一班也已完全错过”时只负责丢弃过期 nextShift。这里用旧班次
        // 触发一次新快照，findNextShiftTimeline 会从当前时刻之后继续排班。
        setActiveShift({
          segments: state.segments,
          plannedEndAtMs: state.plannedEndAtMs,
          overtimeEndAtMs: state.overtimeEndAtMs,
        });
        setShowCountdown(true);
        setShowNextShiftStatus(true);
        return;
      }
      if (state.running && isValidShiftTimeline(state)) {
        // 比较放在 updater 外面：state updater 必须是纯函数，React 会在
        // StrictMode 下双调用、并可能在并发渲染时重放它。把 setShowCountdown
        // 塞在里面，重放时它有被丢弃的风险——那会留下「activeShift 有值但
        // showCountdown 是 false」的状态，也就是有班次却不显示倒计时。
        //
        // 用 ref 而不是闭包里的 activeShift：这个订阅只建立一次，闭包里的值
        // 会一直停在挂载那一刻。ref 在这里同步更新，好让同一批事件里的后续
        // 回调立刻看到新值，不会重复 setState。
        const current = activeShiftRef.current;
        const unchanged =
          current !== null &&
          getShiftStartAtMs(current) === getShiftStartAtMs(state) &&
          getShiftEndAtMs(current) === getShiftEndAtMs(state);
        if (unchanged) return;

        const nextShift = {
          segments: state.segments,
          plannedEndAtMs: state.plannedEndAtMs,
          overtimeEndAtMs: state.overtimeEndAtMs,
        };
        activeShiftRef.current = nextShift;
        completionTrackedRef.current = false;
        setActiveShift(nextShift);
        setShowCountdown(true);
      }
    })
      .then((fn) => {
        if (cancelled) fn();
        else unsubscribe = fn;
      })
      .catch(() => {
        // 拿不到事件通道时退化为单向同步，不影响倒计时本身。
      });

    return () => {
      cancelled = true;
      unsubscribe?.();
    };
  }, []);

  // macOS 用覆盖式标题栏（tauri.conf.json 的 titleBarStyle: Overlay +
  // hiddenTitle），交通灯浮在内容上方，所以顶部要留出让位空间，窗口拖动
  // 也得自己画一条热区。这两项在 Tauri 里都是 macOS 专属配置，Windows
  // 直接忽略、用的是原生标题栏 —— 那边再留 40px 就是白留一片。
  const hasOverlayTitleBar = IS_DESKTOP_BUILD && desktopPlatform === "macos";
  // Windows 的原生标题栏用系统配色，压在玻璃卡片上方是一条对不上的灰白横条。
  // Rust 那边已经把 decorations 关掉，这里补上自绘的拖动条与窗口按钮。
  const hasWindowsTitleBar = IS_DESKTOP_BUILD && desktopPlatform === "windows";

  // 输入页与倒计时页是同一层的状态切换，纵向交换即可。设置页不在这个
  // AnimatePresence 里——它是整页横移，见下方轨道。
  // 退场时长同时也是进场的延时，两处必须一致，否则不是叠上就是空一拍。
  const FLOW_EXIT_SECONDS = 0.14;

  // mode="wait" 会等旧页面完全退场才开始进场，退场时长是实打实看得见的空窗：
  // 进出各 280ms 时，倒计时要在屏幕上淡够 280ms 才轮到输入页，看着就是
  // 「计时器残留了一会」。
  //
  // 时长写在 variant 里而不是 transition prop 上：prop 是所有动画的默认值，
  // 会盖掉 variant 自带的 transition，退场怎么都压不下去。
  const flowPageVariants = {
    initial: { opacity: 0, y: 12 },
    // 进场延后到退场结束再开始。popLayout 让新页面立刻占位，两段动画默认是
    // 重叠的，于是倒计时和输入表单会同时显影、糊在一起。加上这段延时就变成
    // 先送走旧的、再迎进新的，而又不必付 mode="wait" 那三百毫秒的等待。
    animate: {
      opacity: 1,
      y: 0,
      transition: {
        duration: 0.22,
        delay: FLOW_EXIT_SECONDS,
        ease: [0.32, 0.72, 0, 1] as const,
      },
    },
    exit: {
      opacity: 0,
      y: -10,
      transition: { duration: FLOW_EXIT_SECONDS, ease: "easeIn" as const },
    },
  };
  // 轨道横移是物理方向，阿拉伯语下两页左右互换，位移也要跟着反过来。
  const isRtl = getTextDirection(lang) === "rtl";
  const settingsScrollRef = useRef<HTMLDivElement>(null);

  const triggerCelebration = useCallback((shiftEndAtMs: number) => {
    celebratedShiftRef.current = shiftEndAtMs;
    try {
      // 只有动画真正交给 Confetti 组件后才标记为已庆祝。此前在窗口隐藏时
      // 就先落盘，若用户在恢复窗口前退出应用，这一班会永远失去庆祝动画。
      localStorage.setItem("celebratedShiftEnd", String(shiftEndAtMs));
    } catch {
      // 落盘失败不影响本次庆祝。
    }
    setConfettiNonce((nonce) => nonce + 1);
  }, []);

  // 窗口重新可见时把挂起的庆祝补上。
  //
  // 判据只看 visibilityState，不看焦点：窗口可见但焦点在别的应用时 macOS
  // 照常绘制、rAF 照常跑，这时没有理由把庆祝再往后推。WKWebView 会把窗口
  // 的遮挡状态映射到 visibilityState，所以它正是「rAF 会不会被节流」的判据。
  // 同时监听 focus，是为了兜住从托盘恢复时 visibilitychange 偶尔不触发。
  useEffect(() => {
    const release = () => {
      const pendingShiftEnd = celebrationPendingRef.current;
      if (pendingShiftEnd === null) return;
      if (
        document.visibilityState !== "visible" &&
        !document.hasFocus()
      ) return;
      celebrationPendingRef.current = null;
      triggerCelebration(pendingShiftEnd);
    };
    document.addEventListener("visibilitychange", release);
    window.addEventListener("focus", release);
    return () => {
      document.removeEventListener("visibilitychange", release);
      window.removeEventListener("focus", release);
    };
  }, [triggerCelebration]);

  const calculateProgress = useCallback(() => {
    const shift =
      activeShift ?? buildShiftTimeline(startTime, endTime, new Date(), shiftBuildOptions);
    return calculateTimelineProgress(shift, Date.now());
  }, [activeShift, startTime, endTime, shiftBuildOptions]);

  useEffect(() => {
    let interval: NodeJS.Timeout;
    if (showCountdown) {
      const updateCountdown = () => {
        const now = new Date();
        const shift =
          activeShift ?? buildShiftTimeline(startTime, endTime, now, shiftBuildOptions);
        const startAtMs = getShiftStartAtMs(shift);
        const endAtMs = getShiftEndAtMs(shift);

        if (IS_DESKTOP_BUILD && startAtMs > now.getTime()) {
          const beforeSeconds = Math.ceil((startAtMs - now.getTime()) / 1000);
          setOnLunchBreak(false);
          setShowBeforeShiftStatus(true);
          setShowNextShiftStatus(false);
          setTimeLeft(
            `${Math.floor(beforeSeconds / 3600)}:${Math.floor(
              (beforeSeconds % 3600) / 60
            )
              .toString()
              .padStart(2, "0")}:${(beforeSeconds % 60)
              .toString()
              .padStart(2, "0")}`
          );
          setProgress(0);
          return;
        }
        setShowBeforeShiftStatus(false);

        // 午休优先：此时剩余时间是冻结的，界面要说明「在休息」而不是干等。
        const breakEndAtMs = getActiveBreakEndAtMs(shift, now.getTime());
        if (breakEndAtMs !== null) {
          setOnLunchBreak(true);
          setShowNextShiftStatus(false);
          const breakSeconds = Math.max(
            0,
            Math.ceil((breakEndAtMs - now.getTime()) / 1000)
          );
          const breakMinutes = Math.floor(breakSeconds / 60);
          setTimeLeft(
            t("lunchCountdown", {
              time: `${Math.floor(breakMinutes / 60)}:${(breakMinutes % 60)
                .toString()
                .padStart(2, "0")}:${(breakSeconds % 60)
                .toString()
                .padStart(2, "0")}`,
            })
          );
          setProgress(calculateTimelineProgress(shift, now.getTime()));
          return;
        }
        setOnLunchBreak(false);

        const diff = getShiftRemainingMs(shift, now.getTime());
        if (diff <= 0) {
          if (!completionTrackedRef.current) {
            completionTrackedRef.current = true;
            track("countdown_complete");
          }
          const nextShift = IS_DESKTOP_BUILD
            ? findNextShiftTimeline({
                startTime,
                endTime,
                workdays,
                afterMs: Math.max(endAtMs, now.getTime()),
                options: shiftBuildOptions,
              })
            : null;
          const nextStartAtMs = nextShift
            ? getShiftStartAtMs(nextShift)
            : 0;
          if (nextStartAtMs > now.getTime()) {
            setShowNextShiftStatus(true);
            const nextSeconds = Math.ceil(
              (nextStartAtMs - now.getTime()) / 1000
            );
            const nextHours = Math.floor(nextSeconds / 3600);
            const nextMinutes = Math.floor((nextSeconds % 3600) / 60);
            const nextRemainder = nextSeconds % 60;
            // 「今日已下班」是结果，下一班倒计时是补充信息，拆两行让前者
            // 一眼可见；挤在一行时最重要的那句会被长数字冲淡。
            setTimeLeft(
              t("nextShiftIn", {
                time: `${nextHours}:${nextMinutes
                  .toString()
                  .padStart(2, "0")}:${nextRemainder
                  .toString()
                  .padStart(2, "0")}`,
              })
            );
          } else {
            setShowNextShiftStatus(false);
            setTimeLeft(t("offWorkTime"));
          }
          setProgress(100);
          // 撒花只在用户真的看得到时才放。下班那一刻窗口常常被别的应用盖着
          // 或收进了托盘，此时 rAF 被系统节流，canvas-confetti 的 5 秒窗口
          // 会在后台空转完，粒子一个都画不出来——等于白放。
          let alreadyCelebrated = celebratedShiftRef.current === endAtMs;
          if (!alreadyCelebrated) {
            try {
              alreadyCelebrated =
                localStorage.getItem("celebratedShiftEnd") === String(endAtMs);
            } catch {
              // 读不到就按未庆祝处理，最坏情况是多放一次。
            }
          }
          if (!alreadyCelebrated) {
            if (
              document.visibilityState === "visible" ||
              document.hasFocus()
            ) {
              triggerCelebration(endAtMs);
            } else {
              celebrationPendingRef.current = endAtMs;
            }
          }
          if (!IS_DESKTOP_BUILD) clearInterval(interval);
        } else {
          setShowNextShiftStatus(false);
          const hours = Math.floor(diff / (1000 * 60 * 60));
          const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
          const seconds = Math.floor((diff % (1000 * 60)) / 1000);

          // 计算总工作时间（小时）
          const totalWorkHours = getShiftDurationMs(shift) / (1000 * 60 * 60);

          // 根据总工作时间决定是否显示小时数的前导零
          const formattedHours =
            totalWorkHours >= 10
              ? hours.toString().padStart(2, "0")
              : hours.toString();
          const formattedMinutes = minutes.toString().padStart(2, "0");
          const formattedSeconds = seconds.toString().padStart(2, "0");

          setTimeLeft(
            t("timeLeft", {
              hours: formattedHours,
              minutes: formattedMinutes,
              seconds: formattedSeconds,
            })
          );

          setProgress(calculateProgress());

          // 只保留上界。原实现要求 diff 落在 14–15 分钟之间，是个一分钟宽的
          // 窗口——而后台标签页的定时器会被浏览器节流到大约每分钟一次甚至更
          // 稀疏，tick 很容易整个跳过这个窗口，提醒就被静默丢掉了。改成「一旦
          // 少于 15 分钟就发」，配合 reminderFiredRef 保证只发一次；开始倒计
          // 时时若已不足 15 分钟，handleStart 会预先标记为已发，避免一点开就
          // 弹提醒。
          if (
            !IS_DESKTOP_BUILD &&
            reminder &&
            !reminderFiredRef.current &&
            endAtMs - now.getTime() <= REMINDER_LEAD_MS
          ) {
            reminderFiredRef.current = true;
            void showNotification(t("offWorkReminder"), t("fifteenMinutesLeft"));
          }
        }
      };

      updateCountdown(); // 立即运行
      interval = setInterval(updateCountdown, 1000);
    }
    return () => clearInterval(interval);
  }, [showCountdown, startTime, endTime, activeShift, reminder, calculateProgress, t, shiftBuildOptions, workdays, triggerCelebration]);

  const handleStart = () => {
    if (startTime === endTime) {
      setFormError(t("sameTimeError"));
      return;
    }

    const now = new Date();
    const shift = buildShiftTimeline(startTime, endTime, now, shiftBuildOptions);
    const startAtMs = getShiftStartAtMs(shift);
    const endAtMs = getShiftEndAtMs(shift);
    if (!IS_DESKTOP_BUILD && startAtMs > now.getTime()) {
      const timeDiff = startAtMs - now.getTime();
      const hours = Math.floor(timeDiff / (1000 * 60 * 60));
      const minutes = Math.floor((timeDiff % (1000 * 60 * 60)) / (1000 * 60));

      setFormError(t("futureStartTimeError", { hours, minutes }));
      return;
    }

    if (startTime && endTime) {
      setFormError("");
      // 开始时距下班已不足 15 分钟的话，直接标记为已提醒——否则倒计时的第一个
      // tick 就会立刻弹出「还有十五分钟」，而用户是刚点的开始，这属于打扰。
      reminderFiredRef.current = endAtMs - now.getTime() <= REMINDER_LEAD_MS;
      completionTrackedRef.current = false;
      setActiveShift({
        ...shift,
      });
      setShowCountdown(true);
      setShowBeforeShiftStatus(startAtMs > now.getTime());
      setShowNextShiftStatus(false);
      setProgress(calculateTimelineProgress(shift, now.getTime()));
      track("countdown_start");
      if (!IS_DESKTOP_BUILD && reminder) void requestNotificationPermission();
    }
  };

  const enableDesktopNotificationFeature = async (action: () => void) => {
    const result = await requestNotificationPermissionDetailed();
    if (!result.granted) {
      setNotificationDialog("denied");
      return;
    }

    action();
    if (result.newlyGranted) {
      await showNotification(
        t("offWorkReminder"),
        t("notificationTestBody")
      );
    }
  };

  const handleReminderChange = (enabled: boolean) => {
    setReminder(enabled);
  };

  const handleDesktopNotificationModeChange = (
    mode: DesktopNotificationMode
  ) => {
    if (mode === "off") {
      setDesktopNotificationMode("off");
      return;
    }

    pendingNotificationActionRef.current = () =>
      setDesktopNotificationMode(mode);

    requestDesktopNotificationFeature();
  };

  const requestDesktopNotificationFeature = () => {

    let primerSeen = false;
    try {
      primerSeen = localStorage.getItem(notificationPrimerStorageKey) === "true";
    } catch {
      // 无法持久化时仍展示一次说明，授权流程本身不受影响。
    }
    if (!primerSeen) {
      setNotificationDialog("primer");
      return;
    }
    const action = pendingNotificationActionRef.current;
    if (action) void enableDesktopNotificationFeature(action);
  };

  const confirmNotificationPrimer = async () => {
    try {
      localStorage.setItem(notificationPrimerStorageKey, "true");
    } catch {
      // 权限请求不依赖说明页状态成功持久化。
    }
    setNotificationDialog(null);
    const action = pendingNotificationActionRef.current;
    if (action) await enableDesktopNotificationFeature(action);
  };


  const handleLunchEnabledChange = (enabled: boolean) => {
    if (!enabled) {
      setLunchEnabled(false);
      setLunchEndNotificationEnabled(false);
      return;
    }
    pendingNotificationActionRef.current = () => setLunchEnabled(true);
    requestDesktopNotificationFeature();
  };

  const handleLunchEndNotificationChange = (enabled: boolean) => {
    if (!enabled) {
      setLunchEndNotificationEnabled(false);
      return;
    }
    pendingNotificationActionRef.current = () =>
      setLunchEndNotificationEnabled(true);
    requestDesktopNotificationFeature();
  };

  // 快捷入口：进设置页 → 滚到目标分组 → 高亮两秒。滚动必须等设置页挂载后
  // 再做，所以放在下一帧而不是同一次事件里。
  const openSetting = (key: string) => {
    setShowDesktopSettings(true);
    setHighlightedSetting(key);

    // 只滚设置页自己的滚动容器。scrollIntoView 会把每一个可滚动祖先都滚一遍：
    // 设置页挂在横移 200% 的轨道上，点下按钮那一刻目标还在视口外，浏览器为了
    // 把它拉进来会去横向滚外层容器，整页就跑偏了。
    //
    // 位移用两个矩形的差值算。轨道的 transform 对容器和目标是同一份，相减即
    // 抵消，所以不必等滑动动画结束。
    window.requestAnimationFrame(() => {
      const container = settingsScrollRef.current;
      const target = container?.querySelector<HTMLElement>(
        `[data-setting="${key}"]`
      );
      if (!container || !target) return;
      const containerRect = container.getBoundingClientRect();
      const targetRect = target.getBoundingClientRect();
      const delta =
        targetRect.top -
        containerRect.top -
        (containerRect.height - targetRect.height) / 2;
      container.scrollTo({
        top: Math.max(0, container.scrollTop + delta),
        behavior: "smooth",
      });
    });

    window.setTimeout(() => setHighlightedSetting(null), 2400);
  };

  useEffect(() => {
    activeShiftRef.current = activeShift;
  }, [activeShift]);

  const handleLunchStartNotificationChange = (enabled: boolean) => {
    if (!enabled) {
      setLunchStartNotificationEnabled(false);
      return;
    }
    pendingNotificationActionRef.current = () =>
      setLunchStartNotificationEnabled(true);
    requestDesktopNotificationFeature();
  };

  const handleMicroBreakEnabledChange = (enabled: boolean) => {
    if (!enabled) {
      setMicroBreakEnabled(false);
      return;
    }
    pendingNotificationActionRef.current = () => setMicroBreakEnabled(true);
    requestDesktopNotificationFeature();
  };

  const openNotificationSettings = async () => {
    try {
      await openDesktopNotificationSettings();
      setNotificationDialog(null);
    } catch {
      setDesktopSettingError(t("desktopSettingError"));
    }
  };

  const handleAutostartChange = async (enabled: boolean) => {
    const previous = launchAtLogin;
    setLaunchAtLogin(enabled);
    setAutostartPending(true);
    setDesktopSettingError("");
    try {
      // 按返回的真实状态回填，而不是假定请求成功：商店版被系统锁住时
      // 请求打开不会报错，只是不生效。见决策 3。
      const state = await setDesktopAutostartEnabled(enabled);
      setLaunchAtLogin(state.enabled);
      setLaunchAtLoginLocked(state.locked);
    } catch {
      setLaunchAtLogin(previous);
      setDesktopSettingError(t("desktopSettingError"));
    } finally {
      setAutostartPending(false);
    }
  };

  const applyGlobalShortcutSettings = async (
    enabled: boolean,
    accelerator: string
  ) => {
    setGlobalShortcutPending(true);
    setGlobalShortcutError("");
    try {
      const settings = await updateDesktopGlobalShortcutSettings({
        enabled,
        accelerator,
      });
      setGlobalShortcutEnabled(settings.enabled);
      setGlobalShortcutAccelerator(settings.accelerator);
    } catch {
      setGlobalShortcutError(t("shortcutUpdateFailed"));
    } finally {
      setGlobalShortcutPending(false);
    }
  };

  const handleGlobalShortcutEnabledChange = (enabled: boolean) => {
    void applyGlobalShortcutSettings(enabled, globalShortcutAccelerator);
  };

  const handleGlobalShortcutKeyDown = (
    event: ReactKeyboardEvent<HTMLButtonElement>
  ) => {
    if (!globalShortcutCapturing) return;
    event.preventDefault();
    event.stopPropagation();
    if (event.key === "Escape") {
      setGlobalShortcutCapturing(false);
      setGlobalShortcutError("");
      return;
    }
    const accelerator = shortcutFromKeyEvent(event);
    if (!accelerator) {
      const isModifier = ["Meta", "Control", "Alt", "Shift"].includes(
        event.key
      );
      if (!isModifier) setGlobalShortcutError(t("shortcutInvalid"));
      return;
    }
    setGlobalShortcutCapturing(false);
    void applyGlobalShortcutSettings(globalShortcutEnabled, accelerator);
  };

  const openDesktopUrl = async (url: string) => {
    try {
      const { openUrl } = await import("@tauri-apps/plugin-opener");
      await openUrl(url);
    } catch {
      setDesktopSettingError(t("desktopSettingError"));
    }
  };

  const handleCheckForUpdates = async () => {
    if (!IS_DESKTOP_BUILD) return;

    // 商店版：这个入口不检查、不下载，只把用户送到商店详情页，更新在那边完成。
    if (IS_MSSTORE_BUILD) {
      setDesktopUpdateStatus("idle");
      try {
        await openMicrosoftStoreListing();
      } catch {
        // 失败要报在更新这一行下面。这里原本写 setDesktopSettingError，但那个
        // 状态只渲染在上方的「登录时启动」卡片里——用户点的是底部的更新入口，
        // 当前位置毫无反馈，错误却出现在一个不相干的设置下面。
        setDesktopUpdateStatus("error");
      }
      return;
    }

    const pending = pendingUpdateRef.current;

    // 已下载完成：直接安装并重启。
    if (pending && desktopUpdateStatus === "predownloaded") {
      setDesktopUpdateStatus("installing");
      try {
        await pending.install();
        const { relaunch } = await import("@tauri-apps/plugin-process");
        await relaunch();
      } catch {
        // 安装失败，回退到完整流程重来。
        pendingUpdateRef.current = null;
        setDesktopUpdateStatus("available");
      }
      return;
    }

    // 直连失败后的备用通道：重新检查 + 下载 + 安装整条链路都改走镜像，
    // 由 Rust 侧完成。检查失败（连不上 api.github.com）也走这里，否则被墙
    // 的用户根本不会知道有新版本可用。
    if (desktopUpdateStatus === "directFailed") {
      setDesktopUpdateStatus("mirrorInstalling");
      try {
        await installDesktopUpdateViaMirror();
        const { relaunch } = await import("@tauri-apps/plugin-process");
        await relaunch();
      } catch {
        setDesktopUpdateStatus("error");
      }
      return;
    }

    // 启动时已检查出新版本：这一次点击才是用户同意下载。
    if (pending && desktopUpdateStatus === "available") {
      setDesktopUpdateStatus("predownloading");
      try {
        // 卡住的连接不能无限等下去，否则用户看不到「改用镜像」这个出口。
        await pending.download();
        setDesktopUpdateStatus("predownloaded");
      } catch {
        setDesktopUpdateStatus("directFailed");
      }
      return;
    }

    setDesktopUpdateStatus("checking");
    setDesktopLatestVersion("");
    try {
      const { check } = await import("@tauri-apps/plugin-updater");
      const update = await check({ timeout: 15_000 });
      if (!update) {
        setDesktopUpdateStatus("latest");
        return;
      }

      setDesktopCurrentVersion(update.currentVersion);
      setDesktopLatestVersion(update.version);
      pendingUpdateRef.current = {
        version: update.version,
        currentVersion: update.currentVersion,
        download: () => update.download(),
        install: () => update.install(),
        downloadAndInstall: () => update.downloadAndInstall(),
      };
      setDesktopUpdateStatus("installing");
      await update.downloadAndInstall();
      const { relaunch } = await import("@tauri-apps/plugin-process");
      await relaunch();
    } catch (error) {
      const message = String(error).toLowerCase();
      setDesktopUpdateStatus(
        message.includes("endpoint") ||
          message.includes("pubkey") ||
          message.includes("public key") ||
          message.includes("configuration")
          ? "unconfigured"
          : "directFailed"
      );
    }
  };

  const handleReturn = () => {
    if (IS_DESKTOP_BUILD) {
      void stopDesktopCountdown(
        lang,
        t("countdownNotStarted"),
        {
          showEarnings: t("showEarnings"),
          hideEarnings: t("hideEarnings"),
        },
        {
          showSalary,
          hideEarnings,
          miniSkin,
          woodfishSoundEnabled,
        }
      ).catch(() => {
        // The normal snapshot effect remains a fallback.
      });
    }
    setShowCountdown(false);
    setShowBeforeShiftStatus(false);
    setShowNextShiftStatus(false);
    setActiveShift(null);
    setProgress(0);
    setTimeLeft("");
    celebratedShiftRef.current = null;
    celebrationPendingRef.current = null;
    completionTrackedRef.current = false;
    // 退出分享视图：恢复访问者自己保存的时间，并重新开启持久化。
    if (isSharedView) exitSharedView();
  };

  const openOvertimeDialog = () => {
    if (!activeShift) return;
    const suggested = new Date(suggestOvertimeEndAtMs(activeShift, Date.now()));
    setOvertimeEndTime(
      `${suggested.getHours().toString().padStart(2, "0")}:${suggested
        .getMinutes()
        .toString()
        .padStart(2, "0")}`
    );
    setOvertimeDialogOpen(true);
  };

  const confirmOvertime = () => {
    if (!activeShift) return;
    const overtimeEndAtMs = resolveOvertimeEndAtMs(
      activeShift,
      overtimeEndTime,
      Date.now()
    );
    if (overtimeEndAtMs === null) return;
    const extended = extendShiftWithOvertime(activeShift, overtimeEndAtMs);
    if (extended === activeShift) return;
    setActiveShift(extended);
    completionTrackedRef.current = false;
    celebratedShiftRef.current = null;
    setOvertimeDialogOpen(false);
  };

  const overtimeCandidateIsValid =
    activeShift !== null &&
    resolveOvertimeEndAtMs(activeShift, overtimeEndTime, Date.now()) !== null;

  // 「换成我的时间」：把 URL 里别人的班次换回访问者本地保存的设置。
  // 同时清掉 query，避免刷新或分享当前页时又把别人的班次带上。
  const exitSharedView = () => {
    setIsSharedView(false);
    setStartTime(getLocalStorageItem("startTime", "09:00"));
    setEndTime(getLocalStorageItem("endTime", "18:00"));
    if (typeof window !== "undefined") {
      window.history.replaceState(null, "", window.location.pathname);
    }
  };

  const handleUseOwnHours = () => {
    // 分享闭环的关键转化点：接收者从「看别人的班次」变成「设自己的」。
    track("share_convert");
    exitSharedView();
    setShowCountdown(false);
    setShowBeforeShiftStatus(false);
    setShowNextShiftStatus(false);
    setActiveShift(null);
    setProgress(0);
    setTimeLeft("");
    celebratedShiftRef.current = null;
    celebrationPendingRef.current = null;
    completionTrackedRef.current = false;
  };

  const handleTimeChange = (
    type: "start" | "end",
    hour: string,
    minute: string
  ) => {
    const time = `${hour}:${minute}`;
    setFormError("");
    if (type === "start") {
      setStartTime(time);
    } else {
      setEndTime(time);
    }
  };

  // 初始化主题
  useEffect(() => {
    if (isMounted) {
      const savedTheme = localStorage.getItem("theme") as Theme | null;
      const prefersDark = window.matchMedia(
        "(prefers-color-scheme: dark)"
      ).matches;

      // 设置初始主题
      const initialTheme = savedTheme || "auto";
      setTheme(initialTheme);

      // 应用主题
      applyTheme(initialTheme, prefersDark);
    }
  }, [isMounted]);

  // 监听系统主题变化
  useEffect(() => {
    if (!isMounted) return;

    const mediaQuery = window.matchMedia("(prefers-color-scheme: dark)");
    const handleChange = (e: MediaQueryListEvent) => {
      if (theme === "auto") {
        applyTheme("auto", e.matches);
      }
    };

    mediaQuery.addEventListener("change", handleChange);
    return () => mediaQuery.removeEventListener("change", handleChange);
  }, [isMounted, theme]);

  const applyTheme = (newTheme: Theme, prefersDark: boolean) => {
    const root = document.documentElement;
    root.classList.remove("dark", "theme-cyberpunk", "theme-sunset");
    document.body.className = ""; // Reset body class

    if (newTheme === "auto") {
      if (prefersDark) root.classList.add("dark");
    } else if (newTheme === "dark") {
      root.classList.add("dark");
    } else if (newTheme === "cyberpunk") {
      root.classList.add("dark", "theme-cyberpunk");
      document.body.classList.add("theme-cyberpunk");
    } else if (newTheme === "sunset") {
      root.classList.add("theme-sunset");
      document.body.classList.add("theme-sunset");
    }
  };

  // 切换主题
  const handleThemeChange = (newTheme: Theme) => {
    const prefersDark = window.matchMedia(
      "(prefers-color-scheme: dark)"
    ).matches;

    setTheme(newTheme);
    applyTheme(newTheme, prefersDark);
    localStorage.setItem("theme", newTheme);
  };

  // 注意：这里不能因 isMounted 为 false 就返回 null。服务端渲染（以及桌面端
  // 的静态导出）依赖首屏输出真实 DOM，否则爬虫拿到的是空壳。localStorage 里
  // 的个性化配置在挂载后由上面的 effect 覆盖，默认值在服务端与客户端首帧
  // 一致，不会产生 hydration 不匹配。
  const isCustomTheme = theme === "cyberpunk" || theme === "sunset";
  // 中文界面（含繁体）指向中文内容页，其余指向英文。
  const contentLang = resolveContentLocale(lang);

  // 本周与今年的累计，完全由配置推算（见 lib/summary.ts 的说明）。
  // 仅在倒计时视图下计算：它依赖当前时间，服务端渲染时算了也不能用。
  const summaryRows = useMemo(() => {
    if (!isMounted || !showCountdown || !calendarDateKey) return null;
    const now = new Date();
    const summaryShift =
      activeShift ??
      buildShiftTimeline(startTime, endTime, now, shiftBuildOptions);
    const common = {
      asOf: now,
      workdays,
      currentShiftStart: new Date(getShiftStartAtMs(summaryShift)),
      currentShiftEnd: new Date(getShiftEndAtMs(summaryShift)),
      plannedDailyHours:
        getPlannedShiftDurationMs(summaryShift) / (60 * 60 * 1000),
      todayProgress: progress,
      dailySalary: configuredDailySalary,
      todayEffectiveHours:
        getShiftDurationMs(summaryShift) / (60 * 60 * 1000),
      todayPayRatio: calculateTimelinePayRatio(summaryShift, Date.now()),
    };
    return [
      {
        label: t("summaryThisWeek"),
        data: summarize({ ...common, periodStart: startOfWeek(now) }),
      },
      {
        label: t("summaryThisYear"),
        data: summarize({ ...common, periodStart: startOfYear(now) }),
      },
    ];
  }, [
    isMounted,
    showCountdown,
    workdays,
    startTime,
    endTime,
    shiftBuildOptions,
    progress,
    configuredDailySalary,
    activeShift,
    calendarDateKey,
    t,
  ]);

  // 今天这一班是否落在工作日。挂载前一律按 true 处理：这个判断依赖当前时间，
  // 服务端与客户端的结果可能不同，直接算会造成 hydration 不匹配。
  // 判断用班次的开始时刻而非「现在」，这样跨夜班归属正确（见 isWorkday 注释）。
  const todayIsWorkday =
    !isMounted ||
    isWorkday(
      new Date(
        activeShift
          ? getShiftStartAtMs(activeShift)
          : getShiftBounds(startTime, endTime, new Date()).start.getTime()
      ),
      workdays
    );

  return (
    <div
      className={`min-h-screen transition-colors duration-1000 ease-in-out ${
        isAppShell
          ? "select-none flex flex-col items-stretch justify-start p-0"
          : "flex items-center justify-center p-4"
      } ${
        isCustomTheme ? "" : "bg-gray-100 dark:bg-gray-900"
      } ${
        isAppShell
          ? "pl-[env(safe-area-inset-left)] pr-[env(safe-area-inset-right)] pt-[env(safe-area-inset-top)] pb-[env(safe-area-inset-bottom)]"
          : ""
      }`}
    >
      <Background theme={theme} />
      <Confetti trigger={confettiNonce} />

      {IS_DESKTOP_BUILD && (
        <>
        <Dialog
          open={notificationDialog !== null}
          onOpenChange={(open) => {
            if (!open) setNotificationDialog(null);
          }}
        >
          <DialogContent className="max-w-[360px] rounded-2xl p-5">
            <DialogHeader className="text-start">
              <div className="mb-2 flex h-10 w-10 items-center justify-center rounded-xl bg-orange-100 text-orange-600 dark:bg-orange-500/15 dark:text-orange-300">
                {notificationDialog === "denied" ? (
                  <BellRing className="h-5 w-5" />
                ) : (
                  <ShieldCheck className="h-5 w-5" />
                )}
              </div>
              <DialogTitle>
                {t(
                  notificationDialog === "denied"
                    ? "notificationDeniedTitle"
                    : "notificationPrimerTitle"
                )}
              </DialogTitle>
              <DialogDescription className="space-y-2 text-start">
                <span className="block">
                  {t(
                    notificationDialog === "denied"
                      ? "notificationDeniedBody"
                      : "notificationPrimerBody"
                  )}
                </span>
                {notificationDialog === "primer" && (
                  <span className="block font-medium text-gray-700 dark:text-gray-200">
                    {t("notificationPrivacyNote")}
                  </span>
                )}
              </DialogDescription>
            </DialogHeader>
            <div className="mt-2 flex justify-end gap-2">
              <Button
                variant="outline"
                onClick={() => setNotificationDialog(null)}
              >
                {t("notNow")}
              </Button>
              <Button
                onClick={() => {
                  if (notificationDialog === "denied") {
                    void openNotificationSettings();
                  } else {
                    void confirmNotificationPrimer();
                  }
                }}
              >
                {t(
                  notificationDialog === "denied"
                    ? "notificationOpenSettings"
                    : "notificationContinue"
                )}
              </Button>
            </div>
          </DialogContent>
        </Dialog>
        <Dialog open={overtimeDialogOpen} onOpenChange={setOvertimeDialogOpen}>
          <DialogContent className="max-w-[360px] rounded-2xl p-5">
            <DialogHeader className="text-start">
              <DialogTitle>{t("overtimeTitle")}</DialogTitle>
              <DialogDescription>{t("overtimeDescription")}</DialogDescription>
            </DialogHeader>
            <div className="space-y-2">
              <Label>{t("overtimeEndTime")}</Label>
              <div className="grid grid-cols-2 gap-2" dir="ltr">
                <Select
                  value={overtimeEndTime.split(":")[0]}
                  onValueChange={(hour) =>
                    setOvertimeEndTime(
                      `${hour}:${overtimeEndTime.split(":")[1]}`
                    )
                  }
                >
                  <SelectTrigger className="h-10 rounded-xl bg-background">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {Array.from({ length: 24 }, (_, hour) =>
                      hour.toString().padStart(2, "0")
                    ).map((hour) => (
                      <SelectItem key={hour} value={hour}>{hour}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <Select
                  value={overtimeEndTime.split(":")[1]}
                  onValueChange={(minute) =>
                    setOvertimeEndTime(
                      `${overtimeEndTime.split(":")[0]}:${minute}`
                    )
                  }
                >
                  <SelectTrigger className="h-10 rounded-xl bg-background">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {["00", "15", "30", "45"].map((minute) => (
                      <SelectItem key={minute} value={minute}>{minute}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </div>
            <p className="text-xs text-gray-500 dark:text-gray-400">
              {t("overtimeNoMultiplier")}
            </p>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setOvertimeDialogOpen(false)}>
                {t("notNow")}
              </Button>
              <Button
                onClick={confirmOvertime}
                disabled={!overtimeCandidateIsValid}
              >
                {t("confirmOvertime")}
              </Button>
            </div>
          </DialogContent>
        </Dialog>
        </>
      )}

      {hasOverlayTitleBar && (
        <div
          data-tauri-drag-region="deep"
          aria-hidden="true"
          className="fixed inset-x-20 top-0 z-50 h-8 cursor-grab active:cursor-grabbing"
        />
      )}

      {/* Windows 自绘标题栏。不另起一行放标题——窗口只有 430pt 高，而下面的
          页头已经写着「下班倒计时／设置」了，再来一条只是重复。按钮沿用应用
          自己的圆角与配色，关闭键悬停变红，遵循 Windows 的位置习惯。 */}
      {hasWindowsTitleBar && (
        <div
          data-tauri-drag-region="deep"
          className="fixed inset-x-0 top-0 z-50 flex h-9 cursor-grab items-center justify-end gap-0.5 pe-1.5 active:cursor-grabbing"
        >
          <button
            type="button"
            data-tauri-drag-region="false"
            onClick={() => {
              void minimizeDesktopMainWindow().catch(() => {
                // 最小化失败时窗口保持原状，不影响计时。
              });
            }}
            aria-label={t("menuMinimize")}
            title={t("menuMinimize")}
            className="inline-flex h-7 w-7 items-center justify-center rounded-lg text-gray-500 transition-colors hover:bg-black/5 hover:text-gray-900 dark:text-gray-400 dark:hover:bg-white/10 dark:hover:text-white"
          >
            <Minus className="h-3.5 w-3.5" />
          </button>
          <button
            type="button"
            data-tauri-drag-region="false"
            onClick={() => {
              void hideDesktopMainWindow().catch(() => {
                // 隐藏失败时窗口保持原状；托盘里仍可再次唤起。
              });
            }}
            aria-label={t("menuCloseWindow")}
            title={t("menuCloseWindow")}
            className="inline-flex h-7 w-7 items-center justify-center rounded-lg text-gray-500 transition-colors hover:bg-red-500 hover:text-white dark:text-gray-400"
          >
            <X className="h-3.5 w-3.5" />
          </button>
        </div>
      )}

      <div className={isAppShell ? "flex min-h-0 flex-1 flex-col" : "w-full max-w-md"}>
      {/* 接力提示。分享链接落地后对方直接看到的是发送者的班次倒计时，
          这里说明来源并给出一键切回自己时间的出口 —— 分享→落地→转化的
          闭环，此前断在落地这一步（对方只会看到一个空表单）。 */}
      {isSharedView && (
        <div className="mb-4 flex items-center justify-between gap-3 rounded-2xl bg-white/70 px-4 py-3 text-sm shadow-sm backdrop-blur-sm dark:bg-black/30">
          <span className="text-gray-700 dark:text-gray-200">
            {t("sharedShiftBanner")}
          </span>
          <button
            type="button"
            onClick={handleUseOwnHours}
            className="shrink-0 rounded-lg bg-gray-900 px-3 py-1.5 text-xs font-medium text-white transition-colors hover:bg-gray-700 dark:bg-white dark:text-gray-900 dark:hover:bg-gray-200"
          >
            {t("sharedShiftUseOwn")}
          </button>
        </div>
      )}
      <Card className={`w-full glass dark:glass-dark border-0 ${
        isAppShell
          ? "max-w-none h-screen max-h-screen overflow-hidden rounded-none shadow-none border-none bg-transparent flex flex-col"
          : ""
      }`}>
        {/* 轨道：主页面与设置页各占一半，整条横移。Web 版没有设置页，用
            display:contents 让这两层在布局里消失。 */}
        <div
          className={
            IS_DESKTOP_BUILD
              ? "flex min-h-0 w-[200%] flex-1 will-change-transform motion-safe:transition-transform motion-safe:duration-[340ms] motion-safe:ease-[cubic-bezier(0.32,0.72,0,1)]"
              : "contents"
          }
          style={
            IS_DESKTOP_BUILD
              ? {
                  transform: showDesktopSettings
                    ? `translateX(${isRtl ? "50%" : "-50%"})`
                    : "translateX(0)",
                }
              : undefined
          }
        >
        <div
          className={
            IS_DESKTOP_BUILD ? "flex h-full w-1/2 min-h-0 flex-col" : "contents"
          }
        >
        <CardHeader
          className={
            isAppShell
              ? hasOverlayTitleBar || hasWindowsTitleBar
                ? "px-6 pb-3 pt-10"
                : "p-6 pb-3"
              : undefined
          }
        >
          <div
            data-tauri-drag-region={IS_DESKTOP_BUILD ? "deep" : undefined}
            className="flex items-center justify-between gap-3"
          >
            <div className="flex min-w-0 flex-1 items-center gap-2">
              {/* 这里用真正的 h1 而不是 shadcn 的 CardTitle：后者硬编码为 h3，
                  会排在下方说明区的 h2 前面，标题层级就颠倒了。原先另有一个
                  sr-only 的 h1，内容与这里完全相同，属于重复，已一并去掉。 */}
              <h1
                data-tauri-drag-region={IS_DESKTOP_BUILD ? "deep" : undefined}
                title={t("offWorkCountdown")}
                className={
                  IS_DESKTOP_BUILD
                    ? "min-w-0 truncate whitespace-nowrap text-xl font-bold leading-none tracking-tight dark:text-white"
                    : "text-2xl font-bold leading-none tracking-tight dark:text-white"
                }
              >
                {t("offWorkCountdown")}
              </h1>
              {!showCountdown && !IS_DESKTOP_BUILD && (
                <a
                  href="https://github.com/ififi2017/Off-Work-Countdown"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300 transition-colors"
                  title="View source code on GitHub"
                >
                  <Github size={24} />
                </a>
              )}
            </div>
            <div
              data-tauri-drag-region="false"
              className="flex shrink-0 items-center gap-1.5"
            >
              {IS_DESKTOP_BUILD ? (
                <>
                  <Button
                    variant="outline"
                    size="icon"
                    className="h-9 w-9 rounded-xl border-input bg-background shadow-sm"
                    onClick={() => {
                      void toggleDesktopFloatingTimer().catch(() => {
                        setDesktopSettingError(t("desktopSettingError"));
                      });
                    }}
                    aria-label={t("toggleMiniTimer")}
                    title={t("toggleMiniTimer")}
                  >
                    <PictureInPicture2 className="h-[1.15rem] w-[1.15rem]" />
                  </Button>
                  <Button
                    variant="outline"
                    size="icon"
                    className="h-9 w-9 rounded-xl border-input bg-background shadow-sm"
                    onClick={() => setShowDesktopSettings(true)}
                    aria-label={
                      desktopUpdateStatus === "available" ||
                      desktopUpdateStatus === "predownloaded"
                        ? t("updateAvailable")
                        : t("settings")
                    }
                    title={
                      desktopUpdateStatus === "available" ||
                      desktopUpdateStatus === "predownloaded"
                        ? `${t("updateAvailable")}: v${desktopLatestVersion}`
                        : t("settings")
                    }
                  >
                    <span className="relative">
                      {desktopUpdateStatus === "available" ||
                      desktopUpdateStatus === "predownloaded" ? (
                        <Download className="h-[1.15rem] w-[1.15rem] text-orange-500 dark:text-orange-400" />
                      ) : (
                        <Settings2 className="h-[1.15rem] w-[1.15rem]" />
                      )}
                      {(desktopUpdateStatus === "available" ||
                        desktopUpdateStatus === "predownloaded") && (
                        <span className="absolute -end-1.5 -top-1.5 h-2 w-2 rounded-full bg-red-500 ring-2 ring-background" />
                      )}
                    </span>
                  </Button>
                </>
              ) : !IS_DESKTOP_BUILD ? (
                <ThemeToggle
                  theme={theme}
                  onThemeChange={handleThemeChange}
                  compact
                />
              ) : null}
              {!IS_DESKTOP_BUILD && (
              <LanguageSelector
                currentLang={lang}
                languageMap={languageNames}
                compact
              />
            )}
            </div>
          </div>
        </CardHeader>
        <CardContent
          className={
            isAppShell
              ? `relative z-10 min-h-0 flex-1 flex flex-col p-6 pt-2 pb-4 ${
                  IS_DESKTOP_BUILD && formError
                    ? "justify-start overflow-y-auto"
                    : "justify-center overflow-visible"
                }`
              : undefined
          }
        >
          {/* popLayout 而不是 wait：wait 要等退场信号回来才肯渲染新页面，实测
              从点击到 DOM 交换要等 300ms 出头，中间那段旧页面还杵在屏幕上，
              就是「计时器残留一会」。popLayout 让退场元素脱离文档流，新页面
              立刻布局。 */}
          <AnimatePresence mode="popLayout">
            {!showCountdown ? (
              <motion.div
                key="input"
                variants={flowPageVariants}
                initial="initial"
                animate="animate"
                exit="exit"
                className={IS_DESKTOP_BUILD ? "space-y-3" : "space-y-4"}
              >
                {/* 两个选择器并排。Web 版此前各占整行，两位数输入框会拉到
                    200pt 以上；只加宽度上限又会在右边空出一大块。 */}
                <div className="grid grid-cols-2 gap-3">
                  <TimeSelector
                    id="startTime"
                    label={t("startTime")}
                    value={startTime}
                    compact={IS_DESKTOP_BUILD}
                    onChange={(hour, minute) =>
                      handleTimeChange("start", hour, minute)
                    }
                  />
                  <TimeSelector
                    id="endTime"
                    label={t("endTime")}
                    value={endTime}
                    compact={IS_DESKTOP_BUILD}
                    onChange={(hour, minute) =>
                      handleTimeChange("end", hour, minute)
                    }
                  />
                </div>
                <WorkdaySelector
                  lang={lang}
                  label={t("workdaysLabel")}
                  value={workdays}
                  onChange={setWorkdays}
                  compact={IS_DESKTOP_BUILD}
                />
                {!todayIsWorkday && (
                  <p className="text-sm text-gray-500 dark:text-gray-400">
                    {t("restDay")}
                  </p>
                )}

                {/* 特色功能的快捷入口。只放图标：这一屏是「开始倒计时」的
                    主路径，配上文字会喧宾夺主；说明留给 tooltip。 */}
                {IS_DESKTOP_BUILD && (
                  // 与上方班次配置拉开距离：这排是「去设置里调别的」的入口，
                  // 和上下班时间不是一类东西。窗口高度固定，下方本来就有余量，
                  // 这段间距不会把内容顶出去。
                  <div className="flex items-center justify-center gap-2 pt-3">
                    <ThemeToggle
                      theme={theme}
                      onThemeChange={handleThemeChange}
                      compact
                      quick
                    />
                    {(
                      [
                        [
                          "notification",
                          BellRing,
                          "notificationMode",
                          desktopNotificationMode !== "off",
                        ],
                        ["lunch", Coffee, "lunchBreak", lunchEnabled],
                        [
                          "microBreak",
                          GlassWater,
                          "microBreakReminder",
                          microBreakEnabled,
                        ],
                        ["salary", Coins, "salarySettings", showSalary],
                      ] as const
                    ).map(([key, Icon, labelKey, active]) => (
                      <button
                        key={key}
                        type="button"
                        onClick={() => openSetting(key)}
                        aria-pressed={active}
                        aria-label={t(labelKey)}
                        title={t(labelKey)}
                        className={`inline-flex h-9 w-9 items-center justify-center rounded-xl border shadow-sm transition-all duration-150 ${
                          active
                            ? "border-gray-900 bg-gray-900 text-white shadow-gray-900/20 hover:bg-gray-800 dark:border-white dark:bg-white dark:text-gray-900 dark:hover:bg-gray-200"
                            : "border-gray-200/80 bg-white/40 text-gray-600 hover:bg-white/70 hover:text-gray-900 dark:border-gray-700 dark:bg-black/10 dark:text-gray-300 dark:hover:bg-black/20 dark:hover:text-white"
                        }`}
                      >
                        <Icon size={16} />
                      </button>
                    ))}
                  </div>
                )}

                {!IS_DESKTOP_BUILD && (
                  <div className="flex min-h-9 items-center gap-2">
                    <Switch
                      id="reminder"
                      checked={reminder}
                      onCheckedChange={handleReminderChange}
                    />
                    <Label htmlFor="reminder" className="dark:text-gray-200">
                      {t("reminder")}
                    </Label>
                  </div>
                )}

                {!IS_DESKTOP_BUILD && (
                  <SalarySettings
                    enabled={showSalary}
                    onEnabledChange={setShowSalary}
                    salaryType={salaryType}
                    onSalaryTypeChange={setSalaryType}
                    salaryAmount={salaryAmount}
                    onSalaryAmountChange={setSalaryAmount}
                    monthlyWorkingDays={monthlyWorkingDays}
                    onMonthlyWorkingDaysChange={setMonthlyWorkingDays}
                    maskAmountField={maskAmountField}
                    onMaskAmountFieldChange={setMaskAmountField}
                  />
                )}
                {formError && (
                  <p role="alert" className="text-sm text-red-600 dark:text-red-400">
                    {formError}
                  </p>
                )}
              </motion.div>
            ) : (
              <motion.div
                key="countdown"
                variants={flowPageVariants}
                initial="initial"
                animate="animate"
                exit="exit"
                className={IS_DESKTOP_BUILD ? "w-full space-y-3" : "space-y-6"}
              >
                <CountdownDisplay
                  timeLeft={timeLeft}
                  title={
                    showBeforeShiftStatus
                      ? t("nextShiftLabelShort")
                      : showNextShiftStatus
                        ? t("offWorkToday")
                        : undefined
                  }
                  progress={progress}
                  standby={onLunchBreak}
                  dense={IS_DESKTOP_BUILD}
                  overtime={Boolean(activeShift?.overtimeEndAtMs)}
                  status={showNextShiftStatus || showBeforeShiftStatus}
                />
                {summaryRows && (
                  <PeriodSummary
                    lang={lang}
                    note={t("summaryEstimateNote")}
                    rows={summaryRows}
                    hideEarnings={hideEarnings}
                    compact={IS_DESKTOP_BUILD}
                    currentEarnings={
                      moneyEarned !== null
                        ? {
                            label: t("moneyEarned"),
                            value: moneyEarned.toFixed(2),
                            showLabel: t("showEarnings"),
                            hideLabel: t("hideEarnings"),
                            onToggle: () => setHideEarnings((previous) => !previous),
                          }
                        : undefined
                    }
                  />
                )}
              </motion.div>
            )}
          </AnimatePresence>
        </CardContent>
          <CardFooter
            className={
              IS_DESKTOP_BUILD
                ? "relative z-0 flex justify-center border-t border-white/30 bg-white/20 p-3 backdrop-blur-sm dark:border-white/10 dark:bg-black/10"
                : "flex justify-center"
            }
          >
          {/* 同上：页脚按钮组也不能等退场信号，否则换页时下方空一拍。
              这里只淡入淡出、不做缩放：popLayout 会把退场按钮改成绝对定位，
              宽度随之变成收缩包裹，再叠一层缩放就像按钮自己塌了一圈、把文字
              挤到第二行。whitespace-nowrap 兜住换行。 */}
          <AnimatePresence mode="popLayout">
            {!showCountdown ? (
              <motion.div
                key="start"
                className="whitespace-nowrap"
                initial={{ opacity: 0 }}
                animate={{
                  opacity: 1,
                  transition: { duration: 0.2, delay: FLOW_EXIT_SECONDS },
                }}
                exit={{
                  opacity: 0,
                  transition: { duration: FLOW_EXIT_SECONDS },
                }}
              >
                <Button onClick={handleStart}>{t("startCountdown")}</Button>
              </motion.div>
            ) : (
              <motion.div
                key="return"
                initial={{ opacity: 0 }}
                animate={{
                  opacity: 1,
                  transition: { duration: 0.2, delay: FLOW_EXIT_SECONDS },
                }}
                exit={{
                  opacity: 0,
                  transition: { duration: FLOW_EXIT_SECONDS },
                }}
                className="flex gap-2 whitespace-nowrap"
              >
                <Button
                  variant="outline"
                  className={IS_DESKTOP_BUILD ? "h-9 rounded-lg px-4" : undefined}
                  onClick={handleReturn}
                >
                  <ArrowLeft className="me-2 h-4 w-4" /> {t("return")}
                </Button>
                {IS_DESKTOP_BUILD && (
                  <Button
                    variant="outline"
                    className="h-9 rounded-lg px-3"
                    onClick={openOvertimeDialog}
                  >
                    {activeShift?.overtimeEndAtMs
                      ? t("adjustOvertime")
                      : t("overtime")}
                  </Button>
                )}
                <ShareButton
                  timeLeft={timeLeft}
                  progress={progress}
                  isOff={progress >= 100}
                  shift={{ start: startTime, end: endTime }}
                  desktop={IS_DESKTOP_BUILD}
                />
              </motion.div>
            )}
          </AnimatePresence>
          </CardFooter>
        </div>

        {/* 设置页是一整页，连页头一起换。此前只有内容区参与转场，页头还写着
            「下班倒计时」、页脚还挂着倒计时那三个按钮，内容却已经是设置了。

            两页并排放在一条 200% 宽的轨道上整体横移，而不是把设置页浮在主页
            上方：两页都保持透明，背景渐变继续从底下透出。做成覆盖层就得给它
            一个不透明底色，自定义主题的渐变会被压掉。 */}
        {IS_DESKTOP_BUILD && (
          <div className="flex h-full w-1/2 min-h-0 flex-col">
            <div
              className={
                hasOverlayTitleBar || hasWindowsTitleBar
                  ? "px-6 pb-3 pt-10"
                  : "p-6 pb-3"
              }
            >
              <div
                data-tauri-drag-region="deep"
                className="flex items-center gap-2"
              >
                <button
                  type="button"
                  data-tauri-drag-region="false"
                  onClick={() => setShowDesktopSettings(false)}
                  className="-ms-1 inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-lg text-gray-600 transition-colors hover:bg-black/5 hover:text-gray-950 dark:text-gray-300 dark:hover:bg-white/10 dark:hover:text-white"
                  aria-label={t("return")}
                  title={t("return")}
                >
                  <ArrowLeft className="h-4 w-4" />
                </button>
                <h2
                  data-tauri-drag-region="deep"
                  className="min-w-0 truncate whitespace-nowrap text-xl font-bold leading-none tracking-tight dark:text-white"
                >
                  {t("settings")}
                </h2>
              </div>
            </div>
            <div
              ref={settingsScrollRef}
              className="desktop-scrollbar min-h-0 flex-1 space-y-3 overflow-y-auto px-6 pb-4 pt-2"
            >
                  <section className="flex items-center justify-between rounded-xl border border-gray-200/80 bg-white/35 p-3 shadow-sm dark:border-gray-700 dark:bg-black/10">
                    <Label className="flex items-center gap-2 text-sm dark:text-gray-200">
                      <Palette size={16} />
                      {t("toggleTheme")}
                    </Label>
                    <ThemeToggle
                      theme={theme}
                      onThemeChange={handleThemeChange}
                      compact
                    />
                  </section>

                  <section className="flex items-center justify-between rounded-xl border border-gray-200/80 bg-white/35 p-3 shadow-sm dark:border-gray-700 dark:bg-black/10">
                    <Label className="flex items-center gap-2 text-sm dark:text-gray-200">
                      <Globe size={16} />
                      {t("chooselanguage")}
                    </Label>
                    <LanguageSelector
                      currentLang={lang}
                      languageMap={languageNames}
                      compact
                    />
                  </section>

                  <section className="space-y-2.5 rounded-xl border border-gray-200/80 bg-white/35 p-3 shadow-sm dark:border-gray-700 dark:bg-black/10">
                    <div className="flex items-center justify-between gap-4">
                      <Label
                        htmlFor="launch-at-login"
                        className="flex items-center gap-2 text-sm dark:text-gray-200"
                      >
                        <Rocket size={16} />
                        {t("launchAtLogin")}
                      </Label>
                      <Switch
                        id="launch-at-login"
                        checked={launchAtLogin}
                        disabled={
                          !autostartLoaded ||
                          autostartPending ||
                          launchAtLoginLocked
                        }
                        onCheckedChange={handleAutostartChange}
                      />
                    </div>
                    {launchAtLoginLocked && (
                      <p className="text-xs text-gray-500 dark:text-gray-400">
                        {t("launchAtLoginManagedBySystem")}
                      </p>
                    )}
                    {desktopSettingError && (
                      <p
                        role="alert"
                        className="text-xs text-red-600 dark:text-red-400"
                      >
                        {desktopSettingError}
                      </p>
                    )}
                  </section>

                  <section className="space-y-2.5 rounded-xl border border-gray-200/80 bg-white/35 p-3 shadow-sm dark:border-gray-700 dark:bg-black/10">
                    <div className="flex items-center justify-between gap-4">
                      <Label
                        htmlFor="global-shortcut-enabled"
                        className="flex items-center gap-2 text-sm dark:text-gray-200"
                      >
                        <Keyboard size={16} />
                        {t("globalShortcut")}
                      </Label>
                      <Switch
                        id="global-shortcut-enabled"
                        checked={globalShortcutEnabled}
                        disabled={!globalShortcutLoaded || globalShortcutPending}
                        onCheckedChange={handleGlobalShortcutEnabledChange}
                      />
                    </div>
                    <Button
                      ref={globalShortcutButtonRef}
                      type="button"
                      variant="outline"
                      disabled={!globalShortcutLoaded || globalShortcutPending}
                      aria-label={t("shortcutChange")}
                      className={`h-10 w-full justify-between rounded-lg px-3 font-normal ${
                        globalShortcutCapturing
                          ? "border-orange-500 ring-2 ring-orange-500/20 dark:border-orange-400"
                          : ""
                      }`}
                      onClick={() => {
                        setGlobalShortcutError("");
                        setGlobalShortcutCapturing((capturing) => !capturing);
                      }}
                      onKeyDown={handleGlobalShortcutKeyDown}
                      onBlur={() => setGlobalShortcutCapturing(false)}
                    >
                      <kbd className="font-mono text-xs font-semibold text-gray-800 dark:text-gray-100">
                        {globalShortcutCapturing
                          ? t("shortcutRecording")
                          : formatDesktopShortcut(
                              globalShortcutAccelerator,
                              desktopPlatform
                            )}
                      </kbd>
                      <span className="text-xs text-gray-500 dark:text-gray-400">
                        {globalShortcutCapturing
                          ? t("shortcutCancelHint")
                          : t("shortcutChange")}
                      </span>
                    </Button>
                    <p className="text-xs leading-4 text-gray-500 dark:text-gray-400">
                      {/* 提示语按平台给：两个平台的修饰键混在一句里
                          （Command/Ctrl、Option/Alt）等于让用户自己挑，
                          而运行时我们明明知道自己在哪个平台上。 */}
                      {desktopPlatform === "macos"
                        ? t("shortcutHintMac")
                        : t("shortcutHintWindows")}
                    </p>
                    {globalShortcutError && (
                      <p
                        role="alert"
                        className="text-xs text-red-600 dark:text-red-400"
                      >
                        {globalShortcutError}
                      </p>
                    )}
                  </section>

                  <section className="space-y-3 rounded-xl border border-gray-200/80 bg-white/35 p-3 shadow-sm dark:border-gray-700 dark:bg-black/10">
                    <div className="flex items-center justify-between gap-3">
                      <Label className="flex items-center gap-2 text-sm dark:text-gray-200">
                        <PictureInPicture2 size={16} />
                        {t("floatingTimer")}
                      </Label>
                      <Select
                        value={miniSkin}
                        onValueChange={(value) => setMiniSkin(value as DesktopMiniSkin)}
                      >
                        <SelectTrigger className="h-9 w-[140px] rounded-xl bg-background">
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="standard">{t("standardSkin")}</SelectItem>
                          <SelectItem value="woodfish">{t("woodfishSkin")}</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>
                    {miniSkin === "woodfish" && (
                      <div className="flex items-center justify-between gap-4 border-t border-gray-200/70 pt-3 dark:border-gray-700/70">
                        <div>
                          <Label htmlFor="woodfish-sound" className="text-sm font-normal dark:text-gray-200">
                            {t("woodfishSound")}
                          </Label>
                          <p className="mt-1 text-xs text-gray-500 dark:text-gray-400">
                            {t("woodfishFirstTapSilent")}
                          </p>
                        </div>
                        <Switch
                          id="woodfish-sound"
                          checked={woodfishSoundEnabled}
                          onCheckedChange={setWoodfishSoundEnabled}
                        />
                      </div>
                    )}
                    <Button
                      variant="outline"
                      className="h-9 w-full rounded-lg"
                      onClick={() => void toggleDesktopFloatingTimer()}
                    >
                      {t("toggleFloatingTimer")}
                    </Button>
                  </section>

                  {/* 三类通知（下班／午休／健康）此前散在主界面和设置页两处，
                      想「今天别烦我」得跑两个地方。收进同一个分组。 */}
                  <section
                    data-setting="notification"
                    className={`space-y-3 rounded-xl border border-gray-200/80 bg-white/35 p-3 shadow-sm dark:border-gray-700 dark:bg-black/10 ${
                      highlightedSetting === "notification" ? "setting-highlight" : ""
                    }`}
                  >
                    <div className="flex min-h-9 items-center justify-between gap-3">
                      <Label
                        htmlFor="notification-mode"
                        className="flex items-center gap-2 text-sm dark:text-gray-200"
                      >
                        <BellRing size={16} />
                        {t("notificationMode")}
                      </Label>
                      <Select
                        value={desktopNotificationMode}
                        onValueChange={(value) =>
                          handleDesktopNotificationModeChange(
                            value as DesktopNotificationMode
                          )
                        }
                      >
                        <SelectTrigger
                          id="notification-mode"
                          className="h-9 w-[148px] whitespace-nowrap rounded-xl bg-background [&>span]:truncate"
                        >
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="off">
                            {t("notificationModeOff")}
                          </SelectItem>
                          <SelectItem value="simple">
                            {t("notificationModeSimple")}
                          </SelectItem>
                          <SelectItem value="milestones">
                            {t("notificationModeMilestones")}
                          </SelectItem>
                        </SelectContent>
                      </Select>
                    </div>
                  </section>

                  <section
                    data-setting="lunch"
                    className={`space-y-3 rounded-xl border border-gray-200/80 bg-white/35 p-3 shadow-sm dark:border-gray-700 dark:bg-black/10 ${
                      highlightedSetting === "lunch" ? "setting-highlight" : ""
                    }`}
                  >
                    <div className="flex items-center justify-between gap-4">
                      <Label
                        htmlFor="lunch-enabled"
                        className="flex items-center gap-2 text-sm dark:text-gray-200"
                      >
                        <Coffee size={16} />
                        {t("lunchBreak")}
                      </Label>
                      <Switch
                        id="lunch-enabled"
                        checked={lunchEnabled}
                        onCheckedChange={handleLunchEnabledChange}
                      />
                    </div>
                    {lunchEnabled && (
                      <div className="space-y-3 border-t border-gray-200/70 pt-3 dark:border-gray-700/70">
                        <div className="grid grid-cols-[minmax(0,1fr)_120px] items-end gap-3">
                          <TimeSelector
                            id="lunchStartTime"
                            label={t("lunchStartTime")}
                            value={lunchStartTime}
                            compact
                            onChange={(hour, minute) =>
                              setLunchStartTime(`${hour}:${minute}`)
                            }
                          />
                          <div className="space-y-1.5">
                            <Label className="text-xs text-gray-500 dark:text-gray-400">
                              {t("lunchDuration")}
                            </Label>
                            <Select
                              value={String(lunchDurationMinutes)}
                              onValueChange={(value) =>
                                setLunchDurationMinutes(Number(value))
                              }
                            >
                              <SelectTrigger className="h-9 rounded-xl bg-background">
                                <SelectValue />
                              </SelectTrigger>
                              <SelectContent>
                                {/* 国内午休两小时很常见（12:00–14:00），
                                    120 比 45 更该出现在这个列表里。 */}
                                {[30, 60, 90, 120].map((minutes) => (
                                  <SelectItem key={minutes} value={String(minutes)}>
                                    {t("minutesShort", { count: minutes })}
                                  </SelectItem>
                                ))}
                              </SelectContent>
                            </Select>
                          </div>
                        </div>
                        <div className="flex items-center justify-between gap-3">
                          <Label
                            htmlFor="lunch-start-notification"
                            className="text-sm font-normal dark:text-gray-200"
                          >
                            {t("lunchStartReminder")}
                          </Label>
                          <Switch
                            id="lunch-start-notification"
                            checked={lunchStartNotificationEnabled}
                            onCheckedChange={handleLunchStartNotificationChange}
                          />
                        </div>
                        <div className="flex items-center justify-between gap-3">
                          <Label
                            htmlFor="lunch-end-notification"
                            className="text-sm font-normal dark:text-gray-200"
                          >
                            {t("lunchEndReminder")}
                          </Label>
                          <Switch
                            id="lunch-end-notification"
                            checked={lunchEndNotificationEnabled}
                            onCheckedChange={handleLunchEndNotificationChange}
                          />
                        </div>
                        {!lunchWithinShift && (
                          <p
                            role="alert"
                            className="text-xs leading-5 text-red-600 dark:text-red-400"
                          >
                            {t("lunchOutsideShift")}
                          </p>
                        )}
                        <p className="text-xs leading-5 text-gray-500 dark:text-gray-400">
                          {showSalary ? t("lunchPauseNote") : t("lunchPauseNoteNoSalary")}
                        </p>
                      </div>
                    )}
                  </section>

                  <section
                    data-setting="microBreak"
                    className={`space-y-3 rounded-xl border border-gray-200/80 bg-white/35 p-3 shadow-sm dark:border-gray-700 dark:bg-black/10 ${
                      highlightedSetting === "microBreak" ? "setting-highlight" : ""
                    }`}
                  >
                    <div className="flex items-center justify-between gap-4">
                      <Label
                        htmlFor="micro-break-enabled"
                        className="flex items-center gap-2 text-sm dark:text-gray-200"
                      >
                        <GlassWater size={16} />
                        {t("microBreakReminder")}
                      </Label>
                      <Switch
                        id="micro-break-enabled"
                        checked={microBreakEnabled}
                        onCheckedChange={handleMicroBreakEnabledChange}
                      />
                    </div>
                    {microBreakEnabled && (
                      <div className="space-y-3 border-t border-gray-200/70 pt-3 dark:border-gray-700/70">
                        <div className="flex items-center justify-between gap-3">
                          <Label className="text-sm font-normal dark:text-gray-200">
                            {t("microBreakInterval")}
                          </Label>
                          <Select
                            value={String(microBreakIntervalMinutes)}
                            onValueChange={(value) =>
                              setMicroBreakIntervalMinutes(Number(value))
                            }
                          >
                            <SelectTrigger className="h-9 w-[120px] rounded-xl bg-background">
                              <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                              {[30, 45, 60, 90].map((minutes) => (
                                <SelectItem key={minutes} value={String(minutes)}>
                                  {t("minutesShort", { count: minutes })}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                        <p className="text-xs leading-5 text-gray-500 dark:text-gray-400">
                          {t("microBreakEffectiveTimeNote")}
                        </p>
                      </div>
                    )}
                  </section>

                  <SalarySettings
                    desktop
                    anchor="salary"
                    highlighted={highlightedSetting === "salary"}
                    enabled={showSalary}
                    onEnabledChange={setShowSalary}
                    salaryType={salaryType}
                    onSalaryTypeChange={setSalaryType}
                    salaryAmount={salaryAmount}
                    onSalaryAmountChange={setSalaryAmount}
                    monthlyWorkingDays={monthlyWorkingDays}
                    onMonthlyWorkingDaysChange={setMonthlyWorkingDays}
                    maskAmountField={maskAmountField}
                    onMaskAmountFieldChange={setMaskAmountField}
                  />

                  <section className="overflow-hidden rounded-xl border border-gray-200/80 bg-white/35 shadow-sm dark:border-gray-700 dark:bg-black/10">
                    <button
                      type="button"
                      onClick={() =>
                        void openDesktopUrl(
                          `${siteConfig.baseUrl}/${contentLang}/about`
                        )
                      }
                      className="flex w-full items-center justify-between gap-3 px-3 py-2.5 text-left text-sm transition-colors hover:bg-black/5 dark:text-gray-200 dark:hover:bg-white/5"
                    >
                      <span className="flex items-center gap-2">
                        <Info className="h-4 w-4" />
                        {t("aboutProject")}
                      </span>
                      <ExternalLink className="h-3.5 w-3.5 text-gray-400" />
                    </button>
                    <button
                      type="button"
                      onClick={() => void openDesktopUrl(siteConfig.github)}
                      className="flex w-full items-center justify-between gap-3 border-t border-gray-200/70 px-3 py-2.5 text-left text-sm transition-colors hover:bg-black/5 dark:border-gray-700/70 dark:text-gray-200 dark:hover:bg-white/5"
                    >
                      <span className="flex items-center gap-2">
                        <Github className="h-4 w-4" />
                        {t("githubRepository")}
                      </span>
                      <ExternalLink className="h-3.5 w-3.5 text-gray-400" />
                    </button>
                    <button
                      type="button"
                      onClick={() => void handleCheckForUpdates()}
                      disabled={
                        desktopUpdateStatus === "checking" ||
                        desktopUpdateStatus === "predownloading" ||
                        desktopUpdateStatus === "mirrorInstalling" ||
                        desktopUpdateStatus === "installing"
                      }
                      className="grid w-full grid-cols-[minmax(0,1fr)_auto] items-center gap-2 border-t border-gray-200/70 px-3 py-2.5 text-left text-sm transition-colors hover:bg-black/5 disabled:cursor-wait disabled:opacity-60 dark:border-gray-700/70 dark:text-gray-200 dark:hover:bg-white/5"
                    >
                      <span
                        role="status"
                        aria-live="polite"
                        className={`flex min-w-0 items-center gap-2 ${
                          desktopUpdateStatus === "latest"
                            ? "text-emerald-600 dark:text-emerald-400"
                            : ""
                        }`}
                      >
                        <RefreshCw
                          className={`h-4 w-4 shrink-0 ${
                            desktopUpdateStatus === "checking" ||
                            desktopUpdateStatus === "predownloading" ||
                            desktopUpdateStatus === "mirrorInstalling" ||
                            desktopUpdateStatus === "installing"
                              ? "animate-spin"
                              : ""
                          }`}
                        />
                        <span className="truncate">
                          {IS_MSSTORE_BUILD
                            ? t("checkForUpdatesInStore")
                            : desktopUpdateStatus === "checking"
                            ? t("checkingForUpdates")
                            : desktopUpdateStatus === "directFailed"
                              ? t("retryWithMirror")
                              : desktopUpdateStatus === "predownloading" ||
                                  desktopUpdateStatus === "mirrorInstalling"
                                ? t("downloadingUpdate")
                              : desktopUpdateStatus === "predownloaded"
                                ? t("restartToUpdate")
                                : desktopUpdateStatus === "available"
                                  ? t("downloadUpdate")
                                  : desktopUpdateStatus === "installing"
                                    ? t("installingUpdate")
                                    : desktopUpdateStatus === "latest"
                                      ? t("upToDate")
                                      : t("checkForUpdates")}
                        </span>
                      </span>
                      {desktopCurrentVersion && (
                        <span
                          dir="ltr"
                          className="flex shrink-0 items-center gap-1.5 rounded-md border border-gray-200 bg-white/70 px-2 py-1 font-mono text-[11px] leading-none text-gray-600 shadow-sm dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300"
                        >
                          <span>v{desktopCurrentVersion}</span>
                          {desktopLatestVersion &&
                            desktopLatestVersion !== desktopCurrentVersion && (
                              <>
                                <span className="text-gray-400">→</span>
                                <span className="font-semibold text-emerald-600 dark:text-emerald-400">
                                  v{desktopLatestVersion}
                                </span>
                              </>
                            )}
                        </span>
                      )}
                    </button>
                    {desktopUpdateStatus !== "idle" &&
                      desktopUpdateStatus !== "checking" &&
                      desktopUpdateStatus !== "installing" &&
                      desktopUpdateStatus !== "latest" &&
                      desktopUpdateStatus !== "available" &&
                      desktopUpdateStatus !== "predownloading" &&
                      desktopUpdateStatus !== "mirrorInstalling" &&
                      desktopUpdateStatus !== "predownloaded" && (
                        <p
                          role="status"
                          className="border-t border-gray-200/70 px-3 py-2 text-xs text-amber-600 dark:border-gray-700/70 dark:text-amber-400"
                        >
                          {desktopUpdateStatus === "unconfigured"
                            ? t("updateNotConfigured")
                            : desktopUpdateStatus === "directFailed"
                              ? // 明确告诉用户镜像是第三方，以及签名校验没有被跳过。
                                t("updateMirrorNotice", {
                                  host: UPDATE_MIRROR_HOST,
                                })
                              : t("updateFailed")}
                        </p>
                      )}
                  </section>
            </div>
          </div>
        )}
        </div>
      </Card>

      {/* 说明区。冷启动的搜索流量第一眼只看到一个表单，不知道这是什么，跳出率
          会很高；同时主应用页的可见正文原本只有 110–285 字符，内容过薄。
          与页脚同样渲染在设置态（服务端首屏状态），所以这些文字都在初始 HTML 里。
          刻意不放截图：可交互的实物就在正上方，静态图既冗余又对文字量毫无贡献。 */}
      {!showCountdown && !isAppShell && (
        <section className="mt-10">
          <h2 className="text-center text-lg font-semibold text-gray-800 dark:text-gray-100">
            {t("landingTagline")}
          </h2>
          <p className="mx-auto mt-3 max-w-prose text-center text-sm leading-6 text-gray-600 dark:text-gray-400">
            {t("landingBody")}
          </p>

          <ul className="mt-8 space-y-5">
            {[1, 2, 3].map((n) => (
              <li key={n}>
                <h3 className="text-sm font-semibold text-gray-800 dark:text-gray-200">
                  {t(`landingFeature${n}Title`)}
                </h3>
                <p className="mt-1 text-sm leading-6 text-gray-600 dark:text-gray-400">
                  {t(`landingFeature${n}Body`)}
                </p>
              </li>
            ))}
          </ul>
        </section>
      )}

      {/* 内容页入口。渲染在设置态（也就是服务端首屏的状态），因此这些链接
          必然出现在初始 HTML 里 —— 否则内容页会成为无内链的孤儿页，抓取权重
          会明显打折。内容页只有中英两版，按界面语言直接指向正确的一版，
          避免先跳转再重定向。PWA 独立窗口下卡片占满全屏，页脚会落到屏幕外，
          故不渲染。 */}
      {!showCountdown && !isAppShell && (
        <>
        <div className="mt-8 flex w-full flex-wrap items-center justify-center gap-3">
          <MicrosoftStoreBadge className="flex min-h-11 items-center" />
          <Link
            href={`/${contentLang}/download`}
            className="flex h-11 w-[161px] items-center gap-2 rounded-[8px] border border-white/15 bg-[#1a1a1a] px-3 text-white shadow-sm transition-colors hover:bg-black focus:outline-none focus:ring-2 focus:ring-gray-400 focus:ring-offset-2 dark:border-black/10 dark:bg-white dark:text-[#1a1a1a] dark:hover:bg-gray-100 dark:focus:ring-offset-gray-900"
          >
            <Download className="h-5 w-5 shrink-0" aria-hidden="true" />
            <span className="min-w-0 text-left leading-none rtl:text-right">
              <span className="block text-[10px] font-medium opacity-75">
                {t("moreVersions")}
              </span>
              <span className="mt-1 block whitespace-nowrap text-[10px] font-semibold">
                {t("moreVersionsDescription")}
              </span>
            </span>
          </Link>
        </div>
        {/* 圆点分隔符在窄屏换行后会跑到新行开头，让最后一项看起来偏右。
            这里只用均匀间距，确保每一行的链接文字本身都真正居中。 */}
        <footer className="mt-8 flex w-full flex-wrap items-center justify-center gap-x-3 gap-y-1 text-center text-xs font-semibold text-gray-600 dark:text-gray-300">
          {[
            { href: `/${contentLang}/faq`, label: t("faq") },
            { href: `/${contentLang}/how-it-works`, label: t("howItWorks") },
            { href: `/${contentLang}/about`, label: t("aboutProject") },
            { href: `/${contentLang}/privacy`, label: t("privacyPolicy") },
          ].map(({ href, label }) => (
            <Link
              key={href}
              href={href}
              className="whitespace-nowrap transition-colors hover:text-gray-800 dark:hover:text-gray-200"
            >
              {label}
            </Link>
          ))}
        </footer>
        </>
      )}
      </div>
    </div>
  );
}
