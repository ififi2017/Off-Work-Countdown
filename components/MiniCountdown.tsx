"use client";

import { useEffect, useRef, useState } from "react";
import { AppWindow, Palette, Pin, PinOff, Volume2, VolumeX, X, Eye, EyeOff } from "lucide-react";
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
  toggleDesktopMiniSkin,
  toggleDesktopWoodfishSound,
  type DesktopCountdownState,
} from "@/lib/desktop-state";
import { isValidShiftTimeline } from "@/lib/countdown";

/** 本地日历日。用 UTC 会让跨天时点在时区偏移处对不上用户的「今天」。 */
function localDateKey(date = new Date()) {
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${date.getFullYear()}-${month}-${day}`;
}

/**
 * 木鱼字形。整块是单条路径，开缝靠路径自身绕向挖成负空间——所以缝里透出的
 * 是面板真实底色，换皮肤或明暗切换都不会穿帮。早先自绘的版本把缝填成写死的
 * 背景色，那样一改底色就露馅。
 *
 * 素材由项目所有者提供（iconfont 导出），沿用其原始轮廓，仅去掉编辑器留下的
 * 属性并把填充改为 currentColor 以继承主题色。
 */
function WoodfishIllustration() {
  return (
    <svg
      aria-hidden="true"
      viewBox="0 0 1365 1024"
      className="h-[33px] w-[44px]"
      fill="currentColor"
    >
      <path d="M1.450653 780.39695c-10.175905 64.255398 36.031662 101.161718 59.626108 112.361614 23.594445 11.178562 63.274073 0 78.825927 0 116.542907 11.178562 366.759228 131.220103 678.606972 131.220103 0 0 504.635269 7.445264 543.31224-360.487287 9.19458-95.529771 4.885288-277.458732-71.039334-286.162651-63.956734-8.426588-102.121709 4.074628-183.315615 20.565141-53.908828 10.922564-189.011561 29.973052-212.926004 44.970245-260.989553 118.718887-403.324219 204.371417-442.299853 217.128631-29.439724 0-54.975485-7.359931-62.100752-69.972677 0-25.706426 98.089747-87.039184 140.137353-96.959091C682.660267 452.869354 796.365867 435.333519 809.720409 435.333519c19.263819 0 441.489194-101.588381 454.438406-111.188291 12.949212-9.59991 26.62375-18.986489 26.623751-52.543508 0-15.359856-33.813016-49.663534-72.319322-91.455142-45.674238-49.556869-99.94573-107.092329-140.606682-120.788201C1002.934597 20.958737 856.077308-10.912964 727.779844 3.572233 446.929143 35.273269 271.677453 342.662388 256.424263 363.995521c-64.852725 90.708483-116.542907 205.587406-143.678653 256.296264C86.548522 669.272659 11.71189 735.149375 1.450653 780.39695z" />
    </svg>
  );
}

export function MiniCountdown() {
  const { t, i18n } = useTranslation();
  const [state, setState] = useState<DesktopCountdownState | null>(null);
  const [nowMs, setNowMs] = useState(0);
  const [alwaysOnTop, setAlwaysOnTop] = useState(true);
  const [woodfishCount, setWoodfishCount] = useState(0);
  /** 每次敲击生成一个独立实例；连击时多个数字同时在飞，靠 id 各自卸载。 */
  const [knockFloaters, setKnockFloaters] = useState<
    { id: number; value: number }[]
  >([]);
  const [woodfishStruck, setWoodfishStruck] = useState(false);
  /** 静音状态下敲击：把声音按钮亮一下，比弹一行字更轻。 */
  const [mutedHintVisible, setMutedHintVisible] = useState(false);
  const [forceWoodfishPreview, setForceWoodfishPreview] = useState(false);
  const draggedRef = useRef(false);
  const audioContextRef = useRef<AudioContext | null>(null);
  const floaterIdRef = useRef(0);
  const glowTimerRef = useRef<number | null>(null);
  const mutedHintTimerRef = useRef<number | null>(null);
  const woodfishTappedThisSessionRef = useRef(false);

  useEffect(() => {
    setForceWoodfishPreview(
      new URLSearchParams(window.location.search).get("skin") === "woodfish"
    );
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

  useEffect(() => {
    try {
      const storedDay = localStorage.getItem("woodfishCountDate");
      setWoodfishCount(
        storedDay === localDateKey()
          ? Number(localStorage.getItem("woodfishCount")) || 0
          : 0
      );
    } catch {
      // 计数是纯本地彩蛋，存储不可用时仍可敲击。
    }
    return () => {
      if (glowTimerRef.current) window.clearTimeout(glowTimerRef.current);
      if (mutedHintTimerRef.current)
        window.clearTimeout(mutedHintTimerRef.current);
      void audioContextRef.current?.close();
    };
  }, []);

  const view = getDesktopCountdownView(state, nowMs);
  const hasCountdown = Boolean(state?.running && isValidShiftTimeline(state));
  const isBetweenShifts = view.phase === "between";
  const isOnBreak = view.phase === "break";
  const isActiveCountdown = hasCountdown && !isBetweenShifts && view.phase !== "done";
  // 班次之间也要显示读数列：进度停在 100%，说明「这一班确实做完了」。
  const showsReadout = isActiveCountdown || isBetweenShifts;
  const progress = Math.min(100, Math.max(0, view.progress));
  // 判据是「有没有薪资可显示」，不能用 view.earned —— 它在隐藏状态下就是
  // null，拿它当条件会把眼睛按钮一起藏掉，隐藏之后就再也没法恢复了。
  const canShowSalary = Boolean(
    isActiveCountdown && state?.showSalary && state.dailySalary !== null
  );
  // 隐藏状态来自共享的 store，不是本地 state —— 主窗口和 macOS 原生面板
  // 读写的是同一个 hideEarnings，三处必须一致。
  const revealSalary = canShowSalary && !state?.hideEarnings;

  const handleContentClick = () => {
    if (draggedRef.current) return;
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

  const playWoodfishSound = () => {
    const AudioContextClass = window.AudioContext;
    const context = audioContextRef.current ?? new AudioContextClass();
    audioContextRef.current = context;
    if (context.state === "suspended") void context.resume();

    // 木鱼不是带固定音高的电子“嘟”声。用一次极短的木质撞击噪声激发
    // 三个非整数倍的腔体共振，再叠一个很轻的二次回弹，得到干、脆、空心
    // 的打击感；全部实时合成，不引入授权不明的音频文件。
    const sampleRate = context.sampleRate;
    const duration = 0.15;
    const variation = (woodfishCount % 5) * 7;
    const makeStrike = (startAt: number, level: number) => {
      const buffer = context.createBuffer(
        1,
        Math.ceil(sampleRate * duration),
        sampleRate
      );
      const samples = buffer.getChannelData(0);
      for (let index = 0; index < samples.length; index += 1) {
        const seconds = index / sampleRate;
        const attack = Math.min(1, seconds / 0.0012);
        const decay = Math.exp(-seconds * 34);
        const cavity =
          Math.sin(2 * Math.PI * (560 + variation) * seconds) * 0.52 +
          Math.sin(2 * Math.PI * (873 + variation * 0.7) * seconds) * 0.27 +
          Math.sin(2 * Math.PI * (1327 + variation * 0.4) * seconds) * 0.12;
        const impactNoise = (Math.random() * 2 - 1) * Math.exp(-seconds * 95) * 0.32;
        samples[index] = (cavity + impactNoise) * attack * decay * level;
      }

      const source = context.createBufferSource();
      const highpass = context.createBiquadFilter();
      const lowpass = context.createBiquadFilter();
      const gain = context.createGain();
      highpass.type = "highpass";
      highpass.frequency.value = 180;
      lowpass.type = "lowpass";
      lowpass.frequency.value = 2600;
      lowpass.Q.value = 0.45;
      gain.gain.value = 0.42;
      source.buffer = buffer;
      source.connect(highpass).connect(lowpass).connect(gain).connect(context.destination);
      source.start(startAt);
    };

    const now = context.currentTime + 0.002;
    makeStrike(now, 1);
    makeStrike(now + 0.012, 0.22);
  };

  const knockWoodfish = () => {
    if (draggedRef.current) return;
    let firstTapSeen = woodfishTappedThisSessionRef.current;
    try {
      firstTapSeen =
        firstTapSeen ||
        localStorage.getItem("woodfishFirstTapSeen") === "true";
      if (!firstTapSeen) localStorage.setItem("woodfishFirstTapSeen", "true");
    } catch {
      // 无法保存时仍遵守本次会话首次静音。
    }
    woodfishTappedThisSessionRef.current = true;
    // 计数按自然日重置：跨过零点后第一次敲击从 1 重新开始，不需要重启应用。
    const today = localDateKey();
    let storedDay = today;
    try {
      storedDay = localStorage.getItem("woodfishCountDate") ?? today;
    } catch {
      // 读不到就当作今天，最坏情况是少清一次零。
    }
    const nextCount = storedDay === today ? woodfishCount + 1 : 1;
    setWoodfishCount(nextCount);
    try {
      localStorage.setItem("woodfishCount", String(nextCount));
      localStorage.setItem("woodfishCountDate", today);
    } catch {
      // 本地计数失败不影响敲击反馈。
    }

    const floaterId = (floaterIdRef.current += 1);
    setKnockFloaters((current) => [
      ...current,
      { id: floaterId, value: nextCount },
    ]);
    window.setTimeout(
      () =>
        setKnockFloaters((current) =>
          current.filter((floater) => floater.id !== floaterId)
        ),
      900
    );

    setWoodfishStruck(true);
    if (glowTimerRef.current) window.clearTimeout(glowTimerRef.current);
    glowTimerRef.current = window.setTimeout(
      () => setWoodfishStruck(false),
      180
    );
    // 静音时不弹文字，而是把工具条上的声音按钮亮一下再淡出——用户一眼能
    // 看出「哪里可以开声音」，比一行提示语更省地方也更少打扰。
    if (!firstTapSeen || !state?.woodfishSoundEnabled) {
      setMutedHintVisible(true);
      if (mutedHintTimerRef.current)
        window.clearTimeout(mutedHintTimerRef.current);
      mutedHintTimerRef.current = window.setTimeout(
        () => setMutedHintVisible(false),
        1400
      );
      return;
    }
    playWoodfishSound();
  };

  // 时间是这个挂件的主角，能多大就多大。置顶／关闭按钮悬浮在右上角、
  // 与左侧的时间不在同一列，不需要为它们让出高度。唯一的约束是右侧
  // 金额栏留下的宽度——八位数的跨十小时班次要小一号才不会被截断。
  const timeSizeClass =
    view.time.length >= 8 ? "text-[23px]" : "text-[27px]";
  // 木鱼皮肤下窗口宽度不变，横向空间要分给字形：228 内容宽减去内边距、
  // 木鱼与读数列后只剩约 76pt；午休标签和金额同时出现时再缩一级，避免
  // 时间与金额贴在一起。
  const woodfishTimeSizeClass = revealSalary
    ? isOnBreak
      ? "text-[15px]"
      : "text-[17px]"
    : view.time.length >= 8
      ? "text-[18px]"
      : "text-[21px]";

  // 两个皮肤共用同一块读数：金额在上、百分比在下。薪资显隐属于窗口操作，
  // 和置顶、关闭统一放进顶部工具栏，避免它挤压不同皮肤的读数列。
  const readoutColumn = showsReadout ? (
            <span
              className="flex shrink-0 flex-col items-end leading-none"
            >
              {/* 金额是主信息、百分比是次要读数（进度条已经表达过一遍），
                  与 macOS 原生面板保持同一套层级。 */}
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
  ) : null;


  return (
    <main
      data-tauri-drag-region="deep"
      className="h-screen w-screen select-none bg-transparent p-1.5 text-zinc-950 dark:text-white"
    >
      <section
        data-tauri-drag-region="deep"
        className="group relative flex h-full cursor-grab flex-col justify-center overflow-hidden rounded-[16px] border border-black/[0.08] bg-[#f6f6f7] shadow-[0_1px_2px_rgba(0,0,0,0.10),0_6px_16px_-4px_rgba(0,0,0,0.22),inset_0_1px_0_rgba(255,255,255,0.85)] active:cursor-grabbing dark:border-white/[0.10] dark:bg-[#232326] dark:shadow-[0_1px_2px_rgba(0,0,0,0.5),0_6px_16px_-4px_rgba(0,0,0,0.6),inset_0_1px_0_rgba(255,255,255,0.07)]"
      >
        {/* 常驻的窗口工具按钮会一直和数字抢注意力，而这是个整天挂在屏幕角落
            的挂件。改成指针移入或键盘聚焦时才浮出。

            这里必须用 :focus-visible 而不是 focus-within —— WebView 打开时会
            把焦点交给文档里第一个可聚焦元素，恰好就是下面的置顶按钮，用
            focus-within 会让它们一直亮着。 */}
        {(
          <div
            data-tauri-drag-region="false"
            className={`absolute end-1 top-1 z-10 flex items-center gap-0.5 transition-opacity duration-150 group-hover:opacity-100 has-[:focus-visible]:opacity-100 ${
              mutedHintVisible ? "opacity-100" : "opacity-0"
            }`}
          >
            {/* 声音是木鱼最常用的即时开关，固定放在整排最左侧。 */}
            {(state?.miniSkin === "woodfish" || forceWoodfishPreview) && (
              <button
                data-tauri-drag-region="false"
                type="button"
                onClick={() => {
                  void toggleDesktopWoodfishSound().catch(() => {
                    // 切换失败时保持原状，下一次 store 变更会校正。
                  });
                }}
                aria-pressed={Boolean(state?.woodfishSoundEnabled)}
                aria-label={
                  state?.woodfishSoundEnabled
                    ? t("woodfishSoundOff")
                    : t("woodfishSoundOn")
                }
                title={
                  state?.woodfishSoundEnabled
                    ? t("woodfishSoundOff")
                    : t("woodfishSoundOn")
                }
                className={`rounded-md p-1 transition-all duration-200 hover:bg-black/5 dark:hover:bg-white/10 ${
                  mutedHintVisible
                    ? "scale-110 bg-amber-400/20 text-amber-500 opacity-100 dark:text-amber-300"
                    : "text-zinc-500 hover:text-zinc-950 dark:text-zinc-400 dark:hover:text-white"
                }`}
              >
                {state?.woodfishSoundEnabled ? (
                  <Volume2 size={11} />
                ) : (
                  <VolumeX size={11} />
                )}
              </button>
            )}
            <button
              data-tauri-drag-region="false"
              type="button"
              onClick={() => {
                void toggleDesktopMiniSkin().catch(() => {
                  // 切换失败时保持原状，下一次 store 变更会校正。
                });
              }}
              aria-label={t("switchMiniSkin")}
              title={t("switchMiniSkin")}
              className="rounded-md p-1 text-zinc-500 transition-colors hover:bg-black/5 hover:text-zinc-950 dark:text-zinc-400 dark:hover:bg-white/10 dark:hover:text-white"
            >
              <Palette size={11} />
            </button>
            <button
              data-tauri-drag-region="false"
              type="button"
              onClick={() => {
                void showDesktopMainWindow().catch(() => {
                  // 唤起失败不影响挂件继续计时。
                });
              }}
              aria-label={t("trayShowApp")}
              title={t("trayShowApp")}
              className="rounded-md p-1 text-zinc-500 transition-colors hover:bg-black/5 hover:text-zinc-950 dark:text-zinc-400 dark:hover:bg-white/10 dark:hover:text-white"
            >
              <AppWindow size={11} />
            </button>
            {canShowSalary && (
              <button
                data-tauri-drag-region="false"
                type="button"
                onClick={() => {
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
                {revealSalary ? <EyeOff size={11} /> : <Eye size={11} />}
              </button>
            )}
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

        {state?.miniSkin === "woodfish" || forceWoodfishPreview ? (
          <div
            data-tauri-drag-region="deep"
            onMouseDown={() => {
              draggedRef.current = false;
            }}
            onMouseMove={() => {
              draggedRef.current = true;
            }}
            // 木鱼皮肤不接管整面板点击：敲木鱼和唤起主窗口会抢同一个手势。
            // 唤起改由右上角的显式按钮承担（标准皮肤无此冲突，保留点击）。
            className="flex min-w-0 translate-y-1.5 items-center gap-2 px-4"
          >
            <span className="relative -translate-y-[7px] shrink-0">
              <button
                data-tauri-drag-region="false"
                type="button"
                onClick={(event) => {
                  event.stopPropagation();
                  knockWoodfish();
                }}
                aria-label={t("knockWoodfish")}
                className={`flex h-[44px] w-[54px] items-center justify-center rounded-lg text-[#b0763f] transition-transform duration-75 active:scale-[0.92] dark:text-[#d69b5c] ${
                  woodfishStruck ? "woodfish-struck" : "woodfish-idle"
                }`}
              >
                <WoodfishIllustration />
              </button>
              <span
                aria-live="polite"
                aria-label={t("knockCount", { count: woodfishCount })}
                className="pointer-events-none absolute inset-x-0 top-[10%] h-0"
              >
                {knockFloaters.map((floater) => (
                  <span
                    key={floater.id}
                    className="woodfish-floater absolute start-1/2 whitespace-nowrap text-[10px] font-bold text-amber-500 dark:text-amber-300"
                  >
                    {t("meritGain")}
                  </span>
                ))}
              </span>
            </span>
            {hasCountdown ? (
              <p
                className={`flex min-w-0 flex-1 items-baseline ${
                  isOnBreak && revealSalary ? "gap-0.5" : "gap-1"
                }`}
              >
                {isOnBreak && (
                  <span
                    className={`shrink-0 font-semibold text-amber-600 dark:text-amber-400 ${
                      revealSalary ? "text-[9px]" : "text-[10px]"
                    }`}
                  >
                    {t("lunchInProgress")}
                  </span>
                )}
                <span
                  className={`whitespace-nowrap font-semibold leading-none tracking-[-0.035em] tabular-nums ${woodfishTimeSizeClass}`}
                >
                  {view.time}
                </span>
              </p>
            ) : (
              <p className="min-w-0 flex-1 truncate text-center text-[13px] font-semibold tracking-tight text-zinc-700 dark:text-zinc-200">
                {t("countdownNotStarted")}
              </p>
            )}
            {readoutColumn}
          </div>
        ) : (
        <div
          data-tauri-drag-region="deep"
          onMouseDown={() => {
            draggedRef.current = false;
          }}
          onMouseMove={() => {
            draggedRef.current = true;
          }}
          onClick={handleContentClick}
          className="flex min-w-0 translate-y-1.5 items-center gap-3 px-4"
        >
          {isBetweenShifts ? (
            <p className="flex min-w-0 flex-1 flex-col justify-center leading-tight">
              <span className="truncate text-[10px] font-medium text-zinc-500 dark:text-zinc-400">
                {t("nextShiftLabelShort")}
              </span>
              <span className="truncate text-[19px] font-semibold tabular-nums tracking-[-0.035em]">
                {view.time}
              </span>
            </p>
          ) : hasCountdown ? (
            <p className="flex min-w-0 flex-1 items-baseline gap-1.5">
              {isOnBreak && (
                <span className="shrink-0 text-[11px] font-semibold text-amber-600 dark:text-amber-400">
                  {t("lunchInProgress")}
                </span>
              )}
              <span
                className={`whitespace-nowrap font-semibold leading-none tracking-[-0.035em] tabular-nums ${
                  isOnBreak ? "text-[20px]" : timeSizeClass
                }`}
              >
                {view.time}
              </span>
            </p>
          ) : (
            <p className="min-w-0 flex-1 truncate text-center text-[13px] font-semibold tracking-tight text-zinc-700 dark:text-zinc-200">
              {t("countdownNotStarted")}
            </p>
          )}

          {readoutColumn}
        </div>
        )}

        <div className="absolute inset-x-4 bottom-2.5 h-[3px] overflow-hidden rounded-full bg-black/10 dark:bg-white/15">
          <div
            className="h-full rounded-full bg-orange-500 transition-[width] duration-500 ease-out"
            // 班次之间要保持满格：这一班确实做完了，清零会读成「重新开始」。
              // 只有完全没有倒计时（空闲态）才归零。
              style={{ width: `${showsReadout ? progress : 0}%` }}
          />
        </div>
      </section>
    </main>
  );
}
