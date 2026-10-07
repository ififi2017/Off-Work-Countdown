package com.rainif.doneat.core.domain.leave

import com.rainif.doneat.core.domain.records.LeaveBalanceUse
import com.rainif.doneat.core.domain.records.LeaveBudget
import com.rainif.doneat.core.domain.schedule.LeavePortion
import com.rainif.doneat.core.domain.schedule.ShiftSegment
import kotlin.math.floor

/*
 * Plan 020 §2: where a few days of leave buy the longest break, over the
 * user's own final schedule (iOS `LeavePlanner`).
 *
 * It resolves no schedule of its own: `LeavePlannerSchedule` hands it every
 * civil day with the shift the existing rules already produced (cycle rule,
 * hand-set days, holidays and makeup workdays included), so a weekend is rest
 * only when the schedule says so, and a holiday the user still works has to
 * be taken as leave.
 *
 * A full rest day is a civil day, midnight to midnight in the schedule's zone,
 * that no remaining work segment touches. An overnight shift from the day
 * before therefore costs the morning it runs into, and a day with half a
 * shift left is never counted as rest. Leave comes in whole shifts or halves,
 * split by effective working time with breaks left out, never at noon or by
 * an assumed eight-hour day.
 */

/** Why part of a proposal is less than certain. */
sealed interface LeavePlannerCaveat {
    /** The holiday region is on, but this build carries no data for [year], so the day follows the ordinary schedule. */
    data class HolidaysNotIncluded(val year: Int) : LeavePlannerCaveat

    /** The selected calendar carries explicitly predicted, rather than announced, holidays. */
    data class HolidaysEstimated(val year: Int) : LeavePlannerCaveat

    /** The roster repeats an earlier month the user filled in. */
    data object CarriedOverRoster : LeavePlannerCaveat

    /** Nothing assigns the day, so it is taken as rest. */
    data object Unassigned : LeavePlannerCaveat
}

/** One civil day, already resolved by the schedule rules. */
data class LeavePlannerDay(
    val dayNumber: Int,
    val dayKey: String,
    /** Civil midnight to the next civil midnight: 23 or 25 hours across DST. */
    val startAtMs: Double,
    val endAtMs: Double,
    /** Effective work of the shift that starts on this day; empty on rest. */
    val segments: List<ShiftSegment>,
    /** Rest because of a bundled public holiday rather than the roster. */
    val isHoliday: Boolean,
    val caveats: Set<LeavePlannerCaveat> = emptySet(),
)

/**
 * A shift's two halves by effective working time. A 09:00–18:00 shift with
 * lunch at 12:00–13:00 splits at 14:00: 09:00–12:00 and 13:00–14:00 make the
 * first four hours.
 */
class LeaveShiftHalves(segments: List<ShiftSegment>) {
    val first: List<ShiftSegment>
    val second: List<ShiftSegment>
    private val whole: List<ShiftSegment>

    init {
        val ordered = segments.filter { it.endAtMs > it.startAtMs }.sortedBy { it.startAtMs }
        val total = ordered.sumOf { it.endAtMs - it.startAtMs }
        // Whole minutes, so both halves read as clock times.
        var firstRemaining = floor(total / 120_000) * 60_000
        val first = ArrayList<ShiftSegment>()
        val second = ArrayList<ShiftSegment>()
        for (segment in ordered) {
            val length = segment.endAtMs - segment.startAtMs
            if (firstRemaining >= length) {
                first += segment
                firstRemaining -= length
            } else if (firstRemaining > 0) {
                val split = segment.startAtMs + firstRemaining
                first += ShiftSegment(segment.startAtMs, split)
                second += ShiftSegment(split, segment.endAtMs)
                firstRemaining = 0.0
            } else {
                second += segment
            }
        }
        this.first = first
        this.second = second
        this.whole = first + second
    }

