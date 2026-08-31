import Foundation
import Testing
@testable import App

@MainActor
@Test("A retry reuses eventID and a second click is a new observation")
func observationEventIDIsIdempotentPerWrite() {
    let records = RecordCoordinator.inMemory()
    let day = startOf(2026, 8, 24)
    let snapshotID = UUID()
    let firstID = UUID()
    records.recordObservation(
        kind: .countdownStarted,
        eventID: firstID,
        shiftAnchorDate: day,
        occurredAt: day,
        snapshotID: snapshotID
    )
    records.recordObservation(
        kind: .countdownStarted,
        eventID: firstID,
        shiftAnchorDate: day,
        occurredAt: day,
        snapshotID: snapshotID
    )
    records.recordObservation(
        kind: .countdownStarted,
        eventID: UUID(),
        shiftAnchorDate: day,
        occurredAt: day.addingTimeInterval(1),
        snapshotID: snapshotID
    )
    #expect(records.state.observations.count == 2)
}

@MainActor
@Test("Remote batches notify the store only after their durable write")
func remoteBatchInvokesReconciliationHook() {
    let records = RecordCoordinator.inMemory()
    var calls = 0
    records.onRemoteBatchApplied = { calls += 1 }
    records.persistRemoteBatch()
    #expect(calls == 1)
}

@MainActor
@Test("Sharing cancellation stays quiet while a failed activity is actionable")
func exportShareFailuresAreActionable() {
    #expect(RecordsOperationError.exportShareFailure(completed: false, activityWasSelected: false, error: nil) == nil)
    #expect(RecordsOperationError.exportShareFailure(completed: false, activityWasSelected: true, error: nil) == .exportFailed)
    #expect(
        RecordsOperationError.exportShareFailure(
            completed: false,
            activityWasSelected: false,
            error: CocoaError(.fileWriteUnknown)
        ) == .exportFailed
    )
}

@MainActor
@Test("First-seen is once per shift day; start/stop/overtime stay distinct")
func observationKindsStayDistinct() {
    let store = OffWorkStore(defaults: isolatedRecordDefaults())
    store.onboardingComplete = true
    store.scheduleMode = .off
    let monday = date(2026, 8, 24, 9)
    store.noteTimerSurfaceVisible(at: monday)
    store.noteTimerSurfaceVisible(at: monday.addingTimeInterval(60))
    store.startCountdown(at: monday)
    store.stopCountdown(at: monday.addingTimeInterval(30))
    store.startCountdown(at: monday.addingTimeInterval(45))
    store.applyOvertime(date: monday.addingTimeInterval(90))

    let kinds = store.records.state.observations.map(\.kind)
    #expect(kinds.filter { $0 == .timerSurfaceFirstSeen }.count == 1)
    #expect(kinds.filter { $0 == .countdownStarted }.count == 2)
    #expect(kinds.filter { $0 == .countdownStopped }.count == 1)
    #expect(kinds.filter { $0 == .overtimeDeclared }.count == 1)
}

@MainActor
@Test("Reconcile reconnects without writing another start")
func reconcileDoesNotRecordStart() {
    let store = OffWorkStore(defaults: isolatedRecordDefaults())
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    let monday = date(2026, 8, 24, 10)
    store.startCountdown(at: monday)
    let afterStart = store.records.state.observations.filter { $0.kind == .countdownStarted }.count
    _ = store.reconcileCountdownSession(at: monday.addingTimeInterval(60))
    let afterReconcile = store.records.state.observations.filter { $0.kind == .countdownStarted }.count
    #expect(afterStart == 1)
    #expect(afterReconcile == 1)
}

@MainActor
@Test("Overnight first-seen keys the shift start day")
func overnightObservationKeysStartDay() {
    let store = OffWorkStore(defaults: isolatedRecordDefaults())
    store.onboardingComplete = true
    store.startMinutes = 22 * 60
    store.endMinutes = 6 * 60
    store.workdays = [5]
    store.scheduleMode = .classic
    let saturdayMorning = date(2026, 8, 29, 1)
    store.noteTimerSurfaceVisible(at: saturdayMorning)
    let observation = store.records.state.observations.first { $0.kind == .timerSurfaceFirstSeen }
    #expect(observation != nil)
    #expect(OffWorkStore.dayKey(for: observation!.shiftAnchorDate) == "2026-08-28")
}

@MainActor
@Test("Deleted observations are not rebuilt from the same eventID")
func erasedObservationIsNotRecreated() {
    let records = RecordCoordinator.inMemory()
    let eventID = UUID()
    let day = startOf(2026, 8, 24)
    records.recordObservation(
        kind: .countdownStarted,
        eventID: eventID,
        shiftAnchorDate: day,
        occurredAt: day,
        snapshotID: UUID()
    )
    records.erase(.workObservation, key: eventID.uuidString, at: day)
    records.recordObservation(
        kind: .countdownStarted,
        eventID: eventID,
        shiftAnchorDate: day,
        occurredAt: day,
        snapshotID: UUID()
    )
    #expect(records.state.observations.isEmpty)
}

@MainActor
@Test("A seeded store can resolve a week of schedule days")
func resolvedDaysUseTheSeededSnapshot() {
    let store = OffWorkStore(defaults: isolatedRecordDefaults())
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    let from = startOf(2026, 8, 24)
    let through = startOf(2026, 8, 30)
    let days = store.resolvedDays(from: from, through: through, now: from)
    #expect(days.count == 7)
    #expect(days.filter(\.isScheduledWorkday).count == 5)
    #expect(days[0].layer == .schedule)
    #expect(days[5].isScheduledWorkday == false)
}

