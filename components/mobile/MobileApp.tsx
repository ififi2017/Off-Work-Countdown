"use client";

import { useCallback, useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { Monitor, Moon, Sun, Sunset, Zap } from "lucide-react";
import { getTextDirection } from "@/i18n-config";
import { mobileSelectedTabStorageKey } from "@/lib/mobile-navigation";
import { clockAt, durationParts } from "@/lib/mobile/format";
import {
  ONBOARDING_STORAGE_KEY,
  useIosApp,
  type NotificationMode,
} from "@/lib/mobile/use-ios-app";
import type { Theme } from "@/components/ThemeToggle";
import { IosButton, IosGroup, IosSheet } from "./ios-kit";
import { IosTimeField } from "./IosTimeField";
import {
  IosSidebar,
  IosSidebarButton,
  IosTabBar,
  IosTabRail,
  type TabId,
} from "./MobileNav";
import { MobileOnboarding } from "./MobileOnboarding";
import { MobileSettingsScreen } from "./MobileSettingsScreen";
import { MobileShareSheet } from "./MobileShareSheet";
import { MobileSubpage } from "./MobileSubpages";
import { MobileTimerScreen } from "./MobileTimerScreen";
import { MobileWideTimer } from "./MobileWideTimer";
import { useLayoutMode } from "./use-layout-mode";
import type { SubpageId } from "./subpage-ids";

const THEME_CYCLE: Theme[] = ["auto", "light", "dark"];
const THEME_ICONS = {
  light: Sun,
  dark: Moon,
  auto: Monitor,
  cyberpunk: Zap,
  sunset: Sunset,
} as const;

/**
 * The iPhone and iPad app.
 *
 * It deliberately does not mount the Web/Desktop `OffWorkCountdown` component:
 * an iOS grouped list is a different control from a frosted Web card, and the
 * first mobile build read as a website in a shell precisely because it reused
 * one for the other. The rules are shared instead — `lib/countdown.ts` via
 * `useIosApp` — and only the presentation is native to this platform.
 */
export function MobileApp({ lang }: { lang: string }) {
  const { t } = useTranslation();
  const app = useIosApp();
  const layout = useLayoutMode();
  const [tab, setTab] = useState<TabId>("timer");
  const [stack, setStack] = useState<SubpageId[]>([]);
  const [sheet, setSheet] = useState<"share" | "overtime" | null>(null);
  const [overtimeEnd, setOvertimeEnd] = useState("19:00");
  const [onboarding, setOnboarding] = useState<boolean | null>(null);
  const [sidebarVisible, setSidebarVisible] = useState(true);
  const isRtl = getTextDirection(lang) === "rtl";

  useEffect(() => {
    let seen = true;
    try {
      seen = localStorage.getItem(ONBOARDING_STORAGE_KEY) === "true";
    } catch {
      // Without storage the app opens straight into the shift, which is the
      // better failure: a first run repeated every launch would be worse.
    }
    setOnboarding(!seen);
  }, []);

  // The iOS shell owns the real UITabBar so iOS 26 renders the system Liquid
  // Glass material. Browser previews use the same event contract and draw the
  // HTML equivalent instead.
  useEffect(() => {
    const nativeWindow = window as Window & {
      Capacitor?: { getPlatform?: () => string };
    };
    // Next hydrates <html> and can replace classes injected at document start,
    // so the native shell is marked again from the hydrated app — otherwise the
    // browser-only tab bar reappears underneath UIKit after a locale change.
    if (nativeWindow.Capacitor?.getPlatform?.() === "ios") {
      document.documentElement.classList.add("native-ios-tabbar");
    }
    try {
      if (sessionStorage.getItem(mobileSelectedTabStorageKey) === "settings") {
        setTab("settings");
      }
      sessionStorage.removeItem(mobileSelectedTabStorageKey);
    } catch {
      // A language switch still succeeds when session storage is unavailable.
    }

    const handleNativeTab = (event: Event) => {
      const next = (event as CustomEvent<{ tab?: string }>).detail?.tab;
      if (next === "timer" || next === "settings") {
        setTab(next);
        setStack([]);
      }
    };
    window.addEventListener("owc:native-tab", handleNativeTab);
    return () => window.removeEventListener("owc:native-tab", handleNativeTab);
  }, []);

  useEffect(() => {
    const nativeWindow = window as Window & {
      webkit?: {
        messageHandlers?: {
          owcMobileTabs?: { postMessage: (payload: unknown) => void };
        };
      };
    };
    nativeWindow.webkit?.messageHandlers?.owcMobileTabs?.postMessage({
      timer: t("timerTab"),
      settings: t("settings"),
      selected: tab,
      direction: isRtl ? "rtl" : "ltr",
      appearance:
        app.settings.theme === "dark" || app.settings.theme === "cyberpunk"
          ? "dark"
          : app.settings.theme === "auto"
            ? "system"
            : "light",
    });
  }, [app.settings.theme, isRtl, t, tab]);

  const openSubpage = useCallback((page: SubpageId) => {
    setStack((current) => [...current, page]);
  }, []);
  const popSubpage = useCallback(() => {
    setStack((current) => current.slice(0, -1));
  }, []);

  const selectTab = useCallback((next: TabId) => {
    setTab(next);
    setStack([]);
  }, []);

  const openOvertime = useCallback(() => {
    setOvertimeEnd(app.suggestedOvertimeEnd());
    setSheet("overtime");
  }, [app]);

  const finishOnboarding = (notificationMode: NotificationMode | null) => {
    if (notificationMode) app.update({ notificationMode });
    try {
      localStorage.setItem(ONBOARDING_STORAGE_KEY, "true");
    } catch {
      // See above: an unrepeatable first run is preferable to a repeated one.
    }
    setOnboarding(false);
  };

  // Nothing renders until the stored settings are in state, so the first shift
  // the user sees is their own rather than 09:00–18:00 flashing past.
  if (!app.ready || onboarding === null) {
    return <div className="ios-app" />;
  }

  if (onboarding) {
    return (
      <div className="ios-app">
        <MobileOnboarding onFinish={finishOnboarding} />
      </div>
    );
  }

  const timerHeader = (
    <div className="flex items-center justify-between px-5 pt-[calc(env(safe-area-inset-top)+6px)]">
      <span className="text-[13px] font-semibold uppercase tracking-[0.06em] text-[var(--ios-label-2)]">
        {t("offWorkCountdown")}
      </span>
      <ThemeQuickToggle app={app} />
    </div>
  );

  const settingsHeader = (
    <h1 className="px-5 pb-1 pt-[calc(env(safe-area-inset-top)+14px)] text-[34px] font-bold tracking-[-0.025em] text-[var(--ios-title)]">
      {t("settings")}
    </h1>
  );

  const overlays = (
    <>
      {stack.length > 0 && (
        <MobileSubpage
          page={stack[stack.length - 1]}
          lang={lang}
          app={app}
          onBack={popSubpage}
          onOpen={openSubpage}
        />
      )}
      {sheet === "share" && (
        <MobileShareSheet
          lang={lang}
          onClose={() => setSheet(null)}
          timeLeft={t("timeLeft", durationParts(app.view.remainingMs, false))}
          progress={app.view.progress}
          isOff={app.view.phase === "done" || app.view.phase === "nextShift"}
          shift={{ start: app.settings.startTime, end: app.settings.endTime }}
        />
      )}
      {sheet === "overtime" && (
        <OvertimeSheet
          app={app}
          value={overtimeEnd}
          onChange={setOvertimeEnd}
          onClose={() => setSheet(null)}
        />
      )}
    </>
  );

  if (layout === "wide") {
    return (
      <div className="ios-app flex-row">
        {sidebarVisible && (
          <IosSidebar
            lang={lang}
            app={app}
            tab={tab}
            onSelect={selectTab}
            onHide={() => setSidebarVisible(false)}
          />
        )}
        <div className="relative flex min-w-0 flex-1 flex-col">
          {!sidebarVisible && (
            <div className="absolute start-6 top-6 z-10">
              <IosSidebarButton onShow={() => setSidebarVisible(true)} />
            </div>
          )}
          {tab === "timer" ? (
            <div className="mx-auto flex h-full w-full max-w-[900px] flex-col">
              <MobileWideTimer
                large
                lang={lang}
                app={app}
                onShare={() => setSheet("share")}
                onOvertime={openOvertime}
              />
            </div>
          ) : (
            <MobileSettingsScreen
              columns
              lang={lang}
              app={app}
              onOpen={openSubpage}
              header={settingsHeader}
            />
          )}
          {overlays}
        </div>
      </div>
    );
  }

  if (layout === "landscape") {
    return (
      <div className="ios-app flex-row">
        <IosTabRail tab={tab} onSelect={selectTab} />
        <div className="relative flex min-w-0 flex-1 flex-col pe-[max(12px,env(safe-area-inset-right))]">
          {tab === "timer" ? (
            <MobileWideTimer
              lang={lang}
              app={app}
              onShare={() => setSheet("share")}
              onOvertime={openOvertime}
            />
          ) : (
            <MobileSettingsScreen
              columns
              lang={lang}
              app={app}
              onOpen={openSubpage}
              header={
                <h1 className="px-2 pt-4 text-[26px] font-bold tracking-[-0.025em] text-[var(--ios-title)]">
                  {t("settings")}
                </h1>
              }
            />
          )}
          {overlays}
        </div>
      </div>
    );
  }

  return (
    <div className="ios-app">
      {/* Pushed screens and sheets stay inside the content area. In the
          packaged app the tab bar is a UIKit view the WebView cannot draw over,
          so an overlay that covered it here would not survive on device. */}
      <div className="relative flex min-h-0 flex-1 flex-col">
        {tab === "timer" ? (
          <MobileTimerScreen
            lang={lang}
            app={app}
            onOpen={openSubpage}
            onShare={() => setSheet("share")}
            onOvertime={openOvertime}
            header={timerHeader}
          />
        ) : (
          <MobileSettingsScreen
            lang={lang}
            app={app}
            onOpen={openSubpage}
            header={settingsHeader}
          />
        )}
        {overlays}
      </div>
      <IosTabBar tab={tab} onSelect={selectTab} />
    </div>
  );
}

function ThemeQuickToggle({ app }: { app: ReturnType<typeof useIosApp> }) {
  const { t } = useTranslation();
  const theme = app.settings.theme;
  const Icon = THEME_ICONS[theme];
  // Custom themes are chosen in Settings; the quick control only walks the
  // three appearances iOS itself offers.
  const next =
    THEME_CYCLE[(THEME_CYCLE.indexOf(theme) + 1) % THEME_CYCLE.length] ??
    "auto";

  return (
    <button
      type="button"
      onClick={() => app.update({ theme: next })}
      aria-label={t("toggleTheme")}
      className="inline-flex h-[34px] w-[34px] items-center justify-center rounded-full bg-[var(--ios-fill)] text-[var(--ios-label-2)]"
    >
      <Icon className="h-[17px] w-[17px]" />
    </button>
  );
}

function OvertimeSheet({
  app,
  value,
  onChange,
  onClose,
}: {
  app: ReturnType<typeof useIosApp>;
  value: string;
  onChange: (next: string) => void;
  onClose: () => void;
}) {
  const { t } = useTranslation();
  const valid = app.view.plannedEndAtMs > 0;

  return (
    <IosSheet onClose={onClose} label={t("overtimeTitle")}>
      <div className="px-5 pb-1">
        <span className="text-[20px] font-bold tracking-[-0.02em] text-[var(--ios-title)]">
          {t("overtimeTitle")}
        </span>
        <p className="mt-1 text-[15px] text-[var(--ios-label-2)]">
          {t("overtimeDescription")}
        </p>
      </div>
      <IosGroup className="mt-4" note={t("overtimeNoMultiplier")}>
        <IosTimeField
          label={t("overtimeEndTime")}
          value={value}
          onChange={onChange}
        />
      </IosGroup>
      <div className="px-4 pt-4">
        <IosButton
          filled
          className="w-full"
          disabled={!valid}
          onClick={() => {
            if (app.applyOvertime(value)) onClose();
          }}
        >
          {t("confirmOvertime")}
        </IosButton>
      </div>
    </IosSheet>
  );
}
