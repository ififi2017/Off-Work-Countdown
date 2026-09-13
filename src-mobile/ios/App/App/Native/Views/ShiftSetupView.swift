import SwiftUI

/// The screen you see before a countdown is running.
///
/// Six facts, six slots. The previous layout rendered the shift times, the lunch
/// window and the schedule mode twice each, and split the leftover height evenly
/// across three `Spacer`s so the gaps grew with the device. Here the rhythm is
/// fixed, the slack collects above the action button, and the content is short
/// enough that the `GeometryReader` the old version needed is gone.
struct ShiftSetupView: View {
    @Environment(SceneState.self) private var scene
    let shifts: ShiftSessionStore
    let onOpenSettings: (AppRoute?) -> Void

    @State private var timeField: SetupTimeField?

    var body: some View {
        VStack(spacing: 0) {
            OWCAppHeader(preferences: shifts.preferences, text: shifts.text)

            // The hero stays put. It is the answer to the question this screen
            // asks — when does today start and end — and once the list below it
            // grew long enough to scroll, that answer was the first thing to
            // leave the screen. Only the list moves now.
            ShiftHeroCard(shifts: shifts) { timeField = $0 }
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.top, OWCDesign.heroGap)
                .padding(.bottom, OWCDesign.sectionGap)

            // The way back from an early clock-off, and the only way back.
            // Deliberately not a side effect of editing the schedule: changing
            // tomorrow's hours must never quietly resurrect today.
            if let note = shifts.session.earlyClockOffNote() {
                EarlyClockOffBanner(shifts: shifts, note: note)
                    .padding(.horizontal, OWCDesign.pageInset)
                    .padding(.bottom, OWCDesign.sectionGap)
            }

            ScrollView {
                ShiftSetupTimelineView(
                    shifts: shifts,
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
            ShiftStartButton(shifts: shifts) { onOpenSettings(.lunch) }
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.top, 10)
                .padding(.bottom, 14)
                // Opaque: the scroll view runs underneath this inset, and at
                // large text sizes the last row was showing through the button.
                .background(OWCDesign.page)
        }
        .sheet(item: $timeField) { field in
            OWCSetupTimePickerSheet(
                session: shifts.session,
                text: shifts.text,
                title: shifts.text.t(field == .start ? "startTime" : "endTime"),
                minutes: Binding(
                    get: { field == .start ? scene.displayedStartMinutes(using: shifts.preferences) : scene.displayedEndMinutes(using: shifts.preferences) },
                    set: { value in
                        if field == .start { scene.setDisplayedStartMinutes(value, using: shifts.preferences) }
                        else { scene.setDisplayedEndMinutes(value, using: shifts.preferences) }
                    }
                )
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}
