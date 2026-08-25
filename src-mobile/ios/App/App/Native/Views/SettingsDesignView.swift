import SwiftUI

/// Direction 1e: one consistent grouped-row vocabulary for every setting.
struct SettingsDesignView: View {
    let store: OffWorkStore
    let wide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(store.t("settings"))
                .font(.largeTitle.bold())
                .tracking(-0.85)
                .padding(.horizontal, OWCDesign.contentInset)
                .padding(.top, 14)
                .padding(.bottom, 4)

            ForEach(SettingsSection.allCases) { section in
                SettingsSectionCard(store: store, section: section)
                    .padding(.horizontal, OWCDesign.pageInset)
                    .padding(.top, 14)
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: wide ? 680 : 402)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OWCDesign.page)
        .navigationTitle("")
    }

}
