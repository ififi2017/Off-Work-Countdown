import Foundation
import Testing
@testable import App

// MARK: - Schema history this file is based on
//
// `git log -p --follow -- .../RecordJSON.swift` shows every real bump of
// `RecordJSON.schemaVersion` and exactly which fields arrived with it:
//
//  - 28da995 (schemaVersion = 1, the very first commit): careerPeriods,
//    scheduleSnapshots, calendarExceptions, dayOverrides, workObservations,
//    lifeProfile. No per-row `timeZoneIdentifier`, no focus tables.
//  - 4eecf6d (same day, still schemaVersion 1): per-row `timeZoneIdentifier`
//    added to CalendarException/DayOverride/WorkObservation rows, and
//    CareerPeriod's own `timeZoneIdentifier`/`calendarIdentifier` became
//    optional. No version bump accompanied this.
//  - 5641dde (still schemaVersion 1): `focusTasks` and `focusSessions` arrays
//    were added to the document. Again no version bump.
//  - 114cef5 bumped schemaVersion **1 -> 3** in one commit: WorkObservation
//    gained optional `editedAtMs`/`editCount`/`editTieBreaker` (migrating to
//    `occurredAt`/1/`eventID` when absent), LifeProfile gained `bornOn`,
//    `schoolStartedOn`, `workStartedPartial`, `retirementOn`,
//    `averageSleepMinutes`, `sleepSource`, `sleepSourceUpdatedAtMs`,
//    FocusTask gained `scheduledStartAtMs`/`icon`/`isFavorite`/`deletedAtMs`/
//    `templateID`/`templateTaskKey`, FocusSession gained `kind`/
//    `timeZoneIdentifier`/`anchorDayKey`/`actualDurationSeconds`/
//    `plannedEndReason`, and the document gained top-level
//    `recordsStartedOn`.
//  - c7af6be bumped schemaVersion 3 -> 4: added `focusPlanningConfiguration`.
//  - 060eb4a bumped schemaVersion 4 -> 5: added `syncedPreferences`, and
//    LifeProfile gained `workHistoryMode`/`roughCurrentSalary`/
//    `employmentPeriods`. `futureIncomeDecline` landed one commit later
//    (85580f1), still under schemaVersion 5.
//
// IMPORTANT — schema version 2 does not exist in this history. No commit
// ever set `RecordJSON.schemaVersion` (or the export path) to 2; the number
// jumped straight from 1 to 3. `acceptedSchemaVersions` accepts a document
// that *claims* schemaVersion 2 (nothing in `decode`/`apply` special-cases
// it), but no real build ever wrote one, so its true on-disk shape cannot be
// established from history. The v2 fixture below assumes the same shape as
// the last real v1 export; that assumption is called out again at its test.

// MARK: - Fixture construction

@MainActor
private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    // By identifier, not `secondsFromGMT: 0` (which is named "GMT"), so the
    // export's file zone and the rows' "UTC" zone are the same name.
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

@MainActor
private func id(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value)) ?? UUID()
}

@MainActor
private func export(_ state: RecordState) throws -> Data {
    let calendar = utcCalendar()
    return try RecordJSON.export(
        state,
        exportedAt: Date(timeIntervalSince1970: 0),
        timeZone: calendar.timeZone,
        calendar: calendar
    )
}

