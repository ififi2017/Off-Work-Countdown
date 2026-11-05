import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { loadScheduleRuleOracle } from "./ios-schedule-rule-oracle.mjs";

// Differential fixtures for plan 019 R1–R3. The TypeScript oracle answers
// every case; AppTests/ScheduleRuleFixtureTests.swift holds ScheduleRules,
// ReminderRules and SummaryRules to the same values. Cases are one per line so
// a rule change reads as a diff.

const minute = 60_000;
const hour = 3_600_000;
const day = 86_400_000;

const hours = [
  { id: "day-lunch", startTime: "09:00", endTime: "17:00", breakStartTime: "12:00", breakDurationMinutes: 60 },
  { id: "day-no-break", startTime: "09:00", endTime: "18:00", breakStartTime: null, breakDurationMinutes: 0 },
  { id: "overnight", startTime: "22:00", endTime: "06:00", breakStartTime: "02:00", breakDurationMinutes: 30 },
  { id: "overnight-break-before-midnight", startTime: "20:00", endTime: "04:00", breakStartTime: "23:30", breakDurationMinutes: 45 },
  { id: "from-midnight", startTime: "00:00", endTime: "08:00", breakStartTime: "04:00", breakDurationMinutes: 15 },
  // 02:30 and 02:45 do not exist on a spring-forward night in most zones here.
  { id: "dst-gap-clock", startTime: "02:30", endTime: "10:30", breakStartTime: "02:45", breakDurationMinutes: 30 },
  { id: "full-day", startTime: "09:00", endTime: "09:00", breakStartTime: "13:00", breakDurationMinutes: 60 },
  { id: "break-past-end", startTime: "09:00", endTime: "17:00", breakStartTime: "16:45", breakDurationMinutes: 30 },
  { id: "late", startTime: "13:00", endTime: "23:59", breakStartTime: "18:00", breakDurationMinutes: 60 },
  { id: "zero-length-break", startTime: "05:30", endTime: "14:15", breakStartTime: "10:00", breakDurationMinutes: 0 },
];

const schedules = [
  { id: "weekdays", workdays: [1, 2, 3, 4, 5], schedule: { mode: "classic" } },
  { id: "no-workdays", workdays: [], schedule: { mode: "classic" } },
  { id: "weekends", workdays: [0, 6], schedule: { mode: "classic" } },
  { id: "tue-thu", workdays: [2, 4], schedule: { mode: "classic" } },
  { id: "alternating-single", workdays: [1, 2, 3, 4, 5], schedule: { mode: "alternating", referenceWeekStartMs: Date.UTC(2026, 0, 5, 3), referenceWeekType: "single", singleWeekendWorkday: 6 } },
  { id: "alternating-double-sunday", workdays: [1, 2, 3, 4, 5], schedule: { mode: "alternating", referenceWeekStartMs: Date.UTC(2025, 11, 28, 20), referenceWeekType: "double", singleWeekendWorkday: 0 } },
  { id: "rotation-4-2", workdays: [1, 2, 3, 4, 5], schedule: { mode: "rotation", rotationAnchorMs: Date.UTC(2026, 1, 10, 16), rotationWorkDays: 4, rotationRestDays: 2 } },
  { id: "rotation-1-1", workdays: [], schedule: { mode: "rotation", rotationAnchorMs: Date.UTC(2024, 10, 30, 1), rotationWorkDays: 1, rotationRestDays: 1 } },
  { id: "rotation-no-anchor", workdays: [3], schedule: { mode: "rotation", rotationWorkDays: 3, rotationRestDays: 4 } },
  { id: "manual", workdays: [1, 2, 3, 4, 5], schedule: { mode: "off" } },
];

const zones = [
  "Asia/Shanghai",
  "America/New_York",
  "Europe/Berlin",
  "Australia/Lord_Howe",
  "Asia/Kolkata",
  "America/Santiago",
  "Pacific/Chatham",
  "America/St_Johns",
  "UTC",
];

const salaries = [
  { salaryAmount: "", salaryType: "monthly", monthlyWorkingDays: 21.75, annualBonusMonths: 0 },
  { salaryAmount: "22000", salaryType: "monthly", monthlyWorkingDays: 22, annualBonusMonths: 2 },
  { salaryAmount: "500", salaryType: "daily", monthlyWorkingDays: 21.75, annualBonusMonths: 1.5 },
  { salaryAmount: " 1e4 ", salaryType: "monthly", monthlyWorkingDays: 20.83, annualBonusMonths: 0 },
  { salaryAmount: "abc", salaryType: "monthly", monthlyWorkingDays: 22, annualBonusMonths: 0 },
  { salaryAmount: "-1", salaryType: "daily", monthlyWorkingDays: 22, annualBonusMonths: 0 },
  { salaryAmount: "0x10", salaryType: "daily", monthlyWorkingDays: 0, annualBonusMonths: 0 },
  { salaryAmount: "12000", salaryType: "monthly", monthlyWorkingDays: 0, annualBonusMonths: 0 },
  { salaryAmount: "12000", salaryType: "monthly", monthlyWorkingDays: 31.5, annualBonusMonths: 0 },
  { salaryAmount: "12000.5", salaryType: "monthly", monthlyWorkingDays: 21.75, annualBonusMonths: -1 },
  { salaryAmount: ".5", salaryType: "daily", monthlyWorkingDays: 22, annualBonusMonths: 13 },
  { salaryAmount: "Infinity", salaryType: "daily", monthlyWorkingDays: 22, annualBonusMonths: 0 },
  { salaryAmount: "0b101", salaryType: "monthly", monthlyWorkingDays: 21.75, annualBonusMonths: 0 },
  { salaryAmount: "1_000", salaryType: "monthly", monthlyWorkingDays: 22, annualBonusMonths: 0 },
  { salaryAmount: "\t3000\n", salaryType: "monthly", monthlyWorkingDays: 22, annualBonusMonths: 0 },
  { salaryAmount: "5.", salaryType: "daily", monthlyWorkingDays: 22, annualBonusMonths: 0 },
];
// Keep the existing schedule samples stable; add overflow cases explicitly below.
const sampledSalaryCount = salaries.length;
salaries.push(
  { salaryAmount: "1e308", salaryType: "daily", monthlyWorkingDays: 22, annualBonusMonths: 36 },
  { salaryAmount: "1e308", salaryType: "daily", monthlyWorkingDays: 22, annualBonusMonths: 0 },
  { salaryAmount: "1e308", salaryType: "monthly", monthlyWorkingDays: 0.1, annualBonusMonths: 0 },
  { salaryAmount: "1e309", salaryType: "monthly", monthlyWorkingDays: 22, annualBonusMonths: 0 },
);

const milestoneKeys = ["milestone50", "milestone75", "milestone90", "milestone95", "milestone100"];
const milestoneRecord = (values) => Object.fromEntries(milestoneKeys.map((key, index) => [key, values[index]]));

