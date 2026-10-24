import Foundation

/// Durable, salary-free scheduling inputs. Unlike a V1 snapshot, these rules do
/// not expire at the next clock-in. Both watch surfaces run the iPhone's core.
nonisolated struct WatchScheduleV2: Codable, Equatable, Sendable {
    let configuration: ScheduleRuleInput
    let automaticallyRuns: Bool
    let isConfigured: Bool
    let currentShift: WatchShiftProjectionV1?
    let currentUntilMs: Int64
    var resumeAtMs: Int64? = nil
    let presentation: WatchPresentationV1

    /// Adopted leave (plan 020). Older Watch builds would ignore it and count
    /// down to a shift the user has taken off, so it needs schedule schema 6.
    var usesLeave: Bool {
        configuration.extendedSchedule.map { !$0.leaveDays.isEmpty || $0.baseHours != nil } ?? false
    }

    var usesAnnualDateRanges: Bool {
        configuration.extendedSchedule?.shiftTypes.contains {
            $0.kind == .work && !$0.isArchived && $0.annualDateRange != nil
        } ?? false
    }

    init(configuration: ScheduleRuleInput, automaticallyRuns: Bool, isConfigured: Bool,
         currentShift: WatchShiftProjectionV1?, currentUntilMs: Int64,
         resumeAtMs: Int64? = nil, presentation: WatchPresentationV1) {
        self.configuration = configuration
        self.automaticallyRuns = automaticallyRuns
        self.isConfigured = isConfigured
        self.currentShift = currentShift
        self.currentUntilMs = currentUntilMs
        self.resumeAtMs = resumeAtMs
        self.presentation = presentation
    }

    var isValid: Bool {
        let input = configuration
        guard input.nowMs == 0, input.overtimeEndAtMs == nil, input.forcedWorkdayStartMs == nil,
              let identifier = input.timeZoneIdentifier, TimeZone(identifier: identifier) != nil,
              ["classic", "alternating", "rotation", "off"].contains(input.schedule.mode),
              input.workdays.allSatisfy({ (0...6).contains($0) }), input.workdays.count <= 7,
              validClock(input.startTime), validClock(input.endTime),
              input.breakStartTime.map(validClock) ?? true,
              (0..<1_440).contains(input.breakDurationMinutes),
              [input.schedule.referenceWeekStartMs, input.schedule.rotationAnchorMs].allSatisfy({
                  $0.map { $0.isFinite && $0 >= 0 && $0 <= Double(WatchSnapshotContract.maximumJSONTimestamp) } ?? true
              }),
              input.schedule.rotationWorkDays.map({ (1...366).contains($0) }) ?? true,
              input.schedule.rotationRestDays.map({ (0...366).contains($0) }) ?? true,
              currentUntilMs >= 0, currentUntilMs <= WatchSnapshotContract.maximumJSONTimestamp
        else { return false }
        guard resumeAtMs.map({ $0 >= currentUntilMs && $0 <= WatchSnapshotContract.maximumJSONTimestamp }) ?? true,
              currentShift != nil || resumeAtMs == nil else { return false }
        if let plan = input.extendedSchedule {
            let content = ExtendedScheduleContent(shiftTypes: plan.shiftTypes, rule: plan.rule, holidayRegionIdentifier: plan.holidayRegionIdentifier, clearedFromDayKey: plan.clearedFromDayKey)
            guard content.isValid(in: TimeZone(identifier: identifier)!), plan.pinnedDayKey == nil,
                  plan.holidayRegionIdentifier?.isEmpty != false || plan.holidayOverrides != nil,
                  plan.holidayOverrides.map({ values in
                      values.count <= 20_000 && values.keys.allSatisfy(HolidayCalendar.isValidDateCode)
                  }) ?? true,
                  plan.frozenShiftTypes.allSatisfy({ key, type in
                      ExtendedScheduleResolver.parse(dayKey: key) != nil && type.isValid
                          && plan.handSetDays[key] == type.id
                  }),
                  plan.handSetDays.allSatisfy({ key, id in
                      ExtendedScheduleResolver.parse(dayKey: key) != nil
                          && (plan.shiftTypes.contains { $0.id == id } || plan.frozenShiftTypes[key]?.id == id)
                  }),
                  plan.leaveDays.count <= 2_000,
                  plan.leaveDays.keys.allSatisfy({ ExtendedScheduleResolver.parse(dayKey: $0) != nil }),
                  plan.baseHours.map({ hours in
                      validClock(hours.startTime) && validClock(hours.endTime)
                          && (hours.breakStartTime.map(validClock) ?? true)
                          && (0..<1_440).contains(hours.breakDurationMinutes)
                  }) ?? true else { return false }
        }
        if let currentShift {
            guard WatchShiftEvaluator.evaluate(currentShift, nowMs: 0) != nil,
                  currentUntilMs >= (currentShift.overtimeEndAtMs ?? currentShift.plannedEndAtMs)
            else { return false }
        }
        return true
    }

    private func validClock(_ value: String) -> Bool {
        guard value.wholeMatch(of: /[0-9]{2}:[0-9]{2}/) != nil else { return false }
        let parts = value.split(separator: ":").compactMap { Int($0) }
        return parts.count == 2 && (0..<24).contains(parts[0]) && (0..<60).contains(parts[1])
    }

    func content(at nowMs: Int64) -> WatchShiftContentV1 {
        var input = configuration
        input.nowMs = Double(nowMs)
        let projected = ShiftRuleCore.watchProjection(
            input: input, scheduleConfigured: isConfigured, isRunning: automaticallyRuns
        )
        let usesCurrent = currentShift != nil && nowMs < currentUntilMs
        let waitsForResume = resumeAtMs.map { currentShift != nil && nowMs >= currentUntilMs && nowMs < $0 } ?? false
        let shift = usesCurrent ? currentShift : (automaticallyRuns && !waitsForResume ? projected.shift.map(Self.shift) : nil)
        let projectedNext = projected.nextShift.map {
            WatchNextShiftV1(startAtMs: Int64($0.startAtMs), validUntilMs: Int64($0.validUntilMs))
        }
        let resumeNext = resumeAtMs.flatMap { nowMs < $0 ? WatchNextShiftV1(startAtMs: $0, validUntilMs: $0) : nil }
        let next = automaticallyRuns ? resumeNext ?? projectedNext : nil
        return WatchShiftContentV1(
            scheduleState: !isConfigured ? .notConfigured : (automaticallyRuns || shift?.isRunning == true ? .scheduled : .stopped),
            shift: shift, nextShift: next, presentation: presentation
        )
    }

    static func shift(_ value: NativeWatchRulesProjection.Shift) -> WatchShiftProjectionV1 {
        .init(segments: value.segments.map { .init(startAtMs: Int64($0.startAtMs), endAtMs: Int64($0.endAtMs)) },
              plannedEndAtMs: Int64(value.plannedEndAtMs), overtimeEndAtMs: value.overtimeEndAtMs.map(Int64.init),
              finishedAtMs: value.finishedAtMs.map(Int64.init), isRunning: value.isRunning,
              transitions: value.transitions.compactMap { transition in
                  WatchStateTransitionV1.State(rawValue: transition.state).map {
                      .init(atMs: Int64(transition.atMs), state: $0)
                  }
              })
    }
}

