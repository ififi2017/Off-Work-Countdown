"use client";

import { useState, useEffect, useCallback } from "react";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { ArrowLeft, Github } from "lucide-react";
import { motion, AnimatePresence } from "framer-motion";
import { useTranslation } from "react-i18next";
import { TimeSelector } from "./TimeSelector";
import { LanguageSelector } from "./LanguageSelector";
import { ThemeToggle, Theme } from "./ThemeToggle";
import { CountdownDisplay } from "./CountdownDisplay";
import { Confetti } from "./Confetti";
import "../i18n";
import { languageNames } from "@/i18n-config";

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
  const [startTime, setStartTime] = useState("09:00");
  const [endTime, setEndTime] = useState("18:00");
  const [reminder, setReminder] = useState(false);
  const [showCountdown, setShowCountdown] = useState(false);
  const [timeLeft, setTimeLeft] = useState("");
  const [progress, setProgress] = useState(0);
  const [theme, setTheme] = useState<Theme>("auto");
  const { t } = useTranslation();
  const [isMounted, setIsMounted] = useState(false);
  const [showConfetti, setShowConfetti] = useState(false);

  // 初始化和语言同步
  useEffect(() => {
    setIsMounted(true);
  }, []);

  // 加载本地存储的设置
  useEffect(() => {
    if (isMounted) {
      setStartTime(getLocalStorageItem("startTime", "09:00"));
      setEndTime(getLocalStorageItem("endTime", "18:00"));
      setReminder(getLocalStorageItem("reminder", "false") === "true");
    }
  }, [isMounted]);

  // 保存设置到 localStorage
  useEffect(() => {
    if (isMounted) {
      localStorage.setItem("startTime", startTime);
      localStorage.setItem("endTime", endTime);
      localStorage.setItem("reminder", reminder.toString());
    }
  }, [isMounted, startTime, endTime, reminder]);

  const calculateProgress = useCallback(() => {
    const now = new Date();
    const start = new Date(now.toDateString() + " " + startTime);
    const end = new Date(now.toDateString() + " " + endTime);
    if (end < start) end.setDate(end.getDate() + 1);

    const totalDiff = end.getTime() - start.getTime();
    const currentDiff = end.getTime() - now.getTime();

    if (currentDiff <= 0) {
      return 100;
    } else {
      return Math.max(
        0,
        Math.min(100, ((totalDiff - currentDiff) / totalDiff) * 100)
      );
    }
  }, [startTime, endTime]);

  useEffect(() => {
    let interval: NodeJS.Timeout;
    if (showCountdown) {
      const updateCountdown = () => {
        const now = new Date();
        const start = new Date(now.toDateString() + " " + startTime);
        const end = new Date(now.toDateString() + " " + endTime);
        if (end < start) end.setDate(end.getDate() + 1);

        const diff = end.getTime() - now.getTime();
        if (diff <= 0) {
          setTimeLeft(t("offWorkTime"));
          setProgress(100);
          setShowConfetti(true);
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

          if (reminder && diff <= 15 * 60 * 1000 && diff > 14 * 60 * 1000) {
            new Notification(t("offWorkReminder"), {
              body: t("fifteenMinutesLeft"),
            });
          }
        }
      };

      updateCountdown(); // 立即运行
      interval = setInterval(updateCountdown, 1000);
    }
    return () => clearInterval(interval);
  }, [showCountdown, startTime, endTime, reminder, calculateProgress, t]);

  const handleStart = () => {
    if (startTime === endTime) {
      alert(t("sameTimeError"));
      return;
    }

    const now = new Date();
    const start = new Date(now.toDateString() + " " + startTime);
    if (start > now) {
      const timeDiff = start.getTime() - now.getTime();
      const hours = Math.floor(timeDiff / (1000 * 60 * 60));
      const minutes = Math.floor((timeDiff % (1000 * 60 * 60)) / (1000 * 60));

      alert(t("futureStartTimeError", { hours, minutes }));
      return;
    }

    if (startTime && endTime) {
      setShowCountdown(true);
      setProgress(calculateProgress()); // Set initial progress
      if (reminder) {
        Notification.requestPermission();
      }
    }
  };

  const handleReturn = () => {
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

  // 如果还没有挂载，返回空内容
  if (!isMounted) {
    return null;
  }

  return (
    <div
      className={`min-h-screen flex items-center justify-center p-4 transition-colors duration-1000 ease-in-out ${
        theme === "cyberpunk" || theme === "sunset"
          ? ""
          : "bg-gray-100 dark:bg-gray-900"
      }`}
    >
      <Confetti trigger={showConfetti} />
      <h1 className="sr-only">{t("seo:siteName")}</h1>

      <Card className="w-full max-w-md glass dark:glass-dark border-0">
        <CardHeader>
          <div className="flex justify-between items-center">
            <div className="flex items-center gap-2">
              <CardTitle className="text-2xl font-bold dark:text-white">
                {t("offWorkCountdown")}
              </CardTitle>
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
        <CardContent>
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
                <div className="flex items-center space-x-2">
                  <Switch
                    id="reminder"
                    checked={reminder}
                    onCheckedChange={setReminder}
                  />
                  <Label htmlFor="reminder" className="dark:text-gray-200">
                    {t("reminder")}
                  </Label>
                </div>
              </motion.div>
            ) : (
              <CountdownDisplay timeLeft={timeLeft} progress={progress} />
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
              >
                <Button variant="outline" onClick={handleReturn}>
                  <ArrowLeft className="mr-2 h-4 w-4" /> {t("return")}
                </Button>
              </motion.div>
            )}
          </AnimatePresence>
        </CardFooter>
      </Card>
    </div>
  );
}
