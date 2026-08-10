"use client";

import { useEffect, useRef, useState } from "react";
import { Pin, PinOff, X, Eye, EyeOff } from "lucide-react";
import { useTranslation } from "react-i18next";
import {
  getDesktopCountdownView,
  getMiniWindowSettings,
  hideDesktopMiniTimer,
  readDesktopCountdownState,
  setMiniAlwaysOnTop,
  showDesktopMainWindow,
  subscribeToDesktopCountdown,
  toggleDesktopSalaryVisibility,
  type DesktopCountdownState,
} from "@/lib/desktop-state";

export function MiniCountdown() {
  const { t, i18n } = useTranslation();
  const [state, setState] = useState<DesktopCountdownState | null>(null);
  const [nowMs, setNowMs] = useState(0);
  const [isWindows, setIsWindows] = useState(false);
  const [alwaysOnTop, setAlwaysOnTop] = useState(true);
  const draggedRef = useRef(false);

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
  // 判据是「有没有薪资可显示」，不能用 view.earned —— 它在隐藏状态下就是
  // null，拿它当条件会把眼睛按钮一起藏掉，隐藏之后就再也没法恢复了。
  const canShowSalary = Boolean(
    hasCountdown && state?.showSalary && state.dailySalary !== null
  );
  // 隐藏状态来自共享的 store，不是本地 state —— 主窗口和 macOS 原生面板
  // 读写的是同一个 hideEarnings，三处必须一致。
  const revealSalary = canShowSalary && !state?.hideEarnings;

  const handleContentClick = () => {
    if (draggedRef.current) return;
    if (!isWindows) return;
    void showDesktopMainWindow().catch(() => {
      // 点击迷你窗唤起主窗口失败不影响继续使用。
    });
  };

  useEffect(() => {
    if (state?.lang && i18n.language !== state.lang) {
      void i18n.changeLanguage(state.lang);
    }
  }, [i18n, state?.lang]);

  // 这是一个透明窗口：圆角之外必须真的透出桌面。globals.css 给 body 设了
  // 不透明底色（`background: hsl(var(--background))`），不覆盖掉的话整块
  // 窗口会被填满，圆角就只是画在一个方块上。
  useEffect(() => {
    document.documentElement.style.background = "transparent";
    document.body.style.background = "transparent";
  }, []);

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

  // 时间是这个挂件的主角，能多大就多大。置顶／关闭按钮悬浮在右上角、
  // 与左侧的时间不在同一列，不需要为它们让出高度。唯一的约束是右侧
  // 金额栏留下的宽度——八位数的跨十小时班次要小一号才不会被截断。
  const timeSizeClass =
    view.time.length >= 8 ? "text-[23px]" : "text-[27px]";

  return (
    <main
      data-tauri-drag-region="deep"
      className="h-screen w-screen select-none bg-transparent p-1.5 text-zinc-950 dark:text-white"
    >
      <section
        data-tauri-drag-region="deep"
        className="group relative flex h-full cursor-grab flex-col justify-center overflow-hidden rounded-[16px] border border-black/[0.08] bg-[#f6f6f7] shadow-[0_1px_2px_rgba(0,0,0,0.10),0_6px_16px_-4px_rgba(0,0,0,0.22),inset_0_1px_0_rgba(255,255,255,0.85)] active:cursor-grabbing dark:border-white/[0.10] dark:bg-[#232326] dark:shadow-[0_1px_2px_rgba(0,0,0,0.5),0_6px_16px_-4px_rgba(0,0,0,0.6),inset_0_1px_0_rgba(255,255,255,0.07)]"
      >
        {/* 常驻的置顶／关闭按钮会一直和数字抢注意力，而这是个整天挂在屏幕角落
            的挂件。改成指针移入或键盘聚焦时才浮出。

            这里必须用 :focus-visible 而不是 focus-within —— WebView 打开时会
            把焦点交给文档里第一个可聚焦元素，恰好就是下面的置顶按钮，用
            focus-within 会让它们一直亮着。 */}
        {isWindows && (
          <div
            data-tauri-drag-region="false"
            className="absolute end-1 top-1 z-10 flex items-center gap-0.5 opacity-0 transition-opacity duration-150 group-hover:opacity-100 has-[:focus-visible]:opacity-100"
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
          onMouseDown={() => {
            draggedRef.current = false;
          }}
          onMouseMove={() => {
            draggedRef.current = true;
          }}
          onClick={handleContentClick}
          className="flex min-w-0 items-center gap-3 px-4"
        >
          {hasCountdown ? (
            <p
              className={`min-w-0 flex-1 whitespace-nowrap font-semibold leading-none tracking-[-0.035em] tabular-nums ${timeSizeClass}`}
            >
              {view.time}
            </p>
          ) : (
            <p className="min-w-0 flex-1 truncate text-center text-[13px] font-semibold tracking-tight text-zinc-700 dark:text-zinc-200">
              {t("countdownNotStarted")}
            </p>
          )}

          {hasCountdown && (
            <span
              data-tauri-drag-region="false"
              className="flex shrink-0 items-center gap-2"
            >
              {/* 金额是主信息、百分比是次要读数（进度条已经表达过一遍），
                  与 macOS 原生面板保持同一套层级。 */}
              <span className="flex flex-col items-end leading-none">
                {revealSalary && (
                  <span className="text-[13px] font-semibold tabular-nums text-zinc-900 dark:text-white">
                    {(view.earned ?? 0).toFixed(2)}
                  </span>
                )}
                <span
                  className={`text-[10px] font-medium tabular-nums text-zinc-500 dark:text-zinc-400 ${
                    revealSalary ? "mt-0.5" : ""
                  }`}
                >
                  {Math.floor(progress)}%
                </span>
              </span>

              {canShowSalary && (
                <button
                  data-tauri-drag-region="false"
                  type="button"
                  onClick={(e) => {
                    e.stopPropagation();
                    void toggleDesktopSalaryVisibility().catch(() => {
                      // 切换失败时保持原状，下一次 store 变更仍会校正显示。
                    });
                  }}
                  aria-pressed={!revealSalary}
                  aria-label={
                    revealSalary ? t("hideEarnings") : t("showEarnings")
                  }
                  title={revealSalary ? t("hideEarnings") : t("showEarnings")}
                  className="rounded-md p-1 text-zinc-500 transition-colors hover:bg-black/5 hover:text-zinc-950 dark:text-zinc-400 dark:hover:bg-white/10 dark:hover:text-white"
                >
                  {/* 图标表示「点下去会发生什么」，与主窗口 PeriodSummary 一致。 */}
                  {revealSalary ? <EyeOff size={12} /> : <Eye size={12} />}
                </button>
              )}
            </span>
          )}
        </div>

        <div className="absolute inset-x-4 bottom-2.5 h-[3px] overflow-hidden rounded-full bg-black/10 dark:bg-white/15">
          <div
            className="h-full rounded-full bg-orange-500 transition-[width] duration-500 ease-out"
            style={{ width: `${hasCountdown ? progress : 0}%` }}
          />
        </div>
      </section>
    </main>
  );
}