@MainActor
@Test("A second schedule save on the same day updates the winning snapshot")
func sameDayScheduleSaveUpdatesWinningSnapshot() throws {
    let records = RecordCoordinator.inMemory()
    let day = startOf(2026, 8, 24)
    let oldHours = sampleHours()
    let newHours = ScheduleHoursConfiguration(
        startTime: "10:00",
        endTime: "19:00",
        workdays: [1, 2, 3, 4, 5],
        schedule: oldHours.schedule,
        breakStartTime: "12:30",
        breakDurationMinutes: 90
    )
    records.ensureSeeded(hours: oldHours, at: day)
    let originalID = try #require(records.state.snapshots.first?.id)

    #expect(records.commitHours(newHours, effectiveFrom: day, at: date(2026, 8, 24, 12)))

    let period = try #require(DayRecordResolver.period(on: day, from: records.state.periods))
    let winner = try #require(
        DayRecordResolver.snapshot(on: day, in: period, from: records.state.snapshots)
    )
    let decoded = try JSONDecoder().decode(
        ScheduleHoursConfiguration.self,
        from: winner.configurationData
    )
    #expect(records.state.snapshots.count == 1)
    #expect(winner.id == originalID)
    #expect(winner.editCount == 2)
    #expect(decoded.startTime == "10:00")
    #expect(decoded.endTime == "19:00")
    #expect(decoded.breakStartTime == "12:30")
    #expect(decoded.breakDurationMinutes == 90)
}

@MainActor
@Test("Schedule reconciliation never creates the first Records row")
func scheduleReconciliationDoesNotSeedAnEmptyArchive() {
    let records = RecordCoordinator.inMemory()
    let day = startOf(2026, 8, 24)

    #expect(!records.reconcileExistingHours(sampleHours(), effectiveFrom: day, at: day))
    #expect(records.state.periods.isEmpty)
    #expect(records.state.snapshots.isEmpty)
}

@MainActor
@Test("Coordinator export then import after erase still skips")
func coordinatorImportHonorsErasedIDs() throws {
    let records = RecordCoordinator.inMemory()
    let hours = ScheduleHoursConfiguration(
        startTime: "09:00",
        endTime: "17:00",
        workdays: [1, 2, 3, 4, 5],
        schedule: NativeWorkSchedule(
            mode: "classic",
            referenceWeekStartMs: nil,
            referenceWeekType: nil,
            singleWeekendWorkday: nil,
            rotationAnchorMs: nil,
            rotationWorkDays: nil,
            rotationRestDays: nil
        ),
        breakStartTime: nil,
        breakDurationMinutes: 0
    )
    records.ensureSeeded(hours: hours, at: startOf(2026, 8, 24))
    let periodID = records.state.periods[0].id
    let data = try records.exportJSON(exportedAt: startOf(2026, 8, 24), timeZone: TimeZone(secondsFromGMT: 0)!)
    records.erase(.careerPeriod, key: periodID.uuidString, at: startOf(2026, 8, 25))
    let report = try records.import(data, mode: .skipErased)
    #expect(report.skippedErased[.careerPeriod] == 1)
    #expect(records.state.periods.isEmpty)
}

@MainActor
@Test("Import parks unresolved same-id conflicts for later review")
func coordinatorImportParksUnresolvedConflicts() throws {
    let records = RecordCoordinator.inMemory()
    let day = startOf(2026, 8, 24)
    records.upsertOverride(
        DayOverride(
            dayKey: "2026-08-24",
            shiftAnchorDate: day,
            kind: .notWorking,
            segments: [],
            note: "local",
            editedAt: day,
            editCount: 2,
            editTieBreaker: recordID(21)
        ),
        at: day
    )
    var incoming = RecordState()
    incoming.overrides = [
        DayOverride(
            dayKey: "2026-08-24",
            shiftAnchorDate: day,
            kind: .customSegments,
            segments: [NativeShiftSegment(startAtMs: 1, endAtMs: 2)],
            note: "incoming",
            editedAt: day,
            editCount: 1,
            editTieBreaker: recordID(22)
        )
    ]
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let data = try RecordJSON.export(
        incoming,
        exportedAt: day,
        timeZone: calendar.timeZone,
        calendar: calendar
    )
    let report = try records.import(data)
    #expect(report.conflicts.count == 1)
    #expect(records.state.overrides[0].note == "local")
    #expect(records.state.sync.conflicts.count == 1)
    #expect(records.state.sync.conflicts[0].logicalKey == "2026-08-24")
    #expect(records.state.sync.conflicts[0].source == "import")
    #expect(records.state.sync.conflicts[0].localPayload != nil)
    #expect(records.state.sync.conflicts[0].incomingPayload != nil)
    #expect(records.state.sync.conflicts[0].currentWinner == .local)
}

