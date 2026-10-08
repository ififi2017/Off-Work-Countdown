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

    /// An adopted plan's dates, e.g. "Oct 12 – Oct 23".
    func leavePlanTitle(_ days: [LeaveDay]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        let start = leaveDayLabel(dayKey: first.dayKey, template: "MMMd")
        return first.dayKey == last.dayKey
            ? start
            : OWCText.ltrRange(start, leaveDayLabel(dayKey: last.dayKey, template: "MMMd"))
    }

    func leavePlanCost(_ days: [LeaveDay]) -> String {
        text.formatDays(Double(days.reduce(0) { $0 + $1.portion.halfDays }) / 2)
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
    let shifts: ShiftSessionStore
    let actions: RecordsActions
    /// Settings and Records both open this page; the back button names where.
    var backTitleKey = "settings"
    @State private var editing: LeaveBalanceEditing?
    @State private var isPlanning = false
    @State private var viewingPlan: LeavePlanSelection?

    private var text: AppText { shifts.text }
    private var trialsLeft: Int { shifts.preferences.leavePlannerTrialsLeft }

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OWCGroupCard {
                    Button { isPlanning = true } label: {
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
                            Button { viewingPlan = .init(id: plan.id) } label: {
                                OWCRow(icon: "airplane", title: shifts.leavePlanTitle(plan.days),
                                       subtitle: text.t("leaveUses", values: ["days": shifts.leavePlanCost(plan.days)]),
                                       isLast: index == plans.count - 1, centersVertically: true) {
                                    OWCDetailAccessory(text: nil)
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
        .owcDetailBack(title: text.t(backTitleKey), pageTitle: text.t("leaveTitle"))
        .sheet(item: $editing) { editing in
            LeaveBalanceEditor(shifts: shifts, editing: editing)
        }
        .sheet(isPresented: $isPlanning) {
            LeavePlannerSheet(shifts: shifts, actions: actions)
        }
        .sheet(item: $viewingPlan) { selection in
            AdoptedLeavePlanSheet(shifts: shifts, actions: actions, planID: selection.id)
        }
        #if DEBUG
        .onAppear {
            if UserDefaults.standard.bool(forKey: "ios.native.qaLeavePlanner") { isPlanning = true }
        }
        #endif
    }

    private var planSubtitle: String? {
        guard !shifts.plus.isAuthorized else { return nil }
        return trialsLeft > 0 ? text.t("leaveTrialsLeft", count: trialsLeft) : text.t("leaveTrialsUsedUp")
    }

    private func validityLabel(_ balance: LeaveBalance) -> String? {
        balance.validThroughDayKey.map {
            text.t("leaveValidUntilDate", values: ["date": shifts.leaveDayLabel(dayKey: $0, template: "yMMMd")])
        }
    }

    static func newBalance() -> LeaveBalance {
        LeaveBalance(id: UUID(), kind: .annual, name: nil, entitledHalfDays: 10, usedHalfDays: 0,
                     validFromDayKey: nil, validThroughDayKey: nil)
    }
}

private struct LeavePlanSelection: Identifiable {
    let id: UUID
}

/// One adopted plan's days. A day can be handed back on its own; the rest of
/// the plan keeps its id, so undoing it later still finds them.
private struct AdoptedLeavePlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    let shifts: ShiftSessionStore
    let actions: RecordsActions
    let planID: UUID
    @State private var cancelling: String?
    @State private var confirmsUndo = false

    private var text: AppText { shifts.text }
    private var days: [LeaveDay] { shifts.adoptedLeavePlans.first { $0.id == planID }?.days ?? [] }

    var body: some View {
        let days = days
        NavigationStack {
            Form {
                Section {
                    ForEach(days, id: \.dayKey) { day in
                        Button { cancelling = day.dayKey } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(shifts.leaveDayLabel(dayKey: day.dayKey))
                                        .foregroundStyle(OWCDesign.primary)
                                    if let uses = usesLabel(day) {
                                        Text(uses).font(.caption).foregroundStyle(OWCDesign.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                Text(text.t(day.portion.titleKey))
                                    .foregroundStyle(OWCDesign.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityHint(text.t("leaveCancelDay"))
                    }
                } footer: {
                    Text(text.t("leaveUses", values: ["days": shifts.leavePlanCost(days)]))
                }
                Section {
                    Button(text.t("leaveUndoPlan"), role: .destructive) { confirmsUndo = true }
                }
            }
            .navigationTitle(shifts.leavePlanTitle(days))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(text.t("done")) { dismiss() }
                }
            }
            .confirmationDialog(
                text.t("leaveCancelDay"),
                isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }),
                titleVisibility: .visible,
                presenting: cancelling
            ) { key in
                Button(text.t("leaveCancelDay"), role: .destructive) { actions.cancelLeaveDay(key) }
            } message: { key in
                Text(shifts.leaveDayLabel(dayKey: key) + "\n" + text.t("leaveCancelDayConfirm"))
            }
            .confirmationDialog(text.t("leaveUndoPlan"), isPresented: $confirmsUndo, titleVisibility: .visible) {
                Button(text.t("leaveUndoPlan"), role: .destructive) {
                    actions.undoLeavePlan(planID)
                    dismiss()
                }
            } message: {
                Text(text.t("leaveUndoConfirm"))
            }
            .onChange(of: days.isEmpty) { if days.isEmpty { dismiss() } }
        }
        .presentationDragIndicator(.visible)
    }

    private func usesLabel(_ day: LeaveDay) -> String? {
        let balances = shifts.records.state.leaveBalances
        let parts = day.uses.compactMap { use -> String? in
            guard let balance = balances.first(where: { $0.id == use.budgetID }) else { return nil }
            return shifts.leaveBalanceName(balance) + " " + text.formatDays(Double(use.halfDays) / 2)
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

struct LeaveBalanceEditing: Identifiable {
    var balance: LeaveBalance
    var isNew: Bool
    var id: UUID { balance.id }
}

// MARK: - Balance editor

struct LeaveBalanceEditor: View {
    @Environment(\.dismiss) private var dismiss
    let shifts: ShiftSessionStore
    let editing: LeaveBalanceEditing
    /// The first balance, asked for before the time off page opens.
    var isGuided = false
    var onSaved: () -> Void = {}
    @State private var draft: LeaveBalance
    @State private var entitledText: String
    @State private var usedText: String
    @State private var hasStart: Bool
    @State private var hasEnd: Bool
    @State private var start: Date
    @State private var end: Date

    init(shifts: ShiftSessionStore, editing: LeaveBalanceEditing, isGuided: Bool = false, onSaved: @escaping () -> Void = {}) {
        self.shifts = shifts
        self.editing = editing
        self.isGuided = isGuided
        self.onSaved = onSaved
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
                if isGuided {
                    Section {
                        Label(text.t("leaveSetupIntro"), systemImage: "suitcase")
                            .foregroundStyle(OWCDesign.primary)
                    }
                }
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
            .navigationTitle(text.t(isGuided ? "leaveSetupTitle" : editing.isNew ? "leaveNewBalance" : "leaveEditBalance"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(text.t("cancelAction"), role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(text.t("saveAction")) {
                        guard let result else { return }
                        shifts.records.submitCommand { [shifts] in shifts.records.upsertLeaveBalance(result) }
                        onSaved()
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
    @State private var searchTask: Task<Void, Never>?
    @State private var proposals: [LeavePlanProposal] = []
    @State private var didLoad = false
    @State private var showsPaywall = false

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
                if !shifts.plus.isAuthorized {
                    Section { LeaveTrialBanner(shifts: shifts, explainsCost: true) }
                }
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
                        ForEach(estimatedYears, id: \.self) { year in
                            Label(text.t("holidayEstimatedYearWarning", values: ["year": text.formatYear(year)]),
                                  systemImage: "exclamationmark.triangle")
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
                            .disabled(request == nil)
                    }
                }
            }
            .navigationDestination(for: LeavePlannerStep.self) { step in
                switch step {
                case .results:
                    LeavePlanResults(shifts: shifts, proposals: proposals, open: openPlan)
                case .detail(let index):
                    LeavePlanDetail(shifts: shifts, actions: actions, proposal: proposals[index]) { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear(perform: load)
        .onDisappear { searchTask?.cancel() }
        .sheet(isPresented: $showsPaywall) {
            NavigationStack {
                PaywallView(plus: shifts.plus, text: text, reason: .leavePlanning, showsDismissButton: false) {
                    showsPaywall = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(text.t("close")) { showsPaywall = false }
                    }
                }
            }
            .presentationDetents([.large])
        }
    }

    /// The result set was authorized when the search completed. Browsing
    /// any of its options or details never consumes another trial.
    private func openPlan(_ index: Int) {
        guard proposals.indices.contains(index) else { return }
        path.append(.detail(index))
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

    private var estimatedYears: [Int] {
        guard let request else { return [] }
        return shifts.estimatedMainlandHolidayYears(in: request.fromDayNumber...request.throughDayNumber)
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
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "ios.native.qaLeavePlanner") {
            isSearching = true
            let restDays = UserDefaults.standard.object(forKey: "ios.native.qaLeaveRestDays") == nil
                ? nil : UserDefaults.standard.integer(forKey: "ios.native.qaLeaveRestDays")
            let region = UserDefaults.standard.string(forKey: "ios.native.qaLeaveRegion") ?? "CN"
            Task {
                proposals = await Task.detached(priority: .userInitiated) {
                    DebugLeavePlanner.proposals(restDays: restDays, region: region)
                }.value
                isSearching = false
                path = [.results]
            }
        }
        #endif
    }

    private func search() {
        guard !isSearching, let request else { return }
        guard shifts.plus.isAuthorized || shifts.preferences.leavePlannerTrialsLeft > 0 else {
            showsPaywall = true
            return
        }
        isSearching = true
        searchTask = Task {
            defer { isSearching = false }
            let found = await shifts.findLeavePlans(request)
            guard !Task.isCancelled else { return }
            guard shifts.preferences.authorizeLeavePlannerResults(
                hasResults: !found.isEmpty, isPlus: shifts.plus.isAuthorized
            ) else {
                showsPaywall = true
                return
            }
            proposals = found
            path = [.results]
        }
    }

}

private enum LeavePlannerStep: Hashable {
    case results
    case detail(Int)
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
            if !shifts.plus.isAuthorized {
                Section { LeaveTrialBanner(shifts: shifts) }
            }
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
        case predictedHolidays(Int)
        case carriedOver
        case unassigned

        func label(_ text: AppText) -> String {
            switch self {
            case .missingHolidays(let year): text.t("leaveEstimatedYear", values: ["year": String(year)])
            case .predictedHolidays(let year): text.t("holidayEstimatedYearWarning", values: ["year": text.formatYear(year)])
            case .carriedOver: text.t("leaveCarriedOverCaveat")
            case .unassigned: text.t("leaveUnassignedCaveat")
            }
        }
    }

    private var caveatKeys: [Caveat] {
        proposal.caveats.map { caveat -> Caveat in
            switch caveat {
            case .holidaysNotIncluded(let year): .missingHolidays(year)
            case .holidaysEstimated(let year): .predictedHolidays(year)
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

/// How many successful result-set searches remain on this device.
/// Options and details of an authorized set do not spend another trial.
struct LeaveTrialBanner: View {
    let shifts: ShiftSessionStore
    var explainsCost = false

    private var left: Int { shifts.preferences.leavePlannerTrialsLeft }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: left > 0 ? "ticket" : "lock")
                .font(.title3)
                .foregroundStyle(OWCDesign.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(left > 0 ? shifts.text.t("leaveTrialsLeft", count: left) : shifts.text.t("leaveTrialsUsedUp"))
                    .font(.headline)
                    .foregroundStyle(OWCDesign.primary)
                if explainsCost, left > 0 {
                    Text(shifts.text.t("leaveTrialNotice"))
                        .font(.subheadline)
                        .foregroundStyle(OWCDesign.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .listRowBackground(OWCDesign.accent.opacity(0.12))
        .accessibilityElement(children: .combine)
    }
}
