"use client";

import { useMemo } from "react";
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
}

export function PeriodSummary({
  lang,
  note,
  rows,
  hideEarnings,
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
    <div className="rounded-xl bg-white/50 p-4 backdrop-blur-sm dark:bg-black/20">
      <p className="text-xs text-gray-500 dark:text-gray-400">{note}</p>
      <dl className="mt-3 space-y-2">
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