@MainActor
@Test("Resolving a conflict writes a version above both candidates before consuming it")
func conflictResolutionBumpsAboveBothCandidates() throws {
    let records = RecordCoordinator.inMemory()
    let day = startOf(2026, 8, 24)
    let local = DayOverride(
        dayKey: "2026-08-24",
        shiftAnchorDate: day,
        kind: .notWorking,
        segments: [],
        note: "local",
        editedAt: day,
        editCount: 9,
        editTieBreaker: recordID(80),
        timeZoneIdentifier: "UTC"
    )
    records.applyIncomingValue(.override(local))
    var incoming = local
    incoming.kind = .confirmedAsScheduled
    incoming.note = "incoming"
    incoming.editCount = 20
    incoming.editTieBreaker = recordID(81)
    let calendar = RecordsSyncPayload.fileCalendar(for: records.state)
    let localPayload = try #require(RecordsSyncPayload.encode(
        type: .dayOverride,
        key: local.dayKey,
        from: records.state
    ))
    let incomingPayload = try #require(RecordsSyncPayload.encode(.override(incoming), calendar: calendar))
    let conflict = SyncConflictCopy(
        entityType: .dayOverride,
        logicalKey: local.dayKey,
        payload: incomingPayload,
        lostAtMs: 0,
        localPayload: localPayload,
        incomingPayload: incomingPayload,
        currentWinner: .local
    )
    var sync = records.state.sync
    sync.conflicts = [conflict]
    #expect(records.replaceSyncState(sync))

    records.restoreConflict(conflict)
    let resolved = try #require(records.state.overrides.first)
    #expect(resolved.kind == .confirmedAsScheduled)
    #expect(resolved.editCount == 21)
    #expect(records.state.sync.conflicts.isEmpty)
}

@MainActor
@Test("Keeping the current conflict version also writes a newer sync stamp")
func keepCurrentConflictWritesNewVersion() throws {
    let records = RecordCoordinator.inMemory()
    let day = startOf(2026, 8, 24)
    let local = DayOverride(
        dayKey: "2026-08-24",
        shiftAnchorDate: day,
        kind: .notWorking,
        segments: [],
        note: "local",
        editedAt: day,
        editCount: 9,
        editTieBreaker: recordID(82),
        timeZoneIdentifier: "UTC"
    )
    records.applyIncomingValue(.override(local))
    var incoming = local
    incoming.editCount = 20
    incoming.editTieBreaker = recordID(83)
    let calendar = RecordsSyncPayload.fileCalendar(for: records.state)
    let localPayload = try #require(RecordsSyncPayload.encode(
        type: .dayOverride,
        key: local.dayKey,
        from: records.state
    ))
    let incomingPayload = try #require(RecordsSyncPayload.encode(.override(incoming), calendar: calendar))
    let conflict = SyncConflictCopy(
        entityType: .dayOverride,
        logicalKey: local.dayKey,
        payload: incomingPayload,
        lostAtMs: 0,
        localPayload: localPayload,
        incomingPayload: incomingPayload,
        currentWinner: .local
    )
    var sync = records.state.sync
    sync.conflicts = [conflict]
    #expect(records.replaceSyncState(sync))

    records.keepCurrentConflict(conflict)
    let resolved = try #require(records.state.overrides.first)
    #expect(resolved.note == "local")
    #expect(resolved.editCount == 21)
    #expect(records.state.sync.conflicts.isEmpty)
    let row = records.state.sync.rows[RecordsSyncIdentity.recordName(type: .dayOverride, key: local.dayKey)]
    #expect(row?.dirty == true)
    #expect(row?.editCount == 21)
}

@MainActor
@Test("Choosing the other observation version replaces its payload and out-ranks the old server row")
func restoringObservationConflictReplacesSameEventAndWinsLaterFetch() throws {
    let records = RecordCoordinator.inMemory()
    let day = startOf(2026, 8, 24)
    let eventID = recordID(84)
    let snapshotID = recordID(85)
    var local = WorkObservation(
        eventID: eventID,
        shiftAnchorDate: day,
        occurredAt: day,
        kind: .countdownStarted,
        valueData: Data("local".utf8),
        scheduleSnapshotID: snapshotID,
        timeZoneIdentifier: "UTC",
        editedAt: day,
        editCount: 9,
        editTieBreaker: recordID(86)
    )
    records.applyIncomingValue(.observation(local))
    local = try #require(records.state.observations.first)
    var incoming = local
    incoming.kind = .countdownStopped
    incoming.valueData = Data("other".utf8)
    incoming.editedAt = day.addingTimeInterval(60)
    incoming.editCount = 20
    incoming.editTieBreaker = recordID(87)
    let calendar = RecordsSyncPayload.fileCalendar(for: records.state)
    let localPayload = try #require(RecordsSyncPayload.encode(
        type: .workObservation,
        key: eventID.uuidString,
        from: records.state
    ))
    let incomingPayload = try #require(RecordsSyncPayload.encode(.observation(incoming), calendar: calendar))
    let conflict = SyncConflictCopy(
        entityType: .workObservation,
        logicalKey: eventID.uuidString,
        payload: incomingPayload,
        lostAtMs: 0,
        localPayload: localPayload,
        incomingPayload: incomingPayload,
        currentWinner: .local
    )
    var sync = records.state.sync
    sync.conflicts = [conflict]
    #expect(records.replaceSyncState(sync))

    records.restoreConflict(conflict)
    let resolved = try #require(records.state.observations.first)
    #expect(records.state.observations.count == 1)
    #expect(resolved.eventID == eventID)
    #expect(resolved.kind == .countdownStopped)
    #expect(resolved.valueData == Data("other".utf8))
    #expect(resolved.editCount == 21)
    #expect(records.state.sync.conflicts.isEmpty)

    records.applyRemotePayload(
        type: .workObservation,
        key: eventID.uuidString,
        payload: incomingPayload,
        editCount: incoming.editCount,
        editTieBreaker: incoming.editTieBreaker.uuidString,
        systemFields: nil,
        generation: 1
    )
    let afterOldFetch = try #require(records.state.observations.first)
    #expect(afterOldFetch.kind == .countdownStopped)
    #expect(afterOldFetch.valueData == Data("other".utf8))
    #expect(afterOldFetch.editCount == 21)
    #expect(records.state.sync.rows[
        RecordsSyncIdentity.recordName(type: .workObservation, key: eventID.uuidString)
    ]?.dirty == true)
}

