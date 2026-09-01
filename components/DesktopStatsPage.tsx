"use client";

import { useEffect, useMemo, useState } from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { useTranslation } from "react-i18next";
import {
  readDesktopStats,
  subscribeToDesktopStats,
} from "@/lib/desktop-state";
import {
  canShiftMonth,
  clampMonthKey,
  emptyDesktopStats,
  formatStatsDuration,
  formatWoodfishCountLabel,
  localDateKey,
  monthKeyFromDateKey,
  neighboringMonthKey,
  summarizeMonth,
  type DesktopStatsState,
} from "@/lib/desktop-stats";

function formatMonthTitle(monthKey: string, lang: string): string {
  const [yearText, monthText] = monthKey.split("-");
  const date = new Date(Number(yearText), Number(monthText) - 1, 1);
  try {
    return new Intl.DateTimeFormat(lang, {
      month: "long",
      year: "numeric",
    }).format(date);
  } catch {
    return monthKey;
  }
}

function formatDayTitle(
  dateKey: string,
  lang: string,
  todayLabel: string,
  todayKey: string
): string {
  if (dateKey === todayKey) return todayLabel;
  const [yearText, monthText, dayText] = dateKey.split("-");
  const date = new Date(Number(yearText), Number(monthText) - 1, Number(dayText));
  try {
    return new Intl.DateTimeFormat(lang, {
      weekday: "short",
      month: "short",
      day: "numeric",
    }).format(date);
  } catch {
    return dateKey;
  }
}

export function DesktopStatsPage({ lang }: { lang: string }) {
  const { t } = useTranslation();
  const todayKey = localDateKey();
  const [stats, setStats] = useState<DesktopStatsState>(emptyDesktopStats);
  const [monthKey, setMonthKey] = useState(() =>
    monthKeyFromDateKey(todayKey)
  );

  useEffect(() => {
    let unsubscribe = () => {};
    let cancelled = false;

    void readDesktopStats()
      .then((value) => {
        if (!cancelled) setStats(value);
      })
      .catch(() => {
        // 读不到时留空态，设置页本身仍可用。
      });

    void subscribeToDesktopStats((value) => {
      if (!cancelled) setStats(value);
    })
      .then((fn) => {
        if (cancelled) fn();
        else unsubscribe = fn;
      })
      .catch(() => {});

    return () => {
      cancelled = true;
      unsubscribe();
    };
  }, []);

  const clampedMonth = clampMonthKey(monthKey, stats);
  const summary = useMemo(
    () => summarizeMonth(stats, clampedMonth),
    [stats, clampedMonth]
  );
  const canGoPrev = canShiftMonth(clampedMonth, -1, stats);
  const canGoNext = canShiftMonth(clampedMonth, 1, stats);

  const goMonth = (delta: number) => {
    const next = neighboringMonthKey(clampedMonth, delta, stats);
    if (next) setMonthKey(next);
  };

  return (
    <div className="space-y-3">
      <p className="text-xs leading-5 text-gray-500 dark:text-gray-400">
        {t("desktopStatsHint")}
      </p>

      <section className="rounded-xl border border-gray-200/80 bg-white/35 p-3 shadow-sm dark:border-gray-700 dark:bg-black/10">
        <div className="flex items-center justify-between gap-2">
          <button
            type="button"
            onClick={() => goMonth(-1)}
            disabled={!canGoPrev}
            className="inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-lg text-gray-600 transition-colors hover:bg-black/5 hover:text-gray-950 disabled:pointer-events-none disabled:opacity-30 dark:text-gray-300 dark:hover:bg-white/10 dark:hover:text-white"
            aria-label={t("desktopStatsPreviousMonth")}
            title={t("desktopStatsPreviousMonth")}
          >
            <ChevronLeft className="h-4 w-4" />
          </button>
          <p className="min-w-0 truncate text-center text-sm font-medium text-gray-900 dark:text-white">
            {formatMonthTitle(clampedMonth, lang)}
          </p>
          <button
            type="button"
            onClick={() => goMonth(1)}
            disabled={!canGoNext}
            className="inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-lg text-gray-600 transition-colors hover:bg-black/5 hover:text-gray-950 disabled:pointer-events-none disabled:opacity-30 dark:text-gray-300 dark:hover:bg-white/10 dark:hover:text-white"
            aria-label={t("desktopStatsNextMonth")}
            title={t("desktopStatsNextMonth")}
          >
            <ChevronRight className="h-4 w-4" />
          </button>
        </div>

        <dl className="mt-3 grid grid-cols-3 gap-2 text-center">
          <div>
            <dt className="text-[11px] text-gray-500 dark:text-gray-400">
              {t("desktopStatsWorked")}
            </dt>
            <dd className="mt-1 text-sm font-semibold tabular-nums text-gray-900 dark:text-white">
              {t("desktopStatsDays", { count: summary.daysWorked })}
            </dd>
          </div>
          <div>
            <dt className="text-[11px] text-gray-500 dark:text-gray-400">
              {t("desktopStatsHours")}
            </dt>
            <dd className="mt-1 text-sm font-semibold tabular-nums text-gray-900 dark:text-white">
              {formatStatsDuration(summary.workedMs, lang)}
            </dd>
          </div>
          <div>
            <dt className="text-[11px] text-gray-500 dark:text-gray-400">
              {t("desktopStatsKnocks")}
            </dt>
            <dd className="mt-1 text-sm font-semibold tabular-nums text-gray-900 dark:text-white">
              {formatWoodfishCountLabel(summary.woodfishCount)}
            </dd>
          </div>
        </dl>
      </section>

      {summary.days.length === 0 ? (
        <p className="rounded-xl border border-dashed border-gray-200/90 bg-white/20 px-3 py-5 text-center text-xs leading-5 text-gray-500 dark:border-gray-700 dark:bg-black/10 dark:text-gray-400">
          {t("desktopStatsEmpty")}
        </p>
      ) : (
        <ul className="overflow-hidden rounded-xl border border-gray-200/80 bg-white/35 shadow-sm dark:border-gray-700 dark:bg-black/10">
          {summary.days.map((day, index) => {
            const workLabel = day.attended
              ? formatStatsDuration(day.plannedMs, lang)
              : t("desktopStatsNoShift");
            return (
              <li
                key={day.date}
                className={`flex items-baseline justify-between gap-3 px-3 py-2.5 ${
                  index > 0
                    ? "border-t border-gray-200/70 dark:border-gray-700/70"
                    : ""
                }`}
              >
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium text-gray-900 dark:text-white">
                    {formatDayTitle(
                      day.date,
                      lang,
                      t("desktopStatsToday"),
                      todayKey
                    )}
                  </p>
                  <p className="mt-0.5 text-xs tabular-nums text-gray-500 dark:text-gray-400">
                    {workLabel}
                    {day.attended && day.overtimeMs > 0
                      ? ` ${t("desktopStatsOvertimeAdded", {
                          time: formatStatsDuration(day.overtimeMs, lang),
                        })}`
                      : ""}
                  </p>
                </div>
                <p
                  className="shrink-0 text-end text-xs text-gray-600 dark:text-gray-300"
                  title={t("knockCount", { count: day.woodfishCount })}
                >
                  <span className="block text-[10px] text-gray-400 dark:text-gray-500">
                    {t("desktopStatsKnocks")}
                  </span>
                  <span className="tabular-nums">
                    {formatWoodfishCountLabel(day.woodfishCount)}
                  </span>
                </p>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
