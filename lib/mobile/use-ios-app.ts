import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  DEFAULT_MONTHLY_WORKING_DAYS,
  DEFAULT_WORKDAYS,
  buildShiftTimeline,
  calculateTimelinePayRatio,
  calculateTimelineProgress,
  extendShiftWithOvertime,
  findNextShiftTimeline,
  getActiveBreakEndAtMs,
  getDailySalary,
  getPlannedShiftDurationMs,
  getShiftBounds,
  getShiftDurationMs,
  getShiftEndAtMs,
  getShiftLengthHours,
  getShiftRemainingMs,
  getShiftStartAtMs,
  isWorkday,
  parseWorkdays,
  resolveOvertimeEndAtMs,
  serializeWorkdays,
  suggestOvertimeEndAtMs,
  type ShiftTimeline,
} from "@/lib/countdown";
import { startSecondTick } from "@/lib/second-tick";
import { startOfWeek, startOfYear, summarize } from "@/lib/summary";
import type { PeriodSummary } from "@/lib/summary";
import { applySavedTheme } from "@/lib/theme";
import type { Theme } from "@/components/ThemeToggle";

/**
 * Every rule the iPhone app runs on, with no view attached.
 *
 * The screens under `components/mobile/` are iOS controls, not the Web page in
 * a shell, so they cannot reuse `off-work-countdown.tsx` — but they must not
 * reimplement the schedule either. Shift maths stays in `lib/countdown.ts`;
 * this hook only holds the state, persists it under the **same** localStorage
 * keys the Web and Desktop builds use, and turns a tick into the phase the
 * screens render.
 */

export type NotificationMode = "off" | "simple" | "milestones";

/**
 * What the Timer screen is showing right now. One value, so a screen can never
 * end up in two states at once (lunch and overtime, say) the way a pile of
 * booleans can.
 */
export type ShiftPhase =
  | "idle"
  | "beforeShift"
  | "running"
  | "lunch"
  | "overtime"
  | "nextShift"
  | "done";

export interface IosAppSettings {
  startTime: string;
  endTime: string;
  workdays: number[];
  salaryType: "monthly" | "daily";
  salaryAmount: string;
  monthlyWorkingDays: string;
  showSalary: boolean;
  hideEarnings: boolean;
  lunchEnabled: boolean;
  lunchStartTime: string;
  lunchDurationMinutes: number;
  lunchStartNotificationEnabled: boolean;
  lunchEndNotificationEnabled: boolean;
  microBreakEnabled: boolean;
  microBreakIntervalMinutes: number;
  notificationMode: NotificationMode;
  liveActivityEnabled: boolean;
  liveActivityLeadMinutes: number;
  theme: Theme;
}

const DEFAULTS: IosAppSettings = {
  startTime: "09:00",
  endTime: "18:00",
  workdays: DEFAULT_WORKDAYS,
  salaryType: "monthly",
  salaryAmount: "",
  monthlyWorkingDays: DEFAULT_MONTHLY_WORKING_DAYS.toString(),
  showSalary: false,
  hideEarnings: false,
  lunchEnabled: false,
  lunchStartTime: "12:00",
  lunchDurationMinutes: 60,
  lunchStartNotificationEnabled: true,
  lunchEndNotificationEnabled: false,
  microBreakEnabled: false,
  microBreakIntervalMinutes: 60,
  notificationMode: "off",
  liveActivityEnabled: true,
  liveActivityLeadMinutes: 15,
  theme: "auto",
};

/** Live Activity lead times offered on the notifications screen. */
export const LIVE_ACTIVITY_LEAD_CHOICES = [5, 15, 30, 60] as const;

export const ONBOARDING_STORAGE_KEY = "mobileOnboardingSeen";

/**
 * A running countdown survives the app being closed.
 *
 * iOS terminates background apps routinely, and losing the countdown on every
 * cold start would make the app useless for the one thing it does. The shift
 * itself is not stored — it is rebuilt from the settings against the current
 * clock, which also advances it to today's shift automatically. Only the two
 * facts that cannot be derived are kept.
 */
const RUNNING_STORAGE_KEY = "mobileCountdownRunning";
const OVERTIME_STORAGE_KEY = "mobileOvertimeEndAtMs";

