#if DEBUG
import Foundation

/// Deterministic, in-memory inputs for marketing captures and timer QA.
///
/// The shared JavaScript rules still resolve every shift. These values only
/// describe the schedule and the virtual clock supplied to those rules.
enum DebugTimerScenario: String, CaseIterable, Identifiable {
    case working
    case lunch
    case overtime
    case completed
    case restDay
    case manualSchedule

    struct Session: Equatable {
        let scenario: DebugTimerScenario
        let realAnchor: Date
        let virtualAnchor: Date

        func date(for realDate: Date) -> Date {
            virtualAnchor.addingTimeInterval(realDate.timeIntervalSince(realAnchor))
        }
    }

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .working: "debugScenarioWorking"
        case .lunch: "debugScenarioLunch"
        case .overtime: "debugScenarioOvertime"
        case .completed: "debugScenarioCompleted"
        case .restDay: "debugScenarioRestDay"
        case .manualSchedule: "debugScenarioManual"
        }
    }

    var symbol: String {
        switch self {
        case .working: "timer"
        case .lunch: "cup.and.saucer.fill"
        case .overtime: "clock.arrow.circlepath"
        case .completed: "checkmark.circle.fill"
        case .restDay: "bed.double.fill"
        case .manualSchedule: "questionmark.circle"
        }
    }

    var startMinutes: Int { 9 * 60 }

    var endMinutes: Int {
        switch self {
        case .overtime, .completed: 12 * 60
        case .working, .lunch, .restDay, .manualSchedule: 17 * 60
        }
    }

    var workdays: Set<Int> {
        switch self {
        case .completed:
            // Friday completes, then Saturday is deliberately the next shift.
            [1, 2, 3, 4, 5, 6]
        case .restDay:
            // 2024-08-23 is Friday. The next configured shift is Monday.
            [1, 2, 3, 4]
        case .working, .lunch, .overtime, .manualSchedule:
            [1, 2, 3, 4, 5]
        }
    }

    var scheduleMode: WorkScheduleMode {
        self == .manualSchedule ? .off : .classic
    }

    var lunchStartMinutes: Int {
        self == .lunch ? 14 * 60 : 12 * 60
    }

    var lunchDurationMinutes: Int { 60 }

    var overtimeEndMinutes: Int? {
        self == .overtime ? 15 * 60 : nil
    }

    var sessionActive: Bool { self != .manualSchedule }

    func overtimeEndAtMs(on date: Date) -> Double? {
        guard let overtimeEndMinutes else { return nil }
        return Calendar.current.date(
            bySettingHour: overtimeEndMinutes / 60,
            minute: overtimeEndMinutes % 60,
            second: 0,
            of: date
        )?.timeIntervalSince1970.applyingMilliseconds
    }

    static let virtualStartDate: Date = {
        var components = DateComponents()
        components.calendar = .current
        components.timeZone = .current
        components.year = 2024
        components.month = 8
        components.day = 23
        components.hour = 14
        components.minute = 22
        components.second = 0
        guard let date = components.date else {
            preconditionFailure("The debug capture date must be representable.")
        }
        return date
    }()
}

extension OffWorkStore {
    func activateDebugTimerScenario(_ scenario: DebugTimerScenario, at date: Date = .now) {
        debugTimerSession = .init(
            scenario: scenario,
            realAnchor: date,
            virtualAnchor: DebugTimerScenario.virtualStartDate
        )
        timelineExpanded = false
        presentedRoute = nil
        timerPath.removeAll()
        settingsPath.removeAll()
        selectedTab = .timer
        resetCelebratedSession()
    }
}

private extension TimeInterval {
    var applyingMilliseconds: Double { self * 1_000 }
}
#endif
