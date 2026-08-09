"use client";

import { motion } from "framer-motion";
import { ProgressBar } from "./ProgressBar";

interface CountdownDisplayProps {
  timeLeft: string;
  progress: number;
  compact?: boolean;
  dense?: boolean;
}

export function CountdownDisplay({
  timeLeft,
  progress,
  compact = false,
  dense = false,
}: CountdownDisplayProps) {
  return (
    <motion.div
      key="countdown"
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -20 }}
      transition={{ duration: 0.3 }}
      className={compact ? "space-y-2" : dense ? "space-y-3" : "space-y-4"}
    >
      <div
        className={`text-center font-bold tabular-nums dark:text-white ${
          compact ? "whitespace-nowrap tracking-tight" : ""
        }`}
        style={{
          fontSize: compact
            ? "1.7rem"
            : dense
              ? "min(8vw, 2.1rem)"
              : "min(8vw, 2.25rem)",
          lineHeight: "1.2",
          wordBreak: "keep-all",
          overflowWrap: "break-word",
          maxWidth: "100%",
        }}
      >
        {timeLeft}
      </div>
      <ProgressBar progress={progress} compact={compact} dense={dense} />
    </motion.div>
  );
}
