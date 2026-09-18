import Foundation

/// Shift resolution, snapshots, Widget shifts, the Watch projection and range
/// expansion for iOS (plan 019 R1), and the reminder list scheduled from them
/// (R2, with `ReminderRules`).
///
/// These used to run as TypeScript in JavaScriptCore. The TypeScript is still
/// the specification for behaviour iOS shares with Web and Desktop:
/// `scripts/ios-schedule-rule-oracle.mjs` keeps the exact entry points this
/// replaced, and `AppTests/ScheduleRuleFixtureTests.swift` holds this file to
/// fixtures generated from it. A change to a shared rule lands in `lib/` and
/// here together, with regenerated fixtures.
///
/// Everything is resolved in one civil time zone: the input's identifier, or
/// `TimeZone.current` when there is none. That is the TypeScript zoned path.
/// The bundle's zone-less path only ever ran for the few callers that passed
/// no zone, and differed from the zoned path only inside DST gaps.
///
/// Pure and `nonisolated`: no caller has to be on the main actor, which is
/// what the JavaScriptCore context used to require.
nonisolated enum ScheduleRules {
    static func snapshot(input: NativeRulesInput) -> NativeShiftSnapshot {
        let zone = CivilZone(identifier: input.timeZoneIdentifier, extended: ExtendedScheduleResolver(plan: input.extendedSchedule))
        let shift = resolveCurrentShift(input, zone)
        let nextShift = nextShift(after: shift, input, zone)
        let clockIn = countdownProjection(input, shift: shift, nextShift: nextShift, zone)
        let dailySalary = SalaryRules.dailySalary(
            amount: input.salaryAmount,
            type: input.salaryType,
            monthlyWorkingDays: input.monthlyWorkingDays,
            annualBonusMonths: input.annualBonusMonths
        )
        let payRatio = shift.payRatio(at: input.nowMs)
        return NativeShiftSnapshot(
            segments: shift.segments,
            startAtMs: shift.startAtMs,
            endAtMs: shift.endAtMs,
            plannedEndAtMs: shift.plannedEndAtMs,
            overtimeEndAtMs: shift.overtimeEndAtMs,
            durationMs: shift.durationMs,
            plannedDurationMs: shift.plannedDurationMs,
            elapsedMs: shift.elapsedMs(at: input.nowMs),
            remainingMs: shift.remainingMs(at: input.nowMs),
            progress: shift.progress(at: input.nowMs),
            payRatio: payRatio,
            activeBreakEndAtMs: shift.activeBreakEndAtMs(at: input.nowMs),
            isWorkday: zone.isScheduledWorkday(shift.startAtMs, input.workdays, input.schedule),
            nextRestAtMs: zone.nextRestDayStartMs(afterMs: input.nowMs, input.workdays, input.schedule),
            dailySalary: dailySalary,
            earnedSoFar: dailySalary.map { max(0, payRatio) * $0 },
            nextShiftStartAtMs: nextShift?.startAtMs,
            nextShiftEndAtMs: nextShift?.endAtMs,
            countdownTargetAtMs: clockIn.targetAtMs,
            countdownAnchorAtMs: clockIn.anchorAtMs,
            countdownProgress: clockIn.progress
        )
    }

    /// Salary-free Watch projection. `currentShift` is the session's frozen
    /// shift when it supplies one; `finishedAtMs` its early clock-off.
    static func watchProjection(
        input: NativeRulesInput,
        scheduleConfigured: Bool,
        isRunning: Bool,
        currentShift: NativeWatchCurrentShift? = nil,
        finishedAtMs: Double? = nil
    ) -> NativeWatchRulesProjection {
        let zone = CivilZone(identifier: input.timeZoneIdentifier, extended: ExtendedScheduleResolver(plan: input.extendedSchedule))
        let resolved = resolveCurrentShift(input, zone)
        let nextStartAtMs = nextShift(after: resolved, input, zone)?.startAtMs
        let currentIsActual = isActualShift(resolved, input, zone)
        // `|| null` in the TypeScript: an instant of 0 means none.
        let finishedAtMs = finishedAtMs == 0 ? nil : finishedAtMs
        let override = currentShift.map {
            ShiftTimeline(segments: $0.segments, plannedEndAtMs: $0.plannedEndAtMs, overtimeEndAtMs: $0.overtimeEndAtMs)
        }
        let hasSession = override != nil
        let shift = override ?? resolved
        let settlementAtMs = zone.addCivilDaysMs(
            zone.startOfCivilDayMs(hasSession ? shift.endAtMs : input.nowMs),
            1
        )
        let contentExpiresAtMs = scheduleConfigured ? nextStartAtMs ?? settlementAtMs : settlementAtMs
        return NativeWatchRulesProjection(
            scheduleState: scheduleConfigured || hasSession
                ? (isRunning ? "scheduled" : "stopped")
                : "notConfigured",
            shift: (scheduleConfigured && currentIsActual) || hasSession
                ? watchShift(shift, isRunning: isRunning && finishedAtMs == nil, finishedAtMs: finishedAtMs)
                : nil,
            nextShift: scheduleConfigured
                ? nextStartAtMs.map { .init(startAtMs: $0, validUntilMs: $0) }
                : nil,
            contentExpiresAtMs: contentExpiresAtMs
        )
    }

    /// Every scheduled shift after the current one, through the first shift
    /// that starts at or after `throughMs`. That last one is kept as the
    /// Widget's countdown target even though it is never drawn as a shift.
    static func widgetShifts(
        input: NativeRulesInput,
        throughMs: Double,
        maximumCount: Int
    ) -> [NativeWidgetShiftSnapshot] {
        let zone = CivilZone(identifier: input.timeZoneIdentifier, extended: ExtendedScheduleResolver(plan: input.extendedSchedule))
        let current = zone.shiftTimeline(input.startTime, input.endTime, nowMs: input.nowMs, options: .init(input))
        var shifts: [NativeWidgetShiftSnapshot] = []
        var afterMs = max(input.nowMs, current.endAtMs)
        while shifts.count < max(0, maximumCount) {
            guard let shift = zone.nextShiftTimeline(
                input.startTime, input.endTime, input.workdays, input.schedule,
                afterMs: afterMs, options: .init(input).withoutOvertime
            ) else { break }
            shifts.append(NativeWidgetShiftSnapshot(
                segments: shift.segments,
                startAtMs: shift.startAtMs,
                endAtMs: shift.endAtMs,
                plannedEndAtMs: shift.plannedEndAtMs,
                overtimeEndAtMs: shift.overtimeEndAtMs,
                durationMs: shift.durationMs,
                countdownAnchorAtMs: countdownAnchorAtMs(input, targetAtMs: shift.startAtMs, zone)
            ))
            if shift.startAtMs >= throughMs || shift.endAtMs <= afterMs { break }
            afterMs = shift.endAtMs
        }
        return shifts
    }

    /// `widgetShifts` off the caller's actor. A year of shifts is not free, and
    /// the Widget composer asks from the main actor.
    @concurrent
    static func widgetShiftsInBackground(
        input: NativeRulesInput,
        throughMs: Double,
        maximumCount: Int
    ) async -> [NativeWidgetShiftSnapshot] {
        widgetShifts(input: input, throughMs: throughMs, maximumCount: maximumCount)
    }

    /// Every civil day in `[from, through]` with its planned hours. Rest days
    /// still carry segments so a makeup-day exception can reuse them. Noon is
    /// the probe, so an overnight shift keys as the day it starts; manual
    /// (`off`) days are rest.
    static func expandScheduleRange(
        configuration: ScheduleHoursConfiguration,
        from: Date,
        through: Date,
        timeZone: TimeZone? = nil
    ) -> [NativeScheduleDayExpansion] {
        let zone = CivilZone(
            timeZone: timeZone ?? .current,
            extended: ExtendedScheduleResolver(plan: configuration.extendedSchedule)
        )
        let fromDay = zone.civil(from.timeIntervalSince1970 * 1_000).dayNumber
        let throughDay = zone.civil(through.timeIntervalSince1970 * 1_000).dayNumber
        guard throughDay >= fromDay else { return [] }

        var days: [NativeScheduleDayExpansion] = []
        days.reserveCapacity(throughDay - fromDay + 1)

        for dayNumber in fromDay...throughDay {
            // Resolved per day: an extended schedule gives each day its own
            // shift, and without one every day resolves to the configured pair.
            let clocks = zone.dayClocks(dayNumber: dayNumber, configuration.startTime, configuration.endTime)
            let start = clocks.start
            let end = clocks.end
            let dayBreak = zone.dayBreak(
                dayNumber: dayNumber,
                configuration.breakStartTime,
                configuration.breakDurationMinutes
            )
            let breakClock = dayBreak.startTime.flatMap { $0.isEmpty ? nil : Clock($0) }
            let breakDurationMs = Double(dayBreak.durationMinutes) * 60_000
            let startAtMs = zone.utcMs(dayNumber: dayNumber, start)
            var endAtMs = zone.utcMs(dayNumber: dayNumber, end)
            if endAtMs <= startAtMs {
                endAtMs = end.minutes > start.minutes
                    ? startAtMs
                    : zone.utcMs(dayNumber: dayNumber + 1, end)
            }
            var segments = [NativeShiftSegment(startAtMs: startAtMs, endAtMs: endAtMs)]
            if let breakClock, breakDurationMs > 0 {
                var breakStartAtMs = zone.utcMs(dayNumber: dayNumber, breakClock)
                if breakStartAtMs < startAtMs {
                    breakStartAtMs = zone.utcMs(dayNumber: dayNumber + 1, breakClock)
                }
                let breakEndAtMs = breakStartAtMs + breakDurationMs
                if breakStartAtMs > startAtMs, breakEndAtMs < endAtMs {
                    segments = [
                        NativeShiftSegment(startAtMs: startAtMs, endAtMs: breakStartAtMs),
                        NativeShiftSegment(startAtMs: breakEndAtMs, endAtMs: endAtMs),
                    ]
                }
            }
            days.append(NativeScheduleDayExpansion(
                dayKey: zone.dayKey(startAtMs),
                shiftAnchorStartAtMs: startAtMs,
                isWorkday: zone.isScheduledWorkdayInZone(startAtMs, configuration.workdays, configuration.schedule),
                segments: segments
            ))
        }
        return days
    }

    /// Whether the configured break lands strictly inside the shift. No break
    /// configured is trivially valid.
    static func validateBreak(input: NativeRulesInput) -> Bool {
        guard let breakStartTime = input.breakStartTime, !breakStartTime.isEmpty,
              input.breakDurationMinutes > 0
        else { return true }
        let zone = CivilZone(identifier: input.timeZoneIdentifier, extended: ExtendedScheduleResolver(plan: input.extendedSchedule))
        return zone.shiftTimeline(input.startTime, input.endTime, nowMs: input.nowMs, options: .init(input))
            .segments.count > 1
    }

    /// Reminders for the current shift and the one after it, sorted by time.
    /// Each id is prefixed `current:<end>:` or `next:<end>:`, so a caller can
    /// take one shift's list and ids stay stable across rebuilds.
    static func reminders(input: NativeRulesInput, reminderInputs: NativeReminderInputs) -> [NativeReminder] {
        let zone = CivilZone(identifier: input.timeZoneIdentifier, extended: ExtendedScheduleResolver(plan: input.extendedSchedule))
        let shift = resolveCurrentShift(input, zone)
        func project(_ timeline: ShiftTimeline, _ scope: String) -> [NativeReminder] {
            let prefix = "\(scope):\(JavaScriptNumber.string(timeline.endAtMs)):"
            return ReminderRules.buildShiftReminders(timeline, reminderInputs).map { $0.withID(prefix + $0.id) }
        }
        let next = nextShift(after: shift, input, zone).map { project($0, "next") } ?? []
        return ReminderRules.sortedByTime(project(shift, "current") + next)
    }

    /// Whether a Save should ask about today: whenever today's shift under the
    /// current or the edited settings is a scheduled one. A settled shift is
    /// still today's Records row, and even a finished lunch changes how that
    /// row splits, so neither the clock nor the kind of edit narrows it.
    static func shouldPromptApplyToday(current: NativeRulesInput, candidate: NativeRulesInput) -> Bool {
        [current, candidate].contains { input in
            let zone = CivilZone(identifier: input.timeZoneIdentifier, extended: ExtendedScheduleResolver(plan: input.extendedSchedule))
            return zone.isScheduledWorkday(resolveCurrentShift(input, zone).startAtMs, input.workdays, input.schedule)
        }
    }

    // MARK: - Glue that used to live in the JavaScriptCore bundle

    private static func resolveCurrentShift(_ input: NativeRulesInput, _ zone: CivilZone) -> ShiftTimeline {
        let options = ShiftOptions(input)
        let live = zone.shiftTimeline(input.startTime, input.endTime, nowMs: input.nowMs, options: options)
        let ended = zone.endedShiftOnEndCalendarDay(
            input.startTime, input.endTime,
            nowMs: input.nowMs,
            input.workdays, input.schedule,
            options: options,
            forcedWorkdayStartMs: input.forcedWorkdayStartMs == 0 ? nil : input.forcedWorkdayStartMs
        )
        // Settlement of last night's overnight only applies until tonight's
        // window actually starts. A rest-day 22:00–06:00 on Saturday would
        // otherwise stay pinned to Friday's 06:00 end all evening.
        let liveIsOpen = input.nowMs >= live.startAtMs && input.nowMs < live.endAtMs
        if let ended, ended.startAtMs != live.startAtMs, !liveIsOpen {
            return ended
        }
        return live
    }

    private static func nextShift(after shift: ShiftTimeline, _ input: NativeRulesInput, _ zone: CivilZone) -> ShiftTimeline? {
        zone.nextShiftTimeline(
            input.startTime, input.endTime, input.workdays, input.schedule,
            afterMs: max(input.nowMs, shift.endAtMs),
            options: ShiftOptions(input).withoutOvertime
        )
    }

    private static func isActualShift(_ shift: ShiftTimeline, _ input: NativeRulesInput, _ zone: CivilZone) -> Bool {
        if zone.isScheduledWorkday(shift.startAtMs, input.workdays, input.schedule) { return true }
        guard let forced = input.forcedWorkdayStartMs else { return false }
        return zone.startOfCivilDayMs(shift.startAtMs) == zone.startOfCivilDayMs(forced)
    }

    /// The rest-day ring starts after the previous shift's settlement day and
    /// advances monotonically across the rest interval.
    private static func countdownAnchorAtMs(_ input: NativeRulesInput, targetAtMs: Double, _ zone: CivilZone) -> Double {
        let targetDayMs = zone.startOfCivilDayMs(targetAtMs)
        let options = ShiftOptions(input).withoutOvertime
        for offset in 1...366 {
            // Probe from the middle of the candidate day: from civil midnight an
            // overnight 22:00–06:00 resolves to the previous day's shift.
            let probeMs = zone.addCivilDaysMs(targetDayMs, -offset) + 12 * 3_600_000
            let previous = zone.shiftTimeline(input.startTime, input.endTime, nowMs: probeMs, options: options)
            guard zone.isScheduledWorkday(previous.startAtMs, input.workdays, input.schedule) else { continue }
            let anchorMs = zone.addCivilDaysMs(zone.startOfCivilDayMs(previous.endAtMs), 1)
            if anchorMs < targetAtMs { return anchorMs }
        }
        return targetDayMs
    }

    private static func countdownProjection(
        _ input: NativeRulesInput,
        shift: ShiftTimeline,
        nextShift: ShiftTimeline?,
        _ zone: CivilZone
    ) -> (targetAtMs: Double?, anchorAtMs: Double?, progress: Double) {
        let targetAtMs = input.nowMs < shift.startAtMs && isActualShift(shift, input, zone)
            ? shift.startAtMs
            : nextShift?.startAtMs
        guard let targetAtMs, targetAtMs > input.nowMs else { return (nil, nil, 0) }

        let targetDayAtMs = zone.startOfCivilDayMs(targetAtMs)
        let isTargetWorkday = input.nowMs >= targetDayAtMs
        let anchorAtMs = isTargetWorkday ? targetDayAtMs : countdownAnchorAtMs(input, targetAtMs: targetAtMs, zone)
        let progressEndAtMs = isTargetWorkday ? targetAtMs : targetDayAtMs
        let durationMs = progressEndAtMs - anchorAtMs
        let progress = durationMs > 0
            ? max(0, min(100, (input.nowMs - anchorAtMs) / durationMs * 100))
            : 0
        return (targetAtMs, anchorAtMs, progress)
    }

    private static func watchShift(
        _ shift: ShiftTimeline,
        isRunning: Bool,
        finishedAtMs: Double?
    ) -> NativeWatchRulesProjection.Shift {
        let segments = shift.segments
        var transitions: [NativeWatchRulesProjection.Transition] = []
        for (index, segment) in segments.enumerated() {
            transitions.append(.init(
                atMs: segment.startAtMs,
                state: shift.overtimeEndAtMs != nil && segment.startAtMs >= shift.plannedEndAtMs ? "overtime" : "working"
            ))
            if index < segments.count - 1, shift.activeBreakEndAtMs(at: segment.endAtMs) != nil {
                transitions.append(.init(atMs: segment.endAtMs, state: "lunch"))
            }
        }
        if let finishedAtMs {
            transitions.append(.init(atMs: finishedAtMs, state: "finished"))
        } else {
            if shift.overtimeEndAtMs != nil {
                transitions.append(.init(atMs: shift.plannedEndAtMs, state: "overtime"))
            }
            transitions.append(.init(atMs: shift.endAtMs, state: "finished"))
        }
        // Stable, as `Array.prototype.sort` is: equal instants keep insertion
        // order, and the last of them is the one that survives below.
        let sorted = transitions.enumerated()
            .sorted { $0.element.atMs != $1.element.atMs ? $0.element.atMs < $1.element.atMs : $0.offset < $1.offset }
            .map(\.element)
        let visible = finishedAtMs.map { finished in sorted.filter { $0.atMs <= finished } } ?? sorted
        let deduplicated = visible.indices
            .filter { $0 == visible.count - 1 || visible[$0].atMs != visible[$0 + 1].atMs }
            .map { visible[$0] }
        return .init(
            segments: segments,
            plannedEndAtMs: shift.plannedEndAtMs,
            overtimeEndAtMs: shift.overtimeEndAtMs,
            finishedAtMs: finishedAtMs,
            isRunning: isRunning,
            transitions: deduplicated
        )
    }
}

