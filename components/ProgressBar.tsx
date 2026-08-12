"use client";

import { motion } from "framer-motion";
import { useRef } from "react";

interface ProgressBarProps {
  progress: number;
  compact?: boolean;
  dense?: boolean;
  overtime?: boolean;
  /** 午休等暂停状态：轨道走一道掠光，表示在待命而不是停摆。 */
  standby?: boolean;
}

export function ProgressBar({
  progress,
  compact = false,
  dense = false,
  overtime = false,
  standby = false,
}: ProgressBarProps) {
  const progressBarRef = useRef<HTMLDivElement>(null);
  const boundedProgress = Math.min(100, Math.max(0, progress));

  return (
    <div
      className={compact ? "relative" : dense ? "relative pt-8" : "relative pt-10"}
      ref={progressBarRef}
    >
      <div
        className={`relative h-2 w-full overflow-hidden rounded-full ${
          compact ? "bg-white/15" : "bg-gray-200 dark:bg-gray-700"
        } ${standby ? "progress-standby" : ""}`}
      >
        <motion.div
          className={
            compact
              ? "h-full bg-white"
              : overtime
                ? "h-full bg-orange-500"
                : "h-full bg-primary"
          }
          style={{ width: `${boundedProgress}%` }}
          transition={{
            type: "spring",
            stiffness: 300,
            damping: 30,
          }}
        />
      </div>
      {!compact && (
        // 轨道与下方汇总卡片同宽。气泡位置必须如实落在进度百分比上——靠平移
        // 气泡来“防溢出”会让视觉读数与真实进度错位，所以宁可在 0% / 100%
        // 时让它露出边缘一点点。
        //
        // 容器必须贴着轨道（bottom-0），不是贴着组件顶部：根节点有 pt-10，
        // 用 top-0 会让气泡整体上移 40px，直接撞进上方的倒计时数字。
        // 容器给足轨道高度再用 bottom-full，尖角才落在轨道上方的空隙里；
        // 之前用 -translate-y-full，6px 的尖角会直接压进轨道。
        <div className="pointer-events-none absolute inset-x-0 bottom-0 h-2">
          <motion.div
            className="absolute bottom-full mb-[7px]"
            style={{
              left: `${boundedProgress}%`,
              x: "-50%",
            }}
            transition={{ type: "spring", stiffness: 300, damping: 30 }}
          >
            <div className="relative">
              <div className={`${overtime ? "bg-orange-500 text-white" : "bg-primary text-primary-foreground"} whitespace-nowrap rounded-md px-3 py-1 text-sm font-semibold shadow-md`}>
                {(Math.floor(boundedProgress * 10) / 10).toFixed(1)}%
              </div>
              <div className={`absolute left-1/2 top-full h-0 w-0 -translate-x-1/2 border-l-[6px] border-r-[6px] border-t-[6px] border-l-transparent border-r-transparent ${overtime ? "border-t-orange-500" : "border-t-primary"}`} />
            </div>
          </motion.div>
        </div>
      )}
    </div>
  );
}
