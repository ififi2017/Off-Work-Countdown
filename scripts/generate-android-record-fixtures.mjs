import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// Android tasks T10/T11. The records backup codec is iOS's RecordJSON; there is
// no TypeScript oracle. This compiles the real Swift codec and models on macOS
// with scripts/android-record-fixtures/main.swift, runs it over the synthetic
// archives plus targeted edge cases, and records its answers for Kotlin. The
// header hashes every Swift input, so a codec change makes the fixture stale
// on any platform; regenerating needs Xcode.

const models = "src-mobile/ios/App/App/Native/Models";
const swiftInputs = [
  "RecordJSON", "CareerPeriod", "CalendarException", "DayOverride", "WorkObservation", "LifeProfile",
  "FocusModels", "FocusPlanner", "SyncedPreferences", "RecordIncomingValue+Content", "RecordsSyncAdapter",
].map((name) => `${models}/${name}.swift`).concat([
  "src-mobile/ios/App/App/Native/Services/NativeLocalizer.swift",
  "src-mobile/ios/Shared/ExtendedSchedule.swift",
  "src-mobile/ios/Shared/ExtendedScheduleRules.swift",
  "src-mobile/ios/Shared/HolidayCalendar.swift",
  "scripts/android-record-fixtures/main.swift",
]);
// Compiled for their types only.
const compileOnly = ["CountdownRules", "ScheduleRules", "ReminderRules"].map((name) => `${models}/${name}.swift`).concat([
  "src-mobile/ios/Shared/ScheduleRuleInput.swift",
  "src-mobile/ios/Shared/ShiftRuleCore.swift",
  "src-mobile/ios/Shared/WatchDisplayProjection.swift",
  "src-mobile/ios/Shared/WatchPairing.swift",
  "src-mobile/ios/Shared/WatchScheduleV2.swift",
  "src-mobile/ios/Shared/WatchShiftEvaluation.swift",
  "src-mobile/ios/Shared/WatchSnapshot.swift",
  "src-mobile/ios/Shared/WatchSnapshotCache.swift",
]);
const archives = "docs/android/synthetic-archives";

export const androidRecordFixturePath = resolve(
  "src-mobile/android/core/domain/src/test/resources/record-json-fixtures.json"
);

const sha256 = (text) => createHash("sha256").update(text).digest("hex");

export function recordSourceHashes() {
  return Object.fromEntries(
    swiftInputs.map((path) => [path, sha256(readFileSync(resolve(path), "utf8").replace(/\r\n/g, "\n"))])
  );
}

const read = (name) => readFileSync(resolve(archives, name), "utf8");
const v6 = () => JSON.parse(read("v6.json"));
const text = (value) => JSON.stringify(value);

/** A mutated copy of the synthetic v6 archive. */
function variant(edit) {
  const doc = v6();
  edit(doc);
  return text(doc);
}

const MS_2001 = 978_307_200;

