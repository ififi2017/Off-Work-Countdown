import Foundation

/// Plan 020 §2: where a few days of leave buy the longest break, over the
/// user's own final schedule.
///
/// This is iOS-only behaviour tested in Swift. It resolves no schedule of its
/// own: `LeavePlannerSchedule` hands it every civil day with the shift the
/// existing rules already produced — cycle rule, hand-set days, holidays and
/// makeup workdays included — so a weekend is rest only when the schedule
/// says so, and a holiday the user still works has to be taken as leave.
///
/// A full rest day is a civil day, midnight to midnight in the schedule's
/// zone, that no remaining work segment touches. An overnight shift from the
/// day before therefore costs the morning it runs into, and a day with half a
/// shift left is never counted as rest. Leave comes in whole shifts or halves,
/// split by effective working time with breaks left out, never at noon or by
/// an assumed eight-hour day.

/// Why part of a proposal is less than certain.
nonisolated enum LeavePlannerCaveat: Hashable, Sendable {
    /// The holiday region is on, but this build carries no data for `year`,
    /// so the day follows the ordinary schedule without predicted holidays.
    case holidaysNotIncluded(year: Int)
    /// This year's holidays and makeup days are explicitly marked predictions.
    case holidaysEstimated(year: Int)
    /// The roster repeats an earlier month the user filled in.
    case carriedOverRoster
    /// Nothing assigns the day, so it is taken as rest.
    case unassigned
}

/// One civil day, already resolved by the schedule rules.
nonisolated struct LeavePlannerDay: Equatable, Sendable {
    let dayNumber: Int
    let dayKey: String
    /// Civil midnight to the next civil midnight: 23 or 25 hours across DST.
    let startAtMs: Double
    let endAtMs: Double
    /// Effective work of the shift that starts on this day; empty on rest.
    let segments: [NativeShiftSegment]
    /// Rest because of a bundled public holiday rather than the roster.
    let isHoliday: Bool
    let caveats: Set<LeavePlannerCaveat>
}

/// A shift's two halves by effective working time. A 09:00–18:00 shift with
/// lunch at 12:00–13:00 splits at 14:00: 09:00–12:00 and 13:00–14:00 make
/// the first four hours.
nonisolated struct LeaveShiftHalves: Equatable, Sendable {
    let first: [NativeShiftSegment]
    let second: [NativeShiftSegment]
    // Reused across the many candidate windows in a rolling-year search.
    private let whole: [NativeShiftSegment]

    init(segments: [NativeShiftSegment]) {
        let ordered = segments.filter { $0.endAtMs > $0.startAtMs }.sorted { $0.startAtMs < $1.startAtMs }
        let total = ordered.reduce(0) { $0 + $1.endAtMs - $1.startAtMs }
        // Whole minutes, so both halves read as clock times.
        var firstRemaining = (total / 120_000).rounded(.down) * 60_000
        var first: [NativeShiftSegment] = []
        var second: [NativeShiftSegment] = []
        for segment in ordered {
            let length = segment.endAtMs - segment.startAtMs
            if firstRemaining >= length {
                first.append(segment)
                firstRemaining -= length
            } else if firstRemaining > 0 {
                let split = segment.startAtMs + firstRemaining
                first.append(NativeShiftSegment(startAtMs: segment.startAtMs, endAtMs: split))
                second.append(NativeShiftSegment(startAtMs: split, endAtMs: segment.endAtMs))
                firstRemaining = 0
            } else {
                second.append(segment)
            }
        }
        self.first = first
        self.second = second
        self.whole = first + second
    }

    func removed(_ portion: LeavePortion) -> [NativeShiftSegment] {
        switch portion {
        case .whole: whole
        case .firstHalf: first
        case .secondHalf: second
        }
    }

    /// What is still worked once `portion` is taken; everything when `nil`.
    func remaining(after portion: LeavePortion?) -> [NativeShiftSegment] {
        switch portion {
        case nil: whole
        case .whole: []
        case .firstHalf: second
        case .secondHalf: first
        }
    }
}