/// The next shifts from the cached configuration, resolved by the shared rules.
nonisolated enum WatchScheduleOutlook {
    struct Shift: Equatable {
        let startMs: Int64
        let endMs: Int64
        let segments: [(Int64, Int64)]
        let dayNumber: Int
        let shiftName: String?

        static func == (lhs: Shift, rhs: Shift) -> Bool {
            lhs.startMs == rhs.startMs && lhs.endMs == rhs.endMs && lhs.dayNumber == rhs.dayNumber
        }

        var workMs: Int64 { segments.reduce(0) { $0 + max(0, $1.1 - $1.0) } }
        func remainingMs(at ms: Int64) -> Int64 { segments.reduce(0) { $0 + max(0, $1.1 - max($1.0, ms)) } }
    }

    static func shifts(_ input: ScheduleRuleInput, fromMs: Int64, throughMs: Int64, limit: Int = 20) -> [Shift] {
        var probe = input
        probe.nowMs = Double(fromMs)
        let resolver = ExtendedScheduleResolver(plan: probe.extendedSchedule)
        let zone = CivilZone(identifier: probe.timeZoneIdentifier, extended: resolver)
        var result: [Shift] = []
        var current = ShiftRuleCore.resolveCurrentShift(probe, zone)
        if ShiftRuleCore.isActualShift(current, probe, zone), current.endAtMs > Double(fromMs) {
            result.append(shift(current, zone: zone, input: probe, resolver: resolver))
        }
        while result.count < limit, let next = ShiftRuleCore.nextShift(after: current, probe, zone),
              next.startAtMs <= Double(throughMs) {
            if !result.contains(where: { $0.startMs == Int64(next.startAtMs) }) {
                result.append(shift(next, zone: zone, input: probe, resolver: resolver))
            }
            current = next
            probe.nowMs = next.endAtMs
        }
        return result
    }

    private static func shift(_ timeline: ShiftTimeline, zone: CivilZone, input: ScheduleRuleInput,
                              resolver: ExtendedScheduleResolver?) -> Shift {
        let day = zone.civil(timeline.startAtMs).dayNumber
        let name = input.extendedSchedule.flatMap { plan in
            resolver?.day(dayNumber: day).shiftTypeID.flatMap { id in plan.shiftTypes.first { $0.id == id }?.name }
        }
        return Shift(startMs: Int64(timeline.startAtMs), endMs: Int64(timeline.endAtMs),
                     segments: timeline.segments.map { (Int64($0.startAtMs), Int64($0.endAtMs)) },
                     dayNumber: day, shiftName: name)
    }

    static func zone(_ input: ScheduleRuleInput) -> CivilZone {
        CivilZone(identifier: input.timeZoneIdentifier, extended: ExtendedScheduleResolver(plan: input.extendedSchedule))
    }
}

