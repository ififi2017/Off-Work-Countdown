import SwiftUI

struct FocusTaskIconPicker: View {
    let title: String
    var label: (FocusTaskIcon) -> String
    @Binding var selection: FocusTaskIcon

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
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
                        .accessibilityLabel(label(option))
                        .accessibilityAddTraits(selection == option ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct FocusTimerSettingsSheet: View {
    let focus: FocusStore
    let preferences: PreferencesStore

    @Environment(\.dismiss) private var dismiss
    @State private var liveActivityEnabled: Bool
    @State private var notificationsEnabled: Bool
    @State private var focusMinutes: Int
    @State private var shortBreakMinutes: Int
    @State private var longBreakMinutes: Int
    @State private var longBreakEvery: Int
    @State private var isSubmitting = false

    init(focus: FocusStore, preferences: PreferencesStore) {
        self.focus = focus
        self.preferences = preferences
        _liveActivityEnabled = State(initialValue: preferences.focusLiveActivityEnabled)
        _notificationsEnabled = State(initialValue: focus.focusNotificationsEnabled)
        let settings = focus.focusTimerSettings.normalized
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
        focus.activeFocusSession() != nil || focus.focusTimerSettingsLockReason != nil
    }

    private var lockMessage: String? {
        if focus.activeFocusSession() != nil {
            return focus.t("focusTimerSettingsLockedRunning")
        }
        if focus.focusTimerSettingsLockReason == .hasTemplates {
            return focus.t("focusTimerSettingsLockedTemplate")
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(focus.t("focusTimerSettingsBody"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section(focus.t("focusTimerSettingsSection")) {
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
                                focus.t(
                                    "focusRoundsValue",
                                    values: ["count": focus.formatCount(longBreakEvery)]
                                )
                            )
                            .monospacedDigit()
                        } label: {
                            Text(focus.t("focusLongBreakEvery"))
                        }
                    }
                }
                .disabled(isLocked)

                Section {
                    Toggle(focus.t("liveActivity"), isOn: $liveActivityEnabled)
                    Toggle(focus.t("notificationLocal"), isOn: $notificationsEnabled)
                }

                if let lockMessage {
                    Section {
                        Label(lockMessage, systemImage: "lock.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle(focus.t("focusTimerSettings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(focus.t("cancel"), role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(focus.t("saveAction"), action: save)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .disabled(isSubmitting)
        .interactiveDismissDisabled(isSubmitting)
    }

    private func durationStepper(
        titleKey: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        Stepper(value: value, in: range) {
            LabeledContent {
                Text(
                    focus.t(
                        "minutesShort",
                        values: ["count": focus.formatCount(value.wrappedValue)]
                    )
                )
                .monospacedDigit()
            } label: {
                Text(focus.t(titleKey))
            }
        }
    }

    private func save() {
        if isLocked {
            preferences.focusLiveActivityEnabled = liveActivityEnabled
            focus.focusNotificationsEnabled = notificationsEnabled
            dismiss()
            return
        }
        // The return value is the point: a rejected write used to dismiss the
        // sheet as if it had succeeded.
        let submitted = FocusTimerSettings(
            focusMinutes: focusMinutes,
            shortBreakMinutes: shortBreakMinutes,
            longBreakMinutes: longBreakMinutes,
            longBreakEvery: longBreakEvery
        )
        let submittedLiveActivity = liveActivityEnabled
        let submittedNotifications = notificationsEnabled
        let command = focus.updateFocusSettings(
            submitted,
            liveActivityEnabled: submittedLiveActivity,
            notificationsEnabled: submittedNotifications,
            preferences: preferences
        )
        if let saved = command.immediateResult {
            if saved { dismiss() }
            return
        }
        isSubmitting = true
        Task { @MainActor in
            let saved = await command.value
            isSubmitting = false
            guard saved,
                  focusMinutes == submitted.focusMinutes,
                  shortBreakMinutes == submitted.shortBreakMinutes,
                  longBreakMinutes == submitted.longBreakMinutes,
                  longBreakEvery == submitted.longBreakEvery,
                  liveActivityEnabled == submittedLiveActivity,
                  notificationsEnabled == submittedNotifications
            else { return }
            dismiss()
        }
    }
}
