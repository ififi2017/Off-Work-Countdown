"use client";

import { useTranslation } from "react-i18next";
import {
  ArrowLeft,
  BellRing,
  CalendarDays,
  CalendarRange,
  Clock,
  Coffee,
  Coins,
  Eye,
  EyeOff,
  GlassWater,
  Play,
  RectangleHorizontal,
  Share2,
} from "lucide-react";
import { getShiftEndAtMs, getShiftStartAtMs } from "@/lib/countdown";
import {
  approximateDuration,
  clockAt,
  describeWorkdays,
  durationParts,
  formatDays,
  formatHours,
  formatMinutes,
  formatMoney,
  relativeDayLabel,
} from "@/lib/mobile/format";
import type { IosAppState } from "@/lib/mobile/use-ios-app";
import type { PeriodSummary } from "@/lib/summary";
import { IosButton, IosGroup, IosProgress, IosRow } from "./ios-kit";
import { IosTimeField } from "./IosTimeField";
import { IosWorkdayGrid } from "./IosWorkdayGrid";
import type { SubpageId } from "./subpage-ids";

interface Props {
  lang: string;
  app: IosAppState;
  onOpen: (page: SubpageId) => void;
  onShare: () => void;
  onOvertime: () => void;
  header: React.ReactNode;
}

const MINUTE_MS = 60 * 1000;

export function MobileTimerScreen({
  lang,
  app,
  onOpen,
  onShare,
  onOvertime,
  header,
}: Props) {
  const { t } = useTranslation();
  const { settings, view, started } = app;

  return (
    <>
      {header}
      <div className="ios-scroll flex flex-col pb-3">
        {started ? (
          <RunningTimer
            lang={lang}
            app={app}
            onOpen={onOpen}
            onShare={onShare}
            onOvertime={onOvertime}
          />
        ) : view.todayIsWorkday ? (
          <ShiftSetup lang={lang} app={app} onOpen={onOpen} />
        ) : (
          <NotAWorkday lang={lang} app={app} />
        )}
      </div>
      {!started && (
        <div className="px-4 pb-3.5">
          <IosButton
            filled
            icon={Play}
            className="w-full"
            disabled={settings.startTime === settings.endTime}
            onClick={app.start}
          >
            {t("startCountdown")}
          </IosButton>
        </div>
      )}
    </>
  );
}

/* ── Countdown not started ─────────────────────────────────────────────── */

function ShiftSetup({
  lang,
  app,
  onOpen,
}: {
  lang: string;
  app: IosAppState;
  onOpen: (page: SubpageId) => void;
}) {
  const { t } = useTranslation();
  const { settings, update, plannedShift, view } = app;
  const sameTime = settings.startTime === settings.endTime;

  const summaryLine = [
    formatHours(lang, plannedShift.hours - plannedShift.lunchMinutes / 60),
    plannedShift.lunchMinutes > 0
      ? formatMinutes(lang, plannedShift.lunchMinutes)
      : null,
    describeWorkdays(lang, settings.workdays) || t("restDay"),
  ]
    .filter(Boolean)
    .join(" · ");

  return (
    <>
      <div className="px-5 pt-5 text-center">
        <div
          dir="ltr"
          className="text-[40px] font-bold leading-none tracking-[-0.03em] tabular-nums text-[var(--ios-title)]"
        >
          {settings.startTime} — {settings.endTime}
        </div>
        <div className="mt-2.5 text-[15px] text-[var(--ios-label-2)]">
          {sameTime ? t("sameTimeError") : summaryLine}
        </div>
      </div>

      <IosGroup
        title={t("shiftSection")}
        className="mt-6"
        note={plannedShift.lunchFitsInShift ? undefined : t("lunchOutsideShift")}
      >
        <IosTimeField
          label={t("startTime")}
          value={settings.startTime}
          onChange={(startTime) => update({ startTime })}
          separator
        />
        <IosTimeField
          label={t("endTime")}
          value={settings.endTime}
          onChange={(endTime) => update({ endTime })}
          separator
        />
        <IosWorkdayGrid
          lang={lang}
          label={t("workdaysLabel")}
          workdays={settings.workdays}
          onChange={(workdays) => update({ workdays })}
        />
      </IosGroup>

      <IosGroup className="mt-6">
        <IosRow
          icon={Coins}
          label={t("salarySettings")}
          value={
            settings.showSalary
              ? t(settings.salaryType === "daily" ? "daily" : "monthly")
              : t("disabledShort")
          }
          chevron
          separator
          onClick={() => onOpen("salary")}
        />
        <IosRow
          icon={BellRing}
          label={t("notificationMode")}
          value={t(
            settings.notificationMode === "off"
              ? "notificationModeOff"
              : settings.notificationMode === "simple"
                ? "notificationModeSimple"
                : "notificationModeMilestones"
          )}
          chevron
          separator
          onClick={() => onOpen("notifications")}
        />
        <IosRow
          icon={Coffee}
          label={t("lunchBreak")}
          value={
            settings.lunchEnabled
              ? `${settings.lunchStartTime} · ${formatMinutes(
                  lang,
                  settings.lunchDurationMinutes
                )}`
              : t("disabledShort")
          }
          numericValue={settings.lunchEnabled}
          chevron
          separator
          onClick={() => onOpen("lunch")}
        />
        <IosRow
          icon={GlassWater}
          label={t("microBreakReminder")}
          value={
            settings.microBreakEnabled
              ? formatMinutes(lang, settings.microBreakIntervalMinutes)
              : t("disabledShort")
          }
          chevron
          onClick={() => onOpen("health")}
        />
      </IosGroup>

      <div className="min-h-3 flex-1" />
    </>
  );
}

