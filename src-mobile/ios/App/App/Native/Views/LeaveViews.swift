import SwiftUI

// Plan 020 §2: leave balances, the leave planner and adopted plans.

extension ShiftSessionStore {
    /// The settings row's value: what is left across every balance.
    var leaveSummaryLabel: String? {
        let total = leaveBudgets.reduce(0) { $0 + $1.availableHalfDays }
        return records.state.leaveBalances.isEmpty ? nil : text.formatDays(Double(total) / 2)
    }

    func leaveBalanceName(_ balance: LeaveBalance) -> String {
        if let name = balance.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        return text.t(balance.kind.titleKey)
    }

    func leaveDayLabel(_ dayNumber: Int, template: String = "MMMdEEE") -> String {
        let civil = CivilZone.civilDate(dayNumber: dayNumber)
        return text.formatCivilDate(year: civil.year, month: civil.month, day: civil.day, template: template)
    }

    func leaveDayLabel(dayKey: String, template: String = "MMMdEEE") -> String {
        ExtendedScheduleResolver.dayNumber(dayKey: dayKey).map { leaveDayLabel($0, template: template) } ?? dayKey
    }

    func leaveTime(_ ms: Double) -> String {
        queries.formatRecordsTime(Date(timeIntervalSince1970: ms / 1_000))
    }
}

extension LeaveBalance.Kind {
    var titleKey: String {
        switch self {
        case .annual: "leaveKindAnnual"
        case .compensatory: "leaveKindCompensatory"
        case .custom: "leaveKindCustom"
        }
    }

    var symbol: String {
        switch self {
        case .annual: "sun.max"
        case .compensatory: "arrow.uturn.backward.circle"
        case .custom: "tag"
        }
    }
}

extension LeavePortion {
    var titleKey: String {
        switch self {
        case .whole: "leaveWhole"
        case .firstHalf: "leaveFirstHalf"
        case .secondHalf: "leaveSecondHalf"
        }
    }
}

// MARK: - Page

struct LeaveView: View {
    @Environment(SceneState.self) private var scene
    let shifts: ShiftSessionStore
    let actions: RecordsActions
    @State private var editing: LeaveBalanceEditing?
    @State private var isPlanning = false
    @State private var undoing: UUID?

    private var text: AppText { shifts.text }
    private var trialsLeft: Int { shifts.preferences.leavePlannerTrialsLeft }

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OWCGroupCard {
                    Button(action: plan) {
                        OWCRow(icon: "calendar.badge.plus", title: text.t("leavePlanAction"),
                               subtitle: planSubtitle, isLast: true, centersVertically: true) {
                            OWCDetailAccessory(text: nil)
                        }
                    }
                    .buttonStyle(OWCRowButtonStyle())
                }
                .padding(.top, 14)

                OWCSectionHeader(title: text.t("leaveBalancesSection"))
                    .padding(.top, OWCDesign.sectionGap)
                OWCGroupCard {
                    ForEach(shifts.records.state.leaveBalances) { balance in
                        Button { editing = .init(balance: balance, isNew: false) } label: {
                            OWCRow(icon: balance.kind.symbol, title: shifts.leaveBalanceName(balance),
                                   subtitle: validityLabel(balance), centersVertically: true) {
                                Text(text.t("leaveAvailable", values: [
                                    "count": text.formatDays(Double(shifts.availableLeaveHalfDays(for: balance)) / 2),
                                ]))
                                .font(.body.monospacedDigit())
                                .foregroundStyle(OWCDesign.secondary)
                            }
                        }
                        .buttonStyle(OWCRowButtonStyle())
                    }
                    Button { editing = .init(balance: Self.newBalance(), isNew: true) } label: {
                        OWCRow(icon: "plus", title: text.t("leaveAddBalance"), isLast: true) { EmptyView() }
                    }
                    .buttonStyle(OWCRowButtonStyle())
                }

