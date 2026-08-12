"use client";

import { motion } from "framer-motion";
import { useEffect, useLayoutEffect, useRef, useState } from "react";

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
  const bubbleRef = useRef<HTMLDivElement>(null);
  const boundedProgress = Math.min(100, Math.max(0, progress));

  // 气泡在 0% 和 100% 时有一半探出轨道，窗口会把探出的部分切掉——100% 那格
  // 看到的是一个缺了右半边的方块。这里把气泡框推回可见范围，尖角留在真实
  // 百分比上，读数不会跟着位移走。
  //
  // 参照系是窗口而不是轨道：轨道两侧本来就还有卡片内边距，按轨道夹会多推
  // 二十几个像素，把尖角挤到气泡的圆角外面去，看着像脱钩。再对位移本身设
  // 一道上限，保证尖角无论如何都落在气泡的平直段里。
  const [bubbleShiftPx, setBubbleShiftPx] = useState(0);
  const useIsomorphicLayoutEffect =
    typeof window === "undefined" ? useEffect : useLayoutEffect;
  useIsomorphicLayoutEffect(() => {
    const measure = () => {
      const track = progressBarRef.current;
      const bubble = bubbleRef.current;
      if (!track || !bubble) return;
      const trackRect = track.getBoundingClientRect();
      const halfBubble = bubble.offsetWidth / 2;
      if (!trackRect.width || !halfBubble) return;
      // 尖角半宽 6px 加上气泡 6px 的圆角。
      const arrowInset = 12;
      const edgeMargin = 6;
      const center = trackRect.left + (trackRect.width * boundedProgress) / 100;
      const clamped = Math.min(
        Math.max(center, edgeMargin + halfBubble),
        window.innerWidth - edgeMargin - halfBubble
      );
      const maxShift = Math.max(0, halfBubble - arrowInset);
      const shift = clamped - center;
      setBubbleShiftPx(
        Math.min(Math.max(shift, -maxShift), maxShift)
      );
    };
    measure();
    window.addEventListener("resize", measure);
    return () => window.removeEventListener("resize", measure);
  }, [boundedProgress, compact, useIsomorphicLayoutEffect]);

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
        // 轨道与下方汇总卡片同宽。气泡框会被夹进轨道内以免被窗口切掉，但
        // 尖角始终落在真实百分比上，视觉读数不会跟着位移走。
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
              <div
                ref={bubbleRef}
                style={{ transform: `translateX(${bubbleShiftPx}px)` }}
                className={`${overtime ? "bg-orange-500 text-white" : "bg-primary text-primary-foreground"} whitespace-nowrap rounded-md px-3 py-1 text-sm font-semibold shadow-md`}
              >
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
