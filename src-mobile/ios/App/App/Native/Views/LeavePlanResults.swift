import SwiftUI

/// One authorized search result set. Selecting dates, previewing calendars
/// and opening details never spend another trial.
struct LeavePlanResults: View {
    let shifts: ShiftSessionStore
    let proposals: [LeavePlanProposal]
    let searchContext: LeavePlanSearchContext?
    let adjustConditions: () -> Void
    let open: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let groups: [LeavePlanGroup]
    @State private var category: LeavePlanGroup.Category?
    @State private var groupID: Int
    @State private var dates: [Int: Int] = [:]
    @State private var showsPlans = false
    @State private var showsDates = false
    @State private var arrived = false

    init(shifts: ShiftSessionStore, proposals: [LeavePlanProposal], searchContext: LeavePlanSearchContext?,
         adjustConditions: @escaping () -> Void, open: @escaping (Int) -> Void) {
        self.shifts = shifts
        self.proposals = proposals
        self.searchContext = searchContext
        self.adjustConditions = adjustConditions
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
    private var group: LeavePlanGroup? { groups.first { $0.id == groupID } ?? groups.first }
    private var selection: Int { group.flatMap { dates[$0.id] ?? $0.id } ?? 0 }
    private var selected: LeavePlanProposal? {
        proposals.indices.contains(selection) ? proposals[selection] : nil
    }
    private var minimumCost: Int? { proposals.map(\.costHalfDays).min() }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let selected {
                    summary(selected)
                        .owcRevealed(arrived, index: 0, reduceMotion: reduceMotion)
                    ForEach(estimatedYears(selected), id: \.self) { year in
                        HStack(alignment: .center, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .accessibilityHidden(true)
                            Text(text.t("holidayEstimatedYearWarning", values: ["year": text.formatYear(year)]))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.caption)
                        .foregroundStyle(OWCDesign.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .owcRevealed(arrived, index: 1, reduceMotion: reduceMotion)
                    }
                    LeavePlanCalendar(shifts: shifts, proposal: selected, showsEstimatedLabel: false)
                        .padding(16)
                        .background(OWCDesign.card, in: .rect(cornerRadius: OWCDesign.cardRadius))
                        .owcRevealed(arrived, index: estimatedYears(selected).isEmpty ? 1 : 2, reduceMotion: reduceMotion)
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

    private func filterTitle(_ value: LeavePlanGroup.Category?) -> String {
        let count = groups.filter { value == nil || $0.category == value }.count
        return text.t("leaveFilterCount", values: [
            "category": text.t(value?.titleKey ?? "leaveAllPlanTypes"),
            "count": text.formatCount(count),
        ])
    }

    private var categoryPicker: some View {
        Menu {
            Picker(text.t("leaveResultsTitle"), selection: $category) {
                Text(filterTitle(nil)).tag(Optional<LeavePlanGroup.Category>.none)
                ForEach(LeavePlanGroup.Category.allCases, id: \.self) { value in
                    Text(filterTitle(value)).tag(Optional(value))
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 12) {
                Text(filterTitle(category)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(OWCDesign.accent)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("leave-plan-filter")
    }

    private func summary(_ proposal: LeavePlanProposal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            proposalSummary(proposal)
                .accessibilityIdentifier("leave-plan-option-\(selection)")
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
            Divider().padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 0) {
                Button { category = nil; showsPlans = true } label: {
                    selectionLink(text.t("leaveAllPlans", values: ["count": text.formatCount(groups.count)]))
                }
                .accessibilityIdentifier("leave-plan-all-plans")
                if let group, group.proposalIndices.count > 1 {
                    Button { showsDates = true } label: {
                        selectionLink(text.t("leaveAvailableDates", values: ["count": text.formatCount(group.proposalIndices.count)]))
                    }
                    .accessibilityIdentifier("leave-plan-dates")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
        .buttonStyle(.plain)
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
                Section { categoryPicker }
                if visibleGroups.isEmpty {
                    emptyFilter
                }
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
            .onChange(of: category) { _, _ in
                if visibleGroups.contains(where: { $0.id == groupID }) { proxy.scrollTo(groupID, anchor: .center) }
            }
        }
        .navigationTitle(text.t("leaveAllPlans", values: ["count": text.formatCount(groups.count)]))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyFilter: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text(text.t("leaveFilterNoResults")).font(.headline)
                if let searchContext {
                    VStack(alignment: .leading, spacing: 6) {
                        switch searchContext.goal {
                        case .restAtLeast(let days):
                            Text(text.t("leaveCurrentGoalRest", values: ["days": text.formatCount(days)]))
                        case .leaveAtMost(let halfDays):
                            Text(text.t("leaveCurrentGoalBudget", values: ["days": halfDaysNumber(halfDays)]))
                        }
                        Text(text.t("leaveAvailableBudget", values: ["days": halfDaysNumber(searchContext.availableHalfDays)]))
                        Text(OWCText.ltrRange(
                            shifts.leaveDayLabel(searchContext.fromDayNumber, template: "yMMMd"),
                            shifts.leaveDayLabel(searchContext.throughDayNumber, template: "yMMMd")
                        ))
                    }
                    .font(.subheadline).foregroundStyle(OWCDesign.secondary)
                }
                Text(text.t("leaveFilterNoResultsHint"))
                    .font(.subheadline).foregroundStyle(OWCDesign.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 8)
            Button(text.t("leaveAdjustConditions"), action: adjustConditions)
                .accessibilityIdentifier("leave-plan-adjust-conditions")
            Button(text.t("leaveViewAllPlans")) { category = nil }
        }
    }

    // These complete sentences own the unit; insert only the localized number.
    private func halfDaysNumber(_ halfDays: Int) -> String {
        (Double(halfDays) / 2).formatted(.number.precision(.fractionLength(0...1)).locale(shifts.preferences.locale))
    }

    private func estimatedYears(_ proposal: LeavePlanProposal) -> [Int] {
        proposal.caveats.compactMap { caveat in
            if case .holidaysEstimated(let year) = caveat { return year }
            return nil
        }.sorted()
    }
}
