import SwiftUI

struct FocusTaskIconPicker: View {
    let store: OffWorkStore
    @Binding var selection: FocusTaskIcon

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.t("focusChooseIcon"))
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(FocusTaskIcon.allCases) { option in
                        Button {
                            selection = option
                        } label: {
                            Image(systemName: option.systemName)
                                .font(.body.weight(.medium))
                                .foregroundStyle(selection == option ? .white : OWCDesign.secondary)
                                .frame(width: 44, height: 44)
                                .background(
                                    selection == option ? OWCDesign.accent : OWCDesign.control,
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(store.t(option.titleKey))
                        .accessibilityAddTraits(selection == option ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct FocusTimerSettingsSheet: View {
    let store: OffWorkStore

    @Environment(\.dismiss) private var dismiss
    @State private var focusMinutes: Int
    @State private var shortBreakMinutes: Int
    @State private var longBreakMinutes: Int
    @State private var longBreakEvery: Int

    init(store: OffWorkStore) {
        self.store = store
        let settings = store.focusTimerSettings.normalized
        _focusMinutes = State(initialValue: settings.focusMinutes)
        _shortBreakMinutes = State(initialValue: settings.shortBreakMinutes)
        _longBreakMinutes = State(initialValue: settings.longBreakMinutes)
        _longBreakEvery = State(initialValue: settings.longBreakEvery)
    }

    /// F5: this used to lock on "some day has a saved plan" while the store
    /// rejects on "any template exists". With a template saved and no plan
    /// yet, every field was editable, Save was enabled, and
    /// `updateFocusTimerSettings` dropped the write without a word. The sheet
    /// now asks the store what it will actually refuse.
    private var isLocked: Bool {
        store.activeFocusSession() != nil || store.focusTimerSettingsLockReason != nil
    }

    private var lockMessage: String? {
        if store.activeFocusSession() != nil {
            return store.t("focusTimerSettingsLockedRunning")
        }
        if store.focusTimerSettingsLockReason == .hasTemplates {
            return store.t("focusTimerSettingsLockedTemplate")
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(store.t("focusTimerSettingsBody"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section(store.t("focusTimerSettingsSection")) {
                    durationStepper(
                        titleKey: "focusFocusDuration",
                        value: $focusMinutes,
                        range: 10...60
                    )
                    durationStepper(
                        titleKey: "focusShortBreakDuration",
                        value: $shortBreakMinutes,
                        range: 1...15
                    )
                    durationStepper(
                        titleKey: "focusLongBreakDuration",
                        value: $longBreakMinutes,
                        range: 5...30
                    )
                    Stepper(value: $longBreakEvery, in: 2...6) {
                        LabeledContent {
                            Text(
                                store.t(
                                    "focusRoundsValue",
                                    values: ["count": store.formatCount(longBreakEvery)]
                                )
                            )
                            .monospacedDigit()
                        } label: {
                            Text(store.t("focusLongBreakEvery"))
                        }
                    }
                }
                .disabled(isLocked)

                if let lockMessage {
                    Section {
                        Label(lockMessage, systemImage: "lock.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle(store.t("focusTimerSettings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.t("cancel"), role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("saveAction"), action: save)
                        .disabled(isLocked)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func durationStepper(
        titleKey: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        Stepper(value: value, in: range) {
            LabeledContent {
                Text(
                    store.t(
                        "minutesShort",
                        values: ["count": store.formatCount(value.wrappedValue)]
                    )
                )
                .monospacedDigit()
            } label: {
                Text(store.t(titleKey))
            }
        }
    }

    private func save() {
        guard !isLocked else { return }
        // The return value is the point: a rejected write used to dismiss the
        // sheet as if it had succeeded.
        guard store.updateFocusTimerSettings(
            FocusTimerSettings(
                focusMinutes: focusMinutes,
                shortBreakMinutes: shortBreakMinutes,
                longBreakMinutes: longBreakMinutes,
                longBreakEvery: longBreakEvery
            )
        ) else { return }
        dismiss()
    }
}