@MainActor
@Test("Migrating the records time zone keeps civil day keys")
func migrateCalendarTimeZoneKeepsDayKeys() {
    let records = RecordCoordinator.inMemory()
    let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    let hours = ScheduleHoursConfiguration(
        startTime: "09:00",
        endTime: "17:00",
        workdays: [1, 2, 3, 4, 5],
        schedule: NativeWorkSchedule(
            mode: "classic",
            referenceWeekStartMs: nil,
            referenceWeekType: nil,
            singleWeekendWorkday: nil,
            rotationAnchorMs: nil,
            rotationWorkDays: nil,
            rotationRestDays: nil
        ),
        breakStartTime: nil,
        breakDurationMinutes: 0
    )
    records.ensureSeeded(hours: hours, at: startOf(2026, 8, 24), timeZone: shanghai)
    let snapshotEditCount = records.state.snapshots[0].editCount
    var shanghaiCalendar = Calendar(identifier: .gregorian)
    shanghaiCalendar.timeZone = shanghai
    let civilAnchor = shanghaiCalendar.date(from: DateComponents(year: 2026, month: 8, day: 24))!
    records.upsertException(
        CalendarException(
            dayKey: "2026-08-24#user",
            date: civilAnchor,
            effect: .rest,
            origin: .user,
            isCleared: false,
            regionIdentifier: nil,
            datasetVersion: nil,
            label: nil,
            editedAt: civilAnchor,
            editCount: 1,
            editTieBreaker: recordID(20),
            timeZoneIdentifier: shanghai.identifier
        )
    )
    let occurredAt = Date(timeIntervalSince1970: 1_777_000_123)
    records.recordObservation(
        kind: .countdownStarted,
        eventID: recordID(21),
        shiftAnchorDate: civilAnchor,
        occurredAt: occurredAt,
        snapshotID: records.state.snapshots[0].id,
        timeZoneIdentifier: shanghai.identifier
    )
    records.updateLifeProfile(
        LifeProfile(
            workStartedOn: civilAnchor,
            editedAt: civilAnchor,
            editCount: 2,
            editTieBreaker: recordID(22)
        )
    )
    records.upsertOverride(
        DayOverride(
            dayKey: "2026-08-24",
            shiftAnchorDate: startOf(2026, 8, 24),
            kind: .notWorking,
            segments: [],
            timeZoneIdentifier: shanghai.identifier
        )
    )
    records.migrateCalendarTimeZone(to: "America/Los_Angeles", at: startOf(2026, 8, 25))
    #expect(records.state.periods[0].timeZoneIdentifier == "America/Los_Angeles")
    var losAngelesCalendar = Calendar(identifier: .gregorian)
    losAngelesCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    #expect(RecordJSON.dayKey(records.state.periods[0].startsOn, calendar: losAngelesCalendar) == "2026-08-24")
    #expect(RecordJSON.dayKey(records.state.snapshots[0].effectiveFrom, calendar: losAngelesCalendar) == "2026-08-24")
    #expect(records.state.snapshots[0].editCount == snapshotEditCount + 1)
    #expect(records.state.overrides[0].dayKey == "2026-08-24")
    #expect(records.state.overrides[0].timeZoneIdentifier == "America/Los_Angeles")
    #expect(RecordJSON.dayKey(records.state.overrides[0].shiftAnchorDate, calendar: losAngelesCalendar) == "2026-08-24")
    #expect(RecordJSON.dayKey(records.state.exceptions[0].date, calendar: losAngelesCalendar) == "2026-08-24")
    let migratedObservation = records.state.observations[0]
    #expect(migratedObservation.eventID != recordID(21))
    #expect(RecordJSON.dayKey(migratedObservation.shiftAnchorDate, calendar: losAngelesCalendar) == "2026-08-24")
    #expect(migratedObservation.occurredAt == occurredAt)
    #expect(records.state.isErased(.workObservation, key: recordID(21).uuidString))
    let erasedRowName = RecordsSyncIdentity.recordName(type: .workObservation, key: recordID(21).uuidString)
    #expect(records.state.sync.rows[erasedRowName]?.pendingErase == true)
    let migratedRowName = RecordsSyncIdentity.recordName(
        type: .workObservation,
        key: migratedObservation.eventID.uuidString
    )
    #expect(records.state.sync.rows[migratedRowName]?.dirty == true)
    #expect(records.state.sync.rows[migratedRowName]?.pendingErase == false)
    #expect(RecordJSON.dayKey(records.state.lifeProfile!.workStartedOn!, calendar: losAngelesCalendar) == "2026-08-24")
    #expect(records.state.lifeProfile!.editCount == 4)
}

