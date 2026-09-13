import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { loadScheduleRuleOracle } from "./ios-schedule-rule-oracle.mjs";

const hour = 3_600_000;
const scenarios = [
  { name: "before-shift", at: "2026-09-14T00:30:00Z", start: "09:00", end: "17:00", zone: "Asia/Shanghai", lunch: "12:00", lunchMinutes: 60, phase: "before", boundary: "shiftStart" },
  { name: "lunch-working", at: "2026-09-14T02:00:00Z", start: "09:00", end: "17:00", zone: "Asia/Shanghai", lunch: "12:00", lunchMinutes: 60, phase: "working", boundary: "segment0End" },
  { name: "lunch-start-boundary", at: "2026-09-14T04:00:00Z", start: "09:00", end: "17:00", zone: "Asia/Shanghai", lunch: "12:00", lunchMinutes: 60, phase: "resting", boundary: "activeBreakEnd" },
  { name: "lunch-frozen", at: "2026-09-14T04:30:00Z", start: "09:00", end: "17:00", zone: "Asia/Shanghai", lunch: "12:00", lunchMinutes: 60, phase: "resting", boundary: "activeBreakEnd" },
  { name: "lunch-end-boundary", at: "2026-09-14T05:00:00Z", start: "09:00", end: "17:00", zone: "Asia/Shanghai", lunch: "12:00", lunchMinutes: 60, phase: "working", boundary: "segment1End" },
  { name: "lunch-resumed", at: "2026-09-14T06:00:00Z", start: "09:00", end: "17:00", zone: "Asia/Shanghai", lunch: "12:00", lunchMinutes: 60, phase: "working", boundary: "segment1End" },
  { name: "overnight-before-midnight", at: "2026-09-14T23:00:00Z", start: "22:00", end: "06:00", zone: "UTC", phase: "working", boundary: "segment0End" },
  { name: "overnight-after-midnight", at: "2026-09-15T02:00:00Z", start: "22:00", end: "06:00", zone: "UTC", phase: "working", boundary: "segment0End" },
  { name: "overtime-before-boundary", at: "2026-09-14T08:59:59.999Z", start: "09:00", end: "17:00", zone: "Asia/Shanghai", overtimeHours: 2, phase: "working", boundary: "plannedEnd" },
  { name: "overtime-boundary", at: "2026-09-14T09:00:00Z", start: "09:00", end: "17:00", zone: "Asia/Shanghai", overtimeHours: 2, phase: "overtime", boundary: "overtimeEnd" },
  { name: "overtime", at: "2026-09-14T09:30:00Z", start: "09:00", end: "17:00", zone: "Asia/Shanghai", overtimeHours: 2, phase: "overtime", boundary: "overtimeEnd" },
  { name: "dst-spring-forward", at: "2026-03-08T10:30:00Z", start: "00:00", end: "08:00", zone: "America/Los_Angeles", phase: "working", boundary: "segment0End" },
  // The clock repeats 01:00–02:00, so 00:00–08:00 lasts nine real hours.
  { name: "dst-fall-back", at: "2026-11-01T09:30:00Z", start: "00:00", end: "08:00", zone: "America/Los_Angeles", phase: "working", boundary: "segment0End" },
  { name: "other-time-zone", at: "2026-09-14T14:00:00Z", start: "09:00", end: "17:00", zone: "America/New_York", phase: "working", boundary: "segment0End" },
  // Asleep through a whole shift: the projection rolls to the next one, never a backfilled finish.
  { name: "slept-through-to-next-shift", at: "2026-09-15T00:30:00Z", start: "09:00", end: "17:00", zone: "Asia/Shanghai", phase: "before", boundary: "shiftStart" },
  { name: "final-boundary", at: "2026-09-14T09:00:00Z", start: "09:00", end: "17:00", zone: "Asia/Shanghai", phase: "finished", boundary: "none" },
  { name: "expired", at: "2026-09-14T10:00:00Z", start: "09:00", end: "17:00", zone: "Asia/Shanghai", phase: "finished", boundary: "none" },
  { name: "early-finish-working", at: "2026-09-14T08:00:00Z", finishedAt: "2026-09-14T06:00:00Z", start: "09:00", end: "17:00", zone: "Asia/Shanghai", lunch: "12:00", lunchMinutes: 60, phase: "finished", boundary: "none" },
  { name: "early-finish-during-lunch", at: "2026-09-14T07:00:00Z", finishedAt: "2026-09-14T04:30:00Z", start: "09:00", end: "17:00", zone: "Asia/Shanghai", lunch: "12:00", lunchMinutes: 60, phase: "finished", boundary: "none" },
  { name: "early-finish-frozen-after-clock-and-schedule-change", at: "2026-09-14T08:30:00Z", finishedAt: "2026-09-14T03:00:00Z", start: "09:00", end: "17:00", zone: "Asia/Shanghai", lunch: "12:00", lunchMinutes: 60, phase: "finished", boundary: "none" },
];

