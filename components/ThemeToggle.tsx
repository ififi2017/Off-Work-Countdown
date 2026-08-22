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
  compact?: boolean;
  quick?: boolean;
  mobile?: boolean;
}

export function ThemeToggle({
  theme,
  onThemeChange,
  compact = false,
  quick = false,
  mobile = false,
}: ThemeToggleProps) {
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
        <Button
          type="button"
          variant="outline"
          size="icon"
          className={`${
            mobile
              ? "h-11 w-11 rounded-xl border-input bg-background shadow-sm"
              : quick
              ? "h-9 w-9 rounded-xl border-gray-200/80 bg-white/40 text-gray-600 shadow-sm hover:bg-white/70 hover:text-gray-900 dark:border-gray-700 dark:bg-black/10 dark:text-gray-300 dark:hover:bg-black/20 dark:hover:text-white"
              : compact
                ? "h-9 w-9 rounded-xl border-input bg-background shadow-sm"
              : "glass border-0 dark:glass-dark"
          }`}
        >
          {getIcon()}
          <span className="sr-only">{t("toggleTheme")}</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem onClick={() => onThemeChange("light")}>
          <Sun className="me-2 h-4 w-4" />
          {t("light")}
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => onThemeChange("dark")}>
          <Moon className="me-2 h-4 w-4" />
          {t("dark")}
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => onThemeChange("auto")}>
          <Monitor className="me-2 h-4 w-4" />
          {t("auto")}
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => onThemeChange("cyberpunk")}>
          <Zap className="me-2 h-4 w-4" />
          {t("cyberpunk")}
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => onThemeChange("sunset")}>
          <Sunset className="me-2 h-4 w-4" />
          {t("sunset")}
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
