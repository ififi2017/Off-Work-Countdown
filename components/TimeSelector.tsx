"use client";

import { useEffect, useRef, useState } from "react";
import { AnimatePresence, LazyMotion, domAnimation, m } from "framer-motion";
import { ChevronDown } from "lucide-react";

import { Label } from "@/components/ui/label";
import { WheelPicker } from "./WheelPicker";

interface TimeSelectorProps {
  id: string;
  label: string;
  value: string;
  onChange: (hour: string, minute: string) => void;
  compact?: boolean;
  mobile?: boolean;
  hourLabel?: string;
  minuteLabel?: string;
  menuSide?: "top" | "bottom" | "auto";
}

export function TimeSelector({
  id,
  label,
  value,
  onChange,
  compact = false,
  mobile = false,
  hourLabel = "Select hour",
  minuteLabel = "Select minute",
  menuSide = "bottom",
}: TimeSelectorProps) {
  const [hourInput, setHourInput] = useState(() => value.split(":")[0]);
  const [minuteInput, setMinuteInput] = useState(() => value.split(":")[1]);
  const [openMenu, setOpenMenu] = useState<"hour" | "minute" | null>(null);
  const [opensAbove, setOpensAbove] = useState(menuSide === "top");
  const containerRef = useRef<HTMLDivElement>(null);

  function openOptions(type: "hour" | "minute", toggle = false) {
    if (toggle && openMenu === type) {
      setOpenMenu(null);
      return;
    }
    let above = menuSide === "top";
    if (menuSide === "auto" && containerRef.current) {
      const field =
        containerRef.current.querySelectorAll("input")[type === "hour" ? 0 : 1];
      const rect = field.getBoundingClientRect();
      let top = 0;
      let bottom = window.innerHeight;
      // A popup's settings scroll area can be smaller than its viewport.
      for (
        let parent = field.parentElement;
        parent;
        parent = parent.parentElement
      ) {
        if (/(auto|scroll|hidden)/.test(getComputedStyle(parent).overflowY)) {
          const bounds = parent.getBoundingClientRect();
          top = Math.max(top, bounds.top);
          bottom = Math.min(bottom, bounds.bottom);
        }
      }
      above = rect.top - top > bottom - rect.bottom;
    }
    setOpensAbove(above);
    setOpenMenu(type);
  }

  // keep local input in sync with external value (e.g. reset button)
  useEffect(() => {
    const [h, m] = value.split(":");
    setHourInput(h);
    setMinuteInput(m);
  }, [value]);

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (
        containerRef.current &&
        !containerRef.current.contains(event.target as Node)
      ) {
        setOpenMenu(null);
      }
    };

    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  const generateHourOptions = () => {
    const options = [];
    for (let i = 0; i < 24; i++) {
      const hourString = i.toString().padStart(2, "0");
      options.push(hourString);
    }
    return options;
  };

  const generateMinuteOptions = () => {
    const options = [];
    for (let i = 0; i < 60; i++) {
      const minuteString = i.toString().padStart(2, "0");
      options.push(minuteString);
    }
    return options;
  };

  const clampAndPad = (val: string, max: number) => {
    const numeric = val.replace(/\D/g, "").slice(0, 2);
    const clampedNumber =
      numeric === "" ? 0 : Math.min(max, Math.max(0, parseInt(numeric, 10)));
    const clamped = clampedNumber.toString().padStart(2, "0");
    return clamped.toString().padStart(2, "0");
  };

  const commitTime = (nextHour: string, nextMinute: string) => {
    const safeHour = clampAndPad(nextHour, 23);
    const safeMinute = clampAndPad(nextMinute, 59);
    setHourInput(safeHour);
    setMinuteInput(safeMinute);
    onChange(safeHour, safeMinute);
  };

  const handleHourInput = (val: string) => {
    const digits = val.replace(/\D/g, "").slice(0, 2);
    setHourInput(digits);
    if (digits.length === 2) {
      commitTime(digits, minuteInput);
    }
  };

  const handleMinuteInput = (val: string) => {
    const digits = val.replace(/\D/g, "").slice(0, 2);
    setMinuteInput(digits);
    if (digits.length === 2) {
      commitTime(hourInput, digits);
    }
  };

  const optionList = (items: string[], type: "hour" | "minute") => (
    <LazyMotion features={domAnimation}>
      <AnimatePresence>
        {openMenu === type && (
          <m.div
            key={`${type}-menu`}
            initial={{ opacity: 0, scale: 0.98, y: -4 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.98, y: -4 }}
            transition={{ duration: 0.12 }}
            // 主题给卡片加了玻璃效果，bg-popover 在这里会透出底下的工作日按钮，
            // 滚轮读数会糊成一片，所以这层必须自己是不透明的。
            className={`absolute z-30 w-full overflow-hidden rounded-lg border border-input bg-white p-1 text-popover-foreground shadow-lg dark:bg-gray-800 ${opensAbove ? "bottom-full mb-1" : "mt-1"}`}
          >
            <WheelPicker
              items={items}
              value={type === "hour" ? hourInput : minuteInput}
              ariaLabel={type === "hour" ? hourLabel : minuteLabel}
              visibleRows={compact || mobile ? 5 : 7}
              onChange={(item) =>
                commitTime(
                  type === "hour" ? item : hourInput,
                  type === "minute" ? item : minuteInput,
                )
              }
              onSelect={(item) => {
                commitTime(
                  type === "hour" ? item : hourInput,
                  type === "minute" ? item : minuteInput,
                );
                setOpenMenu(null);
              }}
            />
          </m.div>
        )}
      </AnimatePresence>
    </LazyMotion>
  );

  return (
    <div
      className={compact ? "space-y-1.5" : mobile ? "space-y-2.5" : "space-y-2"}
      ref={containerRef}
      onKeyDown={(event) => {
        if (event.key === "Escape" && openMenu) {
          event.stopPropagation();
          setOpenMenu(null);
        }
      }}
    >
      <Label
        htmlFor={`${id}Hour`}
        className={
          compact || mobile
            ? "text-xs font-medium text-muted-foreground"
            : "dark:text-gray-200"
        }
      >
        {label}
      </Label>
      {/* 外层 grid 已把两个选择器各分一半，这里铺满自己那一半即可。 */}
      <div className="flex gap-2">
        <div className="w-1/2">
          <div className="relative">
            <input
              id={`${id}Hour`}
              aria-label={`${label} · ${hourLabel}`}
              type="text"
              inputMode="numeric"
              autoComplete="off"
              autoCorrect="off"
              autoCapitalize="none"
              spellCheck={false}
              pattern="[0-9]*"
              className={`flex w-full items-center justify-between border border-input bg-background ring-offset-background placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 dark:border-gray-600 dark:bg-gray-700 dark:text-white ${
                compact
                  ? "h-9 rounded-lg px-3 py-1.5 pe-8 text-sm"
                  : mobile
                    ? "h-12 rounded-xl px-3 py-2 pe-10 text-base font-semibold tabular-nums"
                    : "h-10 rounded-lg px-3 py-2 pe-8 text-sm"
              }`}
              value={hourInput}
              onChange={(e) => handleHourInput(e.target.value)}
              onFocus={() => openOptions("hour")}
              onBlur={() => commitTime(hourInput, minuteInput)}
              placeholder="HH"
            />
            <button
              type="button"
              className={`absolute end-0 top-1/2 inline-flex -translate-y-1/2 items-center justify-center text-muted-foreground hover:text-foreground ${mobile ? "h-12 w-10" : "h-8 w-8"}`}
              onClick={() => openOptions("hour", true)}
              aria-label={`${label} · ${hourLabel}`}
              aria-expanded={openMenu === "hour"}
            >
              <ChevronDown className="h-4 w-4" />
            </button>
            {optionList(generateHourOptions(), "hour")}
          </div>
        </div>
        <div className="w-1/2">
          <div className="relative">
            <input
              id={`${id}Minute`}
              aria-label={`${label} · ${minuteLabel}`}
              type="text"
              inputMode="numeric"
              autoComplete="off"
              autoCorrect="off"
              autoCapitalize="none"
              spellCheck={false}
              pattern="[0-9]*"
              className={`flex w-full items-center justify-between border border-input bg-background ring-offset-background placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 dark:border-gray-600 dark:bg-gray-700 dark:text-white ${
                compact
                  ? "h-9 rounded-lg px-3 py-1.5 pe-8 text-sm"
                  : mobile
                    ? "h-12 rounded-xl px-3 py-2 pe-10 text-base font-semibold tabular-nums"
                    : "h-10 rounded-lg px-3 py-2 pe-8 text-sm"
              }`}
              value={minuteInput}
              onChange={(e) => handleMinuteInput(e.target.value)}
              onFocus={() => openOptions("minute")}
              onBlur={() => commitTime(hourInput, minuteInput)}
              placeholder="MM"
            />
            <button
              type="button"
              className={`absolute end-0 top-1/2 inline-flex -translate-y-1/2 items-center justify-center text-muted-foreground hover:text-foreground ${mobile ? "h-12 w-10" : "h-8 w-8"}`}
              onClick={() => openOptions("minute", true)}
              aria-label={`${label} · ${minuteLabel}`}
              aria-expanded={openMenu === "minute"}
            >
              <ChevronDown className="h-4 w-4" />
            </button>
            {optionList(generateMinuteOptions(), "minute")}
          </div>
        </div>
      </div>
    </div>
  );
}
