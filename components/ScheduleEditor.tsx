"use client";

import { useEffect, useMemo, useRef, useState, type PointerEvent as ReactPointerEvent } from "react";
import { useTranslation } from "react-i18next";
import type { TFunction } from "i18next";
import { Check, ChevronLeft, ChevronRight, Minus, Plus, TriangleAlert } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { TimeSelector } from "./TimeSelector";
import {
  holidayCoverageWarning,
  holidayDay,
  holidayOverrides,
  holidayRegionName,
  loadHolidayIndex,
  suggestedHolidayRegion,
  type HolidayIndex,
  type HolidayRegion,
} from "@/lib/holidays";
import { buildShiftTimeline, civilDateKey } from "@/lib/countdown";
import { isValidShiftType, minutesTime, resolveScheduleDay, type ExtendedSchedulePlan, type ScheduleDay, type ShiftType } from "@/lib/extended-schedule";
import {
  MAX_CYCLE_LENGTH,
  REST_COLOR,
  SHIFT_COLORS,
  activeTypes,
  addDays,
  anchoringCycle,
  assigningCycleDay,
  cycleDayOf,
  daysInMonth,
  newShiftType,
  paintingDays,
  planMode,
  removingShiftType,
  resizingCycle,
  scheduleMode,
  scheduleModeKeys,
  scheduleModes,
  seedPlan,
  settingRosterDay,
  settingsForPlan,
  shiftTypeInUse,
  startingPaint,
  switchingPattern,
  upsertingShiftType,
  weekdayOf,
  type FixedHours,
  type PaintSession,
  type ScheduleMode,
  type ScheduleSettings,
} from "@/lib/schedule-settings";

const cardFrame = "rounded-xl border border-gray-200/80 bg-white/35 shadow-sm dark:border-gray-700 dark:bg-black/10";
const card = `${cardFrame} p-3`;
const iconButton = "inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-lg text-gray-600 transition-colors hover:bg-black/5 hover:text-gray-950 disabled:pointer-events-none disabled:opacity-30 dark:text-gray-300 dark:hover:bg-white/10 dark:hover:text-white";
const field = "flex h-9 overflow-hidden rounded-xl border border-input bg-background focus-within:outline-none focus-within:ring-2 focus-within:ring-ring focus-within:ring-offset-2";
// 2023-01-02 was a Monday: format weekday names without translating them.
const MONDAY = Date.UTC(2023, 0, 2);

/** Plan colours only say work or rest; a type's own colour marks it in lists. */
function dayFill(type: ShiftType | undefined) {
  if (type?.kind === "work") return "bg-orange-500/[0.12] dark:bg-orange-400/[0.16]";
  if (type?.kind === "rest") return "bg-black/[0.04] dark:bg-white/[0.06]";
  return "";
}

export function hoursLabel(type: Pick<ShiftType, "startMinutes" | "endMinutes">, t: TFunction) {
  const start = minutesTime(type.startMinutes);
  const end = minutesTime(type.endMinutes);
  return type.endMinutes <= type.startMinutes ? t("extendedHoursOvernight", { start, end }) : `${start}–${end}`;
}

interface ScheduleEditorProps {
  lang: string;
  settings: ScheduleSettings;
  fixed: FixedHours;
  /** The chosen region's holiday data, once loaded. */
  holidays: HolidayRegion | null;
  /** `fixed` is set when a plain weekly plan folds back into the main form. */
  onChange: (settings: ScheduleSettings, fixed?: FixedHours) => void;
}