export function recordCases() {
  const cases = [];
  const add = (name, input, extra = {}) => cases.push({ name, input, ...extra });

  for (const file of ["v1.json", "v2.json", "v3.json", "v4.json", "v5.json", "v6.json", "illegal-v0.json", "illegal-v7.json",
    "illegal-invalid-date-v6.json", "illegal-purchase-injected-v6.json", "illegal-not-json.txt"]) {
    add(`archive/${file}`, read(file));
  }

  // Document-level decoding: any missing key, wrong type or unknown enum fails the whole file.
  add("doc/missing-required-row-key", variant((d) => { delete d.careerPeriods[0].createdAtMs; }));
  add("doc/wrong-type", variant((d) => { d.dayOverrides[0].editCount = "1"; }));
  add("doc/unknown-enum", variant((d) => { d.dayOverrides[0].kind = "vacation"; }));
  add("doc/int-written-as-float", read("v6.json").replace('"editCount": 3', '"editCount": 3.0'));
  add("doc/int-fraction", read("v6.json").replace('"editCount": 3', '"editCount": 3.5'));
  add("doc/null-required", variant((d) => { d.workObservations[0].kind = null; }));
  add("doc/unpadded-base64", variant((d) => { d.workObservations[0].valueData = "bWFudWE"; }));
  add("doc/bad-base64", variant((d) => { d.scheduleSnapshots[0].configurationData = "!!!"; }));
  add("doc/unknown-top-level-key", variant((d) => { d.somethingNew = { a: 1 }; }));
  add("doc/missing-rows-array", variant((d) => { delete d.dayOverrides; }));
  add("doc/extended-type-bad-uuid", variant((d) => { d.extendedSchedule.shiftTypes[0].id = "nope"; }));
  add("doc/preferences-bad-tiebreaker", variant((d) => { d.syncedPreferences.editTieBreaker = "nope"; }));
  add("doc/unknown-preset", variant((d) => { d.extendedSchedule.rule.preset = "fortnightly"; }));
  add("doc/schema-2", variant((d) => { d.schemaVersion = 2; }));
  add("doc/schema-string", variant((d) => { d.schemaVersion = "6"; }));

  // Zones and calendars.
  add("zone/iso8601-shanghai", variant((d) => { d.calendarIdentifier = "iso8601"; d.timeZoneIdentifier = "Asia/Shanghai"; delete d.careerPeriods[0].calendarIdentifier; d.careerPeriods[0].calendarIdentifier = null; }));
  add("zone/invalid-document-zone", variant((d) => {
    d.timeZoneIdentifier = "Mars/Base";
    d.dayOverrides[0].timeZoneIdentifier = null;
    d.workObservations[0].timeZoneIdentifier = null;
    d.calendarExceptions[0].timeZoneIdentifier = null;
    d.focusSessions[0].timeZoneIdentifier = null;
    d.careerPeriods[0].timeZoneIdentifier = null;
  }));
  add("zone/invalid-row-zone", variant((d) => { d.dayOverrides[0].timeZoneIdentifier = "Nowhere/City"; }));

  // Row rejection and defaults per entity.
  add("period/bad-id", variant((d) => { d.careerPeriods[0].id = "not-a-uuid"; }));
  add("period/lowercase-ids", variant((d) => {
    d.careerPeriods[0].id = "0000000a-0000-0000-0000-00000000000b";
    d.careerPeriods[0].editTieBreaker = "abcdef00-0000-0000-0000-000000000002";
    d.scheduleSnapshots[0].periodID = "0000000a-0000-0000-0000-00000000000b";
  }));
  add("period/ends-before-start", variant((d) => { d.careerPeriods[0].endsBefore = "2026-08-24"; }));
  add("period/ends-later", variant((d) => { d.careerPeriods[0].endsBefore = "2026-09-30"; }));
  add("period/bad-start", variant((d) => { d.careerPeriods[0].startsOn = "2026-02-29"; }));
  add("period/duplicate-different", variant((d) => { d.careerPeriods.push({ ...d.careerPeriods[0], label: "Other", editCount: 4 }); }));
  add("period/duplicate-same", variant((d) => { d.careerPeriods.push({ ...d.careerPeriods[0] }); }));
  add("snapshot/unknown-period", variant((d) => { d.scheduleSnapshots[0].periodID = "00000000-0000-0000-0000-0000000000FF"; }));
  add("snapshot/bad-effective", variant((d) => { d.scheduleSnapshots[0].effectiveFrom = "2026-8-24"; }));
  add("exception/bad-date", variant((d) => { d.calendarExceptions[0].date = "2026-02-30"; }));
  add("override/empty-custom", variant((d) => { d.dayOverrides[0].segments = []; }));
  add("override/leave-with-segments", variant((d) => { d.dayOverrides[0].kind = "notWorking"; }));
  add("override/overlapping", variant((d) => {
    d.dayOverrides[0].segments = [{ startAtMs: 1787529600000, endAtMs: 1787540000000 }, { startAtMs: 1787539000000, endAtMs: 1787558400000 }];
  }));
  add("override/cleared", variant((d) => { d.dayOverrides[0].kind = "cleared"; d.dayOverrides[0].segments = []; d.dayOverrides[0].note = null; }));
  add("observation/v1-stamps", variant((d) => {
    const o = d.workObservations[0];
    delete o.editedAtMs; delete o.editCount; delete o.editTieBreaker; o.valueData = null;
  }));
  add("observation/zero-edit-count", variant((d) => { d.workObservations[0].editCount = 0; d.workObservations[0].editTieBreaker = "junk"; }));
  add("observation/bad-snapshot-id", variant((d) => { d.workObservations[0].scheduleSnapshotID = "x"; }));

  // Life profile: legacy migration, validation, and the early return a rejection causes.
  add("life/legacy-only", variant((d) => {
    d.lifeProfile = {
      profileID: d.lifeProfile.profileID, birthYear: 1988, workStartedOn: "2012-07-01", retirementAge: 63,
      averageSleepHours: 7.25, hidesExactAges: true, editedAtMs: 1787529600000, editCount: 2,
      editTieBreaker: "00000000-0000-0000-0000-000000000044",
    };
  }));
  add("life/birth-year-only", variant((d) => {
    d.lifeProfile = { profileID: d.lifeProfile.profileID, birthYear: 1995, hidesExactAges: false, averageSleepHours: 6.5, editedAtMs: 0, editCount: 1, editTieBreaker: "00000000-0000-0000-0000-000000000045" };
  }));
  add("life/detailed-periods", variant((d) => {
    const p = d.lifeProfile;
    p.workHistoryMode = "detailed";
    p.employmentPeriods = [
      { id: "00000000-0000-0000-0000-0000000000A2", startsOn: { year: 2019, month: 2, day: 30, precision: "day" }, endsOn: null, salary: { amount: 20000, cadence: "monthly" } },
      { id: "00000000-0000-0000-0000-0000000000A1", startsOn: { year: 2015, month: 6, day: 1, precision: "day" }, endsOn: { year: 2019, month: 3, day: 1, precision: "day" }, salary: { amount: 180000, cadence: "yearly" } },
    ];
  }));
  add("life/invalid-rejects-rest", variant((d) => {
    d.lifeProfile.workHistoryMode = "detailed";
    d.lifeProfile.employmentPeriods = [{ id: "00000000-0000-0000-0000-0000000000A3", startsOn: { year: 2015, month: 6, day: 1, precision: "day" }, endsOn: null, salary: { amount: 0, cadence: "monthly" } }];
    d.recordsStartedOn = "2020-01-01";
  }));
  add("life/bad-decline", variant((d) => { d.lifeProfile.futureIncomeDecline = { startsAtAge: 50, retirementRatio: 1.5 }; }));
  add("life/duplicate-period-ids", variant((d) => {
    const period = { id: "00000000-0000-0000-0000-0000000000A4", startsOn: { year: 2015, month: 6, day: 1, precision: "day" }, endsOn: null, salary: { amount: 1, cadence: "monthly" } };
    d.lifeProfile.employmentPeriods = [period, { ...period }];
  }));
  add("life/sleep-rounding", variant((d) => { d.lifeProfile.averageSleepMinutes = null; d.lifeProfile.averageSleepHours = 2.875; d.lifeProfile.sleepSource = null; }));

  // Focus.
  add("focus/task-defaults", variant((d) => { const t = d.focusTasks[0]; t.icon = "rocket"; delete t.isFavorite; t.templateID = "bad"; }));
  add("focus/task-bad-planned", variant((d) => { d.focusTasks[0].plannedForDate = "2026-13-01"; }));
  add("focus/session-defaults-completed", variant((d) => {
    const s = d.focusSessions[0];
    delete s.kind; delete s.plannedEndReason; delete s.anchorDayKey; delete s.timeZoneIdentifier;
    s.plannedEndAtMs = s.startedAtMs + 1_499_000; s.taskID = "not-a-uuid";
  }));
  add("focus/session-defaults-boundary", variant((d) => {
    const s = d.focusSessions[0];
    delete s.plannedEndReason; s.plannedEndAtMs = s.startedAtMs + 1_498_000;
  }));
  add("focus/planning-normalized", variant((d) => {
    const f = d.focusPlanningConfiguration;
    f.focusMinutes = 90; f.shortBreakMinutes = 0; f.longBreakMinutes = 45; f.longBreakEvery = 1;
    f.defaultTemplateID = "00000000-0000-0000-0000-0000000000EE";
    f.autoAppliedDayKeys = ["2026-08-26", "2026-08-24", "2026-08-24"];
    f.plans[0].assignments.unshift({ blockStartAtMs: 1787520000000, kind: "breakTime", taskID: null, taskTitle: null, taskIcon: null });
  }));
  add("focus/planning-duplicate-day-rejects-rest", variant((d) => {
    d.focusPlanningConfiguration.plans.push({ ...d.focusPlanningConfiguration.plans[0] });
    d.syncedPreferences.editCount = 9;
    d.recordsStartedOn = "2020-01-01";
  }));
  add("focus/planning-bad-template-id", variant((d) => { d.focusPlanningConfiguration.templates[0].id = "bad"; }));

  // Preferences.
  add("prefs/bad-language", variant((d) => { d.syncedPreferences.languageOverride = "xx"; }));
  add("prefs/unsorted-workdays", variant((d) => { d.syncedPreferences.workdays = [5, 1]; }));
  add("prefs/workday-seven", variant((d) => { d.syncedPreferences.workdays = [1, 7]; }));
  add("prefs/legacy-edited-at", variant((d) => { delete d.syncedPreferences.editedAtMs; d.syncedPreferences.editedAt = 1787529600 - MS_2001; }));
  add("prefs/bad-zone", variant((d) => { d.syncedPreferences.recordsTimeZoneIdentifier = "Nope/Nope"; }));

  // Extended schedule and roster.
  add("extended/invalid-zone", variant((d) => { d.extendedSchedule.timeZoneIdentifier = "Nope/Nope"; }));
  add("extended/invalid-type-name", variant((d) => { d.extendedSchedule.shiftTypes[0].name = "   "; }));
  add("roster/mismatched-frozen", variant((d) => { d.rosterDays[0].assignedShiftType = d.extendedSchedule.shiftTypes[0]; }));
  add("roster/frozen", variant((d) => { d.rosterDays[0].assignedShiftType = d.extendedSchedule.shiftTypes[1]; d.rosterDays[0].generatedFromPattern = true; }));
  add("roster/bad-zone", variant((d) => { d.rosterDays[0].timeZoneIdentifier = "Nope/Nope"; }));
  add("roster/negative-count", variant((d) => { d.rosterDays[0].editCount = -1; }));
  add("started/invalid", variant((d) => { d.recordsStartedOn = "yesterday"; }));

  // Merging into an existing archive.
  const base = read("v6.json");
  const newer = variant((d) => { d.dayOverrides[0].note = "Edited elsewhere"; d.dayOverrides[0].editCount = 5; });
  const older = variant((d) => { d.dayOverrides[0].note = "Stale copy"; d.dayOverrides[0].editCount = 0; });
  const tie = variant((d) => { d.dayOverrides[0].note = "Tie"; d.dayOverrides[0].editTieBreaker = "ffffffff-0000-0000-0000-000000000003"; });
  const tieLower = variant((d) => { d.dayOverrides[0].note = "Tie low"; d.dayOverrides[0].editTieBreaker = "00000000-0000-0000-0000-000000000001"; });
  add("merge/identical", base, { base, mode: "skipErased" });
  add("merge/newer-kept-local", newer, { base, mode: "skipErased" });
  add("merge/newer-by-stamp", newer, { base, mode: "resolveByEditStamp" });
  add("merge/older-by-stamp", older, { base, mode: "resolveByEditStamp" });
  add("merge/tie-higher-breaker", tie, { base, mode: "resolveByEditStamp" });
  add("merge/tie-lower-breaker", tieLower, { base, mode: "resolveByEditStamp" });
  add("merge/erased-skipped", base, { base, erase: [["dayOverride", "2026-08-24"], ["rosterDay", "2026-08-25"]], mode: "skipErased" });
  add("merge/erased-by-stamp-skipped", newer, { base, erase: [["dayOverride", "2026-08-24"]], mode: "resolveByEditStamp" });
  add("merge/erased-restored", base, { base, erase: [["dayOverride", "2026-08-24"], ["calendarException", "2026-08-26#user"]], mode: "restoreErased" });
  add("merge/earlier-started", variant((d) => { d.recordsStartedOn = "2025-01-01"; }), { base, mode: "skipErased" });
  add("merge/later-started", variant((d) => { d.recordsStartedOn = "2027-01-01"; }), { base, mode: "skipErased" });
  add("merge/new-rows", variant((d) => {
    d.dayOverrides.push({ ...d.dayOverrides[0], dayKey: "2026-08-27", editTieBreaker: "00000000-0000-0000-0000-000000000033" });
    d.focusTasks.push({ ...d.focusTasks[0], id: "00000000-0000-0000-0000-000000000077", title: "Second" });
  }), { base, mode: "skipErased" });
  // Snapshot hours as Records stores them (ScheduleHoursCodec): decoded, re-encoded with sorted keys, fingerprinted.
  const hours = (name, value) => cases.push({ name: `hours/${name}`, kind: "hours", input: typeof value === "string" ? value : text(value) });
  const classic = { startTime: "09:00", endTime: "17:00", workdays: [1, 2, 3, 4, 5], schedule: { mode: "classic" }, breakStartTime: "12:00", breakDurationMinutes: 60 };
  hours("classic", classic);
  hours("no-break", { ...classic, breakStartTime: null, breakDurationMinutes: 0 });
  hours("alternating", { ...classic, schedule: { mode: "alternating", referenceWeekStartMs: 1767571200000, referenceWeekType: "single", singleWeekendWorkday: 6 } });
  hours("rotation-fraction", { ...classic, schedule: { mode: "rotation", rotationAnchorMs: 1767571200000.5, rotationWorkDays: 4, rotationRestDays: 2 } });
  hours("manual-unicode-slash", { ...classic, startTime: "22:00", endTime: "06:00", schedule: { mode: "off" } });
  const ext = v6().extendedSchedule;
  hours("extended", { ...classic, extendedContent: { shiftTypes: ext.shiftTypes, rule: ext.rule, holidayRegionIdentifier: "CN", clearedFromDayKey: null } });
  hours("extended-names", { ...classic, extendedContent: { shiftTypes: [{ ...ext.shiftTypes[0], name: "夜班/Night \"A\" é\n" }], rule: null } });
  hours("extended-no-region", { ...classic, extendedContent: { shiftTypes: ext.shiftTypes, rule: null, clearedFromDayKey: "2026-09-01" } });
  hours("unknown-mode", { ...classic, schedule: { mode: "biweekly" } });
  hours("missing-field", { startTime: "09:00", endTime: "17:00", workdays: [], schedule: { mode: "classic" } });
  hours("extra-live-plan-key", { ...classic, extendedSchedule: { anything: true } });
  return cases;
}