// Copy is the caller's, so these probe the fallbacks rather than real wording:
// empty titles and pools, a blank template, `{{minutes}}` twice, a cycle-end
// summary that trims to nothing, and intervals that are off, negative, capped
// at 240 per segment, or ordinary.
const reminderInputs = [
  {
    mode: "milestones", fallbackTitle: "Reminder", breakTitle: "Break",
    milestoneTitles: milestoneRecord(["50%", "25% left", "10% left", "5% left", "Done"]),
    milestoneMessages: milestoneRecord([["Halfway", "半程了"], ["Three quarters"], ["Nearly", "快了", "Almost", "🚀 go"], [], ["Off", "收工"]]),
    lunchStartEnabled: true, lunchStartBody: "Lunch", lunchEndEnabled: true, lunchEndBody: "Back to it",
    microBreakEnabled: true, microBreakTitle: "Stretch", microBreakIntervalMinutes: 45,
    microBreakMessages: ["{{minutes}} min in", "", "Up {{minutes}} / {{minutes}}"], cycleEndSummaryBody: null,
  },
  {
    mode: "simple", fallbackTitle: "", breakTitle: "",
    milestoneTitles: milestoneRecord(["", "", "", "", "Off work"]),
    milestoneMessages: milestoneRecord([[], [], [], [], []]),
    lunchStartEnabled: false, lunchStartBody: "Lunch", lunchEndEnabled: true, lunchEndBody: "",
    microBreakEnabled: true, microBreakTitle: "", microBreakIntervalMinutes: 60,
    microBreakMessages: ["Move"], cycleEndSummaryBody: "  Cycle done  ",
  },
  {
    mode: "off", fallbackTitle: "Reminder", breakTitle: "Break",
    milestoneTitles: milestoneRecord(["a", "b", "c", "d", "e"]),
    milestoneMessages: milestoneRecord([["1"], ["2"], ["3"], ["4"], ["5"]]),
    lunchStartEnabled: true, lunchStartBody: "Lunch", lunchEndEnabled: false, lunchEndBody: "Back",
    microBreakEnabled: false, microBreakTitle: "Stretch", microBreakIntervalMinutes: 90,
    microBreakMessages: ["Move"], cycleEndSummaryBody: "",
  },
  {
    mode: "off", fallbackTitle: "", breakTitle: "休息",
    milestoneTitles: milestoneRecord(["", "", "", "", ""]),
    milestoneMessages: milestoneRecord([[], [], [], [], ["Done"]]),
    lunchStartEnabled: true, lunchStartBody: "午休开始", lunchEndEnabled: true, lunchEndBody: "午休结束",
    microBreakEnabled: true, microBreakTitle: "", microBreakIntervalMinutes: -5,
    microBreakMessages: ["Move"], cycleEndSummaryBody: "\t周期结束\n",
  },
  {
    mode: "milestones", fallbackTitle: "Reminder", breakTitle: "Break",
    milestoneTitles: milestoneRecord(["50", "75", "90", "95", "100"]),
    milestoneMessages: milestoneRecord([["x"], ["y", "z"], [""], ["w"], ["v", "u", "t"]]),
    lunchStartEnabled: false, lunchStartBody: "", lunchEndEnabled: false, lunchEndBody: "",
    microBreakEnabled: true, microBreakTitle: "Tick", microBreakIntervalMinutes: 1,
    microBreakMessages: ["{{minutes}}", "{{minute}}"], cycleEndSummaryBody: " ",
  },
  {
    mode: "simple", fallbackTitle: "Reminder", breakTitle: "Break",
    milestoneTitles: milestoneRecord(["50", "75", "90", "95", ""]),
    milestoneMessages: milestoneRecord([["x"], ["y"], ["z"], ["w"], ["Done", "Out"]]),
    lunchStartEnabled: true, lunchStartBody: "Lunch", lunchEndEnabled: true, lunchEndBody: "Back",
    microBreakEnabled: false, microBreakTitle: "Stretch", microBreakIntervalMinutes: 25,
    microBreakMessages: [], cycleEndSummaryBody: null,
  },
];

// Windows around 2026 DST transitions of the zones above (US, EU, Chile,
// Lord Howe's 30-minute shift, Chatham, Newfoundland).
const windows = [
  [Date.UTC(2026, 2, 5), Date.UTC(2026, 2, 12)],
  [Date.UTC(2026, 2, 27), Date.UTC(2026, 3, 7)],
  [Date.UTC(2026, 8, 2), Date.UTC(2026, 8, 9)],
  [Date.UTC(2026, 8, 25), Date.UTC(2026, 9, 6)],
  [Date.UTC(2026, 9, 23), Date.UTC(2026, 10, 3)],
];
const windowSpan = windows.reduce((total, [from, through]) => total + through - from, 0);
const profileCount = 40;
const strideSamples = 40;

const profiles = Array.from({ length: profileCount }, (_, index) => {
  const clock = hours[index % hours.length];
  const pattern = schedules[(index * 7 + 3) % schedules.length];
  const timeZoneIdentifier = zones[(index * 5 + 1) % zones.length];
  return {
    id: `${clock.id}/${pattern.id}/${timeZoneIdentifier}`,
    startTime: clock.startTime,
    endTime: clock.endTime,
    workdays: pattern.workdays,
    schedule: pattern.schedule,
    breakStartTime: clock.breakStartTime,
    breakDurationMinutes: clock.breakDurationMinutes,
    timeZoneIdentifier,
  };
});

const oracle = loadScheduleRuleOracle();
const call = (entry, value) => JSON.parse(oracle[entry](JSON.stringify(value)));

function instantAt(offset) {
  let remaining = ((offset % windowSpan) + windowSpan) % windowSpan;
  for (const [from, through] of windows) {
    if (remaining < through - from) return from + remaining;
    remaining -= through - from;
  }
  throw new Error("unreachable");
}

function rulesInput(profile, nowMs, extra = {}) {
  return {
    startTime: profile.startTime,
    endTime: profile.endTime,
    nowMs,
    workdays: profile.workdays,
    schedule: profile.schedule,
    breakStartTime: profile.breakStartTime,
    breakDurationMinutes: profile.breakDurationMinutes,
    overtimeEndAtMs: extra.overtimeEndAtMs ?? null,
    ...salaries[extra.salary ?? 0],
    forcedWorkdayStartMs: extra.forcedWorkdayStartMs ?? null,
    timeZoneIdentifier: profile.timeZoneIdentifier,
  };
}

function strideInstants(profileIndex) {
  // An irregular stride with a fractional millisecond on every third sample,
  // so both time-of-day coverage and sub-millisecond `nowMs` are exercised.
  const stride = 17 * hour + 37 * minute + 13_375;
  const phase = profileIndex * (5 * hour + 18 * minute);
  return Array.from({ length: strideSamples }, (_, k) =>
    instantAt(phase + k * stride) + (k % 3 === 1 ? 0.375 : 0)
  );
}

function boundaryInstants(profile) {
  const instants = [];
  for (const [from] of [windows[1], windows[4]]) {
    const base = call("snapshot", rulesInput(profile, from + 7 * hour));
    for (const value of [
      base.startAtMs - 1,
      base.startAtMs,
      base.segments[0]?.endAtMs,
      base.segments[1]?.startAtMs,
      base.plannedEndAtMs,
      base.endAtMs,
      base.nextShiftStartAtMs,
      base.countdownAnchorAtMs,
      base.nextRestAtMs,
    ]) {
      if (Number.isFinite(value) && !instants.includes(value)) instants.push(value);
    }
  }
  return instants;
}

function snapshotRow(snapshot) {
  return [
    snapshot.segments.map(({ startAtMs, endAtMs }) => [startAtMs, endAtMs]),
    snapshot.startAtMs,
    snapshot.endAtMs,
    snapshot.plannedEndAtMs,
    snapshot.overtimeEndAtMs,
    snapshot.durationMs,
    snapshot.plannedDurationMs,
    snapshot.elapsedMs,
    snapshot.remainingMs,
    snapshot.progress,
    snapshot.payRatio,
    snapshot.activeBreakEndAtMs,
    snapshot.isWorkday,
    snapshot.nextRestAtMs,
    snapshot.dailySalary,
    snapshot.earnedSoFar,
    snapshot.nextShiftStartAtMs,
    snapshot.nextShiftEndAtMs,
    snapshot.countdownTargetAtMs,
    snapshot.countdownAnchorAtMs,
    snapshot.countdownProgress,
  ];
}

