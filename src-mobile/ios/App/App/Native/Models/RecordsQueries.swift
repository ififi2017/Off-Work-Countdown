import Foundation
import Observation

/// A findable user-authored record day. It is intentionally not a metrics
/// model: manual leave and rest entries belong here even though they must not
/// inflate workday totals.
struct RecordDayIndexEntry: Equatable, Sendable, Identifiable {
    var dayKey: String
    var observations: [WorkObservation] = []
    var dayOverride: DayOverride?
    var calendarException: CalendarException?

    var id: String { dayKey }
    var hasWorkObservation: Bool { !observations.isEmpty }
    var hasManualOverride: Bool { dayOverride != nil }
    var hasUserCalendarException: Bool { calendarException != nil }
}

/// Read-only archive projections. This object owns query caches, never edits
/// the archive, and accepts shift values without retaining an application.
@MainActor
@Observable
final class RecordsQueries {
    struct Sources {
        var calendar: () -> Calendar
        var hours: (Date) -> ScheduleHoursConfiguration?
        var rules: (Date, RulesScheduleSource) -> NativeRulesInput?
        var snapshot: (Date) -> NativeShiftSnapshot?
        var isCounting: () -> Bool
        var salaryIsVisible: () -> Bool
        var salaryType: () -> SalaryType?
        var language: () -> String
    }

    let records: RecordCoordinator
    let plus: PlusEntitlement
    private let sources: Sources
    private let localizer: NativeLocalizer
    @ObservationIgnored private let civilCalendars = CivilCalendarCache()
    private(set) var lastRulesError: String?

    init(records: RecordCoordinator, plus: PlusEntitlement, localizer: NativeLocalizer, sources: Sources) {
        self.records = records
        self.plus = plus
        self.localizer = localizer
        self.sources = sources
    }

    var recordsCalendar: Calendar { sources.calendar() }
    var recordsTimeZone: TimeZone { recordsCalendar.timeZone }
    var recordsTimeZoneIdentifier: String { recordsTimeZone.identifier }
    private var languageCode: String { sources.language() }
    private var locale: Locale { civilCalendars.locale(identifier: languageCode) }
    private var countdownStarted: Bool { sources.isCounting() }
    private var presentationSalaryEnabled: Bool { sources.salaryIsVisible() }
    private var salaryType: SalaryType? { sources.salaryType() }
    private func snapshot(at date: Date) -> NativeShiftSnapshot? { sources.snapshot(date) }
    func rulesInput(at date: Date, using source: RulesScheduleSource = .effective) -> NativeRulesInput? {
        sources.rules(date, source)
    }
    private func t(_ key: String) -> String { localizer.string(key, locale: languageCode) }

    @ObservationIgnored
    private var observationIndexCache: (revision: UInt64, byDay: [String: [WorkObservation]])?
    /// Ignored like every other cache here. Without it, the first
    /// `isRecordedDay` of a calendar body registered a mutation while that body
    /// was still being evaluated, invalidating the view that had just asked.
    @ObservationIgnored
    private var recordedDayKeysCache: (revision: UInt64, keys: Set<String>)?
    @ObservationIgnored
    private var resolvedDaysCache: (revision: UInt64, calendar: Calendar, from: Date, through: Date, days: [DayResolution])?
    @ObservationIgnored
    private var lifeWorkProjectionBoundsCache: LifeWorkProjectionBoundsCache?

    /// A query never seeds or repairs the archive. Startup, foreground and
    /// explicit schedule actions reconcile before publishing their changes.
    func resolvedDays(from: Date, through: Date, now: Date = .now) -> [DayResolution] {
        return resolveDays(
            from: from,
            through: through,
            periods: records.state.periods,
            snapshots: records.state.snapshots,
            usesSharedCache: true
        )
    }

