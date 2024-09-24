"use client";

import { useState, useEffect, useCallback, useRef } from "react";
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
import { ArrowLeft } from "lucide-react";
import { motion, AnimatePresence } from "framer-motion";
import { useTranslation } from "react-i18next";

// Helper function to safely get item from localStorage
const getLocalStorageItem = (key: string, defaultValue: string) => {
  if (typeof window !== "undefined") {
    return localStorage.getItem(key) || defaultValue;
  }
  return defaultValue;
};

export function OffWorkCountdown() {
  const isFirstRender = useRef(true);
  const [startTime, setStartTime] = useState("09:00");
  const [endTime, setEndTime] = useState("18:00");
  const [reminder, setReminder] = useState(false);
  const [gradient, setGradient] = useState(false);
  const [showCountdown, setShowCountdown] = useState(false);
  const [timeLeft, setTimeLeft] = useState("");
  const [progress, setProgress] = useState(0);
  const progressBarRef = useRef<HTMLDivElement>(null);
  const { t, i18n } = useTranslation();
  const [isMounted, setIsMounted] = useState(false);
  const [language, setLanguage] = useState("en"); // 默认值设为 "en"
  const languageMap = {
    de: "Deutsch",
    "en-US": "English",
    es: "Español",
    fr: "Français",
    it: "Italiano",
    ja: "日本語",
    ko: "한국어",
    pt: "Português",
    ru: "Русский",
    "zh-CN": "简体中文",
    "zh-TW": "繁體中文",
  };

  useEffect(() => {
    setIsMounted(true);
    const storedLang = getLocalStorageItem("i18nextLng", "en");
    setLanguage(storedLang);

    const handleStorageChange = () => {
      const newStoredLang = getLocalStorageItem("i18nextLng", "en");
      setLanguage(newStoredLang);
    };

    window.addEventListener("storage", handleStorageChange);
    return () => window.removeEventListener("storage", handleStorageChange);
  }, []);

  const changeLanguage = (lng: string) => {
    i18n.changeLanguage(lng);
    setLanguage(lng);
    localStorage.setItem("i18nextLng", lng);
  };

  useEffect(() => {
    if (isFirstRender.current) {
      // 如果是初次渲染，从 localStorage 加载值
      setStartTime(getLocalStorageItem("startTime", "09:00"));
      setEndTime(getLocalStorageItem("endTime", "18:00"));
      setReminder(getLocalStorageItem("reminder", "false") === "true");
      setGradient(getLocalStorageItem("gradient", "false") === "true");
      isFirstRender.current = false;
    } else {
      // 如果不是初次渲染，将值保存到 localStorage
      localStorage.setItem("startTime", startTime);
      localStorage.setItem("endTime", endTime);
      localStorage.setItem("reminder", reminder.toString());
      localStorage.setItem("gradient", gradient.toString());
    }
  }, [startTime, endTime, reminder, gradient]);

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
          setTimeLeft(t("timeLeft", { hours, minutes, seconds }));

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

  const generateTimeOptions = () => {
    const options = [];
    for (let i = 0; i < 24; i++) {
      for (let j = 0; j < 2; j++) {
        const hour = i.toString().padStart(2, "0");
        const minute = (j * 30).toString().padStart(2, "0");
        options.push(`${hour}:${minute}`);
      }
    }
    return options;
  };

  return (
    <div
      className={`min-h-screen flex items-center justify-center p-4 transition-colors duration-1000 ease-in-out ${
        gradient ? "bg-gradient-animate" : "bg-gray-100"
      }`}
    >
      <Card className="w-full max-w-md">
        <CardHeader>
          <div className="flex justify-between items-center">
            <CardTitle className="text-2xl font-bold">
              {t("offWorkCountdown")}
            </CardTitle>
            <Select onValueChange={changeLanguage} value={language}>
              <SelectTrigger className="w-[100px]">
                <SelectValue>
                  {isMounted
                    ? languageMap[language as keyof typeof languageMap] ||
                      language
                    : null}
                </SelectValue>
              </SelectTrigger>
              <SelectContent>
                {Object.entries(languageMap).map(([code, name]) => (
                  <SelectItem key={code} value={code}>
                    {name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
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
                  <Label htmlFor="startTime">{t("startTime")}</Label>
                  <select
                    id="startTime"
                    value={startTime}
                    onChange={(e) => setStartTime(e.target.value)}
                    className="w-full p-2 border rounded"
                  >
                    {generateTimeOptions().map((time) => (
                      <option key={time} value={time}>
                        {time}
                      </option>
                    ))}
                  </select>
                </div>
                <div className="space-y-2">
                  <Label htmlFor="endTime">{t("endTime")}</Label>
                  <select
                    id="endTime"
                    value={endTime}
                    onChange={(e) => setEndTime(e.target.value)}
                    className="w-full p-2 border rounded"
                  >
                    {generateTimeOptions().map((time) => (
                      <option key={time} value={time}>
                        {time}
                      </option>
                    ))}
                  </select>
                </div>
                <div className="flex items-center space-x-2">
                  <Switch
                    id="reminder"
                    checked={reminder}
                    onCheckedChange={setReminder}
                  />
                  <Label htmlFor="reminder">{t("reminder")}</Label>
                </div>
                <div className="flex items-center space-x-2">
                  <Switch
                    id="gradient"
                    checked={gradient}
                    onCheckedChange={setGradient}
                  />
                  <Label htmlFor="gradient">{t("gradient")}</Label>
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
                <div className="text-4xl font-bold text-center">{timeLeft}</div>
                <div className="relative pt-10" ref={progressBarRef}>
                  <div className="w-full h-2 bg-gray-200 rounded-full overflow-hidden">
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
