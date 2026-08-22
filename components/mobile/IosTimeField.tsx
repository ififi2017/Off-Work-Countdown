"use client";

import { useState } from "react";
import { WheelPicker } from "@/components/WheelPicker";

const HOURS = Array.from({ length: 24 }, (_, hour) =>
  hour.toString().padStart(2, "0")
);
const MINUTES = Array.from({ length: 60 }, (_, minute) =>
  minute.toString().padStart(2, "0")
);

/**
 * A 56 pt row holding the hour and minute as two tappable chips.
 *
 * Tapping a chip opens the wheel in place rather than in a modal: the value the
 * user is changing stays on screen next to the shift it belongs to. The wheel
 * itself is the app's existing `WheelPicker`, which scrolls natively with
 * `scroll-snap` and never captures pointer events — the behaviour VoiceOver and
 * the system's own scrolling depend on.
 */
export function IosTimeField({
  label,
  value,
  onChange,
  separator = false,
}: {
  label: string;
  value: string;
  onChange: (next: string) => void;
  separator?: boolean;
}) {
  const [open, setOpen] = useState<"hour" | "minute" | null>(null);
  const [hour, minute] = value.split(":");

  const commit = (nextHour: string, nextMinute: string) =>
    onChange(`${nextHour}:${nextMinute}`);

  const chip = (part: "hour" | "minute", text: string) => {
    const active = open === part;
    return (
      <button
        type="button"
        aria-expanded={active}
        aria-label={`${label} ${text}`}
        onClick={() => setOpen(active ? null : part)}
        className="inline-flex h-9 min-w-[44px] items-center justify-center rounded-[9px] px-2 text-[17px] font-semibold tabular-nums"
        style={{
          background: active ? "var(--ios-title)" : "var(--ios-fill)",
          color: active ? "var(--ios-bg)" : "var(--ios-label)",
        }}
      >
        {text}
      </button>
    );
  };

  return (
    <>
      <div
        className={`ios-row ios-row-flush min-h-[56px]${
          separator && !open ? " ios-row-sep" : ""
        }`}
      >
        <span className="flex-1">{label}</span>
        <div dir="ltr" className="flex gap-1.5">
          {chip("hour", hour)}
          {chip("minute", minute)}
        </div>
      </div>
      {open && (
        <div
          className={`relative px-4 pb-2${separator ? " ios-row-sep ios-row-flush" : ""}`}
        >
          <WheelPicker
            items={open === "hour" ? HOURS : MINUTES}
            value={open === "hour" ? hour : minute}
            ariaLabel={label}
            onChange={(next) =>
              open === "hour" ? commit(next, minute) : commit(hour, next)
            }
            onSelect={(next) => {
              if (open === "hour") commit(next, minute);
              else commit(hour, next);
              setOpen(null);
            }}
          />
        </div>
      )}
    </>
  );
}
