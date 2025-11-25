"use client";

import { Moon, Sun, Monitor, Zap, Sunset } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { useTranslation } from "react-i18next";

export type Theme = "light" | "dark" | "auto" | "cyberpunk" | "sunset";

interface ThemeToggleProps {
  theme: Theme;
  onThemeChange: (theme: Theme) => void;
}

export function ThemeToggle({ theme, onThemeChange }: ThemeToggleProps) {
  const { t } = useTranslation();

  const getIcon = () => {
    switch (theme) {
      case "light":
        return <Sun className="h-[1.2rem] w-[1.2rem]" />;
      case "dark":
        return <Moon className="h-[1.2rem] w-[1.2rem]" />;
      case "cyberpunk":
        return <Zap className="h-[1.2rem] w-[1.2rem]" />;
      case "sunset":
        return <Sunset className="h-[1.2rem] w-[1.2rem]" />;
      default:
        return <Monitor className="h-[1.2rem] w-[1.2rem]" />;
    }
  };

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="icon" className="glass dark:glass-dark border-0">
          {getIcon()}
          <span className="sr-only">{t("toggleTheme")}</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem onClick={() => onThemeChange("light")}>
          <Sun className="mr-2 h-4 w-4" />
          {t("light")}
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => onThemeChange("dark")}>
          <Moon className="mr-2 h-4 w-4" />
          {t("dark")}
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => onThemeChange("auto")}>
          <Monitor className="mr-2 h-4 w-4" />
          {t("auto")}
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => onThemeChange("cyberpunk")}>
          <Zap className="mr-2 h-4 w-4" />
          {t("cyberpunk")}
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => onThemeChange("sunset")}>
          <Sunset className="mr-2 h-4 w-4" />
          {t("sunset")}
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
