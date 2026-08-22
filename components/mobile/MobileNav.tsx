"use client";

import { useTranslation } from "react-i18next";
import {
  PanelLeftClose,
  PanelLeftOpen,
  Settings2,
  Timer,
} from "lucide-react";
import { siteConfig } from "@/config/site";
import { clockAt, formatMinutes, formatMoney } from "@/lib/mobile/format";
import type { IosAppState } from "@/lib/mobile/use-ios-app";

export type TabId = "timer" | "settings";

const TABS: { id: TabId; icon: typeof Timer; labelKey: string }[] = [
  { id: "timer", icon: Timer, labelKey: "timerTab" },
  { id: "settings", icon: Settings2, labelKey: "settings" },
];

/**
 * The Web tab bar.
 *
 * The packaged app hides this and lets UIKit draw the real `UITabBar`, so iOS
 * applies the system Liquid Glass material rather than an approximation of it.
 * This copy exists for browser visual QA and stays on the same event contract.
 */
export function IosTabBar({
  tab,
  onSelect,
}: {
  tab: TabId;
  onSelect: (tab: TabId) => void;
}) {
  const { t } = useTranslation();
  return (
    <nav className="ios-tabbar" aria-label={siteConfig.name}>
      <div
        className="relative grid"
        style={{ gridTemplateColumns: `repeat(${TABS.length}, 1fr)` }}
      >
        {TABS.map(({ id, icon: Icon, labelKey }) => (
          <button
            key={id}
            type="button"
            role="tab"
            aria-selected={tab === id}
            className="ios-tab"
            onClick={() => onSelect(id)}
          >
            <Icon className="h-[26px] w-[26px]" />
            <span>{t(labelKey)}</span>
          </button>
        ))}
      </div>
    </nav>
  );
}

/** Landscape turns the tab bar into a leading rail so height stays for content. */
export function IosTabRail({
  tab,
  onSelect,
}: {
  tab: TabId;
  onSelect: (tab: TabId) => void;
}) {
  const { t } = useTranslation();
  return (
    <nav
      aria-label={siteConfig.name}
      className="flex w-[104px] flex-none flex-col justify-center gap-2 py-3 ps-[max(12px,env(safe-area-inset-left))]"
    >
      {TABS.map(({ id, icon: Icon, labelKey }) => (
        <button
          key={id}
          type="button"
          role="tab"
          aria-selected={tab === id}
          onClick={() => onSelect(id)}
          className="flex flex-col items-center gap-1 rounded-2xl py-2.5 text-[11px]"
          style={
            tab === id
              ? {
                  background: "var(--ios-grouped)",
                  color: "var(--ios-title)",
                  fontWeight: 600,
                }
              : { color: "var(--ios-label-3)", fontWeight: 500 }
          }
        >
          <Icon className="h-6 w-6" />
          {t(labelKey)}
        </button>
      ))}
    </nav>
  );
}

/**
 * iPad sidebar. It replaces the tab bar and carries today's shift at a glance;
 * the countdown itself keeps the product's single centred column rather than
 * stretching across the whole display.
 */
export function IosSidebar({
  lang,
  app,
  tab,
  onSelect,
  onHide,
}: {
  lang: string;
  app: IosAppState;
  tab: TabId;
  onSelect: (tab: TabId) => void;
  onHide: () => void;
}) {
  const { t } = useTranslation();
  const { settings, view } = app;

  return (
    <div className="ios-scroll w-[290px] flex-none border-e-[0.5px] border-[var(--ios-bar-border)] bg-[var(--ios-bar)] px-3.5 pb-6 pt-[max(28px,env(safe-area-inset-top))] backdrop-blur-xl">
      <div className="flex items-center gap-2.5 px-2.5 pb-5">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/icon-192x192.png" alt="" className="h-[30px] w-[30px] rounded-[9px]" />
        <span className="flex-1 text-[17px] font-bold tracking-[-0.02em] text-[var(--ios-title)]">
          {siteConfig.name}
        </span>
        <button
          type="button"
          onClick={onHide}
          aria-label={siteConfig.name}
          className="inline-flex h-8 w-8 items-center justify-center rounded-[10px] bg-[var(--ios-fill)] text-[var(--ios-label-2)]"
        >
          <PanelLeftClose className="h-[17px] w-[17px]" />
        </button>
      </div>

      <div className="flex flex-col gap-1">
        {TABS.map(({ id, icon: Icon, labelKey }) => (
          <button
            key={id}
            type="button"
            role="tab"
            aria-selected={tab === id}
            onClick={() => onSelect(id)}
            className="flex h-11 items-center gap-2.5 rounded-xl px-3 text-[17px]"
            style={
              tab === id
                ? {
                    background: "var(--ios-title)",
                    color: "var(--ios-bg)",
                    fontWeight: 600,
                  }
                : { color: "var(--ios-title)" }
            }
          >
            <Icon className="h-[19px] w-[19px]" />
            {t(labelKey)}
          </button>
        ))}
      </div>

      <div className="ios-group-title px-3 pt-6">{t("todaysShift")}</div>
      <div className="overflow-hidden rounded-[18px] bg-[var(--ios-grouped)]">
        <div className="ios-row ios-row-flush ios-row-sep min-h-[48px] px-3.5 text-base">
          <span className="flex-1">{t("todaysShift")}</span>
          <span dir="ltr" className="ios-row-value text-base">
            {settings.startTime} – {settings.endTime}
          </span>
        </div>
        <div
          className={`ios-row ios-row-flush min-h-[48px] px-3.5 text-base${
            view.moneyEarned !== null ? " ios-row-sep" : ""
          }`}
        >
          <span className="flex-1">{t("lunchBreak")}</span>
          <span dir="ltr" className="ios-row-value text-base">
            {settings.lunchEnabled
              ? `${settings.lunchStartTime} · ${formatMinutes(
                  lang,
                  settings.lunchDurationMinutes
                )}`
              : t("disabledShort")}
          </span>
        </div>
        {view.moneyEarned !== null && !settings.hideEarnings && (
          <div className="ios-row ios-row-flush min-h-[48px] px-3.5 text-base">
            <span className="flex-1">{t("moneyEarned")}</span>
            <span dir="ltr" className="font-semibold tabular-nums">
              {formatMoney(lang, view.moneyEarned, true)}
            </span>
          </div>
        )}
        {view.phase === "lunch" && view.breakEndAtMs !== null && (
          <div className="ios-row ios-row-flush min-h-[48px] px-3.5 text-base">
            <span className="flex-1">{t("lunchBackAt")}</span>
            <span dir="ltr" className="font-semibold tabular-nums">
              {clockAt(view.breakEndAtMs)}
            </span>
          </div>
        )}
      </div>
    </div>
  );
}

export function IosSidebarButton({ onShow }: { onShow: () => void }) {
  const { t } = useTranslation();
  return (
    <button
      type="button"
      onClick={onShow}
      aria-label={t("timerTab")}
      className="inline-flex h-[38px] w-[38px] items-center justify-center rounded-xl bg-[var(--ios-bar)] text-[var(--ios-label-2)] shadow-sm backdrop-blur-md"
    >
      <PanelLeftOpen className="h-[18px] w-[18px]" />
    </button>
  );
}
