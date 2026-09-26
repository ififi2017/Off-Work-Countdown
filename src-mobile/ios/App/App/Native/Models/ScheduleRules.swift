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
    static func watchProjection(input: NativeRulesInput, scheduleConfigured: Bool, isRunning: Bool,
                                currentShift: NativeWatchCurrentShift? = nil, finishedAtMs: Double? = nil) -> NativeWatchRulesProjection {
        ShiftRuleCore.watchProjection(input: input.scheduleInput, scheduleConfigured: scheduleConfigured,
                                     isRunning: isRunning, currentShift: currentShift, finishedAtMs: finishedAtMs)
    }
    private static func resolveCurrentShift(_ input: NativeRulesInput, _ zone: CivilZone) -> ShiftTimeline {
        ShiftRuleCore.resolveCurrentShift(input.scheduleInput, zone)
    }
    private static func nextShift(after shift: ShiftTimeline, _ input: NativeRulesInput, _ zone: CivilZone) -> ShiftTimeline? {
        ShiftRuleCore.nextShift(after: shift, input.scheduleInput, zone)
    }
    private static func isActualShift(_ shift: ShiftTimeline, _ input: NativeRulesInput, _ zone: CivilZone) -> Bool {
        ShiftRuleCore.isActualShift(shift, input.scheduleInput, zone)
    }

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
            earnedSoFar: dailySalary.flatMap {
                let earned = max(0, payRatio) * $0
                return earned.isFinite ? earned : nil
            },
            nextShiftStartAtMs: nextShift?.startAtMs,
            nextShiftEndAtMs: nextShift?.endAtMs,
            countdownTargetAtMs: clockIn.targetAtMs,
            countdownAnchorAtMs: clockIn.anchorAtMs,
            countdownProgress: clockIn.progress
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
        if type == "daily" {
            let daily = parsed * multiplier
            return daily.isFinite ? daily : nil
        }
        guard monthlyWorkingDays.isFinite, monthlyWorkingDays > 0, monthlyWorkingDays <= 31 else { return nil }
        let daily = (parsed / monthlyWorkingDays) * multiplier
        return daily.isFinite ? daily : nil
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


nonisolated extension ShiftOptions {
    init(_ input: NativeRulesInput) { self.init(input.scheduleInput) }
}
