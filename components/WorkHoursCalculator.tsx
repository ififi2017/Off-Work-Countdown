"use client";

import { useEffect, useId, useMemo, useState } from "react";
import { ArrowUpRight, Timer } from "lucide-react";
import { encodeShift } from "@/lib/share";
import { officialHomeUrl } from "@/lib/site-urls";
import { track } from "@/lib/track";
import {
  MINUTES_PER_DAY,
  calculateFinishTime,
  calculateHoursWorked,
  parseClockTime,
  splitMinutes,
} from "@/lib/work-hours";

export interface WorkHoursCalculatorCopy {
  modeFinish: string;
  modeHours: string;
  startLabel: string;
  endLabel: string;
  workLabel: string;
  hoursUnit: string;
  minutesUnit: string;
  breakLabel: string;
  breakNone: string;
  breakMinutes: string;
  daysLabel: string;
  finishResult: string;
  nextDay: string;
  timeAtWork: string;
  hoursResult: string;
  clockTime: string;
  breakTaken: string;
  perWeek: string;
  toGo: string;
  invalidBreak: string;
  invalidSpan: string;
  startCountdown: string;
  durationHM: string;
  durationH: string;
  durationM: string;
  adEyebrow: string;
  adTitle: string;
  adBody: string;
  adCta: string;
}

type Mode = "finish" | "hours";

const BREAK_OPTIONS = [0, 15, 30, 45, 60, 90] as const;
const DAY_OPTIONS = [1, 2, 3, 4, 5, 6, 7] as const;
const PLATFORMS = "iPhone · iPad · Mac · Windows";

function fill(template: string, values: Record<string, string | number>): string {
  return template.replace(/\{\{(\w+)\}\}/g, (_, key: string) =>
    String(values[key] ?? "")
  );
}

function clampInt(raw: string, max: number): number {
  const value = Math.floor(Number(raw));
  if (!Number.isFinite(value) || value < 0) return 0;
  return Math.min(value, max);
}

/** 起止（当天第几分钟）→ 24 小时轴上的一段或两段（跨零点时折成两段）。 */
function timelineSegments(start: number, span: number): Array<[number, number]> {
  const end = start + span;
  if (end <= MINUTES_PER_DAY) return [[start, end]];
  return [
    [start, MINUTES_PER_DAY],
    [0, end - MINUTES_PER_DAY],
  ];
}

