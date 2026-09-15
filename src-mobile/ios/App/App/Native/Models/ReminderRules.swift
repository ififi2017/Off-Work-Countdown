import Foundation

/// One shift's reminders with their absolute trigger times and final copy
/// (`buildShiftReminders` in `lib/reminders.ts`, plan 019 R2).
///
/// `lib/reminders.ts` stays the specification: `ScheduleRules.reminders` is
/// held to fixtures generated from it. A reminder whose switch is off is still
/// listed, with no title or body, so turning a switch on mid-shift does not
/// replay the ones already crossed.
nonisolated enum ReminderRules {
    /// A break-boundary push that fires this late has lost its context.
    private static let breakFreshnessMs = 2.0 * 60_000
    /// A micro-break after a longer gap between ticks means the device slept
    /// through the work it is asking the user to rest from.
    private static let microBreakMaxTickGapMs = 2.0 * 60_000
    /// Keeps a one-minute interval from exhausting the pending-notification quota.
    private static let maxMicroBreaksPerSegment = 240
    private static let defaultTitle = "Off work reminder"

    private struct Milestone: Sendable {
        let percent: Int
        let defaultBody: String

        func title(_ titles: NativeMilestoneTitles) -> String {
            switch percent {
            case 50: titles.milestone50
            case 75: titles.milestone75
            case 90: titles.milestone90
            case 95: titles.milestone95
            default: titles.milestone100
            }
        }

        func messages(_ messages: NativeMilestoneMessages) -> [String] {
            switch percent {
            case 50: messages.milestone50
            case 75: messages.milestone75
            case 90: messages.milestone90
            case 95: messages.milestone95
            default: messages.milestone100
            }
        }
    }

    private static let milestones = [
        Milestone(percent: 50, defaultBody: "Halfway there."),
        Milestone(percent: 75, defaultBody: "The hardest part is behind you."),
        Milestone(percent: 90, defaultBody: "Almost there."),
        Milestone(percent: 95, defaultBody: "Just a little longer."),
        Milestone(percent: 100, defaultBody: "Off work time!"),
    ]

    static func buildShiftReminders(_ shift: ShiftTimeline, _ inputs: NativeReminderInputs) -> [NativeReminder] {
        let durationMs = shift.durationMs
        guard shift.isValid, durationMs > 0 else { return [] }
        let endAtMs = shift.endAtMs
        var reminders: [NativeReminder] = []

        for milestone in milestones {
            let thresholdMs = (durationMs * Double(milestone.percent) / 100).rounded(.up)
            let cycleEndSummary = milestone.percent == 100
                ? nonEmpty(inputs.cycleEndSummaryBody.map(JavaScriptNumber.trim))
                : nil
            let audible = cycleEndSummary != nil
                || inputs.mode == "milestones"
                || (inputs.mode == "simple" && milestone.percent == 100)
            reminders.append(NativeReminder(
                id: "milestone:\(milestone.percent)",
                kind: "milestone",
                atMs: absoluteAtElapsedMs(shift, thresholdMs),
                expiresAtMs: nil,
                maxTickGapMs: nil,
                collapseGroup: "milestone",
                title: audible
                    ? nonEmpty(milestone.title(inputs.milestoneTitles)) ?? nonEmpty(inputs.fallbackTitle) ?? defaultTitle
                    : nil,
                body: audible ? cycleEndSummary ?? milestoneBody(milestone, inputs, endAtMs: endAtMs) : nil
            ))
        }

        let breakTitle = nonEmpty(inputs.breakTitle) ?? nonEmpty(inputs.fallbackTitle) ?? defaultTitle
        let segments = shift.segments
        for index in 0..<(segments.count - 1) {
            let breakStartAtMs = segments[index].endAtMs
            let breakEndAtMs = segments[index + 1].startAtMs
            guard breakEndAtMs > breakStartAtMs else { continue }

            let startBody = inputs.lunchStartEnabled ? nonEmpty(inputs.lunchStartBody) : nil
            reminders.append(NativeReminder(
                id: "breakStart:\(JavaScriptNumber.string(breakStartAtMs))",
                kind: "breakStart",
                atMs: breakStartAtMs,
                // A break that is already over is not starting.
                expiresAtMs: min(breakStartAtMs + breakFreshnessMs, breakEndAtMs),
                maxTickGapMs: nil,
                collapseGroup: "break",
                title: startBody == nil ? nil : breakTitle,
                body: startBody
            ))

            let endBody = inputs.lunchEndEnabled ? nonEmpty(inputs.lunchEndBody) : nil
            reminders.append(NativeReminder(
                id: "breakEnd:\(JavaScriptNumber.string(breakEndAtMs))",
                kind: "breakEnd",
                atMs: breakEndAtMs,
                expiresAtMs: min(breakEndAtMs + breakFreshnessMs, segments[index + 1].endAtMs),
                maxTickGapMs: nil,
                collapseGroup: "break",
                title: endBody == nil ? nil : breakTitle,
                body: endBody
            ))
        }

        let intervalMinutes = max(0, inputs.microBreakIntervalMinutes)
        let intervalMs = Double(intervalMinutes) * 60_000
        if intervalMs > 0 {
            for segment in segments {
                // Each segment restarts the count: a round cut short by lunch
                // does not carry over to the afternoon.
                for bucket in 1...maxMicroBreaksPerSegment {
                    let atMs = segment.startAtMs + Double(bucket) * intervalMs
                    if atMs >= segment.endAtMs { break }
                    let body = inputs.microBreakEnabled
                        ? microBreakBody(inputs.microBreakMessages, bucket: bucket, intervalMinutes: intervalMinutes)
                        : nil
                    let start = JavaScriptNumber.string(segment.startAtMs)
                    reminders.append(NativeReminder(
                        id: "microBreak:\(start):\(bucket)",
                        kind: "microBreak",
                        atMs: atMs,
                        expiresAtMs: nil,
                        maxTickGapMs: microBreakMaxTickGapMs,
                        collapseGroup: "microBreak:\(start)",
                        title: body == nil ? nil : nonEmpty(inputs.microBreakTitle) ?? breakTitle,
                        body: body
                    ))
                }
            }
        }

        return sortedByTime(reminders)
    }

    /// Stable, as `Array.prototype.sort` is: equal instants keep list order.
    static func sortedByTime(_ reminders: [NativeReminder]) -> [NativeReminder] {
        reminders.enumerated()
            .sorted { $0.element.atMs != $1.element.atMs ? $0.element.atMs < $1.element.atMs : $0.offset < $1.offset }
            .map(\.element)
    }

    /// Wall-clock instant at which `elapsedMs` of effective work has passed.
    /// A milestone landing exactly on a segment's end fires there, not after
    /// the gap.
    private static func absoluteAtElapsedMs(_ shift: ShiftTimeline, _ elapsedMs: Double) -> Double {
        var remaining = elapsedMs
        for segment in shift.segments {
            let duration = segment.endAtMs - segment.startAtMs
            if remaining <= duration { return segment.startAtMs + remaining }
            remaining -= duration
        }
        return shift.segments[shift.segments.count - 1].endAtMs
    }

    /// Seeded by the shift's end so a pending notification keeps its wording
    /// every time the list is rebuilt.
    private static func milestoneBody(_ milestone: Milestone, _ inputs: NativeReminderInputs, endAtMs: Double) -> String? {
        let pool = milestone.messages(inputs.milestoneMessages)
        guard !pool.isEmpty else { return milestone.defaultBody }
        let index = (abs(endAtMs) + Double(milestone.percent)).truncatingRemainder(dividingBy: Double(pool.count))
        // A fractional end (overtime stopped mid-millisecond) indexes nothing in
        // the TypeScript either, which leaves the body out.
        guard index.rounded(.towardZero) == index else { return nil }
        return pool[Int(index)]
    }

    private static func microBreakBody(_ pool: [String], bucket: Int, intervalMinutes: Int) -> String? {
        guard !pool.isEmpty, let template = nonEmpty(pool[bucket % pool.count]) else { return nil }
        // `String.prototype.replace` with a string pattern: first occurrence only.
        guard let range = template.range(of: "{{minutes}}", options: .literal) else { return template }
        return template.replacingCharacters(in: range, with: String(bucket * intervalMinutes))
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

extension JavaScriptNumber {
    /// `String(number)` for the millisecond instants that go into reminder ids:
    /// whole numbers without a fraction, anything else in shortest form.
    nonisolated static func string(_ value: Double) -> String {
        if value.rounded(.towardZero) == value, abs(value) < 9e15 { return String(Int64(value)) }
        return "\(value)"
    }
}

nonisolated struct NativeReminder: Codable, Hashable, Sendable {
    let id: String
    let kind: String
    let atMs: Double
    let expiresAtMs: Double?
    let maxTickGapMs: Double?
    let collapseGroup: String?
    let title: String?
    let body: String?

    func withID(_ id: String) -> NativeReminder {
        NativeReminder(
            id: id, kind: kind, atMs: atMs, expiresAtMs: expiresAtMs, maxTickGapMs: maxTickGapMs,
            collapseGroup: collapseGroup, title: title, body: body
        )
    }
}

nonisolated struct NativeMilestoneTitles: Codable, Sendable {
    let milestone50: String
    let milestone75: String
    let milestone90: String
    let milestone95: String
    let milestone100: String
}

nonisolated struct NativeMilestoneMessages: Codable, Sendable {
    let milestone50: [String]
    let milestone75: [String]
    let milestone90: [String]
    let milestone95: [String]
    let milestone100: [String]
}

nonisolated struct NativeReminderInputs: Codable, Sendable {
    let mode: String
    let fallbackTitle: String
    /// Title for lunch start and end. Without it the rules fall back to the
    /// off-work title, which is what made lunch pushes read "下班提醒".
    let breakTitle: String
    let milestoneTitles: NativeMilestoneTitles
    let milestoneMessages: NativeMilestoneMessages
    let lunchStartEnabled: Bool
    let lunchStartBody: String
    let lunchEndEnabled: Bool
    let lunchEndBody: String
    let microBreakEnabled: Bool
    let microBreakTitle: String
    let microBreakIntervalMinutes: Int
    let microBreakMessages: [String]
    let cycleEndSummaryBody: String?
}