@MainActor
@Test("A fetched row for a locally erased identity re-enters the erase outbox")
func remotePayloadReassertsPermanentErase() throws {
    let records = RecordCoordinator.inMemory()
    let key = "2026-08-24"
    let day = startOf(2026, 8, 24)
    records.erase(.dayOverride, key: key, at: day)
    var sync = records.state.sync
    let rowName = RecordsSyncIdentity.recordName(type: .dayOverride, key: key)
    RecordsSyncOutbox.clearDirty(&sync, recordName: rowName)
    records.replaceSyncState(sync)
    #expect(RecordsSyncOutbox.pending(records.state.sync).isEmpty)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let payload = try #require(
        RecordsSyncPayload.encode(
            .override(
                DayOverride(
                    dayKey: key,
                    shiftAnchorDate: day,
                    kind: .notWorking,
                    segments: []
                )
            ),
            calendar: calendar
        )
    )
    records.applyRemotePayload(
        type: .dayOverride,
        key: key,
        payload: payload,
        editCount: 9,
        editTieBreaker: "remote",
        systemFields: nil,
        generation: 1
    )

    #expect(records.state.overrides.isEmpty)
    #expect(records.state.sync.rows[rowName]?.dirty == true)
    #expect(records.state.sync.rows[rowName]?.pendingErase == true)
}

@MainActor
@Test("A failed sync-state write leaves the last durable state active")
func syncStateWriteFailureIsTransactional() {
    let missingParent = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        .appending(path: "archive.json")
    let records = RecordCoordinator(fileURL: missingParent)
    let original = records.state.sync
    var changed = original
    changed.accountID = "account-a"
    changed.syncEnabled = true

    #expect(!records.replaceSyncState(changed))
    #expect(records.state.sync == original)
    #expect(records.persistenceError == .writeFailed)
}

@MainActor
@Test("The same observation migration converges on one replacement identity")
func observationMigrationIdentityIsDeterministic() {
    let eventID = recordID(23)
    let snapshotID = recordID(24)
    let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = shanghai
    let anchor = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24))!

    func migratedID() -> UUID {
        let records = RecordCoordinator.inMemory()
        records.recordObservation(
            kind: .countdownStarted,
            eventID: eventID,
            shiftAnchorDate: anchor,
            occurredAt: anchor.addingTimeInterval(9 * 3_600),
            snapshotID: snapshotID,
            timeZoneIdentifier: shanghai.identifier
        )
        records.migrateCalendarTimeZone(to: "America/Los_Angeles", at: anchor)
        return records.state.observations[0].eventID
    }

    let first = migratedID()
    let second = migratedID()
    #expect(first == second)
    #expect(first != eventID)
}

@MainActor
@Test("Timezone migrate remaps week and rotation anchors and dirties the archive")
func migrateCalendarTimeZoneMovesScheduleAnchors() throws {
    let records = RecordCoordinator.inMemory()
    let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    var shanghaiCalendar = Calendar(identifier: .gregorian)
    shanghaiCalendar.timeZone = shanghai
    let monday = shanghaiCalendar.date(from: DateComponents(year: 2026, month: 8, day: 24))!
    let hours = ScheduleHoursConfiguration(
        startTime: "09:00",
        endTime: "17:00",
        workdays: [1, 2, 3, 4, 5],
        schedule: NativeWorkSchedule(
            mode: "alternating",
            referenceWeekStartMs: monday.timeIntervalSince1970 * 1_000,
            referenceWeekType: "single",
            singleWeekendWorkday: 6,
            rotationAnchorMs: monday.timeIntervalSince1970 * 1_000,
            rotationWorkDays: 2,
            rotationRestDays: 2
        ),
        breakStartTime: nil,
        breakDurationMinutes: 0
    )
    records.ensureSeeded(hours: hours, at: monday, timeZone: shanghai)
    records.migrateCalendarTimeZone(to: "America/Los_Angeles", at: monday)
    let migrated = try JSONDecoder().decode(
        ScheduleHoursConfiguration.self,
        from: records.state.snapshots[0].configurationData
    )
    var losAngeles = Calendar(identifier: .gregorian)
    losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let weekAnchor = Date(timeIntervalSince1970: migrated.schedule.referenceWeekStartMs! / 1_000)
    let rotationAnchor = Date(timeIntervalSince1970: migrated.schedule.rotationAnchorMs! / 1_000)
    #expect(RecordJSON.dayKey(weekAnchor, calendar: losAngeles) == "2026-08-24")
    #expect(RecordJSON.dayKey(rotationAnchor, calendar: losAngeles) == "2026-08-24")
    #expect(!RecordsSyncOutbox.pending(records.state.sync).isEmpty)
}

@MainActor
@Test("Import adopted rows enter the outbox")
func coordinatorImportMarksAdoptedDirty() throws {
    let source = RecordCoordinator.inMemory()
    source.ensureSeeded(hours: sampleHours(), at: startOf(2026, 8, 24))
    let data = try source.exportJSON(exportedAt: startOf(2026, 8, 24), timeZone: TimeZone(secondsFromGMT: 0)!)
    let target = RecordCoordinator.inMemory()
    let report = try target.import(data)
    #expect(!report.adopted.isEmpty)
    #expect(!RecordsSyncOutbox.pending(target.state.sync).isEmpty)
}