                let plans = shifts.adoptedLeavePlans
                if !plans.isEmpty {
                    OWCSectionHeader(title: text.t("leaveAdoptedPlans"))
                        .padding(.top, OWCDesign.sectionGap)
                    OWCGroupCard {
                        ForEach(Array(plans.enumerated()), id: \.element.id) { index, plan in
                            Button { undoing = plan.id } label: {
                                OWCRow(icon: "airplane", title: planTitle(plan.days),
                                       subtitle: text.t("leaveUses", values: ["days": planLeave(plan.days)]),
                                       isLast: index == plans.count - 1, centersVertically: true) {
                                    Text(text.t("leaveUndoPlan"))
                                        .font(.subheadline)
                                        .foregroundStyle(OWCDesign.accent)
                                }
                            }
                            .buttonStyle(OWCRowButtonStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OWCDesign.page)
        .owcDetailBack(title: text.t("settings"), pageTitle: text.t("leaveTitle"))
        .sheet(item: $editing) { editing in
            LeaveBalanceEditor(shifts: shifts, editing: editing)
        }
        .sheet(isPresented: $isPlanning) {
            LeavePlannerSheet(shifts: shifts, actions: actions)
        }
        .confirmationDialog(
            text.t("leaveUndoPlan"),
            isPresented: Binding(get: { undoing != nil }, set: { if !$0 { undoing = nil } }),
            titleVisibility: .visible,
            presenting: undoing
        ) { id in
            Button(text.t("leaveUndoPlan"), role: .destructive) {
                actions.undoLeavePlan(id)
            }
        } message: { _ in
            Text(text.t("leaveUndoConfirm"))
        }
    }

    private var planSubtitle: String? {
        guard !shifts.plus.isAuthorized else { return nil }
        return trialsLeft > 0 ? text.t("leaveTrialsLeft", count: trialsLeft) : text.t("leaveTrialsUsedUp")
    }

    private func plan() {
        if shifts.plus.isAuthorized || trialsLeft > 0 {
            isPlanning = true
        } else {
            scene.paywallSheet = .leavePlanning
        }
    }

    private func validityLabel(_ balance: LeaveBalance) -> String? {
        balance.validThroughDayKey.map {
            text.t("leaveValidUntilDate", values: ["date": shifts.leaveDayLabel(dayKey: $0, template: "yMMMd")])
        }
    }

    private func planTitle(_ days: [LeaveDay]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        let start = shifts.leaveDayLabel(dayKey: first.dayKey, template: "MMMd")
        return first.dayKey == last.dayKey
            ? start
            : OWCText.ltrRange(start, shifts.leaveDayLabel(dayKey: last.dayKey, template: "MMMd"))
    }

    private func planLeave(_ days: [LeaveDay]) -> String {
        text.formatDays(Double(days.reduce(0) { $0 + $1.portion.halfDays }) / 2)
    }

    private static func newBalance() -> LeaveBalance {
        LeaveBalance(id: UUID(), kind: .annual, name: nil, entitledHalfDays: 10, usedHalfDays: 0,
                     validFromDayKey: nil, validThroughDayKey: nil)
    }
}

struct LeaveBalanceEditing: Identifiable {
    var balance: LeaveBalance
    var isNew: Bool
    var id: UUID { balance.id }
}

// MARK: - Balance editor

private struct LeaveBalanceEditor: View {
    @Environment(\.dismiss) private var dismiss
    let shifts: ShiftSessionStore
    let editing: LeaveBalanceEditing
    @State private var draft: LeaveBalance
    @State private var entitledText: String
    @State private var usedText: String
    @State private var hasStart: Bool
    @State private var hasEnd: Bool
    @State private var start: Date
    @State private var end: Date

    init(shifts: ShiftSessionStore, editing: LeaveBalanceEditing) {
        self.shifts = shifts
        self.editing = editing
        let balance = editing.balance
        let calendar = shifts.preferences.recordsCalendar
        let today = calendar.startOfDay(for: .now)
        func date(_ key: String?) -> Date? { key.flatMap { RecordJSON.date(fromDayKey: $0, calendar: calendar) } }
        _draft = State(initialValue: balance)
        _entitledText = State(initialValue: Self.text(balance.entitledHalfDays))
        _usedText = State(initialValue: Self.text(balance.usedHalfDays))
        _hasStart = State(initialValue: balance.validFromDayKey != nil)
        _hasEnd = State(initialValue: balance.validThroughDayKey != nil)
        _start = State(initialValue: date(balance.validFromDayKey) ?? today)
        _end = State(initialValue: date(balance.validThroughDayKey)
            ?? calendar.date(byAdding: .year, value: 1, to: today) ?? today)
    }

    private var text: AppText { shifts.text }
    private var calendar: Calendar { shifts.preferences.recordsCalendar }
    private var isInUse: Bool { shifts.records.state.leaveDays.contains { $0.uses.contains { $0.budgetID == draft.id } } }

    private static func text(_ halfDays: Int) -> String {
        halfDays % 2 == 0 ? String(halfDays / 2) : String(Double(halfDays) / 2)
    }

    /// Whole or half days only, so "3.5" is 7 and "3.4" is refused.
    private static func halfDays(_ text: String) -> Int? {
        guard let value = NumberInput.parse(text), value >= 0 else { return nil }
        let halves = value * 2
        guard halves.rounded() == halves, halves <= Double(LeaveBalance.maximumHalfDays) else { return nil }
        return Int(halves)
    }

    private var result: LeaveBalance? {
        guard let entitled = Self.halfDays(entitledText), let used = Self.halfDays(usedText) else { return nil }
        var balance = draft
        balance.entitledHalfDays = entitled
        balance.usedHalfDays = used
        balance.name = balance.kind == .custom ? balance.name?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        balance.validFromDayKey = hasStart ? RecordJSON.dayKey(start, calendar: calendar) : nil
        balance.validThroughDayKey = hasEnd ? RecordJSON.dayKey(end, calendar: calendar) : nil
        return balance.isValid ? balance : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(text.t("leaveBalancesSection"), selection: $draft.kind) {
                        Text(text.t("leaveKindAnnual")).tag(LeaveBalance.Kind.annual)
                        Text(text.t("leaveKindCompensatory")).tag(LeaveBalance.Kind.compensatory)
                        Text(text.t("leaveKindCustom")).tag(LeaveBalance.Kind.custom)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if draft.kind == .custom {
                        TextField(text.t("leaveBalanceNamePlaceholder"), text: Binding(
                            get: { draft.name ?? "" },
                            set: { draft.name = String($0.prefix(LeaveBalance.maximumNameLength)) }
                        ))
                        .submitLabel(.done)
                    }
                }

                Section {
                    amountRow(text.t("leaveEntitled"), text: $entitledText)
                    amountRow(text.t("leaveUsedBefore"), text: $usedText)
                } footer: {
                    if Self.halfDays(entitledText) == nil || Self.halfDays(usedText) == nil {
                        Label(text.t("leaveHalfDayInvalid"), systemImage: "exclamationmark.circle")
                            .foregroundStyle(OWCDesign.warning)
                    } else {
                        Text(text.t("leaveUsedBeforeNote"))
                    }
                }

                Section {
                    Toggle(text.t("leaveValidFrom"), isOn: $hasStart.animation())
                        .tint(OWCDesign.accent)
                    if hasStart {
                        DatePicker(text.t("leaveValidFrom"), selection: $start, displayedComponents: .date)
                            .labelsHidden()
                    }
                    Toggle(text.t("leaveValidUntil"), isOn: $hasEnd.animation())
                        .tint(OWCDesign.accent)
                    if hasEnd {
                        DatePicker(text.t("leaveValidUntil"), selection: $end,
                                   in: (hasStart ? start : .distantPast)..., displayedComponents: .date)
                            .labelsHidden()
                    }
                }
                .environment(\.calendar, calendar)
                .environment(\.timeZone, calendar.timeZone)

                if !editing.isNew {
                    Section {
                        Button(text.t("leaveDeleteBalance"), role: .destructive) {
                            shifts.records.submitCommand { [shifts] in
                                shifts.records.erase(.leaveBalance, key: editing.balance.id.uuidString)
                            }
                            dismiss()
                        }
                        .disabled(isInUse)
                    } footer: {
                        if isInUse { Text(text.t("leaveBalanceInUse")) }
                    }
                }
            }
            .navigationTitle(text.t(editing.isNew ? "leaveNewBalance" : "leaveEditBalance"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(text.t("cancelAction"), role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(text.t("saveAction")) {
                        guard let result else { return }
                        shifts.records.submitCommand { [shifts] in shifts.records.upsertLeaveBalance(result) }
                        dismiss()
                    }
                    .disabled(result == nil)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func amountRow(_ title: String, text binding: Binding<String>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField("0", text: binding)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 90)
                Text(text.t("leaveDaysUnit"))
                    .foregroundStyle(OWCDesign.secondary)
            }
        }
    }
}

// MARK: - Planner

private struct LeavePlannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let shifts: ShiftSessionStore
    let actions: RecordsActions
    @State private var path: [LeavePlannerStep] = []
    @State private var goalIsRest = true
    @State private var restDays = 7
    @State private var leaveHalfDays = 6
    @State private var from = Date.now
    @State private var through = Date.now
    @State private var selected: Set<UUID> = []
    @State private var isSearching = false
    @State private var proposals: [LeavePlanProposal] = []
    @State private var didLoad = false

    private var text: AppText { shifts.text }
    private var calendar: Calendar { shifts.preferences.recordsCalendar }
    private var window: ClosedRange<Int>? { shifts.leavePlanningWindow() }
    private var budgets: [LeaveBudget] { shifts.leaveBudgets }
    private var selectedHalfDays: Int {
        budgets.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.availableHalfDays }
    }

