import SwiftUI

struct SettingsPlusStarToolbarButton: View {
    let plus: PlusEntitlement
    let text: AppText

    var body: some View {
        NavigationLink(value: AppRoute.plus) {
            if plus.isAuthorized {
                Label(text.t("plusSettings"), systemImage: "star.fill")
                    .foregroundStyle(OWCDesign.accent)
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "star")
                    Text(verbatim: "Plus")
                }
                .foregroundStyle(OWCDesign.accent)
            }
        }
        .accessibilityLabel(text.t("plusSettings"))
        .accessibilityValue(text.plusStatusLabel(for: plus))
    }
}
