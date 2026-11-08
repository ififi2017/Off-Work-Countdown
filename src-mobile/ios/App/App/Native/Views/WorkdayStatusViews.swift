import SwiftUI

// Plan 021 §3.10: answering "how is today going" and saving days away from
// the office. Neither approves any detected time; only adopting does.

extension WorkDayContext {
    var labelKey: String {
        switch self {
        case .regular: "automationStatusContinue"
        case .fieldwork: "automationContextFieldwork"
        case .businessTrip: "automationContextBusinessTrip"
        case .remote: "automationContextRemote"
        case .rest: "automationContextRest"
        }
    }

    var symbol: String {
        switch self {
        case .regular: "building.2"
        case .fieldwork: "figure.walk"
        case .businessTrip: "airplane"
        case .remote: "house"
        case .rest: "moon"
        }
    }
}

// MARK: - Today's status

struct WorkdayStatusView: View {
    @Environment(\.dismiss) private var dismiss
    let runtime: AppRuntime
    @State private var confirmsRest = false
    @State private var feedback = 0

    private var text: AppText { runtime.text }
    private var automation: WorkplaceAutomationCoordinator { runtime.workplaceAutomation }

    /// The shift the question is about: the one running, else the latest
    /// one that already started, else the next.
    private var shift: AutomationShift? {
        let now = Date.now
        let shifts = runtime.queries.automationShifts(around: now)
        return shifts.first { $0.plannedStart <= now && now < $0.plannedEnd }
            ?? shifts.filter { $0.plannedStart <= now }.max { $0.plannedStart < $1.plannedStart }
            ?? shifts.min { $0.plannedStart < $1.plannedStart }
    }

    var body: some View {
        Group {
            if let shift {
                content(shift)
            } else {
                ContentUnavailableView {
                    Label(text.t("automationStatusNoShift"), systemImage: "calendar")
                } description: {
                    Text(text.t("automationStatusNoShiftNote"))
                }
                .background(OWCDesign.page)
            }
        }
        .owcDetailBack(title: text.t("automationUITitle"), pageTitle: text.t("automationStatusTitle"))
        .tint(OWCDesign.accent)
        .sensoryFeedback(.success, trigger: feedback)
    }

    private func content(_ shift: AutomationShift) -> some View {
        let presenter = WorkplaceAutomationPresenter(
            text: text, timeZone: runtime.preferences.recordsTimeZone, locale: runtime.preferences.locale
        )
        let answer = automation.state.statusAnswer(shiftKey: shift.shiftKey)
        let options: [WorkdayStatusAnswer] = [.continueRecording, .rest, .fieldwork, .businessTrip, .remote]
        return OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(text.t("automationStatusIntro"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                OWCSectionHeader(title: presenter.dayTitle(shift.anchorDayKey) + " · "
                                 + presenter.time(shift.plannedStart) + "–" + presenter.time(shift.plannedEnd))
                    .padding(.top, OWCDesign.sectionGap)
                OWCGroupCard {
                    ForEach(Array(options.enumerated()), id: \.element) { index, option in
                        Button { choose(option, for: shift) } label: {
                            OWCRow(icon: Self.context(option).symbol, title: text.t(Self.labelKey(option)),
                                   subtitle: option == .continueRecording ? text.t("automationStatusContinueNote") : nil,
                                   isLast: index == options.count - 1, centersVertically: true) {
                                if answer == option {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(OWCDesign.accent)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .buttonStyle(OWCRowButtonStyle())
                        .accessibilityAddTraits(answer == option ? .isSelected : [])
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.bottom, OWCDesign.detailBottomInset)
        }
        .background(OWCDesign.page)
        .confirmationDialog(text.t("automationStatusRest"), isPresented: $confirmsRest, titleVisibility: .visible) {
            Button(text.t("automationStatusRest"), role: .destructive) { settle(.rest, for: shift) }
        } message: {
            Text(text.t("automationStatusRestConfirm"))
        }
    }

    private func choose(_ answer: WorkdayStatusAnswer, for shift: AutomationShift) {
        // Recorded hours on the day: say what a day off does before doing it.
        if answer == .rest, runtime.records.state.overrides.contains(where: {
            $0.dayKey == shift.anchorDayKey && $0.kind == .customSegments
        }) {
            confirmsRest = true
            return
        }
        settle(answer, for: shift)
    }

    private func settle(_ answer: WorkdayStatusAnswer, for shift: AutomationShift) {
        Task {
            if await automation.answerStatus(answer, for: shift) == .applied {
                feedback += 1
                dismiss()
            }
        }
    }

    static func labelKey(_ answer: WorkdayStatusAnswer) -> String {
        answer == .rest ? "automationStatusRest" : context(answer).labelKey
    }

    static func context(_ answer: WorkdayStatusAnswer) -> WorkDayContext {
        switch answer {
        case .continueRecording: .regular
        case .rest: .rest
        case .fieldwork: .fieldwork
        case .businessTrip: .businessTrip
        case .remote: .remote
        }
    }
}

// MARK: - Days away from the office

struct WorkContextEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let text: AppText
    let calendar: Calendar
    var onSave: (WorkDayContext, String, String) -> Void

    @State private var context: WorkDayContext = .fieldwork
    @State private var from = Date.now
    @State private var to = Date.now

    static let choices: [WorkDayContext] = [.fieldwork, .businessTrip, .remote, .rest]

    var body: some View {
        NavigationStack {
            OWCContentSizedScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    OWCGroupCard {
                        OWCRow(title: text.t("automationUIContextType")) {
                            Picker(text.t("automationUIContextType"), selection: $context) {
                                ForEach(Self.choices, id: \.self) { choice in
                                    Label(text.t(choice.labelKey), systemImage: choice.symbol).tag(choice)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        OWCRow(title: text.t("automationUIContextFrom")) {
                            DatePicker(text.t("automationUIContextFrom"), selection: $from, displayedComponents: .date)
                                .labelsHidden()
                        }
                        OWCRow(title: text.t("automationUIContextTo"), isLast: true) {
                            DatePicker(text.t("automationUIContextTo"), selection: $to, in: from..., displayedComponents: .date)
                                .labelsHidden()
                        }
                    }
                    .padding(.top, 14)
                    Text(text.t("automationUIContextNote"))
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
                .padding(.horizontal, OWCDesign.pageInset)
            }
            .background(OWCDesign.page)
            .navigationTitle(text.t("automationUIAddContext"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(text.t("cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(text.t("saveAction")) {
                        onSave(context, RecordJSON.dayKey(from, calendar: calendar),
                               RecordJSON.dayKey(max(from, to), calendar: calendar))
                        dismiss()
                    }
                }
            }
            .onChange(of: from) { _, new in if to < new { to = new } }
        }
        .presentationDetents([.medium, .large])
        .tint(OWCDesign.accent)
    }
}
