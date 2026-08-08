"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardFooter,
  CardHeader,
} from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { ArrowLeft, Github, Coins } from "lucide-react";
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
import { languageNames, defaultLocale } from "@/i18n-config";
import {
  getShiftBounds,
  calculateProgress as calculateShiftProgress,
  getDailySalary as calculateDailySalary,
  DEFAULT_MONTHLY_WORKING_DAYS,
} from "@/lib/countdown";
import { Eye, EyeOff } from "lucide-react";
import { useTranslation } from "react-i18next";
import { resolveContentLocale } from "@/lib/content-locales";
import { decodeShift } from "@/lib/share";
import { track } from "@/lib/track";

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

export function OffWorkCountdown({ lang }: OffWorkCountdownProps) {
  const { t, i18n } = useTranslation();
  const [startTime, setStartTime] = useState("09:00");
  const [endTime, setEndTime] = useState("18:00");
  const [reminder, setReminder] = useState(false);
  const [showCountdown, setShowCountdown] = useState(false);
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
  const [isPWA, setIsPWA] = useState(false);
  const [moneyEarned, setMoneyEarned] = useState(0);
  const [hideEarnings, setHideEarnings] = useState(false);
  const [maskAmountField, setMaskAmountField] = useState(true);

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
      setIsPWA(isStandalone || isFullscreen || isMinimalUi || isIOSStandalone);
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
      localStorage.setItem("salaryType", salaryType);
      localStorage.setItem("salaryAmount", salaryAmount);
      localStorage.setItem("monthlyWorkingDays", monthlyWorkingDays);
      localStorage.setItem("showSalary", showSalary.toString());
      localStorage.setItem("hideEarnings", hideEarnings.toString());
    }
  }, [settingsLoaded, isSharedView, startTime, endTime, reminder, salaryType, salaryAmount, monthlyWorkingDays, showSalary, hideEarnings]);

  const getDailySalary = useCallback(() => {
    return calculateDailySalary(
      salaryAmount,
      salaryType,
      parseFloat(monthlyWorkingDays) || DEFAULT_MONTHLY_WORKING_DAYS
    );
  }, [salaryAmount, salaryType, monthlyWorkingDays]);

  const calculateProgress = useCallback(() => {
    return calculateShiftProgress(startTime, endTime, new Date());
  }, [startTime, endTime]);

  useEffect(() => {
    let interval: NodeJS.Timeout;
    if (showCountdown) {
      const updateCountdown = () => {
        const now = new Date();
        const { start, end } = getShiftBounds(startTime, endTime, now);

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

          if (
            reminder &&
            !reminderFiredRef.current &&
            diff <= 15 * 60 * 1000 &&
            diff > 14 * 60 * 1000 &&
            typeof window !== "undefined" &&
            "Notification" in window &&
            Notification.permission === "granted"
          ) {
            reminderFiredRef.current = true;
            try {
              new Notification(t("offWorkReminder"), {
                body: t("fifteenMinutesLeft"),
              });
            } catch {
              // Some platforms (e.g. Android Chrome) only allow notifications
              // via the service worker registration; ignore failures here.
            }
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
  }, [showCountdown, startTime, endTime, reminder, calculateProgress, t, showSalary, salaryAmount, getDailySalary]);

  const handleStart = () => {
    if (startTime === endTime) {
      setFormError(t("sameTimeError"));
      return;
    }

    const now = new Date();
    const { start } = getShiftBounds(startTime, endTime, now);
    if (start > now) {
      const timeDiff = start.getTime() - now.getTime();
      const hours = Math.floor(timeDiff / (1000 * 60 * 60));
      const minutes = Math.floor((timeDiff % (1000 * 60 * 60)) / (1000 * 60));

      setFormError(t("futureStartTimeError", { hours, minutes }));
      return;
    }

    if (startTime && endTime) {
      setFormError("");
      reminderFiredRef.current = false;
      setShowCountdown(true);
      setProgress(calculateProgress()); // Set initial progress
      track("countdown_start");
      if (
        reminder &&
        typeof window !== "undefined" &&
        "Notification" in window &&
        Notification.permission === "default"
      ) {
        Notification.requestPermission();
      }
    }
  };

  const handleReturn = () => {
    setShowCountdown(false);
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

  return (
    <div
      className={`min-h-screen transition-colors duration-1000 ease-in-out ${
        isPWA ? "flex flex-col items-stretch justify-start p-0" : "flex items-center justify-center p-4"
      } ${
        isCustomTheme ? "" : "bg-gray-100 dark:bg-gray-900"
      } ${
        isPWA
          ? "pl-[env(safe-area-inset-left)] pr-[env(safe-area-inset-right)] pt-[env(safe-area-inset-top)] pb-[env(safe-area-inset-bottom)]"
          : ""
      }`}
    >
      <Background theme={theme} />
      <Confetti trigger={showConfetti} />

      <div className={isPWA ? "flex flex-1 flex-col" : "w-full max-w-md"}>
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
        isPWA
          ? "max-w-none min-h-screen rounded-none shadow-none border-none bg-transparent flex flex-col"
          : ""
      }`}>
        <CardHeader className={isPWA ? "p-6 pb-3" : undefined}>
          <div className="flex justify-between items-center">
            <div className="flex items-center gap-2">
              {/* 这里用真正的 h1 而不是 shadcn 的 CardTitle：后者硬编码为 h3，
                  会排在下方说明区的 h2 前面，标题层级就颠倒了。原先另有一个
                  sr-only 的 h1，内容与这里完全相同，属于重复，已一并去掉。 */}
              <h1 className="text-2xl font-bold leading-none tracking-tight dark:text-white">
                {t("offWorkCountdown")}
              </h1>
              {!showCountdown && (
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
            <div className="flex items-center gap-2">
              <ThemeToggle theme={theme} onThemeChange={handleThemeChange} />
              <LanguageSelector
                currentLang={lang}
                languageMap={languageNames}
              />
            </div>
          </div>
        </CardHeader>
        <CardContent className={isPWA ? "flex-1 flex flex-col justify-center p-6 pt-2 pb-6" : undefined}>
          <AnimatePresence mode="wait">
            {!showCountdown ? (
              <motion.div
                key="input"
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -20 }}
                transition={{ duration: 0.3 }}
                className="space-y-4"
              >
                <TimeSelector
                  id="startTime"
                  label={t("startTime")}
                  value={startTime}
                  onChange={(hour, minute) =>
                    handleTimeChange("start", hour, minute)
                  }
                />
                <TimeSelector
                  id="endTime"
                  label={t("endTime")}
                  value={endTime}
                  onChange={(hour, minute) =>
                    handleTimeChange("end", hour, minute)
                  }
                />
                <div className="flex items-center gap-2">
                  <Switch
                    id="reminder"
                    checked={reminder}
                    onCheckedChange={setReminder}
                  />
                  <Label htmlFor="reminder" className="dark:text-gray-200">
                    {t("reminder")}
                  </Label>
                </div>

                <div className="pt-4 border-t border-gray-200 dark:border-gray-700">
                  <div className="flex items-center justify-between mb-4">
                    <Label className="flex items-center gap-2 dark:text-gray-200">
                      <Coins size={16} />
                      {t("salarySettings")}
                    </Label>
                    <Switch
                      checked={showSalary}
                      onCheckedChange={setShowSalary}
                    />
                  </div>
                  
                  <AnimatePresence>
                    {showSalary && (
                      <motion.div
                        initial={{ height: 0, opacity: 0 }}
                        animate={{ height: "auto", opacity: 1 }}
                        exit={{ height: 0, opacity: 0 }}
                        className="space-y-4 overflow-hidden"
                      >
                        <div className="grid grid-cols-2 gap-4">
                          <div className="space-y-2">
                            <Label className="text-xs dark:text-gray-400">{t("salaryType")}</Label>
                            <Select
                              value={salaryType}
                              onValueChange={(value) => setSalaryType(value as "monthly" | "daily")}
                            >
                              <SelectTrigger className="w-full dark:bg-gray-800 dark:border-gray-700 dark:text-white">
                                <SelectValue placeholder={t("salaryType")} />
                              </SelectTrigger>
                              <SelectContent>
                                <SelectItem value="monthly">{t("monthly")}</SelectItem>
                                <SelectItem value="daily">{t("daily")}</SelectItem>
                              </SelectContent>
                            </Select>
                          </div>
                          <div className="space-y-2">
                            <Label className="text-xs dark:text-gray-400">{t("amount")}</Label>
                            <input
                              type="number"
                              className="w-full p-2 rounded-md border bg-background dark:bg-gray-800 dark:border-gray-700 dark:text-white text-sm"
                              value={maskAmountField ? "" : salaryAmount}
                              onFocus={() => setMaskAmountField(false)}
                              onBlur={() => setMaskAmountField(true)}
                              onChange={(e) => {
                                setMaskAmountField(false);
                                setSalaryAmount(e.target.value);
                              }}
                              placeholder={maskAmountField ? "****" : "0.00"}
                            />
                          </div>
                        </div>
                        {salaryType === "monthly" && (
                          <div className="space-y-2">
                            <Label className="text-xs dark:text-gray-400">
                              {t("monthlyWorkingDays")}
                            </Label>
                            <input
                              type="number"
                              min="1"
                              max="31"
                              step="0.25"
                              className="w-full p-2 rounded-md border bg-background dark:bg-gray-800 dark:border-gray-700 dark:text-white text-sm"
                              value={monthlyWorkingDays}
                              onChange={(e) => setMonthlyWorkingDays(e.target.value)}
                              placeholder={DEFAULT_MONTHLY_WORKING_DAYS.toString()}
                            />
                          </div>
                        )}
                      </motion.div>
                    )}
                  </AnimatePresence>
                </div>
                {formError && (
                  <p role="alert" className="text-sm text-red-600 dark:text-red-400">
                    {formError}
                  </p>
                )}
              </motion.div>
            ) : (
              <div className="space-y-6">
                <CountdownDisplay timeLeft={timeLeft} progress={progress} />
                {showSalary && (
                  <motion.div
                    initial={{ opacity: 0, scale: 0.9 }}
                    animate={{ opacity: 1, scale: 1 }}
                    className="bg-white/50 dark:bg-black/20 rounded-xl p-4 text-center backdrop-blur-sm"
                  >
                    <div className="flex items-center justify-between gap-2 text-gray-600 dark:text-gray-400 mb-1">
                      <div className="flex items-center gap-2">
                        <Coins size={16} className="text-yellow-500" />
                        <span className="text-sm font-medium">{t("moneyEarned")}</span>
                      </div>
                      <button
                        type="button"
                        className="text-xs inline-flex items-center gap-1 px-2 py-1 rounded-md bg-gray-100 dark:bg-gray-800 hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors"
                        onClick={() => setHideEarnings((prev) => !prev)}
                        aria-pressed={hideEarnings}
                        aria-label={hideEarnings ? t("showEarnings") : t("hideEarnings")}
                        title={hideEarnings ? t("showEarnings") : t("hideEarnings")}
                      >
                        {hideEarnings ? <Eye size={14} /> : <EyeOff size={14} />}
                        <span>{hideEarnings ? t("showEarnings") : t("hideEarnings")}</span>
                      </button>
                    </div>
                    <div className="text-3xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-yellow-500 to-amber-600 dark:from-yellow-400 dark:to-amber-500">
                      {hideEarnings ? "****" : moneyEarned.toFixed(2)}
                    </div>
                  </motion.div>
                )}
              </div>
            )}
          </AnimatePresence>
        </CardContent>
        <CardFooter className="flex justify-center">
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
                <Button variant="outline" onClick={handleReturn}>
                  <ArrowLeft className="me-2 h-4 w-4" /> {t("return")}
                </Button>
                <ShareButton
                  timeLeft={timeLeft}
                  progress={progress}
                  isOff={progress >= 100}
                  shift={{ start: startTime, end: endTime }}
                />
              </motion.div>
            )}
          </AnimatePresence>
        </CardFooter>
      </Card>

      {/* 说明区。冷启动的搜索流量第一眼只看到一个表单，不知道这是什么，跳出率
          会很高；同时主应用页的可见正文原本只有 110–285 字符，内容过薄。
          与页脚同样渲染在设置态（服务端首屏状态），所以这些文字都在初始 HTML 里。
          刻意不放截图：可交互的实物就在正上方，静态图既冗余又对文字量毫无贡献。 */}
      {!showCountdown && !isPWA && (
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
      {!showCountdown && !isPWA && (
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
        </footer>
      )}
      </div>
    </div>
  );
}
