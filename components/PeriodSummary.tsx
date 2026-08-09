"use client";

import { useMemo } from "react";
import { Coins, Eye, EyeOff } from "lucide-react";
import type { PeriodSummary as SummaryData } from "@/lib/summary";

interface Row {
  label: string;
  data: SummaryData;
}

interface PeriodSummaryProps {
  lang: string;
  /** 「按当前设置推算」——必须显式标注，这些数字是推算而非记录。 */
  note: string;
  rows: Row[];
  hideEarnings: boolean;
  compact?: boolean;
  currentEarnings?: {
    label: string;
    value: string;
    showLabel: string;
    hideLabel: string;
    onToggle: () => void;
  };
}

export function PeriodSummary({
  lang,
  note,
  rows,
  hideEarnings,
  compact = false,
  currentEarnings,
}: PeriodSummaryProps) {
  // 天数与小时用 Intl 的 unit 样式：复数形式、小数分隔符、各语言写法都由它处理，
  // 不需要为 19 种语言各写一遍「天」「小时」。
  const fmt = useMemo(() => {
    const make = (options: Intl.NumberFormatOptions) => {
      try {
        return new Intl.NumberFormat(lang, options);
      } catch {
        return new Intl.NumberFormat(undefined, options);
      }
    };
    return {
      days: make({
        style: "unit",
        unit: "day",
        unitDisplay: "short",
        maximumFractionDigits: 1,
      }),
      hours: make({
        style: "unit",
        unit: "hour",
        unitDisplay: "short",
        maximumFractionDigits: 0,
      }),
      money: make({ maximumFractionDigits: 0 }),
    };
  }, [lang]);

  return (
    <div
      className={`rounded-xl bg-white/50 backdrop-blur-sm dark:bg-black/20 ${
        compact ? "p-3" : "p-4"
      }`}
    >
      <p className="text-xs text-gray-500 dark:text-gray-400">{note}</p>
      {currentEarnings && (
        <div className="mt-2 flex items-center justify-between gap-3 border-b border-gray-200/70 pb-2 dark:border-gray-700/70">
          <span className="flex items-center gap-2 text-sm text-gray-600 dark:text-gray-300">
            <Coins className="h-4 w-4 text-amber-500" />
            {currentEarnings.label}
          </span>
          <span className="flex items-center gap-1.5">
            <strong className="bg-gradient-to-r from-yellow-500 to-amber-600 bg-clip-text text-sm font-semibold tabular-nums text-transparent dark:from-yellow-400 dark:to-amber-500">
              {hideEarnings ? "****" : currentEarnings.value}
            </strong>
            <button
              type="button"
              onClick={currentEarnings.onToggle}
              className="inline-flex h-7 w-7 items-center justify-center rounded-md text-gray-500 transition-colors hover:bg-gray-100 hover:text-gray-900 dark:text-gray-400 dark:hover:bg-gray-800 dark:hover:text-white"
              aria-pressed={hideEarnings}
              aria-label={
                hideEarnings
                  ? currentEarnings.showLabel
                  : currentEarnings.hideLabel
              }
              title={
                hideEarnings
                  ? currentEarnings.showLabel
                  : currentEarnings.hideLabel
              }
            >
              {hideEarnings ? (
                <Eye className="h-3.5 w-3.5" />
              ) : (
                <EyeOff className="h-3.5 w-3.5" />
              )}
            </button>
          </span>
        </div>
      )}
      <dl className={compact ? "mt-2 space-y-1.5" : "mt-3 space-y-2"}>
        {rows.map((row) => (
          <div
            key={row.label}
            className="flex items-baseline justify-between gap-3"
          >
            <dt className="text-sm text-gray-600 dark:text-gray-300">
              {row.label}
            </dt>
            <dd className="text-sm font-medium tabular-nums text-gray-900 dark:text-white">
              {fmt.days.format(row.data.days)}
              <span className="mx-1.5 text-gray-400" aria-hidden="true">
                ·
              </span>
              {fmt.hours.format(row.data.hours)}
              {row.data.earnings !== null && (
                <>
                  <span className="mx-1.5 text-gray-400" aria-hidden="true">
                    ·
                  </span>
                  {/* 与倒计时里的「今日已赚」共用同一个遮挡开关：
                      旁边有人时，汇总金额同样不该露出来。 */}
                  {hideEarnings ? "****" : fmt.money.format(row.data.earnings)}
                </>
              )}
            </dd>
          </div>
        ))}
      </dl>
    </div>
  );
}
