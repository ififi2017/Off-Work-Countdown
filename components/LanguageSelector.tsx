'use client';

import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useEffect, useState } from "react";
import { useRouter } from 'next/navigation';
import { useTranslation } from "react-i18next";

interface LanguageSelectorProps {
  currentLang: string;
  languageMap: Record<string, string>;
}

export function LanguageSelector({ currentLang, languageMap }: LanguageSelectorProps) {
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
    const currentPath = window.location.pathname.split('/').slice(2).join('/');
    const newPath = `/${lng}${currentPath ? `/${currentPath}` : ''}`;
    router.push(newPath);
  };

  return (
    <div className="relative">
      <Select 
        onValueChange={changeLanguage} 
        value={currentLang}
        disabled={isChangingLanguage}
      >
        <SelectTrigger className={`w-[100px] ${isChangingLanguage ? 'opacity-50' : ''}`}>
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
              <SelectItem key={code} value={code} className="cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700">
                {name}
              </SelectItem>
            ))}
          </div>
        </SelectContent>
      </Select>
    </div>
  );
} 