import SwiftUI

/// The primary action, shared by the portrait, landscape and iPad setup layouts.
///
/// Tapping on a day the schedule calls a rest day arms the button instead of
/// starting; a second tap within five seconds commits. `.task(id:)` owns the
/// disarm timer, so SwiftUI cancels it when the state changes or the view goes
/// away — the three hand-rolled `Task` handles this replaced each needed their
/// own `cancel()` in `onDisappear`, and one of them was easy to forget.
struct ShiftStartButton: View {
    let store: OffWorkStore
    // Declared before the closure so callers can use trailing-closure syntax.
    var minimumHeight: CGFloat = 46
    let onOpenLunchSettings: () -> Void

    @State private var armState = StartArmState.idle
    @State private var showInvalidLunch = false
    @State private var appliedPulse = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let nonWorkday = isDraftNonWorkday
        Button(action: { start(nonWorkday: nonWorkday) }) {
            Label(
                store.t(titleKey(nonWorkday: nonWorkday)),
                systemImage: armState == .armed ? "exclamationmark.triangle.fill" : glyph(nonWorkday: nonWorkday)
            )
            .lineLimit(2)
            .minimumScaleFactor(0.72)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
        }
        .buttonStyle(OWCPrimaryButtonStyle(
            color: armState == .armed ? OWCDesign.orangeDeep : OWCDesign.accent,
            minimumHeight: minimumHeight
        ))
        .contentShape(RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .sensoryFeedback(.warning, trigger: armState)
        .sensoryFeedback(.success, trigger: appliedPulse)
        .task(id: armState) {
            guard armState == .armed else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? OWCMotion.reduced : OWCMotion.selection) {
                armState = .idle
            }
        }
        .alert(store.t("invalidLunchTitle"), isPresented: $showInvalidLunch) {
            Button(store.t("return"), role: .cancel) {}
            Button(store.t("goToLunchSettings"), action: onOpenLunchSettings)
        } message: {
            Text(store.t("invalidLunchMessage"))
        }
    }

    /// One button, three honest names.
    ///
    /// The countdown starts itself on a schedule now, so on a workday this no
    /// longer starts anything — it applies what was just edited. On a day the
    /// schedule says is off, pressing it means working anyway, and calling that
    /// "apply settings" would hide the only consequence that matters. Manual
    /// mode still genuinely starts a session.
    private func titleKey(nonWorkday: Bool) -> String {
        if armState == .armed { return "nonWorkdayTapAgain" }
        if store.scheduleMode == .off { return "startCountdown" }
        return nonWorkday ? "workTodayAnyway" : "applySettings"
    }

    private func glyph(nonWorkday: Bool) -> String {
        if store.scheduleMode == .off { return "play.fill" }
        return nonWorkday ? "play.fill" : "checkmark"
    }

    private var isDraftNonWorkday: Bool {
        store.scheduleMode != .off && store.setupSnapshot()?.isWorkday == false
    }

    /// Hours that cannot form a shift. An empty classic workday set is not
    /// included: that state is a rest day, and "work today anyway" must stay
    /// tappable — it is how a user recovers after unchecking every day.
    private var isDisabled: Bool {
        store.displayedStartMinutes == store.displayedEndMinutes
    }

    private func start(nonWorkday: Bool) {
        guard store.isLunchInsideShift else {
            showInvalidLunch = true
            return
        }
        if nonWorkday, armState == .idle {
            withAnimation(reduceMotion ? OWCMotion.reduced : OWCMotion.selection) {
                armState = .armed
            }
            return
        }
        if store.scheduleMode == .off {
            store.startCountdown()
        } else {
            // Apply commits the draft. It is not undo — an early clock-off
            // covering today stays until the user presses undo, starts
            // overtime, or starts a different shift.
            store.applySettings(force: nonWorkday)
        }
        appliedPulse += 1
    }
}
