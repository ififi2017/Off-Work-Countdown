import SwiftUI

/// Starts a manual session: a rest-day override, or an unscheduled day.
///
/// Tapping arms the button instead of starting; a second tap within five
/// seconds commits. `.task(id:)` owns the disarm timer.
struct ShiftStartButton: View {
    @Environment(SceneState.self) private var scene
    let shifts: ShiftSessionStore
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
                shifts.text.t(armState == .armed ? "nonWorkdayTapAgain" : "manualTiming"),
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
        .alert(shifts.text.t("invalidLunchTitle"), isPresented: $showInvalidLunch) {
            Button(shifts.text.t("return"), role: .cancel) {}
            Button(shifts.text.t("goToLunchSettings"), action: onOpenLunchSettings)
        } message: {
            Text(shifts.text.t("invalidLunchMessage"))
        }
    }

    private var isDisabled: Bool {
        scene.displayedStartMinutes(using: shifts.preferences) == scene.displayedEndMinutes(using: shifts.preferences)
    }

    private func start() {
        guard scene.isLunchInsideShift(using: shifts) else {
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
        let forceRestDay = shifts.session.followsSchedule
        let command = scene.startCountdown(force: forceRestDay, using: shifts)
        Task {
            if await command.value { appliedPulse += 1 }
        }
    }
}
