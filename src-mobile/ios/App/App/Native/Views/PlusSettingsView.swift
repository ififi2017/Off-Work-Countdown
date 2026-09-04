import SwiftUI

struct PlusSettingsView: View {
    let store: OffWorkStore

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !store.plus.isAuthorized {
                    OWCGroupCard {
                        statusRow
                    }
                    .padding(.horizontal, OWCDesign.pageInset)
                    .padding(.top, 14)
                }

                // The content, not the whole page. Embedding `PaywallView` put
                // a second vertical scroll view inside this one.
                PaywallContent(
                    store: store,
                    showsBenefits: !store.plus.isAuthorized,
                    showsIntro: false
                )
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
            }
        }
        .background(OWCDesign.page)
        .navigationTitle(store.t("plusSettings"))
        .navigationBarTitleDisplayMode(.large)
        .owcDetailBack(title: store.t("settings"), pageTitle: store.t("plusSettings"))
    }

    private var statusRow: some View {
        OWCRow(
            icon: statusIcon,
            title: store.t("plusStatus"),
            subtitle: statusDetail,
            isLast: true,
            centersVertically: true
        ) {
            Text(store.plusStatusLabel)
                .font(.body.weight(.medium))
                .foregroundStyle(store.plus.isAuthorized ? OWCDesign.accent : OWCDesign.secondary)
        }
    }

    private var statusIcon: String {
        store.plus.isAuthorized ? "checkmark.seal" : "seal"
    }

    /// The renewal date, or why there is none. `plusStatusLabel` carries the
    /// state itself so this page and the settings row cannot disagree.
    private var statusDetail: String? {
        switch store.plus.authorization {
        case .authorized(.lifetime):
            return store.t("plusLifetimeDetail")
        case .authorized(.subscribed(let expires)):
            return store.t("plusRenewsOn", values: ["date": store.formatDate(expires)])
        case .authorized(.inGracePeriod(let expires)):
            return store.t("plusGraceUntil", values: ["date": store.formatDate(expires)])
        case .pendingAskToBuy:
            return store.t("plusWaitingApproval")
        case .unauthorized:
            return nil
        }
    }
}