    private var request: ShiftSessionStore.LeavePlanRequest? {
        guard let window,
              let first = LeavePlannerSchedule.dayNumber(of: from, calendar: calendar),
              let last = LeavePlannerSchedule.dayNumber(of: through, calendar: calendar)
        else { return nil }
        let range = max(first, window.lowerBound)...min(max(last, first), window.upperBound)
        return .init(
            goal: goalIsRest ? .restAtLeast(days: restDays) : .leaveAtMost(halfDays: leaveHalfDays),
            fromDayNumber: range.lowerBound,
            throughDayNumber: range.upperBound,
            budgetIDs: Array(selected)
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    Picker(text.t("leavePlanAction"), selection: $goalIsRest) {
                        Text(text.t("leaveGoalRest")).tag(true)
                        Text(text.t("leaveGoalBudget")).tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if goalIsRest {
                        Stepper(value: $restDays, in: 2...60) {
                            LabeledContent(text.t("leaveGoalRest")) {
                                Text(text.t("leaveAtLeast", values: ["days": text.formatDays(Double(restDays))]))
                                    .monospacedDigit()
                            }
                        }
                    } else {
                        Stepper(value: $leaveHalfDays, in: 1...max(1, selectedHalfDays)) {
                            LabeledContent(text.t("leaveGoalBudget")) {
                                Text(text.t("leaveUpTo", values: ["days": text.formatDays(Double(leaveHalfDays) / 2)]))
                                    .monospacedDigit()
                            }
                        }
                        .disabled(selectedHalfDays == 0)
                    }
                }

                Section {
                    DatePicker(text.t("leaveRangeStart"), selection: $from, in: windowDates, displayedComponents: .date)
                    DatePicker(text.t("leaveRangeEnd"), selection: $through, in: max(from, windowDates.lowerBound)...windowDates.upperBound,
                               displayedComponents: .date)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let window {
                            Text(text.t("leaveRangeFooter", values: [
                                "start": shifts.leaveDayLabel(window.lowerBound, template: "yMMMd"),
                                "end": shifts.leaveDayLabel(window.upperBound, template: "yMMMd"),
                            ]))
                        }
                        ForEach(missingYears, id: \.self) { year in
                            Label(text.t("leaveMainlandHolidaysMissing", values: ["year": String(year)]),
                                  systemImage: "info.circle")
                        }
                    }
                }
                .environment(\.calendar, calendar)
                .environment(\.timeZone, calendar.timeZone)

                Section {
                    if shifts.records.state.leaveBalances.isEmpty {
                        Text(text.t("leaveNoBalancesHint"))
                            .foregroundStyle(OWCDesign.secondary)
                    }
                    ForEach(shifts.records.state.leaveBalances) { balance in
                        let available = shifts.availableLeaveHalfDays(for: balance)
                        Toggle(isOn: Binding(
                            get: { selected.contains(balance.id) },
                            set: { if $0 { selected.insert(balance.id) } else { selected.remove(balance.id) } }
                        )) {
                            LabeledContent(shifts.leaveBalanceName(balance)) {
                                Text(text.t("leaveAvailable", values: ["count": text.formatDays(Double(available) / 2)]))
                                    .monospacedDigit()
                            }
                        }
                        .tint(OWCDesign.accent)
                        .disabled(available == 0)
                    }
                } header: {
                    Text(text.t("leaveUseBalances"))
                } footer: {
                    if !shifts.plus.isAuthorized {
                        Text(shifts.preferences.leavePlannerTrialsLeft > 0
                             ? text.t("leaveTrialsLeft", count: shifts.preferences.leavePlannerTrialsLeft)
                             : text.t("leaveTrialsUsedUp"))
                    }
                }
            }
            .navigationTitle(text.t("leavePlanAction"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(text.t("cancelAction"), role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSearching {
                        ProgressView()
                    } else {
                        Button(text.t("leaveFind"), action: search)
                            .disabled(request == nil || !canSearch)
                    }
                }
            }
            .navigationDestination(for: LeavePlannerStep.self) { step in
                switch step {
                case .results:
                    LeavePlanResults(shifts: shifts, proposals: proposals) { path.append(.detail($0)) }
                case .detail(let index):
                    LeavePlanDetail(shifts: shifts, actions: actions, proposal: proposals[index]) { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear(perform: load)
    }

    private var canSearch: Bool {
        shifts.plus.isAuthorized || shifts.preferences.leavePlannerTrialsLeft > 0
    }

    private var windowDates: ClosedRange<Date> {
        guard let window,
              let lower = date(window.lowerBound),
              let upper = date(window.upperBound)
        else { return Date.now...Date.now }
        return lower...upper
    }

    private var missingYears: [Int] {
        guard let request else { return [] }
        return shifts.missingMainlandHolidayYears(in: request.fromDayNumber...request.throughDayNumber)
    }

    private func date(_ dayNumber: Int) -> Date? {
        RecordJSON.date(fromDayKey: ExtendedScheduleEditing.dayKey(dayNumber: dayNumber), calendar: calendar)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        from = windowDates.lowerBound
        through = windowDates.upperBound
        selected = Set(budgets.filter { $0.availableHalfDays > 0 }.map(\.id))
        leaveHalfDays = min(max(1, selectedHalfDays), 6)
    }

    private func search() {
        guard let request, canSearch else { return }
        isSearching = true
        Task {
            let found = await shifts.findLeavePlans(request)
            proposals = found
            isSearching = false
            // A plan counts once it shows options; nothing found costs nothing.
            if !found.isEmpty, !shifts.plus.isAuthorized {
                shifts.preferences.countLeavePlannerTrial(request: request.fingerprint)
            }
            path = [.results]
        }
    }
}

private enum LeavePlannerStep: Hashable {
    case results
    case detail(Int)
}

private struct LeavePlanResults: View {
    let shifts: ShiftSessionStore
    let proposals: [LeavePlanProposal]
    let open: (Int) -> Void

    private var text: AppText { shifts.text }

    var body: some View {
        List {
            if proposals.isEmpty {
                Text(text.t("leaveNoResults"))
                    .foregroundStyle(OWCDesign.secondary)
            }
            ForEach(Array(proposals.enumerated()), id: \.offset) { index, proposal in
                Button { open(index) } label: {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(OWCText.ltrRange(
                                shifts.leaveDayLabel(proposal.firstRestDayNumber, template: "MMMd"),
                                shifts.leaveDayLabel(proposal.lastRestDayNumber, template: "MMMd")
                            ))
                            .font(.headline)
                            .foregroundStyle(OWCDesign.primary)
                            Text(text.t("leaveDaysOff", count: proposal.fullRestDays))
                                .foregroundStyle(OWCDesign.primary)
                            Text(leaveCost(proposal))
                                .font(.subheadline)
                                .foregroundStyle(OWCDesign.secondary)
                            if !proposal.caveats.isEmpty {
                                Label(text.t("leaveEstimated"), systemImage: "info.circle")
                                    .font(.footnote)
                                    .foregroundStyle(OWCDesign.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(OWCDesign.tertiary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(text.t("leaveResultsTitle"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func leaveCost(_ proposal: LeavePlanProposal) -> String {
        proposal.costHalfDays == 0
            ? text.t("leaveNoLeaveNeeded")
            : text.t("leaveUses", values: ["days": text.formatDays(Double(proposal.costHalfDays) / 2)])
    }
}

private struct LeavePlanDetail: View {
    let shifts: ShiftSessionStore
    let actions: RecordsActions
    let proposal: LeavePlanProposal
    let onAdopted: () -> Void
    @State private var failed = false
    @State private var isAdopting = false

    private var text: AppText { shifts.text }

    var body: some View {
        Form {
            Section {
                LeavePlanCalendar(shifts: shifts, proposal: proposal)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            } header: {
                Text(text.t("leaveDaysOff", count: proposal.fullRestDays))
            }

            if !proposal.items.isEmpty {
                Section(text.t("leaveRequests")) {
                    ForEach(proposal.items, id: \.dayKey) { item in
                        LabeledContent {
                            Text(itemTime(item)).monospacedDigit()
                        } label: {
                            Text(shifts.leaveDayLabel(item.dayNumber))
                            Text(itemDetail(item))
                        }
                    }
                }
                Section(text.t("leaveUseBalances")) {
                    ForEach(proposal.uses, id: \.budgetID) { use in
                        if let balance = shifts.records.state.leaveBalances.first(where: { $0.id == use.budgetID }) {
                            let left = shifts.availableLeaveHalfDays(for: balance) - use.halfDays
                            LabeledContent(shifts.leaveBalanceName(balance)) {
                                Text(text.t("leaveBalanceAfter", values: [
                                    "used": text.formatDays(Double(use.halfDays) / 2),
                                    "left": text.formatDays(Double(max(0, left)) / 2),
                                ]))
                                .monospacedDigit()
                            }
                        }
                    }
                }
            }

            Section {
                if let end = proposal.lastShiftEndAtMs {
                    LabeledContent(text.t("leaveLastShiftEnds"), value: timeLabel(end))
                }
                if let start = proposal.nextShiftStartAtMs {
                    LabeledContent(text.t("leaveNextShiftStarts"), value: timeLabel(start))
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(caveatKeys, id: \.self) { key in
                        Label(key.label(text), systemImage: "info.circle")
                    }
                }
            }

            if !proposal.items.isEmpty {
                Section {
                    Button(action: adopt) {
                        Text(text.t("leaveAdopt"))
                    }
                    .buttonStyle(OWCPrimaryButtonStyle())
                    .disabled(isAdopting)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle(OWCText.ltrRange(
            shifts.leaveDayLabel(proposal.firstRestDayNumber, template: "MMMd"),
            shifts.leaveDayLabel(proposal.lastRestDayNumber, template: "MMMd")
        ))
        .navigationBarTitleDisplayMode(.inline)
        .alert(text.t("leaveAdoptFailed"), isPresented: $failed) {
            Button(text.t("close"), role: .cancel) {}
        }
        .sensoryFeedback(.success, trigger: isAdopting) { _, adopting in !adopting && !failed }
    }

    private enum Caveat: Hashable {
        case missingHolidays(Int)
        case carriedOver
        case unassigned

        func label(_ text: AppText) -> String {
            switch self {
            case .missingHolidays(let year): text.t("leaveEstimatedYear", values: ["year": String(year)])
            case .carriedOver: text.t("leaveCarriedOverCaveat")
            case .unassigned: text.t("leaveUnassignedCaveat")
            }
        }
    }

    private var caveatKeys: [Caveat] {
        proposal.caveats.map { caveat -> Caveat in
            switch caveat {
            case .holidaysNotIncluded(let year): .missingHolidays(year)
            case .carriedOverRoster: .carriedOver
            case .unassigned: .unassigned
            }
        }
        .sorted { "\($0)" < "\($1)" }
    }

    private func timeLabel(_ ms: Double) -> String {
        let zone = CivilZone(timeZone: shifts.preferences.recordsTimeZone)
        return "\(shifts.leaveDayLabel(zone.civil(ms).dayNumber)) \(shifts.leaveTime(ms))"
    }

    private func itemTime(_ item: LeavePlanItem) -> String {
        guard let first = item.segments.first, let last = item.segments.last else { return "" }
        return OWCText.ltrRange(shifts.leaveTime(first.startAtMs), shifts.leaveTime(last.endAtMs))
    }

    private func itemDetail(_ item: LeavePlanItem) -> String {
        switch item.role {
        case .bridge: text.t(item.portion.titleKey)
        case .earlyDeparture: text.t("leaveRoleEarly")
        case .lateReturn: text.t("leaveRoleLate")
        }
    }

    private func adopt() {
        isAdopting = true
        Task {
            let result = await actions.adoptLeavePlan(proposal).value
            switch result {
            case .success:
                isAdopting = false
                onAdopted()
            case .failure:
                failed = true
                isAdopting = false
            }
        }
    }
}

// MARK: - Plan calendar

/// The weeks around a proposal, each day marked by a symbol as well as a tint:
/// rest, a public holiday, a day of leave or half a day of it.
private struct LeavePlanCalendar: View {
    let shifts: ShiftSessionStore
    let proposal: LeavePlanProposal

    private var text: AppText { shifts.text }

    private enum Mark: CaseIterable {
        case work
        case rest
        case holiday
        case leave
        case halfLeave
    }

    private var calendar: Calendar { shifts.preferences.recordsCalendar }

    private var weeks: [[Int?]] {
        let first = proposal.items.map(\.dayNumber).min().map { min($0, proposal.firstRestDayNumber) } ?? proposal.firstRestDayNumber
        let last = proposal.items.map(\.dayNumber).max().map { max($0, proposal.lastRestDayNumber) } ?? proposal.lastRestDayNumber
        // Day numbers count from Thursday 1970-01-01; `weekday` is 0 for Sunday.
        func weekday(_ day: Int) -> Int { ((day + 4) % 7 + 7) % 7 }
        let leading = (weekday(first) - (calendar.firstWeekday - 1) + 7) % 7
        var cursor = first - leading
        var rows: [[Int?]] = []
        while cursor <= last {
            rows.append((0..<7).map { offset in
                let day = cursor + offset
                return day >= first - 1 && day <= last + 1 ? day : nil
            })
            cursor += 7
        }
        return rows
    }

    /// Only the marks this proposal uses, in a fixed order.
    private var legendMarks: [Mark] {
        let used = Set(weeks.flatMap { $0 }.compactMap { $0 }.map(mark))
        return Mark.allCases.filter { $0 != .work && used.contains($0) }
    }

    private func mark(_ day: Int) -> Mark {
        if let item = proposal.items.first(where: { $0.dayNumber == day }) {
            return item.portion == .whole ? .leave : .halfLeave
        }
        if (proposal.firstRestDayNumber...proposal.lastRestDayNumber).contains(day) {
            switch proposal.dayKinds[day - proposal.firstRestDayNumber] {
            case .holiday: return .holiday
            case .leave: return .leave
            case .rest: return .rest
            }
        }
        return .work
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { column in
                    Text(weekdaySymbol(column))
                        .font(.caption2)
                        .foregroundStyle(OWCDesign.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 4) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day { cell(day) } else { Color.clear.frame(maxWidth: .infinity, minHeight: 44) }
                    }
                }
            }
            HStack(spacing: 12) {
                ForEach(legendMarks, id: \.self) { mark in
                    legend(mark, label(mark) ?? "")
                }
            }
            .font(.caption2)
            .foregroundStyle(OWCDesign.secondary)
            .padding(.top, 4)
        }
    }

    private func weekdaySymbol(_ column: Int) -> String {
        var localized = calendar
        localized.locale = Locale(identifier: shifts.preferences.languageCode)
        let symbols = localized.veryShortStandaloneWeekdaySymbols
        return symbols[(column + calendar.firstWeekday - 1) % 7]
    }

    private func cell(_ day: Int) -> some View {
        let mark = mark(day)
        return VStack(spacing: 2) {
            Text(String(CivilZone.civilDate(dayNumber: day).day))
                .font(.subheadline.monospacedDigit().weight(mark == .work ? .regular : .semibold))
                .foregroundStyle(mark == .work ? OWCDesign.secondary : OWCDesign.primary)
            symbol(mark)
                .font(.caption2)
                .frame(height: 12)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(background(mark), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([shifts.leaveDayLabel(day), label(mark)].compactMap { $0 }.joined(separator: ", "))
    }

    @ViewBuilder
    private func symbol(_ mark: Mark) -> some View {
        switch mark {
        case .work: Color.clear
        case .rest: Image(systemName: "moon.zzz").foregroundStyle(OWCDesign.secondary)
        case .holiday: Image(systemName: "flag").foregroundStyle(OWCDesign.secondary)
        case .leave: Image(systemName: "suitcase.fill").foregroundStyle(OWCDesign.accent)
        case .halfLeave: Image(systemName: "circle.lefthalf.filled").foregroundStyle(OWCDesign.accent)
        }
    }

    private func background(_ mark: Mark) -> Color {
        switch mark {
        case .work: .clear
        case .rest, .holiday: OWCDesign.control
        case .leave, .halfLeave: OWCDesign.accent.opacity(0.16)
        }
    }

    private func label(_ mark: Mark) -> String? {
        switch mark {
        case .work: nil
        case .rest: text.t("leaveDayRest")
        case .holiday: text.t("leaveDayHoliday")
        case .leave: text.t("leaveDayLeave")
        case .halfLeave: text.t("leaveDayHalf")
        }
    }

    private func legend(_ mark: Mark, _ title: String) -> some View {
        HStack(spacing: 4) {
            symbol(mark)
            Text(title)
        }
    }
}
