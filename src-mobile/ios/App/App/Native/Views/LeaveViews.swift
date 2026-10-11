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
            VStack(alignment: .leading, spacing: 12) {
                if !shifts.records.state.leaveBalances.isEmpty {
                    remainingCard
                }
                OWCGroupCard {
                    Button { isPlanning = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "suitcase")
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(text.t("leavePlanAction"))
                                if let planSubtitle {
                                    Text(planSubtitle)
                                        .font(.footnote)
                                        .foregroundStyle(OWCDesign.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.forward")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(OWCDesign.tertiary)
                        }
                        .font(.subheadline)
                        .foregroundStyle(OWCDesign.accent)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(OWCRowButtonStyle())
                }

                balancesCard

                let plans = shifts.adoptedLeavePlans
                if !plans.isEmpty {
                    LeaveCard(title: text.t("leaveAdoptedPlans"), note: text.formatCount(plans.count)) {
                        ForEach(Array(plans.enumerated()), id: \.element.id) { index, plan in
                            if index > 0 { Divider() }
                            Button { viewingPlan = .init(id: plan.id) } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(shifts.leavePlanTitle(plan.days))
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(OWCDesign.primary)
                                        Text(text.t("leaveUses", values: ["days": shifts.leavePlanCost(plan.days)]))
                                            .font(.footnote)
                                            .foregroundStyle(OWCDesign.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.forward")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(OWCDesign.tertiary)
                                }
                                .frame(minHeight: 52)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 14)
            .padding(.bottom, OWCDesign.detailBottomInset)
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

    private var balances: [LeaveBalance] { shifts.records.state.leaveBalances }

    private func plannedHalfDays(_ balance: LeaveBalance) -> Int {
        max(0, balance.entitledHalfDays - balance.usedHalfDays - shifts.availableLeaveHalfDays(for: balance))
    }

    /// What is left, then the one balance worth using first.
    private var remainingCard: some View {
        let total = balances.reduce(0) { $0 + shifts.availableLeaveHalfDays(for: $1) }
        let days = Double(total) / 2
        let expiring = balances
            .filter { shifts.availableLeaveHalfDays(for: $0) > 0 && $0.validThroughDayKey != nil }
            .min { ($0.validThroughDayKey ?? "") < ($1.validThroughDayKey ?? "") }
        return LeaveCard {
            Text(text.t("leaveRemainingTitle"))
                .font(LeaveStyle.title)
                .padding(.bottom, 4)
            LeaveHeroNumber(full: text.formatDays(days), number: text.formatDecimal(days))
            if let expiring, let key = expiring.validThroughDayKey {
                Text(text.t("leaveExpiringFirst", values: [
                    "days": text.formatDays(Double(shifts.availableLeaveHalfDays(for: expiring)) / 2),
                    "name": shifts.leaveBalanceName(expiring),
                    "date": shifts.leaveDayLabel(dayKey: key, template: "MMMd"),
                ]))
                .font(.subheadline)
                .foregroundStyle(OWCDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            }
            OWCFlowLayout(spacing: 6) {
                ForEach(balances.filter { shifts.availableLeaveHalfDays(for: $0) > 0 }) { balance in
                    HStack(spacing: 5) {
                        Circle().fill(balance.id == expiring?.id ? OWCDesign.accent.opacity(0.55) : OWCDesign.accent)
                            .frame(width: 7, height: 7)
                        Text("\(shifts.leaveBalanceName(balance)) \(text.t("leaveAvailable", values: ["count": text.formatDecimal(Double(shifts.availableLeaveHalfDays(for: balance)) / 2)]))")
                            .font(.footnote.weight(.medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(OWCDesign.control, in: Capsule())
                }
            }
            .padding(.top, 12)
        }
        .accessibilityElement(children: .combine)
    }

    private var balancesCard: some View {
        LeaveCard(title: text.t("leaveBalancesSection")) {
            ForEach(Array(balances.enumerated()), id: \.element.id) { index, balance in
                Divider()
                Button { editing = .init(balance: balance, isNew: false) } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(shifts.leaveBalanceName(balance))
                                .font(.subheadline.weight(.medium))
                            Spacer(minLength: 8)
                            Text(text.t("leaveAvailable", values: [
                                "count": text.formatDays(Double(shifts.availableLeaveHalfDays(for: balance)) / 2),
                            ]))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                        .foregroundStyle(OWCDesign.primary)
                        LeaveBalanceBar(totalHalfDays: balance.entitledHalfDays,
                                        usedHalfDays: balance.usedHalfDays,
                                        plannedHalfDays: plannedHalfDays(balance))
                            .padding(.top, 8)
                            .padding(.bottom, 6)
                        HStack(alignment: .firstTextBaseline) {
                            Text(balance.usedHalfDays > 0
                                 ? text.t("leaveTotalAndTaken", values: [
                                    "total": text.formatDays(Double(balance.entitledHalfDays) / 2),
                                    "used": text.formatDays(Double(balance.usedHalfDays) / 2),
                                 ])
                                 : text.t("leaveTotal", values: ["total": text.formatDays(Double(balance.entitledHalfDays) / 2)]))
                            Spacer(minLength: 8)
                            if let validity = validityLabel(balance) { Text(validity) }
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(OWCDesign.secondary)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
            Divider()
            Button { editing = .init(balance: Self.newBalance(), isNew: true) } label: {
                Label(text.t("leaveAddBalance"), systemImage: "plus")
                    .font(.subheadline)
                    .foregroundStyle(OWCDesign.accent)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !balances.isEmpty {
                HStack(spacing: 14) {
                    legendItem(Color(uiColor: .systemGray3), "leaveLegendTaken")
                    legendItem(OWCDesign.accent, "leaveLegendPlanned")
                    legendItem(OWCDesign.control, "leaveLegendLeft")
                }
                .font(.caption2)
                .foregroundStyle(OWCDesign.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .accessibilityHidden(true)
            }
        }
    }

    private func legendItem(_ color: Color, _ key: String) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 12, height: 5)
            Text(text.t(key))
        }
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
    @State private var searchContext: LeavePlanSearchContext?
    @State private var submittedRequest: ShiftSessionStore.LeavePlanRequest?
    @State private var resultsID = UUID()
    @State private var searchFoundNothing = false
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
            plannerForm(isAdjusting: false)
            .navigationDestination(for: LeavePlannerStep.self) { step in
                switch step {
                case .results:
                    LeavePlanResults(shifts: shifts, proposals: proposals, searchContext: searchContext,
                                     adjustConditions: prepareAdjustment, open: openPlan)
                        .id(resultsID)
                case .conditions:
                    plannerForm(isAdjusting: true)
                        .onDisappear {
                            if !path.contains(.conditions) { searchTask?.cancel() }
                        }
                case .detail(let index):
                    LeavePlanDetail(shifts: shifts, actions: actions, proposal: proposals[index]) { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear(perform: load)
        .onDisappear { searchTask?.cancel() }
        .onChange(of: path.contains(.conditions)) { wasEditing, isEditing in
            if wasEditing && !isEditing { searchTask?.cancel() }
        }
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

    private func plannerForm(isAdjusting: Bool) -> some View {
        Form {
            if searchFoundNothing {
                Section { Text(text.t("leaveNoResults")).foregroundStyle(OWCDesign.secondary) }
            }
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
                VStack(alignment: .leading, spacing: 6) {
                    Text(text.t(goalIsRest ? "leaveGoalRest" : "leaveGoalBudget"))
                        .font(LeaveStyle.title)
                    HStack(alignment: .center, spacing: 12) {
                        if goalIsRest {
                            LeaveHeroNumber(
                                full: text.t("leaveAtLeast", values: ["days": text.formatDays(Double(restDays))]),
                                number: text.formatCount(restDays)
                            )
                            .contentTransition(.numericText())
                            Spacer(minLength: 0)
                            Stepper(text.t("leaveGoalRest"), value: $restDays, in: 2...60)
                                .labelsHidden()
                        } else {
                            LeaveHeroNumber(
                                full: text.t("leaveUpTo", values: ["days": text.formatDays(Double(leaveHalfDays) / 2)]),
                                number: text.formatDecimal(Double(leaveHalfDays) / 2)
                            )
                            .contentTransition(.numericText())
                            Spacer(minLength: 0)
                            Stepper(text.t("leaveGoalBudget"), value: $leaveHalfDays, in: 1...max(1, selectedHalfDays))
                                .labelsHidden()
                                .disabled(selectedHalfDays == 0)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    Text(text.t(goalIsRest ? "leaveGoalRestHint" : "leaveGoalBudgetHint"))
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
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
                        (Text(shifts.leaveBalanceName(balance)) + Text("  ")
                            + Text([text.t("leaveAvailable", values: ["count": text.formatDays(Double(available) / 2)]),
                                    balance.validThroughDayKey.map {
                                        text.t("leaveValidUntilDate", values: ["date": shifts.leaveDayLabel(dayKey: $0, template: "MMMd")])
                                    }].compactMap { $0 }.joined(separator: " · "))
                                .foregroundStyle(OWCDesign.secondary))
                            .monospacedDigit()
                    }
                    .tint(OWCDesign.accent)
                    .disabled(available == 0)
                }
            } header: {
                Text(text.t("leaveUseBalances"))
            } footer: {
                if !shifts.records.state.leaveBalances.isEmpty {
                    Text(text.t("leaveBalancesFooter"))
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: search) {
                Group {
                    if isSearching { ProgressView().tint(.white) } else { Text(text.t("leaveFind")) }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(OWCPrimaryButtonStyle())
            .disabled(request == nil || isSearching)
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.vertical, 12)
            .background(OWCDesign.page)
        }
        .navigationTitle(text.t("leavePlanAction"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(text.t("cancelAction"), role: .cancel) {
                    searchTask?.cancel()
                    if isAdjusting { path.removeLast() } else { dismiss() }
                }
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
    }

    /// The result set was authorized when the search completed. Browsing
    /// any of its options or details never consumes another trial.
    private func openPlan(_ index: Int) {
        guard proposals.indices.contains(index) else { return }
        path.append(.detail(index))
    }

    private func prepareAdjustment() {
        if let submittedRequest {
            switch submittedRequest.goal {
            case .restAtLeast(let days): goalIsRest = true; restDays = days
            case .leaveAtMost(let halfDays): goalIsRest = false; leaveHalfDays = halfDays
            }
            if let value = date(submittedRequest.fromDayNumber) { from = value }
            if let value = date(submittedRequest.throughDayNumber) { through = value }
            selected = Set(submittedRequest.budgetIDs)
        }
        searchFoundNothing = false
        path.append(.conditions)
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
        if UserDefaults.standard.bool(forKey: "ios.native.qaLeavePlanner"),
           UserDefaults.standard.string(forKey: "ios.native.qaLeaveScreen") != "setup" {
            isSearching = true
            let restDays = UserDefaults.standard.object(forKey: "ios.native.qaLeaveRestDays") == nil
                ? nil : UserDefaults.standard.integer(forKey: "ios.native.qaLeaveRestDays")
            let region = UserDefaults.standard.string(forKey: "ios.native.qaLeaveRegion") ?? "CN"
            if let restDays { self.restDays = restDays; goalIsRest = true }
            else { goalIsRest = false; leaveHalfDays = 10 }
            searchContext = DebugLeavePlanner.searchContext(restDays: restDays)
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
        let context = LeavePlanSearchContext(goal: request.goal, availableHalfDays: selectedHalfDays,
                                             fromDayNumber: request.fromDayNumber, throughDayNumber: request.throughDayNumber)
        searchFoundNothing = false
        isSearching = true
        searchTask = Task {
            defer { isSearching = false }
            let found = await shifts.findLeavePlans(request)
            guard !Task.isCancelled else { return }
            // Editing an authorized set never discards it for an empty search.
            if found.isEmpty && !proposals.isEmpty {
                searchFoundNothing = true
                return
            }
            guard shifts.preferences.authorizeLeavePlannerResults(
                hasResults: !found.isEmpty, isPlus: shifts.plus.isAuthorized
            ) else {
                showsPaywall = true
                return
            }
            proposals = found
            searchContext = context
            submittedRequest = request
            resultsID = UUID()
            path = [.results]
        }
    }

}

private enum LeavePlannerStep: Hashable {
    case conditions
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
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !shifts.plus.isAuthorized {
                    LeaveCard { LeaveTrialBanner(shifts: shifts) }
                }
                LeaveCard { LeaveBridgeCard(shifts: shifts, proposal: proposal) }

                if !proposal.items.isEmpty {
                    LeaveCard(title: text.t("leaveRequests"),
                              note: text.t("recordsAllocationTotal", values: ["duration": text.formatDays(Double(proposal.costHalfDays) / 2)])) {
                        ForEach(Array(proposal.items.enumerated()), id: \.element.dayKey) { index, item in
                            Divider()
                            HStack(spacing: 10) {
                                Image(systemName: item.portion == .whole ? "suitcase.fill" : "circle.lefthalf.filled")
                                    .font(.title3)
                                    .foregroundStyle(OWCDesign.accent)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(shifts.leaveDayLabel(item.dayNumber))
                                        .font(.subheadline.weight(.medium))
                                    Text(itemDetail(item))
                                        .font(.footnote.monospacedDigit())
                                        .foregroundStyle(OWCDesign.secondary)
                                }
                                Spacer(minLength: 8)
                                Text(text.formatDays(Double(item.portion.halfDays) / 2))
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                            }
                            .frame(minHeight: 52)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    let balanceIDs = Set(shifts.records.state.leaveBalances.map(\.id))
                    if proposal.uses.contains(where: { balanceIDs.contains($0.budgetID) }) {
                    LeaveCard(title: text.t("leaveDeductFrom"), note: text.t("leaveDeductOrder")) {
                        ForEach(proposal.uses, id: \.budgetID) { use in
                            if let balance = shifts.records.state.leaveBalances.first(where: { $0.id == use.budgetID }) {
                                let available = shifts.availableLeaveHalfDays(for: balance)
                                let left = available - use.halfDays
                                Divider()
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(shifts.leaveBalanceName(balance))
                                            .font(.subheadline.weight(.medium))
                                        Spacer(minLength: 8)
                                        Text(text.t("leaveBalanceAfter", values: [
                                            "used": text.formatDays(Double(use.halfDays) / 2),
                                            "left": text.formatDays(Double(max(0, left)) / 2),
                                        ]))
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                    }
                                    LeaveBalanceBar(
                                        totalHalfDays: balance.entitledHalfDays,
                                        usedHalfDays: balance.entitledHalfDays - available,
                                        plannedHalfDays: use.halfDays
                                    )
                                }
                                .padding(.vertical, 10)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    }
                }

                if !caveatKeys.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(caveatKeys, id: \.self) { key in
                            Label(key.label(text), systemImage: "exclamationmark.triangle")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                }
            }
            .padding(OWCDesign.pageInset)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(OWCDesign.page)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !proposal.items.isEmpty {
                Button(action: adopt) {
                    Text(text.t("leaveAdopt")).frame(maxWidth: .infinity)
                }
                .buttonStyle(OWCPrimaryButtonStyle())
                .disabled(isAdopting)
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.vertical, 12)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
                .background(OWCDesign.page)
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

    /// "Second half 14:00–18:00 · Leave early".
    private func itemDetail(_ item: LeavePlanItem) -> String {
        var parts = ["\(text.t(item.portion.titleKey)) \(itemTime(item))"]
        switch item.role {
        case .bridge: break
        case .earlyDeparture: parts.append(text.t("leaveRoleEarly"))
        case .lateReturn: parts.append(text.t("leaveRoleLate"))
        }
        return parts.joined(separator: " · ")
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
