"use client";

import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
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
}

export function TimeSelector({
  id,
  label,
  value,
  onChange,
  compact = false,
  mobile = false,
}: TimeSelectorProps) {
  const [hourInput, setHourInput] = useState(() => value.split(":")[0]);
  const [minuteInput, setMinuteInput] = useState(() => value.split(":")[1]);
  const [openMenu, setOpenMenu] = useState<"hour" | "minute" | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  // keep local input in sync with external value (e.g. reset button)
  useEffect(() => {
    const [h, m] = value.split(":");
    setHourInput(h);
    setMinuteInput(m);
  }, [value]);

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
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
    <AnimatePresence>
      {openMenu === type && (
        <motion.div
          key={`${type}-menu`}
          initial={{ opacity: 0, scale: 0.98, y: -4 }}
          animate={{ opacity: 1, scale: 1, y: 0 }}
          exit={{ opacity: 0, scale: 0.98, y: -4 }}
          transition={{ duration: 0.12 }}
          // 主题给卡片加了玻璃效果，bg-popover 在这里会透出底下的工作日按钮，
          // 滚轮读数会糊成一片，所以这层必须自己是不透明的。
          className="absolute z-30 mt-1 w-full overflow-hidden rounded-lg border border-input bg-white p-1 text-popover-foreground shadow-lg dark:bg-gray-800"
        >
          <WheelPicker
            items={items}
            value={type === "hour" ? hourInput : minuteInput}
            ariaLabel={type === "hour" ? "Select hour" : "Select minute"}
            onChange={(item) =>
              commitTime(
                type === "hour" ? item : hourInput,
                type === "minute" ? item : minuteInput
              )
            }
            onSelect={(item) => {
              commitTime(
                type === "hour" ? item : hourInput,
                type === "minute" ? item : minuteInput
              );
              setOpenMenu(null);
            }}
          />
        </motion.div>
      )}
    </AnimatePresence>
  );

  return (
    <div className={compact ? "space-y-1.5" : mobile ? "space-y-2.5" : "space-y-2"} ref={containerRef}>
      <Label
        htmlFor={`${id}Hour`}
        className={compact || mobile ? "text-xs font-medium text-muted-foreground" : "dark:text-gray-200"}
      >
        {label}
      </Label>
      {/* 外层 grid 已把两个选择器各分一半，这里铺满自己那一半即可。 */}
      <div className="flex gap-2">
        <div className="w-1/2">
          <div className="relative">
            <input
              id={`${id}Hour`}
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
              onFocus={() => setOpenMenu("hour")}
              onBlur={() => commitTime(hourInput, minuteInput)}
              placeholder="HH"
            />
            <button
              type="button"
              className={`absolute end-0 top-1/2 inline-flex -translate-y-1/2 items-center justify-center text-muted-foreground hover:text-foreground ${mobile ? "h-12 w-10" : "h-8 w-8"}`}
              onClick={() => setOpenMenu((prev) => (prev === "hour" ? null : "hour"))}
              aria-label="Select hour"
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
              onFocus={() => setOpenMenu("minute")}
              onBlur={() => commitTime(hourInput, minuteInput)}
              placeholder="MM"
            />
            <button
              type="button"
              className={`absolute end-0 top-1/2 inline-flex -translate-y-1/2 items-center justify-center text-muted-foreground hover:text-foreground ${mobile ? "h-12 w-10" : "h-8 w-8"}`}
              onClick={() => setOpenMenu((prev) => (prev === "minute" ? null : "minute"))}
              aria-label="Select minute"
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