@MainActor
@Test("Restoring a conflict copy stamps a new edit and consumes the copy")
func restoreConflictStampsAndConsumes() {
    let records = RecordCoordinator.inMemory()
    records.updateLifeProfile(
        LifeProfile(
            birthYear: 1990,
            retirementAge: 60,
            editedAt: startOf(2026, 8, 24),
            editCount: 1,
            editTieBreaker: recordID(8)
        )
    )
    let localCount = records.state.lifeProfile!.editCount
    var incoming = records.state.lifeProfile!
    incoming.retirementAge = 65
    incoming.editCount = 2
    let payload = try! JSONEncoder().encode(
        LifeProfileDTO(incoming, calendar: Calendar(identifier: .gregorian))
    )
    let copy = SyncConflictCopy(
        entityType: .lifeProfile,
        logicalKey: LifeProfile.profileID.uuidString,
        payload: payload,
        lostAtMs: 0
    )
    var sync = records.state.sync
    sync.conflicts.append(copy)
    records.replaceSyncState(sync)
    var externalApplications = 0
    records.onExternalStateApplied = { externalApplications += 1 }
    #expect(records.restoreConflict(copy))
    #expect(records.state.sync.conflicts.isEmpty)
    #expect(records.state.lifeProfile!.retirementAge == 65)
    #expect(records.state.lifeProfile!.editCount > localCount)
    #expect(!RecordsSyncOutbox.pending(records.state.sync).isEmpty)
    #expect(externalApplications == 1)
}

@MainActor
@Test("A failed conflict write reports failure and keeps the conflict retryable")
func conflictWriteFailureIsRetryable() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "RecordCoordinatorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let records = RecordCoordinator(fileURL: root.appending(path: "archive.json"))
    records.updateLifeProfile(LifeProfile(
        birthYear: 1990,
        retirementAge: 60,
        editedAt: startOf(2026, 8, 24),
        editCount: 1,
        editTieBreaker: recordID(18)
    ))
    var incoming = try #require(records.state.lifeProfile)
    incoming.retirementAge = 65
    incoming.editCount += 1
    let payload = try JSONEncoder().encode(
        LifeProfileDTO(incoming, calendar: Calendar(identifier: .gregorian))
    )
    let copy = SyncConflictCopy(
        entityType: .lifeProfile,
        logicalKey: LifeProfile.profileID.uuidString,
        payload: payload,
        lostAtMs: 0
    )
    var sync = records.state.sync
    sync.conflicts.append(copy)
    #expect(records.replaceSyncState(sync))
    try FileManager.default.removeItem(at: root)

    #expect(!records.restoreConflict(copy))
    #expect(records.persistenceError == .writeFailed)
    #expect(records.state.sync.conflicts.contains { $0.id == copy.id })
    #expect(records.state.lifeProfile?.retirementAge == 60)
}

@MainActor
@Test("Records list is actual start and stop days, not the scheduled year")
func recordedWorkDaysIgnoreScheduleAndFirstSeen() {
    let store = OffWorkStore(defaults: isolatedRecordDefaults())
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.noteTimerSurfaceVisible(at: date(2026, 8, 24, 9))
    #expect(store.recordedWorkDays().isEmpty)

    store.startCountdown(at: date(2026, 8, 24, 9))
    store.noteTimerSurfaceVisible(at: date(2026, 8, 25, 9))

    let days = store.recordedWorkDays()
    #expect(days.map(\.dayKey) == ["2026-08-24"])
    #expect(days[0].firstStart != nil)
}

@MainActor
@Test("Early clock in and off become work records")
func earlyClockWritesWorkRecords() {
    let store = OffWorkStore(defaults: isolatedRecordDefaults())
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.clockInEarly(at: date(2026, 8, 24, 8))
    store.clockOffEarly(at: date(2026, 8, 24, 16))

    let days = store.recordedWorkDays()
    #expect(days.map(\.dayKey) == ["2026-08-24"])
    #expect(days[0].observations.contains { $0.kind == .countdownStarted })
    #expect(days[0].observations.contains { $0.kind == .countdownStopped })
}

@MainActor
@Test("Archive banners split damage from a save failure")
func archiveBannerDistinguishesDamageFromSaveFailure() {
    #expect(RecordsArchiveBanner(error: .invalidArchive) == .damaged)
    #expect(RecordsArchiveBanner(error: .unreadableArchive) == .damaged)
    #expect(RecordsArchiveBanner(error: .writeFailed) == .saveFailed)
    #expect(RecordsArchiveBanner(error: nil) == nil)
}

@MainActor
@Test("Quarantining a damaged archive keeps a .corrupt copy and unlocks writes")
func quarantineDamagedArchiveSucceedsAndAllowsWrites() throws {
    let (root, fileURL) = try makeArchiveRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let damaged = Data("not-json".utf8)
    try damaged.write(to: fileURL)
    let records = RecordCoordinator(fileURL: fileURL)
    #expect(records.archiveBanner == .damaged)
    #expect(records.blocksWrites)
    records.deleteAllLocalData()
    #expect(try Data(contentsOf: fileURL) == damaged)

    let now = Date(timeIntervalSince1970: 1_777_000_000)
    let backup = try records.quarantineCorruptedArchive(at: now)
    #expect(backup == RecordCoordinator.corruptBackupURL(for: fileURL, at: now))
    #expect(backup?.lastPathComponent.contains("corrupt-") == true)
    #expect(try Data(contentsOf: backup!) == damaged)
    #expect(records.persistenceError == nil)
    #expect(records.archiveBanner == nil)
    #expect(try Data(contentsOf: fileURL) != damaged)

    records.ensureSeeded(hours: sampleHours(), at: startOf(2026, 8, 24))
    #expect(!records.state.periods.isEmpty)
    #expect(records.persistenceError == nil)
}

