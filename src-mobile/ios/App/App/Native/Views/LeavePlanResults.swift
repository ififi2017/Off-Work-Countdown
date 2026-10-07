import SwiftUI

/// Selection only previews a proposal. The explicit details action retains
/// the planner's existing free-view gate and is the route to adoption.
struct LeavePlanResults: View {
    let shifts: ShiftSessionStore
    let proposals: [LeavePlanProposal]
    let open: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    private let groups: [LeavePlanGroup]
    @State private var category: LeavePlanGroup.Category
    @State private var groupID: Int
    @State private var dates: [Int: Int] = [:]
    @State private var showsDates = false
    @State private var arrived = false

    init(shifts: ShiftSessionStore, proposals: [LeavePlanProposal], open: @escaping (Int) -> Void) {
        self.shifts = shifts
        self.proposals = proposals
        self.open = open
        let groups = LeavePlanGroup.make(from: proposals)
        self.groups = groups
        let first = groups.first(where: { $0.category == .holiday }) ?? groups.first
        _category = State(initialValue: first?.category ?? .regular)
        _groupID = State(initialValue: first?.id ?? 0)
        #if DEBUG
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "ios.native.qaLeavePlanner"),
           defaults.object(forKey: "ios.native.qaLeaveProposal") != nil {
            let index = defaults.integer(forKey: "ios.native.qaLeaveProposal")
            if let group = groups.first(where: { $0.proposalIndices.contains(index) }) {
                _category = State(initialValue: group.category)
                _groupID = State(initialValue: group.id)
                _dates = State(initialValue: [group.id: index])
            }
        }
        #endif
    }

    private var text: AppText { shifts.text }
    private var visibleGroups: [LeavePlanGroup] { groups.filter { $0.category == category } }
    private var group: LeavePlanGroup? { visibleGroups.first { $0.id == groupID } ?? visibleGroups.first }
    private var groupIndex: Int { visibleGroups.firstIndex { $0.id == group?.id } ?? 0 }
    private var selection: Int { group.flatMap { dates[$0.id] ?? $0.proposalIndices.first } ?? 0 }
    private var selected: LeavePlanProposal? {
        proposals.indices.contains(selection) ? proposals[selection] : nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let selected {
                    LeavePlanCalendar(shifts: shifts, proposal: selected)
                        .padding(16)
                        .background(OWCDesign.card, in: .rect(cornerRadius: OWCDesign.cardRadius))
                        .owcRevealed(arrived, index: 0, reduceMotion: reduceMotion)

                    ForEach(estimatedYears(selected), id: \.self) { year in
                        Label(text.t("holidayEstimatedYearWarning", values: ["year": text.formatYear(year)]),
                              systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(OWCDesign.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 8) {
                        categoryPicker
                        navigation
                        option(selected)
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
        .sheet(isPresented: $showsDates) {
            if let group {
                LeavePlanDatePicker(shifts: shifts, proposals: proposals,
                                    indices: group.proposalIndices, selection: selection) { index in
                    withAnimation(reduceMotion ? OWCMotion.reduced : OWCMotion.navigation) {
                        dates[group.id] = index
                    }
                }
            }
        }
    }

    private var navigation: some View {
        HStack(spacing: 12) {
            navigationButton(-1, titleKey: "leavePreviousPlan", symbol: "chevron.backward")
            Spacer(minLength: 0)
            Text(text.t("leavePlanPosition", values: [
                "current": text.formatCount(groupIndex + 1),
                "total": text.formatCount(visibleGroups.count),
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
        Button { selectGroup(groupIndex + delta) } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(OWCDesign.control, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(OWCDesign.accent)
        .accessibilityLabel(text.t(titleKey))
        .disabled(!visibleGroups.indices.contains(groupIndex + delta))
    }

    private var categoryPicker: some View {
        Picker(text.t("leaveResultsTitle"), selection: $category) {
            ForEach(LeavePlanGroup.Category.allCases, id: \.self) { category in
                if groups.contains(where: { $0.category == category }) {
                    Text(text.t(category.titleKey)).tag(category)
                }
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: category) { _, _ in
            groupID = visibleGroups.first?.id ?? 0
        }
    }

    // One card in the page's coordinate space: no accumulated lazy-scroll
    // offsets, variable-height pages or geometry shared with offscreen cards.
    private func option(_ proposal: LeavePlanProposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
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
                    Label(text.t("leaveEstimated"), systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(OWCDesign.secondary)
                        .opacity(proposal.caveats.isEmpty ? 0 : 1)
                        .accessibilityHidden(proposal.caveats.isEmpty)
                    ForEach(estimatedYears(proposal), id: \.self) { year in
                        Text(text.t("leaveEstimatedHolidaysYear", values: ["year": text.formatYear(year)]))
                            .font(.caption)
                            .foregroundStyle(OWCDesign.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(OWCDesign.accent)
                    .accessibilityHidden(true)
            }
            .id(selection)
            .transition(.opacity)
            if let group, group.proposalIndices.count > 1 {
                Button { showsDates = true } label: {
                    HStack {
                        Text(text.t("leaveAvailableDates", values: ["count": text.formatCount(group.proposalIndices.count)]))
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(OWCDesign.accent)
                .accessibilityIdentifier("leave-plan-dates")
            }
        }
        .foregroundStyle(OWCDesign.primary)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OWCDesign.card, in: .rect(cornerRadius: OWCDesign.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: OWCDesign.cardRadius)
                .strokeBorder(OWCDesign.accent.opacity(0.65), lineWidth: 1.5)
        }
        .contentShape(.rect(cornerRadius: OWCDesign.cardRadius))
        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
            guard abs(value.translation.width) > 44,
                  abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
            let forward = layoutDirection == .rightToLeft ? value.translation.width > 0 : value.translation.width < 0
            selectGroup(groupIndex + (forward ? 1 : -1))
        })
        .accessibilityIdentifier("leave-plan-option-\(selection)")
    }

    private func selectGroup(_ index: Int) {
        guard visibleGroups.indices.contains(index), index != groupIndex else { return }
        withAnimation(reduceMotion ? OWCMotion.reduced : OWCMotion.navigation) {
            groupID = visibleGroups[index].id
        }
    }

    private func estimatedYears(_ proposal: LeavePlanProposal) -> [Int] {
        proposal.caveats.compactMap { caveat in
            if case .holidaysEstimated(let year) = caveat { return year }
            return nil
        }.sorted()
    }
}
