import SwiftUI

struct PlusSettingsView: View {
    let plus: PlusEntitlement
    let text: AppText

    var body: some View {
        Group {
            if !plus.isAuthorized {
                PaywallView(plus: plus, text: text, showsDismissButton: false)
            } else {
                GeometryReader { viewport in
                    ScrollView {
                        PaywallContent(plus: plus, text: text, showsBenefits: false, showsIntro: false)
                            .frame(maxWidth: 560, alignment: .leading)
                            .padding(.horizontal, OWCDesign.contentInset)
                            .padding(.top, 24)
                            .frame(minHeight: max(0, viewport.size.height - OWCDesign.detailBottomInset))
                            .padding(.bottom, OWCDesign.detailBottomInset)
                            .frame(maxWidth: .infinity)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
        .background(OWCDesign.page)
        .owcDetailBack(
            title: text.t("settings"),
            pageTitle: text.t("plusSettings"),
            titleDisplayMode: .inline
        )
    }
}
