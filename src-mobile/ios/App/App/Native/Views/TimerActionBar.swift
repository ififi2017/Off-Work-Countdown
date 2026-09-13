import SwiftUI

struct TimerActionBar: View {
    @Environment(SceneState.self) private var scene
    let shifts: ShiftSessionStore
    let snapshot: NativeShiftSnapshot
    let now: Date
    @Binding var showShare: Bool
    @Binding var showOvertime: Bool

    private var beforeStart: Bool { snapshot.isBeforeStart(at: now) }
    private var overtimeActive: Bool { snapshot.isOvertimeActive(at: now) }

    var body: some View {
        Group {
            if beforeStart {
                beforeStartBar
            } else {
                runningBar
            }
        }
        .padding(.horizontal, OWCDesign.pageInset)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var beforeStartBar: some View {
        HStack(spacing: 10) {
            Button {
                scene.requestClockInEarly(at: now, using: shifts)
            } label: {
                ClockInEarlyLabel(shifts: shifts, now: now, tinted: false)
            }
            .buttonStyle(OWCPrimaryButtonStyle(
                color: scene.isClockInConfirmationArmed(at: now, using: shifts)
                    ? OWCDesign.orangeDeep : OWCDesign.accent
            ))

            Button(shifts.text.t("shareButton"), systemImage: "square.and.arrow.up") {
                showShare = true
            }
            .labelStyle(.iconOnly)
            .font(.body)
            .frame(width: 50, height: 50)
            .foregroundStyle(OWCDesign.primary)
            .background(OWCDesign.control)
            .clipShape(RoundedRectangle(cornerRadius: OWCDesign.controlRadius))
            .buttonStyle(.plain)
        }
    }

    private var runningBar: some View {
        HStack(spacing: 10) {
            Button {
                scene.requestClockOffEarly(at: now, using: shifts)
            } label: {
                ClockOffEarlyLabel(shifts: shifts, now: now)
            }
            .buttonStyle(OWCSecondaryButtonStyle())

            Button {
                showOvertime = true
            } label: {
                Text(overtimeActive ? shifts.text.t("adjustOvertime") : shifts.text.t("overtime"))
            }
            .buttonStyle(OWCSecondaryButtonStyle())

            Button(shifts.text.t("shareButton"), systemImage: "square.and.arrow.up") {
                showShare = true
            }
            .labelStyle(.iconOnly)
            .font(.body)
            .frame(width: 50, height: 50)
            .foregroundStyle(OWCDesign.primary)
            .background(OWCDesign.control)
            .clipShape(RoundedRectangle(cornerRadius: OWCDesign.controlRadius))
            .buttonStyle(.plain)
        }
    }
}
