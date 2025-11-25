"use client";

import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { ChevronDown } from "lucide-react";

import { Label } from "@/components/ui/label";

interface TimeSelectorProps {
  id: string;
  label: string;
  value: string;
  onChange: (hour: string, minute: string) => void;
}

export function TimeSelector({
  id,
  label,
  value,
  onChange,
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
          className="absolute z-20 mt-1 w-full overflow-hidden rounded-md border border-input bg-popover text-popover-foreground shadow-md"
        >
          <div className="max-h-60 overflow-y-auto p-1">
            {items.map((item) => (
              <button
                type="button"
                key={item}
                className="w-full rounded-sm px-3 py-2 text-left text-sm hover:bg-accent hover:text-accent-foreground focus:bg-accent focus:text-accent-foreground"
                onClick={() => {
                  commitTime(
                    type === "hour" ? item : hourInput,
                    type === "minute" ? item : minuteInput
                  );
                  setOpenMenu(null);
                }}
              >
                {item}
              </button>
            ))}
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );

  return (
    <div className="space-y-2" ref={containerRef}>
      <Label htmlFor={`${id}Hour`} className="dark:text-gray-200">
        {label}
      </Label>
      <div className="flex space-x-2">
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
              className="flex h-10 w-full items-center justify-between rounded-md border border-input bg-background px-3 py-2 pr-10 text-sm ring-offset-background placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
              value={hourInput}
              onChange={(e) => handleHourInput(e.target.value)}
              onFocus={() => setOpenMenu("hour")}
              onBlur={() => commitTime(hourInput, minuteInput)}
              placeholder="HH"
            />
            <button
              type="button"
              className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
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
              className="flex h-10 w-full items-center justify-between rounded-md border border-input bg-background px-3 py-2 pr-10 text-sm ring-offset-background placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
              value={minuteInput}
              onChange={(e) => handleMinuteInput(e.target.value)}
              onFocus={() => setOpenMenu("minute")}
              onBlur={() => commitTime(hourInput, minuteInput)}
              placeholder="MM"
            />
            <button
              type="button"
              className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
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
