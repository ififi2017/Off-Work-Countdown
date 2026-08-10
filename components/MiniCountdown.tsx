"use client";

import { useEffect, useState } from "react";
import { Clock3, Pin, PinOff, X } from "lucide-react";
import { useTranslation } from "react-i18next";
import {
  getDesktopCountdownView,
  getMiniWindowSettings,
  hideDesktopMiniTimer,
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
  const progress = Math.min(100, Math.max(0, view.progress));

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

  const hideMiniTimer = async () => {
    try {
      await hideDesktopMiniTimer();
    } catch {
      // 隐藏失败不影响计时；用户仍可通过托盘菜单切换窗口。
    }
  };

  return (
    <main
      data-tauri-drag-region="deep"
      className="h-screen w-screen overflow-hidden bg-[#ececee] text-zinc-950 dark:bg-[#242426] dark:text-white"
    >
      <section
        data-tauri-drag-region="deep"
        className="relative flex h-full cursor-grab flex-col overflow-hidden border border-black/10 bg-gradient-to-b from-white/80 to-zinc-200/80 px-3 pb-1.5 pt-5 shadow-[inset_0_1px_0_rgba(255,255,255,0.7)] active:cursor-grabbing dark:border-white/10 dark:from-zinc-700/90 dark:to-zinc-900/95 dark:shadow-[inset_0_1px_0_rgba(255,255,255,0.08)]"
      >
        {isWindows && (
          <div
            data-tauri-drag-region="false"
            className="absolute end-1 top-1 z-10 flex items-center gap-0.5"
          >
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
              className="rounded-md p-1 text-zinc-500 transition-colors hover:bg-black/5 hover:text-zinc-950 dark:text-zinc-400 dark:hover:bg-white/10 dark:hover:text-white"
            >
              {alwaysOnTop ? <Pin size={11} /> : <PinOff size={11} />}
            </button>
            <button
              data-tauri-drag-region="false"
              type="button"
              onClick={hideMiniTimer}
              aria-label={t("hideMiniTimer")}
              title={t("hideMiniTimer")}
              className="rounded-md p-1 text-zinc-500 transition-colors hover:bg-red-500/10 hover:text-red-600 dark:text-zinc-400 dark:hover:bg-red-400/15 dark:hover:text-red-300"
            >
              <X size={12} />
            </button>
          </div>
        )}

        <div
          data-tauri-drag-region="deep"
          className="flex min-w-0 items-center gap-2.5"
        >
          <div
            data-tauri-drag-region="deep"
            className="flex h-7 w-7 shrink-0 items-center justify-center rounded-[9px] bg-gradient-to-br from-orange-400 to-orange-600 text-white shadow-sm shadow-orange-950/15"
          >
            <Clock3 size={15} strokeWidth={2.4} />
          </div>

          {hasCountdown ? (
            <p className="min-w-0 flex-1 whitespace-nowrap text-[22px] font-semibold leading-none tracking-[-0.035em] tabular-nums">
              {view.time}
            </p>
          ) : (
            <p className="min-w-0 flex-1 truncate text-xs font-semibold tracking-tight text-zinc-700 dark:text-zinc-200">
              {t("countdownNotStarted")}
            </p>
          )}

          {hasCountdown && (
            <span className="shrink-0 rounded-md bg-black/[0.06] px-1.5 py-1 text-[10px] font-semibold tabular-nums text-zinc-600 dark:bg-white/10 dark:text-zinc-300">
              {view.earned !== null
                ? view.earned.toFixed(2)
                : `${Math.floor(progress)}%`}
            </span>
          )}
        </div>

        <div className="mt-1.5 h-1 overflow-hidden rounded-full bg-black/10 dark:bg-white/15">
          <div
            className="h-full rounded-full bg-gradient-to-r from-orange-400 to-orange-600 transition-[width] duration-500 ease-out"
            style={{ width: `${hasCountdown ? progress : 0}%` }}
          />
        </div>
      </section>
    </main>
  );
}
