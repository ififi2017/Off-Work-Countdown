import SwiftUI

/// A searchable-length list of real dates, grouped by month, rather than a
/// several-hundred-item carousel. The chosen index still belongs to the input.
struct LeavePlanDatePicker: View {
    let shifts: ShiftSessionStore
    let proposals: [LeavePlanProposal]
    let indices: [Int]
    let selection: Int
    let select: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    private var months: [[Int]] {
        indices.reduce(into: [[Int]]()) { result, index in
            let day = CivilZone.civilDate(dayNumber: proposals[index].firstRestDayNumber)
            if let previous = result.last?.first {
                let previousDay = CivilZone.civilDate(dayNumber: proposals[previous].firstRestDayNumber)
                if day.year == previousDay.year && day.month == previousDay.month {
                    result[result.count - 1].append(index)
                    return
                }
            }
            result.append([index])
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if let first = indices.first.map({ proposals[$0] }) {
                    Section {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(shifts.text.t("leaveDaysOff", count: first.fullRestDays))
                                    .font(.headline)
                                Text(shifts.leaveCost(first))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(OWCDesign.accent)
                            }
                            LeaveDayStrip(kinds: LeaveDayStrip.kinds(first), cellWidth: 18)
                                .padding(.top, 10)
                            Text(shifts.text.t("leaveSamePatternHint"))
                                .font(.footnote)
                                .foregroundStyle(OWCDesign.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 10)
                        }
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .combine)
                    }
                }
                ForEach(months, id: \.self) { month in
                    Section(shifts.leaveDayLabel(proposals[month[0]].firstRestDayNumber, template: "yMMMM")) {
                        ForEach(month, id: \.self) { index in
                            let proposal = proposals[index]
                            Button {
                                select(index)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(OWCText.ltrRange(
                                            shifts.leaveDayLabel(proposal.firstRestDayNumber, template: "MMMdEEE"),
                                            shifts.leaveDayLabel(proposal.lastRestDayNumber, template: "MMMdEEE")
                                        ))
                                        .monospacedDigit()
                                        .foregroundStyle(OWCDesign.primary)
                                        if !proposal.caveats.isEmpty {
                                            Text(shifts.text.t("leaveEstimated"))
                                                .font(.caption)
                                                .foregroundStyle(OWCDesign.secondary)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    if index == selection {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(OWCDesign.accent)
                                    }
                                }
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(index == selection ? .isSelected : [])
                            .accessibilityIdentifier("leave-plan-date-\(index)")
                            .id(index)
                        }
                    }
                }
            }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
        }
        .navigationTitle(shifts.text.t("leaveAvailableDates", values: ["count": shifts.text.formatCount(indices.count)]))
        .navigationBarTitleDisplayMode(.inline)
    }
}
