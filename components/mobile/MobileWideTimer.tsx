"use client";

import { useTranslation } from "react-i18next";
import { ArrowLeft, Play, Share2 } from "lucide-react";
import {
  clockAt,
  durationParts,
  formatDays,
  formatMoney,
} from "@/lib/mobile/format";
import type { IosAppState } from "@/lib/mobile/use-ios-app";
import { IosButton, IosProgress } from "./ios-kit";

/**
 * The timer with the height of a phone in landscape or the width of an iPad.
 *
 * Same reading order as portrait — time, then progress, then the figures, then
 * the actions — but the progress becomes the shift's own clock: ticked from
 * start to end, with lunch drawn as the gap it actually is. There is room for
 * that here and there is not in 402 pt of portrait width.
 */
export function MobileWideTimer({
  lang,
  app,
  onShare,
  onOvertime,
  large = false,
}: {
  lang: string;
  app: IosAppState;
  onShare: () => void;
  onOvertime: () => void;
  /** iPad sizing rather than landscape-phone sizing. */
  large?: boolean;
}) {
  const { t } = useTranslation();
  const { view, settings, started } = app;
  const finished = view.phase === "done" || view.phase === "nextShift";
  const remaining =
    view.phase === "lunch"
      ? Math.max(0, (view.breakEndAtMs ?? 0) - app.nowMs)
      : view.remainingMs;
  const parts = durationParts(remaining, app.plannedShift.hours >= 10);

  if (!started) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-6 px-10 text-center">
        <div
          dir="ltr"
          className={`font-bold leading-none tracking-[-0.035em] tabular-nums text-[var(--ios-title)] ${
            large ? "text-[88px]" : "text-[64px]"
          }`}
        >
          {settings.startTime} — {settings.endTime}
        </div>
        <p className="text-[17px] text-[var(--ios-label-2)]">
          {t("countdownNotStarted")}
        </p>
        <IosButton filled icon={Play} className="px-8" onClick={app.start}>
          {t("startCountdown")}
        </IosButton>
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col justify-center gap-5 px-12 pb-5 pt-5">
      <div className="text-center">
        <div
          dir="ltr"
          className={`font-bold leading-none tracking-[-0.04em] tabular-nums ${
            large ? "text-[130px]" : "text-[76px]"
          } ${
            view.phase === "lunch"
              ? "text-[var(--ios-label-2)]"
              : "text-[var(--ios-title)]"
          }`}
        >
          {finished ? t("offWorkToday") : t("timeLeft", parts)}
        </div>
        <div
          className={`mt-2 text-[var(--ios-label-2)] ${
            large ? "text-[19px]" : "text-sm"
          }`}
        >
          {view.phase === "lunch"
            ? t("pausedUntil", {
                time: view.breakEndAtMs !== null ? clockAt(view.breakEndAtMs) : "",
              })
            : view.phase === "overtime" && view.overtimeEndAtMs !== null
              ? t("overtimeUntil", { time: clockAt(view.overtimeEndAtMs) })
              : t("timeLeftCaption")}
        </div>
      </div>

      <ShiftScale app={app} large={large} />

      <div
        className={`flex justify-center ${large ? "gap-14 pt-4" : "gap-12"}`}
      >
        <Figure
          label={t("summaryThisWeek")}
          value={view.week ? formatDays(lang, view.week.days) : "—"}
          large={large}
        />
        {view.moneyEarned !== null && !settings.hideEarnings && (
          <Figure
            label={t("moneyEarned")}
            value={formatMoney(lang, view.moneyEarned, true)}
            large={large}
          />
        )}
        <Figure
          label={t("liveActivity")}
          value={`${view.progress.toFixed(1)}%`}
          large={large}
        />
      </div>

      <div className="flex justify-center gap-2.5">
        <IosButton icon={ArrowLeft} className="px-5" onClick={app.stop}>
          {t("return")}
        </IosButton>
        {!finished && (
          <IosButton className="px-5" onClick={onOvertime}>
            {t(view.overtimeEndAtMs !== null ? "adjustOvertime" : "overtime")}
          </IosButton>
        )}
        <IosButton icon={Share2} className="px-5" onClick={onShare}>
          {t("shareNative")}
        </IosButton>
      </div>
    </div>
  );
}

/**
 * The bar as the actual clock rather than an abstract percentage: each work
 * segment is drawn to scale, the gaps between them are the breaks, and the
 * labels underneath are wall-clock times.
 */
function ShiftScale({ app, large }: { app: IosAppState; large: boolean }) {
  const { t } = useTranslation();
  const { view, nowMs } = app;
  const shift = view.shift;
  if (!shift || shift.segments.length === 0) {
    return <IosProgress percent={view.progress} showBubble={false} />;
  }

  const startAtMs = shift.segments[0].startAtMs;
  const endAtMs = shift.segments[shift.segments.length - 1].endAtMs;
  const span = Math.max(1, endAtMs - startAtMs);
  const pct = (atMs: number) => ((atMs - startAtMs) / span) * 100;

  const bands: { widthPct: number; kind: "work" | "gap" }[] = [];
  let cursor = startAtMs;
  for (const segment of shift.segments) {
    if (segment.startAtMs > cursor) {
      bands.push({
        widthPct: pct(segment.startAtMs) - pct(cursor),
        kind: "gap",
      });
    }
    bands.push({
      widthPct: pct(segment.endAtMs) - pct(segment.startAtMs),
      kind: "work",
    });
    cursor = segment.endAtMs;
  }

  const nowPct = Math.max(0, Math.min(100, pct(nowMs)));
  const overtime = view.phase === "overtime";

  return (
    <div>
      <div
        className="relative flex overflow-hidden rounded-full bg-[var(--ios-fill-track)]"
        style={{ height: large ? 12 : 10 }}
        role="progressbar"
        aria-valuenow={Math.round(view.progress)}
        aria-valuemin={0}
        aria-valuemax={100}
      >
        {bands.map((band, index) => (
          <div
            key={index}
            style={{
              width: `${band.widthPct}%`,
              background:
                band.kind === "gap"
                  ? "var(--ios-fill-strong)"
                  : overtime
                    ? "var(--ios-accent)"
                    : "var(--ios-title)",
            }}
          />
        ))}
        {/* Everything after "now" is still ahead, so it is masked back to the
            empty track rather than drawn as done. */}
        <div
          className="absolute inset-y-0 bg-[var(--ios-bg)] opacity-90"
          style={{ insetInlineStart: `${nowPct}%`, insetInlineEnd: 0 }}
        />
      </div>
      <div
        dir="ltr"
        className={`mt-2 flex justify-between tabular-nums text-[var(--ios-label-2)] ${
          large ? "text-sm" : "text-xs"
        }`}
      >
        <span>{clockAt(startAtMs)}</span>
        {shift.segments.length > 1 && (
          <span>
            {clockAt(shift.segments[0].endAtMs)} · {t("lunchBreak")}
          </span>
        )}
        <span>{clockAt(endAtMs)}</span>
      </div>
    </div>
  );
}

function Figure({
  label,
  value,
  large,
}: {
  label: string;
  value: string;
  large: boolean;
}) {
  return (
    <div className="text-center">
      <div
        className={`text-[var(--ios-label-2)] ${large ? "text-[13px]" : "text-xs"}`}
      >
        {label}
      </div>
      <div
        dir="ltr"
        className={`mt-1 font-bold tabular-nums text-[var(--ios-title)] ${
          large ? "text-[28px]" : "text-xl"
        }`}
      >
        {value}
      </div>
    </div>
  );
}
