#!/usr/bin/env node
/**
 * Construct anonymous RecordJSON v1–v6 (+ illegal) archives for Android T02.
 *
 * Shapes follow src-mobile/ios/App/AppTests/RecordSchemaCompatibilityTests.swift
 * at 9252fdfdc66aab88b4acb7493684f11991fd773d (`fullState` + `downgraded`).
 * Extra snapshot/exception rows sample the two families that fixture omitted.
 *
 * These are constructed from source encoding/tests, not live user exports.
 * Usage:
 *   node scripts/android-synthetic-archives.mjs          # write files
 *   node scripts/android-synthetic-archives.mjs --check  # verify committed files
 */

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const SOURCE_COMMIT = "9252fdfdc66aab88b4acb7493684f11991fd773d";
const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const OUT = join(ROOT, "docs/android/synthetic-archives");

const DAY_MS = Date.UTC(2026, 7, 24);
const id = (n) =>
  `00000000-0000-0000-0000-${String(n).padStart(12, "0")}`.toUpperCase();
const LIFE_ID = "00000000-0000-0000-0000-00574F524B01";
const b64 = (text) => Buffer.from(text, "utf8").toString("base64");

const snapshotConfig = {
  startTime: "09:00",
  endTime: "17:00",
  workdays: [1, 2, 3, 4, 5],
  schedule: { mode: "classic" },
  breakStartTime: "12:00",
  breakDurationMinutes: 60,
};

