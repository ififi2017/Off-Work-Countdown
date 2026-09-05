import SwiftUI

/// A one-time explanation at the first useful entry point after unlocking Plus.
/// Kept on the root so changing between phone and tablet shells cannot repeat it.
struct RecordsLifeSetupPromptModifier: ViewModifier {
    let store: OffWorkStore
    let paywallPresentationActive: Bool
    @Binding var presentationActive: Bool
    @State private var showsOffer = false
    @State private var showsEditor = false

    private var shouldOffer: Bool {
        !store.lifeSetupPromptDismissed && store.onboardingComplete && store.plus.hasSeenIntro
            && store.plus.isAuthorized && store.selectedTab == .records
            && store.records.state.lifeProfile == nil
            && store.recordsPath.isEmpty && store.editingDayKey == nil
            && !store.reviewPromptPresented
            && store.paywallSheet == nil && !paywallPresentationActive
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: showsOffer || showsEditor) { _, active in
                presentationActive = active
            }
            .onChange(of: shouldOffer, initial: true) { _, eligible in
                guard eligible else { return }
                store.lifeSetupPromptDismissed = true
                showsOffer = true
            }
            .alert(store.t("lifeSetupOfferTitle"), isPresented: $showsOffer) {
                Button(store.t("lifeSetupOfferAction")) { showsEditor = true }
                Button(store.t("notNow"), role: .cancel) {}
            } message: {
                Text(store.t("lifeSetupOfferBody"))
            }
            .sheet(isPresented: $showsEditor) {
                LifeProfileEditView(store: store)
            }
    }
}
