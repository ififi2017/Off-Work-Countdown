import SwiftUI

/// The label on the button that ends the day, in both of its states.
///
/// Shared across the active timer layouts because this is the second thing
/// about the action that has to stay identical everywhere. The first was the
/// confirmation state itself, which is why that lives on the store.
///
/// The armed appearance deliberately copies `ShiftStartButton`: the same deep
/// orange, the same warning glyph. That button already teaches "this one needs
/// a second press", and teaching it twice with two different vocabularies would
/// be worse than not teaching it at all.
struct ClockOffEarlyLabel: View {
    let store: OffWorkStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var armed: Bool { store.clockOffConfirmPending }

    private var titleKey: String {
        // Manual mode still has a session to leave rather than a day to record.
        if store.scheduleMode == .off { return "return" }
        return armed ? "clockOffEarlyConfirm" : "clockOffEarly"
    }

    var body: some View {
        Label(
            store.t(titleKey),
            systemImage: armed ? "exclamationmark.triangle.fill" : "arrow.left"
        )
        // Tint rather than a button style: three of the five call sites apply
        // their style to an enclosing stack, so a style here would be overridden
        // in some places and fight it in others.
        .foregroundStyle(armed ? OWCDesign.orangeDeep : OWCDesign.primary)
        .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.selection, value: armed)
        .sensoryFeedback(.warning, trigger: armed)
        // Disarms itself, like the start button does. A confirmation left
        // standing is one the user meets again much later, having forgotten it,
        // and fires with a press they meant as their first.
        .task(id: armed) {
            guard armed else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            store.cancelClockOffConfirmation()
        }
    }
}
