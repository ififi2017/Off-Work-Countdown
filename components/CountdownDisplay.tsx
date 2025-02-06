'use client';

import { motion } from "framer-motion";
import { ProgressBar } from "./ProgressBar";

interface CountdownDisplayProps {
  timeLeft: string;
  progress: number;
}

export function CountdownDisplay({ timeLeft, progress }: CountdownDisplayProps) {
  return (
    <motion.div
      key="countdown"
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -20 }}
      transition={{ duration: 0.3 }}
      className="space-y-4"
    >
      <div
        className="text-center font-bold dark:text-white"
        style={{
          fontSize: 'min(8vw, 2.25rem)',
          lineHeight: '1.2',
          wordBreak: 'keep-all',
          overflowWrap: 'break-word',
          maxWidth: '100%'
        }}
      >
        {timeLeft}
      </div>
      <ProgressBar progress={progress} />
    </motion.div>
  );
} 