function readItem(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function writeItem(key: string, value: string) {
  try {
    localStorage.setItem(key, value);
  } catch {
    // A device with storage disabled still runs the countdown for this session.
  }
}

function readBoolean(key: string, fallback: boolean): boolean {
  const raw = readItem(key);
  return raw === null ? fallback : raw === "true";
}

function readNumber(
  key: string,
  fallback: number,
  isValid: (value: number) => boolean
): number {
  const parsed = Number(readItem(key));
  return Number.isFinite(parsed) && isValid(parsed) ? parsed : fallback;
}

function loadSettings(): IosAppSettings {
  const legacyReminder = readBoolean("reminder", false);
  const storedMode = readItem("desktopNotificationMode");
  const storedSalaryType = readItem("salaryType");
  const storedTheme = readItem("theme");
  const storedWorkingDays = readNumber(
    "monthlyWorkingDays",
    DEFAULT_MONTHLY_WORKING_DAYS,
    (value) => value > 0 && value <= 31
  );

  return {
    startTime: readItem("startTime") ?? DEFAULTS.startTime,
    endTime: readItem("endTime") ?? DEFAULTS.endTime,
    // An empty string means "no workdays at all" and must survive a reload;
    // only a missing key falls back to Monday–Friday.
    workdays: parseWorkdays(readItem("workdays")),
    salaryType: storedSalaryType === "daily" ? "daily" : "monthly",
    salaryAmount: readItem("salaryAmount") ?? "",
    monthlyWorkingDays: String(storedWorkingDays),
    showSalary: readBoolean("showSalary", false),
    hideEarnings: readBoolean("hideEarnings", false),
    lunchEnabled: readBoolean("lunchEnabled", false),
    lunchStartTime: readItem("lunchStartTime") ?? DEFAULTS.lunchStartTime,
    lunchDurationMinutes: readNumber(
      "lunchDurationMinutes",
      60,
      (value) => value > 0
    ),
    lunchStartNotificationEnabled: readBoolean(
      "lunchStartNotificationEnabled",
      true
    ),
    lunchEndNotificationEnabled: readBoolean(
      "lunchEndNotificationEnabled",
      false
    ),
    microBreakEnabled: readBoolean("microBreakEnabled", false),
    microBreakIntervalMinutes: readNumber(
      "microBreakIntervalMinutes",
      60,
      (value) => value > 0
    ),
    notificationMode:
      storedMode === "simple" || storedMode === "milestones"
        ? storedMode
        : legacyReminder
          ? "simple"
          : "off",
    liveActivityEnabled: readBoolean("liveActivityEnabled", true),
    liveActivityLeadMinutes: readNumber("liveActivityLeadMinutes", 15, (value) =>
      LIVE_ACTIVITY_LEAD_CHOICES.includes(
        value as (typeof LIVE_ACTIVITY_LEAD_CHOICES)[number]
      )
    ),
    theme:
      storedTheme === "light" ||
      storedTheme === "dark" ||
      storedTheme === "cyberpunk" ||
      storedTheme === "sunset"
        ? storedTheme
        : "auto",
  };
}

function persist(settings: IosAppSettings) {
  writeItem("startTime", settings.startTime);
  writeItem("endTime", settings.endTime);
  writeItem("workdays", serializeWorkdays(settings.workdays));
  writeItem("salaryType", settings.salaryType);
  writeItem("salaryAmount", settings.salaryAmount);
  writeItem("monthlyWorkingDays", settings.monthlyWorkingDays);
  writeItem("showSalary", String(settings.showSalary));
  writeItem("hideEarnings", String(settings.hideEarnings));
  writeItem("lunchEnabled", String(settings.lunchEnabled));
  writeItem("lunchStartTime", settings.lunchStartTime);
  writeItem("lunchDurationMinutes", String(settings.lunchDurationMinutes));
  writeItem(
    "lunchStartNotificationEnabled",
    String(settings.lunchStartNotificationEnabled)
  );
  writeItem(
    "lunchEndNotificationEnabled",
    String(settings.lunchEndNotificationEnabled)
  );
  writeItem("microBreakEnabled", String(settings.microBreakEnabled));
  writeItem(
    "microBreakIntervalMinutes",
    String(settings.microBreakIntervalMinutes)
  );
  writeItem("desktopNotificationMode", settings.notificationMode);
  // The Web build still reads the legacy boolean; keep the two in step so a
  // shared device does not lose the reminder when it switches builds.
  writeItem("reminder", String(settings.notificationMode !== "off"));
  writeItem("liveActivityEnabled", String(settings.liveActivityEnabled));
  writeItem(
    "liveActivityLeadMinutes",
    String(settings.liveActivityLeadMinutes)
  );
  writeItem("theme", settings.theme);
}

export interface IosShiftView {
  phase: ShiftPhase;
  /** The timeline the screen is describing; null before the first tick. */
  shift: ShiftTimeline | null;
  /** Remaining effective work time, or time until the break/next shift ends. */
  remainingMs: number;
  progress: number;
  /** Wall-clock end of the break currently in progress. */
  breakEndAtMs: number | null;
  plannedEndAtMs: number;
  overtimeEndAtMs: number | null;
  shiftStartAtMs: number;
  shiftEndAtMs: number;
  nextShiftStartAtMs: number | null;
  moneyEarned: number | null;
  week: PeriodSummary | null;
  year: PeriodSummary | null;
  /** Today falls on a configured workday. */
  todayIsWorkday: boolean;
}

export interface IosAppState {
  ready: boolean;
  settings: IosAppSettings;
  update: (patch: Partial<IosAppSettings>) => void;
  nowMs: number;
  started: boolean;
  view: IosShiftView;
  dailySalary: number | null;
  /** Shift length and lunch, from the settings alone — used before starting. */
  plannedShift: {
    hours: number;
    lunchMinutes: number;
    lunchFitsInShift: boolean;
  };
  start: () => void;
  stop: () => void;
  applyOvertime: (endTime: string) => boolean;
  suggestedOvertimeEnd: () => string;
}

const HOUR_MS = 60 * 60 * 1000;

export function useIosApp(): IosAppState {
  const [ready, setReady] = useState(false);
  const [settings, setSettings] = useState<IosAppSettings>(DEFAULTS);
  const [started, setStarted] = useState(false);
  const [activeShift, setActiveShift] = useState<ShiftTimeline | null>(null);
  const [nowMs, setNowMs] = useState(0);
  const persistedRef = useRef(false);

  useEffect(() => {
    const restored = loadSettings();
    setSettings(restored);

    if (readItem(RUNNING_STORAGE_KEY) === "true") {
      const now = new Date();
      const options = restored.lunchEnabled
        ? {
            breakStartTime: restored.lunchStartTime,
            breakDurationMinutes: restored.lunchDurationMinutes,
          }
        : {};
      let shift = buildShiftTimeline(
        restored.startTime,
        restored.endTime,
        now,
        options
      );
      const storedOvertime = Number(readItem(OVERTIME_STORAGE_KEY));
      // Overtime only belongs to the shift it was added to. One that already
      // ended must not be carried into tomorrow's.
      if (
        Number.isFinite(storedOvertime) &&
        storedOvertime > now.getTime() &&
        storedOvertime > shift.plannedEndAtMs
      ) {
        shift = extendShiftWithOvertime(shift, storedOvertime);
      }
      setActiveShift(shift);
      setStarted(true);
    }

    setReady(true);
  }, []);

  useEffect(() => {
    if (!ready) return;
    writeItem(RUNNING_STORAGE_KEY, String(started));
    writeItem(
      OVERTIME_STORAGE_KEY,
      activeShift?.overtimeEndAtMs !== null &&
        activeShift?.overtimeEndAtMs !== undefined
        ? String(activeShift.overtimeEndAtMs)
        : ""
    );
  }, [ready, started, activeShift]);

  // Persistence starts only once the stored values are in state. Writing on the
  // first commit would push the defaults back over what the user had saved.
  useEffect(() => {
    if (!ready) return;
    if (!persistedRef.current) {
      persistedRef.current = true;
      return;
    }
    persist(settings);
  }, [ready, settings]);

  // The theme is written to localStorage by `persist`, then applied from there
  // by the same helper the layout script and the route sync use — one document
  // state, not three that can drift apart.
  useEffect(() => {
    if (!ready) return;
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const sync = () => applySavedTheme(media.matches);
    sync();
    media.addEventListener("change", sync);
    return () => media.removeEventListener("change", sync);
  }, [ready, settings.theme]);

  // The first frame keeps `nowMs` at 0 so the static export and the hydrated
  // app agree; the clock starts on the effect that follows.
  useEffect(() => {
    const tick = () => {
      const now = new Date();
      setNowMs(now.getTime());
    };
    tick();
    return startSecondTick(tick);
  }, []);

  const update = useCallback((patch: Partial<IosAppSettings>) => {
    setSettings((current) => ({ ...current, ...patch }));
  }, []);

  const buildOptions = useMemo(
    () =>
      settings.lunchEnabled
        ? {
            breakStartTime: settings.lunchStartTime,
            breakDurationMinutes: settings.lunchDurationMinutes,
          }
        : {},
    [settings.lunchEnabled, settings.lunchStartTime, settings.lunchDurationMinutes]
  );

  const dailySalary = settings.showSalary
    ? getDailySalary(
        settings.salaryAmount,
        settings.salaryType,
        settings.monthlyWorkingDays.trim()
          ? Number(settings.monthlyWorkingDays)
          : undefined
      )
    : null;

  const plannedShift = useMemo(() => {
    const hours = getShiftLengthHours(settings.startTime, settings.endTime);
    // Ask the timeline whether it actually kept the break rather than
    // re-deriving the rule: `buildShiftTimeline` silently drops a break that
    // falls outside the shift, and a second copy of that rule could disagree.
    const probe = buildShiftTimeline(
      settings.startTime,
      settings.endTime,
      new Date(nowMs || Date.now()),
      buildOptions
    );
    return {
      hours,
      lunchMinutes: settings.lunchEnabled ? settings.lunchDurationMinutes : 0,
      lunchFitsInShift: !settings.lunchEnabled || probe.segments.length > 1,
    };
  }, [
    settings.startTime,
    settings.endTime,
    settings.lunchEnabled,
    settings.lunchDurationMinutes,
    buildOptions,
    nowMs,
  ]);

  const view = useMemo<IosShiftView>(() => {
    const empty: IosShiftView = {
      phase: "idle",
      shift: null,
      remainingMs: 0,
      progress: 0,
      breakEndAtMs: null,
      plannedEndAtMs: 0,
      overtimeEndAtMs: null,
      shiftStartAtMs: 0,
      shiftEndAtMs: 0,
      nextShiftStartAtMs: null,
      moneyEarned: null,
      week: null,
      year: null,
      todayIsWorkday: true,
    };

    if (!nowMs) return empty;

    const now = new Date(nowMs);
    const shift =
      activeShift ??
      buildShiftTimeline(
        settings.startTime,
        settings.endTime,
        now,
        buildOptions
      );
    const shiftStartAtMs = getShiftStartAtMs(shift);
    const shiftEndAtMs = getShiftEndAtMs(shift);
    const todayIsWorkday = isWorkday(
      new Date(
        activeShift
          ? shiftStartAtMs
          : getShiftBounds(
              settings.startTime,
              settings.endTime,
              now
            ).start.getTime()
      ),
      settings.workdays
    );

    const summariesFor = (progressPercent: number, payRatio: number) => {
      const common = {
        asOf: now,
        workdays: settings.workdays,
        currentShiftStart: new Date(shiftStartAtMs),
        currentShiftEnd: new Date(shiftEndAtMs),
        plannedDailyHours: getPlannedShiftDurationMs(shift) / HOUR_MS,
        todayProgress: progressPercent,
        dailySalary,
        todayEffectiveHours: getShiftDurationMs(shift) / HOUR_MS,
        todayPayRatio: payRatio,
      };
      return {
        week: summarize({ ...common, periodStart: startOfWeek(now) }),
        year: summarize({ ...common, periodStart: startOfYear(now) }),
      };
    };

    if (!started) {
      // The next shift is worth knowing before the countdown starts too — it is
      // the whole content of the "not a workday" screen.
      const upcoming = findNextShiftTimeline({
        startTime: settings.startTime,
        endTime: settings.endTime,
        workdays: settings.workdays,
        afterMs: todayIsWorkday ? Math.max(shiftEndAtMs, nowMs) : nowMs,
        options: buildOptions,
      });
      return {
        ...empty,
        shift,
        shiftStartAtMs,
        shiftEndAtMs,
        plannedEndAtMs: shift.plannedEndAtMs,
        nextShiftStartAtMs: upcoming ? getShiftStartAtMs(upcoming) : null,
        todayIsWorkday,
        // Nothing has been worked today yet, so today contributes nothing.
        ...summariesFor(0, 0),
      };
    }

    const progress = calculateTimelineProgress(shift, nowMs);
    const moneyEarned =
      dailySalary !== null
        ? dailySalary * calculateTimelinePayRatio(shift, nowMs)
        : null;

    const { week, year } = summariesFor(
      progress,
      calculateTimelinePayRatio(shift, nowMs)
    );

    const base = {
      ...empty,
      shift,
      progress,
      plannedEndAtMs: shift.plannedEndAtMs,
      overtimeEndAtMs: shift.overtimeEndAtMs,
      shiftStartAtMs,
      shiftEndAtMs,
      moneyEarned,
      week,
      year,
      todayIsWorkday,
    };

    if (shiftStartAtMs > nowMs) {
      return {
        ...base,
        phase: "beforeShift",
        remainingMs: shiftStartAtMs - nowMs,
        progress: 0,
      };
    }

    // A break wins over everything else: remaining work time is frozen, so the
    // screen has to say "on a break" rather than show a stalled number.
    const breakEndAtMs = getActiveBreakEndAtMs(shift, nowMs);
    if (breakEndAtMs !== null) {
      return {
        ...base,
        phase: "lunch",
        breakEndAtMs,
        remainingMs: getShiftRemainingMs(shift, nowMs),
      };
    }

    const remainingMs = getShiftRemainingMs(shift, nowMs);
    if (remainingMs > 0) {
      return {
        ...base,
        phase:
          shift.overtimeEndAtMs !== null && nowMs >= shift.plannedEndAtMs
            ? "overtime"
            : "running",
        remainingMs,
      };
    }

    const nextShift = findNextShiftTimeline({
      startTime: settings.startTime,
      endTime: settings.endTime,
      workdays: settings.workdays,
      afterMs: Math.max(shiftEndAtMs, nowMs),
      options: buildOptions,
    });
    const nextShiftStartAtMs = nextShift ? getShiftStartAtMs(nextShift) : null;

    return {
      ...base,
      phase:
        nextShiftStartAtMs !== null && nextShiftStartAtMs > nowMs
          ? "nextShift"
          : "done",
      progress: 100,
      remainingMs:
        nextShiftStartAtMs !== null ? Math.max(0, nextShiftStartAtMs - nowMs) : 0,
      nextShiftStartAtMs,
    };
  }, [
    nowMs,
    started,
    activeShift,
    settings.startTime,
    settings.endTime,
    settings.workdays,
    buildOptions,
    dailySalary,
  ]);

  const start = useCallback(() => {
    const now = new Date();
    setActiveShift(
      buildShiftTimeline(
        settings.startTime,
        settings.endTime,
        now,
        buildOptions
      )
    );
    setStarted(true);
  }, [settings.startTime, settings.endTime, buildOptions]);

  const stop = useCallback(() => {
    setStarted(false);
    setActiveShift(null);
  }, []);

  const applyOvertime = useCallback(
    (endTime: string) => {
      const shift = activeShift;
      if (!shift) return false;
      const endAtMs = resolveOvertimeEndAtMs(shift, endTime, Date.now());
      if (endAtMs === null) return false;
      const extended = extendShiftWithOvertime(shift, endAtMs);
      if (extended === shift) return false;
      setActiveShift(extended);
      return true;
    },
    [activeShift]
  );

  const suggestedOvertimeEnd = useCallback(() => {
    const suggested = new Date(
      activeShift
        ? suggestOvertimeEndAtMs(activeShift, Date.now())
        : Date.now() + HOUR_MS
    );
    return `${suggested.getHours().toString().padStart(2, "0")}:${suggested
      .getMinutes()
      .toString()
      .padStart(2, "0")}`;
  }, [activeShift]);

  return {
    ready,
    settings,
    update,
    nowMs,
    started,
    view,
    dailySalary,
    plannedShift,
    start,
    stop,
    applyOvertime,
    suggestedOvertimeEnd,
  };
}
