package com.rainif.doneat.core.domain.leave

/** Presentation groups retain every original date and its exact allocation and caveats. */
data class LeavePlanGroup(
    val id: Int,
    val category: Category,
    val proposalIndices: List<Int>,
) {
    enum class Category { HOLIDAY, REGULAR }

    private data class Pattern(val restDays: Int, val halfDays: Int, val earlyHalfDays: Int, val lateHalfDays: Int)

    companion object {
        fun make(proposals: List<LeavePlanProposal>): List<LeavePlanGroup> {
            val groups = ArrayList<LeavePlanGroup>()
            val regular = HashMap<Pattern, Int>()
            proposals.forEachIndexed { index, proposal ->
                // A public holiday that the user still works is not free rest.
                if (LeavePlanProposal.DayKind.HOLIDAY in proposal.dayKinds) {
                    groups += LeavePlanGroup(index, Category.HOLIDAY, listOf(index))
                } else {
                    val pattern = Pattern(
                        proposal.fullRestDays, proposal.costHalfDays,
                        proposal.items.filter { it.role == LeavePlanItem.Role.EARLY_DEPARTURE }.sumOf { it.portion.halfDays },
                        proposal.items.filter { it.role == LeavePlanItem.Role.LATE_RETURN }.sumOf { it.portion.halfDays },
                    )
                    val existing = regular[pattern]
                    if (existing == null) {
                        regular[pattern] = groups.size
                        groups += LeavePlanGroup(index, Category.REGULAR, listOf(index))
                    } else {
                        groups[existing] = groups[existing].copy(proposalIndices = groups[existing].proposalIndices + index)
                    }
                }
            }
            // Groups retain recommendation order; dates inside each group are chronological.
            return groups.map { group ->
                group.copy(proposalIndices = group.proposalIndices.sortedWith(compareBy<Int> { proposals[it].firstRestDayNumber }.thenBy { it }))
            }
        }
    }
}
