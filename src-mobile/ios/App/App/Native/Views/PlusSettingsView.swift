import SwiftUI

struct PlusSettingsView: View {
    let store: OffWorkStore

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !store.plus.isAuthorized {
                    Text(store.t("plusIntroTitle"))
                        .font(.title.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }

                // The content, not the whole page. Embedding `PaywallView` put
                // a second vertical scroll view inside this one.
                PaywallContent(
                    store: store,
                    showsBenefits: !store.plus.isAuthorized,
                    showsIntro: !store.plus.isAuthorized
                )
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, OWCDesign.contentInset)
            .padding(.top, 24)
        }
        .background(OWCDesign.page)
        .owcDetailBack(
            title: store.t("settings"),
            pageTitle: store.t("plusSettings"),
            titleDisplayMode: .inline
        )
    }
}
