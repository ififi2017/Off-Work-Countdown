import SwiftUI

struct TimerActionBar: View {
    let store: OffWorkStore
    let overtimeActive: Bool
    @Binding var showShare: Bool
    @Binding var showOvertime: Bool


    var body: some View {
        HStack(spacing: 10) {
            Button {
                store.requestClockOffEarly()
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
        .padding(.horizontal, OWCDesign.pageInset)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }
}
