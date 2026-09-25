"use client";

import { AnimatePresence, motion, useReducedMotion } from "framer-motion";

// Web 版的 SwiftUI `.contentTransition(.numericText(countsDown: true))`，
// 与 iOS 的 OWCCountdownTextTransition 同一套参数：
// - 只有变了的那一位在动，其余字符原地不动（外层用等宽数字，位置不会跳）；
// - 倒计时方向：新数字从上方落下、旧数字向下淡出，带一点模糊；
// - 时长取 iOS OWCMotion.countdownTick：linear 0.16s；
// - 系统开启「减少动态效果」时直接换字，与 iOS 的 `.identity` 一致。
//
// 文案格式不变（「6 小时 29 分钟 45 秒」照旧），只换过渡。按空格分词，每个词
// 不折行，所以长语言换行时也不会把一个数字拆到两行。读屏只读完整文本
// （sr-only），不逐位播报。

const COUNTDOWN_TICK = { duration: 0.16, ease: "linear" } as const;

export function RollingText({ text }: { text: string }) {
  const reduceMotion = useReducedMotion();
  if (reduceMotion) return <>{text}</>;

  const words = text.split(" ");
  return (
    <>
      <span className="sr-only">{text}</span>
      <span aria-hidden="true">
        {words.map((word, wordIndex) => (
          <span key={wordIndex}>
            {wordIndex > 0 && " "}
            <span className="inline-block whitespace-nowrap">
              {Array.from(word).map((char, charIndex) => (
                // 按位置固定槽位：同一位换字时，新旧两个字叠在同一格里交接。
                <span key={charIndex} className="inline-grid">
                  <AnimatePresence initial={false}>
                    <motion.span
                      key={char}
                      className="[grid-area:1/1]"
                      initial={{ y: "-0.3em", opacity: 0, filter: "blur(3px)" }}
                      animate={{ y: "0em", opacity: 1, filter: "blur(0px)" }}
                      exit={{ y: "0.3em", opacity: 0, filter: "blur(3px)" }}
                      transition={COUNTDOWN_TICK}
                    >
                      {char}
                    </motion.span>
                  </AnimatePresence>
                </span>
              ))}
            </span>
          </span>
        ))}
      </span>
    </>
  );
}