/// Daily pay from the salary settings (`getDailySalary` in `lib/countdown.ts`).
nonisolated enum SalaryRules {
    static func dailySalary(
        amount: String,
        type: String,
        monthlyWorkingDays: Double,
        annualBonusMonths: Double
    ) -> Double? {
        guard !JavaScriptNumber.trim(amount).isEmpty else { return nil }
        let parsed = JavaScriptNumber.parse(amount)
        guard parsed.isFinite, parsed >= 0 else { return nil }
        guard annualBonusMonths.isFinite, annualBonusMonths >= 0 else { return nil }
        let multiplier = 1 + annualBonusMonths / 12
        if type == "daily" { return parsed * multiplier }
        guard monthlyWorkingDays.isFinite, monthlyWorkingDays > 0, monthlyWorkingDays <= 31 else { return nil }
        return (parsed / monthlyWorkingDays) * multiplier
    }
}

/// `Number(string)` as ECMAScript defines it, for the salary field. Swift's
/// `Double(_:)` differs in both directions: it rejects surrounding whitespace
/// and `0b`/`0o` literals, and accepts `nan`, `inf` and hexadecimal floats.
nonisolated enum JavaScriptNumber {
    private static let whitespace = CharacterSet.whitespaces
        .union(CharacterSet(charactersIn: "\n\r\u{0B}\u{0C}\u{2028}\u{2029}\u{FEFF}"))

    static func trim(_ value: String) -> String {
        value.trimmingCharacters(in: whitespace)
    }

    static func parse(_ value: String) -> Double {
        let text = trim(value)
        if text.isEmpty { return 0 }
        for (prefix, radix) in [("0x", 16), ("0o", 8), ("0b", 2)] where text.lowercased().hasPrefix(prefix) {
            let digits = text.dropFirst(2)
            guard !digits.isEmpty else { return .nan }
            var result = 0.0
            for character in digits {
                guard let digit = character.hexDigitValue, digit < radix else { return .nan }
                result = result * Double(radix) + Double(digit)
            }
            return result
        }
        var body = Substring(text)
        var sign = 1.0
        if let first = body.first, first == "+" || first == "-" {
            sign = first == "-" ? -1 : 1
            body = body.dropFirst()
        }
        if body == "Infinity" { return sign * .infinity }
        guard body.wholeMatch(of: /(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?/) != nil else { return .nan }
        var normalized = String(body)
        if normalized.hasPrefix(".") { normalized = "0" + normalized }
        if let exponent = normalized.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            if normalized[normalized.index(before: exponent)] == "." {
                normalized.insert("0", at: exponent)
            }
        } else if normalized.hasSuffix(".") {
            normalized += "0"
        }
        return Double(normalized).map { sign * $0 } ?? .nan
    }
}

