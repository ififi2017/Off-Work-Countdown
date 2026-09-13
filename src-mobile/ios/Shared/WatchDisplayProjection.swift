import Foundation

nonisolated enum WatchDisplayAvailability: Equatable, Sendable {
    case waiting
    case locked
    case confirmationRequired
    case pending
    case contentExpired
    case invalid
    case content(WatchDisplayContent)
}

nonisolated struct WatchDisplayContent: Equatable, Sendable {
    let scheduleState: WatchShiftContentV1.ScheduleState
    let phase: WatchShiftPhase?
    let remainingMs: Int64?
    let progress: Double?
    let effectiveEndAtMs: Int64?
    let nextBoundaryAtMs: Int64?
    let nextShiftStartAtMs: Int64?
    let presentation: WatchPresentationV1
}

nonisolated enum WatchDisplayProjection {
    static func project(_ package: WatchSnapshotPackageV1?, nowMs: Int64) -> WatchDisplayAvailability {
        guard let package else { return .waiting }
        switch WatchSnapshotAvailabilityEvaluator.evaluate(package, nowMs: nowMs) {
        case .locked, .accessExpired:
            return .locked
        case .confirmationRequired:
            return .confirmationRequired
        case .pending:
            return .pending
        case .contentExpired:
            return .contentExpired
        case .invalid:
            return .invalid
        case .content(let content):
            let evaluation: WatchShiftEvaluation?
            if let shift = content.shift, shift.isRunning || shift.finishedAtMs != nil {
                guard let value = WatchShiftEvaluator.evaluate(shift, nowMs: nowMs) else { return .invalid }
                evaluation = value
            } else {
                evaluation = nil
            }
            return .content(.init(
                scheduleState: content.scheduleState,
                phase: evaluation?.phase,
                remainingMs: evaluation?.remainingMs,
                progress: evaluation?.progress,
                effectiveEndAtMs: evaluation == nil ? nil : content.shift.map {
                    $0.finishedAtMs ?? $0.overtimeEndAtMs ?? $0.plannedEndAtMs
                },
                nextBoundaryAtMs: evaluation?.nextBoundaryAtMs,
                nextShiftStartAtMs: content.nextShift?.startAtMs,
                presentation: content.presentation
            ))
        }
    }

    /// Dates at which a cached package can change without a new phone delivery.
    /// Minute entries keep the progress ring useful while the exact rule and
    /// expiry boundaries ensure state changes are never rounded past their time.
    static func timelineDates(
        for package: WatchSnapshotPackageV1?,
        from now: Date,
        minuteCount: Int = 60
    ) -> [Date] {
        let nowMs = Int64((now.timeIntervalSince1970 * 1_000).rounded(.towardZero))
        guard let package, package.isValid else { return [now] }
        var milliseconds: Set<Int64> = [nowMs]

        if minuteCount > 0 {
            for offset in 1...min(minuteCount, 120) {
                let (value, overflow) = nowMs.addingReportingOverflow(Int64(offset) * 60_000)
                if !overflow, value < package.expiresAtMs { milliseconds.insert(value) }
            }
        }
        milliseconds.insert(package.expiresAtMs)
        if let accessEnd = package.access.validUntilMs { milliseconds.insert(accessEnd) }
        if let content = package.content {
            if let shift = content.shift {
                milliseconds.formUnion(shift.segments.flatMap { [$0.startAtMs, $0.endAtMs] })
                milliseconds.formUnion(shift.transitions.map(\.atMs))
                if let finished = shift.finishedAtMs { milliseconds.insert(finished) }
            }
            if let next = content.nextShift {
                milliseconds.insert(next.startAtMs)
                milliseconds.insert(next.validUntilMs)
            }
        }
        return milliseconds
            .filter { $0 >= nowMs && $0 <= WatchSnapshotContract.maximumJSONTimestamp }
            .sorted()
            .map { Date(timeIntervalSince1970: Double($0) / 1_000) }
    }
}

