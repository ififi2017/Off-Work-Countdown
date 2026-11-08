import Foundation

/// Record editing and file actions consume explicit hours and committed
/// preferences. They have no scene, timer lifecycle or application dependency.
@MainActor
final class RecordsActions {
    let records: RecordCoordinator
    let preferences: PreferencesStore
    let plus: PlusEntitlement
    let text: AppText
    private let currentHours: (Date) -> ScheduleHoursConfiguration

    init(records: RecordCoordinator, preferences: PreferencesStore, plus: PlusEntitlement,
         text: AppText, currentHours: @escaping (Date) -> ScheduleHoursConfiguration) {
        self.records = records
        self.preferences = preferences
        self.plus = plus
        self.text = text
        self.currentHours = currentHours
    }

    func exportRecordsFile(at date: Date = .now, includeLifeProfile: Bool = true) async throws -> URL {
        let data = try await records.exportJSON(
            exportedAt: date,
            timeZone: preferences.recordsTimeZone,
            includeLifeProfile: includeLifeProfile
        )
        let name = includeLifeProfile ? "doneat-records.json" : "doneat-records-without-life.json"
        return try await RecordArchive.writeExport(data, named: name)
    }

    func previewRecordsImport(_ data: Data) async throws -> RecordImportReport {
        try await RecordArchive.prepareImport(data, into: records.state, mode: .skipErased).report
    }

    func confirmRecordsOwnerIfNeeded(reasonKey: String) async -> Bool {
        guard preferences.hideEarnings else { return true }
        return await BiometricGate.confirmOwner(reason: text.t(reasonKey))
    }

    func canMutateRecordedDay(_ dayKey: String) -> Bool {
        guard !records.blocksWrites else { return false }
        guard RecordJSON.date(fromDayKey: dayKey, calendar: preferences.recordsCalendar) != nil else { return false }
        if !RecordsAccess.allows(.recordsPageEdit, authorized: plus.isAuthorized) {
            return false
        }
        return true
    }

    /// Plan 024 phase 4: records a day's overtime — its period, the hours that
    /// count and how it is paid — as a new `overtimeDeclared` observation. The
    /// latest declaration on a day is the one that counts; earlier ones stay.
    @discardableResult
    func declareOvertime(dayKey: String, state: RecordOvertimeState, declaredAt: Date = .now) -> RecordCommand<Bool> {
        records.submitCommand { [self] in
            guard canMutateRecordedDay(dayKey), records.captureEnabled, state.isValid,
                  OvertimePay.normalized(state.payMultiplier) == state.payMultiplier,
                  state.countedMs.map({ CountedOvertime.normalized($0) != nil }) ?? true,
                  let date = RecordJSON.date(fromDayKey: dayKey, calendar: preferences.recordsCalendar),
                  let valueData = try? JSONEncoder().encode(state.payload)
            else { return false }
            records.withBatchedWrites {
                records.ensureSeeded(hours: currentHours(date), at: date, timeZone: preferences.recordsTimeZone)
                records.recordObservation(
                    kind: .overtimeDeclared,
                    eventID: UUID(),
                    shiftAnchorDate: preferences.recordsCalendar.startOfDay(for: date),
                    occurredAt: declaredAt,
                    snapshotID: records.currentSnapshotID(on: date) ?? UUID(),
                    valueData: valueData,
                    timeZoneIdentifier: preferences.recordsTimeZoneIdentifier
                )
            }
            return true
        }
    }

    @discardableResult
    func applyDayWrite(
        _ write: DayRecordWrite,
        dayKey: String,
        startMinutes: Int = 9 * 60,
        endMinutes: Int = 18 * 60
    ) -> RecordCommand<Bool> {
        records.submitCommand { [self] in
            guard canMutateRecordedDay(dayKey) else { return false }
            return switch DayRecordLayers.plan(for: write) {
            case .overrideOnly(let kind):
                switch kind {
                case .customSegments:
                    saveCustomHours(
                        dayKey: dayKey,
                        startMinutes: startMinutes,
                        endMinutes: endMinutes
                    ).synchronousResult
                case .confirmedAsScheduled:
                    confirmDayAsScheduled(dayKey: dayKey).synchronousResult
                case .notWorking:
                    markDayNotWorking(dayKey: dayKey).synchronousResult
                case .cleared:
                    clearDayOverride(dayKey: dayKey).synchronousResult
                }
            case .exception(let overrideKind, let effect, let exceptionCleared):
                writeDayLayers(
                    dayKey: dayKey,
                    overrideKind: overrideKind,
                    effect: effect,
                    exceptionCleared: exceptionCleared
                )
            }
        }
    }

