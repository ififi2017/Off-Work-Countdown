import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { loadScheduleRuleOracle } from "./ios-schedule-rule-oracle.mjs";

// Differential fixtures for plan 019 R1. The TypeScript oracle answers every
// case; AppTests/ScheduleRuleFixtureTests.swift holds ScheduleRules.swift to
// the same values. Cases are one per line so a rule change reads as a diff.

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

export function createScheduleRuleFixtures() {
  const snapshots = [];
  const watch = [];
  const widgetShifts = [];
  const widgetDigests = [];
  const expansions = [];
  const expansionDigests = [];
  const validateBreak = [];

  profiles.forEach((profile, p) => {
    const stride = strideInstants(p);
    const instants = [...stride, ...boundaryInstants(profile)];

    instants.forEach((nowMs, k) => {
      const salary = (p * 3 + k) % salaries.length;
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
  });

  const section = (name, rows) =>
    `"${name}":[\n${rows.map((row) => JSON.stringify(row)).join(",\n")}\n]`;
  const json = `{"version":1,
"generator":"scripts/generate-ios-schedule-rule-fixtures.mjs",
${section("profiles", profiles)},
${section("salaries", salaries)},
${section("snapshots", snapshots)},
${section("watch", watch)},
${section("widgetShifts", widgetShifts)},
${section("widgetDigests", widgetDigests)},
${section("expansions", expansions)},
${section("expansionDigests", expansionDigests)},
${section("validateBreak", validateBreak)}
}`;
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
