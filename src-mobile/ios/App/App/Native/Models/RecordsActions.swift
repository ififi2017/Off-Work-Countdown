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
                   let configuration = try? JSONDecoder().decode(
                    ScheduleHoursConfiguration.self,
                    from: snapshot.configurationData
                   ) {
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
