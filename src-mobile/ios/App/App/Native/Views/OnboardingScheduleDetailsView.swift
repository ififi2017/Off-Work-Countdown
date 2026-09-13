import SwiftUI

/// The configuration controlled by the four schedule rows above it.
///
/// Only the visible panel is in the layout. Stacking every mode in a `ZStack`
/// used to size the stage to the tallest panel (rotation), so the first-run
/// classic grid reserved empty space and English copy that wrapped a line
/// pushed Continue off the screen. Mode changes swap the panel while it is
/// faded out, so the height change is not on screen.
struct OnboardingScheduleDetailsView: View {
    @Bindable var preferences: PreferencesStore
    let text: AppText
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var displayedMode: WorkScheduleMode
    @State private var pendingMode: WorkScheduleMode
    @State private var detailsVisible = true

    init(preferences: PreferencesStore, text: AppText) {
        self.preferences = preferences
        self.text = text
        _displayedMode = State(initialValue: preferences.scheduleMode)
        _pendingMode = State(initialValue: preferences.scheduleMode)
    }

    var body: some View {
        details(for: displayedMode)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .opacity(detailsVisible ? 1 : 0)
            .offset(y: detailOffset)
            .allowsHitTesting(detailsVisible)
            .accessibilityHidden(!detailsVisible)
            .onChange(of: preferences.scheduleMode) { _, mode in
                transition(to: mode)
            }
    }

    @ViewBuilder
    private func details(for mode: WorkScheduleMode) -> some View {
        switch mode {
        case .classic:
            VStack(alignment: .leading, spacing: 0) {
                Text(text.t("workdaysLabel"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OWCDesign.secondary)
                weekdayGrid
                    .padding(.top, 8)
                Text(text.t("keepAtLeastOneWorkday"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .padding(.top, 8)
            }
        case .alternating:
            OWCGroupCard {
                VStack(alignment: .leading, spacing: 9) {
                    Text(text.t("alternatingCurrentWeek"))
                        .font(.subheadline.weight(.semibold))
                    Picker(text.t("alternatingCurrentWeek"), selection: Binding(
                        get: { preferences.alternatingWeekType },
                        set: { preferences.applySetupScheduleChange(ScheduleFieldChange(alternatingWeekType: $0)) }
                    )) {
                        Text(text.t("singleRestWeek")).tag(AlternatingWeekType.single)
                        Text(text.t("doubleRestWeek")).tag(AlternatingWeekType.double)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(12)
                .overlay(alignment: .bottomTrailing) {
                    Rectangle()
                        .fill(OWCDesign.separator)
                        .frame(height: 0.5)
                        .padding(.leading, 16)
                }
                VStack(alignment: .leading, spacing: 9) {
                    Text(text.t("singleWeekWorkday"))
                        .font(.subheadline.weight(.semibold))
                    Picker(text.t("singleWeekWorkday"), selection: preferences.preferenceBinding(\.alternatingWeekendWorkday)) {
                        Text(text.t("workOnWeekday", values: ["day": text.weekdayLabels()[5]])).tag(6)
                        Text(text.t("workOnWeekday", values: ["day": text.weekdayLabels()[6]])).tag(0)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(12)
            }
        case .rotation:
            OWCGroupCard {
                Stepper(value: preferences.preferenceBinding(\.rotationWorkDays), in: 1...30) {
                    OWCRow(title: text.t("rotationWorkDays")) {
                        Text("\(preferences.rotationWorkDays)")
                            .monospacedDigit()
                            .foregroundStyle(OWCDesign.secondary)
                    }
                }
                .padding(.trailing, 16)
                .overlay(alignment: .bottomTrailing) {
                    Rectangle()
                        .fill(OWCDesign.separator)
                        .frame(height: 0.5)
                        .padding(.leading, 16)
                }
                Stepper(value: preferences.preferenceBinding(\.rotationRestDays), in: 1...30) {
                    OWCRow(title: text.t("rotationRestDays")) {
                        Text("\(preferences.rotationRestDays)")
                            .monospacedDigit()
                            .foregroundStyle(OWCDesign.secondary)
                    }
                }
                .padding(.trailing, 16)
                .overlay(alignment: .bottomTrailing) {
                    Rectangle()
                        .fill(OWCDesign.separator)
                        .frame(height: 0.5)
                        .padding(.leading, 16)
                }
                Menu {
                    ForEach(1...preferences.rotationCycleLength, id: \.self) { day in
                        Button {
                            preferences.applySetupScheduleChange(ScheduleFieldChange(rotationCycleDay: day))
                        } label: {
                            Label(
                                text.t(
                                    day <= preferences.rotationWorkDays ? "rotationWorkdayOption" : "rotationRestdayOption",
                                    values: ["day": "\(day)"]
                                ),
                                systemImage: day <= preferences.rotationWorkDays ? "briefcase" : "bed.double"
                            )
                        }
                    }
                } label: {
                    OWCRow(
                        icon: "repeat",
                        title: text.t("rotationStartDay", values: ["day": "\(preferences.rotationCycleDay)"]),
                        isLast: true
                    ) {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(OWCDesign.tertiary)
                    }
                }
                .buttonStyle(OWCRowButtonStyle())
            }
        case .off:
            OWCGroupCard {
                OWCRow(
                    icon: "calendar.badge.minus",
                    title: text.t("scheduleOffManualStart"),
                    isLast: true
                ) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(OWCDesign.accent)
                }
            }
        }
    }

    private var weekdayGrid: some View {
        HStack(spacing: 6) {
            ForEach(Array(zip([1, 2, 3, 4, 5, 6, 0], text.weekdayLabels())), id: \.0) { day, label in
                let selected = preferences.workdays.contains(day)
                let locked = selected && preferences.workdays.count == 1
                OWCWeekdayButton(
                    label: label, selected: selected, locked: locked,
                    differentiateWithoutColor: differentiateWithoutColor,
                    lockedHint: text.t("keepAtLeastOneWorkday")
                ) { preferences.toggleWorkday(day) }
            }
        }
        .padding(12)
        .background(OWCDesign.card)
        .clipShape(RoundedRectangle(cornerRadius: OWCDesign.cardRadius, style: .continuous))
    }

    private var detailOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        return detailsVisible ? 0 : -6
    }

    /// Fade the old panel completely before revealing the latest requested
    /// panel. Updating `pendingMode` while the exit is in flight coalesces fast
    /// taps, so obsolete panels never flash between the user's finger and the
    /// final choice.
    private func transition(to mode: WorkScheduleMode) {
        pendingMode = mode

        if mode == displayedMode {
            guard !detailsVisible else { return }
            withAnimation(reduceMotion ? OWCMotion.reduced : OWCMotion.stateEnter) {
                detailsVisible = true
            }
            return
        }

        guard detailsVisible else { return }

        withAnimation(
            reduceMotion ? OWCMotion.reduced : OWCMotion.stateExit,
            completionCriteria: .logicallyComplete
        ) {
            detailsVisible = false
        } completion: {
            displayedMode = pendingMode
            withAnimation(reduceMotion ? OWCMotion.reduced : OWCMotion.stateEnter) {
                detailsVisible = true
            }
        }
    }
}