@MainActor
@Test("A failed quarantine leaves the damaged archive in place")
func quarantineDamagedArchiveFailureKeepsOriginal() throws {
    let (root, fileURL) = try makeArchiveRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let damaged = Data("not-json".utf8)
    try damaged.write(to: fileURL)
    let records = RecordCoordinator(fileURL: fileURL)
    let now = Date(timeIntervalSince1970: 1_777_000_111)
    let backup = RecordCoordinator.corruptBackupURL(for: fileURL, at: now)
    try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)

    #expect(throws: RecordPersistenceError.writeFailed) {
        try records.quarantineCorruptedArchive(at: now)
    }
    #expect(records.persistenceError == .invalidArchive)
    #expect(records.archiveBanner == .damaged)
    #expect(try Data(contentsOf: fileURL) == damaged)
    #expect(records.blocksWrites)
}

@MainActor
@Test("A save failure is not a damaged archive and cannot be quarantined")
func writeFailedDoesNotEnterQuarantine() throws {
    let (root, fileURL) = try makeArchiveRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let records = RecordCoordinator(fileURL: fileURL)
    records.ensureSeeded(hours: sampleHours(), at: startOf(2026, 8, 24))
    #expect(records.persistenceError == nil)
    try FileManager.default.removeItem(at: fileURL)
    try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)

    records.recordObservation(
        kind: .countdownStarted,
        eventID: recordID(40),
        shiftAnchorDate: startOf(2026, 8, 24),
        occurredAt: startOf(2026, 8, 24),
        snapshotID: records.state.snapshots[0].id
    )
    #expect(records.persistenceError == .writeFailed)
    #expect(records.archiveBanner == .saveFailed)
    #expect(!records.blocksWrites)

    let backup = try records.quarantineCorruptedArchive()
    #expect(backup == nil)
    #expect(records.persistenceError == .writeFailed)
    #expect(records.archiveBanner == .saveFailed)
    let leftovers = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.contains("corrupt-") }
    #expect(leftovers.isEmpty)
}

@MainActor
@Test("Following the schedule writes observations in the locked records time zone")
func scheduledFollowUsesLockedRecordsTimeZone() {
    let store = OffWorkStore(defaults: isolatedRecordDefaults())
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.recordsTimeZoneIdentifier = "Asia/Shanghai"
    store.noteTimerSurfaceVisible(at: date(2026, 8, 24, 9))
    let observation = store.records.state.observations.first { $0.kind == .timerSurfaceFirstSeen }
    #expect(observation?.timeZoneIdentifier == "Asia/Shanghai")
    #expect(store.timeZoneIdentifierForWriting() == "Asia/Shanghai")
    #expect(store.countdownTimeZoneIdentifier == "Asia/Shanghai")
}

@MainActor
@Test("Migrating while a countdown is running keeps the session time zone")
func migrateWhileRunningKeepsSessionTimeZone() {
    let store = OffWorkStore(defaults: isolatedRecordDefaults())
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.recordsTimeZoneIdentifier = "Asia/Shanghai"
    store.countdownStarted = true
    store.migrateRecordsTimeZone(
        to: TimeZone(identifier: "America/Los_Angeles")!,
        at: date(2026, 8, 24, 10)
    )
    #expect(store.recordsTimeZoneIdentifier == "America/Los_Angeles")
    #expect(store.sessionTimeZoneIdentifier == "Asia/Shanghai")
    #expect(store.countdownTimeZoneIdentifier == "Asia/Shanghai")
}

@MainActor
@Test("Days recorded in another time zone are listed for the life view")
func daysRecordedOutsidePeriodTimeZoneFoundation() {
    let store = OffWorkStore(defaults: isolatedRecordDefaults())
    let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    let hours = ScheduleHoursConfiguration(
        startTime: "09:00",
        endTime: "17:00",
        workdays: [1, 2, 3, 4, 5],
        schedule: NativeWorkSchedule(
            mode: "classic",
            referenceWeekStartMs: nil,
            referenceWeekType: nil,
            singleWeekendWorkday: nil,
            rotationAnchorMs: nil,
            rotationWorkDays: nil,
            rotationRestDays: nil
        ),
        breakStartTime: nil,
        breakDurationMinutes: 0
    )
    store.recordsTimeZoneIdentifier = shanghai.identifier
    store.records.ensureSeeded(hours: hours, at: startOf(2026, 8, 24), timeZone: shanghai)
    let anchor = ISO8601DateFormatter().date(from: "2026-08-24T12:00:00Z")!
    store.records.recordObservation(
        kind: .countdownStarted,
        eventID: UUID(),
        shiftAnchorDate: anchor,
        occurredAt: anchor,
        snapshotID: UUID(),
        timeZoneIdentifier: "America/Los_Angeles"
    )
    #expect(store.daysRecordedOutsidePeriodTimeZone() == ["2026-08-24"])
}

@MainActor
private func makeArchiveRoot() throws -> (root: URL, fileURL: URL) {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "owc-records-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return (root, root.appending(path: "archive.json"))
}

@MainActor
private func sampleHours() -> ScheduleHoursConfiguration {
    ScheduleHoursConfiguration(
        startTime: "09:00",
        endTime: "17:00",
        workdays: [1, 2, 3, 4, 5],
        schedule: NativeWorkSchedule(
            mode: "classic",
            referenceWeekStartMs: nil,
            referenceWeekType: nil,
            singleWeekendWorkday: nil,
            rotationAnchorMs: nil,
            rotationWorkDays: nil,
            rotationRestDays: nil
        ),
        breakStartTime: nil,
        breakDurationMinutes: 0
    )
}