function integer(value, label) {
  if (!Number.isInteger(value)) {
    throw new Error(`Digest input ${label} is not an integer: ${value}`);
  }
  return String(value);
}

function digest(lines) {
  return createHash("sha256").update(lines.join("")).digest("hex");
}

// Canonical line formats. ScheduleRuleFixtureTests.swift writes the same text.
function expansionLine(entry) {
  const segments = entry.segments
    .map(({ startAtMs, endAtMs }) => `${integer(startAtMs, "segment")}-${integer(endAtMs, "segment")}`)
    .join(",");
  return `${entry.dayKey}|${integer(entry.shiftAnchorStartAtMs, "anchor")}|${entry.isWorkday ? 1 : 0}|${segments}\n`;
}

function widgetLine(shift) {
  const segments = shift.segments
    .map(({ startAtMs, endAtMs }) => `${integer(startAtMs, "segment")}-${integer(endAtMs, "segment")}`)
    .join(",");
  const overtime = shift.overtimeEndAtMs == null ? "" : integer(shift.overtimeEndAtMs, "overtime");
  return `${segments}|${integer(shift.startAtMs, "start")}|${integer(shift.endAtMs, "end")}|${integer(shift.plannedEndAtMs, "planned")}|${overtime}|${integer(shift.durationMs, "duration")}|${integer(shift.countdownAnchorAtMs, "anchor")}\n`;
}

// Instants may be fractional here (overtime ending mid-millisecond), so they
// are written as `String(number)`, which Swift's shortest form matches.
function reminderLine(reminder) {
  const number = (value) => (value == null ? "" : String(value));
  const parts = [
    reminder.id,
    reminder.kind,
    number(reminder.atMs),
    number(reminder.expiresAtMs),
    number(reminder.maxTickGapMs),
    reminder.collapseGroup ?? "",
    reminder.title ?? "∅",
    reminder.body ?? "∅",
  ];
  if (parts.some((part) => /[|\n]/.test(part))) {
    throw new Error(`Reminder digest field contains a separator: ${JSON.stringify(reminder)}`);
  }
  return `${parts.join("|")}\n`;
}

// A fixed-seed generator, so lifetime-income cases are varied yet reproducible.
function seeded(seed) {
  let state = seed >>> 0;
  return () => (state = (Math.imul(state, 1_664_525) + 1_013_904_223) >>> 0) / 2 ** 32;
}

// Valid civil dates first; the tail is what `civilDay` must reject (a day that
// does not exist, a year `Date.UTC` reads as 19xx, a month 13, blanks, and an
// unpadded date).
const validCivilDates = ["2010-03-15", "2012-01-01", "2015-02-28", "2016-02-29", "2018-07-31", "2020-12-31", "2023-06-10", "2026-09-15", "2026-09-16", "2031-01-01", "2040-05-20", "2058-12-31"];
const civilDates = [...validCivilDates, "2026-02-30", "0099-06-01", "2026-13-01", "", "abc", "2026-9-1"];

function lifetimeIncomeCases() {
  const random = seeded(19);
  const pick = (list) => list[Math.floor(random() * list.length)];
  return Array.from({ length: 160 }, (_, i) => {
    // Sequential intervals by construction, then a few broken on purpose.
    const points = [...new Set(Array.from({ length: 1 + Math.floor(random() * 4) }, () => pick(validCivilDates)))].sort();
    const periods = points.slice(0, -1).map((startsOn, j) => ({
      startsOn,
      endsOn: j === points.length - 2 && random() < 0.3 ? null : points[j + 1],
      salaryAmount: pick([8000, 12500.5, 240000, 0, -10, 3333.33]),
      salaryCadence: pick(["monthly", "yearly"]),
    }));
    if (periods.length > 0 && random() < 0.2) periods[0].startsOn = pick(civilDates);
    if (periods.length > 1 && random() < 0.15) periods[1].endsOn = pick(civilDates);
    return {
      periods,
      currentSalary: random() < 0.6
        ? { salaryAmount: pick([15000, 180000, 9999.99, 0]), salaryCadence: pick(["monthly", "yearly"]), startsOn: random() < 0.5 ? null : pick(civilDates) }
        : null,
      futureIncomeDecline: random() < 0.45
        ? { startsOn: pick(civilDates), retirementRatio: pick([0, 0.35, 0.5, 1, 1.2, -0.1]) }
        : null,
      asOf: i % 20 === 7 ? pick(civilDates) : "2026-09-15",
      retirementOn: i % 25 === 3 ? pick(civilDates) : pick(["2046-09-15", "2058-12-31", "2031-01-01", "2020-01-01"]),
    };
  });
}


// Plan 024 phase 2 (`dailySalaryBasis`). Self-contained so the sections above
// keep their indices and bytes: every case carries its own scenario.
const monthBasisSalaries = [
  { salaryAmount: "22000", salaryType: "monthly", monthlyWorkingDays: 22, annualBonusMonths: 2, dailySalaryBasis: "scheduledMonth" },
  { salaryAmount: "12000.5", salaryType: "monthly", monthlyWorkingDays: 21.75, annualBonusMonths: 0, dailySalaryBasis: "scheduledMonth" },
  // The fixed divisor is unusable, but every month has its own.
  { salaryAmount: "9000", salaryType: "monthly", monthlyWorkingDays: 0, annualBonusMonths: 0, dailySalaryBasis: "scheduledMonth" },
  // A daily salary ignores the basis.
  { salaryAmount: "500", salaryType: "daily", monthlyWorkingDays: 22, annualBonusMonths: 1.5, dailySalaryBasis: "scheduledMonth" },
  { salaryAmount: "abc", salaryType: "monthly", monthlyWorkingDays: 22, annualBonusMonths: 0, dailySalaryBasis: "scheduledMonth" },
  { salaryAmount: " 18000 ", salaryType: "monthly", monthlyWorkingDays: 22, annualBonusMonths: 0, dailySalaryBasis: "fixed" },
];

const WORK_TYPE_ID = "11111111-1111-4111-8111-111111111111";
const REST_TYPE_ID = "22222222-2222-4222-8222-222222222222";

// A weekday holiday run and two makeup days laid over a weekday pattern.
const goldenWeek = {
  handSet: {
    "2026-09-27": "work",
    "2026-10-01": "rest", "2026-10-02": "rest", "2026-10-05": "rest", "2026-10-06": "rest", "2026-10-07": "rest",
    "2026-10-10": "work",
  },
};

const monthScenarios = [
  { id: "shanghai-weekdays", hours: hours[0], pattern: schedules[0], zone: "Asia/Shanghai" },
  { id: "new-york-weekdays", hours: hours[1], pattern: schedules[0], zone: "America/New_York" },
  { id: "berlin-weekends", hours: hours[0], pattern: schedules[2], zone: "Europe/Berlin" },
  { id: "lord-howe-rotation", hours: hours[0], pattern: schedules[6], zone: "Australia/Lord_Howe" },
  { id: "shanghai-overnight", hours: hours[2], pattern: schedules[0], zone: "Asia/Shanghai" },
  { id: "shanghai-manual", hours: hours[0], pattern: schedules[9], zone: "Asia/Shanghai" },
  { id: "utc-no-workdays", hours: hours[0], pattern: schedules[1], zone: "UTC" },
  { id: "shanghai-golden-week", hours: hours[0], pattern: schedules[0], zone: "Asia/Shanghai", extended: goldenWeek },
  { id: "santiago-tue-thu", hours: hours[0], pattern: schedules[3], zone: "America/Santiago" },
  { id: "kolkata-alternating", hours: hours[0], pattern: schedules[4], zone: "Asia/Kolkata" },
].map(({ id, hours: clock, pattern, zone, extended }) => ({
  id,
  startTime: clock.startTime,
  endTime: clock.endTime,
  workdays: pattern.workdays,
  schedule: pattern.schedule,
  breakStartTime: clock.breakStartTime,
  breakDurationMinutes: clock.breakDurationMinutes,
  timeZoneIdentifier: zone,
  extended: extended ?? null,
}));

