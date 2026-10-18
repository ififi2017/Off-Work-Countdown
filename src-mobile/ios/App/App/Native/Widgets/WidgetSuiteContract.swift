import Foundation

/// Payloads for the widget suite (plan 023). Compiled into the app, which
/// writes them, and the widget extension, which only reads them.
///
/// Each widget kind reads its own file so one provider never decodes another
/// kind's data inside the extension's memory budget. Nothing here carries a
/// salary, an hourly rate or income: the widget suite shows hours, days and
/// dates only (AGENTS.md privacy boundary, enforced by `WidgetSuitePrivacyTests`).
nonisolated enum WidgetSuiteKind {
    static let prefix = "com.rainif.offworkcountdown.macappstore.widget"
    static let week = "\(prefix).week"
    static let roster = "\(prefix).roster"
    static let summary = "\(prefix).summary"
    static let life = "\(prefix).life"
    static let holiday = "\(prefix).holiday"
    static let focus = "\(prefix).focus"

    static let all = [week, roster, summary, life, holiday, focus]
}

nonisolated enum WidgetSuiteFile: String, CaseIterable, Sendable {
    case calendar = "widget-calendar-v1.json"
    case summary = "widget-summary-v1.json"
    case life = "widget-life-v1.json"
    case holiday = "widget-holiday-v1.json"
    case focus = "widget-focus-v1.json"

    /// The kinds that draw from this file, reloaded whenever it changes.
    var kinds: [String] {
        switch self {
        case .calendar: [WidgetSuiteKind.week, WidgetSuiteKind.roster]
        case .summary: [WidgetSuiteKind.summary]
        case .life: [WidgetSuiteKind.life]
        case .holiday: [WidgetSuiteKind.holiday]
        case .focus: [WidgetSuiteKind.focus]
        }
    }
}

/// Whether Plus content may be drawn. The app writes `plus: false` and no data
/// for anyone without Plus; a subscription carries its end so the extension can
/// lock itself if the app is not opened again after it lapses.
nonisolated struct WidgetAccess: Codable, Equatable, Sendable {
    var plus: Bool
    var validUntilMs: Int64?

    static let locked = WidgetAccess(plus: false, validUntilMs: nil)

    func isUnlocked(atMs nowMs: Int64) -> Bool {
        guard plus else { return false }
        guard let validUntilMs else { return true }
        return nowMs < validUntilMs
    }
}

// MARK: - Calendar (week progress, tomorrow's shift, roster) — free

nonisolated struct WidgetCalendarPayload: Codable, Equatable, Sendable {
    nonisolated enum ScheduleKind: String, Codable, Sendable {
        /// Countdown only, no schedule: the roster widgets show their setup state.
        case none
        case weekly
        case alternatingWeeks
        case rotation
        case custom
    }

    var schemaVersion = 1
    var generatedAtMs: Int64
    var locale: String
    var timeZoneIdentifier: String
    /// `Calendar.firstWeekday` of the Records grid, 1 = Sunday.
    var firstWeekday: Int
    var scheduleKind: ScheduleKind
    /// Every civil day from the start of this week (or month, whichever is
    /// earlier) through the end of next month.
    var days: [WidgetCalendarDay]
    /// Localized copy the app chose, keyed by `WidgetCalendarLabel`.
    var labels: [String: String]

    /// The civil day holding `ms`; days run midnight to the next day's midnight.
    func dayIndex(containingMs ms: Int64) -> Int? {
        guard let index = days.lastIndex(where: { $0.startMs <= ms }) else { return nil }
        let end = index + 1 < days.count ? days[index + 1].startMs : days[index].startMs + 86_400_000
        return ms < end ? index : nil
    }

    func day(containingMs ms: Int64) -> WidgetCalendarDay? {
        dayIndex(containingMs: ms).map { days[$0] }
    }

    /// The days of the week holding `ms`, in the Records grid's week order.
    func week(containingMs ms: Int64) -> ArraySlice<WidgetCalendarDay> {
        guard let index = dayIndex(containingMs: ms) else { return [] }
        let date = WidgetSuiteTime.date(days[index].startMs)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        calendar.firstWeekday = firstWeekday
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        let startMs = WidgetSuiteTime.ms(interval.start)
        let endMs = WidgetSuiteTime.ms(interval.end)
        let lower = days.firstIndex { $0.startMs >= startMs } ?? index
        let upper = days.firstIndex { $0.startMs >= endMs } ?? days.count
        return days[lower..<max(lower, upper)]
    }
}