/** The desktop schedule page. Every change applies at once, like other settings. */
export function ScheduleEditor({ lang, settings, fixed, holidays, onChange }: ScheduleEditorProps) {
  const { t } = useTranslation();
  const today = civilDateKey(Date.now());
  const [month, setMonth] = useState(() => today.slice(0, 7));
  const [week, setWeek] = useState(0);
  const [editing, setEditing] = useState<ShiftType | null>(null);
  // Free roster quick fill: pick a shift, then click or drag across dates.
  const [brush, setBrush] = useState<string | null>(null);
  const paint = useRef<PaintSession | null>(null);

  const names = { work: t("extendedDefaultWorkShift"), rest: t("extendedDefaultRest") };
  const seeded = useMemo(
    () => seedPlan(fixed, today, names, settings.fixedTypes),
    // Re-seed only when the form or kept types change, not on every render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [fixed.startTime, fixed.endTime, fixed.workdays.join(), fixed.breakStartTime, fixed.breakDurationMinutes, settings.fixedTypes, today, names.work, names.rest]
  );
  const storedPlan = settings.plan ?? seeded;
  const mode = scheduleMode(settings);
  const types = activeTypes(storedPlan);
  // Resolve with the holiday calendar, the way the timer does; commit strips
  // it again, so overrides are never saved into the plan.
  const region = settings.holidayRegion || null;
  const overrides = useMemo(() => (holidays ? holidayOverrides(holidays) : null), [holidays]);
  const plan = useMemo(
    () => (region && overrides ? { ...storedPlan, holidayRegionIdentifier: region, holidayOverrides: overrides } : storedPlan),
    [storedPlan, region, overrides]
  );
  // A drag can paint again before React re-renders; always paint the newest plan.
  const latestPlan = useRef(plan);
  latestPlan.current = plan;
  const activeBrush = mode === "free" && types.some((type) => type.id === brush) ? brush : null;

  function chooseBrush(id: string | null) {
    const next = id === activeBrush ? null : id;
    setBrush(next);
    paint.current = next ? startingPaint(next) : null;
  }

  useEffect(() => {
    if (!activeBrush) return;
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape") { setBrush(null); paint.current = null; } };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [activeBrush]);

  function paintDays(keys: string[]) {
    if (!activeBrush || !paint.current || keys.length === 0) return;
    const next = paintingDays(latestPlan.current, keys, paint.current, today);
    if (next === latestPlan.current) return;
    latestPlan.current = next;
    commit(next);
  }
  const weekdayName = (weekday: number) =>
    new Intl.DateTimeFormat(lang, { weekday: "short", timeZone: "UTC" }).format(new Date(MONDAY + ((weekday + 6) % 7) * 86_400_000));

  function commit(next: ExtendedSchedulePlan, patterns = settings.patterns) {
    const result = settingsForPlan(next, patterns, settings.holidayRegion);
    onChange(result.settings, result.fixed ?? undefined);
  }

  function chooseMode(next: ScheduleMode) {
    if (next === mode) return;
    setEditing(null);
    chooseBrush(null);
    setWeek(0);
    if (next === "manual") return onChange({ ...settings, manual: true });
    const current = planMode(plan);
    if (current === next) return onChange({ ...settings, manual: false });
    const switched = switchingPattern(plan, settings.patterns, current, next, fixed, today, names.rest);
    commit(switched.plan, switched.patterns);
  }

  return (
    <div className="space-y-3 pb-1">
      <section className={card}>
        <div className="flex items-center justify-between gap-3">
          <Label htmlFor="schedule-pattern" className="text-sm dark:text-gray-200">{t("extendedPattern")}</Label>
          <Select value={mode} onValueChange={(value) => chooseMode(value as ScheduleMode)}>
            <SelectTrigger id="schedule-pattern" className="h-9 w-auto min-w-[148px] max-w-[72%] gap-2 whitespace-nowrap rounded-xl bg-background [&>span]:truncate">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {scheduleModes.map((option) => <SelectItem key={option} value={option}>{t(scheduleModeKeys[option])}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>
        {mode === "manual" && <p className="mt-2 text-xs leading-5 text-gray-500 dark:text-gray-400">{t("scheduleOffManualStart")}</p>}
        {mode !== "manual" && (
          <HolidayCalendarRow
            lang={lang}
            region={settings.holidayRegion ?? null}
            onSelect={(holidayRegion) => onChange({ ...settings, holidayRegion })}
          />
        )}
        {mode === "free" && (
          <div className="mt-3 space-y-2 border-t border-gray-200/70 pt-3 dark:border-gray-700/70">
            <div role="radiogroup" aria-label={t("extendedShiftTypes")} className="flex flex-wrap gap-1.5">
              {types.map((type) => (
                <button
                  key={type.id} type="button" role="radio" aria-checked={activeBrush === type.id}
                  onClick={() => chooseBrush(type.id)}
                  className={`inline-flex h-7 max-w-full items-center gap-1.5 rounded-full border px-2.5 text-xs transition-colors ${activeBrush === type.id
                    ? "border-orange-500 bg-orange-500/10 font-medium text-orange-700 dark:border-orange-400 dark:text-orange-300"
                    : "border-gray-200 text-gray-700 hover:border-gray-300 dark:border-gray-700 dark:text-gray-300 dark:hover:border-gray-600"}`}
                >
                  <span className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: type.colorHex }} />
                  <span className="truncate">{type.name}</span>
                </button>
              ))}
            </div>
            <p className="text-xs leading-5 text-gray-500 dark:text-gray-400">{t(activeBrush ? "desktopSchedulePaintHint" : "desktopSchedulePaintStartHint")}</p>
          </div>
        )}
        {plan.rule && mode !== "manual" && mode !== "free" && (
          <CyclePanel
            plan={plan} mode={mode} week={week} today={today} types={types} weekdayName={weekdayName}
            onWeek={setWeek} onChange={commit} restName={names.rest}
          />
        )}
      </section>

      {mode !== "manual" && <>
        <MonthCalendar
          lang={lang} plan={plan} month={month} today={today} types={types} weekdayName={weekdayName}
          holidays={region ? holidays : null}
          onMonth={setMonth}
          onSet={(key, id) => commit(settingRosterDay(plan, key, id, today))}
          brush={activeBrush}
          onPaint={paintDays}
          onStrokeEnd={() => paint.current?.visited.clear()}
        />
        <section className={`${cardFrame} overflow-hidden`}>
          <p className="px-3 pb-1 pt-3 text-xs font-medium text-gray-500 dark:text-gray-400">{t("extendedShiftTypes")}</p>
          <ul>
            {types.map((type) => (
              <li key={type.id} className="border-t border-gray-200/70 first:border-t-0 dark:border-gray-700/70">
                <button
                  type="button"
                  aria-expanded={editing?.id === type.id}
                  onClick={() => setEditing(editing?.id === type.id ? null : { ...type })}
                  className="flex w-full items-center gap-2.5 px-3 py-2.5 text-start text-sm transition-colors hover:bg-black/5 dark:text-gray-200 dark:hover:bg-white/5"
                >
                  <span className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: type.colorHex }} />
                  <span className="min-w-0 flex-1 truncate">{type.name}</span>
                  <span className="shrink-0 text-xs tabular-nums text-gray-500 dark:text-gray-400" dir="ltr">
                    {type.kind === "rest" ? t("extendedKindRest") : hoursLabel(type, t)}
                  </span>
                </button>
                {editing?.id === type.id && (
                  <ShiftTypeForm
                    value={editing} onEdit={setEditing}
                    inUse={shiftTypeInUse(plan, type.id, today)}
                    onCancel={() => setEditing(null)}
                    onSave={(next) => { commit(upsertingShiftType(plan, next, today)); setEditing(null); }}
                    onDelete={() => { commit(removingShiftType(plan, type.id)); setEditing(null); }}
                  />
                )}
              </li>
            ))}
            <li className="border-t border-gray-200/70 dark:border-gray-700/70">
              {editing && !plan.shiftTypes.some((type) => type.id === editing.id) ? (
                <ShiftTypeForm
                  value={editing} onEdit={setEditing} inUse={false}
                  onCancel={() => setEditing(null)}
                  onSave={(next) => { commit(upsertingShiftType(plan, next, today)); setEditing(null); }}
                />
              ) : (
                <button
                  type="button"
                  onClick={() => setEditing(newShiftType(plan, fixed))}
                  className="flex w-full items-center gap-2.5 px-3 py-2.5 text-start text-sm text-orange-600 transition-colors hover:bg-black/5 dark:text-orange-400 dark:hover:bg-white/5"
                >
                  <Plus className="h-3.5 w-3.5" />
                  {t("extendedAddShiftType")}
                </button>
              )}
            </li>
          </ul>
        </section>
      </>}
    </div>
  );
}