function monthExtendedPlan(extended) {
  if (!extended) return null;
  const type = (id, name, kind) => ({
    id, name, kind, startMinutes: 540, endMinutes: 1020, breakEnabled: true, breakStartMinutes: 720,
    breakDurationMinutes: 60, colorHex: "#3366CC", isArchived: false, annualDateRange: null,
  });
  return {
    shiftTypes: [type(WORK_TYPE_ID, "Day", "work"), type(REST_TYPE_ID, "Rest", "rest")],
    rule: null,
    handSetDays: Object.fromEntries(Object.entries(extended.handSet).map(([key, kind]) => [key, kind === "work" ? WORK_TYPE_ID : REST_TYPE_ID])),
    fallsBackToBaseSchedule: true,
  };
}

function monthRules(scenario, nowMs, salary) {
  const plan = monthExtendedPlan(scenario.extended);
  return {
    startTime: scenario.startTime,
    endTime: scenario.endTime,
    nowMs,
    workdays: scenario.workdays,
    schedule: plan ? { ...scenario.schedule, extendedSchedule: plan } : scenario.schedule,
    breakStartTime: scenario.breakStartTime,
    breakDurationMinutes: scenario.breakDurationMinutes,
    overtimeEndAtMs: null,
    ...monthBasisSalaries[salary],
    forcedWorkdayStartMs: null,
    timeZoneIdentifier: scenario.timeZoneIdentifier,
  };
}

// Month ends and starts, a shift that begins in one month and ends in the next,
// and the days around the golden-week holiday and makeup days.
const monthInstants = [
  Date.UTC(2026, 1, 28, 4), Date.UTC(2026, 2, 1, 5), Date.UTC(2026, 7, 31, 15), Date.UTC(2026, 8, 1, 2),
  Date.UTC(2026, 8, 30, 4), Date.UTC(2026, 9, 1, 4), Date.UTC(2026, 9, 9, 4), Date.UTC(2026, 9, 10, 4),
];

function monthBasisFixtures() {
  const snapshots = [];
  const summaries = [];
  const recordsIncome = [];
  const monthlyEquivalent = [];
  const monthCounts = [];

  monthScenarios.forEach((scenario, sc) => {
    monthInstants.forEach((nowMs, k) => {
      monthBasisSalaries.forEach((_, s) => {
        const snapshot = call("snapshot", monthRules(scenario, nowMs, s));
        snapshots.push({ sc, s, now: nowMs, expected: [snapshot.dailySalary, snapshot.earnedSoFar, snapshot.payRatio, snapshot.startAtMs, snapshot.isWorkday] });
      });

      const salaryIndex = (sc + k) % 4 === 3 ? 5 : (sc + k) % 3;
      const snapshot = call("snapshot", monthRules(scenario, nowMs, salaryIndex));
      const row = monthBasisSalaries[salaryIndex];
      const asOfMs = k % 4 === 3 ? nowMs + 2 * day + 5 * hour : nowMs;
      const rules = monthRules(scenario, nowMs, salaryIndex);
      const input = {
        period: k % 3 === 1 ? "year" : "week",
        // A window that begins in an earlier month than it ends.
        ...(k % 3 !== 1 ? { periodStartMs: asOfMs - (k % 2 === 0 ? 40 : 11) * day - 7 * hour } : {}),
        asOfMs,
        workdays: scenario.workdays,
        schedule: scenario.schedule,
        currentShiftStartMs: snapshot.startAtMs,
        currentShiftEndMs: snapshot.endAtMs,
        plannedDailyHours: snapshot.plannedDurationMs / hour,
        todayProgress: Math.min(100, snapshot.progress),
        dailySalary: snapshot.dailySalary,
        salary: { amount: row.salaryAmount, type: row.salaryType, monthlyWorkingDays: row.monthlyWorkingDays, annualBonusMonths: row.annualBonusMonths, basis: row.dailySalaryBasis },
        todayEffectiveHours: snapshot.durationMs / hour,
        todayPayRatio: snapshot.payRatio,
        timeZoneIdentifier: scenario.timeZoneIdentifier,
      };
      const oracleInput = { ...input, schedule: rules.schedule };
      summaries.push({ sc, input, expected: call("summarize", oracleInput) });
    });

    const anchors = [Date.UTC(2026, 1, 10, 4), Date.UTC(2026, 7, 12, 4), Date.UTC(2026, 8, 14, 4), Date.UTC(2026, 9, 20, 4)];
    const months = [[], [{ anchorMs: anchors[0], count: 12 }], [{ anchorMs: anchors[1], count: 3 }, { anchorMs: anchors[2], count: 9 }, { anchorMs: anchors[3], count: 20 }], [{ anchorMs: anchors[2], count: -4 }, { anchorMs: anchors[3], count: 2 }]];
    monthBasisSalaries.forEach((_, s) => {
      months.forEach((completedByMonth, m) => {
        const completedWorkdays = completedByMonth.reduce((total, entry) => total + entry.count, 0);
        recordsIncome.push({
          sc, s, m, completedWorkdays, completedByMonth,
          expected: call("recordsIncome", { ...monthRules(scenario, 0, s), completedWorkdays, completedByMonth }).earnings,
        });
      });
      for (const type of ["monthly", "daily"]) {
        if (sc !== 0) continue;
        monthlyEquivalent.push({
          s, type,
          expected: call("salaryMonthlyEquivalent", { ...monthRules(scenario, 0, s), salaryType: type }).amount,
        });
      }
    });

    for (let month = 0; month < 12; month += 1) {
      const anchorMs = Date.UTC(2026, month, 1, 12);
      monthCounts.push({
        sc, anchorMs,
        expected: call("scheduledWorkdaysInMonth", { anchorMs, workdays: scenario.workdays, schedule: monthRules(scenario, 0, 0).schedule, timeZoneIdentifier: scenario.timeZoneIdentifier }).count,
      });
    }
  });

  return { scenarios: monthScenarios, salaries: monthBasisSalaries, snapshots, summaries, recordsIncome, monthlyEquivalent, monthCounts };
}

