"use client";

import { WEEKDAY_ORDER, weekdayNames } from "@/lib/mobile/format";

/**
 * The workdays as seven 44 pt targets, Monday first — plain selection chips
 * rather than coloured tiles, so the only strong colour left on the screen is
 * the countdown itself.
 */
export function IosWorkdayGrid({
  lang,
  label,
  workdays,
  onChange,
  todayHighlight = false,
}: {
  lang: string;
  label: string;
  workdays: number[];
  onChange: (next: number[]) => void;
  /** Ring today's chip — used on the "not a workday" screen. */
  todayHighlight?: boolean;
}) {
  const names = weekdayNames(lang);
  const today = new Date().getDay();

  return (
    <div className="px-4 pb-4 pt-3.5">
      <div className="text-[17px] tracking-[-0.43px] text-[var(--ios-label)]">
        {label}
      </div>
      <div className="mt-3 grid grid-cols-7 gap-1.5">
        {WEEKDAY_ORDER.map((day) => {
          const selected = workdays.includes(day);
          return (
            <button
              key={day}
              type="button"
              role="switch"
              aria-checked={selected}
              aria-label={names[day]}
              onClick={() =>
                onChange(
                  selected
                    ? workdays.filter((value) => value !== day)
                    : [...workdays, day].sort()
                )
              }
              className="inline-flex h-11 items-center justify-center rounded-xl text-[13px]"
              style={{
                background: selected ? "var(--ios-title)" : "var(--ios-fill)",
                color: selected ? "var(--ios-bg)" : "var(--ios-label-2)",
                fontWeight: selected ? 600 : 500,
                boxShadow:
                  todayHighlight && day === today && !selected
                    ? "inset 0 0 0 2px var(--ios-accent)"
                    : undefined,
              }}
            >
              {names[day]}
            </button>
          );
        })}
      </div>
    </div>
  );
}
