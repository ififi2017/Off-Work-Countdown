import SwiftUI

/// Direction 1e: one consistent grouped-row vocabulary for every setting.
struct SettingsDesignView: View {
    let store: OffWorkStore

    var body: some View {
        // Scrolls, because the sections outgrow the window. Four of them
        // already reached the tab bar at accessibility text sizes; the fifth
        // put "about" under it at the standard size on every phone.
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(SettingsSection.allCases) { section in
                    SettingsSectionCard(store: store, section: section)
                        .padding(.horizontal, OWCDesign.pageInset)
                        .padding(.top, 14)
                }
            }
            .padding(.bottom, 8)
        }
        // No measure cap. An iPhone is never wide enough to need one — the
        // widest is 440pt — and the old 402 was the Pro's width, so on a Pro Max
        // it left a 19pt stripe on each side that read as a layout mistake.
        // `pageInset` is what sets the margin; nothing else should.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OWCDesign.page)
        .navigationTitle(store.t("settings"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SettingsPlusStarToolbarButton(store: store)
            }
        }
    }
}

struct SettingsPlusStarToolbarButton: View {
    let store: OffWorkStore

    var body: some View {
        NavigationLink(value: AppRoute.plus) {
            if store.plus.isAuthorized {
                Label(store.t("plusSettings"), systemImage: "star.fill")
                    .foregroundStyle(OWCDesign.accent)
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "star")
                    Text(verbatim: "Plus")
                }
                .foregroundStyle(OWCDesign.accent)
            }
        }
        .accessibilityLabel(store.t("plusSettings"))
        .accessibilityValue(store.plusStatusLabel)
    }
}

struct SettingsPlusStarButton: View {
    let store: OffWorkStore

    var body: some View {
        NavigationLink(value: AppRoute.plus) {
            if store.plus.isAuthorized {
                Image(systemName: "star.fill")
                    .font(.body.weight(.semibold))
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "star")
                    Text(verbatim: "Plus")
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .owcTabletGlassAction()
        .foregroundStyle(OWCDesign.accent)
        .accessibilityLabel(store.t("plusSettings"))
        .accessibilityValue(store.plusStatusLabel)
    }
}
