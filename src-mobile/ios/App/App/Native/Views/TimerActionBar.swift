import SwiftUI

struct TimerActionBar: View {
    let store: OffWorkStore
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
                store.requestClockInEarly(at: now)
            } label: {
                ClockInEarlyLabel(store: store, tinted: false)
            }
            .buttonStyle(OWCPrimaryButtonStyle(
                color: store.clockInConfirmPending ? OWCDesign.orangeDeep : OWCDesign.accent
            ))

            Button(store.t("shareButton"), systemImage: "square.and.arrow.up") {
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
                store.requestClockOffEarly(at: now)
            } label: {
                ClockOffEarlyLabel(store: store)
            }
            .buttonStyle(OWCSecondaryButtonStyle())

            Button {
                showOvertime = true
            } label: {
                Text(overtimeActive ? store.t("adjustOvertime") : store.t("overtime"))
            }
            .buttonStyle(OWCSecondaryButtonStyle())

            Button(store.t("shareButton"), systemImage: "square.and.arrow.up") {
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
