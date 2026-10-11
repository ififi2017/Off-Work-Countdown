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
    @State private var listWidth: CGFloat = 390
    @State private var showsListDates = false
    @State private var listDatesGroupID: Int?

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
                    LeaveCard {
                        LeaveBreakCalendar(shifts: shifts, proposal: selected)
                    }
                    .owcRevealed(arrived, index: 1, reduceMotion: reduceMotion)
                    OWCGroupCard {
                        VStack(alignment: .leading, spacing: 0) {
                            Button { category = nil; showsPlans = true } label: {
                                selectionLink(text.t("leaveAllPlans", values: ["count": text.formatCount(groups.count)]))
                            }
                            .accessibilityIdentifier("leave-plan-all-plans")
                            if let group, group.proposalIndices.count > 1 {
                                Divider()
                                Button { showsDates = true } label: {
                                    selectionLink(text.t("leaveAvailableDates", values: ["count": text.formatCount(group.proposalIndices.count)]))
                                }
                                .accessibilityIdentifier("leave-plan-dates")
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 18)
                    }
                    .owcRevealed(arrived, index: 2, reduceMotion: reduceMotion)
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
        .onAppear {
            arrived = true
            #if DEBUG
            // `-ios.native.qaLeaveScreen plans|dates|detail` opens one step further.
            switch UserDefaults.standard.string(forKey: "ios.native.qaLeaveScreen") {
            case "plans": showsPlans = true
            case "dates":
                if let regular = groups.first(where: { $0.proposalIndices.count > 1 }) {
                    groupID = regular.id
                    showsDates = true
                }
            case "detail": open(selection)
            default: break
            }
            #endif
        }
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

    /// The cost first, then what it buys, in green, then when.
    private func summary(_ proposal: LeavePlanProposal) -> some View {
        LeaveCard {
            Text(shifts.leaveCost(proposal))
                .font(LeaveStyle.title)
                .foregroundStyle(OWCDesign.primary)
                .padding(.bottom, 4)
            LeaveHeroNumber(full: text.t("leaveDaysOff", count: proposal.fullRestDays),
                            number: text.formatCount(proposal.fullRestDays),
                            color: OWCDesign.recordsHoliday)
            Text([shifts.leaveRange(proposal), shifts.leaveHolidayName(proposal)].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(OWCDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            if proposal.costHalfDays == minimumCost, proposal.costHalfDays > 0 {
                Text(text.t("leaveBestValue"))
                    .font(.caption.weight(.semibold)).foregroundStyle(OWCDesign.accent)
                    .padding(.top, 6)
            }
            ForEach(estimatedYears(proposal), id: \.self) { year in
                Label(text.t("leaveEstimatedHolidaysYear", values: ["year": text.formatYear(year)]),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(OWCDesign.secondary)
                    .padding(.top, 6)
            }
            if !proposal.caveats.isEmpty, estimatedYears(proposal).isEmpty {
                Label(text.t("leaveEstimated"), systemImage: "info.circle")
                    .font(.caption).foregroundStyle(OWCDesign.secondary)
                    .padding(.top, 6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("leave-plan-option-\(selection)")
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

    /// Fewest leave days first; the cheapest is marked.
    private var sortedVisibleGroups: [LeavePlanGroup] {
        visibleGroups.sorted { lhs, rhs in
            let a = proposals[dates[lhs.id] ?? lhs.id], b = proposals[dates[rhs.id] ?? rhs.id]
            return a.costHalfDays == b.costHalfDays
                ? a.firstRestDayNumber < b.firstRestDayNumber : a.costHalfDays < b.costHalfDays
        }
    }

    private var planList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Picker(text.t("leaveResultsTitle"), selection: $category) {
                        Text(filterTitle(nil)).tag(Optional<LeavePlanGroup.Category>.none)
                        ForEach(LeavePlanGroup.Category.allCases, id: \.self) { value in
                            Text(filterTitle(value)).tag(Optional(value))
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("leave-plan-filter")
                    if visibleGroups.isEmpty {
                        LeaveCard { emptyFilterContent }
                    } else {
                        let rows = sortedVisibleGroups
                        let longest = rows.map { LeaveDayStrip.kinds(proposals[dates[$0.id] ?? $0.id]).count }.max() ?? 1
                        LeaveCard {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { position, candidate in
                                if position > 0 { Divider() }
                                planRow(candidate, longest: longest)
                                    .id(candidate.id)
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            LeaveDayStrip.legend(text)
                            Text(text.t("leaveSortedByLeast"))
                                .font(.caption)
                                .foregroundStyle(OWCDesign.secondary)
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(OWCDesign.pageInset)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .onGeometryChange(for: CGFloat.self) { min(620, $0.size.width) } action: { listWidth = $0 }
            .background(OWCDesign.page)
            .onAppear { proxy.scrollTo(groupID, anchor: .center) }
        }
        .navigationTitle(text.t("leaveAllPlans", values: ["count": text.formatCount(groups.count)]))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showsListDates) {
            if let datesGroup = groups.first(where: { $0.id == listDatesGroupID }) {
                LeavePlanDatePicker(shifts: shifts, proposals: proposals,
                                    indices: datesGroup.proposalIndices,
                                    selection: dates[datesGroup.id] ?? datesGroup.id) { index in
                    dates[datesGroup.id] = index
                    groupID = datesGroup.id
                }
            }
        }
    }

    private func planRow(_ candidate: LeavePlanGroup, longest: Int) -> some View {
        let index = dates[candidate.id] ?? candidate.id
        let proposal = proposals[index]
        let kinds = LeaveDayStrip.kinds(proposal)
        // Page and card insets, then the selection mark's column.
        let available = max(120, listWidth - OWCDesign.pageInset * 2 - 36 - 36)
        let cell = min(22, (available - CGFloat(longest - 1) * 2) / CGFloat(max(1, longest)))
        return Button {
            groupID = candidate.id
            showsPlans = false
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(text.t("leaveDaysOff", count: proposal.fullRestDays))
                            .font(.headline)
                            .foregroundStyle(OWCDesign.primary)
                        Text(shifts.leaveCost(proposal))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(OWCDesign.accent)
                    }
                    Text([shifts.leaveRange(proposal), shifts.leaveHolidayName(proposal)].compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                        .padding(.top, 2)
                    LeaveDayStrip(kinds: kinds, cellWidth: cell)
                        .padding(.top, 10)
                    HStack(spacing: 10) {
                        if proposal.costHalfDays == minimumCost {
                            Text(text.t("leaveBestValue")).fontWeight(.semibold).foregroundStyle(OWCDesign.accent)
                        }
                        if !estimatedYears(proposal).isEmpty {
                            Text(text.t("leaveEstimatedHolidaysShort")).foregroundStyle(OWCDesign.secondary)
                        } else if !proposal.caveats.isEmpty {
                            Text(text.t("leaveEstimated")).foregroundStyle(OWCDesign.secondary)
                        }
                        if candidate.proposalIndices.count > 1 {
                            Button {
                                listDatesGroupID = candidate.id
                                showsListDates = true
                            } label: {
                                Text("\(text.t("leaveAvailableDates", values: ["count": text.formatCount(candidate.proposalIndices.count)])) \(Image(systemName: "chevron.forward"))")
                                    .fontWeight(.medium)
                                    .foregroundStyle(OWCDesign.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .font(.caption)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if candidate.id == group?.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(OWCDesign.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(candidate.id == group?.id ? .isSelected : [])
        .accessibilityIdentifier("leave-plan-choice-\(candidate.id)")
    }

    private var emptyFilterContent: some View {
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
            Divider()
            Button(text.t("leaveAdjustConditions"), action: adjustConditions)
                .accessibilityIdentifier("leave-plan-adjust-conditions")
                .frame(minHeight: 44)
            Button(text.t("leaveViewAllPlans")) { category = nil }
                .frame(minHeight: 44)
        }
        .fixedSize(horizontal: false, vertical: true)
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