@MainActor
private func isolatedRecordDefaults() -> UserDefaults {
    let suite = "RecordCoordinatorTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@MainActor
private func startOf(_ year: Int, _ month: Int, _ day: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
}

@MainActor
private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
}

@MainActor
private func recordID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value)) ?? UUID()
}

@MainActor
@Test("Recording an erased day again revokes its tombstone locally and in iCloud")
func revivedNaturalKeyRevokesTombstone() {
    let records = RecordCoordinator.inMemory()
    let key = "2026-08-24"
    let day = startOf(2026, 8, 24)
    let rowName = RecordsSyncIdentity.recordName(type: .dayOverride, key: key)

    records.upsertOverride(
        DayOverride(dayKey: key, shiftAnchorDate: day, kind: .notWorking, segments: [])
    )
    // A remote erase from another device buries the row at its current version.
    records.applyRemoteErase(type: .dayOverride, key: key, erasedEditCount: 1)
    #expect(records.state.overrides.isEmpty)
    #expect(records.state.isErased(.dayOverride, key: key))
    #expect(records.state.erasedEditCount(.dayOverride, key: key) == 1)

    // The user records the day again.
    records.upsertOverride(
        DayOverride(dayKey: key, shiftAnchorDate: day, kind: .confirmedAsScheduled, segments: [])
    )
    #expect(!records.state.isErased(.dayOverride, key: key))
    let row = records.state.sync.rows[rowName]
    #expect(row?.pendingErase == false)
    // The push has to take the cloud tombstone down, not only save the record.
    #expect(row?.revokesErase == true)
    // And it has to out-rank the tombstone it replaced.
    #expect((row?.editCount ?? 0) > 1)

    // A save receipt alone must not clear the row: the tombstone would survive
    // in iCloud and every other device would erase the day again.
    let erasedName = RecordsSyncIdentity.erasedName(type: .dayOverride, key: key)
    #expect(
        !RecordsSyncSent.shouldClearSave(
            row: row!,
            savedCount: row!.editCount,
            savedTie: row!.editTieBreaker,
            deletedNames: []
        )
    )
    #expect(
        RecordsSyncSent.shouldClearSave(
            row: row!,
            savedCount: row!.editCount,
            savedTie: row!.editTieBreaker,
            deletedNames: [erasedName]
        )
    )
}

@MainActor
@Test("A fetched tombstone revocation clears the local erase so the row can return")
func remoteEraseRevocationClearsTombstone() {
    let records = RecordCoordinator.inMemory()
    let key = "2026-08-24"
    let day = startOf(2026, 8, 24)

    records.applyRemoteErase(type: .dayOverride, key: key, erasedEditCount: 3)
    #expect(records.state.isErased(.dayOverride, key: key))
    #expect(records.state.erasedEditCount(.dayOverride, key: key) == 3)

    records.applyRemoteEraseRevocation(type: .dayOverride, key: key)
    #expect(!records.state.isErased(.dayOverride, key: key))

    // With the tombstone gone the revived row inserts instead of reasserting.
    records.upsertOverride(
        DayOverride(dayKey: key, shiftAnchorDate: day, kind: .notWorking, segments: [])
    )
    #expect(records.state.overrides.count == 1)
}

@MainActor
@Test("A tombstone older than a local revival does not delete it again")
func staleTombstoneLosesToNewerLocalRow() {
    let records = RecordCoordinator.inMemory()
    let key = "2026-08-24"
    let day = startOf(2026, 8, 24)

    records.upsertOverride(
        DayOverride(dayKey: key, shiftAnchorDate: day, kind: .notWorking, segments: [])
    )
    records.applyRemoteErase(type: .dayOverride, key: key, erasedEditCount: 1)
    records.upsertOverride(
        DayOverride(dayKey: key, shiftAnchorDate: day, kind: .confirmedAsScheduled, segments: [])
    )
    let revivedCount = records.state.overrides.first?.editCount ?? 0

    // The erasing device re-sends the tombstone it wrote before the revival.
    records.applyRemoteErase(type: .dayOverride, key: key, erasedEditCount: 1)
    #expect(records.state.overrides.count == 1)
    #expect(records.state.overrides.first?.editCount == revivedCount)
    #expect(!records.state.isErased(.dayOverride, key: key))
}

@MainActor
@Test("An unversioned tombstone still erases a row that has been edited")
func legacyTombstoneStillErases() {
    let records = RecordCoordinator.inMemory()
    let key = "2026-08-24"
    let day = startOf(2026, 8, 24)
    records.upsertOverride(
        DayOverride(dayKey: key, shiftAnchorDate: day, kind: .notWorking, segments: [])
    )
    records.upsertOverride(
        DayOverride(dayKey: key, shiftAnchorDate: day, kind: .confirmedAsScheduled, segments: [])
    )
    #expect((records.state.overrides.first?.editCount ?? 0) >= 2)

    // A tombstone from a build that never wrote `editCount` carries no version
    // and must still be honoured, or deletes stop propagating between devices.
    records.applyRemoteErase(type: .dayOverride, key: key, erasedEditCount: nil)
    #expect(records.state.overrides.isEmpty)
    #expect(records.state.isErased(.dayOverride, key: key))
}
