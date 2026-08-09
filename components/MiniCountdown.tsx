"use client";

import { useEffect, useState } from "react";
import { Pin, PinOff } from "lucide-react";
import { CountdownDisplay } from "./CountdownDisplay";
import {
  getDesktopCountdownView,
  getMiniWindowSettings,
  readDesktopCountdownState,
  setMiniAlwaysOnTop,
  subscribeToDesktopCountdown,
  type DesktopCountdownState,
} from "@/lib/desktop-state";

export function MiniCountdown() {
  const [state, setState] = useState<DesktopCountdownState | null>(null);
  const [nowMs, setNowMs] = useState(0);
  const [isWindows, setIsWindows] = useState(false);
  const [alwaysOnTop, setAlwaysOnTop] = useState(true);

  useEffect(() => {
    let unsubscribe = () => {};
    let cancelled = false;

    const initialize = async () => {
      const [initialState, settings] = await Promise.all([
        readDesktopCountdownState(),
        getMiniWindowSettings(),
      ]);
      if (cancelled) return;
      setState(initialState);
      setNowMs(Date.now());
      setIsWindows(settings.platform === "windows");
      setAlwaysOnTop(settings.alwaysOnTop);
      const nextUnsubscribe = await subscribeToDesktopCountdown(setState);
      if (cancelled) {
        nextUnsubscribe();
      } else {
        unsubscribe = nextUnsubscribe;
      }
    };

    void initialize().catch(() => {
      // IPC/Store 暂时不可用时保留空闲态；窗口本身仍可被关闭或拖动。
    });
    const timer = window.setInterval(() => setNowMs(Date.now()), 1000);
    return () => {
      cancelled = true;
      window.clearInterval(timer);
      unsubscribe();
    };
  }, []);

  const view = getDesktopCountdownView(state, nowMs);

  const toggleAlwaysOnTop = async () => {
    const next = !alwaysOnTop;
    setAlwaysOnTop(next);
    try {
      await setMiniAlwaysOnTop(next);
    } catch {
      setAlwaysOnTop(!next);
    }
  };

  return (
    <main
      data-tauri-drag-region="deep"
      className="h-screen w-screen overflow-hidden bg-zinc-950"
    >
      <section
        data-tauri-drag-region="deep"
        className="relative flex h-full cursor-grab flex-col justify-center overflow-hidden bg-zinc-950 px-5 pb-3 pt-4 text-white active:cursor-grabbing"
      >
        <div
          data-tauri-drag-region="deep"
          className="absolute inset-x-0 top-0 h-8"
        />
        {isWindows && (
          <button
            data-tauri-drag-region="false"
            type="button"
            onClick={toggleAlwaysOnTop}
            aria-pressed={alwaysOnTop}
            aria-label={
              alwaysOnTop ? "Disable always on top" : "Enable always on top"
            }
            title={
              alwaysOnTop ? "Disable always on top" : "Enable always on top"
            }
            className="absolute end-2 top-1.5 z-10 rounded-md p-1 text-zinc-400 transition-colors hover:bg-white/10 hover:text-white"
          >
            {alwaysOnTop ? <Pin size={13} /> : <PinOff size={13} />}
          </button>
        )}
        <CountdownDisplay
          timeLeft={view.time}
          progress={view.progress}
          compact
        />
        {view.earned !== null && (
          <p className="mt-1 truncate text-center text-xs font-medium text-amber-300">
            {view.earned.toFixed(2)}
          </p>
        )}
      </section>
    </main>
  );
}