/// One in-memory archive covering every entity kind the current (v5) schema
/// knows about: a career period, a worked day with `customSegments`, a work
/// observation, a Focus task and session, a Focus planning configuration, a
/// life profile carrying both the v3 partial-date fields and the v5 income
/// history fields, and synced preferences. Every date is built from
/// `DateComponents` on an explicit UTC calendar so the fixture is
/// deterministic across machine time zones (AGENTS.md).
///
/// The life-profile fields below are deliberately chosen so that a value
/// *migration* would produce (`.yearOnly(1990)`, `2050`, `450` minutes,
/// `.manual`) differs from the value actually stored (`1990-03-15`, `2055`,
/// `480` minutes, `.healthSuggested`). That way, a v3+ test that reads back
/// the stored value instead of the migrated default proves the DTO is really
/// reading the field, not re-deriving it.
@MainActor
private func fullState() -> RecordState {
    let calendar = utcCalendar()
    let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24))!
    var state = RecordState()

    state.periods = [
        CareerPeriod(
            id: id(1),
            startsOn: day,
            endsBefore: nil,
            label: "Current",
            timeZoneIdentifier: "UTC",
            calendarIdentifier: "gregorian",
            createdAt: day,
            editedAt: day,
            editCount: 1,
            editTieBreaker: id(2)
        )
    ]

    state.overrides = [
        DayOverride(
            dayKey: "2026-08-24",
            shiftAnchorDate: day,
            kind: .customSegments,
            segments: [
                NativeShiftSegment(
                    startAtMs: day.timeIntervalSince1970 * 1_000,
                    endAtMs: day.timeIntervalSince1970 * 1_000 + 8 * 3_600_000
                )
            ],
            note: "Worked a full shift",
            editedAt: day,
            editCount: 1,
            editTieBreaker: id(3),
            timeZoneIdentifier: "UTC"
        )
    ]

    state.observations = [
        WorkObservation(
            eventID: id(4),
            shiftAnchorDate: day,
            occurredAt: day,
            kind: .countdownStarted,
            valueData: Data("manual".utf8),
            scheduleSnapshotID: id(5),
            timeZoneIdentifier: "UTC",
            editedAt: day.addingTimeInterval(60),
            editCount: 3,
            editTieBreaker: id(6)
        )
    ]

    state.focusTasks = [
        FocusTask(
            id: id(7),
            createdAt: day,
            plannedForDate: day,
            scheduledStartAt: day.addingTimeInterval(3_600),
            title: "Write release notes",
            estimatedPomodoros: 2,
            icon: .writing,
            isFavorite: true,
            completedAt: nil,
            deletedAt: nil,
            sortIndex: 0,
            editedAt: day,
            editCount: 2,
            editTieBreaker: id(8),
            templateID: nil,
            templateTaskKey: nil
        )
    ]

    state.focusSessions = [
        FocusSession(
            id: id(9),
            taskID: id(7),
            shiftAnchorDate: day,
            startedAt: day,
            plannedEndAt: day.addingTimeInterval(1_500),
            endedAt: day.addingTimeInterval(1_500),
            endReason: .completed,
            editedAt: day,
            editCount: 1,
            editTieBreaker: id(10),
            kind: .focus,
            timeZoneIdentifier: "UTC",
            anchorDayKey: "2026-08-24",
            actualDurationSeconds: 1_500,
            plannedEndReason: .completed
        )
    ]

    state.focusPlanningConfiguration = FocusPlanningConfiguration(
        planning: FocusPlanningState(
            plans: [
                "2026-08-24": FocusDayPlan(
                    dayKey: "2026-08-24",
                    shiftStartAtMs: Int64(day.timeIntervalSince1970 * 1_000),
                    assignments: [
                        FocusPlanAssignment(
                            blockStartAtMs: Int64(day.timeIntervalSince1970 * 1_000),
                            kind: .task,
                            taskID: id(7),
                            taskTitle: "Write release notes",
                            taskIcon: .writing
                        )
                    ],
                    appliedTemplateID: id(11)
                )
            ],
            templates: [
                FocusTemplate(
                    id: id(11),
                    name: "Release day",
                    slots: [
                        FocusTemplateSlot(
                            blockIndex: 0,
                            kind: .task,
                            taskKey: id(12),
                            taskTitle: "Write release notes",
                            taskIcon: .writing
                        )
                    ],
                    createdAt: day,
                    updatedAt: day
                )
            ],
            defaultTemplateID: id(11),
            autoAppliedDayKeys: ["2026-08-24"]
        ),
        timerSettings: FocusTimerSettings(
            focusMinutes: 40,
            shortBreakMinutes: 8,
            longBreakMinutes: 20,
            longBreakEvery: 3
        ),
        editedAt: day,
        editCount: 4,
        editTieBreaker: id(13)
    )

    state.lifeProfile = LifeProfile(
        birthYear: 1990,
        workStartedOn: day,
        retirementAge: 60,
        averageSleepHours: 7.5,
        hidesExactAges: false,
        bornOn: .exact(year: 1990, month: 3, day: 15)!,
        schoolStartedOn: .yearOnly(1996),
        workStartedPartial: .exact(year: 2015, month: 6, day: 1)!,
        retirementOn: .yearOnly(2055),
        averageSleepMinutes: 480,
        sleepSource: .healthSuggested,
        sleepSourceUpdatedAt: day,
        workHistoryMode: .detailed,
        roughCurrentSalary: LifeSalary(amount: 10_000, cadence: .monthly),
        employmentPeriods: [
            LifeEmploymentPeriod(
                id: id(14),
                startsOn: .exact(year: 2015, month: 6, day: 1)!,
                endsOn: nil,
                salary: LifeSalary(amount: 120_000, cadence: .yearly)
            )
        ],
        futureIncomeDecline: LifeIncomeDecline(startsAtAge: 45, retirementRatio: 0.6),
        editedAt: day,
        editCount: 5,
        editTieBreaker: id(15)
    )

    state.syncedPreferences = SyncedPreferences(
        startMinutes: 9 * 60,
        endMinutes: 17 * 60,
        workdays: [1, 2, 3, 4, 5],
        scheduleMode: .classic,
        alternatingWeekType: .double,
        alternatingWeekendWorkday: 6,
        alternatingReferenceWeekStartMs: day.timeIntervalSince1970 * 1_000,
        rotationWorkDays: 2,
        rotationRestDays: 2,
        rotationAnchorMs: day.timeIntervalSince1970 * 1_000,
        lunchEnabled: true,
        lunchStartMinutes: 12 * 60,
        lunchDurationMinutes: 60,
        recordsTimeZoneIdentifier: "UTC",
        salaryAmount: "64000",
        salaryEnabled: true,
        salaryType: .monthly,
        monthlyWorkingDays: 22,
        annualBonusEnabled: true,
        annualBonusMonths: 2,
        notificationMode: .milestones,
        cycleEndSummaryNotificationEnabled: true,
        lunchStartReminderEnabled: true,
        lunchEndReminderEnabled: true,
        microBreakEnabled: true,
        microBreakIntervalMinutes: 60,
        theme: .auto,
        languageOverride: nil,
        editedAtMs: day.timeIntervalSince1970 * 1_000,
        editCount: 1,
        editTieBreaker: id(16)
    )

    return state
}

