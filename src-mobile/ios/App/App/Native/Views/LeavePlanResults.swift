import SwiftUI

/// One authorized search result set. Selecting dates, previewing calendars
/// and opening details never spend another trial.
struct LeavePlanResults: View {
    let shifts: ShiftSessionStore
    let proposals: [LeavePlanProposal]
    let open: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let groups: [LeavePlanGroup]
    @State private var category: LeavePlanGroup.Category?
    @State private var groupID: Int
    @State private var dates: [Int: Int] = [:]
    @State private var showsPlans = false
    @State private var showsDates = false
    @State private var arrived = false

    init(shifts: ShiftSessionStore, proposals: [LeavePlanProposal], open: @escaping (Int) -> Void) {
        self.shifts = shifts
        self.proposals = proposals
        self.open = open
        let groups = LeavePlanGroup.make(from: proposals)
        self.groups = groups
        _category = State(initialValue: nil)
        _groupID = State(initialValue: groups.first?.id ?? 0)
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
    private var visibleGroups: [LeavePlanGroup] { groups.filter { category == nil || $0.category == category } }
    private var group: LeavePlanGroup? { visibleGroups.first { $0.id == groupID } ?? visibleGroups.first }
    private var selection: Int { group.flatMap { dates[$0.id] ?? $0.id } ?? 0 }
    private var selected: LeavePlanProposal? {
        proposals.indices.contains(selection) ? proposals[selection] : nil
    }
    private var minimumCost: Int? { proposals.map(\.costHalfDays).min() }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let selected {
                    categoryPicker
                    summary(selected)
                        .owcRevealed(arrived, index: 0, reduceMotion: reduceMotion)
                    ForEach(estimatedYears(selected), id: \.self) { year in
                        Label(text.t("holidayEstimatedYearWarning", values: ["year": text.formatYear(year)]),
                              systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(OWCDesign.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    LeavePlanCalendar(shifts: shifts, proposal: selected, showsEstimatedLabel: false)
                        .padding(16)
                        .background(OWCDesign.card, in: .rect(cornerRadius: OWCDesign.cardRadius))
                        .owcRevealed(arrived, index: 1, reduceMotion: reduceMotion)
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selected != nil { detailsAction }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .onAppear { arrived = true }
        .navigationDestination(isPresented: $showsPlans) { planList }
        .navigationDestination(isPresented: $showsDates) {
            if let group {
                LeavePlanDatePicker(shifts: shifts, proposals: proposals,
                                    indices: group.proposalIndices, selection: selection) { index in
                    dates[group.id] = index
                }
            }
        }
    }

    @ViewBuilder
    private var categoryPicker: some View {
        if dynamicTypeSize.isAccessibilitySize || availableCategories.count > 1 {
            Menu {
                filterPicker.pickerStyle(.inline)
            } label: {
                HStack {
                    Text(text.t(category?.titleKey ?? "leaveRecommendedPlans"))
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(OWCDesign.accent)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            filterPicker.pickerStyle(.segmented)
        }
    }

    private var availableCategories: [LeavePlanGroup.Category] {
        LeavePlanGroup.Category.allCases.filter { category in groups.contains { $0.category == category } }
    }

    private var filterPicker: some View {
        Picker(text.t("leaveResultsTitle"), selection: $category) {
            Text(text.t("leaveRecommendedPlans")).tag(Optional<LeavePlanGroup.Category>.none)
            ForEach(LeavePlanGroup.Category.allCases, id: \.self) { category in
                if groups.contains(where: { $0.category == category }) {
                    Text(text.t(category.titleKey)).tag(Optional(category))
                }
            }
        }
        .onChange(of: category) { _, _ in groupID = visibleGroups.first?.id ?? 0 }
    }

    private func summary(_ proposal: LeavePlanProposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            proposalSummary(proposal)
                .accessibilityIdentifier("leave-plan-option-\(selection)")
            Divider()
            Button { showsPlans = true } label: {
                selectionLink(text.t("leaveAllPlans", values: ["count": text.formatCount(visibleGroups.count)]))
            }
            .accessibilityIdentifier("leave-plan-all-plans")
            if let group, group.proposalIndices.count > 1 {
                Button { showsDates = true } label: {
                    selectionLink(text.t("leaveAvailableDates", values: ["count": text.formatCount(group.proposalIndices.count)]))
                }
                .accessibilityIdentifier("leave-plan-dates")
            }
        }
        .buttonStyle(.plain)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OWCDesign.card, in: .rect(cornerRadius: OWCDesign.cardRadius))
    }

    private func selectionLink(_ title: String) -> some View {
        HStack(spacing: 12) {
            Text(title).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward").font(.caption.weight(.semibold))
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(OWCDesign.accent)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func proposalSummary(_ proposal: LeavePlanProposal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { benefit(proposal) }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 4) { benefit(proposal) }
            }
            Text(OWCText.ltrRange(
                shifts.leaveDayLabel(proposal.firstRestDayNumber, template: "yMMMd"),
                shifts.leaveDayLabel(proposal.lastRestDayNumber, template: "yMMMd")
            ))
            .font(.subheadline).foregroundStyle(OWCDesign.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if proposal.costHalfDays == minimumCost {
                Text(text.t("leaveBestValue"))
                    .font(.caption.weight(.medium)).foregroundStyle(OWCDesign.accent)
            }
            if !proposal.caveats.isEmpty {
                if estimatedYears(proposal).isEmpty {
                    Label(text.t("leaveEstimated"), systemImage: "info.circle")
                        .font(.caption).foregroundStyle(OWCDesign.secondary)
                } else {
                    ForEach(estimatedYears(proposal), id: \.self) { year in
                        Text(text.t("leaveEstimatedHolidaysYear", values: ["year": text.formatYear(year)]))
                            .font(.caption).foregroundStyle(OWCDesign.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func benefit(_ proposal: LeavePlanProposal) -> some View {
        Text(proposal.costHalfDays == 0 ? text.t("leaveNoLeaveNeeded")
             : text.t("leaveUses", values: ["days": text.formatDays(Double(proposal.costHalfDays) / 2)]))
            .font(.headline).foregroundStyle(OWCDesign.accent)
            .fixedSize(horizontal: false, vertical: true)
        Text(text.t("leaveDaysOff", count: proposal.fullRestDays))
            .font(.headline).foregroundStyle(OWCDesign.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var detailsAction: some View {
        VStack(spacing: 8) {
            if !shifts.plus.isAuthorized {
                Text(text.t("leaveTrialsLeft", count: shifts.preferences.leavePlannerTrialsLeft))
                    .font(.caption.weight(.medium)).foregroundStyle(OWCDesign.secondary)
                Text(text.t("leaveResultsBrowsingFree"))
                    .font(.caption).foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { open(selection) } label: {
                Text(text.t("leaveViewDetails")).frame(maxWidth: .infinity)
            }
            .buttonStyle(OWCPrimaryButtonStyle())
            .accessibilityIdentifier("leave-plan-details")
        }
        .padding(.horizontal, OWCDesign.pageInset).padding(.vertical, 12)
        .frame(maxWidth: 620).frame(maxWidth: .infinity)
        .background(OWCDesign.page)
    }

    private var planList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(visibleGroups) { candidate in
                    let index = dates[candidate.id] ?? candidate.id
                    if proposals.indices.contains(index) {
                        Button {
                            groupID = candidate.id
                            showsPlans = false
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                proposalSummary(proposals[index])
                                if candidate.id == group?.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(OWCDesign.accent)
                                        .accessibilityHidden(true)
                                }
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(candidate.id == group?.id ? .isSelected : [])
                        .accessibilityIdentifier("leave-plan-choice-\(candidate.id)")
                        .id(candidate.id)
                    }
                }
            }
            .onAppear { proxy.scrollTo(groupID, anchor: .center) }
        }
        .navigationTitle(text.t("leaveAllPlans", values: ["count": text.formatCount(visibleGroups.count)]))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func estimatedYears(_ proposal: LeavePlanProposal) -> [Int] {
        proposal.caveats.compactMap { caveat in
            if case .holidaysEstimated(let year) = caveat { return year }
            return nil
        }.sorted()
    }
}