/**
 * Today is not one of the configured workdays.
 *
 * It gets its own screen rather than a warning on the setup screen: nothing on
 * the setup screen would be wrong, but the one thing worth saying is that the
 * next shift is days away — and starting a countdown anyway is still allowed.
 */
function NotAWorkday({ lang, app }: { lang: string; app: IosAppState }) {
  const { t } = useTranslation();
  const { settings, update, view } = app;

  return (
    <>
      <div className="px-5 pt-8 text-center">
        <div className="text-[34px] font-bold tracking-[-0.025em] text-[var(--ios-title)]">
          {t("restDay")}
        </div>
        <p className="mt-3 text-[17px] leading-snug text-[var(--ios-label-2)]">
          {t("notAWorkdayBody", {
            day: new Intl.DateTimeFormat(lang, { weekday: "long" }).format(
              new Date(app.nowMs || Date.now())
            ),
          })}
        </p>
      </div>

      <IosGroup className="mt-[34px]">
        <IosRow
          icon={Clock}
          label={t("nextShiftRow")}
          value={
            view.nextShiftStartAtMs !== null
              ? `${relativeDayLabel(
                  lang,
                  view.nextShiftStartAtMs,
                  app.nowMs,
                  t("tomorrow")
                )} ${clockAt(view.nextShiftStartAtMs)}`
              : "—"
          }
          numericValue
        />
      </IosGroup>

      <IosGroup
        title={t("summaryThisWeek")}
        className="mt-[18px]"
        note={t("summaryEstimateNote")}
      >
        <IosWorkdayGrid
          lang={lang}
          todayHighlight
          label={t("workdaysLabel")}
          workdays={settings.workdays}
          onChange={(workdays) => update({ workdays })}
        />
        <div className="relative">
          <div className="absolute inset-x-4 top-0 h-px bg-[var(--ios-separator)]" />
          <SummaryRow
            icon={Clock}
            label={t("worked")}
            lang={lang}
            summary={view.week}
            hideEarnings={settings.hideEarnings}
          />
        </div>
      </IosGroup>

      <div className="min-h-3 flex-1" />
    </>
  );
}

/* ── Countdown running ─────────────────────────────────────────────────── */

