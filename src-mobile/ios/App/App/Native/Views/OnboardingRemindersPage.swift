import SwiftUI

/// Lunch window, reminder preferences, and the Live Activity toggle.
///
/// This page writes preferences directly, like the schedule form. Local
/// notification permission is requested by the shell when Continue is
/// tapped, and only if something on this page actually needs it. Live
/// Activity is a preference here — the system prompt waits until an
/// activity is really started. Extra reminder modes and Live Activity
/// lead time stay in Settings.
struct OnboardingRemindersPage: View {
    @Environment(SceneState.self) private var scene
    @Bindable var preferences: PreferencesStore
    let session: ShiftSession
    let text: AppText
    let onContinue: () -> Void

    @FocusState private var durationFocused: Bool
    @State private var durationText = ""
    @State private var showLunchStartPicker = false
    @State private var continueFeedback = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            Text(text.t("onboardingRemindersTitle"))
                .font(.title.bold())
                .tracking(-0.6)
                .multilineTextAlignment(.center)
            Text(text.t("onboardingRemindersBody"))
                .font(.callout)
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 10)

            lunchCard
                .padding(.top, 22)

            if preferences.lunchEnabled {
                footnote(text.t("onboardingLunchNotifyHint"))
                    .padding(.top, 8)
            }

            remindersCard
                .padding(.top, preferences.lunchEnabled ? 16 : 22)

            footnote(text.t("onboardingRemindersMoreInSettings"))
                .padding(.top, 8)

            Spacer(minLength: 12)

            OnboardingDots(
                page: scene.onboardingPage,
                includesAllSet: preferences.scheduleMode != .off
            )
            Button(text.t("continue")) {
                durationFocused = false
                continueFeedback += 1
                let command = clampDuration()
                Task {
                    _ = await command.value
                    onContinue()
                }
            }
            .buttonStyle(OWCPrimaryButtonStyle())
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 560)
        .sensoryFeedback(.impact(weight: .light), trigger: continueFeedback)
        .sensoryFeedback(.selection, trigger: preferences.lunchEnabled)
        .sensoryFeedback(.selection, trigger: preferences.notificationMode)
        .sensoryFeedback(.selection, trigger: preferences.microBreakEnabled)
        .sensoryFeedback(.selection, trigger: preferences.liveActivityEnabled)
        .onAppear {
            durationText = "\(preferences.lunchDurationMinutes)"
            preferences.applyOnboardingReminderDefaultsIfNeeded()
        }
        .onChange(of: durationFocused) { _, focused in
            if !focused { clampDuration() }
        }
        .toolbar {
            // A `ToolbarItemGroup` with a leading `Spacer` builds a full-width
            // accessory bar. On iOS 26 that bar's glass fallback is opaque
            // white, so dismissing the number pad left a white overlay on the
            // continue row for a frame. One trailing item is just the Done
            // chip; hiding the shared glass stops the fallback flash.
            ToolbarItem(placement: .keyboard) {
                Button(text.t("done")) {
                    durationFocused = false
                    clampDuration()
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .sheet(isPresented: $showLunchStartPicker) {
            OWCSetupTimePickerSheet(
                session: session,
                text: text,
                title: text.t("lunchStartTime"),
                minutes: preferences.preferenceBinding(\.lunchStartMinutes)
            )
            .presentationDetents([.medium])
        }
    }

    private var lunchCard: some View {
        OWCGroupCard {
            OWCRow(title: text.t("lunchBreak"), isLast: !preferences.lunchEnabled) {
                Toggle(text.t("lunchBreak"), isOn: lunchEnabledBinding)
                    .labelsHidden()
                    .tint(OWCDesign.accent)
            }

            if preferences.lunchEnabled {
                OWCRow(title: text.t("lunchStartTime")) {
                    Button {
                        showLunchStartPicker = true
                    } label: {
                        OWCDetailAccessory(text: session.timeString(preferences.lunchStartMinutes))
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    .buttonStyle(.plain)
                }

                OWCRow(title: text.t("lunchDuration"), isLast: true) {
                    HStack(spacing: 8) {
                        OWCNumberField(
                            placeholder: "60",
                            text: $durationText,
                            width: 58,
                            textAlignment: .center,
                            onCommit: { _ = clampDuration() }
                        )
                        .focused($durationFocused)
                        .padding(.vertical, 6)
                        .background(
                            OWCDesign.control,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        Text(text.t("minutesUnit"))
                            .font(.callout)
                            .foregroundStyle(OWCDesign.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(text.t("lunchDuration"))
                }
            }
        }
    }

    private var remindersCard: some View {
        OWCGroupCard {
            OWCRow(title: text.t("offWorkReminder")) {
                Toggle(text.t("offWorkReminder"), isOn: offWorkReminderBinding)
                    .labelsHidden()
                    .tint(OWCDesign.accent)
            }
            OWCRow(title: text.t("microBreakReminder")) {
                Toggle(text.t("microBreakReminder"), isOn: preferences.preferenceBinding(\.microBreakEnabled))
                    .labelsHidden()
                    .tint(OWCDesign.accent)
            }
            OWCRow(title: text.t("liveActivity"), isLast: true) {
                Toggle(text.t("liveActivity"), isOn: Binding(get: { preferences.liveActivityEnabled }, set: { preferences.liveActivityEnabled = $0 }))
                    .labelsHidden()
                    .tint(OWCDesign.accent)
            }
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(OWCDesign.secondary)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
    }

    private var lunchEnabledBinding: Binding<Bool> {
        Binding(
            get: { preferences.lunchEnabled },
            set: { enabled in
                preferences.applyPreferences {
                    $0.lunchEnabled = enabled
                    $0.lunchStartReminderEnabled = enabled
                    $0.lunchEndReminderEnabled = enabled
                }
            }
        )
    }

    private var offWorkReminderBinding: Binding<Bool> {
        Binding(
            get: { preferences.notificationMode != .off },
            set: { enabled in
                preferences.applyPreferences { $0.notificationMode = enabled ? .simple : .off }
            }
        )
    }

    @discardableResult
    private func clampDuration() -> RecordCommand<Bool> {
        let typed = Int(durationText) ?? preferences.lunchDurationMinutes
        let clamped = min(180, max(10, typed))
        durationText = "\(clamped)"
        return preferences.applyPreferences { $0.lunchDurationMinutes = clamped }
    }
}