function v6Document() {
  return {
    schemaVersion: 6,
    exportedAtMs: 0,
    timeZoneIdentifier: "UTC",
    calendarIdentifier: "gregorian",
    careerPeriods: [
      {
        id: id(1),
        startsOn: "2026-08-24",
        endsBefore: null,
        label: "Current",
        timeZoneIdentifier: "UTC",
        calendarIdentifier: "gregorian",
        createdAtMs: DAY_MS,
        editedAtMs: DAY_MS,
        editCount: 1,
        editTieBreaker: id(2),
      },
    ],
    scheduleSnapshots: [
      {
        id: id(5),
        periodID: id(1),
        effectiveFrom: "2026-08-24",
        configurationData: b64(JSON.stringify(snapshotConfig)),
        fingerprint: "synthetic-hours-v1",
        editedAtMs: DAY_MS,
        editCount: 1,
        editTieBreaker: id(21),
      },
    ],
    calendarExceptions: [
      {
        dayKey: "2026-08-26#user",
        date: "2026-08-26",
        effect: "rest",
        origin: "user",
        isCleared: false,
        regionIdentifier: null,
        datasetVersion: null,
        label: "Personal rest",
        editedAtMs: DAY_MS,
        editCount: 1,
        editTieBreaker: id(22),
        timeZoneIdentifier: "UTC",
      },
    ],
    dayOverrides: [
      {
        dayKey: "2026-08-24",
        kind: "customSegments",
        segments: [{ startAtMs: DAY_MS, endAtMs: DAY_MS + 8 * 3_600_000 }],
        note: "Worked a full shift",
        editedAtMs: DAY_MS,
        editCount: 1,
        editTieBreaker: id(3),
        timeZoneIdentifier: "UTC",
      },
    ],
    workObservations: [
      {
        eventID: id(4),
        shiftAnchorDate: "2026-08-24",
        occurredAtMs: DAY_MS,
        kind: "countdownStarted",
        valueData: b64("manual"),
        scheduleSnapshotID: id(5),
        schemaVersion: 2,
        timeZoneIdentifier: "UTC",
        editedAtMs: DAY_MS + 60_000,
        editCount: 3,
        editTieBreaker: id(6),
      },
    ],
    lifeProfile: {
      profileID: LIFE_ID,
      birthYear: 1990,
      workStartedOn: "2026-08-24",
      retirementAge: 60,
      averageSleepHours: 7.5,
      hidesExactAges: false,
      bornOn: { year: 1990, month: 3, day: 15, precision: "day" },
      schoolStartedOn: { year: 1996, month: null, day: null, precision: "year" },
      workStartedPartial: { year: 2015, month: 6, day: 1, precision: "day" },
      retirementOn: { year: 2055, month: null, day: null, precision: "year" },
      averageSleepMinutes: 480,
      sleepSource: "healthSuggested",
      sleepSourceUpdatedAtMs: DAY_MS,
      workHistoryMode: "detailed",
      roughCurrentSalary: { amount: 10_000, cadence: "monthly" },
      employmentPeriods: [
        {
          id: id(14),
          startsOn: { year: 2015, month: 6, day: 1, precision: "day" },
          endsOn: null,
          salary: { amount: 120_000, cadence: "yearly" },
        },
      ],
      futureIncomeDecline: { startsAtAge: 45, retirementRatio: 0.6 },
      editedAtMs: DAY_MS,
      editCount: 5,
      editTieBreaker: id(15),
    },
    focusTasks: [
      {
        id: id(7),
        createdAtMs: DAY_MS,
        plannedForDate: "2026-08-24",
        scheduledStartAtMs: DAY_MS + 3_600_000,
        title: "Write release notes",
        estimatedPomodoros: 2,
        icon: "writing",
        isFavorite: true,
        completedAtMs: null,
        deletedAtMs: null,
        sortIndex: 0,
        editedAtMs: DAY_MS,
        editCount: 2,
        editTieBreaker: id(8),
        templateID: null,
        templateTaskKey: null,
      },
    ],
    focusSessions: [
      {
        id: id(9),
        taskID: id(7),
        shiftAnchorDate: "2026-08-24",
        startedAtMs: DAY_MS,
        plannedEndAtMs: DAY_MS + 1_500_000,
        endedAtMs: DAY_MS + 1_500_000,
        endReason: "completed",
        editedAtMs: DAY_MS,
        editCount: 1,
        editTieBreaker: id(10),
        kind: "focus",
        timeZoneIdentifier: "UTC",
        anchorDayKey: "2026-08-24",
        actualDurationSeconds: 1500,
        plannedEndReason: "completed",
      },
    ],
    focusPlanningConfiguration: {
      plans: [
        {
          dayKey: "2026-08-24",
          shiftStartAtMs: DAY_MS,
          assignments: [
            {
              blockStartAtMs: DAY_MS,
              kind: "task",
              taskID: id(7),
              taskTitle: "Write release notes",
              taskIcon: "writing",
            },
          ],
          appliedTemplateID: id(11),
        },
      ],
      templates: [
        {
          id: id(11),
          name: "Release day",
          slots: [
            {
              blockIndex: 0,
              kind: "task",
              taskKey: id(12),
              taskTitle: "Write release notes",
              taskIcon: "writing",
            },
          ],
          createdAtMs: DAY_MS,
          updatedAtMs: DAY_MS,
        },
      ],
      defaultTemplateID: id(11),
      autoAppliedDayKeys: ["2026-08-24"],
      focusMinutes: 40,
      shortBreakMinutes: 8,
      longBreakMinutes: 20,
      longBreakEvery: 3,
      editedAtMs: DAY_MS,
      editCount: 4,
      editTieBreaker: id(13),
    },
    syncedPreferences: {
      startMinutes: 540,
      endMinutes: 1020,
      workdays: [1, 2, 3, 4, 5],
      scheduleMode: "classic",
      alternatingWeekType: "double",
      alternatingWeekendWorkday: 6,
      alternatingReferenceWeekStartMs: DAY_MS,
      rotationWorkDays: 2,
      rotationRestDays: 2,
      rotationAnchorMs: DAY_MS,
      lunchEnabled: true,
      lunchStartMinutes: 720,
      lunchDurationMinutes: 60,
      recordsTimeZoneIdentifier: "UTC",
      salaryAmount: "64000",
      salaryEnabled: true,
      salaryType: "monthly",
      monthlyWorkingDays: 22,
      annualBonusEnabled: true,
      annualBonusMonths: 2,
      notificationMode: "milestones",
      cycleEndSummaryNotificationEnabled: true,
      lunchStartReminderEnabled: true,
      lunchEndReminderEnabled: true,
      microBreakEnabled: true,
      microBreakIntervalMinutes: 60,
      theme: "auto",
      languageOverride: null,
      editedAtMs: DAY_MS,
      editCount: 1,
      editTieBreaker: id(16),
    },
    recordsStartedOn: "2026-08-24",
    extendedSchedule: {
      isEnabled: true,
      shiftTypes: [
        {
          id: id(17),
          name: "Night",
          kind: "work",
          startMinutes: 1320,
          endMinutes: 360,
          breakEnabled: true,
          breakStartMinutes: 120,
          breakDurationMinutes: 30,
          colorHex: "#3A6EA5",
          isArchived: false,
        },
        {
          id: id(18),
          name: "Rest",
          kind: "rest",
          startMinutes: 0,
          endMinutes: 0,
          breakEnabled: false,
          breakStartMinutes: 0,
          breakDurationMinutes: 0,
          colorHex: "#9E9E9E",
          isArchived: false,
        },
      ],
      rule: {
        preset: "rotation",
        anchorDayKey: "2026-08-24",
        days: [id(17), id(17), id(18)],
      },
      holidayRegionIdentifier: null,
      clearedFromDayKey: null,
      timeZoneIdentifier: "UTC",
      editedAtMs: DAY_MS,
      editCount: 2,
      editTieBreaker: id(19),
    },
    rosterDays: [
      {
        dayKey: "2026-08-25",
        shiftTypeID: id(18),
        assignedShiftType: null,
        generatedFromPattern: null,
        timeZoneIdentifier: "UTC",
        editedAtMs: DAY_MS,
        editCount: 1,
        editTieBreaker: id(20),
      },
    ],
  };
}