function RunningTimer({
  lang,
  app,
  onOpen,
  onShare,
  onOvertime,
}: {
  lang: string;
  app: IosAppState;
  onOpen: (page: SubpageId) => void;
  onShare: () => void;
  onOvertime: () => void;
}) {
  const { t } = useTranslation();
  const { settings, view, update, nowMs } = app;
  const finished = view.phase === "done" || view.phase === "nextShift";

  return (
    <>
      {finished ? (
        <FinishedHero lang={lang} app={app} />
      ) : (
        <RunningHero lang={lang} app={app} />
      )}

      {finished ? (
        <TodayInFull lang={lang} app={app} />
      ) : view.phase === "lunch" ? (
        <IosGroup className="mt-[30px]" note={t("lunchPauseNote")}>
          <IosRow
            icon={Clock}
            label={t("lunchBackAt")}
            value={
              <span className="font-semibold text-[var(--ios-label)]">
                {view.breakEndAtMs !== null ? clockAt(view.breakEndAtMs) : "--:--"}
              </span>
            }
            numericValue
            separator={view.moneyEarned !== null}
          />
          {view.moneyEarned !== null && (
            <EarningsRow lang={lang} app={app} />
          )}
        </IosGroup>
      ) : view.phase === "overtime" ? (
        <IosGroup className="mt-[30px]" note={t("overtimeNoMultiplier")}>
          <IosRow
            icon={Clock}
            label={t("shiftEnded")}
            value={`${clockAt(view.plannedEndAtMs)} · ${t("timeAgo", {
              time: approximateDuration(lang, nowMs - view.plannedEndAtMs),
            })}`}
            numericValue
            separator={view.moneyEarned !== null}
          />
          {view.moneyEarned !== null && <EarningsRow lang={lang} app={app} />}
        </IosGroup>
      ) : (
        <IosGroup className="mt-[30px]" note={t("summaryEstimateNote")}>
          <IosRow
            icon={Clock}
            label={t("todaysShift")}
            value={`${clockAt(view.shiftStartAtMs)} – ${clockAt(
              view.plannedEndAtMs
            )}`}
            numericValue
            separator
          />
          {view.moneyEarned !== null && <EarningsRow lang={lang} app={app} separator />}
          <SummaryRow
            icon={CalendarDays}
            label={t("summaryThisWeek")}
            lang={lang}
            summary={view.week}
            hideEarnings={settings.hideEarnings}
            separator
          />
          <SummaryRow
            icon={CalendarRange}
            label={t("summaryThisYear")}
            lang={lang}
            summary={view.year}
            hideEarnings={settings.hideEarnings}
          />
        </IosGroup>
      )}

      {!finished && <ComingUp lang={lang} app={app} onOpen={onOpen} />}

      <div className="min-h-3 flex-1" />

      <div className="flex gap-2.5 px-4 pb-3.5">
        {finished ? (
          <>
            <IosButton icon={ArrowLeft} className="flex-1" onClick={app.stop}>
              {t("return")}
            </IosButton>
            <IosButton icon={Share2} className="flex-1" onClick={onShare}>
              {t("shareButton")}
            </IosButton>
          </>
        ) : (
          <>
            <IosButton icon={ArrowLeft} className="flex-1" onClick={app.stop}>
              {t("return")}
            </IosButton>
            <IosButton className="flex-1" onClick={onOvertime}>
              {t(view.overtimeEndAtMs !== null ? "adjustOvertime" : "overtime")}
            </IosButton>
            <IosButton
              className="w-[50px] flex-none"
              icon={Share2}
              ariaLabel={t("shareButton")}
              onClick={onShare}
            />
          </>
        )}
      </div>
    </>
  );
}

