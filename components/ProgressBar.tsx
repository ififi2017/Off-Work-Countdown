'use client';

import { motion } from "framer-motion";
import { useRef } from "react";

interface ProgressBarProps {
  progress: number;
}

export function ProgressBar({ progress }: ProgressBarProps) {
  const progressBarRef = useRef<HTMLDivElement>(null);

  return (
    <div className="relative pt-10" ref={progressBarRef}>
      <div className="w-full h-2 bg-gray-200 dark:bg-gray-700 rounded-full overflow-hidden">
        <motion.div
          className="h-full bg-primary"
          style={{ width: `${progress}%` }}
          transition={{
            type: "spring",
            stiffness: 300,
            damping: 30,
          }}
        />
      </div>
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
    </div>
  );
} 