private struct FixtureError: Error {}

/// The full v5 export of `fullState()`, decoded back into a plain JSON object
/// so `downgraded(_:to:)` can strip fields by key.
@MainActor
private func baseDocumentObject() throws -> [String: Any] {
    let data = try export(fullState())
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw FixtureError()
    }
    return object
}

/// Removes exactly the keys that had not been introduced yet at `version`,
/// per the commit-by-commit history documented above, and stamps
/// `schemaVersion`. This reproduces what a real build running at that
/// version would have written, rather than guessing at a shape.
private func downgraded(_ object: [String: Any], to version: Int) -> [String: Any] {
    var result = object
    result["schemaVersion"] = version

    if version < 3 {
        result["recordsStartedOn"] = nil

        if var observations = result["workObservations"] as? [[String: Any]] {
            for index in observations.indices {
                observations[index]["editedAtMs"] = nil
                observations[index]["editCount"] = nil
                observations[index]["editTieBreaker"] = nil
            }
            result["workObservations"] = observations
        }

        if var life = result["lifeProfile"] as? [String: Any] {
            for key in [
                "bornOn", "schoolStartedOn", "workStartedPartial", "retirementOn",
                "averageSleepMinutes", "sleepSource", "sleepSourceUpdatedAtMs",
            ] {
                life[key] = nil
            }
            result["lifeProfile"] = life
        }

        if var tasks = result["focusTasks"] as? [[String: Any]] {
            for index in tasks.indices {
                for key in [
                    "scheduledStartAtMs", "icon", "isFavorite", "deletedAtMs",
                    "templateID", "templateTaskKey",
                ] {
                    tasks[index][key] = nil
                }
            }
            result["focusTasks"] = tasks
        }

        if var sessions = result["focusSessions"] as? [[String: Any]] {
            for index in sessions.indices {
                for key in [
                    "kind", "timeZoneIdentifier", "anchorDayKey",
                    "actualDurationSeconds", "plannedEndReason",
                ] {
                    sessions[index][key] = nil
                }
            }
            result["focusSessions"] = sessions
        }
    }

    if version < 4 {
        result["focusPlanningConfiguration"] = nil
    }

    if version < 5 {
        result["syncedPreferences"] = nil
        if var life = result["lifeProfile"] as? [String: Any] {
            for key in ["workHistoryMode", "roughCurrentSalary", "employmentPeriods", "futureIncomeDecline"] {
                life[key] = nil
            }
            result["lifeProfile"] = life
        }
    }

    return result
}

