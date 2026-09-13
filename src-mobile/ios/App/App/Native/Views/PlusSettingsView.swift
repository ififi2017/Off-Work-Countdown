import SwiftUI

struct PlusSettingsView: View {
    let plus: PlusEntitlement
    let text: AppText

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !plus.isAuthorized {
                        Text(text.t("plusIntroTitle"))
                            .font(.title.bold())
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                    }

                    // The content, not the whole page. Embedding `PaywallView` put
                    // a second vertical scroll view inside this one.
                    PaywallContent(
                        plus: plus,
                        text: text,
                        showsBenefits: !plus.isAuthorized,
                        showsIntro: !plus.isAuthorized
                    )
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.horizontal, OWCDesign.contentInset)
                .padding(.top, 24)
                .frame(
                    minHeight: plus.isAuthorized
                        ? max(0, viewport.size.height - OWCDesign.detailBottomInset) : 0
                )
                .padding(.bottom, OWCDesign.detailBottomInset)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(OWCDesign.page)
        .owcDetailBack(
            title: text.t("settings"),
            pageTitle: text.t("plusSettings"),
            titleDisplayMode: .inline
        )
    }
}