// Plan 024 phase 3 (`overtimePayMultiplier`). Self-contained, like the month
// basis section, so older sections keep their indices and bytes.
const overtimeMultipliers = [0, 0.5, 1, 1.5, 2, 2.7, 5, 0.3, 5.1, -1, 1.55];
const overtimeSalaries = [
  { salaryAmount: "500", salaryType: "daily", monthlyWorkingDays: 22, annualBonusMonths: 0, dailySalaryBasis: "fixed" },
  { salaryAmount: "22000", salaryType: "monthly", monthlyWorkingDays: 22, annualBonusMonths: 2, dailySalaryBasis: "fixed" },
  { salaryAmount: "", salaryType: "monthly", monthlyWorkingDays: 22, annualBonusMonths: 0, dailySalaryBasis: "fixed" },
];
const overtimeScenarios = [
  { id: "day-no-lunch", ...hours[1], zone: "Asia/Shanghai", base: Date.UTC(2026, 10, 4, 3) },
  { id: "day-lunch", ...hours[0], zone: "Asia/Shanghai", base: Date.UTC(2026, 10, 4, 6) },
  { id: "overnight-shift", ...hours[2], zone: "Asia/Shanghai", base: Date.UTC(2026, 10, 4, 15) },
  { id: "new-york-lunch", ...hours[0], zone: "America/New_York", base: Date.UTC(2026, 10, 4, 18) },
].map(({ id, startTime, endTime, breakStartTime, breakDurationMinutes, zone, base }) => ({
  id, startTime, endTime, breakStartTime, breakDurationMinutes, zone, base,
  workdays: [0, 1, 2, 3, 4, 5, 6], schedule: { mode: "classic" },
}));

function overtimeRules(scenario, nowMs, salary, extra = {}) {
  return {
    startTime: scenario.startTime,
    endTime: scenario.endTime,
    nowMs,
    workdays: scenario.workdays,
    schedule: scenario.schedule,
    breakStartTime: scenario.breakStartTime,
    breakDurationMinutes: scenario.breakDurationMinutes,
    overtimeEndAtMs: extra.overtimeEndAtMs ?? null,
    ...overtimeSalaries[salary],
    forcedWorkdayStartMs: null,
    timeZoneIdentifier: scenario.zone,
    ...(extra.overtimePayMultiplier === undefined ? {} : { overtimePayMultiplier: extra.overtimePayMultiplier }),
  };
}

function overtimePayFixtures() {
  const snapshots = [];
  const forecasts = [];
  const normalize = [0, 0.5, 0.1, 0.4, 0.6, 1, 1.5, 2.5, 3.14, 4.9, 5, 5.01, 5.1, 10, -0.5, -1, 1e-9, 0.30000000000000004, 0.1 + 0.2 + 1.2, null, 0.05]
    .map((value) => ({ value, expected: call("normalizeOvertimePayMultiplier", { value }).value }));

  overtimeScenarios.forEach((scenario, sc) => {
    const planned = call("snapshot", overtimeRules(scenario, scenario.base, 0));
    const plannedEnd = planned.plannedEndAtMs;
    for (const otMinutes of [45, 180, 540]) {
      const ot = plannedEnd + otMinutes * minute;
      const offsets = [-30 * minute, 0, 20 * minute, otMinutes * minute / 2, otMinutes * minute - 1, otMinutes * minute];
      overtimeSalaries.forEach((_, s) => {
        overtimeMultipliers.forEach((m, mi) => {
          // Not every combination: rotate the offsets so the file stays small
          // while each multiplier meets every salary, length and offset.
          offsets.forEach((offset, oi) => {
            if ((mi + oi + s) % 2 !== 0 && otMinutes !== 180) return;
            const nowMs = plannedEnd + offset + (oi % 2 === 1 ? 0.25 : 0);
            const rules = overtimeRules(scenario, nowMs, s, { overtimeEndAtMs: ot, overtimePayMultiplier: m });
            const snapshot = call("snapshot", rules);
            const extra = call("overtimePay", rules);
            snapshots.push({
              sc, s, m, ot, now: nowMs,
              expected: {
                dailySalary: snapshot.dailySalary, earnedSoFar: snapshot.earnedSoFar, payRatio: snapshot.payRatio,
                overtimeElapsedMs: extra.overtimeElapsedMs, comparison: extra.comparison,
              },
            });
          });
        });
      });
    }
    // Overtime beyond the declared end, and no overtime at all.
    for (const m of [0, 1.5]) {
      const rules = overtimeRules(scenario, plannedEnd + hour, 0, { overtimePayMultiplier: m });
      const snapshot = call("snapshot", rules);
      const extra = call("overtimePay", rules);
      snapshots.push({ sc, s: 0, m, ot: null, now: plannedEnd + hour, expected: {
        dailySalary: snapshot.dailySalary, earnedSoFar: snapshot.earnedSoFar, payRatio: snapshot.payRatio,
        overtimeElapsedMs: extra.overtimeElapsedMs, comparison: extra.comparison,
      } });
    }

    // Records: scheduled / corrected / observed days with declared overtime,
    // one running day whose overtime reaches past "now".
    for (const kind of ["scheduled", "corrected", "observed"]) {
      for (const m of [undefined, 0, 1, 1.5, 3]) {
        for (const asOfOffset of [-90 * minute, 5 * hour]) {
          const segments = planned.segments;
          const first = segments[0];
          const last = segments[segments.length - 1];
          const input = {
            days: [{
              dayKey: "2026-11-04",
              actualKind: kind,
              resolvedSegments: segments,
              plannedSegments: segments,
              overtimeSegments: [
                { startAtMs: last.endAtMs, endAtMs: last.endAtMs + 90 * minute },
                { startAtMs: last.endAtMs + 60 * minute, endAtMs: last.endAtMs + 150 * minute },
              ],
              ...(m === undefined ? {} : { overtimePayMultiplier: m }),
              observations: kind === "observed"
                ? [{ kind: "started", occurredAtMs: first.startAtMs + 5 * minute }, { kind: "stopped", occurredAtMs: last.endAtMs - 10 * minute }]
                : [],
              isActiveAnchor: asOfOffset < 0,
            }],
            periodDayKeys: ["2026-11-04"],
            dailySalary: call("snapshot", overtimeRules(scenario, scenario.base, 0)).dailySalary,
            asOfMs: last.endAtMs + asOfOffset,
            salaryRules: overtimeRules(scenario, last.endAtMs + asOfOffset, 0),
          };
          forecasts.push({ sc, input, expected: call("recordsActualForecast", input) });
        }
      }
    }
  });

  return { multipliers: overtimeMultipliers, salaries: overtimeSalaries, scenarios: overtimeScenarios, normalize, snapshots, forecasts };
}

