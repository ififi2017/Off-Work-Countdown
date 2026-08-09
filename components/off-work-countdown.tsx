"use client";

import { useState, useEffect, useCallback, useMemo, useRef } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
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
  RefreshCw,
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
  getShiftBounds,
  calculateProgress as calculateShiftProgress,
  getDailySalary as calculateDailySalary,
  DEFAULT_MONTHLY_WORKING_DAYS,
  DEFAULT_WORKDAYS,
  parseWorkdays,
  serializeWorkdays,
  isWorkday,
} from "@/lib/countdown";
import { WorkdaySelector } from "./WorkdaySelector";
import { PeriodSummary } from "./PeriodSummary";
import { summarize, startOfWeek, startOfYear } from "@/lib/summary";
import { useTranslation } from "react-i18next";
import { resolveContentLocale } from "@/lib/content-locales";
import { decodeShift } from "@/lib/share";
import { track } from "@/lib/track";
import { siteConfig } from "@/config/site";
import {
  requestNotificationPermission,
  showNotification,
} from "@/lib/notify";
import {
  emptyDesktopCountdownState,
  getDesktopAutostartEnabled,
  getMiniWindowSettings,
  readDesktopCountdownState,
  setDesktopAutostartEnabled,
  stopDesktopCountdown,
  writeDesktopCountdownState,
} from "@/lib/desktop-state";

/** 下班前多久提醒。与 translation.json 里 "reminder" 的文案保持一致。 */
const REMINDER_LEAD_MS = 15 * 60 * 1000;

/** 由 next.config.mjs 在构建期注入，见 docs/PLAN-M5-TAURI.md 决策 1 与 7。 */
const IS_DESKTOP_BUILD = process.env.NEXT_PUBLIC_BUILD_TARGET === "desktop";

type DesktopUpdateStatus =
  | "idle"
  | "checking"
  | "installing"
  | "latest"
  | "unconfigured"
  | "error";

// Helper function to safely get item from localStorage
const getLocalStorageItem = (key: string, defaultValue: string) => {
  if (typeof window !== "undefined") {
    return localStorage.getItem(key) || defaultValue;
  }
  return defaultValue;
};

export interface OffWorkCountdownProps {
  lang: string;
}

interface SalarySettingsProps {
  desktop?: boolean;
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
      className={
        desktop
          ? "rounded-xl border border-gray-200/80 bg-white/35 p-3 shadow-sm dark:border-gray-700 dark:bg-black/10"
          : "border-t border-gray-200 pt-3 dark:border-gray-700"
      }
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
  const [workdays, setWorkdays] = useState<number[]>(DEFAULT_WORKDAYS);
  const [showCountdown, setShowCountdown] = useState(false);
  const [showDesktopSettings, setShowDesktopSettings] = useState(false);
  const [timeLeft, setTimeLeft] = useState("");
  const [progress, setProgress] = useState(0);
  const [theme, setTheme] = useState<Theme>("auto");
  const [isMounted, setIsMounted] = useState(false);
  const [showConfetti, setShowConfetti] = useState(false);
  const [formError, setFormError] = useState("");
  const reminderFiredRef = useRef(false);

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
  const [moneyEarned, setMoneyEarned] = useState(0);
  const [hideEarnings, setHideEarnings] = useState(false);
  const [maskAmountField, setMaskAmountField] = useState(true);
  const [activeBounds, setActiveBounds] = useState<{
    start: Date;
    end: Date;
    leadReminderArmed: boolean;
  } | null>(null);
  const [desktopStateRestored, setDesktopStateRestored] = useState(
    !IS_DESKTOP_BUILD
  );
  const [launchAtLogin, setLaunchAtLogin] = useState(false);
  const [autostartLoaded, setAutostartLoaded] = useState(!IS_DESKTOP_BUILD);
  const [autostartPending, setAutostartPending] = useState(false);
  const [desktopSettingError, setDesktopSettingError] = useState("");
  const [desktopUpdateStatus, setDesktopUpdateStatus] =
    useState<DesktopUpdateStatus>("idle");
  const [desktopCurrentVersion, setDesktopCurrentVersion] = useState("");
  const [desktopLatestVersion, setDesktopLatestVersion] = useState("");
  const [desktopPlatform, setDesktopPlatform] = useState<
    "macos" | "windows" | "other"
  >("other");

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