// MARK: - Shift timeline

nonisolated struct ShiftOptions: Sendable {
    var breakStartTime: String?
    var breakDurationMinutes: Int
    var overtimeEndAtMs: Double?

    init(breakStartTime: String?, breakDurationMinutes: Int, overtimeEndAtMs: Double? = nil) {
        self.breakStartTime = breakStartTime?.isEmpty == false ? breakStartTime : nil
        self.breakDurationMinutes = breakDurationMinutes
        self.overtimeEndAtMs = overtimeEndAtMs
    }

    init(_ input: NativeRulesInput) {
        breakStartTime = input.breakStartTime?.isEmpty == false ? input.breakStartTime : nil
        breakDurationMinutes = input.breakDurationMinutes
        overtimeEndAtMs = input.overtimeEndAtMs == 0 ? nil : input.overtimeEndAtMs
    }

    var withoutOvertime: ShiftOptions {
        var copy = self
        copy.overtimeEndAtMs = nil
        return copy
    }
}

/// `ShiftTimeline` from `lib/countdown.ts`: effective segments, the planned
/// end, and overtime extending the last segment.
nonisolated struct ShiftTimeline: Equatable, Sendable {
    var segments: [NativeShiftSegment]
    var plannedEndAtMs: Double
    var overtimeEndAtMs: Double?

    var startAtMs: Double { segments.first?.startAtMs ?? 0 }
    var endAtMs: Double { overtimeEndAtMs ?? plannedEndAtMs }

    /// Rejects a malformed timeline rather than repairing it.
    var isValid: Bool {
        guard let last = segments.last, plannedEndAtMs.isFinite else { return false }
        if let overtimeEndAtMs, !overtimeEndAtMs.isFinite || overtimeEndAtMs <= plannedEndAtMs { return false }
        var previousEnd = -Double.infinity
        for segment in segments {
            guard segment.startAtMs.isFinite, segment.endAtMs.isFinite,
                  segment.endAtMs > segment.startAtMs, segment.startAtMs >= previousEnd
            else { return false }
            previousEnd = segment.endAtMs
        }
        return plannedEndAtMs > startAtMs
            && plannedEndAtMs > last.startAtMs
            && plannedEndAtMs <= last.endAtMs
            && endAtMs == last.endAtMs
    }

    var durationMs: Double {
        guard isValid else { return 0 }
        return segments.reduce(0) { $0 + $1.endAtMs - $1.startAtMs }
    }

    var plannedDurationMs: Double {
        guard isValid else { return 0 }
        return segments.reduce(0) { $0 + max(0, min($1.endAtMs, plannedEndAtMs) - $1.startAtMs) }
    }

    func elapsedMs(at nowMs: Double) -> Double {
        guard isValid else { return 0 }
        return segments.reduce(0) { $0 + min($1.endAtMs - $1.startAtMs, max(0, nowMs - $1.startAtMs)) }
    }

    func remainingMs(at nowMs: Double) -> Double {
        max(0, durationMs - elapsedMs(at: nowMs))
    }

    func progress(at nowMs: Double) -> Double {
        let duration = durationMs
        guard duration > 0 else { return 0 }
        return max(0, min(100, (elapsedMs(at: nowMs) / duration) * 100))
    }

    /// Linear pay ratio: 1 at the planned end, above 1 in overtime.
    func payRatio(at nowMs: Double) -> Double {
        let planned = plannedDurationMs
        guard planned > 0 else { return 0 }
        return max(0, elapsedMs(at: nowMs) / planned)
    }

    /// The end of the gap between segments that `nowMs` falls in, if any.
    func activeBreakEndAtMs(at nowMs: Double) -> Double? {
        guard segments.count > 1 else { return nil }
        for index in 0..<(segments.count - 1) {
            let gapStart = segments[index].endAtMs
            let gapEnd = segments[index + 1].startAtMs
            if gapEnd > gapStart, nowMs >= gapStart, nowMs < gapEnd { return gapEnd }
        }
        return nil
    }
}

