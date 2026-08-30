import SwiftUI

struct PlusSettingsView: View {
    let store: OffWorkStore

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OWCGroupCard {
                    statusRow
                }
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.top, 14)

                if store.plus.hasActiveSubscription {
                    Text(store.t("plusAlsoHasSubscription"))
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                        .padding(.horizontal, 36)
                        .padding(.top, 10)
                }

                PaywallView(store: store, reason: .intro, showsSkip: false)
                    .padding(.top, 8)

                Button(store.t("plusManage")) {
                    store.plus.manageSubscriptions()
                }
                .font(.body)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
            }
        }
        .background(OWCDesign.page)
        .navigationTitle(store.t("plusSettings"))
        .navigationBarTitleDisplayMode(.large)
        .owcDetailBack(title: store.t("settings"), pageTitle: store.t("plusSettings"))
    }

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(statusTitle)
                .font(.body.weight(.medium))
            if case .authorized(.subscribed(let expires)) = store.plus.authorization {
                Text(expires.formatted(date: .abbreviated, time: .omitted))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
            }
            if case .authorized(.inGracePeriod(let expires)) = store.plus.authorization {
                Text(expires.formatted(date: .abbreviated, time: .omitted))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var statusTitle: String {
        switch store.plus.authorization {
        case .authorized(.lifetime):
            return store.t("plusStatusLifetime")
        case .authorized(.subscribed), .authorized(.inGracePeriod):
            return store.t("plusStatusSubscribed")
        case .pendingAskToBuy:
            return store.t("plusWaitingApproval")
        default:
            return store.t("plusStatusNone")
        }
    }
}