// Plan 024 phase 4 (`overtimeStartAtMs`, `countedMs`). Self-contained, like the
// sections before it, so older sections keep their indices and bytes.
function overtimeStartFixtures() {
  const snapshots = [];
  const forecasts = [];
  const multipliers = [1, 0, 1.5];
  const salaryIndexes = [0, 1];
  const normalizeCounted = [0, 1, 30 * minute, 90 * minute, 24 * hour, 24 * hour + 1, 25 * hour, -1, -0.5, 0.5, 1e-9, NaN, null]
    .map((value) => ({ value, expected: call("normalizeCountedOvertimeMs", { value }).value }));
  const scales = [];
  for (const fullMs of [0, 1, 45 * minute, 90 * minute, 3 * hour, 9 * hour, -hour]) {
    for (const countedMs of [null, 0, 15 * minute, 45 * minute, 90 * minute, 2.5 * hour, 24 * hour, 25 * hour, -1]) {
      scales.push({ fullMs, countedMs, expected: call("overtimeCountScale", { fullMs, countedMs }).value });
    }
  }

  overtimeScenarios.forEach((scenario, sc) => {
    const planned = call("snapshot", overtimeRules(scenario, scenario.base, 0));
    const plannedEnd = planned.plannedEndAtMs;
    for (const otMinutes of [45, 180, 540]) {
      const ot = plannedEnd + otMinutes * minute;
      // Rest before the overtime; null/-30/0 stretch the last segment, a start
      // at or past the end does too; the rest append a segment.
      const starts = [null, -30, 0, 15, 30, 45, 60, otMinutes, otMinutes + 30];
      starts.forEach((restMinutes, ri) => {
        const st = restMinutes === null ? null : plannedEnd + restMinutes * minute;
        const offsets = [-30 * minute, 0, 10 * minute, 20 * minute, 40 * minute, otMinutes * minute / 2, otMinutes * minute - 1, otMinutes * minute];
        offsets.forEach((offset, oi) => {
          salaryIndexes.forEach((s, si) => {
            const m = multipliers[(ri + oi + si) % multipliers.length];
            const nowMs = plannedEnd + offset + (oi % 2 === 1 ? 0.25 : 0);
            const rules = overtimeRules(scenario, nowMs, s, { overtimeEndAtMs: ot, overtimePayMultiplier: m });
            if (st !== null) rules.overtimeStartAtMs = st;
            const snapshot = call("snapshot", rules);
            const extra = call("overtimePay", rules);
            snapshots.push({
              sc, s, m, ot, st, now: nowMs,
              expected: {
                segments: snapshot.segments, durationMs: snapshot.durationMs, elapsedMs: snapshot.elapsedMs,
                remainingMs: snapshot.remainingMs, progress: snapshot.progress, payRatio: snapshot.payRatio,
                activeBreakEndAtMs: snapshot.activeBreakEndAtMs, dailySalary: snapshot.dailySalary,
                earnedSoFar: snapshot.earnedSoFar, overtimeElapsedMs: extra.overtimeElapsedMs, comparison: extra.comparison,
              },
            });
          });
        });
      });
    }

    // Records: counted hours against measured overtime, with and without a gap
    // before the overtime, for scheduled / corrected / observed days.
    for (const kind of ["scheduled", "corrected", "observed"]) {
      for (const counted of [undefined, null, 0, 30 * minute, 90 * minute, 4 * hour, 24 * hour, 25 * hour, -1]) {
        for (const multiplier of [undefined, 1.5, 0]) {
          for (const [gap, length] of [[0, 90], [30, 90], [45, 150]]) {
            for (const asOfOffset of [-90 * minute, 20 * minute, 5 * hour]) {
              const segments = planned.segments;
              const first = segments[0];
              const last = segments[segments.length - 1];
              const input = {
                days: [{
                  dayKey: "2026-11-04",
                  actualKind: kind,
                  resolvedSegments: segments,
                  plannedSegments: segments,
                  overtimeSegments: [{ startAtMs: last.endAtMs + gap * minute, endAtMs: last.endAtMs + (gap + length) * minute }],
                  ...(multiplier === undefined ? {} : { overtimePayMultiplier: multiplier }),
                  ...(counted === undefined ? {} : { overtimeCountedMs: counted }),
                  observations: kind === "observed"
                    ? [{ kind: "started", occurredAtMs: first.startAtMs + 5 * minute }, { kind: "stopped", occurredAtMs: last.endAtMs - 10 * minute }]
                    : [],
                  isActiveAnchor: asOfOffset < 0,
                }],
                periodDayKeys: ["2026-11-04"],
                dailySalary: call("snapshot", overtimeRules(scenario, scenario.base, 0)).dailySalary,
                asOfMs: last.endAtMs + asOfOffset,
                salaryRules: overtimeRules(scenario, last.endAtMs + asOfOffset, 0),
              };
              forecasts.push({ sc, input, expected: call("recordsActualForecast", input) });
            }
          }
        }
      }
    }
  });

  return { multipliers, salaries: overtimeSalaries, scenarios: overtimeScenarios, normalizeCounted, scales, snapshots, forecasts };
}

/**
 * The fixture body as JSON text. iOS embeds it in Swift (below); Android
 * copies it verbatim (scripts/generate-android-rule-fixtures.mjs), so both
 * ports are held to the same cases.
 */
