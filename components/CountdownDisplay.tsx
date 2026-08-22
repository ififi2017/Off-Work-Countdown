"use client";

import { motion } from "framer-motion";
import { ProgressBar } from "./ProgressBar";

interface CountdownDisplayProps {
  timeLeft: string;
  /** 有值时分两行：标题占主字号，timeLeft 降为次行。用于「今日已下班」。 */
  title?: string;
  progress: number;
  compact?: boolean;
  dense?: boolean;
  overtime?: boolean;
  status?: boolean;
  standby?: boolean;
  mobile?: boolean;
  forceLtr?: boolean;
}

export function CountdownDisplay({
  timeLeft,
  title,
  progress,
  compact = false,
  dense = false,
  overtime = false,
  status = false,
  standby = false,
  mobile = false,
  forceLtr = false,
}: CountdownDisplayProps) {
  return (
    <motion.div
      key="countdown"
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -20 }}
      transition={{ duration: 0.3 }}
      className={compact ? "space-y-2" : dense ? "space-y-3" : mobile ? "space-y-6" : "space-y-4"}
    >
      {title && (
        <div
          className="text-center font-bold dark:text-white"
          style={{
            fontSize: compact
              ? "1.1rem"
              : dense
                ? "min(7vw, 1.8rem)"
                : mobile
                  ? "clamp(1.75rem, 8vw, 2.35rem)"
                  : "min(7vw, 1.9rem)",
            lineHeight: "1.25",
          }}
        >
          {title}
        </div>
      )}
      <div
        dir={forceLtr ? "ltr" : undefined}
        className={`text-center tabular-nums dark:text-white ${
          title ? "font-semibold text-gray-600 dark:text-gray-300" : "font-bold"
        } ${compact || status || mobile ? "whitespace-nowrap tracking-tight" : ""}`}
        style={{
          fontSize: title
            ? compact
              ? "0.95rem"
              : "min(5.5vw, 1.35rem)"
            : status
            ? "1.15rem"
            : compact
            ? "1.7rem"
            : dense
              ? "min(8vw, 2.1rem)"
              : mobile
                ? "clamp(2.2rem, 9.5vw, 3.25rem)"
              : "min(8vw, 2.25rem)",
          lineHeight: "1.2",
          wordBreak: "keep-all",
          overflowWrap: status ? "normal" : "break-word",
          overflow: status ? "hidden" : undefined,
          textOverflow: status ? "ellipsis" : undefined,
          maxWidth: "100%",
        }}
      >
        {timeLeft}
      </div>
      <ProgressBar progress={progress} compact={compact} dense={dense} overtime={overtime} standby={standby} />
    </motion.div>
  );
}