@MainActor
private func importDowngraded(_ baseObject: [String: Any], version: Int) throws -> (RecordState, RecordImportReport) {
    let data = try JSONSerialization.data(withJSONObject: downgraded(baseObject, to: version))
    let document = try RecordJSON.decode(data)
    #expect(document.schemaVersion == version)
    var state = RecordState()
    let report = try RecordJSON.apply(document, to: &state, mode: .skipErased)
    return (state, report)
}

// MARK: - Version-specific imports

@MainActor
@Test("Schema v1 documents import and receive safe defaults for every field introduced later")
func schemaVersion1DocumentImportsWithSafeDefaults() throws {
    let calendar = utcCalendar()
    let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24))!
    let (state, report) = try importDowngraded(try baseDocumentObject(), version: 1)
    #expect(report.rejected.isEmpty)

    // Core business content survives exactly.
    let period = try #require(state.periods.first)
    #expect(period.label == "Current")
    #expect(RecordJSON.dayKey(period.startsOn, calendar: calendar) == "2026-08-24")

    let override = try #require(state.overrides.first)
    #expect(override.kind == .customSegments)
    #expect(override.segments == [
        NativeShiftSegment(
            startAtMs: day.timeIntervalSince1970 * 1_000,
            endAtMs: day.timeIntervalSince1970 * 1_000 + 8 * 3_600_000
        )
    ])
    #expect(override.note == "Worked a full shift")

    let observation = try #require(state.observations.first)
    #expect(observation.kind == .countdownStarted)
    #expect(observation.valueData == Data("manual".utf8))
    // v3 edit stamps are absent from a v1 document: they migrate to the
    // observation's own immutable event values.
    #expect(observation.editedAt == day)
    #expect(observation.editCount == 1)
    #expect(observation.editTieBreaker == id(4))

    let task = try #require(state.focusTasks.first)
    #expect(task.title == "Write release notes")
    #expect(task.estimatedPomodoros == 2)
    #expect(task.icon == .focus)
    #expect(task.isFavorite == false)
    #expect(task.scheduledStartAt == nil)
    #expect(task.deletedAt == nil)
    #expect(task.templateID == nil)

    let session = try #require(state.focusSessions.first)
    #expect(session.startedAt == day)
    #expect(session.plannedEndAt == day.addingTimeInterval(1_500))
    #expect(session.endedAt == day.addingTimeInterval(1_500))
    #expect(session.endReason == .completed)
    #expect(session.kind == .focus)
    // A v1 session carried no zone of its own; it inherits the file's zone.
    #expect(session.timeZoneIdentifier == calendar.timeZone.identifier)
    #expect(session.anchorDayKey == "2026-08-24")
    #expect(session.actualDurationSeconds == nil)
    // 1500s planned duration == 25 minutes, so FocusPlanner.endReason
    // computes `.completed` even though the document never carried the field.
    #expect(session.plannedEndReason == .completed)

    let profile = try #require(state.lifeProfile)
    #expect(profile.birthYear == 1990)
    #expect(profile.retirementAge == 60)
    #expect(profile.averageSleepHours == 7.5)
    #expect(profile.workStartedOn == day)
    // `migrateLegacyFields`, run at the end of every `apply`, derives these
    // from the v1 fields it does have.
    #expect(profile.bornOn == .yearOnly(1990))
    #expect(profile.workStartedPartial == .exact(year: 2026, month: 8, day: 24))
    #expect(profile.retirementOn == .yearOnly(1990 + 60))
    #expect(profile.averageSleepMinutes == 450)
    #expect(profile.sleepSource == .manual)
    // v5-only fields default safely.
    #expect(profile.workHistoryMode == .rough)
    #expect(profile.roughCurrentSalary == nil)
    #expect(profile.employmentPeriods.isEmpty)
    #expect(profile.futureIncomeDecline == nil)

    // Rows that did not exist yet at v1.
    #expect(state.focusPlanningConfiguration == nil)
    #expect(state.syncedPreferences == nil)
}