function RunningHero({ lang, app }: { lang: string; app: IosAppState }) {
  const { t } = useTranslation();
  const { view, settings } = app;
  const lunch = view.phase === "lunch";
  const overtime = view.phase === "overtime";
  const beforeShift = view.phase === "beforeShift";

  const remaining = lunch
    ? Math.max(0, (view.breakEndAtMs ?? 0) - app.nowMs)
    : view.remainingMs;
  const parts = durationParts(
    remaining,
    app.plannedShift.hours >= 10 && !lunch
  );

  return (
    <>
      <div className="px-5 pt-6 text-center">
        {lunch && (
          <span className="inline-flex items-center gap-1.5 rounded-full bg-[var(--ios-fill)] px-3 py-[5px] text-[13px] font-semibold text-[var(--ios-label-2)]">
            <Coffee className="h-3.5 w-3.5" />
            {t("lunchInProgress")}
          </span>
        )}
        {overtime && view.overtimeEndAtMs !== null && (
          <span className="inline-flex items-center rounded-full bg-[var(--ios-accent-wash)] px-3 py-[5px] text-[13px] font-semibold text-[var(--ios-accent-ink)]">
            {t("overtimeUntil", { time: clockAt(view.overtimeEndAtMs) })}
          </span>
        )}
        <div
          dir="ltr"
          className={`ios-countdown font-bold leading-none tracking-[-0.025em] tabular-nums ${
            lunch || overtime ? "mt-4" : ""
          } ${lunch ? "text-[var(--ios-label-2)]" : "text-[var(--ios-title)]"}`}
        >
          {t("timeLeft", parts)}
        </div>
        <div className="mt-2 text-[15px] text-[var(--ios-label-2)]">
          {lunch
            ? t("pausedUntil", {
                time: view.breakEndAtMs !== null ? clockAt(view.breakEndAtMs) : "",
              })
            : beforeShift
              ? t("nextShiftLabelShort")
              : t("timeLeftCaption")}
        </div>
      </div>
      <IosProgress
        className="mx-5 mt-[34px]"
        percent={view.progress}
        tone={overtime ? "overtime" : "neutral"}
        paused={lunch}
        showBubble={!beforeShift}
      />
    </>
  );
}

function FinishedHero({ lang, app }: { lang: string; app: IosAppState }) {
  const { t } = useTranslation();
  const { view } = app;
  const parts = durationParts(view.remainingMs, false);

  return (
    <>
      <div className="px-5 pt-8 text-center">
        <div className="text-[34px] font-bold tracking-[-0.025em] text-[var(--ios-title)]">
          {t("offWorkToday")}
        </div>
        {view.phase === "nextShift" && (
          <div
            dir="ltr"
            className="mt-3 text-[22px] font-semibold tabular-nums text-[var(--ios-label-2)]"
          >
            {t("nextShiftIn", { time: t("timeLeft", parts) })}
          </div>
        )}
      </div>
      <IosProgress
        className="mx-5 mt-[30px]"
        percent={100}
        showBubble={false}
      />
    </>
  );
}

function TodayInFull({ lang, app }: { lang: string; app: IosAppState }) {
  const { t } = useTranslation();
  const { view, settings } = app;
  const shift = view.shift;
  if (!shift) return null;

  const workedMs = shift.segments.reduce(
    (total, segment) => total + segment.endAtMs - segment.startAtMs,
    0
  );
  const lunchGapStart = shift.segments.length > 1 ? shift.segments[0].endAtMs : null;
  const lunchGapEnd =
    shift.segments.length > 1 ? shift.segments[1].startAtMs : null;

  return (
    <>
      <IosGroup className="mt-[30px]">
        {view.moneyEarned !== null && <EarningsRow lang={lang} app={app} separator />}
        {view.nextShiftStartAtMs !== null && (
          <IosRow
            icon={CalendarDays}
            label={relativeDayLabel(
              lang,
              view.nextShiftStartAtMs,
              app.nowMs,
              t("tomorrow")
            )}
            value={clockAt(view.nextShiftStartAtMs)}
            numericValue
          />
        )}
      </IosGroup>

      <IosGroup
        title={t("todayInFull")}
        className="mt-[18px]"
        note={t("summaryEstimateNote")}
      >
        <IosRow
          icon={Clock}
          label={t("worked")}
          value={approximateDuration(lang, workedMs)}
          numericValue
          separator
        />
        {lunchGapStart !== null && lunchGapEnd !== null && (
          <IosRow
            icon={Coffee}
            label={t("lunchTaken")}
            value={`${clockAt(lunchGapStart)} – ${clockAt(lunchGapEnd)}`}
            numericValue
            separator
          />
        )}
        <SummaryRow
          icon={CalendarDays}
          label={t("summaryThisWeek")}
          lang={lang}
          summary={view.week}
          hideEarnings={settings.hideEarnings}
        />
      </IosGroup>
    </>
  );
}

/**
 * What the app will do next, so a reminder that has been scheduled is visible
 * rather than something the user has to trust silently.
 */
