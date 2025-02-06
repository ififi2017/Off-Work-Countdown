'use client';

import * as React from "react";
import * as Select from "@radix-ui/react-select";
import { useEffect, useState } from "react";
import { useRouter } from 'next/navigation';
import { useTranslation } from "react-i18next";
import { ChevronDown } from "lucide-react";
import { cn } from "@/lib/utils";

interface LanguageSelectorProps {
  currentLang: string;
  languageMap: Record<string, string>;
}

const SelectTrigger = React.forwardRef<
  HTMLButtonElement,
  React.ComponentPropsWithoutRef<typeof Select.Trigger>
>(({ className, children, ...props }, ref) => (
  <Select.Trigger
    ref={ref}
    className={cn(
      "flex h-10 w-[100px] items-center justify-between rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50",
      className
    )}
    {...props}
  >
    {children}
  </Select.Trigger>
));
SelectTrigger.displayName = Select.Trigger.displayName;

const SelectContent = React.forwardRef<
  HTMLDivElement,
  React.ComponentPropsWithoutRef<typeof Select.Content>
>(({ className, children, position = "popper", ...props }, ref) => (
  <Select.Portal>
    <Select.Content
      ref={ref}
      className={cn(
        "relative z-50 min-w-[8rem] overflow-hidden rounded-md border bg-popover text-popover-foreground shadow-md data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0 data-[state=closed]:zoom-out-95 data-[state=open]:zoom-in-95 data-[side=bottom]:slide-in-from-top-2 data-[side=left]:slide-in-from-right-2 data-[side=right]:slide-in-from-left-2 data-[side=top]:slide-in-from-bottom-2",
        className
      )}
      position={position}
      {...props}
    >
      <Select.Viewport className="p-1">
        {children}
      </Select.Viewport>
    </Select.Content>
  </Select.Portal>
));
SelectContent.displayName = Select.Content.displayName;

const SelectItem = React.forwardRef<
  HTMLDivElement,
  React.ComponentPropsWithoutRef<typeof Select.Item>
>(({ className, children, ...props }, ref) => (
  <Select.Item
    ref={ref}
    className={cn(
      "relative flex w-full cursor-default select-none items-center rounded-sm py-1.5 pl-2 pr-8 text-sm outline-none hover:bg-accent hover:text-accent-foreground focus:bg-accent focus:text-accent-foreground data-[disabled]:pointer-events-none data-[disabled]:opacity-50",
      className
    )}
    {...props}
  >
    <Select.ItemText>{children}</Select.ItemText>
  </Select.Item>
));
SelectItem.displayName = Select.Item.displayName;

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

  if (isChangingLanguage) {
    return (
      <div className="w-[100px] h-10 flex items-center justify-center border rounded-md">
        <div className="w-4 h-4 border-2 border-primary border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <Select.Root onValueChange={changeLanguage} value={currentLang}>
      <SelectTrigger>
        <Select.Value>{languageMap[currentLang]}</Select.Value>
        <Select.Icon>
          <ChevronDown className="h-4 w-4 opacity-50" />
        </Select.Icon>
      </SelectTrigger>
      <SelectContent>
        {Object.entries(languageMap).map(([code, name]) => (
          <SelectItem key={code} value={code}>
            {name}
          </SelectItem>
        ))}
      </SelectContent>
    </Select.Root>
  );
} 