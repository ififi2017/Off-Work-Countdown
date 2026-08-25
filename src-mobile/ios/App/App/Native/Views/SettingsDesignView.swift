import SwiftUI

/// Direction 1e: one consistent grouped-row vocabulary for every setting.
struct SettingsDesignView: View {
    let store: OffWorkStore

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
        // No measure cap. An iPhone is never wide enough to need one — the
        // widest is 440pt — and the old 402 was the Pro's width, so on a Pro Max
        // it left a 19pt stripe on each side that read as a layout mistake.
        // `pageInset` is what sets the margin; nothing else should.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OWCDesign.page)
        .navigationTitle("")
    }

}
