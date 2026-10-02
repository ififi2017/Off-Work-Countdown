import Foundation

/// Weekly and monthly reports (plan 020 §4).
///
/// A report is one week or month of the Records page, read out of the same
/// aggregates the Records summary prints. Nothing here adds up hours or pay a
/// second way: `CycleReportBuilder` only arranges what `RecordsHeadlineSummary`
/// and the day cells already say, so a report cannot disagree with Records.
nonisolated enum CycleReportKind: String, Codable, CaseIterable, Sendable {
    case week
    case month
}

/// A report's period, named by civil day keys rather than instants. A
/// notification can be opened days later, and a key still means the same week
/// then, where "this week" would have moved on. Both ends are inclusive.
nonisolated struct CycleReportPeriod: Hashable, Codable, Sendable {
    var kind: CycleReportKind
    var startDayKey: String
    var endDayKey: String
    /// The Records time zone the keys were cut in, carried for the record. The
    /// keys are civil dates, so a later travel does not move the period.
    var timeZoneIdentifier: String

    static let urlScheme = "offworkcountdown"
    static let urlHost = "report"

    // MARK: Period arithmetic

    /// The week or month holding `date`. `calendar` is the Records grid
    /// calendar, so weeks begin where the Records page's weeks do.
    static func containing(_ date: Date, kind: CycleReportKind, calendar: Calendar) -> Self {
        let day = calendar.startOfDay(for: date)
        let start: Date
        let end: Date
        switch kind {
        case .week:
            start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: day)) ?? day
            end = calendar.date(byAdding: .day, value: 6, to: start) ?? day
        case .month:
            start = calendar.date(from: calendar.dateComponents([.year, .month], from: day)) ?? day
            end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? day
        }
        return Self(
            kind: kind,
            startDayKey: RecordJSON.dayKey(start, calendar: calendar),
            endDayKey: RecordJSON.dayKey(end, calendar: calendar),
            timeZoneIdentifier: calendar.timeZone.identifier
        )
    }

    func startDate(calendar: Calendar) -> Date? { RecordJSON.date(fromDayKey: startDayKey, calendar: calendar) }
    func endDate(calendar: Calendar) -> Date? { RecordJSON.date(fromDayKey: endDayKey, calendar: calendar) }

    func previous(calendar: Calendar) -> Self? { neighbour(by: -1, calendar: calendar) }
    func following(calendar: Calendar) -> Self? { neighbour(by: 1, calendar: calendar) }

    private func neighbour(by offset: Int, calendar: Calendar) -> Self? {
        guard let start = startDate(calendar: calendar),
              let moved = calendar.date(
                byAdding: kind == .week ? .weekOfYear : .month, value: offset, to: start
              )
        else { return nil }
        return Self.containing(moved, kind: kind, calendar: calendar)
    }

    /// Every civil day of the period, in order.
    func dayKeys(calendar: Calendar) -> [String] {
        guard let start = startDate(calendar: calendar), let end = endDate(calendar: calendar) else { return [] }
        var keys: [String] = []
        var cursor = start
        while cursor <= end, keys.count <= 31 {
            keys.append(RecordJSON.dayKey(cursor, calendar: calendar))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return keys
    }

    /// Whether the period's last day has passed, in the Records time zone.
    func isComplete(at now: Date, calendar: Calendar) -> Bool {
        guard let end = endDate(calendar: calendar) else { return false }
        return calendar.startOfDay(for: now) > end
    }

    /// Reports arrive the morning after a period closes: a week or month that
    /// has not ended has nothing to look back on.
    static let notificationHour = 9

    func notificationDate(calendar: Calendar) -> Date? {
        guard let end = endDate(calendar: calendar),
              let next = calendar.date(byAdding: .day, value: 1, to: end)
        else { return nil }
        return calendar.date(bySettingHour: Self.notificationHour, minute: 0, second: 0, of: next)
    }

    var notificationIdentifier: String { "owc.report.\(kind.rawValue).\(startDayKey)" }
    static let notificationIdentifierPrefix = "owc.report."

    // MARK: Link

    /// The route a report notification carries. It goes through the app's own
    /// URL handling, the same way a widget or the alarm reminder does, so a cold
    /// start and a running app take one path.
    var url: URL {
        var components = URLComponents()
        components.scheme = Self.urlScheme
        components.host = Self.urlHost
        components.queryItems = [
            URLQueryItem(name: "kind", value: kind.rawValue),
            URLQueryItem(name: "start", value: startDayKey),
            URLQueryItem(name: "end", value: endDayKey),
            URLQueryItem(name: "tz", value: timeZoneIdentifier),
        ]
        return components.url ?? URL(string: "\(Self.urlScheme)://\(Self.urlHost)")!
    }

    init(kind: CycleReportKind, startDayKey: String, endDayKey: String, timeZoneIdentifier: String) {
        self.kind = kind
        self.startDayKey = startDayKey
        self.endDayKey = endDayKey
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    /// `nil` for a link that does not name a well-formed period, so a damaged
    /// or hand-written link opens nothing instead of an arbitrary range.
    init?(url: URL) {
        guard url.scheme == Self.urlScheme, url.host == Self.urlHost,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let kind = value("kind").flatMap(CycleReportKind.init(rawValue:)),
              let start = value("start"), Self.isDayKey(start),
              let end = value("end"), Self.isDayKey(end),
              start <= end,
              let zone = value("tz"), TimeZone(identifier: zone) != nil
        else { return nil }
        self.init(kind: kind, startDayKey: start, endDayKey: end, timeZoneIdentifier: zone)
        // A week or a month, never a free range: reject a span the kind cannot hold.
        let calendar = Calendar.civil(timeZoneIdentifier: zone)
        let span = dayKeys(calendar: calendar).count
        guard span > 0, kind == .week ? span == 7 : (28...31).contains(span) else { return nil }
    }

    private static func isDayKey(_ key: String) -> Bool {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        return parts.count == 3 && parts[0].count == 4 && parts[1].count == 2 && parts[2].count == 2
            && parts.allSatisfy { $0.allSatisfy(\.isASCII) && Int($0) != nil }
    }
}

extension Calendar {
    /// A Gregorian calendar fixed to a zone, for reading civil day keys.
    nonisolated static func civil(timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar
    }
}

/// One period's figures, as the Records summary reports them.
nonisolated struct CycleReportFigures: Equatable, Sendable {
    var workdays: Int
    /// Everything worked, overtime included, as Records' "Time worked".
    var workedMs: Int64
    var overtimeMs: Int64
    /// Pay estimated by the existing salary rules; `nil` without a salary.
    var income: Double?

    var hasData: Bool { workdays > 0 || workedMs > 0 }

    /// What a Records summary says about time that has actually happened. A
    /// forecast is a plan, not something the user did, so it never counts.
    init(headline: RecordsHeadlineSummary?) {
        guard let headline else {
            self.init(workdays: 0, workedMs: 0, overtimeMs: 0, income: nil)
            return
        }
        if let split = headline.actualForecast {
            self.init(
                workdays: Int(split.actual.days.rounded(.down)),
                workedMs: Int64((split.actual.hours * 3_600_000).rounded()),
                overtimeMs: Int64((split.actualOvertimeHours * 3_600_000).rounded()),
                income: split.actual.earnings
            )
        } else {
            self.init(
                workdays: headline.workdays,
                workedMs: headline.regularWorkMs + headline.overtimeMs,
                overtimeMs: headline.overtimeMs,
                income: headline.estimatedIncome
            )
        }
    }

    init(workdays: Int, workedMs: Int64, overtimeMs: Int64, income: Double?) {
        self.workdays = max(0, workdays)
        self.workedMs = max(0, workedMs)
        self.overtimeMs = max(0, overtimeMs)
        self.income = income.flatMap { $0.isFinite ? max(0, $0) : nil }
    }
}

nonisolated enum CycleReportDayKind: Equatable, Sendable {
    case work
    case rest
    /// A day after `asOf`, in a period still running.
    case upcoming
}

nonisolated struct CycleReportDay: Equatable, Sendable, Identifiable {
    var dayKey: String
    var date: Date
    var kind: CycleReportDayKind
    var workMs: Int64
    var overtimeMs: Int64
    var isToday: Bool

    var id: String { dayKey }
}

/// The change from the period before, only ever built from two periods that
/// both hold data.
nonisolated struct CycleReportComparison: Equatable, Sendable {
    var workedDeltaMs: Int64
    var overtimeDeltaMs: Int64
}

/// Everything a report plays, computed once. Each stage reads this one value,
/// so the numbers cannot change between the first page and the last.
nonisolated struct CycleReportSnapshot: Equatable, Sendable {
    var period: CycleReportPeriod
    var days: [CycleReportDay]
    var figures: CycleReportFigures
    var comparison: CycleReportComparison?
    var restDayCount: Int
    var longestRestRun: Int
    /// Index into `days` where the longest rest stretch begins; the first one
    /// wins a tie.
    var longestRestStart: Int?
    /// The period is still running; figures read "so far", never a forecast.
    var isInProgress: Bool

    var hasData: Bool { figures.hasData }
    var income: Double? { figures.income }

    /// The snapshot a report that was not asked for pay is allowed to hold.
    /// Dropping the amount here, not in each view, keeps it out of every page
    /// and every accessibility label at once.
    func withoutIncome() -> Self {
        var copy = self
        copy.figures.income = nil
        return copy
    }
}

nonisolated enum CycleReportBuilder {
    /// `cells` are the period's own days, in order, as the Records page builds
    /// them. `previous` is the period before, when it holds records.
    static func snapshot(
        period: CycleReportPeriod,
        cells: [RecordsDayCell],
        figures: CycleReportFigures,
        previous: CycleReportFigures?,
        isInProgress: Bool
    ) -> CycleReportSnapshot {
        let days = cells.map { cell -> CycleReportDay in
            let worked = cell.workMs + cell.overtimeMs
            let kind: CycleReportDayKind =
                cell.isFuture ? .upcoming : (worked > 0 ? .work : .rest)
            return CycleReportDay(
                dayKey: cell.dayKey,
                date: cell.date,
                kind: kind,
                workMs: cell.workMs,
                overtimeMs: cell.overtimeMs,
                isToday: cell.isToday
            )
        }
        // A day that only receives the tail of a night shift is not a rest day:
        // it already carries worked time, so it stays `work` here.
        var longest = 0
        var longestStart: Int?
        var run = 0
        var restDays = 0
        for (index, day) in days.enumerated() {
            if day.kind == .rest {
                restDays += 1
                run += 1
                if run > longest {
                    longest = run
                    longestStart = index - run + 1
                }
            } else {
                run = 0
            }
        }
        var comparison: CycleReportComparison?
        if figures.hasData, let previous, previous.hasData {
            comparison = CycleReportComparison(
                workedDeltaMs: figures.workedMs - previous.workedMs,
                overtimeDeltaMs: figures.overtimeMs - previous.overtimeMs
            )
        }
        return CycleReportSnapshot(
            period: period,
            days: days,
            figures: figures,
            comparison: comparison,
            restDayCount: restDays,
            longestRestRun: longest,
            longestRestStart: longestStart,
            isInProgress: isInProgress
        )
    }
}

/// Which report notifications to leave with the system.
///
/// Only the next period of each enabled kind is scheduled. Each one costs a
/// slot of iOS's 64 pending notifications, which the shift reminders, focus
/// timers and the alarm refresh already share, and a report is only worth
/// sending to someone who has opened the app since the last one.
nonisolated struct CycleReportNotificationPlan: Equatable, Sendable {
    struct Item: Equatable, Sendable {
        var period: CycleReportPeriod
        var fireDate: Date
    }

    /// The slots this feature may use; the shift reminders give them up.
    static let reservedSlots = 2

    static func items(
        weekly: Bool,
        monthly: Bool,
        now: Date,
        calendar: Calendar
    ) -> [Item] {
        var items: [Item] = []
        for (kind, enabled) in [(CycleReportKind.week, weekly), (.month, monthly)] where enabled {
            var period = CycleReportPeriod.containing(now, kind: kind, calendar: calendar)
            // The running period closes in the future, so its morning-after is
            // too; the loop only matters if that morning has already passed.
            for _ in 0..<2 {
                if let fire = period.notificationDate(calendar: calendar), fire > now {
                    items.append(Item(period: period, fireDate: fire))
                    break
                }
                guard let next = period.following(calendar: calendar) else { break }
                period = next
            }
        }
        return items.sorted { $0.fireDate < $1.fireDate }
    }
}

/// What a report asks to open: one period, from a notification, a link, or
/// the Records page's own week or month.
struct CycleReportRequest: Identifiable, Equatable {
    let id = UUID()
    var period: CycleReportPeriod
}
