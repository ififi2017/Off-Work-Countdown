import SwiftUI

/// Selection only previews a proposal. The explicit details action retains
/// the planner's existing free-view gate and is the route to adoption.
struct LeavePlanResults: View {
    let shifts: ShiftSessionStore
    let proposals: [LeavePlanProposal]
    let open: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection = 0
    @State private var arrived = false
    @Namespace private var selectionSpace

    private var text: AppText { shifts.text }
    private var selected: LeavePlanProposal? {
        proposals.indices.contains(selection) ? proposals[selection] : nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let selected {
                    LeavePlanCalendar(shifts: shifts, proposal: selected)
                        .padding(16)
                        .background(OWCDesign.card, in: .rect(cornerRadius: OWCDesign.cardRadius))
                        .owcRevealed(arrived, index: 0, reduceMotion: reduceMotion)

                    VStack(spacing: 12) {
                        navigation
                        options
                        Button { open(selection) } label: {
                            Text(text.t("leaveViewDetails"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OWCPrimaryButtonStyle())
                        .accessibilityIdentifier("leave-plan-details")
                    }
                    .owcRevealed(arrived, index: 1, reduceMotion: reduceMotion)

                    if !shifts.plus.isAuthorized {
                        LeaveTrialBanner(shifts: shifts, explainsCost: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ContentUnavailableView {
                        Label(text.t("leaveResultsTitle"), systemImage: "calendar")
                    } description: {
                        Text(text.t("leaveNoResults"))
                    }
                }
            }
            .padding(OWCDesign.pageInset)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(OWCDesign.page)
        .navigationTitle(text.t("leaveResultsTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: selection)
        .onAppear { arrived = true }
    }

    private var navigation: some View {
        HStack(spacing: 12) {
            navigationButton(-1, titleKey: "leavePreviousPlan", symbol: "chevron.backward")
            Spacer(minLength: 0)
            Text(text.t("leavePlanPosition", values: [
                "current": text.formatCount(selection + 1),
                "total": text.formatCount(proposals.count),
            ]))
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(OWCDesign.secondary)
            .contentTransition(.numericText())
            .accessibilityIdentifier("leave-plan-position")
            Spacer(minLength: 0)
            navigationButton(1, titleKey: "leaveNextPlan", symbol: "chevron.forward")
        }
    }

    private func navigationButton(_ delta: Int, titleKey: String, symbol: String) -> some View {
        Button { select(selection + delta) } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(OWCDesign.control, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(OWCDesign.accent)
        .accessibilityLabel(text.t(titleKey))
        .disabled(!proposals.indices.contains(selection + delta))
    }

    private var options: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 10) {
                ForEach(proposals.indices, id: \.self) { index in
                    option(proposals[index], at: index)
                        .containerRelativeFrame(.horizontal) { width, _ in max(0, width - 24) }
                        .id(index)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: Binding<Int?>(
            get: { selection },
            set: { if let index = $0 { select(index) } }
        ))
    }

    private func option(_ proposal: LeavePlanProposal, at index: Int) -> some View {
        let isSelected = selection == index
        return Button { select(index) } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(OWCText.ltrRange(
                        shifts.leaveDayLabel(proposal.firstRestDayNumber, template: "MMMd"),
                        shifts.leaveDayLabel(proposal.lastRestDayNumber, template: "MMMd")
                    ))
                    .font(.headline)
                    Text(text.t("leaveDaysOff", count: proposal.fullRestDays))
                        .font(.subheadline.weight(.medium))
                    Text(proposal.costHalfDays == 0
                         ? text.t("leaveNoLeaveNeeded")
                         : text.t("leaveUses", values: ["days": text.formatDays(Double(proposal.costHalfDays) / 2)]))
                        .font(.subheadline)
                        .foregroundStyle(OWCDesign.secondary)
                    if !proposal.caveats.isEmpty {
                        Label(text.t("leaveEstimated"), systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(OWCDesign.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? OWCDesign.accent : OWCDesign.tertiary)
            }
            .foregroundStyle(OWCDesign.primary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OWCDesign.card, in: .rect(cornerRadius: OWCDesign.cardRadius))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: OWCDesign.cardRadius)
                        .strokeBorder(OWCDesign.accent.opacity(0.65), lineWidth: 1.5)
                        .matchedGeometryEffect(id: "selected-plan", in: selectionSpace)
                }
            }
            .contentShape(.rect(cornerRadius: OWCDesign.cardRadius))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("leave-plan-option-\(index)")
    }

    private func select(_ index: Int) {
        guard proposals.indices.contains(index), index != selection else { return }
        withAnimation(reduceMotion ? OWCMotion.reduced : OWCMotion.navigation) {
            selection = index
        }
    }
}
