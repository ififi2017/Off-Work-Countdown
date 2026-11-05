import SwiftUI

/// A deliberately content-free destination for an expired free-history route.
/// It receives no day resolution, title, counts, or observations.
struct RecordsLockedHistoryPlaceholder: View {
    let text: AppText

    var body: some View {
        OWCContentSizedScrollView {
            OWCGroupCard {
                OWCRow(title: text.t("recordsLockedDay"), isLast: true) {
                    Image(systemName: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.tertiary)
                }
                .accessibilityLabel(text.t("recordsLockedDay"))
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 14)
        }
        .background(OWCDesign.page)
        .navigationTitle(text.t("recordsAllRecords"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RecordDayEditView: View {
    @Bindable var draft: RecordDayEditDraft
    let actions: RecordsActions
    private var text: AppText { actions.text }

    @State private var savedFeedback = 0
    @State private var warningFeedback = 0
    @State private var selectionFeedback = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    /// Plan 024: the day's overtime is edited here too and saved by the same
    /// Save, so there is one place where changes are kept or thrown away.
    @State private var overtime: RecordOvertimeState
    @State private var overtimeExpanded: Bool
    private let overtimeBaseline: RecordOvertimeState

    init(draft: RecordDayEditDraft, actions: RecordsActions) {
        self.draft = draft
        self.actions = actions
        let initial = RecordOvertimeSection.initialState(loaded: draft.overtime, actions: actions)
        _overtime = State(initialValue: initial)
        _overtimeExpanded = State(initialValue: draft.overtime.hasDeclaration)
        overtimeBaseline = initial
    }

    /// A new declaration counts as a change once the section is opened.
    private var overtimeChanged: Bool {
        overtimeExpanded && (overtime != overtimeBaseline || !overtimeBaseline.hasDeclaration)
    }

    private var hasChanges: Bool { draft.hasChanges || overtimeChanged }

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if draft.kind == .customHours {
                    OWCSectionHeader(title: text.t("recordsSectionHours"))
                        .padding(.top, 8)
                    OWCGroupCard {
                        OWCRow(icon: "sunrise", title: text.t("startTime")) {
                            DatePicker("", selection: startBinding, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                        OWCRow(icon: "sunset", title: text.t("endTime"), isLast: true) {
                            DatePicker("", selection: endBinding, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                    }
                    .padding(.horizontal, OWCDesign.pageInset)
                }

                OWCSectionHeader(title: text.t("recordsSectionKind"))
                    .padding(.horizontal, OWCDesign.pageInset)
                    .padding(.top, draft.kind == .customHours ? 22 : 8)

                OWCGroupCard {
                    ForEach(Array(RecordDayEditDraft.Kind.allCases.enumerated()), id: \.element.id) { index, option in
                        Button {
                            select(option)
                        } label: {
                            OWCRow(
                                icon: option.icon,
                                title: text.t(option.titleKey),
                                isLast: index == RecordDayEditDraft.Kind.allCases.count - 1,
                                centersVertically: true
                            ) {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(OWCDesign.accent)
                                    .opacity(draft.kind == option ? 1 : 0)
                                    // Not just colour: the mark is present or
                                    // absent, which is the second channel.
                                    .accessibilityHidden(true)
                            }
                        }
                        .buttonStyle(OWCRowButtonStyle())
                        .accessibilityAddTraits(draft.kind == option ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.horizontal, OWCDesign.pageInset)

                RecordOvertimeSection(state: $overtime, isExpanded: $overtimeExpanded, actions: actions)

                Button(text.t("saveAction"), action: save)
                    .buttonStyle(OWCPrimaryButtonStyle())
                    .disabled(!hasChanges || (overtimeChanged && !overtime.isValid))
                    .padding(.horizontal, OWCDesign.pageInset)
                    .padding(.top, 22)

                if draft.loadedKind != .customHours || draft.hasStoredOverride {
                    OWCSectionHeader(title: text.t("syncDangerZone"))
                        .padding(.horizontal, OWCDesign.pageInset)
                        .padding(.top, 26)
                    OWCGroupCard {
                        Button {
                            warningFeedback += 1
                            draft.confirmsClear = true
                        } label: {
                            OWCRow(
                                icon: "arrow.uturn.backward",
                                title: text.t("recordsClearDay"),
                                subtitle: text.t("recordsClearDayDetail"),
                                isLast: true,
                                isDestructive: true
                            )
                        }
                        .buttonStyle(OWCRowButtonStyle())
                    }
                    .padding(.horizontal, OWCDesign.pageInset)
                }
            }
            .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.stateEnter, value: draft.kind)
        }
        .background(OWCDesign.page)
        .navigationTitle(text.t("recordsEditDay"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(text.t("cancel")) {
                    if hasChanges {
                        draft.confirmsDiscard = true
                    } else {
                        dismiss()
                    }
                }
            }
        }
        .environment(\.timeZone, draft.calendar.timeZone)
        .environment(\.calendar, draft.calendar)
        .interactiveDismissDisabled(hasChanges)
        .confirmationDialog(text.t("recordsDiscardEdits"), isPresented: $draft.confirmsDiscard, titleVisibility: .visible) {
            Button(text.t("recordsDiscardEdits"), role: .destructive) { dismiss() }
            Button(text.t("cancel"), role: .cancel) {}
        }
        .sensoryFeedback(.selection, trigger: selectionFeedback)
        .sensoryFeedback(.success, trigger: savedFeedback)
        .sensoryFeedback(.warning, trigger: warningFeedback)
        .alert(
            text.t("recordsReplaceHoursTitle"),
            isPresented: Binding(get: { draft.pendingKind != nil }, set: { if !$0 { draft.pendingKind = nil } })
        ) {
            if let pendingKind = draft.pendingKind {
                Button(text.t(pendingKind.titleKey)) {
                    draft.kind = pendingKind
                    selectionFeedback += 1
                    draft.pendingKind = nil
                }
            }
            Button(text.t("cancel"), role: .cancel) { draft.pendingKind = nil }
        } message: {
            Text(text.t("recordsReplaceHoursConfirm"))
        }
        .alert(text.t("recordsClearDayTitle"), isPresented: $draft.confirmsClear) {
            Button(text.t("recordsClearDay"), role: .destructive) {
                clear()
            }
            Button(text.t("cancel"), role: .cancel) {}
        } message: {
            Text(text.t("recordsClearDayConfirm"))
        }
    }

    /// Switching away from recorded hours throws them away, so it asks first.
    /// Choosing the hours option back again is free and does not.
    private func select(_ option: RecordDayEditDraft.Kind) {
        guard option != draft.kind else { return }
        if option != .customHours, draft.kind == .customHours, draft.hasStoredOverride {
            warningFeedback += 1
            draft.pendingKind = option
            return
        }
        draft.kind = option
        selectionFeedback += 1
    }

    /// One Save, at the end. Every one of the six buttons used to write
    /// straight through on tap, so there was no way to change your mind and no
    /// sign that anything had happened.
    /// The day's hours and its overtime are separate records (a day override
    /// and an `overtimeDeclared` observation); each is written only when it
    /// changed, in that order, and the editor closes once both succeeded.
    private func save() {
        let submission = draft.submission
        let dayCommand: RecordCommand<Bool>? = draft.hasChanges
            ? actions.applyDayWrite(
                submission.write,
                dayKey: submission.dayKey,
                startMinutes: submission.startMinutes,
                endMinutes: submission.endMinutes
            )
            : nil
        let overtimeCommand: RecordCommand<Bool>? = overtimeChanged && overtime.isValid
            ? actions.declareOvertime(dayKey: draft.dayKey, state: overtime)
            : nil
        Task { @MainActor in
            if let dayCommand {
                guard await dayCommand.value, draft.stillMatches(submission) else { return }
            }
            if let overtimeCommand {
                guard await overtimeCommand.value else { return }
            }
            savedFeedback += 1
            dismiss()
        }
    }

    private func clear() {
        let submission = draft.submission
        let command = actions.clearDayOverride(dayKey: submission.dayKey)
        Task { @MainActor in
            guard await command.value, draft.stillMatches(submission) else { return }
            dismiss()
        }
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { date(fromMinutes: draft.startMinutes) },
            set: { draft.startMinutes = minutes(from: $0) }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { date(fromMinutes: draft.endMinutes) },
            set: { draft.endMinutes = minutes(from: $0) }
        )
    }

    private func date(fromMinutes value: Int) -> Date {
        draft.calendar.date(
            bySettingHour: value / 60,
            minute: value % 60,
            second: 0,
            of: draft.calendar.startOfDay(for: .now)
        ) ?? .now
    }

    private func minutes(from date: Date) -> Int {
        let parts = draft.calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