function downgraded(object, version) {
  const result = structuredClone(object);
  result.schemaVersion = version;
  if (version < 3) {
    delete result.recordsStartedOn;
    for (const row of result.workObservations ?? []) {
      delete row.editedAtMs;
      delete row.editCount;
      delete row.editTieBreaker;
    }
    if (result.lifeProfile) {
      for (const key of [
        "bornOn",
        "schoolStartedOn",
        "workStartedPartial",
        "retirementOn",
        "averageSleepMinutes",
        "sleepSource",
        "sleepSourceUpdatedAtMs",
      ]) {
        delete result.lifeProfile[key];
      }
    }
    for (const row of result.focusTasks ?? []) {
      for (const key of [
        "scheduledStartAtMs",
        "icon",
        "isFavorite",
        "deletedAtMs",
        "templateID",
        "templateTaskKey",
      ]) {
        delete row[key];
      }
    }
    for (const row of result.focusSessions ?? []) {
      for (const key of [
        "kind",
        "timeZoneIdentifier",
        "anchorDayKey",
        "actualDurationSeconds",
        "plannedEndReason",
      ]) {
        delete row[key];
      }
    }
  }
  if (version < 4) delete result.focusPlanningConfiguration;
  if (version < 5) {
    delete result.syncedPreferences;
    if (result.lifeProfile) {
      for (const key of [
        "workHistoryMode",
        "roughCurrentSalary",
        "employmentPeriods",
        "futureIncomeDecline",
      ]) {
        delete result.lifeProfile[key];
      }
    }
  }
  if (version < 6) {
    delete result.extendedSchedule;
    delete result.rosterDays;
  }
  return result;
}

const PURCHASE_KEYS = [
  "purchaseToken",
  "isPlus",
  "transactionId",
  "receipt",
  "jwsRepresentation",
];

function assertNoPurchaseKeys(value, path = "$") {
  if (Array.isArray(value)) {
    value.forEach((item, i) => assertNoPurchaseKeys(item, `${path}[${i}]`));
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) {
      if (PURCHASE_KEYS.includes(key)) {
        throw new Error(`${path}.${key} must not appear in a user backup`);
      }
      assertNoPurchaseKeys(child, `${path}.${key}`);
    }
  }
}