function TypeMenuItems({ types, selected, onSelect }: { types: ShiftType[]; selected?: string | null; onSelect: (id: string) => void }) {
  const { t } = useTranslation();
  return <>
    {types.map((type) => (
      <DropdownMenuItem key={type.id} onSelect={() => onSelect(type.id)} className="gap-2">
        <span className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: type.colorHex }} />
        <span className="min-w-[3rem] flex-1 truncate">{type.name}</span>
        {type.kind === "work" && <span className="min-w-0 shrink truncate text-xs tabular-nums text-muted-foreground" dir="ltr">{hoursLabel(type, t)}</span>}
        <Check className={`h-3.5 w-3.5 shrink-0 text-orange-500 ${selected === type.id ? "" : "invisible"}`} />
      </DropdownMenuItem>
    ))}
  </>;
}

function CyclePanel({ plan, mode, week, today, types, weekdayName, onWeek, onChange, restName }: {
  plan: ExtendedSchedulePlan;
  mode: ScheduleMode;
  week: number;
  today: string;
  types: ShiftType[];
  weekdayName: (weekday: number) => string;
  onWeek: (week: number) => void;
  onChange: (plan: ExtendedSchedulePlan) => void;
  restName: string;
}) {
  const { t, i18n } = useTranslation();
  const rule = plan.rule!;
  const count = new Intl.NumberFormat(i18n.language);
  const start = mode === "alternating" ? week * 7 : 0;
  const end = mode === "alternating" ? Math.min(start + 7, rule.days.length) : rule.days.length;
  const position = cycleDayOf(rule, today);
  return (
    <div className="mt-3 space-y-2.5 border-t border-gray-200/70 pt-3 dark:border-gray-700/70">
      {mode === "alternating" && (
        <div role="tablist" className="grid grid-cols-2 gap-1 rounded-lg bg-black/[0.04] p-0.5 dark:bg-white/[0.06]">
          {[0, 1].map((index) => (
            <button
              key={index} type="button" role="tab" aria-selected={week === index} onClick={() => onWeek(index)}
              className={`h-7 rounded-md text-xs transition-colors ${week === index ? "bg-background font-medium shadow-sm dark:bg-white/[0.14] dark:text-white" : "text-gray-500 hover:text-gray-900 dark:text-gray-400 dark:hover:text-white"}`}
            >
              {t("extendedWeekNumber", { week: count.format(index + 1) })}
            </button>
          ))}
        </div>
      )}
      {mode === "rotation" && <>
        <div className="flex items-center justify-between gap-3">
          <span className="text-sm dark:text-gray-200">{t("extendedCycleLength")}</span>
          <div className="flex items-center gap-1" dir="ltr">
            <button type="button" className={iconButton} disabled={rule.days.length <= 1} aria-label="−" onClick={() => onChange(resizingCycle(plan, rule.days.length - 1, restName))}><Minus className="h-3.5 w-3.5" /></button>
            <span className="min-w-[2ch] text-center text-sm tabular-nums dark:text-white">{count.format(rule.days.length)}</span>
            <button type="button" className={iconButton} disabled={rule.days.length >= MAX_CYCLE_LENGTH} aria-label="+" onClick={() => onChange(resizingCycle(plan, rule.days.length + 1, restName))}><Plus className="h-3.5 w-3.5" /></button>
          </div>
        </div>
        <div className="flex items-center justify-between gap-3">
          <Label htmlFor="schedule-cycle-today" className="text-sm font-normal dark:text-gray-200">{t("extendedTodayIs")}</Label>
          <Select value={String(position)} onValueChange={(value) => onChange(anchoringCycle(plan, today, Number(value)))}>
            <SelectTrigger id="schedule-cycle-today" className="h-9 w-[112px] rounded-xl bg-background"><SelectValue /></SelectTrigger>
            <SelectContent className="max-h-64">
              {rule.days.map((_, index) => <SelectItem key={index} value={String(index + 1)}>{t("extendedCycleDay", { day: count.format(index + 1) })}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>
      </>}
      <div className="grid grid-cols-7 gap-1">
        {rule.days.slice(start, end).map((id, offset) => {
          const index = start + offset;
          const type = plan.shiftTypes.find((candidate) => candidate.id === id);
          const label = mode === "rotation" ? count.format(index + 1) : weekdayName(weekdayOf(addDays(rule.anchorDayKey, index)));
          return (
            <DropdownMenu key={index} modal={false}>
              <DropdownMenuTrigger asChild>
                <button
                  type="button"
                  title={type?.name}
                  aria-label={`${label}, ${type?.name ?? t("extendedUnassigned")}`}
                  className={`flex h-11 min-w-0 flex-col items-center justify-center rounded-lg px-0.5 transition-colors hover:ring-1 hover:ring-orange-500/40 data-[state=open]:ring-2 data-[state=open]:ring-orange-500 ${dayFill(type)} ${mode === "rotation" && index + 1 === position ? "ring-1 ring-orange-500/60" : ""}`}
                >
                  <span className={`max-w-full truncate text-xs ${type?.kind === "work" ? "font-semibold text-orange-600 dark:text-orange-400" : "text-gray-500 dark:text-gray-400"}`}>{label}</span>
                  <span className="max-w-full truncate text-[10px] leading-4 text-gray-500 dark:text-gray-400">{type?.name ?? "–"}</span>
                </button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="center" className="w-64 max-w-[calc(100vw-2rem)]">
                <TypeMenuItems types={types} selected={id} onSelect={(next) => onChange(assigningCycleDay(plan, index, next))} />
              </DropdownMenuContent>
            </DropdownMenu>
          );
        })}
      </div>
    </div>
  );
}

const sourceKeys: Record<ScheduleDay["source"], string> = {
  handSet: "extendedSetByHand",
  rule: "extendedPattern",
  annualRange: "extendedSourceAnnualRange",
  carriedOver: "extendedCarriedOver",
  holiday: "holidaySource",
  unassigned: "extendedUnassigned",
};

function MonthCalendar({ lang, plan, month, today, types, weekdayName, holidays, onMonth, onSet, brush, onPaint, onStrokeEnd }: {
  holidays: HolidayRegion | null;
  lang: string;
  plan: ExtendedSchedulePlan;
  month: string;
  today: string;
  types: ShiftType[];
  weekdayName: (weekday: number) => string;
  onMonth: (month: string) => void;
  onSet: (key: string, id: string | null) => void;
  brush: string | null;
  onPaint: (keys: string[]) => void;
  onStrokeEnd: () => void;
}) {
  const { t } = useTranslation();
  const stroke = useRef<{ x: number; y: number } | null>(null);
  const [year, monthNumber] = month.split("-").map(Number);
  const dayAt = (x: number, y: number) => document.elementFromPoint(x, y)?.closest<HTMLElement>("[data-day]")?.dataset.day;
  function strokeStart(event: ReactPointerEvent<HTMLDivElement>) {
    const key = (event.target as Element).closest<HTMLElement>("[data-day]")?.dataset.day;
    if (!brush || !key || event.button !== 0) return;
    event.preventDefault();
    try {
      // Keep receiving moves when the drag leaves the grid.
      event.currentTarget.setPointerCapture(event.pointerId);
    } catch {
      // The pointer was already released; the press still paints its date.
    }
    stroke.current = { x: event.clientX, y: event.clientY };
    onPaint([key]);
  }
  function strokeMove(event: ReactPointerEvent<HTMLDivElement>) {
    const last = stroke.current;
    if (!last) return;
    // Sample the path so a quick drag cannot skip a date between two events.
    const steps = Math.max(1, Math.ceil(Math.hypot(event.clientX - last.x, event.clientY - last.y) / 6));
    const keys: string[] = [];
    for (let step = 1; step <= steps; step += 1) {
      const key = dayAt(last.x + ((event.clientX - last.x) * step) / steps, last.y + ((event.clientY - last.y) * step) / steps);
      if (key && !keys.includes(key)) keys.push(key);
    }
    stroke.current = { x: event.clientX, y: event.clientY };
    onPaint(keys);
  }
  function strokeEnd() {
    if (!stroke.current) return;
    stroke.current = null;
    onStrokeEnd();
  }
  const first = `${month}-01`;
  const leading = (weekdayOf(first) + 6) % 7;
  const count = daysInMonth(year, monthNumber);
  const numberFormat = new Intl.NumberFormat(lang);
  const dateFormat = new Intl.DateTimeFormat(lang, { month: "long", day: "numeric", weekday: "long", timeZone: "UTC" });
  const shift = (delta: number) => {
    const index = year * 12 + monthNumber - 1 + delta;
    onMonth(`${Math.floor(index / 12)}-${String((index % 12) + 1).padStart(2, "0")}`);
  };
  return (
    <section className={card}>
      <div className="flex items-center justify-between gap-2">
        <button
          type="button"
          onClick={() => onMonth(today.slice(0, 7))}
          title={t("extendedToday")}
          className="min-w-0 truncate rounded-md px-1 text-sm font-medium text-gray-900 hover:text-orange-600 dark:text-white dark:hover:text-orange-400"
        >
          {new Intl.DateTimeFormat(lang, { year: "numeric", month: "long", timeZone: "UTC" }).format(Date.UTC(year, monthNumber - 1, 1))}
        </button>
        <div className="flex shrink-0 items-center rtl:flex-row-reverse">
          <button type="button" className={iconButton} onClick={() => shift(-1)} aria-label={t("extendedPreviousMonth")} title={t("extendedPreviousMonth")}><ChevronLeft className="h-4 w-4" /></button>
          <button type="button" className={iconButton} onClick={() => shift(1)} aria-label={t("extendedNextMonth")} title={t("extendedNextMonth")}><ChevronRight className="h-4 w-4" /></button>
        </div>
      </div>
      <div
        className={`mt-2 grid grid-cols-7 gap-1 ${brush ? "touch-none select-none" : ""}`}
        onPointerDown={strokeStart}
        onPointerMove={strokeMove}
        onPointerUp={strokeEnd}
        onPointerCancel={strokeEnd}
        onLostPointerCapture={strokeEnd}
      >
        {[1, 2, 3, 4, 5, 6, 0].map((weekday) => (
          <span key={weekday} aria-hidden="true" className="truncate pb-0.5 text-center text-[11px] text-gray-500 dark:text-gray-400">{weekdayName(weekday)}</span>
        ))}
        {Array.from({ length: leading }, (_, index) => <span key={`lead-${index}`} aria-hidden="true" />)}
        {Array.from({ length: count }, (_, index) => {
          const key = `${month}-${String(index + 1).padStart(2, "0")}`;
          const day = resolveScheduleDay(plan, key);
          const type = plan.frozenShiftTypes?.[key] ?? plan.shiftTypes.find((candidate) => candidate.id === day.shiftTypeID);
          const isToday = key === today;
          const date = dateFormat.format(Date.UTC(year, monthNumber - 1, index + 1));
          const holiday = holidayDay(holidays, key, lang);
          const holidayLabel = holiday && [holiday.name,
            t(holiday.isWorkday ? "holidayMakeupWorkday" : "holidayRestDay"),
            holidays?.estimatedYears?.includes(year) ? t("holidayEstimatedLabel") : null,
          ].filter(Boolean).join(" · ");
          const label = [date, type?.name ?? t("extendedUnassigned"), holidayLabel, isToday ? t("extendedToday") : null].filter(Boolean).join(", ");
          const content = <>
            <span className={`text-sm tabular-nums leading-5 ${isToday ? "font-semibold text-orange-600 dark:text-orange-400" : "text-gray-900 dark:text-gray-100"}`}>{numberFormat.format(index + 1)}</span>
            <span className="flex max-w-full items-center gap-0.5 text-[10px] leading-4 text-gray-500 dark:text-gray-400">
              {/* 与 iOS 一致：节假日在班次名前加一个小点，调休上班用强调色。 */}
              {holiday && <span className={`h-[3px] w-[3px] shrink-0 rounded-full ${holiday.isWorkday ? "bg-orange-500" : "bg-gray-400 dark:bg-gray-500"}`} />}
              <span className="truncate">{type?.name ?? "–"}</span>
            </span>
          </>;
          if (brush) {
            const painted = plan.handSetDays[key] === brush;
            return (
              <button
                key={key} type="button" data-day={key} title={type?.name} aria-label={label} aria-pressed={painted}
                // Pointer strokes paint on press; this handles the keyboard only.
                onClick={(event) => { if (event.detail === 0) { onPaint([key]); onStrokeEnd(); } }}
                className={`flex h-11 min-w-0 flex-col items-center justify-center rounded-lg px-0.5 transition-colors hover:ring-1 hover:ring-orange-500/40 ${painted ? "ring-1 ring-orange-500/70" : ""} ${dayFill(type)}`}
              >
                {content}
              </button>
            );
          }
          return (
            <DropdownMenu key={key} modal={false}>
              <DropdownMenuTrigger asChild>
                <button
                  type="button"
                  title={type?.name}
                  aria-label={label}
                  className={`flex h-11 min-w-0 flex-col items-center justify-center rounded-lg px-0.5 transition-colors hover:ring-1 hover:ring-orange-500/40 data-[state=open]:ring-2 data-[state=open]:ring-orange-500 ${dayFill(type)}`}
                >
                  {content}
                </button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="center" className="w-64 max-w-[calc(100vw-2rem)]">
                <DropdownMenuLabel className="font-normal">
                  <span className="block truncate text-sm font-medium">{date}</span>
                  {holidayLabel && <span className="block truncate text-xs text-muted-foreground">{holidayLabel}</span>}
                  <span className="block text-xs text-muted-foreground">{t(sourceKeys[day.source])}</span>
                </DropdownMenuLabel>
                <DropdownMenuSeparator />
                <TypeMenuItems types={types} selected={day.shiftTypeID} onSelect={(id) => onSet(key, id)} />
                {plan.handSetDays[key] && <>
                  <DropdownMenuSeparator />
                  <DropdownMenuItem onSelect={() => onSet(key, null)}>
                    {t(plan.rule ? "extendedFollowPattern" : "extendedClearDay")}
                  </DropdownMenuItem>
                </>}
              </DropdownMenuContent>
            </DropdownMenu>
          );
        })}
      </div>
      {(() => {
        const warning = holidayCoverageWarning(holidays, year, monthNumber);
        return warning && (
          <p className="mt-2 flex items-start gap-1.5 text-[11px] leading-4 text-gray-500 dark:text-gray-400">
            <TriangleAlert className="mt-px h-3 w-3 shrink-0" />
            {t(warning.key, { year: String(warning.year) })}
          </p>
        );
      })()}
    </section>
  );
}

function ShiftTypeForm({ value, inUse, onEdit, onCancel, onSave, onDelete }: {
  value: ShiftType;
  inUse: boolean;
  onEdit: (type: ShiftType) => void;
  onCancel: () => void;
  onSave: (type: ShiftType) => void;
  onDelete?: () => void;
}) {
  const { t } = useTranslation();
  const [duration, setDuration] = useState(String(value.breakDurationMinutes));
  const breakFits = value.kind === "rest" || !value.breakEnabled || buildShiftTimeline(
    minutesTime(value.startMinutes), minutesTime(value.endMinutes), new Date(),
    { breakStartTime: minutesTime(value.breakStartMinutes), breakDurationMinutes: value.breakDurationMinutes }
  ).segments.length > 1;
  const valid = isValidShiftType({ ...value, name: value.name.trim() }) && breakFits;
  const save = () => onSave({ ...value, name: value.name.trim() });
  // A colour from another device stays selectable without being listed twice.
  const palette = value.kind === "rest" ? [...SHIFT_COLORS, REST_COLOR] : SHIFT_COLORS;
  const swatches = palette.includes(value.colorHex.toUpperCase()) ? palette : [value.colorHex.toUpperCase(), ...palette];
  const time = (key: "startMinutes" | "endMinutes" | "breakStartMinutes") => (hour: string, minute: string) =>
    onEdit({ ...value, [key]: Number(hour) * 60 + Number(minute) });

  return (
    // Not a <form>: Enter in a time field commits that field, not the whole shift.
    <div className="space-y-3 border-t border-gray-200/70 bg-black/[0.02] px-3 py-3 dark:border-gray-700/70 dark:bg-white/[0.02]">
      <div className={field}>
        <input
          autoFocus
          aria-label={t("extendedShiftNamePlaceholder")}
          placeholder={t("extendedShiftNamePlaceholder")}
          value={value.name}
          maxLength={40}
          onChange={(event) => onEdit({ ...value, name: event.target.value })}
          onKeyDown={(event) => { if (event.key === "Enter" && valid) save(); }}
          className="min-w-0 flex-1 bg-transparent px-3 text-sm outline-none placeholder:text-gray-400 dark:text-white"
        />
      </div>
      <div role="radiogroup" aria-label={t("extendedShiftTypes")} className="grid grid-cols-2 gap-1 rounded-lg bg-black/[0.04] p-0.5 dark:bg-white/[0.06]">
        {(["work", "rest"] as const).map((kind) => (
          <button
            key={kind} type="button" role="radio" aria-checked={value.kind === kind}
            onClick={() => onEdit({ ...value, kind, colorHex: kind === "rest" && value.kind !== "rest" ? REST_COLOR : value.colorHex })}
            className={`h-7 rounded-md text-xs transition-colors ${value.kind === kind ? "bg-background font-medium shadow-sm dark:bg-white/[0.14] dark:text-white" : "text-gray-500 hover:text-gray-900 dark:text-gray-400 dark:hover:text-white"}`}
          >
            {t(kind === "work" ? "extendedKindWork" : "extendedKindRest")}
          </button>
        ))}
      </div>
      {value.kind === "rest" ? (
        <p className="text-xs leading-5 text-gray-500 dark:text-gray-400">{t("extendedRestKindNote")}</p>
      ) : <>
        <div className="grid grid-cols-2 gap-3">
          <TimeSelector id={`type-start-${value.id}`} label={t("startTime")} value={minutesTime(value.startMinutes)} compact menuSide="auto" onChange={time("startMinutes")} />
          <TimeSelector id={`type-end-${value.id}`} label={t("endTime")} value={minutesTime(value.endMinutes)} compact menuSide="auto" onChange={time("endMinutes")} />
        </div>
        {value.endMinutes <= value.startMinutes && <p className="text-xs text-gray-500 dark:text-gray-400">{t("extendedOvernightNote")}</p>}
        <div className="flex items-center justify-between gap-3">
          <Label htmlFor={`type-break-${value.id}`} className="text-sm font-normal dark:text-gray-200">{t("extendedBreak")}</Label>
          <Switch id={`type-break-${value.id}`} checked={value.breakEnabled} onCheckedChange={(breakEnabled) => onEdit({ ...value, breakEnabled })} />
        </div>
        {value.breakEnabled && (
          <div className="grid grid-cols-[minmax(0,1fr)_112px] items-end gap-3">
            <TimeSelector id={`type-break-start-${value.id}`} label={t("extendedBreakStart")} value={minutesTime(value.breakStartMinutes)} compact menuSide="auto" onChange={time("breakStartMinutes")} />
            <div className="space-y-1.5">
              <Label htmlFor={`type-break-length-${value.id}`} className="text-xs text-gray-500 dark:text-gray-400">{t("extendedBreakDuration")}</Label>
              <div dir="ltr" className={field}>
                <input
                  id={`type-break-length-${value.id}`}
                  inputMode="numeric"
                  value={duration}
                  onChange={(event) => {
                    if (!/^\d{0,4}$/.test(event.target.value)) return;
                    setDuration(event.target.value);
                    const minutes = Number(event.target.value);
                    if (minutes >= 1 && minutes < 1440) onEdit({ ...value, breakDurationMinutes: minutes });
                  }}
                  onBlur={() => setDuration(String(value.breakDurationMinutes))}
                  className="min-w-0 flex-1 bg-transparent px-3 text-sm tabular-nums outline-none dark:text-white"
                />
                <span aria-hidden="true" className="flex shrink-0 items-center border-l border-input px-2 text-xs text-gray-500 dark:text-gray-400">{t("minutesUnit")}</span>
              </div>
            </div>
          </div>
        )}
        {!breakFits && <p role="alert" className="text-xs text-red-600 dark:text-red-400">{t("extendedBreakOutside")}</p>}
      </>}
      <div className="flex items-center justify-between gap-3">
        <span className="text-sm dark:text-gray-200">{t("extendedColor")}</span>
        <div role="radiogroup" aria-label={t("extendedColor")} className="flex gap-1.5">
          {swatches.map((color) => (
            <button
              key={color} type="button" role="radio" aria-checked={value.colorHex.toUpperCase() === color.toUpperCase()} aria-label={color}
              onClick={() => onEdit({ ...value, colorHex: color })}
              className={`h-4 w-4 rounded-full ring-offset-2 ring-offset-background transition-shadow ${value.colorHex.toUpperCase() === color.toUpperCase() ? "ring-2 ring-gray-400 dark:ring-gray-500" : ""}`}
              style={{ backgroundColor: color }}
            />
          ))}
        </div>
      </div>
      <div className="flex items-center gap-2 pt-1">
        {onDelete && (
          <Button type="button" variant="ghost" size="sm" disabled={inUse} title={inUse ? t("extendedShiftTypeInUse") : undefined} onClick={onDelete}
            className="h-8 px-2 text-red-600 hover:bg-red-500/10 hover:text-red-600 dark:text-red-400">
            {t("extendedDeleteShiftType")}
          </Button>
        )}
        <div className="ms-auto flex gap-2">
          <Button type="button" variant="outline" size="sm" className="h-8 rounded-lg" onClick={onCancel}>{t("cancelAction")}</Button>
          <Button type="button" size="sm" className="h-8 rounded-lg" disabled={!valid} onClick={save}>{t("saveAction")}</Button>
        </div>
      </div>
      {onDelete && inUse && <p className="text-xs leading-5 text-gray-500 dark:text-gray-400">{t("extendedShiftTypeInUse")}</p>}
    </div>
  );
}

/** iOS HolidayRegionPicker as an inline, searchable list inside the pattern card. */
function HolidayCalendarRow({ lang, region, onSelect }: { lang: string; region: string | null; onSelect: (region: string) => void }) {
  const { t } = useTranslation();
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [index, setIndex] = useState<HolidayIndex | null>(null);
  useEffect(() => {
    let cancelled = false;
    void loadHolidayIndex().then((value) => { if (!cancelled) setIndex(value); });
    return () => { cancelled = true; };
  }, []);
  const regions = useMemo(
    () => Object.keys(index?.regions ?? {})
      .map((id) => ({ id, name: holidayRegionName(id, lang) }))
      .sort((a, b) => a.name.localeCompare(b.name, lang)),
    [index, lang]
  );
  const suggested = suggestedHolidayRegion(index, typeof navigator === "undefined" ? lang : navigator.language);
  const featured = region || suggested;
  const search = query.trim().toLocaleLowerCase();
  const matches = regions.filter(({ id, name }) =>
    search ? name.toLocaleLowerCase().includes(search) || id.toLowerCase().includes(search) : id !== featured);
  const choose = (value: string) => { onSelect(value); setOpen(false); setQuery(""); };
  const row = (value: string, title: string) => (
    <button
      key={value || "off"} type="button" role="option" aria-selected={(region ?? "") === value}
      onClick={() => choose(value)}
      className="flex w-full items-center justify-between gap-2 rounded-md px-2 py-1.5 text-start text-sm transition-colors hover:bg-black/5 dark:text-gray-200 dark:hover:bg-white/10"
    >
      <span className="min-w-0 truncate">{title}</span>
      {(region ?? "") === value && <Check className="h-3.5 w-3.5 shrink-0 text-orange-500" />}
    </button>
  );
  return (
    <div className="mt-3 border-t border-gray-200/70 pt-3 dark:border-gray-700/70">
      <button
        type="button" aria-expanded={open} onClick={() => setOpen(!open)}
        className="flex w-full items-center justify-between gap-3 text-sm dark:text-gray-200"
      >
        <span className="shrink-0">{t("holidayCalendar")}</span>
        <span className="flex min-w-0 items-center gap-1 text-gray-500 dark:text-gray-400">
          <span className="truncate">{region ? holidayRegionName(region, lang) : t("holidayCalendarOff")}</span>
          <ChevronRight className={`h-4 w-4 shrink-0 transition-transform ${open ? "rotate-90" : "rtl:rotate-180"}`} />
        </span>
      </button>
      {open && (
        <div className="mt-2 space-y-1.5">
          <div className={field}>
            <input
              autoFocus
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              onKeyDown={(event) => { if (event.key === "Escape") { setOpen(false); setQuery(""); } }}
              placeholder={t("holidayCalendarSearch")}
              aria-label={t("holidayCalendarSearch")}
              className="min-w-0 flex-1 bg-transparent px-3 text-sm outline-none placeholder:text-gray-400 dark:text-white"
            />
          </div>
          <div role="listbox" aria-label={t("holidayCalendar")} className="desktop-scrollbar max-h-52 overflow-y-auto overscroll-contain">
            {!search && row("", t("holidayCalendarOff"))}
            {!search && featured && row(featured, featured === region
              ? holidayRegionName(featured, lang)
              : t("holidayCalendarSystemDefault", { region: holidayRegionName(featured, lang) }))}
            {!search && <div className="my-1 border-t border-gray-200/70 dark:border-gray-700/70" />}
            {matches.map(({ id, name }) => row(id, name))}
          </div>
        </div>
      )}
    </div>
  );
}
