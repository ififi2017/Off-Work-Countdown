"use client";

import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useTranslation } from "react-i18next";
import { desktopLanguageStorageKey } from "@/i18n-config";
import { mobileSelectedTabStorageKey } from "@/lib/mobile-navigation";

interface LanguageSelectorProps {
  currentLang: string;
  languageMap: Record<string, string>;
  compact?: boolean;
  mobile?: boolean;
}

export function LanguageSelector({
  currentLang,
  languageMap,
  compact = false,
  mobile = false,
}: LanguageSelectorProps) {
  const router = useRouter();
  const { i18n } = useTranslation();
  const [isChangingLanguage, setIsChangingLanguage] = useState(false);

  // 监听当前语言变化
  useEffect(() => {
    if (i18n.language !== currentLang) {
      i18n.changeLanguage(currentLang);
    }
    setIsChangingLanguage(false);
  }, [currentLang, i18n]);

  const changeLanguage = (lng: string) => {
    if (lng === currentLang) return;

    setIsChangingLanguage(true);
    try {
      localStorage.setItem(desktopLanguageStorageKey, lng);
    } catch {
      // The route change still works if storage is unavailable.
    }

    // Mobile exports locale pages as sibling files (en.html, zh-CN.html, ...)
    // so the Capacitor package has no Web-style /<locale> route to push to.
    // A full local navigation also lets the new document update <html lang/dir>
    // before first paint, which matters when switching to or from Arabic.
    if (mobile) {
      try {
        // Language lives inside Settings; keep the user on that tab across the
        // required full-document locale navigation.
        sessionStorage.setItem(mobileSelectedTabStorageKey, "settings");
      } catch {
        // Losing the tab position is harmless if session storage is unavailable.
      }
      window.location.assign(new URL(`${lng}.html`, window.location.href).href);
      return;
    }

    const currentPath = window.location.pathname.split("/").slice(2).join("/");
    const newPath = `/${lng}${currentPath ? `/${currentPath}` : ""}`;
    router.push(newPath);
  };

  return (
    <div className="relative">
      <Select
        onValueChange={changeLanguage}
        value={currentLang}
        disabled={isChangingLanguage}
      >
        <SelectTrigger
          className={`${
            mobile
              ? "h-11 w-[132px] rounded-xl border-input bg-background px-3 text-sm shadow-sm [&>span]:truncate"
              : compact
                ? "h-9 w-[92px] rounded-xl border-input bg-background px-2.5 text-xs shadow-sm"
                : "w-[100px]"
          } ${
            isChangingLanguage ? "opacity-50" : ""
          }`}
        >
          <SelectValue>
            {isChangingLanguage ? (
              <div className="flex items-center justify-center">
                <div className="w-4 h-4 border-2 border-primary border-t-transparent rounded-full animate-spin" />
              </div>
            ) : (
              languageMap[currentLang]
            )}
          </SelectValue>
        </SelectTrigger>
        <SelectContent className="max-h-[40vh] overflow-y-auto">
          <div className="grid grid-cols-1 gap-1">
            {Object.entries(languageMap).map(([code, name]) => (
              <SelectItem
                key={code}
                value={code}
                className="cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700"
              >
                {name}
              </SelectItem>
            ))}
          </div>
        </SelectContent>
      </Select>
    </div>
  );
}