const oracle = loadScheduleRuleOracle();

function swiftOptional(value) {
  return value == null ? "nil" : String(Math.trunc(value));
}

function expectedBoundary(result, selector) {
  // Select a named absolute boundary returned by the TypeScript bundle. Do not
  // recompute the boundary with the Swift evaluator's decision tree here.
  let boundary;
  switch (selector) {
    case "shiftStart": boundary = result.startAtMs; break;
    case "segment0End": boundary = result.segments[0]?.endAtMs; break;
    case "segment1End": boundary = result.segments[1]?.endAtMs; break;
    case "activeBreakEnd": boundary = result.activeBreakEndAtMs; break;
    case "plannedEnd": boundary = result.plannedEndAtMs; break;
    case "overtimeEnd": boundary = result.overtimeEndAtMs; break;
    case "none": return null;
    default: throw new Error(`Unknown boundary selector: ${selector}`);
  }
  if (!Number.isFinite(boundary)) {
    throw new Error(`TypeScript returned no valid ${selector} boundary for ${result.startAtMs ?? "unknown shift"}.`);
  }
  return boundary;
}

function fixture(scenario) {
  const nowMs = Date.parse(scenario.at);
  const baseInput = {
    startTime: scenario.start,
    endTime: scenario.end,
    nowMs,
    workdays: [0, 1, 2, 3, 4, 5, 6],
    schedule: { mode: "off" },
    breakStartTime: scenario.lunch ?? null,
    breakDurationMinutes: scenario.lunchMinutes ?? 0,
    overtimeEndAtMs: null,
    timeZoneIdentifier: scenario.zone,
    salaryAmount: "0",
    salaryType: "daily",
    monthlyWorkingDays: 21.75,
    annualBonusMonths: 0,
  };
  const initial = JSON.parse(oracle.snapshot(JSON.stringify(baseInput)));
  if (scenario.overtimeHours) {
    baseInput.overtimeEndAtMs = initial.plannedEndAtMs + scenario.overtimeHours * hour;
  }
  const result = JSON.parse(oracle.snapshot(JSON.stringify(baseInput)));
  const finishedAtMs = scenario.finishedAt ? Date.parse(scenario.finishedAt) : null;
  const frozen = finishedAtMs == null ? result : JSON.parse(oracle.snapshot(JSON.stringify({
    ...baseInput,
    nowMs: finishedAtMs,
  })));
  const nextBoundary = expectedBoundary(result, scenario.boundary);

  return `        .init(
            name: ${JSON.stringify(scenario.name)},
            nowMs: ${nowMs},
            shift: .init(
                segments: [${result.segments.map(segment => `.init(startAtMs: ${segment.startAtMs}, endAtMs: ${segment.endAtMs})`).join(", ")}],
                plannedEndAtMs: ${result.plannedEndAtMs},
                overtimeEndAtMs: ${swiftOptional(result.overtimeEndAtMs)},
                finishedAtMs: ${swiftOptional(finishedAtMs)},
                isRunning: true,
                transitions: []
            ),
            expected: .init(
                phase: .${scenario.phase}, totalMs: ${Math.trunc(frozen.durationMs)}, elapsedMs: ${Math.trunc(frozen.elapsedMs)},
                remainingMs: ${Math.trunc(frozen.remainingMs)}, progress: ${frozen.progress}, nextBoundaryAtMs: ${swiftOptional(nextBoundary)}
            )
        )`;
}

export function createWatchShiftFixtures() {
  return `// Generated by scripts/generate-watch-shift-fixtures.mjs from lib/countdown.ts through
// scripts/ios-schedule-rule-oracle.mjs. Do not edit by hand.
import Foundation
@testable import App

nonisolated struct WatchShiftEvaluationFixture: Sendable {
    let name: String
    let nowMs: Int64
    let shift: WatchShiftProjectionV1
    let expected: WatchShiftEvaluation
}

nonisolated enum WatchShiftEvaluationFixtures {
    static let all: [WatchShiftEvaluationFixture] = [
${scenarios.map(fixture).join(",\n")}
    ]
}
`;
}

export function checkWatchShiftFixtures(outputPath, expected) {
  let existing;
  try {
    existing = readFileSync(outputPath, "utf8");
  } catch {
    return `Watch shift fixture is missing or unreadable: ${outputPath}`;
  }
  if (existing !== expected) {
    return "Watch shift fixture is stale. Run: node scripts/generate-watch-shift-fixtures.mjs";
  }
  return null;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const outputPath = resolve("src-mobile/ios/App/AppTests/WatchShiftEvaluationFixtures.generated.swift");
  const output = createWatchShiftFixtures();
  if (process.argv.slice(2).includes("--check")) {
    const failure = checkWatchShiftFixtures(outputPath, output);
    if (failure) {
      console.error(failure);
      process.exitCode = 1;
    }
  } else {
    writeFileSync(outputPath, output);
  }
}
