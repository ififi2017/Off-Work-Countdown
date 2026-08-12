"use client";

import { useEffect, useCallback, useRef } from "react";
import confetti from "canvas-confetti";

interface ConfettiProps {
  /**
   * 每次自增都放一次。用计数而不是布尔：布尔一旦为 true 就停在 true，
   * 第二天再次下班时 React 看不到状态变化，effect 不会重跑。
   */
  trigger: number;
}

export function Confetti({ trigger }: ConfettiProps) {
  const cannonRef = useRef<ReturnType<typeof confetti.create> | null>(null);

  const fireConfetti = useCallback(() => {
    // canvas-confetti 的默认导出会启用 blob: Web Worker。Desktop 的 CSP
    // 没有开放 worker-src blob:，WKWebView 可能在画布转交给 Worker 之后才
    // 异步拒绝它，结果既没有 Worker 动画，也不会回退到主线程。庆祝一年只
    // 触发很少几次，明确走主线程更可靠，也不需要扩大 CSP 权限。
    const cannon =
      cannonRef.current ??
      confetti.create(undefined, { resize: true, useWorker: false });
    cannonRef.current = cannon;
    const duration = 5 * 1000;
    const animationEnd = Date.now() + duration;
    // 桌面端卡片是 relative z-10 且铺满整个窗口，zIndex: 0 会让整个撒花画布
    // 压在卡片底下、一点都看不到。必须高于卡片。
    const defaults = { startVelocity: 30, spread: 360, ticks: 60, zIndex: 60 };

    const randomInRange = (min: number, max: number) => {
      return Math.random() * (max - min) + min;
    };

    const launch = () => {
      const timeLeft = animationEnd - Date.now();

      if (timeLeft <= 0) {
        return false;
      }

      const particleCount = 50 * (timeLeft / duration);
      void cannon({
        ...defaults,
        particleCount,
        origin: { x: randomInRange(0.1, 0.3), y: Math.random() - 0.2 },
      });
      void cannon({
        ...defaults,
        particleCount,
        origin: { x: randomInRange(0.7, 0.9), y: Math.random() - 0.2 },
      });
      return true;
    };

    // 到点的第一帧就要有反馈，不能先空等 250ms。
    launch();
    const interval = window.setInterval(() => {
      if (!launch()) window.clearInterval(interval);
    }, 250);
    return interval;
  }, []);

  useEffect(() => {
    if (trigger > 0) {
      const interval = fireConfetti();
      return () => window.clearInterval(interval);
    }
    return undefined;
  }, [trigger, fireConfetti]);

  useEffect(
    () => () => {
      cannonRef.current?.reset();
    },
    []
  );

  return null;
}
