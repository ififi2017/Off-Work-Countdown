import SwiftUI

/// Direction 1e: one consistent grouped-row vocabulary for every setting.
struct SettingsDesignView: View {
    let shifts: ShiftSessionStore
    let recovery: RecoveryStore

    var body: some View {
        // Scrolls, because the sections outgrow the window. Four of them
        // already reached the tab bar at accessibility text sizes; the fifth
        // put "about" under it at the standard size on every phone.
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(SettingsSection.allCases) { section in
                    SettingsSectionCard(shifts: shifts, recovery: recovery, section: section)
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
        .navigationTitle(shifts.text.t("settings"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SettingsPlusStarToolbarButton(plus: shifts.plus, text: shifts.text)
            }
        }
    }
}

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

struct SettingsPlusStarButton: View {
    let plus: PlusEntitlement
    let text: AppText

    var body: some View {
        NavigationLink(value: AppRoute.plus) {
            if plus.isAuthorized {
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
        .accessibilityLabel(text.t("plusSettings"))
        .accessibilityValue(text.plusStatusLabel(for: plus))
    }
}
