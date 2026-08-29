import SwiftUI

/// Lunch window, reminder preferences, and the Live Activity toggle.
///
/// This page writes the store directly, like the schedule form. Local
/// notification permission is requested by the shell when Continue is
/// tapped, and only if something on this page actually needs it. Live
/// Activity is a preference here — the system prompt waits until an
/// activity is really started. Extra reminder modes and Live Activity
/// lead time stay in Settings.
struct OnboardingRemindersPage: View {
    @Bindable var store: OffWorkStore
    let onContinue: () -> Void

    @FocusState private var durationFocused: Bool
    @State private var durationText = ""
    @State private var showLunchStartPicker = false
    @State private var continueFeedback = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            Text(store.t("onboardingRemindersTitle"))
                .font(.title.bold())
                .tracking(-0.6)
                .multilineTextAlignment(.center)
            Text(store.t("onboardingRemindersBody"))
                .font(.callout)
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 10)

            lunchCard
                .padding(.top, 22)

            if store.lunchEnabled {
                footnote(store.t("onboardingLunchNotifyHint"))
                    .padding(.top, 8)
            }

            remindersCard
                .padding(.top, store.lunchEnabled ? 16 : 22)

            footnote(store.t("onboardingRemindersMoreInSettings"))
                .padding(.top, 8)

            Spacer(minLength: 12)

            OnboardingDots(
                page: store.onboardingPage,
                includesAllSet: store.scheduleMode != .off
            )
            Button(store.t("continue")) {
                durationFocused = false
                clampDuration()
                continueFeedback += 1
                onContinue()
            }
            .buttonStyle(OWCPrimaryButtonStyle())
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 560)
        .sensoryFeedback(.impact(weight: .light), trigger: continueFeedback)
        .sensoryFeedback(.selection, trigger: store.lunchEnabled)
        .sensoryFeedback(.selection, trigger: store.notificationMode)
        .sensoryFeedback(.selection, trigger: store.microBreakEnabled)
        .sensoryFeedback(.selection, trigger: store.liveActivityEnabled)
        .onAppear {
            durationText = "\(store.lunchDurationMinutes)"
            store.applyOnboardingReminderDefaultsIfNeeded()
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
                Button(store.t("done")) {
                    durationFocused = false
                    clampDuration()
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .sheet(isPresented: $showLunchStartPicker) {
            OWCSetupTimePickerSheet(
                store: store,
                title: store.t("lunchStartTime"),
                minutes: $store.lunchStartMinutes
            )
            .presentationDetents([.medium])
        }
    }

    private var lunchCard: some View {
        OWCGroupCard {
            OWCRow(title: store.t("lunchBreak"), isLast: !store.lunchEnabled) {
                Toggle(store.t("lunchBreak"), isOn: lunchEnabledBinding)
                    .labelsHidden()
                    .tint(OWCDesign.accent)
            }

            if store.lunchEnabled {
                OWCRow(title: store.t("lunchStartTime")) {
                    Button {
                        showLunchStartPicker = true
                    } label: {
                        OWCDetailAccessory(text: store.timeString(store.lunchStartMinutes))
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    .buttonStyle(.plain)
                }

                OWCRow(title: store.t("lunchDuration"), isLast: true) {
                    HStack(spacing: 8) {
                        OWCNumberField(
                            placeholder: "60",
                            text: $durationText,
                            width: 58,
                            textAlignment: .center,
                            onCommit: clampDuration
                        )
                        .focused($durationFocused)
                        .padding(.vertical, 6)
                        .background(
                            OWCDesign.control,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        Text(store.t("minutesUnit"))
                            .font(.callout)
                            .foregroundStyle(OWCDesign.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(store.t("lunchDuration"))
                }
            }
        }
    }

    private var remindersCard: some View {
        OWCGroupCard {
            OWCRow(title: store.t("offWorkReminder")) {
                Toggle(store.t("offWorkReminder"), isOn: offWorkReminderBinding)
                    .labelsHidden()
                    .tint(OWCDesign.accent)
            }
            OWCRow(title: store.t("microBreakReminder")) {
                Toggle(store.t("microBreakReminder"), isOn: $store.microBreakEnabled)
                    .labelsHidden()
                    .tint(OWCDesign.accent)
            }
            OWCRow(title: store.t("liveActivity"), isLast: true) {
                Toggle(store.t("liveActivity"), isOn: $store.liveActivityEnabled)
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
            get: { store.lunchEnabled },
            set: { enabled in
                store.lunchEnabled = enabled
                store.lunchStartReminderEnabled = enabled
                store.lunchEndReminderEnabled = enabled
            }
        )
    }

    private var offWorkReminderBinding: Binding<Bool> {
        Binding(
            get: { store.notificationMode != .off },
            set: { enabled in
                store.notificationMode = enabled ? .simple : .off
            }
        )
    }

    private func clampDuration() {
        let typed = Int(durationText) ?? store.lunchDurationMinutes
        let clamped = min(180, max(10, typed))
        durationText = "\(clamped)"
        store.lunchDurationMinutes = clamped
    }
}