function header(hashes) {
  return `{"fixtureSchemaVersion":1,
"generator":"scripts/generate-android-record-fixtures.mjs",
"note":"Answers of iOS RecordJSON (decode, apply, export). Do not edit by hand.",
"sourceHashes":${JSON.stringify(hashes)},
"cases":`;
}

export function createAndroidRecordFixtures() {
  const work = mkdtempSync(join(tmpdir(), "owc-records-"));
  try {
    const binary = join(work, "export");
    execFileSync("xcrun", [
      "swiftc", "-O", "-swift-version", "6", "-default-isolation", "MainActor",
      ...[...swiftInputs, ...compileOnly].map((path) => resolve(path)),
      "-o", binary,
    ], { stdio: ["ignore", "ignore", "inherit"] });
    const casesPath = join(work, "cases.json");
    const cases = recordCases();
    writeFileSync(casesPath, JSON.stringify(cases));
    const answers = JSON.parse(execFileSync(binary, [casesPath], { cwd: work, maxBuffer: 256 * 1024 * 1024 }).toString("utf8"));
    const rows = cases.map((item, index) => {
      const answer = answers[index];
      if (answer.name !== item.name) throw new Error(`Case order mismatch at ${item.name}`);
      return JSON.stringify({ ...item, expected: answer });
    });
    return `${header(recordSourceHashes())}[\n${rows.join(",\n")}\n]\n}\n`;
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

export function checkRecordSourceHashes(outputPath) {
  let existing;
  try {
    existing = JSON.parse(readFileSync(outputPath, "utf8"));
  } catch {
    return `Android record fixture is missing or unreadable: ${outputPath}`;
  }
  const expected = recordSourceHashes();
  const stale = Object.keys(expected).filter((path) => existing.sourceHashes?.[path] !== expected[path]);
  const casesChanged = JSON.stringify(existing.cases?.map(({ expected: _, ...rest }) => rest)) !== JSON.stringify(recordCases());
  if (stale.length > 0 || casesChanged) {
    return `Android record fixture is stale (${[...stale, ...(casesChanged ? ["cases"] : [])].join(", ")}). On macOS run: npm run generate:android-record-fixtures`;
  }
  return null;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const output = createAndroidRecordFixtures();
  if (process.argv.slice(2).includes("--check")) {
    let existing = "";
    try {
      existing = readFileSync(androidRecordFixturePath, "utf8");
    } catch {}
    if (existing !== output) {
      console.error("Android record fixture is stale. Run: npm run generate:android-record-fixtures");
      process.exitCode = 1;
    }
  } else {
    mkdirSync(dirname(androidRecordFixturePath), { recursive: true });
    writeFileSync(androidRecordFixturePath, output);
  }
}
