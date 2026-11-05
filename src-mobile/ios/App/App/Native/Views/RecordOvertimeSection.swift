import SwiftUI

/// Plan 024 phase 4: a past day's overtime in the Records day editor — the
/// period, the hours that count and how it is paid. The editor owns the state
/// and saves it together with the day's hours behind its single Save button.
struct RecordOvertimeSection: View {
    @Binding var state: RecordOvertimeState
    @Binding var isExpanded: Bool
    let actions: RecordsActions

    @State private var isPaid: Bool
    @State private var multiplier: Double
    @State private var showsCustomMultiplier: Bool

    private var text: AppText { actions.text }
    private var calendar: Calendar { actions.preferences.recordsCalendar }

    init(state: Binding<RecordOvertimeState>, isExpanded: Binding<Bool>, actions: RecordsActions) {
        _state = state
        _isExpanded = isExpanded
        self.actions = actions
        let initial = state.wrappedValue
        let paid = initial.payMultiplier > 0
        let shown = paid ? initial.payMultiplier : (actions.preferences.overtimePayMultiplier > 0 ? actions.preferences.overtimePayMultiplier : 1)
        _isPaid = State(initialValue: paid)
        _multiplier = State(initialValue: shown)
        _showsCustomMultiplier = State(initialValue: paid && !OvertimePayChoices.isPreset(shown))
    }

    /// The state a day without a declaration starts from: the default pay choice.
    static func initialState(loaded: RecordOvertimeState, actions: RecordsActions) -> RecordOvertimeState {
        var initial = loaded
        if !loaded.hasDeclaration {
            initial.payMultiplier = OvertimePay.normalized(actions.preferences.overtimePayMultiplier)
        }
        return initial
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OWCSectionHeader(title: text.t("recordsSectionOvertime"))
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.top, 22)
            if isExpanded {
                editor
            } else {
                OWCGroupCard {
                    Button { isExpanded = true } label: {
                        OWCRow(icon: "plus.circle", title: text.t("overtimeTitle"), isLast: true)
                    }
                    .buttonStyle(OWCRowButtonStyle())
                }
                .padding(.horizontal, OWCDesign.pageInset)
            }
        }
        .onChange(of: isPaid) { applyPay() }
        .onChange(of: multiplier) { applyPay() }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            OWCGroupCard {
                OWCRow(icon: "clock", title: text.t("recordsOvertimePeriod")) {
                    HStack(spacing: 6) {
                        DatePicker("", selection: startBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Text("–").foregroundStyle(OWCDesign.tertiary)
                        DatePicker("", selection: endBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                }
                OWCRow(
                    icon: "timer",
                    title: text.t("recordsOvertimeCounted"),
                    subtitle: text.t("recordsOvertimeCountedSubtitle", values: [
                        "duration": text.formatRelativeDuration(state.measuredMs)
                    ]),
                    isLast: state.countedMs == nil
                ) {
                    Stepper(value: countedSteps, in: 0...96) {
                        Text(text.formatRelativeDuration(state.effectiveCountedMs))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(OWCDesign.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .accessibilityLabel(text.t("recordsOvertimeCounted"))
                    .accessibilityValue(text.formatRelativeDuration(state.effectiveCountedMs))
                }
                if state.countedMs != nil {
                    Button { state.countedMs = nil } label: {
                        OWCRow(icon: "arrow.uturn.backward", title: text.t("recordsOvertimeUseMeasured"), isLast: true)
                    }
                    .buttonStyle(OWCRowButtonStyle())
                }
            }
            OvertimePayCard(text: text, isPaid: $isPaid, multiplier: $multiplier, showsCustom: $showsCustomMultiplier)
            Text(text.t("recordsOvertimeFootnote"))
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, OWCDesign.pageInset)
        .environment(\.timeZone, calendar.timeZone)
        .environment(\.calendar, calendar)
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: state.startAtMs / 1_000) },
            set: { state.setStart(timeOf: $0, calendar: calendar) }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: state.endAtMs / 1_000) },
            set: { state.setEnd(timeOf: $0, calendar: calendar) }
        )
    }

    /// Counted hours in quarter-hour steps; the first tap leaves the period.
    private var countedSteps: Binding<Int> {
        Binding(
            get: { Int((state.effectiveCountedMs / RecordOvertimeState.countedStepMs).rounded()) },
            set: { steps in
                let current = Int((state.effectiveCountedMs / RecordOvertimeState.countedStepMs).rounded())
                state.countedMs = steps == current ? state.countedMs : state.steppedCountedMs(by: steps - current)
            }
        )
    }

    private func applyPay() {
        state.payMultiplier = isPaid ? OvertimePay.normalized(multiplier) : 0
    }
}
