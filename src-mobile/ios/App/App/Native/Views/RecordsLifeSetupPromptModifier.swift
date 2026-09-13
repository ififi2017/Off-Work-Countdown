import SwiftUI

/// A one-time explanation at the first useful entry point after unlocking Plus.
/// Kept on the root so changing between phone and tablet shells cannot repeat it.
struct RecordsLifeSetupPromptModifier: ViewModifier {
    @Environment(SceneState.self) private var scene
    let life: LifeSummaryModel
    let actions: RecordsActions
    let reviewPromptPresented: Bool
    let paywallPresentationActive: Bool
    let hasBlockingPresentation: Bool
    @Binding var presentationActive: Bool

    private var shouldOffer: Bool {
        !actions.preferences.lifeSetupPromptDismissed && actions.preferences.onboardingComplete && actions.plus.hasSeenIntro
            && actions.plus.isAuthorized && scene.selectedTab == .records
            && actions.records.state.lifeProfile == nil
            && scene.recordsPath.isEmpty && scene.dayEditor?.dayKey == nil
            && !reviewPromptPresented
            && scene.paywallSheet == nil && !paywallPresentationActive
            && !hasBlockingPresentation
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: scene.lifeSetupOfferPresented || scene.lifeSetupEditorPresented) { _, active in
                presentationActive = active
            }
            .onChange(of: shouldOffer, initial: true) { _, eligible in
                guard eligible else { return }
                scene.presentLifeSetupOffer()
            }
            .alert(actions.text.t("lifeSetupOfferTitle"), isPresented: Bindable(scene).lifeSetupOfferPresented) {
                Button(actions.text.t("lifeSetupOfferAction")) {
                    scene.consumeLifeSetupOffer(preferences: actions.preferences, opensEditor: true)
                }
                Button(actions.text.t("notNow"), role: .cancel) {
                    scene.consumeLifeSetupOffer(preferences: actions.preferences, opensEditor: false)
                }
            } message: {
                Text(actions.text.t("lifeSetupOfferBody"))
            }
            .sheet(isPresented: Bindable(scene).lifeSetupEditorPresented) {
                LifeProfileEditView(
                    life: life,
                    actions: actions,
                    preferences: actions.preferences,
                    text: actions.text
                )
            }
    }
}
