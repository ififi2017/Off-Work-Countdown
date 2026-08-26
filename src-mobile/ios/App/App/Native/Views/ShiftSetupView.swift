import SwiftUI

/// The screen you see before a countdown is running.
///
/// Six facts, six slots. The previous layout rendered the shift times, the lunch
/// window and the schedule mode twice each, and split the leftover height evenly
/// across three `Spacer`s so the gaps grew with the device. Here the rhythm is
/// fixed, the slack collects above the action button, and the content is short
/// enough that the `GeometryReader` the old version needed is gone.
struct ShiftSetupView: View {
    let store: OffWorkStore
    let onOpenSettings: (AppRoute?) -> Void

    @State private var timeField: SetupTimeField?

    /// Present only while an early clock-off still applies to a shift that has
    /// not run out on its own — once the planned end passes there is nothing
    /// left to undo.
    private var earlyClockOffNote: String? {
        guard let earlyOffAtMs = store.earlyOffAtMs,
              let shift = store.snapshot(),
              store.isEndedEarly(shift)
        else { return nil }
        let at = Date(timeIntervalSince1970: earlyOffAtMs / 1_000)
        return store.t("clockedOffEarlyNote", values: ["time": store.formatTime(at)])
    }

    var body: some View {
        VStack(spacing: 0) {
            OWCAppHeader(store: store)

            // The hero stays put. It is the answer to the question this screen
            // asks — when does today start and end — and once the list below it
            // grew long enough to scroll, that answer was the first thing to
            // leave the screen. Only the list moves now.
            ShiftHeroCard(store: store) { timeField = $0 }
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.top, OWCDesign.heroGap)
                .padding(.bottom, OWCDesign.sectionGap)

            // The way back from an early clock-off, and the only way back.
            // Deliberately not a side effect of editing the schedule: changing
            // tomorrow's hours must never quietly resurrect today.
            if let note = earlyClockOffNote {
                HStack(spacing: 10) {
                    Image(systemName: "figure.walk.departure")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(OWCDesign.secondary)
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(OWCDesign.secondary)
                    Spacer(minLength: 8)
                    Button(store.t("undoClockOffEarly")) { store.undoEarlyClockOff() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OWCDesign.accent)
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(OWCDesign.card, in: RoundedRectangle(cornerRadius: OWCDesign.cardRadius, style: .continuous))
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.bottom, OWCDesign.sectionGap)
            }

            ScrollView {
                ShiftSetupTimelineView(
                    store: store,
                    onSelect: { onOpenSettings($0) },
                    onEditTime: { timeField = $0 }
                )
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom) {
            ShiftStartButton(store: store) { onOpenSettings(.lunch) }
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.top, 10)
                .padding(.bottom, 14)
                // Opaque: the scroll view runs underneath this inset, and at
                // large text sizes the last row was showing through the button.
                .background(OWCDesign.page)
        }
        .sheet(item: $timeField) { field in
            OWCSetupTimePickerSheet(
                store: store,
                title: store.t(field == .start ? "startTime" : "endTime"),
                minutes: Binding(
                    get: { field == .start ? store.startMinutes : store.endMinutes },
                    set: { value in
                        if field == .start { store.startMinutes = value }
                        else { store.endMinutes = value }
                    }
                )
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}