/// Watch surfaces format in the phone app's language and the shift's own time
/// zone, both carried by the package, so a Watch set to another language or
/// zone still shows the same clock times as the iPhone.
nonisolated enum WatchDisplayFormat {
    static func locale(_ presentation: WatchPresentationV1) -> Locale {
        Locale(identifier: presentation.localeIdentifier)
    }

    /// "17:00" or "5:00 PM".
    static func time(_ milliseconds: Int64, _ presentation: WatchPresentationV1) -> String {
        date(milliseconds).formatted(dateStyle(presentation).hour().minute())
    }

    /// "Mon 09:00" — for a next shift that may not be today.
    static func weekdayAndTime(_ milliseconds: Int64, _ presentation: WatchPresentationV1) -> String {
        date(milliseconds).formatted(dateStyle(presentation).weekday(.abbreviated).hour().minute())
    }

    /// A countdown clock. Seconds only while the screen is fully awake; without
    /// them the minute rounds up, so the last minute reads 0:01 rather than 0:00.
    static func clock(_ remainingMilliseconds: Int64, showsSeconds: Bool, _ presentation: WatchPresentationV1) -> String {
        let remaining = max(0, remainingMilliseconds)
        if showsSeconds {
            return Duration.seconds(remaining / 1_000)
                .formatted(.time(pattern: .hourMinuteSecond).locale(locale(presentation)))
        }
        return Duration.seconds(roundedUpMinutes(remaining) * 60)
            .formatted(.time(pattern: .hourMinute).locale(locale(presentation)))
    }

    /// "3h 18m" — the unit keeps a remaining duration from reading as a time of day.
    static func shortDuration(_ remainingMilliseconds: Int64, _ presentation: WatchPresentationV1) -> String {
        let minutes = roundedUpMinutes(max(0, remainingMilliseconds))
        let units: Set<Duration.UnitsFormatStyle.Unit> = minutes >= 60 ? [.hours, .minutes] : [.minutes]
        return Duration.seconds(minutes * 60)
            .formatted(.units(allowed: units, width: .narrow).locale(locale(presentation)))
    }

    /// "60%" with the language's own digits and percent placement.
    static func percent(_ progress: Double, _ presentation: WatchPresentationV1) -> String {
        (min(100, max(0, progress)) / 100)
            .formatted(.percent.precision(.fractionLength(0)).locale(locale(presentation)))
    }

    static func label(for phase: WatchShiftPhase, _ presentation: WatchPresentationV1) -> String {
        switch phase {
        case .before: presentation.restingLabel
        case .working: presentation.workingLabel
        case .resting: presentation.lunchLabel
        case .overtime: presentation.overtimeLabel
        case .finished: presentation.finishedLabel
        }
    }

    static func symbol(for phase: WatchShiftPhase) -> String {
        switch phase {
        case .before: "clock"
        case .working: "briefcase"
        case .resting: "cup.and.saucer"
        case .overtime: "clock.badge.exclamationmark"
        case .finished: "checkmark.circle"
        }
    }

    struct Footnote: Equatable {
        /// A Watch localization key whose template takes `{{time}}`.
        let key: String
        let atMs: Int64
        let includesWeekday: Bool
    }

    /// The one time that gives a countdown its meaning: when work ends, when
    /// overtime ends, when work resumes after a break, or when the next shift starts.
    static func footnote(for content: WatchDisplayContent) -> Footnote? {
        switch content.phase {
        case .working, .finished:
            content.effectiveEndAtMs.map { Footnote(key: "watchOffAt", atMs: $0, includesWeekday: false) }
        case .overtime:
            content.effectiveEndAtMs.map { Footnote(key: "watchOvertimeUntil", atMs: $0, includesWeekday: false) }
        case .resting:
            content.nextBoundaryAtMs.map { Footnote(key: "watchBackAt", atMs: $0, includesWeekday: false) }
        case .before:
            content.nextBoundaryAtMs.map { Footnote(key: "watchNextShiftAt", atMs: $0, includesWeekday: false) }
        case nil:
            content.nextShiftStartAtMs.map { Footnote(key: "watchNextShiftAt", atMs: $0, includesWeekday: true) }
        }
    }

    static func footnoteTime(_ footnote: Footnote, _ presentation: WatchPresentationV1) -> String {
        footnote.includesWeekday
            ? weekdayAndTime(footnote.atMs, presentation)
            : time(footnote.atMs, presentation)
    }

    /// Replaces `{{name}}` placeholders in a translated template.
    static func fill(_ template: String, _ values: [String: String]) -> String {
        values.reduce(template) { $0.replacingOccurrences(of: "{{\($1.key)}}", with: $1.value) }
    }

    private static func roundedUpMinutes(_ milliseconds: Int64) -> Int64 {
        milliseconds / 60_000 + (milliseconds % 60_000 == 0 ? 0 : 1)
    }

    private static func date(_ milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    private static func dateStyle(_ presentation: WatchPresentationV1) -> Date.FormatStyle {
        var style = Date.FormatStyle()
        style.locale = locale(presentation)
        style.timeZone = TimeZone(identifier: presentation.timeZoneIdentifier) ?? .current
        return style
    }
}
