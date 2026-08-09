"use client";

import { useEffect, useState } from "react";
import { Pin, PinOff } from "lucide-react";
import { useTranslation } from "react-i18next";
import { CountdownDisplay } from "./CountdownDisplay";
import { ProgressBar } from "./ProgressBar";
import {
  getDesktopCountdownView,
  getMiniWindowSettings,
  readDesktopCountdownState,
  setMiniAlwaysOnTop,
  subscribeToDesktopCountdown,
  type DesktopCountdownState,
} from "@/lib/desktop-state";

export function MiniCountdown() {
  const { t, i18n } = useTranslation();
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
  const hasCountdown = Boolean(
    state?.running && state.endAtMs > state.startAtMs
  );

  useEffect(() => {
    if (state?.lang && i18n.language !== state.lang) {
      void i18n.changeLanguage(state.lang);
    }
  }, [i18n, state?.lang]);

  // 迷你窗是独立 WebView，主窗口改主题时不会自动重渲染。同步本地主题与
  // 系统明暗变化，保证它不会永远停在深色样式。
  useEffect(() => {
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const syncTheme = () => {
      let savedTheme = "auto";
      try {
        savedTheme = localStorage.getItem("theme") || "auto";
      } catch {
        // 保持跟随系统。
      }
      const isDark =
        savedTheme === "dark" ||
        savedTheme === "cyberpunk" ||
        (savedTheme === "auto" && media.matches);
      document.documentElement.classList.toggle("dark", isDark);
    };

    syncTheme();
    window.addEventListener("storage", syncTheme);
    media.addEventListener("change", syncTheme);
    return () => {
      window.removeEventListener("storage", syncTheme);
      media.removeEventListener("change", syncTheme);
    };
  }, []);

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
      className="h-screen w-screen overflow-hidden bg-zinc-100 dark:bg-zinc-950"
    >
      <section
        data-tauri-drag-region="deep"
        className="relative flex h-full cursor-grab flex-col justify-center overflow-hidden border border-black/10 bg-gradient-to-b from-white to-zinc-100 px-5 pb-3 pt-4 text-zinc-950 shadow-inner active:cursor-grabbing dark:border-white/10 dark:from-zinc-800 dark:to-zinc-950 dark:text-white"
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
              alwaysOnTop ? t("disableAlwaysOnTop") : t("enableAlwaysOnTop")
            }
            title={
              alwaysOnTop ? t("disableAlwaysOnTop") : t("enableAlwaysOnTop")
            }
            className="absolute end-2 top-1.5 z-10 rounded-md p-1 text-zinc-500 transition-colors hover:bg-black/5 hover:text-zinc-950 dark:text-zinc-400 dark:hover:bg-white/10 dark:hover:text-white"
          >
            {alwaysOnTop ? <Pin size={13} /> : <PinOff size={13} />}
          </button>
        )}
        {hasCountdown ? (
          <CountdownDisplay
            timeLeft={view.time}
            progress={view.progress}
            compact
          />
        ) : (
          <div className="space-y-3">
            <p className="truncate text-center text-sm font-semibold tracking-tight">
              {t("countdownNotStarted")}
            </p>
            <ProgressBar progress={0} compact />
          </div>
        )}
        {view.earned !== null && (
          <p className="mt-1 truncate text-center text-xs font-medium text-amber-600 dark:text-amber-300">
            {view.earned.toFixed(2)}
          </p>
        )}
      </section>
    </main>
  );
}