    private func writeDayLayers(
        dayKey: String,
        overrideKind: DayOverrideKind,
        effect: CalendarEffect,
        exceptionCleared: Bool
    ) -> Bool {
        guard let date = RecordJSON.date(fromDayKey: dayKey, calendar: preferences.recordsCalendar) else { return false }
        let override = DayOverride(
            dayKey: dayKey,
            shiftAnchorDate: date,
            kind: overrideKind,
            segments: [],
            timeZoneIdentifier: preferences.recordsTimeZoneIdentifier
        )
        var exception: CalendarException?
        if exceptionCleared {
            if let existing = records.state.exceptions.first(where: { $0.matches(dateKey: dayKey) && $0.origin == .user }) {
                var next = existing
                next.isCleared = true
                exception = next
            }
        } else {
            exception = CalendarException(
                dayKey: CalendarException.dayKey(dateKey: dayKey, origin: .user),
                date: date,
                effect: effect,
                origin: .user,
                isCleared: false,
                regionIdentifier: nil,
                datasetVersion: nil,
                label: nil,
                editedAt: .now,
                editCount: 0,
                editTieBreaker: UUID(),
                timeZoneIdentifier: preferences.recordsTimeZoneIdentifier
            )
        }
        records.applyDayLayers(override: override, exception: exception)
        return true
    }

    @discardableResult
    func saveCustomHours(dayKey: String, startMinutes: Int, endMinutes: Int) -> RecordCommand<Bool> {
        records.submitCommand { [self] in
            guard canMutateRecordedDay(dayKey), (0..<1440).contains(startMinutes),
                  (0..<1440).contains(endMinutes),
                  let date = RecordJSON.date(fromDayKey: dayKey, calendar: preferences.recordsCalendar),
                  let start = preferences.recordsCalendar.date(
                    bySettingHour: startMinutes / 60, minute: startMinutes % 60, second: 0, of: date),
                  let sameDayEnd = preferences.recordsCalendar.date(
                    bySettingHour: endMinutes / 60, minute: endMinutes % 60, second: 0, of: date)
            else { return false }
            let end: Date
            if sameDayEnd <= start {
                guard let nextDayEnd = preferences.recordsCalendar.date(byAdding: .day, value: 1, to: sameDayEnd)
                else { return false }
                end = nextDayEnd
            } else {
                end = sameDayEnd
            }
            records.withBatchedWrites {
                records.ensureSeeded(hours: currentHours(date), at: date, timeZone: preferences.recordsTimeZone)
                let period = DayRecordResolver.period(on: date, from: records.state.periods)
                let snapshot = period.flatMap {
                    DayRecordResolver.snapshot(on: date, in: $0, from: records.state.snapshots)
                }
                var planned: [NativeShiftSegment] = []
                if let snapshot,
                   let configuration = records.expandableHours(for: snapshot) {
                    planned = ScheduleRules.expandScheduleRange(
                        configuration: configuration,
                        from: date,
                        through: date,
                        timeZone: period?.timeZone
                    ).first?.segments ?? []
                }
                if planned.isEmpty {
                    planned = [
                        NativeShiftSegment(
                            startAtMs: start.timeIntervalSince1970 * 1_000,
                            endAtMs: end.timeIntervalSince1970 * 1_000
                        )
                    ]
                }
                records.upsertOverride(
                    DayOverride(
                        dayKey: dayKey,
                        shiftAnchorDate: date,
                        kind: .customSegments,
                        segments: DayOverrideProjection.applyTimeBounds(
                            to: planned,
                            startAtMs: start.timeIntervalSince1970 * 1_000,
                            endAtMs: end.timeIntervalSince1970 * 1_000
                        ),
                        timeZoneIdentifier: preferences.recordsTimeZoneIdentifier
                    )
                )
            }
            return true
        }
    }