export function createScheduleRuleFixtureJson() {
  const snapshots = [];
  const watch = [];
  const widgetShifts = [];
  const widgetDigests = [];
  const expansions = [];
  const expansionDigests = [];
  const validateBreak = [];
  const reminders = [];
  const applyToday = [];
  const actualForecast = [];

  // The "This week" incident (fa927fb): on a Wednesday afternoon the timer
  // credited 2.5 days of pay while a second, Swift-only formula counted 2.
  // Rows 0 and 1, so ScheduleRuleFixtureTests can name them; manual mode must
  // still count today even though it counts no finished days.
  const weekIncident = {
    period: "week",
    asOfMs: Date.UTC(2026, 6, 1, 5),
    workdays: [1, 2, 3, 4, 5],
    schedule: { mode: "classic" },
    currentShiftStartMs: Date.UTC(2026, 6, 1, 1),
    currentShiftEndMs: Date.UTC(2026, 6, 1, 10),
    plannedDailyHours: 9,
    todayProgress: 50,
    dailySalary: 1000,
    todayEffectiveHours: 9,
    todayPayRatio: 0.5,
    timeZoneIdentifier: "Asia/Shanghai",
  };
  const summaries = [weekIncident, { ...weekIncident, schedule: { mode: "off" } }]
    .map((input) => ({ input, expected: call("summarize", input) }));

  profiles.forEach((profile, p) => {
    const stride = strideInstants(p);
    const instants = [...stride, ...boundaryInstants(profile)];

    instants.forEach((nowMs, k) => {
      const salary = (p * 3 + k) % sampledSalaryCount;
      const base = call("snapshot", rulesInput(profile, nowMs, { salary }));
      const overtimeEndAtMs = k % 5 === 2
        ? base.plannedEndAtMs + (37 + (k % 4) * 53) * minute
        : null;
      const forcedWorkdayStartMs = k % 7 === 3 ? nowMs - (k % 3) * day : null;
      const expected = overtimeEndAtMs == null && forcedWorkdayStartMs == null
        ? base
        : call("snapshot", rulesInput(profile, nowMs, { salary, overtimeEndAtMs, forcedWorkdayStartMs }));
      snapshots.push({ p, s: salary, now: nowMs, ot: overtimeEndAtMs, forced: forcedWorkdayStartMs, expected: snapshotRow(expected) });

      if (k % 2 === 0) {
        const j = watch.length;
        const configured = j % 4 !== 1;
        const running = j % 3 !== 2;
        const current = j % 5 === 0
          ? { segments: expected.segments, plannedEndAtMs: expected.plannedEndAtMs, overtimeEndAtMs: expected.overtimeEndAtMs }
          : null;
        const finished = j % 10 === 0
          ? expected.startAtMs + 2.5 * hour
          : j % 6 === 4
            ? nowMs - 10 * minute
            : j % 8 === 3
              ? 0
              : null;
        const input = rulesInput(profile, nowMs, { overtimeEndAtMs, forcedWorkdayStartMs });
        const request = { rules: input, scheduleConfigured: configured, isRunning: running };
        if (current) request.currentShift = current;
        if (finished != null) request.finishedAtMs = finished;
        watch.push({ p, now: nowMs, ot: overtimeEndAtMs, forced: forcedWorkdayStartMs, configured, running, current, finished, expected: call("watchProjection", request) });
      }
    });

    stride.slice(0, 6).forEach((nowMs, k) => {
      const variants = [
        [profile.breakStartTime, profile.breakDurationMinutes, null],
        ["11:00", 0, null],
        [null, 30, null],
        ["23:00", 120, null],
        ["08:59", 1, null],
        [profile.breakStartTime, profile.breakDurationMinutes, nowMs + 5 * hour],
      ];
      const [breakStartTime, breakDurationMinutes, overtimeEndAtMs] = variants[k];
      const input = { ...rulesInput(profile, nowMs, { overtimeEndAtMs }), breakStartTime, breakDurationMinutes };
      validateBreak.push({ p, now: nowMs, breakStartTime, breakDurationMinutes, ot: overtimeEndAtMs, expected: oracle.validateBreak(JSON.stringify(input)) });
    });

    // Lists run long (a one-minute interval fills 240 per segment), so every
    // case is compared by digest and the short ones also carry their rows.
    stride.filter((_, k) => k % 5 === 0).forEach((nowMs, k) => {
      const v = (p + k) % reminderInputs.length;
      const plannedEndAtMs = call("snapshot", rulesInput(profile, nowMs)).plannedEndAtMs;
      const ot = k % 4 === 1
        ? plannedEndAtMs + 50 * minute
        : k % 4 === 3
          ? plannedEndAtMs + 83 * minute + 0.25
          : null;
      const forced = k % 3 === 2 ? nowMs : null;
      const list = call("reminders", {
        ...rulesInput(profile, nowMs, { overtimeEndAtMs: ot, forcedWorkdayStartMs: forced }),
        reminderInputs: reminderInputs[v],
      });
      const row = { p, v, now: nowMs, ot, forced, count: list.length, sha256: digest(list.map(reminderLine)) };
      if ((k % 2 === 0 || ot % 1 !== 0) && list.length <= 40) {
        row.expected = list.map((r) => [r.id, r.kind, r.atMs, r.expiresAtMs, r.maxTickGapMs, r.collapseGroup, r.title, r.body]);
      }
      reminders.push(row);
    });

    stride.slice(0, 10).forEach((nowMs, k) => {
      const c = (p * 11 + k * 7 + 1) % profiles.length;
      const forced = k % 8 === 1 ? nowMs : k % 8 === 5 ? nowMs - day : null;
      const current = rulesInput(profile, nowMs, { forcedWorkdayStartMs: forced });
      // Another profile's hours and pattern, edited by the same user in the same zone.
      const candidate = {
        ...rulesInput(profiles[c], nowMs, { forcedWorkdayStartMs: forced }),
        timeZoneIdentifier: profile.timeZoneIdentifier,
      };
      const request = { current, candidate, kind: k % 2 === 0 ? "schedule" : "lunch", schedulePatternChanged: k % 3 === 0 };
      applyToday.push({ p, c, now: nowMs, forced, expected: oracle.shouldPromptApplyToday(JSON.stringify(request)) });
    });

    // Summaries are fed from a live snapshot, exactly as ShiftSession.periodSummary
    // feeds them, including a snapshot left stale two days later.
    stride.slice(0, 8).forEach((nowMs, k) => {
      const salary = (p + k * 5) % sampledSalaryCount;
      const overtimeEndAtMs = k % 4 === 2 ? call("snapshot", rulesInput(profile, nowMs)).plannedEndAtMs + 70 * minute : null;
      const snapshot = call("snapshot", rulesInput(profile, nowMs, { salary, overtimeEndAtMs }));
      const asOfMs = k % 6 === 5 ? nowMs + 2 * day + 5 * hour : nowMs;
      const workdays = k % 5 === 4
        ? [...new Set([...profile.workdays, new Date(snapshot.startAtMs).getUTCDay()])].sort((a, b) => a - b)
        : profile.workdays;
      const input = {
        period: k % 3 === 1 ? "year" : "week",
        ...(k % 3 === 2 ? { periodStartMs: asOfMs - (3 + (k % 4)) * day - 7 * hour } : {}),
        asOfMs,
        workdays,
        schedule: profile.schedule,
        currentShiftStartMs: snapshot.startAtMs,
        currentShiftEndMs: snapshot.endAtMs,
        plannedDailyHours: snapshot.plannedDurationMs / hour,
        todayProgress: Math.min(100, snapshot.progress),
        dailySalary: snapshot.dailySalary,
        todayEffectiveHours: snapshot.durationMs / hour,
        todayPayRatio: snapshot.payRatio,
        timeZoneIdentifier: profile.timeZoneIdentifier,
      };
      summaries.push({ input, expected: call("summarize", input) });
    });

    {
      const nowMs = stride[5];
      const overtimeEndAtMs = p % 3 === 0 ? call("snapshot", rulesInput(profile, nowMs)).plannedEndAtMs + 90 * minute : null;
      const maximum = p === 0 ? 0 : p === 1 ? 1 : 8;
      const through = nowMs + 9 * day;
      const request = { rules: rulesInput(profile, nowMs, { overtimeEndAtMs }), throughMs: through, maximumCount: maximum };
      widgetShifts.push({ p, now: nowMs, ot: overtimeEndAtMs, through, max: maximum, expected: call("widgetShifts", request) });
    }
    {
      const nowMs = Math.floor(stride[7]);
      const through = nowMs + 120 * day;
      const shifts = call("widgetShifts", { rules: rulesInput(profile, nowMs), throughMs: through, maximumCount: 400 });
      widgetDigests.push({ p, now: nowMs, through, max: 400, count: shifts.length, sha256: digest(shifts.map(widgetLine)) });
    }

    const expansionRequest = (fromMs, throughMs) => ({
      startTime: profile.startTime,
      endTime: profile.endTime,
      workdays: profile.workdays,
      schedule: profile.schedule,
      breakStartTime: profile.breakStartTime,
      breakDurationMinutes: profile.breakDurationMinutes,
      fromMs,
      throughMs,
      timeZoneIdentifier: profile.timeZoneIdentifier,
    });
    {
      const from = Date.UTC(2026, 2, 25, 15) + p * hour;
      const through = p === 0 ? from - day : from + 14 * day;
      expansions.push({ p, from, through, expected: call("expandScheduleRange", expansionRequest(from, through)) });
    }
    {
      // Two years: both DST transitions twice in every zone, and the
      // alternating and rotation anchors across a year boundary.
      const from = Date.UTC(2026, 0, 1, 12);
      const through = Date.UTC(2027, 11, 31, 12);
      const days = call("expandScheduleRange", expansionRequest(from, through));
      expansionDigests.push({ p, from, through, count: days.length, sha256: digest(days.map(expansionLine)) });
    }

    // Records periods: every actual kind (and an unknown one) against forecast
    // rows, overlapping overtime, unpaired observations, and a day key that
    // repeats or does not exist.
    [0, 1, 2].forEach((c) => {
      const asOfMs = stride[10 + c] + (c === 1 ? 0.5 : 0);
      const kinds = [null, "corrected", "observed", "scheduled", null, "unknown"];
      const expanded = call("expandScheduleRange", expansionRequest(asOfMs - 4 * day, asOfMs + 5 * day));
      const days = expanded.map((entry, j) => {
        const actualKind = kinds[(j + c + p) % kinds.length];
        const planned = entry.segments;
        const first = planned[0];
        const last = planned[planned.length - 1];
        const offset = (j + p) % 4 === 1 ? 30 * minute : 0;
        const resolvedSegments = (!entry.isWorkday && actualKind === null) || (j + c) % 7 === 3
          ? []
          : planned.map((segment) => ({ startAtMs: segment.startAtMs + offset, endAtMs: segment.endAtMs + offset }));
        const overtimeSegments = actualKind !== null && j % 3 === 0
          ? [
            { startAtMs: last.endAtMs - 20 * minute, endAtMs: last.endAtMs + 45 * minute },
            { startAtMs: last.endAtMs + 30 * minute, endAtMs: last.endAtMs + 90 * minute },
          ]
          : [];
        const observations = actualKind === "observed"
          ? [
            { kind: "started", occurredAtMs: first.startAtMs + 10 * minute },
            { kind: "started", occurredAtMs: first.startAtMs + 20 * minute },
            { kind: "stopped", occurredAtMs: last.endAtMs - (j % 2) * 3 * hour },
            ...(j % 2 === 0 ? [{ kind: "started", occurredAtMs: last.endAtMs + 10 * minute }] : []),
            { kind: "stopped", occurredAtMs: first.startAtMs - hour },
          ]
          : [];
        return {
          dayKey: entry.dayKey,
          actualKind,
          resolvedSegments,
          plannedSegments: planned,
          overtimeSegments,
          observations,
          isActiveAnchor: c !== 2 && first.startAtMs <= asOfMs && asOfMs < last.endAtMs + 2 * hour,
        };
      });
      const salary = (p + c * 7) % sampledSalaryCount;
      const input = {
        days,
        periodDayKeys: [...expanded.map((entry) => entry.dayKey), ...(p % 3 === 0 ? [expanded[0].dayKey, "2026-02-30"] : [])],
        dailySalary: p % 5 === 0 ? null : call("snapshot", rulesInput(profile, asOfMs, { salary })).dailySalary,
        asOfMs,
        salaryRules: c === 2 && p % 2 === 0 ? null : rulesInput(profile, asOfMs, { salary }),
      };
      actualForecast.push({ input, expected: call("recordsActualForecast", input) });
    });
  });

  // Explicit Los Angeles spring-gap and repeated-hour probes. Append after the
  // broad sweep so its existing profile indices and cases stay unchanged.
  const laInstants = [
    Date.UTC(2026, 2, 8, 9, 30),  // 01:30 PST, before the skipped hour
    Date.UTC(2026, 2, 8, 10, 0),  // 03:00 PDT, immediately after it
    Date.UTC(2026, 2, 8, 10, 30),
    Date.UTC(2026, 10, 1, 8, 30), // first 01:30, PDT
    Date.UTC(2026, 10, 1, 9, 30), // second 01:30, PST
    Date.UTC(2026, 10, 1, 10, 0),
  ];
  for (const clock of [hours[2], hours[5]]) {
    const p = profiles.length;
    const profile = {
      id: `${clock.id}/weekends/America/Los_Angeles`,
      startTime: clock.startTime,
      endTime: clock.endTime,
      workdays: [0, 6],
      schedule: { mode: "classic" },
      breakStartTime: clock.breakStartTime,
      breakDurationMinutes: clock.breakDurationMinutes,
      timeZoneIdentifier: "America/Los_Angeles",
    };
    profiles.push(profile);
    for (const nowMs of laInstants) {
      snapshots.push({ p, s: 1, now: nowMs, ot: null, forced: null,
        expected: snapshotRow(call("snapshot", rulesInput(profile, nowMs, { salary: 1 }))) });
    }
  }

  for (let salary = sampledSalaryCount; salary < salaries.length; salary += 1) {
    for (const nowMs of strideInstants(0).slice(0, 4)) {
      snapshots.push({ p: 0, s: salary, now: nowMs, ot: null, forced: null,
        expected: snapshotRow(call("snapshot", rulesInput(profiles[0], nowMs, { salary }))) });
    }
  }

  // Recovered finite salaries can still overflow while summing a Records period.
  for (const salaryType of ["daily", "monthly"]) {
    const input = { ...actualForecast[0].input, dailySalary: 1e308,
      salaryRules: { ...rulesInput(profiles[0], actualForecast[0].input.asOfMs),
        salaryAmount: "1e308", salaryType, monthlyWorkingDays: 22, annualBonusMonths: 0 } };
    actualForecast.push({ input, expected: call("recordsActualForecast", input) });
  }

  const recordsIncome = salaries.flatMap((_, s) => [0, 1, 2, 23, -3].map((n) => ({
    s,
    n,
    expected: call("recordsIncome", { ...rulesInput(profiles[0], 0, { salary: s }), completedWorkdays: n }).earnings,
  })));
  const monthlyEquivalent = salaries.flatMap((_, s) => ["monthly", "daily"].map((type) => ({
    s,
    type,
    expected: call("salaryMonthlyEquivalent", { ...rulesInput(profiles[0], 0, { salary: s }), salaryType: type }).amount,
  })));
  const lifetimeIncome = lifetimeIncomeCases().map((input) => ({ input, expected: call("lifetimeIncome", input) }));

  const section = (name, rows) =>
    `"${name}":[\n${rows.map((row) => JSON.stringify(row)).join(",\n")}\n]`;
  const monthBasis = monthBasisFixtures();
  const overtimePay = overtimePayFixtures();
  const overtimeStart = overtimeStartFixtures();
  const json = `{"version":3,
"generator":"scripts/generate-ios-schedule-rule-fixtures.mjs",
${section("profiles", profiles)},
${section("salaries", salaries)},
${section("reminderInputs", reminderInputs)},
${section("snapshots", snapshots)},
${section("watch", watch)},
${section("widgetShifts", widgetShifts)},
${section("widgetDigests", widgetDigests)},
${section("expansions", expansions)},
${section("expansionDigests", expansionDigests)},
${section("validateBreak", validateBreak)},
${section("reminders", reminders)},
${section("applyToday", applyToday)},
${section("summaries", summaries)},
${section("recordsIncome", recordsIncome)},
${section("monthlyEquivalent", monthlyEquivalent)},
${section("lifetimeIncome", lifetimeIncome)},
${section("actualForecast", actualForecast)},
"monthBasis":{
${Object.entries(monthBasis).map(([name, rows]) => section(name, rows)).join(",\n")}
},
"overtimePay":{
${Object.entries(overtimePay).map(([name, rows]) => section(name, rows)).join(",\n")}
},
"overtimeStart":{
${Object.entries(overtimeStart).map(([name, rows]) => section(name, rows)).join(",\n")}
}
}`;
  return json;
}