nonisolated extension WatchScheduleOutlook {
    /// What "This week" draws. Fills and progress hold the last
    /// `WatchDisplayProjection.progressStepCount` step each shift reached, so
    /// they only change at the dates `timelineDates` lists.
    struct WeekFigures: Equatable {
        let isDone: Bool
        let remainingDays: Double
        let finishMs: Int64?
        let fills: [Double]
        let progress: Double
    }

    static func weekFigures(_ input: ScheduleRuleInput, nowMs: Int64) -> WeekFigures {
        let zone = Self.zone(input)
        let weekStart = Int64(zone.weekStartMs(Double(nowMs)))
        let weekEnd = Int64(zone.addCivilDaysMs(Double(weekStart), 7))
        let shifts = Self.shifts(input, fromMs: weekStart, throughMs: weekEnd - 1)
            .filter { $0.startMs >= weekStart && $0.startMs < weekEnd }
        let total = shifts.reduce(Int64(0)) { $0 + $1.workMs }
        let isDone = total > 0 && shifts.allSatisfy { $0.remainingMs(at: nowMs) == 0 }
        let fills = shifts.map { shift -> Double in
            guard shift.workMs > 0, nowMs > shift.startMs else { return 0 }
            let fill = 1 - Double(shift.remainingMs(at: nowMs)) / Double(shift.workMs)
            return WatchDisplayFormat.steppedProgress(fill * 100) / 100
        }
        let days = zip(shifts, fills).reduce(0.0) { $1.0.workMs > 0 ? $0 + 1 - $1.1 : $0 }
        let done = zip(shifts, fills).reduce(0.0) { $0 + Double($1.0.workMs) * $1.1 }
        let finish = shifts.last.map(\.endMs).flatMap { $0 > nowMs ? $0 : nil }
        return WeekFigures(isDone: isDone, remainingDays: days, finishMs: finish,
                           fills: fills, progress: total > 0 ? done / Double(total) : 0)
    }

    /// Dates at which a schedule complication can change: every segment edge
    /// (the shown shift, "coming up" and the weekend countdown move there),
    /// the moment a shift enters the two-day "coming up" window, civil
    /// midnights, and, for "This week", each progress step. Text that counts
    /// down is system timer text, so nothing is sampled per minute or quarter
    /// hour. WidgetKit renders every entry in every family ahead of time and
    /// these widgets share the countdown complication's CPU budget.
    static func timelineDates(_ schedule: WatchScheduleV2?, from now: Date, includesProgressSteps: Bool,
                              hours: Int64 = 36) -> [Date] {
        let nowMs = Int64((now.timeIntervalSince1970 * 1_000).rounded(.towardZero))
        var milliseconds: Set<Int64> = [nowMs]
        if let schedule, schedule.isConfigured {
            let input = schedule.configuration
            let end = nowMs + hours * 3_600_000
            let zone = Self.zone(input)
            var midnight = zone.addCivilDaysMs(zone.startOfCivilDayMs(Double(nowMs)), 1)
            while midnight <= Double(end) {
                milliseconds.insert(Int64(midnight))
                midnight = zone.addCivilDaysMs(midnight, 1)
            }
            for shift in shifts(input, fromMs: nowMs, throughMs: end + upcomingWindowMs) {
                milliseconds.insert(shift.startMs - upcomingWindowMs)
                milliseconds.formUnion(shift.segments.flatMap { [$0.0, $0.1] })
                if includesProgressSteps {
                    milliseconds.formUnion(WatchDisplayProjection.progressStepDates(segments: shift.segments))
                }
            }
            milliseconds = milliseconds.filter { $0 >= nowMs && $0 <= end }
        }
        return milliseconds.sorted().map { Date(timeIntervalSince1970: Double($0) / 1_000) }
    }

    /// How far ahead "coming up" looks for shifts.
    static let upcomingWindowMs: Int64 = 2 * 86_400_000
}