    /// Plan 021: adopts workplace-automation times as the day's segments.
    ///
    /// Unlike a Records page edit this does not ask for Plus: adopting or
    /// correcting results automation already produced stays open after Plus
    /// ends (§3.14). New automatic writes are gated on `canAutoApplyAutomation`
    /// by the caller. A row the person changed since automation last wrote it
    /// (`expectedEditCount`) is never overwritten: that is a conflict. Only a
    /// reviewed adoption, the person's explicit choice, passes
    /// `replacingPersonEdits`.
    ///
    /// `provenance` is the adopted boundary's minimal summary (C1). It is
    /// written in the same archive save as the override, so the day never
    /// holds adopted times without their source or the other way round.
    @discardableResult
    func writeAutomationSegments(
        dayKey: String,
        segments: [NativeShiftSegment],
        expectedEditCount: Int?,
        replacingPersonEdits: Bool = false,
        provenance: WorkTimeProvenance.Boundary? = nil
    ) -> RecordCommand<AutomationDayWriteResult> {
        records.submitCommand { [self] in
            guard !records.blocksWrites, records.captureEnabled, !segments.isEmpty,
                  segments.allSatisfy({ $0.endAtMs > $0.startAtMs }),
                  let date = RecordJSON.date(fromDayKey: dayKey, calendar: preferences.recordsCalendar)
            else { return .unavailable }
            let current = liveOverride(dayKey)
            let currentProvenance = liveProvenance(dayKey)
            if let current, current.kind == .customSegments, current.segments == segments {
                // A retry after the app stopped mid-command: both were saved
                // together, so only a summary that is genuinely missing is added.
                if let provenance, currentProvenance?.boundary(provenance.boundary)?.time != provenance.time {
                    records.withBatchedWrites {
                        records.upsertWorkTimeProvenance(
                            adoptedProvenance(provenance, onto: currentProvenance, dayKey: dayKey)
                        )
                    }
                }
                return .unchanged(editCount: current.editCount)
            }
            if !replacingPersonEdits {
                if let current, current.editCount != expectedEditCount { return .conflict }
                if current == nil, expectedEditCount != nil { return .conflict }
            }
            records.withBatchedWrites {
                records.ensureSeeded(hours: currentHours(date), at: date, timeZone: preferences.recordsTimeZone)
                records.upsertOverride(
                    DayOverride(
                        dayKey: dayKey,
                        shiftAnchorDate: date,
                        kind: .customSegments,
                        segments: segments,
                        timeZoneIdentifier: preferences.recordsTimeZoneIdentifier
                    )
                )
                if let provenance {
                    records.upsertWorkTimeProvenance(
                        adoptedProvenance(provenance, onto: currentProvenance, dayKey: dayKey)
                    )
                }
            }
            guard let written = liveOverride(dayKey) else { return .unavailable }
            let provenanceWrite = provenance.flatMap { _ in
                liveProvenance(dayKey).map {
                    AutomationProvenanceWrite(previous: currentProvenance, editCount: $0.editCount)
                }
            }
            return .written(previous: current, editCount: written.editCount, provenance: provenanceWrite)
        }
    }

    /// Undoes one automation write by putting back the row it replaced, only
    /// while the row is still exactly what automation wrote (§3.6).
    ///
    /// The day's provenance goes back to what it was before the write too,
    /// unless it changed since (for example the person deleted the evidence).
    @discardableResult
    func restoreAutomationOverride(
        dayKey: String,
        previous: DayOverride?,
        expectedEditCount: Int,
        provenance: AutomationProvenanceWrite? = nil
    ) -> RecordCommand<AutomationDayWriteResult> {
        records.submitCommand { [self] in
            guard !records.blocksWrites, records.captureEnabled,
                  let date = RecordJSON.date(fromDayKey: dayKey, calendar: preferences.recordsCalendar)
            else { return .unavailable }
            guard let current = liveOverride(dayKey), current.editCount == expectedEditCount else { return .conflict }
            let restored = previous ?? DayOverride(
                dayKey: dayKey,
                shiftAnchorDate: date,
                kind: .cleared,
                segments: [],
                timeZoneIdentifier: preferences.recordsTimeZoneIdentifier
            )
            records.withBatchedWrites {
                records.upsertOverride(restored)
                if let provenance, liveProvenance(dayKey)?.editCount == provenance.editCount {
                    if let earlier = provenance.previous {
                        records.upsertWorkTimeProvenance(earlier)
                    } else {
                        records.erase(.workTimeProvenance, key: dayKey)
                    }
                }
            }
            guard let written = records.state.overrides.first(where: { $0.dayKey == dayKey }) else {
                return .unavailable
            }
            return .written(previous: current, editCount: written.editCount)
        }
    }

