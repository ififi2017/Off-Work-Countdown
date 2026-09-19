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
            let content = ExtendedScheduleContent(shiftTypes: plan.shiftTypes, rule: plan.rule)
            guard content.isValid(in: TimeZone(identifier: identifier)!), plan.pinnedDayKey == nil,
                  plan.frozenShiftTypes.allSatisfy({ key, type in
                      ExtendedScheduleResolver.parse(dayKey: key) != nil && type.isValid
                          && plan.handSetDays[key] == type.id
                  }),
                  plan.handSetDays.allSatisfy({ key, id in
                      ExtendedScheduleResolver.parse(dayKey: key) != nil
                          && (plan.shiftTypes.contains { $0.id == id } || plan.frozenShiftTypes[key]?.id == id)
                  }) else { return false }
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
