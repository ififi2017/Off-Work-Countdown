"use client";

import { motion } from "framer-motion";
import { useRef } from "react";

interface ProgressBarProps {
  progress: number;
  compact?: boolean;
  dense?: boolean;
}

export function ProgressBar({
  progress,
  compact = false,
  dense = false,
}: ProgressBarProps) {
  const progressBarRef = useRef<HTMLDivElement>(null);

  return (
    <div
      className={compact ? "relative" : dense ? "relative pt-8" : "relative pt-10"}
      ref={progressBarRef}
    >
      <div
        className={`h-2 w-full overflow-hidden rounded-full ${
          compact ? "bg-white/15" : "bg-gray-200 dark:bg-gray-700"
        }`}
      >
        <motion.div
          className={compact ? "h-full bg-white" : "h-full bg-primary"}
          style={{ width: `${progress}%` }}
          transition={{
            type: "spring",
            stiffness: 300,
            damping: 30,
          }}
        />
      </div>
      {!compact && (
        <motion.div
          className="absolute top-0 left-0 transform -translate-y-full"
          style={{
            left: `calc(${progress}%)`,
            x: "-50%",
          }}
          transition={{ type: "spring", stiffness: 300, damping: 30 }}
        >
          <div className="relative">
            <div className="bg-primary text-primary-foreground px-3 py-1 rounded-md shadow-md text-sm font-semibold whitespace-nowrap">
              {(Math.floor(progress * 10) / 10).toFixed(1)}%
            </div>
            <div className="absolute left-1/2 top-full -translate-x-1/2 w-0 h-0 border-l-[6px] border-l-transparent border-r-[6px] border-r-transparent border-t-[6px] border-t-primary" />
          </div>
        </motion.div>
      )}
    </div>
  );
}
