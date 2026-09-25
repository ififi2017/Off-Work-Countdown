"use client";

import { useEffect, useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import { ArrowUp, ChevronDown } from "lucide-react";

// 网页版首屏底部的一个按钮，两种状态：
// - 在首屏：淡淡的向下箭头，点了平滑滚到说明区；
// - 滚下去以后：变成悬浮的「回到倒计时」胶囊，点了平滑回到卡片。
// 「减少动态效果」时直接跳转，不做平滑滚动。

interface HeroScrollButtonProps {
  targetId: string;
  moreLabel: string;
  backLabel: string;
}

const SWAP = { duration: 0.18, ease: [0.23, 1, 0.32, 1] } as const;

export function HeroScrollButton({
  targetId,
  moreLabel,
  backLabel,
}: HeroScrollButtonProps) {
  const reduceMotion = useReducedMotion();
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const update = () => setScrolled(window.scrollY > window.innerHeight * 0.35);
    update();
    window.addEventListener("scroll", update, { passive: true });
    window.addEventListener("resize", update);
    return () => {
      window.removeEventListener("scroll", update);
      window.removeEventListener("resize", update);
    };
  }, []);

  const behavior: ScrollBehavior = reduceMotion ? "auto" : "smooth";
  const scrollDown = () =>
    document.getElementById(targetId)?.scrollIntoView({ behavior, block: "start" });
  const scrollUp = () => window.scrollTo({ top: 0, behavior });

  return (
    <div className="pointer-events-none fixed inset-x-0 bottom-5 z-40 flex justify-center">
      <AnimatePresence mode="wait" initial={false}>
        {scrolled ? (
          <motion.button
            key="back"
            type="button"
            onClick={scrollUp}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: 8 }}
            transition={SWAP}
            className="pointer-events-auto inline-flex h-10 items-center gap-2 rounded-full border border-black/[0.06] bg-white/85 px-4 text-sm font-medium text-gray-800 shadow-[0_8px_30px_-8px_rgba(15,23,42,0.25)] backdrop-blur-xl transition-colors hover:bg-white hover:text-gray-950 focus:outline-none focus-visible:ring-2 focus-visible:ring-gray-400 dark:border-white/[0.08] dark:bg-gray-900/85 dark:text-gray-200 dark:shadow-[0_8px_30px_-8px_rgba(0,0,0,0.7)] dark:hover:bg-gray-900 dark:hover:text-white"
          >
            <ArrowUp className="h-4 w-4" aria-hidden="true" />
            {backLabel}
          </motion.button>
        ) : (
          <motion.button
            key="more"
            type="button"
            onClick={scrollDown}
            aria-label={moreLabel}
            title={moreLabel}
            initial={{ opacity: 0, y: -6 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -6 }}
            transition={SWAP}
            // 矮窗口里卡片几乎占满一屏，箭头会压到卡片上，只在够高时出现。
            className="pointer-events-auto hidden h-9 w-9 items-center justify-center rounded-full text-gray-400 transition-colors hover:bg-black/[0.04] hover:text-gray-700 focus:outline-none focus-visible:ring-2 focus-visible:ring-gray-400 [@media(min-height:760px)]:inline-flex dark:text-gray-600 dark:hover:bg-white/[0.06] dark:hover:text-gray-300"
          >
            <ChevronDown className="h-5 w-5" aria-hidden="true" />
          </motion.button>
        )}
      </AnimatePresence>
    </div>
  );
}
