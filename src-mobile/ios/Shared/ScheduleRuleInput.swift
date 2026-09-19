import Foundation

nonisolated struct NativeShiftSegment: Codable, Hashable, Sendable {
    let startAtMs: Double
    let endAtMs: Double
}

nonisolated struct NativeWatchRulesProjection: Codable, Equatable, Sendable {
    nonisolated struct Shift: Codable, Equatable, Sendable {
        let segments: [NativeShiftSegment]
        let plannedEndAtMs: Double
        let overtimeEndAtMs: Double?
        let finishedAtMs: Double?
        let isRunning: Bool
        let transitions: [Transition]
    }

    nonisolated struct Transition: Codable, Equatable, Sendable {
        let atMs: Double
        let state: String
    }

    nonisolated struct NextShift: Codable, Equatable, Sendable {
        let startAtMs: Double
        let validUntilMs: Double
    }

    let scheduleState: String
    let shift: Shift?
    let nextShift: NextShift?
    let contentExpiresAtMs: Double
}

nonisolated struct NativeWatchCurrentShift: Codable, Sendable {
    let segments: [NativeShiftSegment]
    let plannedEndAtMs: Double
    let overtimeEndAtMs: Double?
}

nonisolated struct NativeWorkSchedule: Codable, Equatable, Hashable, Sendable {
    let mode: String
    let referenceWeekStartMs: Double?
    let referenceWeekType: String?
    let singleWeekendWorkday: Int?
    let rotationAnchorMs: Double?
    let rotationWorkDays: Int?
    let rotationRestDays: Int?
}

nonisolated struct ScheduleRuleInput: Codable, Equatable, Sendable {
    let startTime: String
    let endTime: String
    var nowMs: Double
    let workdays: [Int]
    let schedule: NativeWorkSchedule
    let breakStartTime: String?
    let breakDurationMinutes: Int
    let overtimeEndAtMs: Double?
    let forcedWorkdayStartMs: Double?
    var timeZoneIdentifier: String? = nil
    /// Plan 018 P8's extended schedule, when the user has one switched on.
    /// `nil` keeps every rule on the fixed-hours path it took before.
    var extendedSchedule: ExtendedSchedulePlan? = nil
}