@MainActor
@Test(
    "Schema v2 documents import the same way v1 does (no v2 shape exists in this project's history)"
)
func schemaVersion2DocumentImportsLikeV1() throws {
    // No commit ever set `RecordJSON.schemaVersion` to 2 — the constant
    // jumped from 1 straight to 3 (114cef5). `acceptedSchemaVersions`
    // tolerates a document that claims version 2, and the only fields a v1
    // build could have written are the v1 fields, so this fixture is
    // identical in shape to the v1 one above with only the version number
    // changed. This is an assumption about an undocumented gap, not a
    // verified historical shape.
    let calendar = utcCalendar()
    let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24))!
    let (state, report) = try importDowngraded(try baseDocumentObject(), version: 2)
    #expect(report.rejected.isEmpty)

    #expect(state.periods.count == 1)
    #expect(state.overrides.count == 1)
    let observation = try #require(state.observations.first)
    #expect(observation.editedAt == day)
    #expect(observation.editCount == 1)
    #expect(observation.editTieBreaker == id(4))

    let task = try #require(state.focusTasks.first)
    #expect(task.icon == .focus)
    #expect(task.isFavorite == false)

    let profile = try #require(state.lifeProfile)
    #expect(profile.bornOn == .yearOnly(1990))
    #expect(profile.workHistoryMode == .rough)
    #expect(profile.employmentPeriods.isEmpty)

    #expect(state.focusPlanningConfiguration == nil)
    #expect(state.syncedPreferences == nil)
}

@MainActor
@Test("Schema v3 documents preserve the fields 114cef5 introduced and still default v5-only fields")
func schemaVersion3DocumentPreservesIntroducedFields() throws {
    let day = utcCalendar().date(from: DateComponents(year: 2026, month: 8, day: 24))!
    let (state, report) = try importDowngraded(try baseDocumentObject(), version: 3)
    #expect(report.rejected.isEmpty)

    let observation = try #require(state.observations.first)
    #expect(observation.editedAt == day.addingTimeInterval(60))
    #expect(observation.editCount == 3)
    #expect(observation.editTieBreaker == id(6))

    let task = try #require(state.focusTasks.first)
    #expect(task.icon == .writing)
    #expect(task.isFavorite)
    #expect(task.scheduledStartAt == day.addingTimeInterval(3_600))

    let session = try #require(state.focusSessions.first)
    #expect(session.actualDurationSeconds == 1_500)
    #expect(session.plannedEndReason == .completed)

    let profile = try #require(state.lifeProfile)
    // These values were deliberately chosen to differ from what
    // `migrateLegacyFields` would derive, so reading them back proves the
    // v3 fields themselves were decoded rather than defaulted.
    #expect(profile.bornOn == .exact(year: 1990, month: 3, day: 15))
    #expect(profile.schoolStartedOn == .yearOnly(1996))
    #expect(profile.workStartedPartial == .exact(year: 2015, month: 6, day: 1))
    #expect(profile.retirementOn == .yearOnly(2055))
    #expect(profile.averageSleepMinutes == 480)
    #expect(profile.sleepSource == .healthSuggested)
    // workHistoryMode is not `.detailed` here (it is a v5 field, absent from
    // a v3 document), so the migration that recomputes `workStartedOn` from
    // `employmentPeriods` never fires and the v1 field survives untouched.
    #expect(profile.workStartedOn == day)
    // v5-only fields still default safely.
    #expect(profile.workHistoryMode == .rough)
    #expect(profile.roughCurrentSalary == nil)
    #expect(profile.employmentPeriods.isEmpty)
    #expect(profile.futureIncomeDecline == nil)

    #expect(state.focusPlanningConfiguration == nil)
    #expect(state.syncedPreferences == nil)
}

