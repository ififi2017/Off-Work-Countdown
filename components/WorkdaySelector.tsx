"use client";

import { useMemo } from "react";
import { Label } from "@/components/ui/label";

// 2023-01-01 是周日，以它为锚点按 getDay() 的 0–6 取出对应日期，
// 再交给 Intl 按当前语言给出星期简称——19 种语言都不需要人工翻译。
const SUNDAY_ANCHOR = Date.UTC(2023, 0, 1);

// 展示顺序为周一到周日（ISO 8601），与 getDay() 的 0=周日 口径解耦。
const DISPLAY_ORDER = [1, 2, 3, 4, 5, 6, 0];

interface WorkdaySelectorProps {
  lang: string;
  label: string;
  value: number[];
  onChange: (days: number[]) => void;
}

export function WorkdaySelector({
  lang,
  label,
  value,
  onChange,
}: WorkdaySelectorProps) {
  const names = useMemo(() => {
    let fmt: Intl.DateTimeFormat;
    try {
      fmt = new Intl.DateTimeFormat(lang, {
        weekday: "short",
        timeZone: "UTC",
      });
    } catch {
      // 语言标签不被运行时接受时退回默认区域，不影响功能
      fmt = new Intl.DateTimeFormat(undefined, {
        weekday: "short",
        timeZone: "UTC",
      });
    }
    return Object.fromEntries(
      DISPLAY_ORDER.map((d) => [
        d,
        fmt.format(new Date(SUNDAY_ANCHOR + d * 86400000)),
      ])
    ) as Record<number, string>;
  }, [lang]);

  const toggle = (day: number) => {
    onChange(
      value.includes(day) ? value.filter((d) => d !== day) : [...value, day]
    );
  };

  return (
    <div className="space-y-2">
      <Label className="dark:text-gray-200">{label}</Label>
      <div className="flex gap-1.5">
        {DISPLAY_ORDER.map((day) => {
          const on = value.includes(day);
          return (
            <button
              key={day}
              type="button"
              onClick={() => toggle(day)}
              aria-pressed={on}
              // 星期简称的长度因语言差异很大（英文 "Mon" 三字符，阿拉伯语
              // "الأربعاء" 八字符，泰语更长）。用 min-w-0 + truncate 兜底，
              // 任何语言都不会把这一行撑破；截断只是视觉行为，读屏仍读完整文本。
              title={names[day]}
              className={`min-w-0 flex-1 truncate rounded-md border px-1 py-1.5 text-xs transition-colors ${
                on
                  ? "border-gray-900 bg-gray-900 text-white dark:border-white dark:bg-white dark:text-gray-900"
                  : "border-input bg-background text-muted-foreground hover:text-foreground dark:border-gray-600 dark:bg-gray-700 dark:text-gray-400"
              }`}
            >
              {names[day]}
            </button>
          );
        })}
      </div>
    </div>
  );
}
