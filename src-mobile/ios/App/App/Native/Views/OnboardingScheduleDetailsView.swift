import SwiftUI

/// The configuration controlled by the four schedule rows above it.
///
/// Only the visible panel is in the layout. Stacking every mode in a `ZStack`
/// used to size the stage to the tallest panel (rotation), so the first-run
/// classic grid reserved empty space and English copy that wrapped a line
/// pushed Continue off the screen. Mode changes swap the panel while it is
/// faded out, so the height change is not on screen.
struct OnboardingScheduleDetailsView: View {
    @Bindable var store: OffWorkStore
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var displayedMode: WorkScheduleMode
    @State private var pendingMode: WorkScheduleMode
    @State private var detailsVisible = true

    init(store: OffWorkStore) {
        self.store = store
        _displayedMode = State(initialValue: store.scheduleMode)
        _pendingMode = State(initialValue: store.scheduleMode)
    }

    var body: some View {
        details(for: displayedMode)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .opacity(detailsVisible ? 1 : 0)
            .offset(y: detailOffset)
            .allowsHitTesting(detailsVisible)
            .accessibilityHidden(!detailsVisible)
            .onChange(of: store.scheduleMode) { _, mode in
                transition(to: mode)
            }
    }

    @ViewBuilder
    private func details(for mode: WorkScheduleMode) -> some View {
        switch mode {
        case .classic:
            VStack(alignment: .leading, spacing: 0) {
                Text(store.t("workdaysLabel"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OWCDesign.secondary)
                weekdayGrid
                    .padding(.top, 8)
                Text(store.t("keepAtLeastOneWorkday"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .padding(.top, 8)
            }
        case .alternating:
            OWCGroupCard {
                VStack(alignment: .leading, spacing: 9) {
                    Text(store.t("alternatingCurrentWeek"))
                        .font(.subheadline.weight(.semibold))
                    Picker(store.t("alternatingCurrentWeek"), selection: $store.alternatingWeekType) {
                        Text(store.t("singleRestWeek")).tag(AlternatingWeekType.single)
                        Text(store.t("doubleRestWeek")).tag(AlternatingWeekType.double)
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
                    Text(store.t("singleWeekWorkday"))
                        .font(.subheadline.weight(.semibold))
                    Picker(store.t("singleWeekWorkday"), selection: $store.alternatingWeekendWorkday) {
                        Text(store.t("workOnWeekday", values: ["day": store.weekdayLabels()[5]])).tag(6)
                        Text(store.t("workOnWeekday", values: ["day": store.weekdayLabels()[6]])).tag(0)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(12)
            }
            .onChange(of: store.alternatingWeekType) { store.anchorAlternatingWeekToToday() }
        case .rotation:
            OWCGroupCard {
                Stepper(value: $store.rotationWorkDays, in: 1...30) {
                    OWCRow(title: store.t("rotationWorkDays")) {
                        Text("\(store.rotationWorkDays)")
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
                Stepper(value: $store.rotationRestDays, in: 1...30) {
                    OWCRow(title: store.t("rotationRestDays")) {
                        Text("\(store.rotationRestDays)")
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
                    ForEach(1...store.rotationCycleLength, id: \.self) { day in
                        Button {
                            store.setRotationCycleDay(day)
                        } label: {
                            Label(
                                store.t(
                                    day <= store.rotationWorkDays ? "rotationWorkdayOption" : "rotationRestdayOption",
                                    values: ["day": "\(day)"]
                                ),
                                systemImage: day <= store.rotationWorkDays ? "briefcase" : "bed.double"
                            )
                        }
                    }
                } label: {
                    OWCRow(
                        icon: "repeat",
                        title: store.t("rotationStartDay", values: ["day": "\(store.rotationCycleDay)"]),
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
                    title: store.t("scheduleOffManualStart"),
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
            ForEach(Array(zip([1, 2, 3, 4, 5, 6, 0], store.weekdayLabels())), id: \.0) { day, label in
                let selected = store.workdays.contains(day)
                let locked = selected && store.workdays.count == 1
                Button {
                    if locked { return }
                    store.toggleWorkday(day)
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Text(label)
                            .font(.footnote.weight(selected ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                            .foregroundStyle(selected ? Color(uiColor: .systemBackground) : OWCDesign.secondary)
                            .frame(maxWidth: .infinity, minHeight: 46)

                        if differentiateWithoutColor, selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(Color(uiColor: .systemBackground))
                                .padding(4)
                        }
                    }
                    .background(selected ? OWCDesign.accent : OWCDesign.control)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .opacity(locked ? 0.55 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityHint(locked ? store.t("keepAtLeastOneWorkday") : "")
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