nonisolated struct WidgetCalendarDay: Codable, Equatable, Sendable, Identifiable {
    nonisolated enum Kind: String, Codable, Sendable {
        case work
        case rest
        /// A public holiday the user does not work.
        case holiday
        /// A weekend day a holiday calendar moves work onto (调休上班).
        case makeupWork
        /// Leave the user recorded or adopted.
        case leave
    }

    var dayKey: String
    /// Local midnight.
    var startMs: Int64
    var kind: Kind
    /// Shift type name, holiday name or nil for the plain work / rest wording.
    var title: String?
    /// `#RRGGBB` of the extended-schedule shift type, when there is one.
    var colorHex: String?
    /// Effective work segments, `[start, end]` in ms.
    var segments: [[Int64]]
    /// 1-based day in a rotation cycle and the cycle's length.
    var cycleDay: Int?
    var cycleLength: Int?

    var id: String { dayKey }
    var isWork: Bool { kind == .work || kind == .makeupWork }
    var workMs: Int64 { segments.reduce(0) { $0 + max(0, $1[1] - $1[0]) } }
    var startAtMs: Int64? { segments.first?[0] }
    var endAtMs: Int64? { segments.last?[1] }

    /// Effective work still ahead at `ms`.
    func remainingMs(atMs ms: Int64) -> Int64 {
        segments.reduce(0) { total, segment in
            total + max(0, segment[1] - max(segment[0], ms))
        }
    }
}

nonisolated enum WidgetCalendarLabel {
    static let work = "work"
    static let rest = "rest"
    static let leave = "leave"
    static let makeupWork = "makeupWork"
    static let bigWeek = "bigWeek"
    static let smallWeek = "smallWeek"
    static let weekdaysShort = "weekdaysShort"
}

// MARK: - Period summary — Plus

nonisolated struct WidgetSummaryPayload: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var generatedAtMs: Int64
    var locale: String
    var access: WidgetAccess
    var periods: [WidgetSummaryPeriod]
    /// Today's remaining work segments, so worked time keeps growing between
    /// app launches without the app writing again.
    var liveSegments: [[Int64]]
    var labels: [String: String]

    func period(_ kind: WidgetSummaryPeriod.Kind) -> WidgetSummaryPeriod? {
        periods.first { $0.kind == kind }
    }
}

nonisolated struct WidgetSummaryPeriod: Codable, Equatable, Sendable {
    nonisolated enum Kind: String, Codable, Sendable, CaseIterable {
        case week, month, year
    }

    nonisolated struct Bar: Codable, Equatable, Sendable {
        nonisolated enum State: String, Codable, Sendable { case past, current, future, rest }
        var label: String
        var valueMs: Int64
        var state: State
    }

    var kind: Kind
    var title: String
    var subtitle: String?
    var startDayKey: String
    var endDayKey: String
    var workedMs: Int64
    var overtimeMs: Int64
    var workdays: Int
    /// Workdays the schedule plans for the whole period, worked or ahead.
    var plannedWorkdays: Int
    var remainingWorkdays: Int
    /// Share of the period's planned workdays already behind, 0…1.
    var progress: Double
    var bars: [Bar]
    /// A localized comparison with the previous period, when Records has one.
    var comparison: String?
    /// Whether the live segments belong to this period.
    var includesToday: Bool

    func workedMs(liveSegments: [[Int64]], since generatedAtMs: Int64, atMs ms: Int64) -> Int64 {
        guard includesToday, ms > generatedAtMs else { return workedMs }
        let added = liveSegments.reduce(Int64(0)) { total, segment in
            let start = max(segment[0], generatedAtMs)
            let end = min(segment[1], ms)
            return total + max(0, end - start)
        }
        return workedMs + added
    }
}

