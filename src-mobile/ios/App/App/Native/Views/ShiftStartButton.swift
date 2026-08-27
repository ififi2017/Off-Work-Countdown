import SwiftUI

/// Starts a manual session: a rest-day override, or an unscheduled day.
///
/// Tapping arms the button instead of starting; a second tap within five
/// seconds commits. `.task(id:)` owns the disarm timer.
struct ShiftStartButton: View {
    let store: OffWorkStore
    var minimumHeight: CGFloat = 46
    let onOpenLunchSettings: () -> Void

    @State private var armState = StartArmState.idle
    @State private var showInvalidLunch = false
    @State private var warningPulse = 0
    @State private var appliedPulse = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: start) {
            Label(
                store.t(armState == .armed ? "nonWorkdayTapAgain" : "manualTiming"),
                systemImage: armState == .armed ? "exclamationmark.triangle.fill" : "play.fill"
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
        .sensoryFeedback(.warning, trigger: warningPulse)
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

    private var isDisabled: Bool {
        store.startMinutes == store.endMinutes
    }

    private func start() {
        guard store.isLunchInsideShift else {
            showInvalidLunch = true
            return
        }
        if armState == .idle {
            warningPulse += 1
            withAnimation(reduceMotion ? OWCMotion.reduced : OWCMotion.selection) {
                armState = .armed
            }
            return
        }
        let forceRestDay = store.followsSchedule
        store.startCountdown(force: forceRestDay)
        appliedPulse += 1
    }
}