/// An `HH:mm` clock reading.
nonisolated struct Clock: Hashable, Sendable {
    let hour: Int
    let minute: Int

    init(_ text: String) {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        hour = parts.first.flatMap { Int($0) } ?? 0
        minute = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
    }

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    var minutes: Int { hour * 60 + minute }
}

// MARK: - Civil time

/// Civil-time arithmetic in one zone, matching `lib/countdown.ts`'s zoned
/// helpers minute for minute, including the DST policy: a clock reading in a
/// fold resolves to the earlier instant, one in a gap to the first minute
/// after it. One instance per rule call; it memoises civil conversions.
nonisolated final class CivilZone {
    struct Civil: Equatable {
        let dayNumber: Int
        let year: Int
        let month: Int
        let day: Int
        let hour: Int
        let minute: Int
        let second: Int
        var weekday: Int { ((dayNumber + 4) % 7 + 7) % 7 }
    }

    private struct Reading: Hashable {
        let dayNumber: Int
        let hour: Int
        let minute: Int
    }

    private static let dayMs = 86_400_000.0
    let timeZone: TimeZone
    private var readingCache: [Reading: Double] = [:]
    /// Plan 018 P8's per-day assignments. `nil` for every schedule that
    /// predates extended scheduling, and then every path below is exactly the
    /// one it took before.
    private let extended: ExtendedScheduleResolver?

    init(timeZone: TimeZone, extended: ExtendedScheduleResolver? = nil) {
        self.timeZone = timeZone
        self.extended = extended
    }

    convenience init(identifier: String?, extended: ExtendedScheduleResolver? = nil) {
        let trimmed = identifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.init(
            timeZone: trimmed.isEmpty ? .current : TimeZone(identifier: trimmed) ?? .current,
            extended: extended
        )
    }

    func civil(_ ms: Double) -> Civil {
        // A JavaScript Date truncates to whole milliseconds before formatting.
        let wholeMs = ms.rounded(.towardZero)
        let local = wholeMs + Double(timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: wholeMs / 1_000))) * 1_000
        return Self.utcCivil(local)
    }

    private static func utcCivil(_ ms: Double) -> Civil {
        let days = (ms / dayMs).rounded(.down)
        let msOfDay = Int(ms - days * dayMs)
        let dayNumber = Int(days)
        let (year, month, day) = civilDate(dayNumber: dayNumber)
        return Civil(
            dayNumber: dayNumber, year: year, month: month, day: day,
            hour: msOfDay / 3_600_000, minute: msOfDay / 60_000 % 60, second: msOfDay / 1_000 % 60
        )
    }

    /// The instant a civil reading names in this zone (`zonedTimeToUtcMs`).
    func utcMs(dayNumber: Int, _ clock: Clock) -> Double {
        let reading = Reading(dayNumber: dayNumber, hour: clock.hour, minute: clock.minute)
        if let cached = readingCache[reading] { return cached }
        let civilMs = Double(dayNumber) * Self.dayMs + Double(clock.hour) * 3_600_000 + Double(clock.minute) * 60_000
        var offsets: [Double] = []
        for hours in [0.0, -6, 6, -24, 24, -48, 48] {
            let offset = offsetMs(civilMs + hours * 3_600_000)
            if !offsets.contains(offset) { offsets.append(offset) }
        }
        func exact(_ baseMs: Double, matching target: Civil) -> Double? {
            offsets.map { baseMs - $0 }.filter {
                let actual = civil($0)
                return actual.dayNumber == target.dayNumber && actual.hour == target.hour && actual.minute == target.minute
            }.min()
        }
        // The reading as the caller spelled it. An hour past 23 never matches,
        // exactly as in the TypeScript, and falls through to the gap walk.
        let target = Civil(dayNumber: dayNumber, year: 0, month: 0, day: 0, hour: clock.hour, minute: clock.minute, second: 0)
        var resolved = exact(civilMs, matching: target)
        if resolved == nil {
            for delta in 1...(24 * 60) {
                let nextMs = civilMs + Double(delta) * 60_000
                if let candidate = exact(nextMs, matching: Self.utcCivil(nextMs)) {
                    resolved = candidate
                    break
                }
            }
        }
        let result = resolved ?? civilMs
        readingCache[reading] = result
        return result
    }

    private func offsetMs(_ instantMs: Double) -> Double {
        let reading = civil(instantMs)
        let civilMs = Double(reading.dayNumber) * Self.dayMs
            + Double(reading.hour) * 3_600_000 + Double(reading.minute) * 60_000 + Double(reading.second) * 1_000
        return civilMs - instantMs
    }

    func startOfCivilDayMs(_ ms: Double) -> Double {
        utcMs(dayNumber: civil(ms).dayNumber, Clock(hour: 0, minute: 0))
    }

    /// Same wall-clock minute `days` civil days later; seconds are dropped.
    func addCivilDaysMs(_ ms: Double, _ days: Int) -> Double {
        let reading = civil(ms)
        return utcMs(dayNumber: reading.dayNumber + days, Clock(hour: reading.hour, minute: reading.minute))
    }

    func dayKey(_ ms: Double) -> String {
        let reading = civil(ms)
        func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        return "\(reading.year)-\(pad(reading.month))-\(pad(reading.day))"
    }

    /// Civil midnight on the Monday of the week containing `ms` (`zonedWeekStartMs`).
    func weekStartMs(_ ms: Double) -> Double {
        let reading = civil(ms)
        return utcMs(dayNumber: reading.dayNumber - (reading.weekday + 6) % 7, Clock(hour: 0, minute: 0))
    }

    private func dayDifference(_ fromMs: Double, _ toMs: Double) -> Int {
        civil(toMs).dayNumber - civil(fromMs).dayNumber
    }

    // MARK: Extended scheduling (plan 018 P8)

    /// The clocks one civil day works: the extended schedule's, when it assigns
    /// a shift to that day, otherwise the fixed pair the caller passed. A rest
    /// or unassigned day keeps the caller's hours, exactly as a classic rest
    /// day does, so a makeup day still has a shape to reuse.
    func dayClocks(dayNumber: Int, _ startTime: String, _ endTime: String) -> (start: Clock, end: Clock) {
        guard let hours = extended?.day(dayNumber: dayNumber).hours else {
            return (Clock(startTime), Clock(endTime))
        }
        return (Clock(hours.startTime), Clock(hours.endTime))
    }

    /// The same for the in-shift break, which belongs to the day's shift type.
    func dayBreak(
        dayNumber: Int,
        _ breakStartTime: String?,
        _ breakDurationMinutes: Int
    ) -> (startTime: String?, durationMinutes: Int) {
        guard let hours = extended?.day(dayNumber: dayNumber).hours else {
            return (breakStartTime, breakDurationMinutes)
        }
        return (hours.breakStartTime, hours.breakDurationMinutes)
    }

    /// `options` carrying the break of the day the shift starts on.
    func dayOptions(startingAtMs: Double, _ options: ShiftOptions) -> ShiftOptions {
        guard let hours = extended?.day(dayNumber: civil(startingAtMs).dayNumber).hours else { return options }
        var copy = options
        copy.breakStartTime = hours.breakStartTime
        copy.breakDurationMinutes = hours.breakDurationMinutes
        return copy
    }

    /// The effective hours one civil day is scheduled to work under an extended
    /// schedule, break already taken out. `nil` when no extended schedule
    /// assigns that day work, which leaves the caller on its own figure.
    ///
    /// It runs the same `timeline` the countdown runs on rather than measuring
    /// the day a second way: a summary that computed its own durations is how
    /// the "This week" row once shipped a number Records disagreed with.
    func plannedHours(dayNumber: Int) -> Double? {
        guard let hours = extended?.day(dayNumber: dayNumber).hours else { return nil }
        let noonMs = utcMs(dayNumber: dayNumber, Clock(hour: 12, minute: 0))
        let bounds = shiftBounds(hours.startTime, hours.endTime, nowMs: noonMs)
        guard bounds.end > bounds.start else { return 0 }
        let options = dayOptions(
            startingAtMs: bounds.start,
            ShiftOptions(breakStartTime: nil, breakDurationMinutes: 0)
        )
        return timeline(start: bounds.start, end: bounds.end, options: options).plannedDurationMs / 3_600_000
    }

    /// One day's bounds, when that day's assignment crosses midnight.
    private func overnightBounds(dayNumber: Int, _ startTime: String, _ endTime: String) -> (start: Double, end: Double)? {
        let clocks = dayClocks(dayNumber: dayNumber, startTime, endTime)
        guard clocks.end.minutes <= clocks.start.minutes else { return nil }
        let startAtMs = utcMs(dayNumber: dayNumber, clocks.start)
        let endAtMs = utcMs(dayNumber: dayNumber + 1, clocks.end)
        guard endAtMs > startAtMs else { return nil }
        return (startAtMs, endAtMs)
    }

    // MARK: Work patterns

    /// Manual (`off`) mode has no rest pattern, so every shift counts. An
    /// extended schedule answers for itself: it assigns rest days as a shift
    /// type, so the weekday patterns below never run.
    func isScheduledWorkday(_ shiftStartMs: Double, _ workdays: [Int], _ schedule: NativeWorkSchedule) -> Bool {
        if let day = extended?.assignedDay(dayNumber: civil(shiftStartMs).dayNumber) { return day.isWorkday }
        return schedule.mode == "off" || isScheduledWorkdayInZone(shiftStartMs, workdays, schedule)
    }

    /// As `isScheduledWorkday`, except manual days are rest: range expansion
    /// must not paint a seven-day week for a user who starts shifts by hand.
    func isScheduledWorkdayInZone(_ shiftStartMs: Double, _ workdays: [Int], _ schedule: NativeWorkSchedule) -> Bool {
        if let day = extended?.assignedDay(dayNumber: civil(shiftStartMs).dayNumber) { return day.isWorkday }
        if schedule.mode == "off" { return false }
        let weekday = civil(shiftStartMs).weekday
        if schedule.mode == "classic" { return workdays.contains(weekday) }

        if schedule.mode == "alternating" {
            if (1...5).contains(weekday) { return true }
            let anchor = weekStartMs(schedule.referenceWeekStartMs ?? shiftStartMs)
            let week = weekStartMs(shiftStartMs)
            let weeksFromAnchor = Int((Double(dayDifference(anchor, week)) / 7).rounded(.down))
            let anchorIsSingle = schedule.referenceWeekType == "single"
            let isSingleWeek = abs(weeksFromAnchor) % 2 == 0 ? anchorIsSingle : !anchorIsSingle
            return isSingleWeek && weekday == (schedule.singleWeekendWorkday ?? 6)
        }

        let workLength = max(1, schedule.rotationWorkDays ?? 1)
        let restLength = max(1, schedule.rotationRestDays ?? 1)
        let offset = dayDifference(schedule.rotationAnchorMs ?? shiftStartMs, shiftStartMs)
        let cycleLength = workLength + restLength
        return ((offset % cycleLength) + cycleLength) % cycleLength < workLength
    }

    func nextRestDayStartMs(afterMs: Double, _ workdays: [Int], _ schedule: NativeWorkSchedule) -> Double? {
        if extended == nil, schedule.mode == "off" { return nil }
        let first = civil(afterMs).dayNumber
        for offset in 0...366 {
            let dayStartMs = utcMs(dayNumber: first + offset, Clock(hour: 0, minute: 0))
            if !isScheduledWorkdayInZone(dayStartMs, workdays, schedule) { return dayStartMs }
        }
        return nil
    }

    // MARK: Shifts

    /// The concrete window of the shift containing or nearest `nowMs`. An
    /// overnight shift after midnight still belongs to the previous evening.
    func shiftBounds(_ startTime: String, _ endTime: String, nowMs: Double) -> (start: Double, end: Double) {
        let today = civil(nowMs).dayNumber
        // With one fixed pair of clocks, a still-running overnight shift is
        // always found by walking today's own bounds back a day. Per-day
        // assignments break that: last night can be a night shift while today
        // is an ordinary day shift, and today's bounds would never look back.
        if extended != nil,
           let overnight = overnightBounds(dayNumber: today - 1, startTime, endTime),
           nowMs >= overnight.start, nowMs < overnight.end {
            return overnight
        }
        let todayClocks = dayClocks(dayNumber: today, startTime, endTime)
        let start = todayClocks.start
        let end = todayClocks.end
        var startAtMs = utcMs(dayNumber: today, start)
        var endAtMs = utcMs(dayNumber: today, end)
        if endAtMs <= startAtMs {
            // A spring-forward gap can legalise two same-day clocks onto one
            // instant. That is not an overnight shift.
            if end.minutes > start.minutes { return (startAtMs, startAtMs) }
            if nowMs < endAtMs {
                // Last night's shift is still running, so both of its ends
                // belong to yesterday's assignment.
                let yesterdayClocks = dayClocks(dayNumber: today - 1, startTime, endTime)
                startAtMs = utcMs(dayNumber: today - 1, yesterdayClocks.start)
                endAtMs = utcMs(dayNumber: today, yesterdayClocks.end)
            } else {
                endAtMs = utcMs(dayNumber: today + 1, end)
            }
        }
        return (startAtMs, endAtMs)
    }

    func shiftTimeline(_ startTime: String, _ endTime: String, nowMs: Double, options: ShiftOptions) -> ShiftTimeline {
        let bounds = shiftBounds(startTime, endTime, nowMs: nowMs)
        return timeline(start: bounds.start, end: bounds.end, options: dayOptions(startingAtMs: bounds.start, options))
    }

    func timeline(start: Double, end plannedEndAtMs: Double, options: ShiftOptions) -> ShiftTimeline {
        var segments = [NativeShiftSegment(startAtMs: start, endAtMs: plannedEndAtMs)]
        let breakDurationMs = Double(options.breakDurationMinutes) * 60_000
        if let breakStartTime = options.breakStartTime, breakDurationMs > 0 {
            let clock = Clock(breakStartTime)
            let startDay = civil(start).dayNumber
            var breakStartAtMs = utcMs(dayNumber: startDay, clock)
            if breakStartAtMs < start {
                breakStartAtMs = utcMs(dayNumber: startDay + 1, clock)
            }
            let breakEndAtMs = breakStartAtMs + breakDurationMs
            if breakStartAtMs > start, breakEndAtMs < plannedEndAtMs {
                segments = [
                    NativeShiftSegment(startAtMs: start, endAtMs: breakStartAtMs),
                    NativeShiftSegment(startAtMs: breakEndAtMs, endAtMs: plannedEndAtMs),
                ]
            }
        }
        let overtimeEndAtMs = options.overtimeEndAtMs.flatMap { $0 > plannedEndAtMs ? $0 : nil }
        if let overtimeEndAtMs, let last = segments.last {
            segments[segments.count - 1] = NativeShiftSegment(startAtMs: last.startAtMs, endAtMs: overtimeEndAtMs)
        }
        return ShiftTimeline(segments: segments, plannedEndAtMs: plannedEndAtMs, overtimeEndAtMs: overtimeEndAtMs)
    }

    /// The shift that still belongs on `nowMs`'s civil day after the live
    /// bounds have jumped: a day shift whose overtime crossed midnight, or an
    /// overnight shift after its planned end. Checks today and the two days
    /// before, using each candidate's effective end.
    func endedShiftOnEndCalendarDay(
        _ startTime: String,
        _ endTime: String,
        nowMs: Double,
        _ workdays: [Int],
        _ schedule: NativeWorkSchedule,
        options: ShiftOptions,
        forcedWorkdayStartMs: Double?
    ) -> ShiftTimeline? {
        let todayMs = startOfCivilDayMs(nowMs)
        let forcedDayMs = forcedWorkdayStartMs.flatMap { $0.isFinite ? startOfCivilDayMs($0) : nil }
        for offset in 0...2 {
            let dayNumber = civil(addCivilDaysMs(todayMs, -offset)).dayNumber
            let bounds = shiftBounds(startTime, endTime, nowMs: utcMs(dayNumber: dayNumber, Clock(hour: 12, minute: 0)))
            guard bounds.end > bounds.start else { continue }
            guard isScheduledWorkday(bounds.start, workdays, schedule)
                    || forcedDayMs.map({ startOfCivilDayMs(bounds.start) == $0 }) == true
            else { continue }
            let shift = timeline(start: bounds.start, end: bounds.end, options: dayOptions(startingAtMs: bounds.start, options))
            if nowMs >= shift.startAtMs, nowMs < shift.endAtMs { return shift }
            if nowMs >= shift.endAtMs, startOfCivilDayMs(shift.endAtMs) == todayMs { return shift }
        }
        return nil
    }

    func nextShiftTimeline(
        _ startTime: String,
        _ endTime: String,
        _ workdays: [Int],
        _ schedule: NativeWorkSchedule,
        afterMs: Double,
        options: ShiftOptions
    ) -> ShiftTimeline? {
        if extended == nil {
            if schedule.mode == "off" { return nil }
            if schedule.mode == "classic", workdays.isEmpty { return nil }
        }
        let cursorMs = startOfCivilDayMs(afterMs)
        for offset in 0...366 {
            let dayNumber = civil(addCivilDaysMs(cursorMs, offset)).dayNumber
            let bounds = shiftBounds(startTime, endTime, nowMs: utcMs(dayNumber: dayNumber, Clock(hour: 12, minute: 0)))
            guard isScheduledWorkdayInZone(bounds.start, workdays, schedule), bounds.start > afterMs else { continue }
            return timeline(start: bounds.start, end: bounds.end, options: dayOptions(startingAtMs: bounds.start, options))
        }
        return nil
    }

    // MARK: Proleptic Gregorian day numbers (days since 1970-01-01)

    static func dayNumber(year: Int, month: Int, day: Int) -> Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    static func civilDate(dayNumber: Int) -> (year: Int, month: Int, day: Int) {
        let shifted = dayNumber + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        return (yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }
}