export function createScheduleRuleFixtures() {
  const json = createScheduleRuleFixtureJson();
  // A Swift raw string ends at `"""#`, and `"#` would begin an escape inside it.
  if (json.includes('"#')) throw new Error("Fixture JSON cannot be embedded in a Swift raw string.");
  return `// Generated by scripts/generate-ios-schedule-rule-fixtures.mjs from lib/ through
// scripts/ios-schedule-rule-oracle.mjs. Do not edit by hand.
//
// Compiled into the test binary rather than copied as a resource: AppTests has
// no resources phase, and Xcode Cloud runs tests on a host without the source.
nonisolated enum ScheduleRuleFixtureData {
    static let json = #"""
${json}
"""#
}
`;
}

export const scheduleRuleFixturePath = resolve(
  "src-mobile/ios/App/AppTests/ScheduleRuleFixtures.generated.swift"
);

export function checkScheduleRuleFixtures(outputPath, expected) {
  let existing;
  try {
    existing = readFileSync(outputPath, "utf8");
  } catch {
    return `iOS schedule-rule fixture is missing or unreadable: ${outputPath}`;
  }
  if (existing !== expected) {
    return "iOS schedule-rule fixture is stale. Run: node scripts/generate-ios-schedule-rule-fixtures.mjs";
  }
  return null;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const output = createScheduleRuleFixtures();
  if (process.argv.slice(2).includes("--check")) {
    const failure = checkScheduleRuleFixtures(scheduleRuleFixturePath, output);
    if (failure) {
      console.error(failure);
      process.exitCode = 1;
    }
  } else {
    writeFileSync(scheduleRuleFixturePath, output);
  }
}
