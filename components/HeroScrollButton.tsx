"use client";

import { useEffect, useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import { ArrowUp, ChevronDown } from "lucide-react";

// 网页版首屏底部的一个按钮，两种状态：
// - 在首屏：卡片下方一行轻文字「获取 App」加向下箭头，点了平滑滚到 App 介绍；
//   它跟着首屏（父级 section 需 relative，并在底部留出位置），不悬浮在卡片上，
//   所以矮窗口、手机上也能一直显示；
// - 滚下去以后：变成悬浮的「回到倒计时」胶囊，点了平滑回到卡片。
// 「减少动态效果」时直接跳转，不做平滑滚动，箭头也不轻晃。

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
    <>
      <motion.button
        type="button"
        onClick={scrollDown}
        tabIndex={scrolled ? -1 : undefined}
        aria-hidden={scrolled || undefined}
        initial={false}
        animate={{ opacity: scrolled ? 0 : 1 }}
        transition={SWAP}
        className="group absolute inset-x-0 bottom-4 mx-auto inline-flex w-fit flex-col items-center gap-0.5 rounded-xl px-3 py-1.5 text-[0.8125rem] font-medium text-gray-500 transition-colors hover:text-gray-900 focus:outline-none focus-visible:ring-2 focus-visible:ring-gray-400 dark:text-gray-400 dark:hover:text-gray-100"
      >
        {moreLabel}
        <motion.span
          aria-hidden="true"
          className="text-gray-400 transition-colors group-hover:text-gray-700 dark:text-gray-500 dark:group-hover:text-gray-300"
          animate={reduceMotion || scrolled ? { y: 0 } : { y: [0, 3, 0] }}
          transition={
            reduceMotion || scrolled
              ? SWAP
              : { duration: 1.6, ease: "easeInOut", repeat: Infinity, repeatDelay: 2.4 }
          }
        >
          <ChevronDown className="h-4 w-4" />
        </motion.span>
      </motion.button>

      <div className="pointer-events-none fixed inset-x-0 bottom-5 z-40 flex justify-center">
        <AnimatePresence initial={false}>
          {scrolled && (
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
          )}
        </AnimatePresence>
      </div>
    </>
  );
}