// MARK: - Life — Plus

nonisolated struct WidgetLifePayload: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var generatedAtMs: Int64
    var locale: String
    var access: WidgetAccess
    /// Days since 1970-01-01 in the user's civil calendar.
    var bornDay: Int?
    /// Only the birth year is known: day counts are shown as approximate.
    var bornIsApproximate: Bool
    var careerStartDay: Int?
    var retirementDay: Int?
    var lifeYears: Int
    /// The user asked Life not to show exact ages.
    var hidesExactAges: Bool
    var labels: [String: String]
}

// MARK: - Holidays and leave — holidays free, leave Plus

nonisolated struct WidgetHolidayPayload: Codable, Equatable, Sendable {
    nonisolated struct Holiday: Codable, Equatable, Sendable {
        var name: String
        var startDayKey: String
        var startMs: Int64
        var endDayKey: String
        var days: Int
        var isEstimated: Bool
    }

    nonisolated struct Leave: Codable, Equatable, Sendable {
        nonisolated enum DayKind: String, Codable, Sendable { case leave, holiday, rest }
        nonisolated struct Day: Codable, Equatable, Sendable {
            var dayKey: String
            var kind: DayKind
        }
        var startDayKey: String
        var startMs: Int64
        var requestedDays: Double
        var totalDays: Int
        var days: [Day]
    }

    var schemaVersion = 1
    var generatedAtMs: Int64
    var locale: String
    /// When this week's work ends: the first rest moment after the last
    /// workday of the week, if the schedule has one.
    var weekendStartMs: Int64?
    var nextHoliday: Holiday?
    var access: WidgetAccess
    /// The next adopted or recorded leave run, Plus only.
    var nextLeave: Leave?
    /// Remaining annual-leave days across balances, Plus only.
    var leaveRemainingDays: Double?
    var labels: [String: String]
}

// MARK: - Focus — Plus

nonisolated struct WidgetFocusPayload: Codable, Equatable, Sendable {
    nonisolated struct Block: Codable, Equatable, Sendable {
        var title: String
        var symbol: String?
        var startMs: Int64
        var endMs: Int64
        var round: Int
        var rounds: Int
        var isBreak: Bool
    }

    var schemaVersion = 1
    var generatedAtMs: Int64
    var locale: String
    var access: WidgetAccess
    /// The running block, its break and the blocks queued after them.
    var blocks: [Block]
    var labels: [String: String]

    func current(atMs ms: Int64) -> Block? {
        blocks.first { $0.startMs <= ms && ms < $0.endMs }
    }

    func next(afterMs ms: Int64) -> Block? {
        blocks.first { $0.startMs > ms && !$0.isBreak }
    }
}

// MARK: - Reading and writing

nonisolated enum WidgetSuiteStore {
    static let appGroupIdentifier = "group.com.rainif.offworkcountdown.macappstore"

    static func url(_ file: WidgetSuiteFile) -> URL? {
        appGroupURL(file: file.rawValue)
    }

    static func appGroupURL(file name: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appending(path: name)
    }

    static func load<Payload: Decodable>(_ type: Payload.Type, from file: WidgetSuiteFile) -> Payload? {
        guard let url = url(file), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// Small helpers shared by every suite widget's timeline.
nonisolated enum WidgetSuiteTime {
    /// Local midnights after `start`, up to `count` of them.
    static func midnights(after start: Date, count: Int, calendar: Calendar = .current) -> [Date] {
        var result: [Date] = []
        var cursor = calendar.startOfDay(for: start)
        for _ in 0..<count {
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            result.append(next)
            cursor = next
        }
        return result
    }

    static func ms(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970 * 1_000) }
    static func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1_000) }
}