@MainActor
@Test("Schema v4 documents preserve Focus planning configuration and still default v5-only life fields")
func schemaVersion4DocumentPreservesFocusPlanningConfiguration() throws {
    let (state, report) = try importDowngraded(try baseDocumentObject(), version: 4)
    #expect(report.rejected.isEmpty)

    let configuration = try #require(state.focusPlanningConfiguration)
    #expect(configuration == fullState().focusPlanningConfiguration)
    #expect(configuration.planning.plans.count == 1)
    #expect(configuration.planning.templates.count == 1)
    #expect(configuration.timerSettings.focusMinutes == 40)

    let profile = try #require(state.lifeProfile)
    #expect(profile.workHistoryMode == .rough)
    #expect(profile.roughCurrentSalary == nil)
    #expect(profile.employmentPeriods.isEmpty)
    #expect(profile.futureIncomeDecline == nil)

    #expect(state.syncedPreferences == nil)
}

@MainActor
@Test("Schema v5 documents preserve synced preferences and the full life income history exactly")
func schemaVersion5DocumentPreservesEverything() throws {
    let calendar = utcCalendar()
    let (state, report) = try importDowngraded(try baseDocumentObject(), version: 5)
    #expect(report.rejected.isEmpty)

    let profile = try #require(state.lifeProfile)
    #expect(profile.workHistoryMode == .detailed)
    #expect(profile.roughCurrentSalary == LifeSalary(amount: 10_000, cadence: .monthly))
    #expect(profile.employmentPeriods == [
        LifeEmploymentPeriod(
            id: id(14),
            startsOn: .exact(year: 2015, month: 6, day: 1)!,
            endsOn: nil,
            salary: LifeSalary(amount: 120_000, cadence: .yearly)
        )
    ])
    #expect(profile.futureIncomeDecline == LifeIncomeDecline(startsAtAge: 45, retirementRatio: 0.6))
    // Because `workHistoryMode == .detailed` and there is exactly one
    // employment period, `migrateLegacyFields` recomputes `workStartedOn`
    // from that period's start rather than keeping the v1 field's value —
    // this is existing, intentional behaviour, not a defaulting bug.
    let earliestEmploymentStart = calendar.date(from: DateComponents(year: 2015, month: 6, day: 1))!
    #expect(profile.workStartedOn == earliestEmploymentStart)

    let preferences = try #require(state.syncedPreferences)
    #expect(preferences == fullState().syncedPreferences)
    #expect(preferences.salaryAmount == "64000")
    #expect(preferences.workdays == [1, 2, 3, 4, 5])

    let configuration = try #require(state.focusPlanningConfiguration)
    #expect(configuration == fullState().focusPlanningConfiguration)
}

// MARK: - Cross-version guarantees