function expectedFiles() {
  const v6 = v6Document();
  const files = {
    "v6.json": v6,
    "v5.json": downgraded(v6, 5),
    "v4.json": downgraded(v6, 4),
    "v3.json": downgraded(v6, 3),
    "v2.json": downgraded(v6, 2),
    "v1.json": downgraded(v6, 1),
    "illegal-v0.json": { ...structuredClone(v6), schemaVersion: 0 },
    "illegal-v7.json": { ...structuredClone(v6), schemaVersion: 7 },
    "illegal-invalid-date-v6.json": (() => {
      const doc = structuredClone(v6);
      doc.dayOverrides[0].dayKey = "2026-02-30";
      return doc;
    })(),
    "illegal-purchase-injected-v6.json": {
      ...structuredClone(v6),
      purchaseToken: "SHOULD-NOT-GRANT-PLUS",
      isPlus: true,
    },
  };
  return files;
}

const ENTITY_KEYS = [
  "careerPeriods",
  "scheduleSnapshots",
  "calendarExceptions",
  "dayOverrides",
  "workObservations",
  "lifeProfile",
  "focusTasks",
  "focusSessions",
  "focusPlanningConfiguration",
  "syncedPreferences",
  "extendedSchedule",
  "rosterDays",
];

function validateExpected(files) {
  let checks = 0;
  const v6 = files["v6.json"];
  if (v6.schemaVersion !== 6) throw new Error("v6 schemaVersion");
  checks += 1;
  for (const key of ENTITY_KEYS) {
    const value = v6[key];
    const empty = value == null || (Array.isArray(value) && value.length === 0);
    if (empty) throw new Error(`v6 missing sample for ${key}`);
    checks += 1;
  }
  assertNoPurchaseKeys(v6);
  checks += 1;
  for (const version of [1, 2, 3, 4, 5, 6]) {
    const doc = files[`v${version}.json`];
    if (doc.schemaVersion !== version) {
      throw new Error(`v${version} stamped ${doc.schemaVersion}`);
    }
    checks += 1;
  }
  if (files["v1.json"].recordsStartedOn != null) {
    throw new Error("v1 must not carry recordsStartedOn");
  }
  if (files["v4.json"].syncedPreferences != null) {
    throw new Error("v4 must not carry syncedPreferences");
  }
  if (files["v5.json"].extendedSchedule != null) {
    throw new Error("v5 must not carry extendedSchedule");
  }
  if (files["illegal-v0.json"].schemaVersion !== 0) throw new Error("v0 stamp");
  if (files["illegal-v7.json"].schemaVersion !== 7) throw new Error("v7 stamp");
  checks += 5;
  return checks;
}

function writeJson(path, value) {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);
}

function main() {
  const check = process.argv.includes("--check");
  mkdirSync(OUT, { recursive: true });
  const files = expectedFiles();
  const generatedChecks = validateExpected(files);
  if (check) {
    let compared = 0;
    for (const [name, expected] of Object.entries(files)) {
      const actual = JSON.parse(readFileSync(join(OUT, name), "utf8"));
      if (JSON.stringify(actual) !== JSON.stringify(expected)) {
        throw new Error(`${name} differs from generator`);
      }
      compared += 1;
    }
    const notJson = readFileSync(join(OUT, "illegal-not-json.txt"), "utf8");
    if (!notJson.includes("not-json")) throw new Error("illegal-not-json.txt");
    compared += 1;
    console.log(
      `android-synthetic-archives check passed: ${generatedChecks} shape checks, ${compared} files, source ${SOURCE_COMMIT}`
    );
    return;
  }
  for (const [name, value] of Object.entries(files)) {
    writeJson(join(OUT, name), value);
  }
  writeFileSync(
    join(OUT, "illegal-not-json.txt"),
    "this is not-json and must be rejected as invalidDocument\n"
  );
  writeJson(join(OUT, "manifest.json"), {
    sourceCommit: SOURCE_COMMIT,
    provenance:
      "Constructed from RecordSchemaCompatibilityTests.fullState/downgraded plus one snapshot and one calendar exception so all 12 entity families are sampled. Not a live user export.",
    versions: {
      wire: 6,
      room: "not created",
      fixture: "not created",
      syncEnvelope: "not created",
    },
    files: Object.keys(files).concat(["illegal-not-json.txt"]),
  });
  console.log(
    `wrote ${Object.keys(files).length + 2} files under docs/android/synthetic-archives (${generatedChecks} checks)`
  );
}

main();