nonisolated struct LeaveBudgetUse: Equatable, Sendable {
    let budgetID: UUID
    let halfDays: Int
}

/// One shift, or half of one, the user would ask to take off.
nonisolated struct LeavePlanItem: Equatable, Sendable {
    nonisolated enum Role: String, Sendable {
        /// Needed for the full rest days.
        case bridge
        /// A spare half day that leaves earlier on the last working day.
        case earlyDeparture
        /// A spare half day that returns later on the first working day.
        case lateReturn
    }

    /// The day the shift starts; an overnight shift keys as its first day.
    let dayNumber: Int
    let dayKey: String
    let portion: LeavePortion
    /// Absolute time freed, for "13:00–18:00" style previews.
    let segments: [NativeShiftSegment]
    let uses: [LeaveBudgetUse]
    let role: Role
}

nonisolated struct LeavePlanProposal: Equatable, Sendable {
    nonisolated enum DayKind: String, Sendable {
        case rest
        case holiday
        case leave
    }

    let firstRestDayNumber: Int
    let lastRestDayNumber: Int
    let firstRestDayKey: String
    let lastRestDayKey: String
    /// Sorted by time.
    let items: [LeavePlanItem]
    /// Per budget, in the order the budgets were given.
    let uses: [LeaveBudgetUse]
    /// When the last remaining shift before the break ends, and the next one
    /// after it starts. `nil` when the planner saw no work that far out.
    let lastShiftEndAtMs: Double?
    let nextShiftStartAtMs: Double?
    /// One per full rest day, from the first.
    let dayKinds: [DayKind]
    let caveats: Set<LeavePlannerCaveat>

    var fullRestDays: Int { lastRestDayNumber - firstRestDayNumber + 1 }
    var costHalfDays: Int { items.reduce(0) { $0 + $1.portion.halfDays } }
    /// The cost of the full rest days alone, without spare half days.
    var bridgeHalfDays: Int {
        items.filter { $0.role == .bridge }.reduce(0) { $0 + $1.portion.halfDays }
    }
}

nonisolated enum LeavePlanner {
    nonisolated enum Goal: Equatable, Sendable {
        /// "I want at least N days off in a row": fewest half days first.
        case restAtLeast(days: Int)
        /// "I can take at most N half days": longest break first.
        case leaveAtMost(halfDays: Int)
    }

    nonisolated struct Query: Equatable, Sendable {
        var goal: Goal
        /// The civil days the break must fall within, inclusive.
        var fromDayNumber: Int
        var throughDayNumber: Int
        /// Leave can only free time that has not started yet.
        var nowMs: Double
        /// The balances the user chose for this plan, in their order.
        var budgets: [LeaveBudget]
        var maximumProposals: Int = .max
    }

    /// Proposals for distinct stretches of rest, best first.
    ///
    /// `days` must be consecutive and cover the query's range; days either
    /// side of it only supply context — the overnight shift running into the
    /// first day, and the shifts that bound a break at the range's edges.
    static func proposals(days: [LeavePlannerDay], query: Query) -> [LeavePlanProposal] {
        guard let search = Search(days: days, query: query) else { return [] }
        return search.run()
    }
}

// MARK: - Search

