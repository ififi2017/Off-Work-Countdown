"use client";

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
  const [hour, minute] = value.split(":");

  const generateHourOptions = () => {
    const options = [];
    for (let i = 0; i < 24; i++) {
      const hour = i.toString().padStart(2, "0");
      options.push(hour);
    }
    return options;
  };

  const generateMinuteOptions = () => {
    const options = [];
    for (let i = 0; i < 60; i++) {
      const minute = i.toString().padStart(2, "0");
      options.push(minute);
    }
    return options;
  };

  return (
    <div className="space-y-2">
      <Label htmlFor={`${id}Hour`} className="dark:text-gray-200">
        {label}
      </Label>
      <div className="flex space-x-2">
        <select
          id={`${id}Hour`}
          value={hour}
          onChange={(e) => onChange(e.target.value, minute)}
          className="w-1/2 p-2 border rounded dark:bg-gray-700 dark:border-gray-600 dark:text-white"
        >
          {generateHourOptions().map((hour) => (
            <option key={hour} value={hour}>
              {hour}
            </option>
          ))}
        </select>
        <select
          id={`${id}Minute`}
          value={minute}
          onChange={(e) => onChange(hour, e.target.value)}
          className="w-1/2 p-2 border rounded dark:bg-gray-700 dark:border-gray-600 dark:text-white"
        >
          {generateMinuteOptions().map((minute) => (
            <option key={minute} value={minute}>
              {minute}
            </option>
          ))}
        </select>
      </div>
    </div>
  );
}
