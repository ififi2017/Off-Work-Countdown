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

interface LanguageSelectorProps {
  currentLang: string;
  languageMap: Record<string, string>;
  compact?: boolean;
}

export function LanguageSelector({
  currentLang,
  languageMap,
  compact = false,
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
          className={`${compact ? "h-9 w-[92px] rounded-xl border-input bg-background px-2.5 text-xs shadow-sm" : "w-[100px]"} ${
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