private nonisolated struct Search {
    struct Shift {
        let dayIndex: Int
        let halves: LeaveShiftHalves
    }

    struct Candidate {
        let first: Int
        let last: Int
        let leave: [Int: LeavePortion]
        let cost: Int
    }

    enum Requirement: Equatable {
        case nothing
        case portion(LeavePortion)
    }

    let days: [LeavePlannerDay]
    let query: LeavePlanner.Query
    let shifts: [Shift]
    /// Shift indices whose work touches each day.
    let touching: [[Int]]
    let low: Int
    let high: Int
    let ceiling: Int

    init?(days: [LeavePlannerDay], query: LeavePlanner.Query) {
        guard let firstDay = days.first,
              query.fromDayNumber <= query.throughDayNumber,
              query.maximumProposals > 0,
              days.indices.allSatisfy({ days[$0].dayNumber == firstDay.dayNumber + $0 })
        else { return nil }
        let low = query.fromDayNumber - firstDay.dayNumber
        let high = query.throughDayNumber - firstDay.dayNumber
        guard days.indices.contains(low), days.indices.contains(high) else { return nil }

        var shifts: [Shift] = []
        var touching = Array(repeating: [Int](), count: days.count)
        for (index, day) in days.enumerated() where !day.segments.isEmpty {
            let halves = LeaveShiftHalves(segments: day.segments)
            let work = halves.remaining(after: nil)
            guard !work.isEmpty else { continue }
            let shiftIndex = shifts.count
            shifts.append(Shift(dayIndex: index, halves: halves))
            // A shift can reach back a day across a DST fold and forward
            // across midnight; a few days either side covers every shape.
            for other in max(0, index - 1)...min(days.count - 1, index + 3)
            where Self.overlaps(work, days[other].startAtMs, days[other].endAtMs) {
                touching[other].append(shiftIndex)
            }
        }

        let available = query.budgets.reduce(0) { $0 + max(0, $1.availableHalfDays) }
        let ceiling = switch query.goal {
        case .restAtLeast: available
        case .leaveAtMost(let halfDays): min(max(0, halfDays), available)
        }

        self.days = days
        self.query = query
        self.shifts = shifts
        self.touching = touching
        self.low = low
        self.high = high
        self.ceiling = ceiling
    }

    func run() -> [LeavePlanProposal] {
        var best: [Int: Candidate] = [:]
        for first in low...high {
            // A run starting the day after a day with no work at all takes the
            // same leave as one starting on that day, so only the earlier is tried.
            if first > low, touching[first - 1].isEmpty { continue }
            var leave: [Int: LeavePortion] = [:]
            var cost = 0
            var last = first
            extending: while last <= high {
                for shift in touching[last] {
                    guard case .portion(let portion) = requirement(
                        shift, from: days[first].startAtMs, to: days[last].endAtMs
                    ) else { continue }
                    let previous = leave[shift]
                    if previous == portion { continue }
                    guard let freed = shifts[shift].halves.removed(portion).first,
                          freed.startAtMs >= query.nowMs
                    else { break extending }
                    cost += portion.halfDays - (previous?.halfDays ?? 0)
                    leave[shift] = portion
                }
                guard cost <= ceiling else { break }
                let run = extend(first: first, last: last, leave: leave)
                let key = run.first * (high + 1) + run.last
                if best[key].map({ cost < $0.cost }) ?? true {
                    best[key] = Candidate(first: run.first, last: run.last, leave: leave, cost: cost)
                }
                if case .restAtLeast(let target) = query.goal, run.last - run.first + 1 >= target { break }
                // Days up to the run's end are already free under this leave.
                last = run.last + 1
            }
        }
        return select(Array(best.values))
    }

    /// The least of `shift` that must be taken so no work falls in `[from, to)`.
    func requirement(_ shift: Int, from: Double, to: Double) -> Requirement {
        let halves = shifts[shift].halves
        let inFirst = Self.overlaps(halves.first, from, to)
        let inSecond = Self.overlaps(halves.second, from, to)
        switch (inFirst, inSecond) {
        case (true, true): return .portion(.whole)
        case (true, false): return .portion(.firstHalf)
        case (false, true): return .portion(.secondHalf)
        case (false, false): return .nothing
        }
    }

    func isFree(_ day: Int, leave: [Int: LeavePortion]) -> Bool {
        touching[day].allSatisfy { shift in
            !Self.overlaps(shifts[shift].halves.remaining(after: leave[shift]), days[day].startAtMs, days[day].endAtMs)
        }
    }

    func extend(first: Int, last: Int, leave: [Int: LeavePortion]) -> (first: Int, last: Int) {
        var first = first
        var last = last
        while first > low, isFree(first - 1, leave: leave) { first -= 1 }
        while last < high, isFree(last + 1, leave: leave) { last += 1 }
        return (first, last)
    }

    func select(_ candidates: [Candidate]) -> [LeavePlanProposal] {
        let eligible: [Candidate]
        switch query.goal {
        case .restAtLeast(let target):
            eligible = candidates.filter { $0.last - $0.first + 1 >= max(1, target) }.sorted {
                ($0.cost, -($0.last - $0.first), $0.first) < ($1.cost, -($1.last - $1.first), $1.first)
            }
        case .leaveAtMost:
            eligible = candidates.sorted {
                (-($0.last - $0.first), $0.cost, $0.first) < (-($1.last - $1.first), $1.cost, $1.first)
            }
        }

        var chosen: [LeavePlanProposal] = []
        // Keep the already-computed bounds and bridge cost. Reading these
        // from rendered proposals would filter/sum every leave item for
        // every comparison in a full year's alternatives.
        var chosenCandidates: [Candidate] = []
        for candidate in eligible {
            if chosen.count == query.maximumProposals { break }
            // Shared weekends do not make two leave requests the same plan.
            // Only drop a shorter stretch fully covered by an already valid,
            // no-more-expensive plan. Partially overlapping alternatives stay.
            let isDominated = chosenCandidates.contains {
                $0.first <= candidate.first && $0.last >= candidate.last && $0.cost <= candidate.cost
            }
            guard !isDominated,
                  let proposal = proposal(for: candidate)
            else { continue }
            chosen.append(proposal)
            chosenCandidates.append(candidate)
        }
        return chosen
    }

    func proposal(for candidate: Candidate) -> LeavePlanProposal? {
        var leave = candidate.leave
        var roles = leave.mapValues { _ in LeavePlanItem.Role.bridge }
        guard var allocation = allocate(leave) else { return nil }
        let runStart = days[candidate.first].startAtMs
        let runEnd = days[candidate.last].endAtMs

        // A spare half day is spent on leaving earlier, then on returning
        // later. Neither adds a full rest day, so neither affects the ranking.
        if case .leaveAtMost = query.goal, candidate.cost < ceiling {
            let edges: [(shift: Int?, portion: LeavePortion, role: LeavePlanItem.Role)] = [
                (adjacentShift(before: runStart, leave: leave), .secondHalf, .earlyDeparture),
                (adjacentShift(after: runEnd, leave: leave), .firstHalf, .lateReturn),
            ]
            for edge in edges {
                guard let shift = edge.shift,
                      leave.values.reduce(0, { $0 + $1.halfDays }) < ceiling,
                      leave[shift] == nil,
                      (low...high).contains(shifts[shift].dayIndex),
                      let freed = shifts[shift].halves.removed(edge.portion).first,
                      freed.startAtMs >= query.nowMs
                else { continue }
                var trial = leave
                trial[shift] = edge.portion
                guard let trialAllocation = allocate(trial) else { continue }
                leave = trial
                roles[shift] = edge.role
                allocation = trialAllocation
            }
        }

        let items = leave.keys.sorted { shifts[$0].dayIndex < shifts[$1].dayIndex }.map { shift in
            let day = days[shifts[shift].dayIndex]
            let portion = leave[shift]!
            return LeavePlanItem(
                dayNumber: day.dayNumber,
                dayKey: day.dayKey,
                portion: portion,
                segments: shifts[shift].halves.removed(portion),
                uses: allocation.perShift[shift] ?? [],
                role: roles[shift] ?? .bridge
            )
        }
        let restDays = Array(days[candidate.first...candidate.last])
        let dayKinds = (candidate.first...candidate.last).map { index -> LeavePlanProposal.DayKind in
            if !touching[index].isEmpty { return .leave }
            return days[index].isHoliday ? .holiday : .rest
        }
        var caveats = restDays.reduce(into: Set<LeavePlannerCaveat>()) { $0.formUnion($1.caveats) }
        for item in items { caveats.formUnion(days[item.dayNumber - days[0].dayNumber].caveats) }

        let work = remainingWork(leave)
        return LeavePlanProposal(
            firstRestDayNumber: days[candidate.first].dayNumber,
            lastRestDayNumber: days[candidate.last].dayNumber,
            firstRestDayKey: days[candidate.first].dayKey,
            lastRestDayKey: days[candidate.last].dayKey,
            items: items,
            uses: allocation.totals,
            lastShiftEndAtMs: work.filter { $0.endAtMs <= runStart }.map(\.endAtMs).max(),
            nextShiftStartAtMs: work.filter { $0.startAtMs >= runEnd }.map(\.startAtMs).min(),
            dayKinds: dayKinds,
            caveats: caveats
        )
    }

    func remainingWork(_ leave: [Int: LeavePortion]) -> [NativeShiftSegment] {
        shifts.indices.flatMap { shifts[$0].halves.remaining(after: leave[$0]) }
    }

    /// The shift whose remaining work ends last before `ms`.
    func adjacentShift(before ms: Double, leave: [Int: LeavePortion]) -> Int? {
        shifts.indices.filter { index in
            shifts[index].halves.remaining(after: leave[index]).contains { $0.endAtMs <= ms }
        }.max { lhs, rhs in
            let left = shifts[lhs].halves.remaining(after: leave[lhs]).map(\.endAtMs).max() ?? 0
            let right = shifts[rhs].halves.remaining(after: leave[rhs]).map(\.endAtMs).max() ?? 0
            return left < right
        }
    }

    /// The shift whose remaining work starts first after `ms`.
    func adjacentShift(after ms: Double, leave: [Int: LeavePortion]) -> Int? {
        shifts.indices.filter { index in
            shifts[index].halves.remaining(after: leave[index]).contains { $0.startAtMs >= ms }
        }.min { lhs, rhs in
            let left = shifts[lhs].halves.remaining(after: leave[lhs]).map(\.startAtMs).min() ?? 0
            let right = shifts[rhs].halves.remaining(after: leave[rhs]).map(\.startAtMs).min() ?? 0
            return left < right
        }
    }

    /// Half days assigned earliest-expiry first, which places every half day
    /// whenever any assignment can: each is a point in time and each balance
    /// an interval. A whole shift may draw on two balances.
    func allocate(_ leave: [Int: LeavePortion]) -> (perShift: [Int: [LeaveBudgetUse]], totals: [LeaveBudgetUse])? {
        var remaining = query.budgets.map { max(0, $0.availableHalfDays) }
        var perShift: [Int: [LeaveBudgetUse]] = [:]
        for shift in leave.keys.sorted(by: { shifts[$0].dayIndex < shifts[$1].dayIndex }) {
            let dayNumber = days[shifts[shift].dayIndex].dayNumber
            var uses: [LeaveBudgetUse] = []
            for _ in 0..<leave[shift]!.halfDays {
                let pick = query.budgets.indices
                    .filter { remaining[$0] > 0 && query.budgets[$0].covers(dayNumber: dayNumber) }
                    .min { (query.budgets[$0].validThroughDayNumber ?? .max, $0) < (query.budgets[$1].validThroughDayNumber ?? .max, $1) }
                guard let pick else { return nil }
                remaining[pick] -= 1
                let id = query.budgets[pick].id
                if let existing = uses.firstIndex(where: { $0.budgetID == id }) {
                    uses[existing] = LeaveBudgetUse(budgetID: id, halfDays: uses[existing].halfDays + 1)
                } else {
                    uses.append(LeaveBudgetUse(budgetID: id, halfDays: 1))
                }
            }
            perShift[shift] = uses
        }
        let totals = query.budgets.indices.compactMap { index -> LeaveBudgetUse? in
            let spent = max(0, query.budgets[index].availableHalfDays) - remaining[index]
            return spent > 0 ? LeaveBudgetUse(budgetID: query.budgets[index].id, halfDays: spent) : nil
        }
        return (perShift, totals)
    }

    static func overlaps(_ segments: [NativeShiftSegment], _ from: Double, _ to: Double) -> Bool {
        segments.contains { $0.startAtMs < to && $0.endAtMs > from }
    }
}