    fun removed(portion: LeavePortion): List<ShiftSegment> = when (portion) {
        LeavePortion.WHOLE -> whole
        LeavePortion.FIRST_HALF -> first
        LeavePortion.SECOND_HALF -> second
    }

    /** What is still worked once [portion] is taken; everything when null. */
    fun remaining(after: LeavePortion?): List<ShiftSegment> = when (after) {
        null -> whole
        LeavePortion.WHOLE -> emptyList()
        LeavePortion.FIRST_HALF -> second
        LeavePortion.SECOND_HALF -> first
    }
}

/** One shift, or half of one, the user would ask to take off. */
data class LeavePlanItem(
    /** The day the shift starts; an overnight shift keys as its first day. */
    val dayNumber: Int,
    val dayKey: String,
    val portion: LeavePortion,
    /** Absolute time freed, for "13:00–18:00" style previews. */
    val segments: List<ShiftSegment>,
    val uses: List<LeaveBalanceUse>,
    val role: Role,
) {
    enum class Role {
        /** Needed for the full rest days. */
        BRIDGE,
        /** A spare half day that leaves earlier on the last working day. */
        EARLY_DEPARTURE,
        /** A spare half day that returns later on the first working day. */
        LATE_RETURN,
    }
}

data class LeavePlanProposal(
    val firstRestDayNumber: Int,
    val lastRestDayNumber: Int,
    val firstRestDayKey: String,
    val lastRestDayKey: String,
    /** Sorted by time. */
    val items: List<LeavePlanItem>,
    /** Per budget, in the order the budgets were given. */
    val uses: List<LeaveBalanceUse>,
    /** When the last remaining shift before the break ends, and the next one after it starts. */
    val lastShiftEndAtMs: Double?,
    val nextShiftStartAtMs: Double?,
    /** One per full rest day, from the first. */
    val dayKinds: List<DayKind>,
    val caveats: Set<LeavePlannerCaveat>,
) {
    enum class DayKind { REST, HOLIDAY, LEAVE }

    val fullRestDays get() = lastRestDayNumber - firstRestDayNumber + 1
    val costHalfDays get() = items.sumOf { it.portion.halfDays }

    /** The cost of the full rest days alone, without spare half days. */
    val bridgeHalfDays get() = items.filter { it.role == LeavePlanItem.Role.BRIDGE }.sumOf { it.portion.halfDays }
}

object LeavePlanner {
    sealed interface Goal {
        /** "I want at least N days off in a row": fewest half days first. */
        data class RestAtLeast(val days: Int) : Goal

        /** "I can take at most N half days": longest break first. */
        data class LeaveAtMost(val halfDays: Int) : Goal
    }

    data class Query(
        val goal: Goal,
        /** The civil days the break must fall within, inclusive. */
        val fromDayNumber: Int,
        val throughDayNumber: Int,
        /** Leave can only free time that has not started yet. */
        val nowMs: Double,
        /** The balances the user chose for this plan, in their order. */
        val budgets: List<LeaveBudget>,
        val maximumProposals: Int = Int.MAX_VALUE,
    )

    /**
     * Proposals for distinct stretches of rest, best first. [days] must be
     * consecutive and cover the query's range; days either side of it only
     * supply context: the overnight shift running into the first day, and the
     * shifts that bound a break at the range's edges.
     */
    fun proposals(days: List<LeavePlannerDay>, query: Query): List<LeavePlanProposal> =
        Search.of(days, query)?.run().orEmpty()
}

