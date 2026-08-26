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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: start) {
            Label(
                store.t(titleKey),
                systemImage: armState == .armed ? "exclamationmark.triangle.fill" : glyph
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
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .sensoryFeedback(.warning, trigger: armState)
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
    private var titleKey: String {
        if armState == .armed { return "nonWorkdayTapAgain" }
        if store.scheduleMode == .off { return "startCountdown" }
        return isNonWorkday ? "workTodayAnyway" : "applySettings"
    }

    private var glyph: String {
        if store.scheduleMode == .off { return "play.fill" }
        return isNonWorkday ? "play.fill" : "checkmark"
    }

    private var isNonWorkday: Bool {
        store.scheduleMode != .off && store.snapshot()?.isWorkday == false
    }

    private var isDisabled: Bool {
        store.startMinutes == store.endMinutes
            || (store.scheduleMode == .classic && store.workdays.isEmpty)
    }

    private func start() {
        guard store.isLunchInsideShift else {
            showInvalidLunch = true
            return
        }
        if isNonWorkday, armState == .idle {
            withAnimation(reduceMotion ? OWCMotion.reduced : OWCMotion.selection) {
                armState = .armed
            }
            return
        }
        store.startCountdown(force: isNonWorkday)
    }
}