    /// Deletes the automation evidence for a day (§3.7). The tombstone reaches
    /// other devices; the day's adopted times stay as they are.
    @discardableResult
    func deleteWorkTimeProvenance(dayKey: String) -> RecordCommand<Bool> {
        records.submitCommand { [self] in
            guard !records.blocksWrites, liveProvenance(dayKey) != nil else { return false }
            records.erase(.workTimeProvenance, key: dayKey)
            return true
        }
    }

    private func liveProvenance(_ dayKey: String) -> WorkTimeProvenance? {
        guard !records.state.isErased(.workTimeProvenance, key: dayKey) else { return nil }
        return records.state.workTimeProvenance.first { $0.dayKey == dayKey }
    }

    private func adoptedProvenance(
        _ entry: WorkTimeProvenance.Boundary,
        onto current: WorkTimeProvenance?,
        dayKey: String
    ) -> WorkTimeProvenance {
        (current ?? WorkTimeProvenance(
            dayKey: dayKey,
            boundaries: [],
            timeZoneIdentifier: preferences.recordsTimeZoneIdentifier
        )).adopting(entry)
    }

    /// The day's override unless it was erased or cleared back to the plan.
    private func liveOverride(_ dayKey: String) -> DayOverride? {
        guard !records.state.isErased(.dayOverride, key: dayKey),
              let row = records.state.overrides.first(where: { $0.dayKey == dayKey }),
              row.kind != .cleared
        else { return nil }
        return row
    }

    @discardableResult
    func confirmDayAsScheduled(dayKey: String) -> RecordCommand<Bool> {
        records.submitCommand { [self] in
            writeOverride(dayKey: dayKey, kind: .confirmedAsScheduled)
        }
    }

    @discardableResult
    func markDayNotWorking(dayKey: String) -> RecordCommand<Bool> {
        records.submitCommand { [self] in
            writeOverride(dayKey: dayKey, kind: .notWorking)
        }
    }

    private func writeOverride(dayKey: String, kind: DayOverrideKind) -> Bool {
        guard canMutateRecordedDay(dayKey),
              let date = RecordJSON.date(fromDayKey: dayKey, calendar: preferences.recordsCalendar)
        else { return false }
        records.upsertOverride(
            DayOverride(
                dayKey: dayKey,
                shiftAnchorDate: date,
                kind: kind,
                segments: [],
                timeZoneIdentifier: preferences.recordsTimeZoneIdentifier
            )
        )
        return true
    }

    @discardableResult
    func clearDayOverride(dayKey: String) -> RecordCommand<Bool> {
        records.submitCommand { [self] in
            guard canMutateRecordedDay(dayKey) else { return false }
            return writeDayLayers(dayKey: dayKey, overrideKind: .cleared, effect: .rest, exceptionCleared: true)
        }
    }

    @discardableResult
    func markCalendarException(dayKey: String, effect: CalendarEffect) -> RecordCommand<Bool> {
        records.submitCommand { [self] in
            guard canMutateRecordedDay(dayKey) else { return false }
            return writeDayLayers(
                dayKey: dayKey,
                overrideKind: .cleared,
                effect: effect,
                exceptionCleared: false
            )
        }
    }

}

/// What happened to a workplace-automation record write.
nonisolated enum AutomationDayWriteResult: Equatable, Sendable {
    /// Written; `previous` and `provenance` are what an undo puts back.
    case written(previous: DayOverride?, editCount: Int, provenance: AutomationProvenanceWrite? = nil)
    /// The day already has exactly these segments.
    case unchanged(editCount: Int)
    /// The person changed the day since automation last wrote it.
    case conflict
    /// Records are locked, damaged or the day is invalid.
    case unavailable
}

/// The provenance row an automation write replaced, and the edit count it
/// left, so an undo restores it only while it is still that write's version.
nonisolated struct AutomationProvenanceWrite: Codable, Equatable, Sendable {
    var previous: WorkTimeProvenance?
    var editCount: Int
}
