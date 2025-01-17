"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import { useRouter } from 'next/navigation';
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { ArrowLeft, Github, Moon, Sun } from "lucide-react";
import { motion, AnimatePresence } from "framer-motion";
import { useTranslation } from "react-i18next";
import "../i18n";

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
  const router = useRouter();
  const [startTime, setStartTime] = useState("09:00");
  const [endTime, setEndTime] = useState("18:00");
  const [reminder, setReminder] = useState(false);
  const [gradient, setGradient] = useState(false);
  const [showCountdown, setShowCountdown] = useState(false);
  const [timeLeft, setTimeLeft] = useState("");
  const [progress, setProgress] = useState(0);
  const [theme, setTheme] = useState<'light' | 'dark'>('light');
  const progressBarRef = useRef<HTMLDivElement>(null);
  const { t, i18n } = useTranslation();
  const [isMounted, setIsMounted] = useState(false);
  const [isChangingLanguage, setIsChangingLanguage] = useState(false);

  // 语言名称映射
  const languageMap = {
    de: "Deutsch",
    en: "English",
    es: "Español",
    fr: "Français",
    "hi-IN": "हिन्दी",
    it: "Italiano",
    ja: "日本語",
    ko: "한국어",
    "mr-IN": "मराठी",
    pt: "Português",
    ru: "Русский",
    "zh-CN": "简体中文",
    "zh-HK": "繁體中文（香港）",
    "zh-TW": "繁體中文（台灣）"
  };

  // 初始化和语言同步
  useEffect(() => {
    if (i18n.language !== lang) {
      i18n.changeLanguage(lang);
    }
    setIsMounted(true);
  }, [lang, i18n]);

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

  const changeLanguage = (lng: string) => {
    setIsChangingLanguage(true);
    const currentPath = window.location.pathname.split('/').slice(2).join('/');
    const newPath = `/${lng}${currentPath ? `/${currentPath}` : ''}`;
    router.push(newPath);
  };

  // 在语言变化时重置加载状态
  useEffect(() => {
    if (i18n.language === lang && isChangingLanguage) {
      setIsChangingLanguage(false);
    }
  }, [i18n.language, lang, isChangingLanguage]);

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

  const generateHourOptions = () => {
    const options = [];
    for (let i = 0; i < 24; i++) {
      const hour = i.toString().padStart(2, "0");
      options.push(hour);
    }
    return options;
  };

  const generateMinuteOptions = () => {
    const options = [];
    for (let i = 0; i < 60; i++) {
      const minute = i.toString().padStart(2, "0");
      options.push(minute);
    }
    return options;
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
      // 从 localStorage 获取主题设置
      const savedTheme = localStorage.getItem('theme') as 'light' | 'dark' | null;
      
      if (savedTheme) {
        setTheme(savedTheme);
        document.documentElement.classList.toggle('dark', savedTheme === 'dark');
      } else {
        // 如果没有保存的主题，则使用系统主题
        const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
        setTheme(prefersDark ? 'dark' : 'light');
        document.documentElement.classList.toggle('dark', prefersDark);
      }

      // 监听系统主题变化
      const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
      const handleChange = (e: MediaQueryListEvent) => {
        if (!localStorage.getItem('theme')) {
          setTheme(e.matches ? 'dark' : 'light');
          document.documentElement.classList.toggle('dark', e.matches);
        }
      };

      mediaQuery.addEventListener('change', handleChange);
      return () => mediaQuery.removeEventListener('change', handleChange);
    }
  }, [isMounted]);

  // 切换主题
  const toggleTheme = () => {
    const newTheme = theme === 'light' ? 'dark' : 'light';
    setTheme(newTheme);
    document.documentElement.classList.toggle('dark', newTheme === 'dark');
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
              <Button
                variant="ghost"
                size="icon"
                onClick={toggleTheme}
                className="w-9 h-9 p-0"
              >
                {theme === 'light' ? <Moon size={20} /> : <Sun size={20} />}
              </Button>
              <div className="relative">
                <Select 
                  onValueChange={changeLanguage} 
                  value={lang}
                  disabled={isChangingLanguage}
                >
                  <SelectTrigger className={`w-[100px] ${isChangingLanguage ? 'opacity-50' : ''}`}>
                    <SelectValue>
                      {isChangingLanguage ? (
                        <div className="flex items-center justify-center">
                          <div className="w-4 h-4 border-2 border-primary border-t-transparent rounded-full animate-spin" />
                        </div>
                      ) : (
                        languageMap[lang as keyof typeof languageMap]
                      )}
                    </SelectValue>
                  </SelectTrigger>
                  <SelectContent className="max-h-[40vh] overflow-y-auto">
                    <div className="grid grid-cols-1 gap-1">
                      {Object.entries(languageMap).map(([code, name]) => (
                        <SelectItem key={code} value={code} className="cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700">
                          {name}
                        </SelectItem>
                      ))}
                    </div>
                  </SelectContent>
                </Select>
              </div>
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
                <div className="space-y-2">
                  <Label htmlFor="startTimeHour">{t("startTime")}</Label>
                  <div className="flex space-x-2">
                    <select
                      id="startTimeHour"
                      value={startTime.split(":")[0]}
                      onChange={(e) =>
                        handleTimeChange(
                          "start",
                          e.target.value,
                          startTime.split(":")[1]
                        )
                      }
                      className="w-1/2 p-2 border rounded dark:bg-gray-700 dark:border-gray-600 dark:text-white"
                    >
                      {generateHourOptions().map((hour) => (
                        <option key={hour} value={hour}>
                          {hour}
                        </option>
                      ))}
                    </select>
                    <select
                      id="startTimeMinute"
                      value={startTime.split(":")[1]}
                      onChange={(e) =>
                        handleTimeChange(
                          "start",
                          startTime.split(":")[0],
                          e.target.value
                        )
                      }
                      className="w-1/2 p-2 border rounded dark:bg-gray-700 dark:border-gray-600 dark:text-white"
                    >
                      {generateMinuteOptions().map((minute) => (
                        <option key={minute} value={minute}>
                          {minute}
                        </option>
                      ))}
                    </select>
                  </div>
                </div>
                <div className="space-y-2">
                  <Label htmlFor="endTimeHour" className="dark:text-gray-200">{t("endTime")}</Label>
                  <div className="flex space-x-2">
                    <select
                      id="endTimeHour"
                      value={endTime.split(":")[0]}
                      onChange={(e) =>
                        handleTimeChange(
                          "end",
                          e.target.value,
                          endTime.split(":")[1]
                        )
                      }
                      className="w-1/2 p-2 border rounded dark:bg-gray-700 dark:border-gray-600 dark:text-white"
                    >
                      {generateHourOptions().map((hour) => (
                        <option key={hour} value={hour}>
                          {hour}
                        </option>
                      ))}
                    </select>
                    <select
                      id="endTimeMinute"
                      value={endTime.split(":")[1]}
                      onChange={(e) =>
                        handleTimeChange(
                          "end",
                          endTime.split(":")[0],
                          e.target.value
                        )
                      }
                      className="w-1/2 p-2 border rounded dark:bg-gray-700 dark:border-gray-600 dark:text-white"
                    >
                      {generateMinuteOptions().map((minute) => (
                        <option key={minute} value={minute}>
                          {minute}
                        </option>
                      ))}
                    </select>
                  </div>
                </div>
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
              <motion.div
                key="countdown"
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -20 }}
                transition={{ duration: 0.3 }}
                className="space-y-4"
              >
                <div
                  className="text-4xl font-bold text-center whitespace-nowrap overflow-hidden dark:text-white"
                  style={{
                    minWidth: 0,
                    fontSize: "clamp(1.5rem, 5vw, 2.25rem)",
                    lineHeight: "1.2",
                  }}
                >
                  {timeLeft}
                </div>
                <div className="relative pt-10" ref={progressBarRef}>
                  <div className="w-full h-2 bg-gray-200 dark:bg-gray-700 rounded-full overflow-hidden">
                    <motion.div
                      className="h-full bg-primary"
                      style={{ width: `${progress}%` }}
                      transition={{
                        type: "spring",
                        stiffness: 300,
                        damping: 30,
                      }}
                    />
                  </div>
                  <motion.div
                    className="absolute top-0 left-0 transform -translate-y-full"
                    style={{
                      left: `calc(${progress}%)`,
                      x: "-50%",
                    }}
                    transition={{ type: "spring", stiffness: 300, damping: 30 }}
                  >
                    <div className="relative">
                      <div className="bg-primary text-primary-foreground px-3 py-1 rounded-md shadow-md text-sm font-semibold whitespace-nowrap">
                        {(Math.floor(progress * 10) / 10).toFixed(1)}%
                      </div>
                      <div className="absolute left-1/2 top-full -translate-x-1/2 w-0 h-0 border-l-[6px] border-l-transparent border-r-[6px] border-r-transparent border-t-[6px] border-t-primary" />
                    </div>
                  </motion.div>
                </div>
              </motion.div>
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