    /// Expands an explicit career timeline through the same shared-rule and
    /// three-layer resolver used by Records. Life can add an in-memory
    /// backfill period without mutating or duplicating the user's archive.
    private func resolveDays(
        from: Date,
        through: Date,
        periods: [CareerPeriod],
        snapshots: [ScheduleSnapshot],
        usesSharedCache: Bool
    ) -> [DayResolution] {
        let calendar = recordsCalendar
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: through)
        guard start <= end else { return [] }
        if usesSharedCache, let cached = cachedResolvedDays(from: start, through: end) {
            return cached
        }
        let result = Self.walkResolutions(
            from: start,
            through: end,
            calendar: calendar,
            periods: periods,
            snapshots: snapshots,
            exceptions: records.state.exceptions,
            overrides: records.state.overrides,
            expansions: gatherScheduleExpansions(
                from: from,
                through: through,
                periods: periods,
                snapshots: snapshots
            )
        )
        if usesSharedCache {
            storeResolvedDays(result, from: start, through: end, revision: records.historyRevision)
        }
        return result
    }

    /// The same answer as `resolveDays`, with the per-day walk off the main
    /// actor. Only the expansion gather has to stay here: `CountdownRules`
    /// owns the JavaScriptCore context and its cache, and
    /// `prefetchScheduleExpansions` has normally already filled it on
    /// `ScheduleRangeEngine`.
    private func resolveDaysOffMainActor(
        from: Date,
        through: Date,
        periods: [CareerPeriod],
        snapshots: [ScheduleSnapshot],
        usesSharedCache: Bool
    ) async -> [DayResolution] {
        let calendar = recordsCalendar
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: through)
        guard start <= end else { return [] }
        if usesSharedCache, let cached = cachedResolvedDays(from: start, through: end) {
            return cached
        }
        let revision = records.historyRevision
        let result = await Self.walkResolutionsOffMainActor(
            from: start,
            through: end,
            calendar: calendar,
            periods: periods,
            snapshots: snapshots,
            exceptions: records.state.exceptions,
            overrides: records.state.overrides,
            expansions: gatherScheduleExpansions(
                from: from,
                through: through,
                periods: periods,
                snapshots: snapshots
            )
        )
        // The archive can be edited while the walk runs. Caching a result built
        // from the older revision would outlive the edit that invalidated it.
        if usesSharedCache, records.historyRevision == revision, recordsCalendar == calendar, !Task.isCancelled {
            storeResolvedDays(result, from: start, through: end, revision: revision)
        }
        return result
    }

    private func cachedResolvedDays(from start: Date, through end: Date) -> [DayResolution]? {
        guard !records.hasUncommittedHistoryChanges,
              let cached = resolvedDaysCache,
              cached.revision == records.historyRevision,
              cached.calendar == recordsCalendar,
              cached.from == start,
              cached.through == end
        else { return nil }
        return cached.days
    }

    private func storeResolvedDays(
        _ days: [DayResolution],
        from start: Date,
        through end: Date,
        revision: UInt64
    ) {
        guard !records.hasUncommittedHistoryChanges,
              !days.contains(where: \.expansionFailed) else { return }
        resolvedDaysCache = (revision, recordsCalendar, start, end, days)
    }

    /// Every schedule expansion the day walk will ask for, keyed by snapshot.
    /// This is the half that cannot leave the main actor, so it is deliberately
    /// the small half: one JavaScriptCore range per snapshot, not per day.
    func gatherScheduleExpansions(
        from: Date,
        through: Date,
        periods: [CareerPeriod],
        snapshots: [ScheduleSnapshot]
    ) -> ScheduleExpansionTable {
        let calendar = recordsCalendar
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: through)
        guard start <= end else { return ScheduleExpansionTable() }

        var table = ScheduleExpansionTable()
        for snapshot in snapshots {
            guard let period = periods.first(where: { $0.id == snapshot.periodID }),
                  period.startsOn <= end,
                  period.endsBefore.map({ $0 > start }) ?? true,
                  snapshot.effectiveFrom <= end,
                  table.bySnapshot[snapshot.id] == nil,
                  !table.failures.contains(snapshot.id)
            else { continue }
            let dayCalendar = period.civilCalendar()
            if let configuration = try? JSONDecoder().decode(
                ScheduleHoursConfiguration.self,
                from: snapshot.configurationData
            ), let days = try? CountdownRules.shared.expandScheduleRange(
                configuration: configuration,
                from: dayCalendar.startOfDay(for: from),
                through: dayCalendar.startOfDay(for: through),
                timeZone: period.timeZone
            ) {
                // Date-line changes can produce duplicate civil day keys.
                table.bySnapshot[snapshot.id] = Dictionary(
                    days.map { ($0.dayKey, ScheduleExpansion(isWorkday: $0.isWorkday, segments: $0.segments)) },
                    uniquingKeysWith: { first, _ in first }
                )
            } else {
                table.failures.insert(snapshot.id)
                lastRulesError = "scheduleExpandFailed"
            }
        }
        return table
    }

    /// The day walk, over value types and already-expanded schedules: no store
    /// access and no JavaScriptCore, which is what lets it leave the main
    /// actor. A career is roughly 15,700 days of it.
    nonisolated static func walkResolutions(
        from start: Date,
        through end: Date,
        calendar: Calendar,
        periods: [CareerPeriod],
        snapshots: [ScheduleSnapshot],
        exceptions: [CalendarException],
        overrides: [DayOverride],
        expansions: ScheduleExpansionTable
    ) -> [DayResolution] {
        // Exceptions and overrides are keyed by day, so their winners do not
        // depend on which day is being resolved. Deciding them once is what
        // keeps a career-length walk from re-filtering the archive per day.
        let lookup = DayRecordLookup(exceptions: exceptions, overrides: overrides)
        var periodCalendars: [UUID: Calendar] = [:]
        var cursor = start
        var result: [DayResolution] = []
        result.reserveCapacity((calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
        while cursor <= end {
            let covering = DayRecordResolver.period(on: cursor, from: periods)
            let dayCalendar: Calendar
            if let covering {
                if let cached = periodCalendars[covering.id] {
                    dayCalendar = cached
                } else {
                    let next = covering.civilCalendar()
                    periodCalendars[covering.id] = next
                    dayCalendar = next
                }
            } else {
                dayCalendar = calendar
            }
            let dayKey = RecordJSON.dayKey(cursor, calendar: dayCalendar)
            let snapshot = covering.flatMap {
                DayRecordResolver.snapshot(on: cursor, in: $0, from: snapshots)
            }
            let expansion: ScheduleExpansion
            if let snapshot, expansions.failures.contains(snapshot.id) {
                expansion = .failed
            } else {
                expansion = snapshot.flatMap { expansions.bySnapshot[$0.id]?[dayKey] }
                    ?? ScheduleExpansion(isWorkday: false, segments: [])
            }
            // `cursor` is already the start of its day in `calendar`, so the
            // only reason to normalize again is a period that keeps a
            // different civil zone.
            let sharesCivilDay = dayCalendar.timeZone == calendar.timeZone
                && dayCalendar.identifier == calendar.identifier
            let anchor = sharesCivilDay ? cursor : dayCalendar.startOfDay(for: cursor)
            // The chain has always been resolved against the anchor while the
            // expansion above was picked against the cursor, and across a
            // period that keeps its own zone those are two different days.
            // That behaviour is preserved; what is dropped is repeating the
            // lookup when they are the same day, which is every day for
            // everyone who has not moved between zones.
            let anchorPeriod = sharesCivilDay
                ? covering
                : DayRecordResolver.period(on: anchor, from: periods)
            let anchorSnapshot = sharesCivilDay
                ? snapshot
                : anchorPeriod.flatMap {
                    DayRecordResolver.snapshot(on: anchor, in: $0, from: snapshots)
                }
            result.append(
                DayRecordResolver.resolve(
                    dayKey: dayKey,
                    shiftAnchorDate: anchor,
                    period: anchorPeriod,
                    snapshot: anchorSnapshot,
                    lookup: lookup,
                    expansion: expansion
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// `@concurrent` is required: with approachable concurrency a plain
    /// `nonisolated async` function still runs on its caller, so without it
    /// this would stay on the main actor and move nothing.
    @concurrent
    nonisolated private static func walkResolutionsOffMainActor(
        from start: Date,
        through end: Date,
        calendar: Calendar,
        periods: [CareerPeriod],
        snapshots: [ScheduleSnapshot],
        exceptions: [CalendarException],
        overrides: [DayOverride],
        expansions: ScheduleExpansionTable
    ) async -> [DayResolution] {
        walkResolutions(
            from: start,
            through: end,
            calendar: calendar,
            periods: periods,
            snapshots: snapshots,
            exceptions: exceptions,
            overrides: overrides,
            expansions: expansions
        )
    }

    /// Same result as `resolvedDays`, but the JavaScriptCore walk runs off the
    /// main actor. Opening the year chart used to expand 365 days during the
    /// navigation push and freeze the Records list.
    func prepareResolvedDays(from: Date, through: Date, now: Date = .now) async -> [DayResolution] {
        let calendar = recordsCalendar
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: through)
        guard start <= end else { return [] }

        guard !Task.isCancelled else { return [] }
        let revision = records.historyRevision
        let timeZone = recordsTimeZone.identifier
        await prefetchScheduleExpansions(
            from: start,
            through: end,
            periods: records.state.periods,
            snapshots: records.state.snapshots
        )
        guard !Task.isCancelled else { return [] }
        guard records.historyRevision == revision, recordsTimeZone.identifier == timeZone else {
            return await prepareResolvedDays(from: from, through: through, now: now)
        }
        let result = await resolveDaysOffMainActor(
            from: from,
            through: through,
            periods: records.state.periods,
            snapshots: records.state.snapshots,
            usesSharedCache: true
        )
        guard !Task.isCancelled else { return [] }
        guard records.historyRevision == revision, recordsTimeZone.identifier == timeZone else {
            return await prepareResolvedDays(from: from, through: through, now: now)
        }
        return result
    }

    /// Records month/year projection. This reuses the generated TypeScript
    /// schedule rules and Life's in-memory history backfill; it never creates
    /// durable observations, overrides, periods or snapshots for estimated
    /// days.
    func prepareRecordsDisplayDays(
        from: Date,
        through: Date,
        now: Date = .now
    ) async -> [DayResolution] {
        let input = displayInput(now: now)
        guard let bounds = lifeWorkProjectionBounds(now: now) else {
            let result = await prepareResolvedDays(from: from, through: through, now: now)
            guard !Task.isCancelled else { return [] }
            guard input == displayInput(now: now) else {
                return await prepareRecordsDisplayDays(from: from, through: through, now: now)
            }
            return result
        }
        let archive = lifeScheduleArchive(workStart: bounds.start, now: now)
        guard !Task.isCancelled else { return [] }
        await prefetchScheduleExpansions(
            from: from,
            through: through,
            periods: archive.periods,
            snapshots: archive.snapshots
        )
        guard !Task.isCancelled else { return [] }
        guard input == displayInput(now: now) else {
            return await prepareRecordsDisplayDays(from: from, through: through, now: now)
        }
        let result = await resolveDaysOffMainActor(
            from: from,
            through: through,
            periods: archive.periods,
            snapshots: archive.snapshots,
            usesSharedCache: false
        )
        guard !Task.isCancelled else { return [] }
        guard input == displayInput(now: now) else {
            return await prepareRecordsDisplayDays(from: from, through: through, now: now)
        }
        return result
    }

    private struct DisplayInput: Equatable {
        var revision: UInt64
        var calendar: Calendar
        var estimatedHours: ScheduleHoursConfiguration?
    }

    private func displayInput(now: Date) -> DisplayInput {
        .init(revision: records.projectionRevision, calendar: recordsCalendar,
              estimatedHours: lifeWorkProjectionBounds(now: now).flatMap {
                  lifeProjectionHours(workStart: $0.start, now: now)
              })
    }

    /// Current preferences only affect a synthetic first period or the gap
    /// before recorded history. A fully covered archive uses its own snapshots.
    private func lifeProjectionHours(workStart: Date, now: Date) -> ScheduleHoursConfiguration? {
        let periods = records.state.periods
        if periods.isEmpty { return sources.hours(now) }
        guard let firstStart = periods.map(\.startsOn).min(), workStart < firstStart,
              let current = DayRecordResolver.period(on: now, from: periods), current.endsBefore == nil
        else { return nil }
        return sources.hours(now)
    }

    private func prefetchScheduleExpansions(
        from: Date,
        through: Date,
        periods: [CareerPeriod],
        snapshots: [ScheduleSnapshot]
    ) async {
        let calendar = recordsCalendar
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: through)
        guard start <= end else { return }

        for snapshot in snapshots {
            guard !Task.isCancelled else { return }
            guard let period = periods.first(where: { $0.id == snapshot.periodID }),
                  period.startsOn <= end,
                  period.endsBefore.map({ $0 > start }) ?? true,
                  snapshot.effectiveFrom <= end,
                  let configuration = try? JSONDecoder().decode(
                    ScheduleHoursConfiguration.self,
                    from: snapshot.configurationData
                  )
            else { continue }
            let dayCalendar = period.civilCalendar()
            try? await CountdownRules.shared.prefetchExpansion(
                configuration: configuration,
                from: dayCalendar.startOfDay(for: from),
                through: dayCalendar.startOfDay(for: through),
                timeZone: period.timeZone
            )
        }
    }

    func observations(on day: Date) -> [WorkObservation] {
        observationIndex()[RecordJSON.dayKey(day, calendar: recordsCalendar)] ?? []
    }

    /// Observations grouped by the records-zone civil day. Chart metrics used
    /// to scan the whole archive once per day of the window.
    func observationIndex() -> [String: [WorkObservation]] {
        let revision = records.historyRevision
        if !records.hasUncommittedHistoryChanges,
           let cached = observationIndexCache, cached.revision == revision {
            return cached.byDay
        }
        var byDay: [String: [WorkObservation]] = [:]
        var calendars: [String: Calendar] = [:]
        for observation in records.state.observations {
            let zoneID = observation.timeZoneIdentifier
            let calendar: Calendar
            if let cached = calendars[zoneID] {
                calendar = cached
            } else {
                var next = Calendar(identifier: .gregorian)
                next.timeZone = TimeZone(identifier: zoneID) ?? recordsTimeZone
                calendars[zoneID] = next
                calendar = next
            }
            let key = RecordJSON.dayKey(observation.shiftAnchorDate, calendar: calendar)
            byDay[key, default: []].append(observation)
        }
        for key in byDay.keys {
            byDay[key]?.sort { $0.occurredAt < $1.occurredAt }
        }
        if !records.hasUncommittedHistoryChanges { observationIndexCache = (revision, byDay) }
        return byDay
    }

    /// Every civil day that has a user-authored Records fact. This deliberately
    /// has broader semantics than `recordedWorkDays()`: the latter remains the
    /// timer-only work metric, while the All Records navigation must also let a
    /// person find a manual correction, leave day, makeup day, or rest day.
    ///
    /// The key is a civil `YYYY-MM-DD`, never an absolute `Date`. An archive can
    /// contain rows written while travelling, so formatting a stored midnight in
    /// the device's current zone is not a valid way to recover its calendar day.
    func recordDayIndex() -> [RecordDayIndexEntry] {
        var entries: [String: RecordDayIndexEntry] = [:]

        for observation in records.state.observations where observation.kind.isWorkSessionRecord {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: observation.timeZoneIdentifier) ?? recordsTimeZone
            let key = RecordJSON.dayKey(observation.shiftAnchorDate, calendar: calendar)
            var entry = entries[key] ?? RecordDayIndexEntry(dayKey: key)
            entry.observations.append(observation)
            entries[key] = entry
        }

        for override in records.state.overrides where override.kind != .cleared {
            var entry = entries[override.dayKey] ?? RecordDayIndexEntry(dayKey: override.dayKey)
            entry.dayOverride = override
            entries[override.dayKey] = entry
        }

        for exception in records.state.exceptions where exception.origin == .user && !exception.isCleared {
            let key = Self.civilDayKey(fromExceptionKey: exception.dayKey)
            guard Self.isCivilDayKey(key) else { continue }
            var entry = entries[key] ?? RecordDayIndexEntry(dayKey: key)
            entry.calendarException = exception
            entries[key] = entry
        }

        return entries.values
            .map { entry in
                var sorted = entry
                sorted.observations.sort { $0.occurredAt < $1.occurredAt }
                return sorted
            }
            .sorted { $0.dayKey > $1.dayKey }
    }

    /// Days the user actually started, stopped, or logged overtime.
    ///
    /// The free list is this, not a year of schedule expansion. Opening the
    /// timer does not create a row. Life view can still project the schedule
    /// later without stuffing those days in here first.
    func recordedWorkDays() -> [RecordedWorkDay] {
        var groups: [String: [WorkObservation]] = [:]
        var anchors: [String: Date] = [:]
        var calendars: [String: Calendar] = [:]
        for observation in records.state.observations where observation.kind.isWorkSessionRecord {
            let zoneID = observation.timeZoneIdentifier
            let calendar: Calendar
            if let cached = calendars[zoneID] {
                calendar = cached
            } else {
                var next = Calendar(identifier: .gregorian)
                next.timeZone = TimeZone(identifier: zoneID) ?? recordsTimeZone
                calendars[zoneID] = next
                calendar = next
            }
            let key = RecordJSON.dayKey(observation.shiftAnchorDate, calendar: calendar)
            groups[key, default: []].append(observation)
            if anchors[key] == nil {
                anchors[key] = calendar.startOfDay(for: observation.shiftAnchorDate)
            }
        }
        return groups.keys.map { key in
            RecordedWorkDay(
                dayKey: key,
                shiftAnchorDate: anchors[key] ?? .distantPast,
                observations: (groups[key] ?? []).sorted { $0.occurredAt < $1.occurredAt }
            )
        }
        .sorted { $0.shiftAnchorDate > $1.shiftAnchorDate }
    }

    /// Formats an archive civil key in the records calendar. Keep this separate
    /// from the `Date` overload: callers with an archival key must not first
    /// construct an instant and accidentally move it to an adjacent day.
    func formatRecordsDayTitle(dayKey: String) -> String {
        guard let date = RecordJSON.date(fromDayKey: dayKey, calendar: recordsCalendar) else {
            return dayKey
        }
        return formatRecordsDayTitle(date)
    }

    /// The sync conflict recorded against a civil day, if any. Conflict keys
    /// carry a `#user` suffix, so the day page's exact string comparison never
    /// matched one the month grid had already flagged.
    func recordsConflict(forDayKey dayKey: String) -> SyncConflictCopy? {
        records.state.sync.conflicts.first {
            Self.civilDayKey(fromExceptionKey: $0.logicalKey) == dayKey
        }
    }

    private static func civilDayKey(fromExceptionKey key: String) -> String {
        String(key.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    }

    private static func isCivilDayKey(_ key: String) -> Bool {
        key.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    func daysRecordedOutsidePeriodTimeZone() -> [String] {
        let periodZones = Set(records.state.periods.map(\.timeZoneIdentifier))
        var calendars: [String: Calendar] = [:]
        var tagged: [(String, String)] = records.state.overrides.map { ($0.dayKey, $0.timeZoneIdentifier) }
        tagged.append(contentsOf: records.state.exceptions.map { ($0.dayKey, $0.timeZoneIdentifier) })
        for observation in records.state.observations {
            let zoneID = observation.timeZoneIdentifier
            let calendar: Calendar
            if let cached = calendars[zoneID] {
                calendar = cached
            } else {
                var next = Calendar(identifier: .gregorian)
                next.timeZone = TimeZone(identifier: zoneID) ?? recordsTimeZone
                calendars[zoneID] = next
                calendar = next
            }
            tagged.append((RecordJSON.dayKey(observation.shiftAnchorDate, calendar: calendar), zoneID))
        }
        return Set(
            tagged.compactMap { dayKey, zone in
                periodZones.contains(zone) ? nil : dayKey
            }
        ).sorted()
    }

    func resolvedDay(dayKey: String) -> DayResolution? {
        guard let date = RecordJSON.date(fromDayKey: dayKey, calendar: recordsCalendar) else { return nil }
        return resolvedDays(from: date, through: date).first
    }

    func recordsWindow(for scale: RecordsScale, anchor: Date, now: Date = .now) -> (Date, Date) {
        let calendar = recordsGridCalendar
        let day = calendar.startOfDay(for: anchor)
        switch scale {
        case .week:
            let start = calendar.date(
                from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: day)
            ) ?? day
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? day
            return (start, end)
        case .month:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: day)) ?? day
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? day
            return (start, end)
        case .year:
            let year = calendar.component(.year, from: day)
            let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? day
            let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? day
            return (start, end)
        case .life:
            return (day, day)
        }
    }

    func shiftRecordsAnchor(_ anchor: Date, scale: RecordsScale, by offset: Int) -> Date {
        let calendar = recordsGridCalendar
        switch scale {
        case .week:
            return calendar.date(byAdding: .weekOfYear, value: offset, to: anchor) ?? anchor
        case .month:
            return calendar.date(byAdding: .month, value: offset, to: anchor) ?? anchor
        case .year:
            return calendar.date(byAdding: .year, value: offset, to: anchor) ?? anchor
        case .life:
            return anchor
        }
    }

    /// Cached against the archive revision. Drawing a month asks this twice
    /// per cell — once for the day, once for the night before it — and
    /// rebuilding the whole index each time made a calendar cost hundreds of
    /// passes over every observation, override and exception on file.
    func isRecordedDay(_ dayKey: String) -> Bool {
        if !records.hasUncommittedHistoryChanges,
           let cached = recordedDayKeysCache, cached.revision == records.historyRevision {
            return cached.keys.contains(dayKey)
        }
        let keys = Set(recordDayIndex().map(\.dayKey))
        if !records.hasUncommittedHistoryChanges { recordedDayKeysCache = (records.historyRevision, keys) }
        return keys.contains(dayKey)
    }

    /// A durable, effective schedule is the user's standing agreement. App
    /// visits are observations, not attendance checks. Life's synthetic
    /// history uses separate IDs and never qualifies as this source.
    private func hasSavedSchedule(_ resolution: DayResolution) -> Bool {
        guard !resolution.expansionFailed, resolution.layer != .none,
              let periodID = resolution.periodID, let snapshotID = resolution.snapshotID
        else { return false }
        return records.state.periods.contains {
            $0.id == periodID && $0.covers(resolution.shiftAnchorDate)
        } && records.state.snapshots.contains {
            $0.id == snapshotID && $0.periodID == periodID
                && $0.effectiveFrom <= resolution.shiftAnchorDate
        }
    }

    func recordsDayCell(
        for resolution: DayResolution,
        previous: DayResolution? = nil,
        now: Date = .now,
        includesLifeProjection: Bool = false
    ) -> RecordsDayCell {
        let today = recordsCalendar.startOfDay(for: now)
        let date = recordsCalendar.startOfDay(for: resolution.shiftAnchorDate)
        let authorized = plus.isAuthorized
        let revealed = RecordsAccess.canRevealDay(
            dayKey: resolution.dayKey,
            today: now,
            calendar: recordsCalendar,
            authorized: authorized
        )
        let future = date > today
        let recorded = isRecordedDay(resolution.dayKey)
        let scheduled = !future && hasSavedSchedule(resolution)
        let corrected = records.state.overrides.contains {
            $0.dayKey == resolution.dayKey && $0.kind != .cleared
        }
        let projected = includesLifeProjection
            && !recorded
            && !corrected
            && !scheduled
            && isInsideLifeWorkProjection(date, now: now)
        let appearance: RecordsDayAppearance
        if !revealed {
            appearance = .locked
        } else if future && !recorded {
            appearance = resolution.isScheduledWorkday ? .planned : .rest
        } else if corrected {
            appearance = .corrected
        } else if recorded || (scheduled && resolution.isScheduledWorkday) {
            appearance = .recorded
        } else if !resolution.isScheduledWorkday {
            appearance = .rest
        } else {
            appearance = .unrecorded
        }
        // A 22:00–06:00 shift is two hours of its anchor day and six of the
        // next one. Reading only this day's own resolution dropped the morning
        // half from the cell, the summary and every total above them.
        let contributors = contributingShifts(
            for: resolution,
            previous: previous,
            now: now,
            includesLifeProjection: includesLifeProjection
        )
        let share = revealed && !contributors.isEmpty
            ? dayAllocation(resolution, contributedBy: contributors, now: now)
            : TimeAllocationShare(workMs: 0, overtimeMs: 0, sleepMs: 0, freeMs: 0, dayLengthMs: 0)
        return RecordsDayCell(
            dayKey: resolution.dayKey,
            date: date,
            appearance: appearance,
            workMs: share.workMs,
            overtimeMs: share.overtimeMs,
            breakMs: share.breakMs,
            freeMs: share.freeMs,
            observationCount: (observationIndex()[resolution.dayKey] ?? []).count,
            isToday: recordsCalendar.isDate(date, inSameDayAs: today),
            isFuture: future,
            isProjection: projected,
            hasConflict: records.state.sync.conflicts.contains {
                Self.civilDayKey(fromExceptionKey: $0.logicalKey) == resolution.dayKey
            },
            isFromSavedSchedule: revealed && scheduled && !recorded && !corrected
        )
    }

    func recordsHeadline(
        cells: [RecordsDayCell],
        days: [DayResolution],
        now: Date = .now
    ) -> RecordsHeadlineSummary? {
        guard plus.isAuthorized else { return nil }
        let recordedKeys = Set(cells.filter { $0.appearance == .recorded || $0.appearance == .corrected }.map(\.dayKey))
        let actualForecast = recordsActualForecast(cells: cells, days: days, now: now)
        guard !recordedKeys.isEmpty
            || actualForecast.map({ $0.forecast.days > 0 || $0.forecast.hours > 0 }) == true
            || (salaryType == .monthly && actualForecast?.total.earnings != nil)
        else { return nil }
        // Observed, corrected and elapsed saved-schedule days count. Life's
        // synthetic history remains an estimate. A day that merely *receives* those
        // hours after midnight is counted for its time, never as a workday.
        // `days` may reach one day either side of the window so an overnight
        // shift at the edge can still be found; the totals stay on `cells`.
        let byKey = Dictionary(days.map { ($0.dayKey, $0) }, uniquingKeysWith: { first, _ in first })
        let counted = Set(
            days
                .filter { contributesHours($0, now: now, includesLifeProjection: false) }
                .map(\.dayKey)
        )
        let shares = cells.compactMap { cell -> TimeAllocationShare? in
            guard let day = byKey[cell.dayKey] else { return nil }
            let contributors = [previousDay(before: day, in: byKey), day]
                .compactMap { $0 }
                .filter { counted.contains($0.dayKey) }
            guard !contributors.isEmpty else { return nil }
            let allocation = dayAllocation(day, contributedBy: contributors, now: now)
            // A neighbouring record alone does not make this a covered day.
            // Keep only actual spillover, or a record/correction on this date.
            guard recordedKeys.contains(day.dayKey)
                || allocation.workMs > 0 || allocation.overtimeMs > 0 || allocation.breakMs > 0
            else { return nil }
            return allocation
        }
        let combined = TimeAllocationCalculator.combining(shares)
        // Allocation describes the whole visible period, including scheduled
        // forecasts and rest days. Actual metrics above keep their own basis.
        let periodShares = cells.compactMap { cell -> TimeAllocationShare? in
            guard let day = byKey[cell.dayKey] else { return nil }
            return dayAllocation(
                day,
                contributedBy: contributingShifts(
                    for: day, previous: previousDay(before: day, in: byKey),
                    now: now, includesLifeProjection: true
                ),
                now: now
            )
        }
        let today = recordsCalendar.startOfDay(for: now)
        let visibleKeys = Set(cells.map(\.dayKey))
        let completedScheduledWorkdays = days.filter { day in
            guard visibleKeys.contains(day.dayKey), day.baseScheduleIsWorkday else { return false }
            let date = RecordJSON.date(fromDayKey: day.dayKey, calendar: recordsCalendar)
                ?? day.shiftAnchorDate
            return recordsCalendar.startOfDay(for: date) < today
        }.count
        let sleepKey = records.state.lifeProfile?.sleepSource == .healthSuggested
            ? "recordsSleepFromHealth"
            : "recordsSleepEstimated"
        return RecordsHeadlineSummary(
            workdays: recordedKeys.count,
            regularWorkMs: combined.workMs,
            overtimeMs: combined.overtimeMs,
            wakingFreeMs: combined.wakingFreeMs,
            estimatedIncome: recordsIncome(
                completedWorkdays: completedScheduledWorkdays,
                at: now
            ),
            completedScheduledWorkdays: completedScheduledWorkdays,
            allocationDays: periodShares.count,
            allocation: TimeAllocationCalculator.combining(periodShares),
            sleepSourceKey: sleepKey,
            actualForecast: actualForecast
        )
    }

    /// One shift-anchor row per visible date. A corrected or explicitly
    /// observed row is actual, as is elapsed saved scheduling. Synthetic life
    /// history and future schedule rows remain forecasts.
    /// The TypeScript rule keeps worked hours on these rows. Fixed monthly pay
    /// is allocated separately across every visible civil date, so absence or
    /// shorter recorded time does not turn this summary into a payslip.
    private func recordsActualForecast(
        cells: [RecordsDayCell],
        days: [DayResolution],
        now: Date
    ) -> NativeRecordsActualForecastSummary? {
        let cellsByKey = Dictionary(cells.map { ($0.dayKey, $0) }, uniquingKeysWith: { first, _ in first })
        let observationsByDay = observationIndex()
        let currentSnapshot = snapshot(at: now)
        let activeAnchorDayKey = countdownStarted
            ? currentSnapshot.map { RecordJSON.dayKey($0.startDate, calendar: recordsCalendar) }
            : nil
        let inputs = days.compactMap { day -> NativeRecordsActualForecastDay? in
            guard let cell = cellsByKey[day.dayKey] else { return nil }
            let dayObservations = observationsByDay[day.dayKey] ?? []
            let hasActualObservation = dayObservations.contains { $0.kind.isWorkSessionRecord }
            let actualKind: String? = if cell.appearance == .corrected {
                "corrected"
            } else if cell.appearance == .recorded && hasActualObservation {
                "observed"
            } else if !cell.isFuture && hasSavedSchedule(day) {
                "scheduled"
            } else {
                nil
            }
            let isForecast = actualKind == nil && (
                cell.isFromSavedSchedule
                    || cell.appearance == .planned
                    || cell.isProjection
                    || (cell.appearance == .recorded && !hasActualObservation)
            )
            guard actualKind != nil || isForecast else { return nil }
            let observations = dayObservations.compactMap { item -> NativeRecordsSummaryObservation? in
                let kind: String
                switch item.kind {
                case .countdownStarted: kind = "started"
                case .countdownStopped: kind = "stopped"
                case .timerSurfaceFirstSeen, .overtimeDeclared: return nil
                }
                return NativeRecordsSummaryObservation(
                    kind: kind,
                    occurredAtMs: item.occurredAt.timeIntervalSince1970 * 1_000
                )
            }
            return NativeRecordsActualForecastDay(
                dayKey: day.dayKey,
                actualKind: actualKind,
                resolvedSegments: day.segments,
                plannedSegments: day.baseScheduleSegments,
                overtimeSegments: actualKind == nil ? [] : overtimeSegments(on: day),
                observations: observations,
                isActiveAnchor: activeAnchorDayKey == day.dayKey
            )
        }
        guard !inputs.isEmpty || (presentationSalaryEnabled && salaryType == .monthly) else { return nil }
        return try? CountdownRules.shared.recordsActualForecast(input: .init(
            days: inputs,
            periodDayKeys: cells.map(\.dayKey),
            dailySalary: currentSnapshot?.dailySalary,
            asOfMs: now.timeIntervalSince1970 * 1_000,
            salaryRules: rulesInput(at: now, using: .base)
        ))
    }

    /// One civil day's numbers, cut from the shifts allowed to contribute to
    /// it. Both the month cell and the day canvas read this, so a day cannot
    /// print one total in the calendar and a different one on its own page.
    func dayAllocation(
        _ resolution: DayResolution,
        contributedBy shifts: [DayResolution],
        now: Date = .now
    ) -> TimeAllocationShare {
        dayCanvasModel(
            for: resolution,
            contributedBy: shifts,
            source: .scheduleEstimate,
            now: now
        ).allocation
    }

    func dayAllocation(
        _ resolution: DayResolution,
        previous: DayResolution? = nil,
        now: Date = .now
    ) -> TimeAllocationShare {
        dayAllocation(
            resolution,
            contributedBy: [previous, resolution].compactMap { $0 },
            now: now
        )
    }

    /// Saved schedules continue without daily attendance in the app. Only
    /// future schedules and synthetic life history require projection access.
    private func contributesHours(
        _ resolution: DayResolution,
        now: Date,
        includesLifeProjection: Bool
    ) -> Bool {
        if isRecordedDay(resolution.dayKey) { return true }
        if records.state.overrides.contains(where: {
            $0.dayKey == resolution.dayKey && $0.kind != .cleared
        }) { return true }
        if hasSavedSchedule(resolution) {
            return recordsCalendar.startOfDay(for: resolution.shiftAnchorDate)
                <= recordsCalendar.startOfDay(for: now) || includesLifeProjection
        }
        guard includesLifeProjection else { return false }
        return isInsideLifeWorkProjection(
            recordsCalendar.startOfDay(for: resolution.shiftAnchorDate),
            now: now
        )
    }

    /// The shifts allowed to put hours on a civil day: the day itself and the
    /// night before, each if its saved schedule, record, correction or life projection
    /// lets it count. Every surface that prints a per-day number reads this, so
    /// the calendar cell, the compact summary and the day canvas cannot
    /// disagree — the cell used to filter and the other two did not, which put
    /// "not recorded, 0 h" in the grid above a solid eight-hour day.
    func contributingShifts(
        for resolution: DayResolution,
        previous: DayResolution?,
        now: Date = .now,
        includesLifeProjection: Bool
    ) -> [DayResolution] {
        [previous, resolution]
            .compactMap { $0 }
            .filter { contributesHours($0, now: now, includesLifeProjection: includesLifeProjection) }
    }

    private func previousDay(
        before day: DayResolution,
        in index: [String: DayResolution]
    ) -> DayResolution? {
        guard let date = RecordJSON.date(fromDayKey: day.dayKey, calendar: recordsCalendar),
              let earlier = recordsCalendar.date(byAdding: .day, value: -1, to: date)
        else { return nil }
        return index[RecordJSON.dayKey(earlier, calendar: recordsCalendar)]
    }

    /// The whole civil day, ready to draw. Views never intersect shifts, clip
    /// overtime, derive a lunch gap or decide what a source is.
    func dayCanvasModel(
        for resolution: DayResolution,
        contributedBy shifts: [DayResolution],
        source: RecordsDaySource,
        now: Date = .now,
        editableAnchors: Set<String> = []
    ) -> RecordsDayCanvasModel {
        let start = recordsCalendar.startOfDay(for: resolution.shiftAnchorDate)
        let next = recordsCalendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86_400)
        let sleepKey = records.state.lifeProfile?.sleepSource == .healthSuggested
            ? "recordsSleepFromHealth"
            : "recordsSleepEstimated"
        var canvasShifts = shifts.map { shift in
            RecordsDayShift(
                anchorDayKey: shift.dayKey,
                segments: shift.segments,
                overtimeSegments: overtimeSegments(on: shift),
                source: shift.dayKey == resolution.dayKey
                    ? source
                    : shiftSource(of: shift, now: now),
                isEditable: editableAnchors.contains(shift.dayKey)
            )
        }
        // A past rest or unrecorded day has no contributing hours, but it is
        // still a real edit anchor. Keep that anchor without feeding its
        // scheduled estimate into the factual allocation.
        if editableAnchors.contains(resolution.dayKey),
           !canvasShifts.contains(where: { $0.anchorDayKey == resolution.dayKey }) {
            canvasShifts.append(
                RecordsDayShift(
                    anchorDayKey: resolution.dayKey,
                    segments: [],
                    source: source,
                    isEditable: true
                )
            )
        }
        return RecordsDayCanvasModel.build(
            RecordsDayCanvasModel.Input(
                dayKey: resolution.dayKey,
                dayStart: start,
                dayEnd: next,
                source: source,
                shifts: canvasShifts,
                sleepHours: records.state.lifeProfile?.averageSleepHours ?? 8,
                sleepSourceKey: sleepKey,
                isToday: recordsCalendar.isDate(start, inSameDayAs: now),
                now: now,
                // Any contributing shift, not just this day's. When last
                // night's expansion failed its overnight tail is missing, and
                // the hole it leaves here is unaccounted for rather than free.
                rulesFailed: resolution.expansionFailed
                    || shifts.contains(where: \.expansionFailed)
            )
        )
    }

    /// The source of a neighbouring shift reaching into the day on screen.
    private func shiftSource(of resolution: DayResolution, now: Date) -> RecordsDaySource {
        if records.state.overrides.contains(where: {
            $0.dayKey == resolution.dayKey && $0.kind != .cleared
        }) { return .corrected }
        if isRecordedDay(resolution.dayKey) {
            return resolution.layer == .calendarException ? .exception : .recorded
        }
        let date = recordsCalendar.startOfDay(for: resolution.shiftAnchorDate)
        if date > recordsCalendar.startOfDay(for: now) { return .planned }
        if hasSavedSchedule(resolution) {
            return resolution.layer == .calendarException ? .exception : .scheduled
        }
        return isInsideLifeWorkProjection(date, now: now) ? .lifeProjection : .scheduleEstimate
    }

    func overtimeSegments(on resolution: DayResolution) -> [NativeShiftSegment] {
        let latest = (observationIndex()[resolution.dayKey] ?? [])
            .filter { $0.kind == .overtimeDeclared }
            .max { lhs, rhs in
                if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt < rhs.occurredAt }
                return lhs.eventID.uuidString < rhs.eventID.uuidString
            }
        guard let latest,
              let segment = RecordsMetrics.declaredOvertimeSegment(
                observation: latest,
                day: resolution,
                avoidingRegularWork: true
              )
        else { return [] }
        return [segment]
    }

    func recordsDayDetail(
        for resolution: DayResolution,
        previous: DayResolution? = nil,
        now: Date = .now,
        includesLifeProjection: Bool = false
    ) -> RecordsDayDetail? {
        let cell = recordsDayCell(
            for: resolution,
            previous: previous,
            now: now,
            includesLifeProjection: includesLifeProjection
        )
        guard cell.appearance != .locked else { return nil }
        // The same qualified inputs the cell above it used, so the calendar and
        // the summary under it cannot print two different days.
        let canvas = dayCanvasModel(
            for: resolution,
            contributedBy: contributingShifts(
                for: resolution,
                previous: previous,
                now: now,
                includesLifeProjection: includesLifeProjection
            ),
            source: recordsDaySource(cell: cell, resolution: resolution),
            now: now
        )
        // The same words the day canvas uses. Two mappings meant the compact
        // summary could call a day one thing and its own page another.
        let sourceKey = canvas.source.titleKey
        let sleepKey = records.state.lifeProfile?.sleepSource == .healthSuggested
            ? "recordsSleepFromHealth"
            : "recordsSleepEstimated"
        let notes = observations(on: resolution.shiftAnchorDate).map { item in
            let time = formatRecordsTime(item.occurredAt)
            let kind: String
            switch item.kind {
            case .timerSurfaceFirstSeen: kind = t("recordsObservedFirstSeen")
            case .countdownStarted: kind = t("recordsObservedStarted")
            case .countdownStopped: kind = t("recordsObservedStopped")
            case .overtimeDeclared: kind = t("recordsObservedOvertime")
            }
            return "\(time) · \(kind)"
        }
        return RecordsDayDetail(
            dayKey: resolution.dayKey,
            date: resolution.shiftAnchorDate,
            appearance: cell.appearance,
            sourceKey: sourceKey,
            regularWorkMs: canvas.allocation.workMs,
            overtimeMs: canvas.allocation.overtimeMs,
            breakMs: canvas.allocation.breakMs,
            sleepMs: canvas.allocation.sleepMs,
            freeMs: canvas.allocation.freeMs,
            sleepSourceKey: sleepKey,
            observations: notes,
            isPlanned: cell.appearance == .planned,
            isProjection: cell.isProjection
        )
    }

    /// The day canvas for one civil day, including the part of the night
    /// before that runs into it. A locked day resolves to a model that carries
    /// no interval, duration, source or anchor at all — there is nothing to
    /// blur, because nothing real was ever built.
    func recordsDayCanvas(dayKey: String, now: Date = .now) async -> RecordsDayCanvasModel? {
        guard let date = RecordJSON.date(fromDayKey: dayKey, calendar: recordsCalendar) else {
            return nil
        }
        let start = recordsCalendar.startOfDay(for: date)
        let end = recordsCalendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86_400)
        guard RecordsAccess.canRevealDay(
            dayKey: dayKey,
            today: now,
            calendar: recordsCalendar,
            authorized: plus.isAuthorized
        ) else {
            return .locked(dayKey: dayKey, dayStart: start, dayEnd: end)
        }
        let earlier = recordsCalendar.date(byAdding: .day, value: -1, to: start) ?? start
        let resolved = await prepareRecordsDisplayDays(from: earlier, through: start, now: now)
        guard let resolution = resolved.first(where: { $0.dayKey == dayKey }) else { return nil }
        let previous = resolved.last(where: { $0.dayKey != dayKey })
        let cell = recordsDayCell(
            for: resolution,
            previous: previous,
            now: now,
            includesLifeProjection: true
        )
        // Records edits a day that has already happened. A future day is
        // changed by moving the schedule or by running the timer, not by
        // writing history forward — and a day the life profile merely projects
        // has no original input to open, so it gets no editor either.
        let today = recordsCalendar.startOfDay(for: now)
        let editableAnchors: Set<String> = plus.isAuthorized
            ? Set(
                resolved
                    .filter { candidate in
                        let anchor = recordsCalendar.startOfDay(for: candidate.shiftAnchorDate)
                        guard anchor <= today else { return false }
                        if contributesHours(candidate, now: now, includesLifeProjection: false) {
                            return true
                        }
                        return !isInsideLifeWorkProjection(anchor, now: now)
                    }
                    .map(\.dayKey)
            )
            : []
        return dayCanvasModel(
            for: resolution,
            contributedBy: contributingShifts(
                for: resolution,
                previous: previous,
                now: now,
                includesLifeProjection: true
            ),
            source: recordsDaySource(cell: cell, resolution: resolution),
            now: now,
            editableAnchors: editableAnchors
        )
    }

    /// One mapping from a day's appearance to the words that describe it, so
    /// the calendar cell, the compact summary and the day canvas cannot each
    /// invent their own vocabulary for the same day.
    func recordsDaySource(cell: RecordsDayCell, resolution: DayResolution) -> RecordsDaySource {
        if cell.appearance == .locked { return .locked }
        if cell.isProjection { return .lifeProjection }
        switch cell.appearance {
        case .planned: return .planned
        case .rest: return .rest
        case .unrecorded: return .unrecorded
        case .corrected: return .corrected
        case .locked: return .locked
        case .recorded:
            switch resolution.layer {
            case .override: return .corrected
            case .calendarException: return .exception
            case .schedule: return isRecordedDay(resolution.dayKey) ? .recorded : .scheduled
            case .none: return .unrecorded
            }
        }
    }

    func recordsMetrics(for days: [DayResolution]) -> RecordsPeriodMetrics {
        let sleep = records.state.lifeProfile?.averageSleepHours ?? 8
        let items = days.flatMap { observations(on: $0.shiftAnchorDate) }
        return RecordsMetrics.summarize(
            days: days,
            observations: items,
            sleepHours: sleep,
            calendar: recordsCalendar
        )
    }

    /// Records and the timer intentionally answer different questions. Records
    /// counts completed base-schedule workdays; the bundle applies the current
    /// salary while excluding today's partial shift and declared overtime.
    func recordsIncome(completedWorkdays: Int, at date: Date = .now) -> Double? {
        guard presentationSalaryEnabled, let input = rulesInput(at: date) else { return nil }
        do {
            let result = try CountdownRules.shared.recordsIncome(input: .init(
                completedWorkdays: completedWorkdays,
                rules: input
            ))
            if lastRulesError != nil { lastRulesError = nil }
            return result.earnings
        } catch {
            lastRulesError = error.localizedDescription
            return nil
        }
    }

    /// The window is entirely a property of the life profile — `now` is not
    /// read — but it is asked for once per calendar cell and once per resolved
    /// day, and each answer used to migrate the profile and re-anchor two
    /// partial dates. That is a full profile migration fifteen thousand times
    /// during a life build.
    private func lifeWorkProjectionBounds(now: Date) -> (start: Date, end: Date)? {
        let revision = records.lifeRevision
        let zone = recordsTimeZoneIdentifier
        if !records.hasUncommittedLifeChanges,
           let cached = lifeWorkProjectionBoundsCache,
           cached.revision == revision,
           cached.timeZoneIdentifier == zone {
            return cached.bounds
        }
        let bounds = computeLifeWorkProjectionBounds()
        if !records.hasUncommittedLifeChanges {
            lifeWorkProjectionBoundsCache = LifeWorkProjectionBoundsCache(
                revision: revision,
                timeZoneIdentifier: zone,
                bounds: bounds
            )
        }
        return bounds
    }

    private struct LifeWorkProjectionBoundsCache {
        var revision: UInt64
        var timeZoneIdentifier: String
        var bounds: (start: Date, end: Date)?
    }

    private func computeLifeWorkProjectionBounds() -> (start: Date, end: Date)? {
        guard var profile = records.state.lifeProfile else { return nil }
        let calendar = recordsCalendar
        profile.migrateLegacyFields(calendar: calendar)
        guard let start = profile.workStartedPartial?.calculationAnchor(in: calendar)
            ?? profile.workStartedOn,
            let end = profile.retirementOn?.calculationAnchor(in: calendar),
            start < end
        else { return nil }
        return (calendar.startOfDay(for: start), calendar.startOfDay(for: end))
    }

    func isInsideLifeWorkProjection(_ date: Date, now: Date) -> Bool {
        guard let bounds = lifeWorkProjectionBounds(now: now) else { return false }
        let day = recordsCalendar.startOfDay(for: date)
        return day >= bounds.start && day < bounds.end
    }

    func lifeScheduleArchive(
        workStart: Date,
        now: Date
    ) -> (periods: [CareerPeriod], snapshots: [ScheduleSnapshot]) {
        var periods = records.state.periods
        var snapshots = records.state.snapshots
        addLifeScheduleIfArchiveIsEmpty(
            workStart: workStart,
            now: now,
            periods: &periods,
            snapshots: &snapshots
        )
        addLifeHistoryBackfillIfNeeded(
            workStart: workStart,
            now: now,
            periods: &periods,
            snapshots: &snapshots
        )
        return (periods, snapshots)
    }

    /// Life's minimum input includes the current schedule even when Records
    /// has never been opened. Keep that estimate in memory: merely viewing the
    /// life grid must not backdate the durable Records archive by decades.
    private func addLifeScheduleIfArchiveIsEmpty(
        workStart: Date,
        now: Date,
        periods: inout [CareerPeriod],
        snapshots: inout [ScheduleSnapshot]
    ) {
        guard periods.isEmpty,
              let hours = lifeProjectionHours(workStart: workStart, now: now),
              let encoded = try? ScheduleHoursCodec.encode(hours)
        else { return }
        let periodID = UUID()
        periods.append(
            CareerPeriod(
                id: periodID,
                startsOn: workStart,
                endsBefore: nil,
                label: nil,
                timeZoneIdentifier: recordsTimeZoneIdentifier,
                calendarIdentifier: "gregorian",
                createdAt: now,
                editedAt: now,
                editCount: 1,
                editTieBreaker: UUID()
            )
        )
        snapshots.append(
            ScheduleSnapshot(
                id: UUID(),
                periodID: periodID,
                effectiveFrom: workStart,
                configurationData: encoded.data,
                fingerprint: encoded.fingerprint,
                editedAt: now,
                editCount: 1,
                editTieBreaker: UUID()
            )
        )
    }

    /// The current open-ended schedule is the fallback for the otherwise
    /// unknown history between workStart and the first explicit career period.
    /// Gaps between real periods and time after an ended period stay uncovered.
    private func addLifeHistoryBackfillIfNeeded(
        workStart: Date,
        now: Date,
        periods: inout [CareerPeriod],
        snapshots: inout [ScheduleSnapshot]
    ) {
        guard let firstStart = periods.map(\.startsOn).min(), workStart < firstStart,
              let currentPeriod = DayRecordResolver.period(on: now, from: periods),
              currentPeriod.endsBefore == nil,
              let hours = lifeProjectionHours(workStart: workStart, now: now),
              let encoded = try? ScheduleHoursCodec.encode(hours)
        else { return }
        let backfillPeriodID = UUID()
        var backfillPeriod = currentPeriod
        backfillPeriod.id = backfillPeriodID
        backfillPeriod.startsOn = workStart
        backfillPeriod.endsBefore = firstStart
        let backfillSnapshot = ScheduleSnapshot(
            id: UUID(),
            periodID: backfillPeriodID,
            effectiveFrom: workStart,
            configurationData: encoded.data,
            fingerprint: encoded.fingerprint,
            editedAt: now,
            editCount: 1,
            editTieBreaker: UUID()
        )
        periods.append(backfillPeriod)
        snapshots.append(backfillSnapshot)
    }

    // MARK: - Records dates
    //
    // `Date.formatted()` reads `Locale.autoupdatingCurrent` and
    // `TimeZone.current`. Neither is right here: the language is a user choice
    // the root view injects into the SwiftUI environment, and these strings are
    // built before SwiftUI sees them — a German UI on a Chinese device printed
    // Chinese weekdays. Records also keep their own civil zone, which the
    // travelling device zone must not shift a date across midnight. Every
    // records surface formats through these.

    /// "Wed, 26 Aug" — a day's identity in a list.
    func formatRecordsDayTitle(_ date: Date) -> String {
        recordsDateString(date, template: "EEEMMMd")
    }

    /// "26 Aug" — a day heading, where the weekday is already implied.
    func formatRecordsMonthDay(_ date: Date) -> String {
        recordsDateString(date, template: "MMMd")
    }

    /// "M" — one column of a month or week grid.
    func formatRecordsWeekdayNarrow(_ date: Date) -> String {
        recordsDateString(date, template: "EEEEE")
    }

    /// "August 2026" — a chart's window.
    func formatRecordsMonthYear(_ date: Date) -> String {
        recordsDateString(date, template: "MMMMy")
    }

    /// "August" — a compact month control where the year is already visible.
    func formatRecordsMonth(_ date: Date) -> String {
        recordsDateString(date, template: "MMMM")
    }

    /// The expanded year lists all twelve months in one narrow column beside a
    /// bar. "Dezember" and "листопада" do not fit there at full length.
    func formatRecordsMonthShort(_ date: Date) -> String {
        recordsDateString(date, template: "MMM")
    }

    /// A clock time as read in the records zone, not the device's.
    func formatRecordsTime(_ date: Date) -> String {
        recordsDateString(date, template: "jm")
    }

    /// Narrow weekday initials in the order the grid columns run.
    func recordsWeekdayGridSymbols() -> [String] {
        let calendar = recordsGridCalendar
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { offset in
            symbols[(calendar.firstWeekday - 1 + offset) % 7]
        }
    }

    /// How many blank cells a month grid needs before its first day, so the
    /// dates land in the right columns.
    func recordsGridLeadingBlanks(before date: Date) -> Int {
        let calendar = recordsGridCalendar
        let weekday = calendar.component(.weekday, from: date)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    /// Records time zone for the dates, app language for where the week starts.
    /// A German reader expects a month grid that begins on Monday, and
    /// `Calendar(identifier:)` alone always starts on Sunday.
    var recordsGridCalendar: Calendar {
        civilCalendars.gridCalendar(timeZoneIdentifier: recordsTimeZoneIdentifier, localeIdentifier: languageCode)
    }

    private func recordsDateString(_ date: Date, template: String) -> String {
        RecordsDateFormatters.shared
            .formatter(template: template, locale: locale, timeZone: recordsTimeZone)
            .string(from: date)
    }

}