private class Search private constructor(
    val days: List<LeavePlannerDay>,
    val query: LeavePlanner.Query,
    val shifts: List<LeaveShiftHalves>,
    val shiftDays: List<Int>,
    /** Shift indices whose work touches each day. */
    val touching: List<List<Int>>,
    val low: Int,
    val high: Int,
    val ceiling: Int,
) {
    class Candidate(val first: Int, val last: Int, val leave: Map<Int, LeavePortion>, val cost: Int)

    fun run(): List<LeavePlanProposal> {
        val best = HashMap<Int, Candidate>()
        for (first in low..high) {
            // A run starting the day after a day with no work at all takes the
            // same leave as one starting on that day, so only the earlier is tried.
            if (first > low && touching[first - 1].isEmpty()) continue
            val leave = HashMap<Int, LeavePortion>()
            var cost = 0
            var last = first
            extending@ while (last <= high) {
                for (shift in touching[last]) {
                    val portion = requirement(shift, days[first].startAtMs, days[last].endAtMs) ?: continue
                    val previous = leave[shift]
                    if (previous == portion) continue
                    val freed = shifts[shift].removed(portion).firstOrNull()
                    if (freed == null || freed.startAtMs < query.nowMs) break@extending
                    cost += portion.halfDays - (previous?.halfDays ?: 0)
                    leave[shift] = portion
                }
                if (cost > ceiling) break
                val (runFirst, runLast) = extend(first, last, leave)
                val key = runFirst * (high + 1) + runLast
                val existing = best[key]
                if (existing == null || cost < existing.cost) best[key] = Candidate(runFirst, runLast, HashMap(leave), cost)
                val goal = query.goal
                if (goal is LeavePlanner.Goal.RestAtLeast && runLast - runFirst + 1 >= goal.days) break
                // Days up to the run's end are already free under this leave.
                last = runLast + 1
            }
        }
        return select(best.values.toList())
    }

    /** The least of [shift] that must be taken so no work falls in `[from, to)`; null for nothing. */
    fun requirement(shift: Int, from: Double, to: Double): LeavePortion? {
        val inFirst = overlaps(shifts[shift].first, from, to)
        val inSecond = overlaps(shifts[shift].second, from, to)
        return when {
            inFirst && inSecond -> LeavePortion.WHOLE
            inFirst -> LeavePortion.FIRST_HALF
            inSecond -> LeavePortion.SECOND_HALF
            else -> null
        }
    }

    fun isFree(day: Int, leave: Map<Int, LeavePortion>) = touching[day].all { shift ->
        !overlaps(shifts[shift].remaining(leave[shift]), days[day].startAtMs, days[day].endAtMs)
    }

    fun extend(first: Int, last: Int, leave: Map<Int, LeavePortion>): Pair<Int, Int> {
        var start = first
        var end = last
        while (start > low && isFree(start - 1, leave)) start -= 1
        while (end < high && isFree(end + 1, leave)) end += 1
        return start to end
    }

    fun select(candidates: List<Candidate>): List<LeavePlanProposal> {
        val eligible = when (val goal = query.goal) {
            is LeavePlanner.Goal.RestAtLeast -> candidates.filter { it.last - it.first + 1 >= maxOf(1, goal.days) }
                .sortedWith(compareBy<Candidate> { it.cost }.thenBy { -(it.last - it.first) }.thenBy { it.first })
            is LeavePlanner.Goal.LeaveAtMost -> candidates
                .sortedWith(compareBy<Candidate> { -(it.last - it.first) }.thenBy { it.cost }.thenBy { it.first })
        }
        val chosen = ArrayList<LeavePlanProposal>()
        val chosenCandidates = ArrayList<Candidate>()
        for (candidate in eligible) {
            if (chosen.size == query.maximumProposals) break
            // Sharing a weekend does not make two leave requests the same plan.
            // Discard only a fully covered stretch which costs no less.
            val isDominated = chosenCandidates.any {
                it.first <= candidate.first && it.last >= candidate.last && it.cost <= candidate.cost
            }
            if (isDominated) continue
            chosen += proposal(candidate) ?: continue
            chosenCandidates += candidate
        }
        return chosen
    }

    fun proposal(candidate: Candidate): LeavePlanProposal? {
        val leave = HashMap(candidate.leave)
        val roles = HashMap<Int, LeavePlanItem.Role>().apply { leave.keys.forEach { put(it, LeavePlanItem.Role.BRIDGE) } }
        var allocation = allocate(leave) ?: return null
        val runStart = days[candidate.first].startAtMs
        val runEnd = days[candidate.last].endAtMs

        // A spare half day is spent on leaving earlier, then on returning
        // later. Neither adds a full rest day, so neither affects the ranking.
        if (query.goal is LeavePlanner.Goal.LeaveAtMost && candidate.cost < ceiling) {
            val edges = listOf(
                Triple(adjacentShiftBefore(runStart, leave), LeavePortion.SECOND_HALF, LeavePlanItem.Role.EARLY_DEPARTURE),
                Triple(adjacentShiftAfter(runEnd, leave), LeavePortion.FIRST_HALF, LeavePlanItem.Role.LATE_RETURN),
            )
            for ((shift, portion, role) in edges) {
                if (shift == null || leave.values.sumOf { it.halfDays } >= ceiling || leave.containsKey(shift)) continue
                if (shiftDays[shift] !in low..high) continue
                val freed = shifts[shift].removed(portion).firstOrNull()
                if (freed == null || freed.startAtMs < query.nowMs) continue
                val trial = HashMap(leave).apply { put(shift, portion) }
                val trialAllocation = allocate(trial) ?: continue
                leave[shift] = portion
                roles[shift] = role
                allocation = trialAllocation
            }
        }

        val items = leave.keys.sortedBy { shiftDays[it] }.map { shift ->
            val day = days[shiftDays[shift]]
            val portion = leave.getValue(shift)
            LeavePlanItem(
                dayNumber = day.dayNumber,
                dayKey = day.dayKey,
                portion = portion,
                segments = shifts[shift].removed(portion),
                uses = allocation.first[shift].orEmpty(),
                role = roles[shift] ?: LeavePlanItem.Role.BRIDGE,
            )
        }
        val dayKinds = (candidate.first..candidate.last).map { index ->
            when {
                touching[index].isNotEmpty() -> LeavePlanProposal.DayKind.LEAVE
                days[index].isHoliday -> LeavePlanProposal.DayKind.HOLIDAY
                else -> LeavePlanProposal.DayKind.REST
            }
        }
        val caveats = HashSet<LeavePlannerCaveat>()
        for (index in candidate.first..candidate.last) caveats += days[index].caveats
        for (item in items) caveats += days[item.dayNumber - days[0].dayNumber].caveats
        val remaining = remainingWork(leave)
        return LeavePlanProposal(
            firstRestDayNumber = days[candidate.first].dayNumber,
            lastRestDayNumber = days[candidate.last].dayNumber,
            firstRestDayKey = days[candidate.first].dayKey,
            lastRestDayKey = days[candidate.last].dayKey,
            items = items,
            uses = allocation.second,
            lastShiftEndAtMs = remaining.filter { it.endAtMs <= runStart }.maxOfOrNull { it.endAtMs },
            nextShiftStartAtMs = remaining.filter { it.startAtMs >= runEnd }.minOfOrNull { it.startAtMs },
            dayKinds = dayKinds,
            caveats = caveats,
        )
    }

    fun remainingWork(leave: Map<Int, LeavePortion>) = shifts.indices.flatMap { shifts[it].remaining(leave[it]) }

    /** The shift whose remaining work ends last before [ms]. */
    fun adjacentShiftBefore(ms: Double, leave: Map<Int, LeavePortion>): Int? = shifts.indices
        .filter { index -> shifts[index].remaining(leave[index]).any { it.endAtMs <= ms } }
        .maxByOrNull { index -> shifts[index].remaining(leave[index]).maxOfOrNull { it.endAtMs } ?: 0.0 }

    /** The shift whose remaining work starts first after [ms]. */
    fun adjacentShiftAfter(ms: Double, leave: Map<Int, LeavePortion>): Int? = shifts.indices
        .filter { index -> shifts[index].remaining(leave[index]).any { it.startAtMs >= ms } }
        .minByOrNull { index -> shifts[index].remaining(leave[index]).minOfOrNull { it.startAtMs } ?: 0.0 }

    /**
     * Half days assigned earliest-expiry first, which places every half day
     * whenever any assignment can: each is a point in time and each balance an
     * interval. A whole shift may draw on two balances.
     */
    fun allocate(leave: Map<Int, LeavePortion>): Pair<Map<Int, List<LeaveBalanceUse>>, List<LeaveBalanceUse>>? {
        val budgets = query.budgets
        val remaining = budgets.map { maxOf(0, it.availableHalfDays) }.toIntArray()
        val perShift = HashMap<Int, List<LeaveBalanceUse>>()
        for (shift in leave.keys.sortedBy { shiftDays[it] }) {
            val dayNumber = days[shiftDays[shift]].dayNumber
            val uses = ArrayList<LeaveBalanceUse>()
            repeat(leave.getValue(shift).halfDays) {
                val pick = budgets.indices
                    .filter { remaining[it] > 0 && budgets[it].covers(dayNumber) }
                    .minWithOrNull(compareBy<Int> { budgets[it].validThroughDayNumber ?: Int.MAX_VALUE }.thenBy { it })
                    ?: return null
                remaining[pick] -= 1
                val id = budgets[pick].id
                val existing = uses.indexOfFirst { it.balanceID == id }
                if (existing >= 0) uses[existing] = LeaveBalanceUse(id, uses[existing].halfDays + 1) else uses += LeaveBalanceUse(id, 1)
            }
            perShift[shift] = uses
        }
        val totals = budgets.indices.mapNotNull { index ->
            val spent = maxOf(0, budgets[index].availableHalfDays) - remaining[index]
            if (spent > 0) LeaveBalanceUse(budgets[index].id, spent) else null
        }
        return perShift to totals
    }

    companion object {
        fun overlaps(segments: List<ShiftSegment>, from: Double, to: Double) = segments.any { it.startAtMs < to && it.endAtMs > from }

        fun of(days: List<LeavePlannerDay>, query: LeavePlanner.Query): Search? {
            val firstDay = days.firstOrNull() ?: return null
            if (query.fromDayNumber > query.throughDayNumber || query.maximumProposals <= 0) return null
            if (days.indices.any { days[it].dayNumber != firstDay.dayNumber + it }) return null
            val low = query.fromDayNumber - firstDay.dayNumber
            val high = query.throughDayNumber - firstDay.dayNumber
            if (low !in days.indices || high !in days.indices) return null

            val shifts = ArrayList<LeaveShiftHalves>()
            val shiftDays = ArrayList<Int>()
            val touching = List(days.size) { ArrayList<Int>() }
            for ((index, day) in days.withIndex()) {
                if (day.segments.isEmpty()) continue
                val halves = LeaveShiftHalves(day.segments)
                val work = halves.remaining(null)
                if (work.isEmpty()) continue
                val shiftIndex = shifts.size
                shifts += halves
                shiftDays += index
                // A shift can reach back a day across a DST fold and forward
                // across midnight; a few days either side covers every shape.
                for (other in maxOf(0, index - 1)..minOf(days.size - 1, index + 3)) {
                    if (overlaps(work, days[other].startAtMs, days[other].endAtMs)) touching[other] += shiftIndex
                }
            }
            val available = query.budgets.sumOf { maxOf(0, it.availableHalfDays) }
            val ceiling = when (val goal = query.goal) {
                is LeavePlanner.Goal.RestAtLeast -> available
                is LeavePlanner.Goal.LeaveAtMost -> minOf(maxOf(0, goal.halfDays), available)
            }
            return Search(days, query, shifts, shiftDays, touching, low, high, ceiling)
        }
    }
}