@MainActor
@Test(
    "Every accepted schema version (1-5) imports without dropping a row, and re-exports at the current schemaVersion idempotently"
)
func everyAcceptedSchemaVersionReexportsIdempotentlyWithoutDroppingRows() throws {
    let baseObject = try baseDocumentObject()

    for version in RecordJSON.acceptedSchemaVersions {
        let (imported, firstReport) = try importDowngraded(baseObject, version: version)
        #expect(firstReport.rejected.isEmpty, "v\(version): rows were rejected: \(firstReport.rejected)")

        #expect(imported.periods.count == 1, "v\(version): careerPeriod count")
        #expect(imported.overrides.count == 1, "v\(version): dayOverride count")
        #expect(imported.observations.count == 1, "v\(version): workObservation count")
        #expect(imported.focusTasks.count == 1, "v\(version): focusTask count")
        #expect(imported.focusSessions.count == 1, "v\(version): focusSession count")
        #expect(imported.lifeProfile != nil, "v\(version): lifeProfile present")
        #expect(
            (imported.focusPlanningConfiguration != nil) == (version >= 4),
            "v\(version): focusPlanningConfiguration presence"
        )
        #expect(
            (imported.syncedPreferences != nil) == (version >= 5),
            "v\(version): syncedPreferences presence"
        )

        // Re-export always writes the current schema version...
        var state = imported
        let reexported = try export(state)
        let reexportedDocument = try RecordJSON.decode(reexported)
        #expect(reexportedDocument.schemaVersion == RecordJSON.schemaVersion, "v\(version): re-export version")

        // ...and reimporting that current-version document changes nothing:
        // no new inserts, no conflicts, nothing rejected.
        let secondReport = try RecordJSON.apply(reexportedDocument, to: &state, mode: .skipErased)
        #expect(secondReport.inserted.isEmpty, "v\(version): reimport inserted new rows: \(secondReport.inserted)")
        #expect(secondReport.conflicts.isEmpty, "v\(version): reimport produced conflicts: \(secondReport.conflicts)")
        #expect(secondReport.rejected.isEmpty, "v\(version): reimport rejected rows: \(secondReport.rejected)")
    }
}

@MainActor
@Test("An on-disk archive written by an older build reopens through RecordArchive's cold-load path")
func coldArchiveWithOlderSchemaReopens() throws {
    let downgradedData = try JSONSerialization.data(withJSONObject: downgraded(try baseDocumentObject(), to: 3))
    let localFile = RecordLocalFile(schemaVersion: 3, document: downgradedData, erased: [], sync: nil)
    let fileData = try JSONEncoder().encode(localFile)

    let directory = FileManager.default.temporaryDirectory
        .appending(path: "record-schema-compat-\(UUID())", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appending(path: "archive.json")
    try fileData.write(to: fileURL, options: .atomic)

    let result = RecordArchive.loadSynchronously(from: fileURL)
    guard case .loaded(let state, _) = result else {
        Issue.record("Expected the v3 archive to load, got \(result)")
        return
    }

    #expect(state.periods.count == 1)
    #expect(state.overrides.count == 1)
    #expect(state.observations.count == 1)
    #expect(state.focusTasks.count == 1)
    #expect(state.focusSessions.count == 1)
    // v3 predates focusPlanningConfiguration (v4) and syncedPreferences (v5).
    #expect(state.focusPlanningConfiguration == nil)
    #expect(state.syncedPreferences == nil)
    #expect(state.lifeProfile?.workHistoryMode == .rough)
}

@MainActor
@Test("Schema versions outside 1...5 are rejected without mutating existing state")
func outOfRangeSchemaVersionsAreRejectedWithoutMutatingState() throws {
    var state = fullState()
    let before = state
    var document = try RecordJSON.decode(try export(fullState()))

    document.schemaVersion = 0
    do {
        _ = try RecordJSON.apply(document, to: &state, mode: .skipErased)
        Issue.record("Expected schemaVersion 0 to be rejected")
    } catch RecordJSONError.unknownSchemaVersion(let version) {
        #expect(version == 0)
    } catch {
        Issue.record("Unexpected error for schemaVersion 0: \(error)")
    }
    #expect(state == before)

    document.schemaVersion = 6
    do {
        _ = try RecordJSON.apply(document, to: &state, mode: .skipErased)
        Issue.record("Expected schemaVersion 6 to be rejected")
    } catch RecordJSONError.unknownSchemaVersion(let version) {
        #expect(version == 6)
    } catch {
        Issue.record("Unexpected error for schemaVersion 6: \(error)")
    }
    #expect(state == before)

    // `decode` (the entry point every real import/reopen goes through) gates
    // the same way, before `apply` is ever reached.
    #expect(throws: RecordJSONError.unknownSchemaVersion(0)) {
        var zero = document
        zero.schemaVersion = 0
        _ = try RecordJSON.decode(try JSONEncoder().encode(zero))
    }
}