function ComingUp({
  lang,
  app,
  onOpen,
}: {
  lang: string;
  app: IosAppState;
  onOpen: (page: SubpageId) => void;
}) {
  const { t } = useTranslation();
  const { settings, view, nowMs } = app;
  const microBreak = settings.microBreakEnabled
    ? view.phase === "lunch"
      ? t("pausedUntil", {
          time: view.breakEndAtMs !== null ? clockAt(view.breakEndAtMs) : "",
        })
      : nextMicroBreakLabel(lang, app, t)
    : "";
  // An empty label means the last reminder of this segment has already passed;
  // an empty row would read as a broken one.
  const showMicroBreak = microBreak !== "";
  if (!showMicroBreak && !settings.liveActivityEnabled) return null;

  const liveActivityAtMs =
    view.plannedEndAtMs - settings.liveActivityLeadMinutes * MINUTE_MS;

  return (
    <IosGroup title={t("comingUp")} className="mt-4">
      {showMicroBreak && (
        <IosRow
          icon={GlassWater}
          label={t("microBreakReminder")}
          value={microBreak}
          numericValue={view.phase !== "lunch"}
          separator={settings.liveActivityEnabled}
          chevron
          onClick={() => onOpen("health")}
        />
      )}
      {settings.liveActivityEnabled && (
        <IosRow
          icon={RectangleHorizontal}
          label={t("liveActivity")}
          value={clockAt(liveActivityAtMs)}
          numericValue
          chevron
          onClick={() => onOpen("notifications")}
        />
      )}
    </IosGroup>
  );
}

function nextMicroBreakLabel(
  lang: string,
  app: IosAppState,
  t: (key: string, options?: Record<string, unknown>) => string
): string {
  const { view, settings, nowMs } = app;
  const shift = view.shift;
  if (!shift) return "";
  const intervalMs = settings.microBreakIntervalMinutes * MINUTE_MS;

  // Health reminders are spaced by *effective* work time, so they restart from
  // the segment boundary rather than from the wall clock.
  const segment = shift.segments.find(
    (candidate) => nowMs >= candidate.startAtMs && nowMs < candidate.endAtMs
  );
  if (!segment) return "";
  const elapsed = nowMs - segment.startAtMs;
  const nextAtMs =
    segment.startAtMs + (Math.floor(elapsed / intervalMs) + 1) * intervalMs;
  if (nextAtMs >= segment.endAtMs) return "";

  return `${clockAt(nextAtMs)} · ${t("inTime", {
    time: approximateDuration(lang, nextAtMs - nowMs),
  })}`;
}

function EarningsRow({
  lang,
  app,
  separator = false,
}: {
  lang: string;
  app: IosAppState;
  separator?: boolean;
}) {
  const { t } = useTranslation();
  const { settings, update, view } = app;
  const hidden = settings.hideEarnings;

  return (
    <IosRow
      icon={Coins}
      label={t("moneyEarned")}
      value={
        <span className="font-semibold text-[var(--ios-label)]">
          {hidden ? "••••" : formatMoney(lang, view.moneyEarned ?? 0, true)}
        </span>
      }
      numericValue
      separator={separator}
      // The icon states what the tap will do, not what is on screen — the same
      // contract the Desktop and Mini Timer eye follows.
      detail={
        <button
          type="button"
          onClick={() => update({ hideEarnings: !hidden })}
          aria-label={t(hidden ? "showEarnings" : "hideEarnings")}
          className="-m-2 flex-none p-2 text-[var(--ios-label-3)]"
        >
          {hidden ? (
            <Eye className="h-[17px] w-[17px]" />
          ) : (
            <EyeOff className="h-[17px] w-[17px]" />
          )}
        </button>
      }
    />
  );
}

function SummaryRow({
  icon,
  label,
  lang,
  summary,
  hideEarnings,
  separator = false,
}: {
  icon: typeof CalendarDays;
  label: string;
  lang: string;
  summary: PeriodSummary | null;
  hideEarnings: boolean;
  separator?: boolean;
}) {
  if (!summary) return null;
  const parts = [
    formatDays(lang, summary.days),
    formatHours(lang, summary.hours, 0),
  ];
  if (summary.earnings !== null && !hideEarnings) {
    parts.push(formatMoney(lang, summary.earnings));
  }

  return (
    <IosRow
      icon={icon}
      label={label}
      value={<span className="text-[15px]">{parts.join(" · ")}</span>}
      numericValue
      separator={separator}
    />
  );
}