export function WorkHoursCalculator({
  lang,
  copy,
}: {
  lang: string;
  copy: WorkHoursCalculatorCopy;
}) {
  const id = useId();
  const [mode, setMode] = useState<Mode>("finish");
  const [start, setStart] = useState("09:00");
  const [end, setEnd] = useState("17:00");
  const [workHours, setWorkHours] = useState(8);
  const [workMinutes, setWorkMinutes] = useState(0);
  const [breakMinutes, setBreakMinutes] = useState<number>(60);
  const [days, setDays] = useState(5);

  // 首屏在服务端渲染成 24 小时制，挂载后才换成本地习惯（6:00 PM、下午6:00），
  // 避免服务端与浏览器 ICU 数据不同导致的水合不一致。「今天还剩多久」同理。
  const [now, setNow] = useState<Date | null>(null);
  useEffect(() => {
    setNow(new Date());
    const timer = window.setInterval(() => setNow(new Date()), 30_000);
    return () => window.clearInterval(timer);
  }, []);

  const timeFormatter = useMemo(() => {
    if (!now) return null;
    try {
      return new Intl.DateTimeFormat(lang, { hour: "numeric", minute: "2-digit" });
    } catch {
      return null;
    }
    // 只在首次挂载时建一次；now 每 30 秒更新，不必重建。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lang, now === null]);

  const formatTime = (value: string): string => {
    if (!timeFormatter) return value;
    const [h, m] = value.split(":").map(Number);
    return timeFormatter.format(new Date(2000, 0, 1, h, m));
  };

  const formatDuration = (total: number): string => {
    const { hours, minutes } = splitMinutes(total);
    if (hours > 0 && minutes > 0) return fill(copy.durationHM, { hours, minutes });
    if (hours > 0) return fill(copy.durationH, { hours });
    return fill(copy.durationM, { minutes });
  };

  const finish = calculateFinishTime(start, workHours * 60 + workMinutes, breakMinutes);
  const worked = calculateHoursWorked(start, end, breakMinutes);

  const startMinutes = parseClockTime(start);
  const shiftEnd = mode === "finish" ? finish?.end : worked ? end : undefined;
  const span = mode === "finish" ? finish?.spanMinutes : worked?.spanMinutes;
  const error =
    mode === "finish"
      ? finish
        ? null
        : startMinutes === null
          ? null
          : copy.invalidSpan
      : worked
        ? null
        : startMinutes === null || parseClockTime(end) === null
          ? null
          : copy.invalidBreak;

  // 今天这段班还剩多久：只在当前时刻落在这段班里时显示。
  let remaining: number | null = null;
  if (now && startMinutes !== null && span !== undefined) {
    const nowMinutes = now.getHours() * 60 + now.getMinutes();
    for (const offset of [0, -MINUTES_PER_DAY]) {
      const elapsed = nowMinutes - (startMinutes + offset);
      if (elapsed >= 0 && elapsed < span) remaining = span - elapsed;
    }
  }

  // 起止相同在倒计时里不成立（decodeShift 会拒绝），这时不给入口。
  const countdownHref =
    shiftEnd && shiftEnd !== start
      ? `/${lang}?s=${encodeShift({ start, end: shiftEnd })}&from=calculator`
      : null;

  const appHref = `${officialHomeUrl(lang)}?utm_source=off.rainif.com&utm_medium=referral&utm_campaign=work-hours-calculator`;

  const inputClass =
    "h-11 w-full rounded-xl border border-gray-200 bg-white px-3 text-base tabular-nums text-gray-950 shadow-sm outline-none transition-colors focus:border-gray-400 focus:ring-2 focus:ring-gray-200 dark:border-gray-700 dark:bg-gray-900 dark:text-white dark:focus:border-gray-500 dark:focus:ring-gray-700 [color-scheme:light] dark:[color-scheme:dark]";
  const labelClass = "mb-1.5 block text-sm font-medium text-gray-700 dark:text-gray-300";
  const chipClass = (selected: boolean) =>
    `h-9 min-w-[3rem] rounded-lg px-3 text-sm font-medium tabular-nums transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-gray-400 ${
      selected
        ? "bg-gray-950 text-white dark:bg-white dark:text-gray-950"
        : "bg-gray-100 text-gray-600 hover:bg-gray-200 hover:text-gray-900 dark:bg-white/[0.06] dark:text-gray-300 dark:hover:bg-white/[0.12] dark:hover:text-white"
    }`;

  return (
    <div className="space-y-4">
      <section className="rounded-2xl border border-gray-200/80 bg-white p-5 shadow-sm dark:border-gray-800 dark:bg-gray-800/40 sm:p-6">
        <div
          role="radiogroup"
          aria-label={`${copy.modeFinish} / ${copy.modeHours}`}
          className="grid grid-cols-2 gap-1 rounded-xl bg-gray-100 p-1 dark:bg-black/30"
        >
          {(
            [
              ["finish", copy.modeFinish],
              ["hours", copy.modeHours],
            ] as const
          ).map(([value, label]) => (
            <button
              key={value}
              type="button"
              role="radio"
              aria-checked={mode === value}
              onClick={() => setMode(value)}
              className={`min-h-10 rounded-lg px-3 py-2 text-sm font-semibold transition-all focus:outline-none focus-visible:ring-2 focus-visible:ring-gray-400 ${
                mode === value
                  ? "bg-white text-gray-950 shadow-sm dark:bg-white/[0.14] dark:text-white"
                  : "text-gray-500 hover:text-gray-800 dark:text-gray-400 dark:hover:text-gray-200"
              }`}
            >
              {label}
            </button>
          ))}
        </div>

        <div className="mt-6 grid gap-4 sm:grid-cols-2">
          <div>
            <label htmlFor={`${id}-start`} className={labelClass}>
              {copy.startLabel}
            </label>
            <input
              id={`${id}-start`}
              type="time"
              value={start}
              onChange={(e) => setStart(e.target.value)}
              className={inputClass}
            />
          </div>

          {mode === "finish" ? (
            <fieldset>
              <legend className={labelClass}>{copy.workLabel}</legend>
              <div className="grid grid-cols-2 gap-2">
                <div className="relative">
                  <input
                    type="number"
                    inputMode="numeric"
                    min={0}
                    max={23}
                    value={workHours}
                    aria-label={`${copy.workLabel} (${copy.hoursUnit})`}
                    onChange={(e) => setWorkHours(clampInt(e.target.value, 23))}
                    className={`${inputClass} pe-14`}
                  />
                  <span className="pointer-events-none absolute inset-y-0 end-3 flex items-center text-sm text-gray-400">
                    {copy.hoursUnit}
                  </span>
                </div>
                <div className="relative">
                  <input
                    type="number"
                    inputMode="numeric"
                    min={0}
                    max={59}
                    step={5}
                    value={workMinutes}
                    aria-label={`${copy.workLabel} (${copy.minutesUnit})`}
                    onChange={(e) => setWorkMinutes(clampInt(e.target.value, 59))}
                    className={`${inputClass} pe-14`}
                  />
                  <span className="pointer-events-none absolute inset-y-0 end-3 flex items-center text-sm text-gray-400">
                    {copy.minutesUnit}
                  </span>
                </div>
              </div>
            </fieldset>
          ) : (
            <div>
              <label htmlFor={`${id}-end`} className={labelClass}>
                {copy.endLabel}
              </label>
              <input
                id={`${id}-end`}
                type="time"
                value={end}
                onChange={(e) => setEnd(e.target.value)}
                className={inputClass}
              />
            </div>
          )}
        </div>

        <fieldset className="mt-5">
          <legend className={labelClass}>{copy.breakLabel}</legend>
          <div role="radiogroup" aria-label={copy.breakLabel} className="flex flex-wrap gap-2">
            {BREAK_OPTIONS.map((minutes) => (
              <button
                key={minutes}
                type="button"
                role="radio"
                aria-checked={breakMinutes === minutes}
                onClick={() => setBreakMinutes(minutes)}
                className={chipClass(breakMinutes === minutes)}
              >
                {minutes === 0 ? copy.breakNone : fill(copy.breakMinutes, { minutes })}
              </button>
            ))}
          </div>
        </fieldset>

        {mode === "hours" && (
          <fieldset className="mt-5">
            <legend className={labelClass}>{copy.daysLabel}</legend>
            <div role="radiogroup" aria-label={copy.daysLabel} className="flex flex-wrap gap-2">
              {DAY_OPTIONS.map((value) => (
                <button
                  key={value}
                  type="button"
                  role="radio"
                  aria-checked={days === value}
                  onClick={() => setDays(value)}
                  className={`${chipClass(days === value)} min-w-9 px-0`}
                >
                  {value}
                </button>
              ))}
            </div>
          </fieldset>
        )}

        <div className="mt-6 border-t border-gray-100 pt-6 dark:border-gray-700/70" aria-live="polite">
          {error ? (
            <p className="text-sm leading-6 text-orange-700 dark:text-orange-300">{error}</p>
          ) : mode === "finish" && finish ? (
            <div>
              <p className="text-sm font-medium text-gray-500 dark:text-gray-400">
                {copy.finishResult}
              </p>
              <p className="mt-1 flex flex-wrap items-baseline gap-x-3 gap-y-1">
                <span className="text-5xl font-semibold tracking-tight tabular-nums text-gray-950 dark:text-white">
                  {formatTime(finish.end)}
                </span>
                {finish.dayOffset > 0 && (
                  <span className="rounded-md bg-orange-50 px-2 py-0.5 text-xs font-semibold text-orange-700 dark:bg-orange-400/10 dark:text-orange-300">
                    {copy.nextDay}
                  </span>
                )}
              </p>
              <p className="mt-2 text-sm leading-6 text-gray-600 dark:text-gray-400">
                {fill(copy.timeAtWork, { duration: formatDuration(finish.spanMinutes) })}
              </p>
            </div>
          ) : mode === "hours" && worked ? (
            <div>
              <p className="text-sm font-medium text-gray-500 dark:text-gray-400">
                {copy.hoursResult}
              </p>
              <p className="mt-1 flex flex-wrap items-baseline gap-x-3 gap-y-1">
                <span className="text-5xl font-semibold tracking-tight tabular-nums text-gray-950 dark:text-white">
                  {formatDuration(worked.paidMinutes)}
                </span>
                {worked.overnight && (
                  <span className="rounded-md bg-orange-50 px-2 py-0.5 text-xs font-semibold text-orange-700 dark:bg-orange-400/10 dark:text-orange-300">
                    {copy.nextDay}
                  </span>
                )}
              </p>
              <dl className="mt-4 grid grid-cols-3 gap-3 text-sm">
                {(
                  [
                    [copy.clockTime, formatDuration(worked.spanMinutes)],
                    [
                      copy.breakTaken,
                      worked.breakMinutes > 0 ? formatDuration(worked.breakMinutes) : copy.breakNone,
                    ],
                    [copy.perWeek, formatDuration(worked.paidMinutes * days)],
                  ] as const
                ).map(([label, value]) => (
                  <div key={label} className="min-w-0">
                    <dt className="truncate text-xs text-gray-500 dark:text-gray-400">{label}</dt>
                    <dd className="mt-0.5 font-semibold tabular-nums text-gray-900 dark:text-gray-100">
                      {value}
                    </dd>
                  </div>
                ))}
              </dl>
            </div>
          ) : (
            <p className="text-5xl font-semibold text-gray-300 dark:text-gray-600">—</p>
          )}

          {startMinutes !== null && span !== undefined && !error && (
            <div className="mt-6" aria-hidden="true">
              <div className="relative h-2 rounded-full bg-gray-100 dark:bg-white/[0.08]">
                {timelineSegments(startMinutes, span).map(([from, to]) => (
                  <span
                    key={from}
                    className="absolute inset-y-0 rounded-full bg-orange-500"
                    style={{
                      insetInlineStart: `${(from / MINUTES_PER_DAY) * 100}%`,
                      width: `${((to - from) / MINUTES_PER_DAY) * 100}%`,
                    }}
                  />
                ))}
                {now && (
                  <span
                    className="absolute -top-1 h-4 w-0.5 rounded-full bg-gray-900 dark:bg-white"
                    style={{
                      insetInlineStart: `${((now.getHours() * 60 + now.getMinutes()) / MINUTES_PER_DAY) * 100}%`,
                    }}
                  />
                )}
              </div>
              <div className="mt-1.5 flex justify-between text-[11px] tabular-nums text-gray-400 dark:text-gray-500">
                {["00", "06", "12", "18", "24"].map((tick) => (
                  <span key={tick}>{tick}</span>
                ))}
              </div>
            </div>
          )}

          {(countdownHref || remaining !== null) && !error && (
            <div className="mt-6 flex flex-wrap items-center justify-between gap-3">
              {remaining !== null ? (
                <p className="text-sm font-medium tabular-nums text-gray-700 dark:text-gray-300">
                  {fill(copy.toGo, { duration: formatDuration(remaining) })}
                </p>
              ) : (
                <span />
              )}
              {countdownHref && shiftEnd && (
                <a
                  href={countdownHref}
                  className="inline-flex h-11 items-center gap-2 rounded-xl bg-gray-950 px-4 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-black focus:outline-none focus-visible:ring-2 focus-visible:ring-gray-400 focus-visible:ring-offset-2 dark:bg-white dark:text-gray-950 dark:hover:bg-gray-100 dark:focus-visible:ring-offset-gray-900"
                >
                  <Timer className="h-4 w-4 shrink-0" aria-hidden="true" />
                  {fill(copy.startCountdown, { time: formatTime(shiftEnd) })}
                </a>
              )}
            </div>
          )}
        </div>
      </section>

      <aside className="flex items-start gap-4 rounded-2xl border border-gray-200/80 bg-white/70 p-5 dark:border-gray-800 dark:bg-gray-800/25">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src="/icon-192x192.png"
          alt=""
          width={48}
          height={48}
          className="h-12 w-12 shrink-0 rounded-[0.8rem] shadow-sm"
        />
        <div className="min-w-0 flex-1">
          <p className="text-xs font-medium text-gray-500 dark:text-gray-400">{copy.adEyebrow}</p>
          <h2 className="mt-0.5 font-semibold tracking-tight text-gray-950 dark:text-white">
            {copy.adTitle}
          </h2>
          <p className="mt-1 text-sm leading-6 text-gray-600 dark:text-gray-400">{copy.adBody}</p>
          <div className="mt-3 flex flex-wrap items-center justify-between gap-x-4 gap-y-2">
            <span className="text-xs text-gray-500 dark:text-gray-400">{PLATFORMS}</span>
            <a
              href={appHref}
              target="_blank"
              rel="noopener"
              onClick={() => track("calculator_app_open")}
              className="inline-flex items-center gap-1 text-sm font-semibold text-orange-700 underline-offset-4 transition-colors hover:text-orange-800 hover:underline dark:text-orange-300 dark:hover:text-orange-200"
            >
              {copy.adCta}
              <ArrowUpRight className="h-4 w-4 rtl:-scale-x-100" aria-hidden="true" />
            </a>
          </div>
        </div>
      </aside>
    </div>
  );
}
