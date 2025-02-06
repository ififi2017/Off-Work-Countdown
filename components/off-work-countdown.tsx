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
import { ThemeToggle } from "./ThemeToggle";
import { CountdownDisplay } from "./CountdownDisplay";
import "../i18n";
import { languageNames } from '@/i18n-config';

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
  const [gradient, setGradient] = useState(false);
  const [showCountdown, setShowCountdown] = useState(false);
  const [timeLeft, setTimeLeft] = useState("");
  const [progress, setProgress] = useState(0);
  const [theme, setTheme] = useState<'light' | 'dark' | 'auto'>('auto');
  const { t } = useTranslation();
  const [isMounted, setIsMounted] = useState(false);

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
      setGradient(getLocalStorageItem("gradient", "false") === "true");
    }
  }, [isMounted]);

  // 保存设置到 localStorage
  useEffect(() => {
    if (isMounted) {
      localStorage.setItem("startTime", startTime);
      localStorage.setItem("endTime", endTime);
      localStorage.setItem("reminder", reminder.toString());
      localStorage.setItem("gradient", gradient.toString());
    }
  }, [isMounted, startTime, endTime, reminder, gradient]);

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
  };

  const handleTimeChange = (type: "start" | "end", hour: string, minute: string) => {
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
      // 从 localStorage 获取主题设置
      const savedTheme = localStorage.getItem('theme') as 'light' | 'dark' | 'auto' | null;
      
      if (savedTheme) {
        setTheme(savedTheme);
        if (savedTheme === 'auto') {
          const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
          document.documentElement.classList.toggle('dark', prefersDark);
        } else {
          document.documentElement.classList.toggle('dark', savedTheme === 'dark');
        }
      } else {
        // 如果没有保存的主题，则默认使用自动模式
        setTheme('auto');
        const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
        document.documentElement.classList.toggle('dark', prefersDark);
      }

      // 监听系统主题变化
      const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
      const handleChange = (e: MediaQueryListEvent) => {
        if (theme === 'auto') {
          document.documentElement.classList.toggle('dark', e.matches);
        }
      };

      mediaQuery.addEventListener('change', handleChange);
      return () => mediaQuery.removeEventListener('change', handleChange);
    }
  }, [isMounted, theme]);

  // 切换主题
  const toggleTheme = () => {
    const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
    let newTheme: 'light' | 'dark' | 'auto';

    if (theme === 'auto') {
      // 从自动模式切换到明确的模式（与当前系统主题相反）
      newTheme = prefersDark ? 'light' : 'dark';
    } else if (theme === 'light') {
      newTheme = 'dark';
    } else {
      // 从深色模式切换回自动模式
      newTheme = 'auto';
    }

    setTheme(newTheme);
    if (newTheme === 'auto') {
      document.documentElement.classList.toggle('dark', prefersDark);
    } else {
      document.documentElement.classList.toggle('dark', newTheme === 'dark');
    }
    localStorage.setItem('theme', newTheme);
  };

  // 如果还没有挂载，返回空内容
  if (!isMounted) {
    return null;
  }

  return (
    <div
      className={`min-h-screen flex items-center justify-center p-4 transition-colors duration-1000 ease-in-out ${
        gradient ? "bg-gradient-animate" : "bg-gray-100 dark:bg-gray-900"
      }`}
    >
      <h1 className="sr-only">{t("seo:siteName")}</h1>

      <Card className="w-full max-w-md dark:bg-gray-800 dark:border-gray-700">
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
              <ThemeToggle theme={theme} onToggle={toggleTheme} />
              <LanguageSelector currentLang={lang} languageMap={languageNames} />
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
                  onChange={(hour, minute) => handleTimeChange("start", hour, minute)}
                />
                <TimeSelector
                  id="endTime"
                  label={t("endTime")}
                  value={endTime}
                  onChange={(hour, minute) => handleTimeChange("end", hour, minute)}
                />
                <div className="flex items-center space-x-2">
                  <Switch
                    id="reminder"
                    checked={reminder}
                    onCheckedChange={setReminder}
                  />
                  <Label htmlFor="reminder" className="dark:text-gray-200">{t("reminder")}</Label>
                </div>
                <div className="flex items-center space-x-2">
                  <Switch
                    id="gradient"
                    checked={gradient}
                    onCheckedChange={setGradient}
                  />
                  <Label htmlFor="gradient" className="dark:text-gray-200">{t("gradient")}</Label>
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