  // 加载本地存储的设置
  useEffect(() => {
    if (isMounted) {
      setStartTime(getLocalStorageItem("startTime", "09:00"));
      setEndTime(getLocalStorageItem("endTime", "18:00"));
      setReminder(getLocalStorageItem("reminder", "false") === "true");
      // 这里不能用 getLocalStorageItem 的默认值兜底：空字符串是「一天都不上班」
      // 这个合法状态，与「从未设置过」必须区分，交给 parseWorkdays 处理。
      setWorkdays(
        parseWorkdays(
          typeof window !== "undefined"
            ? localStorage.getItem("workdays")
            : null
        )
      );
      setSalaryType((getLocalStorageItem("salaryType", "monthly") as "monthly" | "daily"));
      setSalaryAmount(getLocalStorageItem("salaryAmount", ""));
      setMonthlyWorkingDays(
        getLocalStorageItem(
          "monthlyWorkingDays",
          DEFAULT_MONTHLY_WORKING_DAYS.toString()
        )
      );
      setShowSalary(getLocalStorageItem("showSalary", "false") === "true");
      setHideEarnings(getLocalStorageItem("hideEarnings", "false") === "true");
      setSettingsLoaded(true);
    }
  }, [isMounted]);

  // 桌面端从 Tauri Store 恢复正在进行的绝对班次。只恢复尚未结束的快照，
  // 避免第二天打开应用时把昨天的「运行中」误算成今天的新班次。
  useEffect(() => {
    if (!IS_DESKTOP_BUILD || !settingsLoaded) return;

    let cancelled = false;
    void readDesktopCountdownState()
      .then((state) => {
        if (
          cancelled ||
          !state?.running ||
          state.endAtMs <= Date.now() ||
          state.endAtMs <= state.startAtMs
        ) {
          return;
        }
        const start = new Date(state.startAtMs);
        const end = new Date(state.endAtMs);
        setActiveBounds({
          start,
          end,
          leadReminderArmed: state.leadReminderArmed ?? false,
        });
        reminderFiredRef.current =
          end.getTime() - Date.now() <= REMINDER_LEAD_MS;
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
    void getDesktopAutostartEnabled()
      .then((enabled) => {
        if (!cancelled) setLaunchAtLogin(enabled);
      })
      .catch(() => {
        if (!cancelled) setDesktopSettingError(t("desktopSettingError"));
      })
      .finally(() => {
        if (!cancelled) setAutostartLoaded(true);
      });

    void getMiniWindowSettings()
      .then((settings) => {
        if (!cancelled) setDesktopPlatform(settings.platform);
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

    return () => {
      cancelled = true;
    };
  }, [t]);

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
    const { start, end } = getShiftBounds(shift.start, shift.end, new Date());
    reminderFiredRef.current = end.getTime() - Date.now() <= REMINDER_LEAD_MS;
    setActiveBounds({
      start,
      end,
      leadReminderArmed: end.getTime() - Date.now() > REMINDER_LEAD_MS,
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

  // 保存设置到 localStorage。两个前提：本地设置已读入 state（见 settingsLoaded
  // 的说明），且不处于分享视图——那是别人的班次，不该覆盖访问者自己保存的时间，
  // 等他点了「换成我的时间」再恢复正常持久化。
  useEffect(() => {
    if (settingsLoaded && !isSharedView) {
      localStorage.setItem("startTime", startTime);
      localStorage.setItem("endTime", endTime);
      localStorage.setItem("reminder", reminder.toString());
      localStorage.setItem("workdays", serializeWorkdays(workdays));
      localStorage.setItem("salaryType", salaryType);
      localStorage.setItem("salaryAmount", salaryAmount);
      localStorage.setItem("monthlyWorkingDays", monthlyWorkingDays);
      localStorage.setItem("showSalary", showSalary.toString());
      localStorage.setItem("hideEarnings", hideEarnings.toString());
    }
  }, [settingsLoaded, isSharedView, startTime, endTime, reminder, workdays, salaryType, salaryAmount, monthlyWorkingDays, showSalary, hideEarnings]);

  const getDailySalary = useCallback(() => {
    return calculateDailySalary(
      salaryAmount,
      salaryType,
      parseFloat(monthlyWorkingDays) || DEFAULT_MONTHLY_WORKING_DAYS
    );
  }, [salaryAmount, salaryType, monthlyWorkingDays]);

  // 将 UI 的运行状态镜像为一个原子快照。Rust 与迷你窗都只消费这组绝对
  // 时间戳，不需要理解跨夜班次、工作日等业务规则。
  useEffect(() => {
    if (!IS_DESKTOP_BUILD || !settingsLoaded || !desktopStateRestored) return;

    const state =
      showCountdown && activeBounds
        ? {
            startAtMs: activeBounds.start.getTime(),
            endAtMs: activeBounds.end.getTime(),
            running: true,
            reminder,
            leadReminderArmed: activeBounds.leadReminderArmed,
            notificationTitle: t("offWorkReminder"),
            leadNotificationBody: t("fifteenMinutesLeft"),
            completionNotificationBody: t("offWorkTime"),
            showSalary,
            hideEarnings,
            dailySalary: showSalary ? getDailySalary() : null,
            lang,
          }
        : emptyDesktopCountdownState(lang);

    void writeDesktopCountdownState(state).catch(() => {
      // 桌面快照失败不应打断 Web 共用的主倒计时界面。
    });
  }, [
    settingsLoaded,
    desktopStateRestored,
    showCountdown,
    activeBounds,
    reminder,
    showSalary,
    hideEarnings,
    getDailySalary,
    lang,
    t,
  ]);

  const calculateProgress = useCallback(() => {
    if (activeBounds) {
      const total = activeBounds.end.getTime() - activeBounds.start.getTime();
      const elapsed = Date.now() - activeBounds.start.getTime();
      return Math.max(0, Math.min(100, (elapsed / total) * 100));
    }
    return calculateShiftProgress(startTime, endTime, new Date());
  }, [activeBounds, startTime, endTime]);

  useEffect(() => {
    let interval: NodeJS.Timeout;
    if (showCountdown) {
      const updateCountdown = () => {
        const now = new Date();
        const { start, end } =
          activeBounds ?? getShiftBounds(startTime, endTime, now);

        const diff = end.getTime() - now.getTime();
        if (diff <= 0) {
          setTimeLeft(t("offWorkTime"));
          setProgress(100);
          setShowConfetti(true);
          if (showSalary) {
            const dailySalary = getDailySalary();
            if (dailySalary !== null) {
              setMoneyEarned(dailySalary);
            }
          }
          clearInterval(interval);
        } else {
          const hours = Math.floor(diff / (1000 * 60 * 60));
          const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
          const seconds = Math.floor((diff % (1000 * 60)) / 1000);

          // 计算总工作时间（小时）
          const totalWorkHours =
            (end.getTime() - start.getTime()) / (1000 * 60 * 60);

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
            diff <= REMINDER_LEAD_MS
          ) {
            reminderFiredRef.current = true;
            void showNotification(t("offWorkReminder"), t("fifteenMinutesLeft"));
          }

          // Calculate money earned
          if (showSalary && salaryAmount) {
            const currentProgress = calculateProgress();
            const dailySalary = getDailySalary();
            if (dailySalary !== null) {
              setMoneyEarned((dailySalary * currentProgress) / 100);
            }
          }
        }
      };

      updateCountdown(); // 立即运行
      interval = setInterval(updateCountdown, 1000);
    }
    return () => clearInterval(interval);
  }, [showCountdown, startTime, endTime, activeBounds, reminder, calculateProgress, t, showSalary, salaryAmount, getDailySalary]);

  const handleStart = () => {
    if (startTime === endTime) {
      setFormError(t("sameTimeError"));
      return;
    }

    const now = new Date();
    const { start, end } = getShiftBounds(startTime, endTime, now);
    if (start > now) {
      const timeDiff = start.getTime() - now.getTime();
      const hours = Math.floor(timeDiff / (1000 * 60 * 60));
      const minutes = Math.floor((timeDiff % (1000 * 60 * 60)) / (1000 * 60));

      setFormError(t("futureStartTimeError", { hours, minutes }));
      return;
    }

    if (startTime && endTime) {
      setFormError("");
      // 开始时距下班已不足 15 分钟的话，直接标记为已提醒——否则倒计时的第一个
      // tick 就会立刻弹出「还有十五分钟」，而用户是刚点的开始，这属于打扰。
      reminderFiredRef.current = end.getTime() - now.getTime() <= REMINDER_LEAD_MS;
      setActiveBounds({
        start,
        end,
        leadReminderArmed: end.getTime() - now.getTime() > REMINDER_LEAD_MS,
      });
      setShowCountdown(true);
      setProgress(calculateProgress()); // Set initial progress
      track("countdown_start");
      if (reminder) void requestNotificationPermission();
    }
  };

  const handleAutostartChange = async (enabled: boolean) => {
    const previous = launchAtLogin;
    setLaunchAtLogin(enabled);
    setAutostartPending(true);
    setDesktopSettingError("");
    try {
      await setDesktopAutostartEnabled(enabled);
    } catch {
      setLaunchAtLogin(previous);
      setDesktopSettingError(t("desktopSettingError"));
    } finally {
      setAutostartPending(false);
    }
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
          : "error"
      );
    }
  };

  const handleReturn = () => {
    if (IS_DESKTOP_BUILD) {
      void stopDesktopCountdown(lang).catch(() => {
        // The normal snapshot effect remains a fallback.
      });
    }
    setShowCountdown(false);
    setActiveBounds(null);
    setProgress(0);
    setTimeLeft("");
    setShowConfetti(false);
    // 退出分享视图：恢复访问者自己保存的时间，并重新开启持久化。
    if (isSharedView) exitSharedView();
  };

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
    setActiveBounds(null);
    setProgress(0);
    setTimeLeft("");
    setShowConfetti(false);
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
    if (!isMounted || !showCountdown) return null;
    const now = new Date();
    const common = {
      now,
      workdays,
      startTime,
      endTime,
      todayProgress: progress,
      dailySalary: showSalary ? getDailySalary() : null,
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
    progress,
    showSalary,
    getDailySalary,
    t,
  ]);

  // 今天这一班是否落在工作日。挂载前一律按 true 处理：这个判断依赖当前时间，
  // 服务端与客户端的结果可能不同，直接算会造成 hydration 不匹配。
  // 判断用班次的开始时刻而非「现在」，这样跨夜班归属正确（见 isWorkday 注释）。
  const todayIsWorkday =
    !isMounted ||
    isWorkday(
      activeBounds?.start ?? getShiftBounds(startTime, endTime, new Date()).start,
      workdays
    );

  return (
    <div
      className={`min-h-screen transition-colors duration-1000 ease-in-out ${
        isAppShell ? "flex flex-col items-stretch justify-start p-0" : "flex items-center justify-center p-4"
      } ${
        isCustomTheme ? "" : "bg-gray-100 dark:bg-gray-900"
      } ${
        isAppShell
          ? "pl-[env(safe-area-inset-left)] pr-[env(safe-area-inset-right)] pt-[env(safe-area-inset-top)] pb-[env(safe-area-inset-bottom)]"
          : ""
      }`}
    >
      <Background theme={theme} />
      <Confetti trigger={showConfetti} />

      {IS_DESKTOP_BUILD && (
        <div
          data-tauri-drag-region="deep"
          aria-hidden="true"
          className="fixed inset-x-20 top-0 z-50 h-8 cursor-grab active:cursor-grabbing"
        />
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
        <CardHeader
          className={
            isAppShell
              ? IS_DESKTOP_BUILD
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
              {IS_DESKTOP_BUILD && showDesktopSettings && (
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
              )}
              <h1
                data-tauri-drag-region={IS_DESKTOP_BUILD ? "deep" : undefined}
                title={
                  IS_DESKTOP_BUILD && showDesktopSettings
                    ? t("settings")
                    : t("offWorkCountdown")
                }
                className={
                  IS_DESKTOP_BUILD
                    ? "min-w-0 truncate whitespace-nowrap text-xl font-bold leading-none tracking-tight dark:text-white"
                    : "text-2xl font-bold leading-none tracking-tight dark:text-white"
                }
              >
                {IS_DESKTOP_BUILD && showDesktopSettings
                  ? t("settings")
                  : t("offWorkCountdown")}
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
              {IS_DESKTOP_BUILD && !showDesktopSettings ? (
                <Button
                  variant="outline"
                  size="icon"
                  className="h-9 w-9 rounded-xl border-input bg-background shadow-sm"
                  onClick={() => setShowDesktopSettings(true)}
                  aria-label={t("settings")}
                  title={t("settings")}
                >
                  <Settings2 className="h-[1.15rem] w-[1.15rem]" />
                </Button>
              ) : !IS_DESKTOP_BUILD ? (
                <ThemeToggle
                  theme={theme}
                  onThemeChange={handleThemeChange}
                />
              ) : null}
              <LanguageSelector
                currentLang={lang}
                languageMap={languageNames}
                compact={IS_DESKTOP_BUILD}
              />
            </div>
          </div>
        </CardHeader>
        <CardContent
          className={
            isAppShell
              ? `relative z-10 min-h-0 flex-1 flex flex-col p-6 pt-2 pb-4 ${
                  IS_DESKTOP_BUILD && showDesktopSettings
                    ? "justify-start overflow-y-auto"
                    : IS_DESKTOP_BUILD && formError
                      ? "justify-start overflow-y-auto"
                      : "justify-center overflow-visible"
                }`
              : undefined
          }
        >
          <AnimatePresence mode="wait">
            {IS_DESKTOP_BUILD && showDesktopSettings ? (
              <motion.div
                key="settings"
                initial={{ opacity: 0, x: 16 }}
                animate={{ opacity: 1, x: 0 }}
                exit={{ opacity: 0, x: 16 }}
                transition={{ duration: 0.2 }}
                className="space-y-3"
              >
                <section className="flex items-center justify-between rounded-xl border border-gray-200/80 bg-white/35 p-3 shadow-sm dark:border-gray-700 dark:bg-black/10">
                  <Label className="text-sm dark:text-gray-200">
                    {t("toggleTheme")}
                  </Label>
                  <ThemeToggle
                    theme={theme}
                    onThemeChange={handleThemeChange}
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
                      disabled={!autostartLoaded || autostartPending}
                      onCheckedChange={handleAutostartChange}
                    />
                  </div>
                  <div className="flex items-center justify-between gap-4 text-sm text-gray-600 dark:text-gray-400">
                    <span className="flex items-center gap-2">
                      <Keyboard size={16} />
                      {t("globalShortcut")}
                    </span>
                    <kbd className="rounded-md border border-gray-300 bg-white/70 px-2 py-1 font-mono text-xs text-gray-700 shadow-sm dark:border-gray-600 dark:bg-gray-800 dark:text-gray-200">
                      {desktopPlatform === "macos"
                        ? "⌘ + Shift + O"
                        : "Ctrl + Shift + O"}
                    </kbd>
                  </div>
                  {desktopSettingError && (
                    <p
                      role="alert"
                      className="text-xs text-red-600 dark:text-red-400"
                    >
                      {desktopSettingError}
                    </p>
                  )}
                </section>

                <SalarySettings
                  desktop
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
                        `${siteConfig.baseUrl}/${contentLang}/faq`
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
                      desktopUpdateStatus === "installing"
                    }
                    className="flex w-full items-center justify-between gap-3 border-t border-gray-200/70 px-3 py-2.5 text-left text-sm transition-colors hover:bg-black/5 disabled:cursor-wait disabled:opacity-60 dark:border-gray-700/70 dark:text-gray-200 dark:hover:bg-white/5"
                  >
                    <span className="flex min-w-0 items-center gap-2">
                      <RefreshCw
                        className={`h-4 w-4 shrink-0 ${
                          desktopUpdateStatus === "checking" ||
                          desktopUpdateStatus === "installing"
                            ? "animate-spin"
                            : ""
                        }`}
                      />
                      <span className="truncate">
                        {desktopUpdateStatus === "checking"
                          ? t("checkingForUpdates")
                          : desktopUpdateStatus === "installing"
                            ? t("installingUpdate")
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
                    desktopUpdateStatus !== "installing" && (
                      <p
                        role="status"
                        className={`border-t border-gray-200/70 px-3 py-2 text-xs dark:border-gray-700/70 ${
                          desktopUpdateStatus === "latest"
                            ? "text-emerald-600 dark:text-emerald-400"
                            : "text-amber-600 dark:text-amber-400"
                        }`}
                      >
                        {desktopUpdateStatus === "latest"
                          ? t("upToDate")
                          : desktopUpdateStatus === "unconfigured"
                            ? t("updateNotConfigured")
                            : t("updateFailed")}
                      </p>
                    )}
                </section>
              </motion.div>
            ) : !showCountdown ? (
              <motion.div
                key="input"
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -20 }}
                transition={{ duration: 0.3 }}
                className={IS_DESKTOP_BUILD ? "space-y-3" : "space-y-4"}
              >
                <div className={IS_DESKTOP_BUILD ? "grid grid-cols-2 gap-3" : "contents"}>
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

                <div className="flex min-h-9 items-center gap-2">
                  <Switch
                    id="reminder"
                    checked={reminder}
                    onCheckedChange={setReminder}
                  />
                  <Label htmlFor="reminder" className="dark:text-gray-200">
                    {t("reminder")}
                  </Label>
                </div>

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
                initial={{ opacity: 0, y: 12 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -12 }}
                transition={{ duration: 0.2 }}
                className={IS_DESKTOP_BUILD ? "w-full space-y-3" : "space-y-6"}
              >
                <CountdownDisplay
                  timeLeft={timeLeft}
                  progress={progress}
                  dense={IS_DESKTOP_BUILD}
                />
                {summaryRows && (
                  <PeriodSummary
                    lang={lang}
                    note={t("summaryEstimateNote")}
                    rows={summaryRows}
                    hideEarnings={hideEarnings}
                    compact={IS_DESKTOP_BUILD}
                    currentEarnings={
                      showSalary
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
        {!(IS_DESKTOP_BUILD && showDesktopSettings) && (
          <CardFooter
            className={
              IS_DESKTOP_BUILD
                ? "relative z-0 flex justify-center border-t border-white/30 bg-white/20 p-3 backdrop-blur-sm dark:border-white/10 dark:bg-black/10"
                : "flex justify-center"
            }
          >
          <AnimatePresence mode="wait">
            {!showCountdown ? (
              <motion.div
                key="start"
                initial={{ opacity: 0, scale: 0.8 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.8 }}
                transition={{ duration: 0.3 }}
              >
                <Button onClick={handleStart}>{t("startCountdown")}</Button>
              </motion.div>
            ) : (
              <motion.div
                key="return"
                initial={{ opacity: 0, scale: 0.8 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.8 }}
                transition={{ duration: 0.3 }}
                className="flex gap-2"
              >
                <Button
                  variant="outline"
                  className={IS_DESKTOP_BUILD ? "h-9 rounded-lg px-4" : undefined}
                  onClick={handleReturn}
                >
                  <ArrowLeft className="me-2 h-4 w-4" /> {t("return")}
                </Button>
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
        )}
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

      {/* 内容页入口。渲染在设置态（也就是服务端首屏的状态），因此这两个链接
          必然出现在初始 HTML 里 —— 否则内容页会成为无内链的孤儿页，抓取权重
          会明显打折。内容页只有中英两版，按界面语言直接指向正确的一版，
          避免先跳转再重定向。PWA 独立窗口下卡片占满全屏，页脚会落到屏幕外，
          故不渲染。 */}
      {!showCountdown && !isAppShell && (
        <footer className="mt-8 flex items-center justify-center gap-3 text-xs text-gray-500 dark:text-gray-400">
          <Link
            href={`/${contentLang}/faq`}
            className="transition-colors hover:text-gray-800 dark:hover:text-gray-200"
          >
            {t("faq")}
          </Link>
          <span aria-hidden="true">·</span>
          <Link
            href={`/${contentLang}/how-it-works`}
            className="transition-colors hover:text-gray-800 dark:hover:text-gray-200"
          >
            {t("howItWorks")}
          </Link>
          <span aria-hidden="true">·</span>
          <Link
            href={`/${contentLang}/about`}
            className="transition-colors hover:text-gray-800 dark:hover:text-gray-200"
          >
            {t("aboutProject")}
          </Link>
        </footer>
      )}
      </div>
    </div>
  );
}
