import SwiftUI

/// A quiet brand handoff between first-run setup and the live timer.
///
/// The mark stays interactive here because this is the one point in
/// onboarding where the user is invited to stop rather than read or configure.
struct OnboardingFinalePage: View {
    @Bindable var store: OffWorkStore
    let logoSize: CGFloat
    let onFinish: () -> Void

    @State private var finishFeedback = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            CelebratingBrandMark()
                .frame(width: logoSize, height: logoSize)

            Text(verbatim: OWCBrand.shortName)
                .font(.largeTitle.bold())
                .tracking(-0.8)
                .multilineTextAlignment(.center)
                .padding(.top, 22)

            Text(store.t("onboardingFinaleMessage"))
                .font(.body)
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)

            Spacer(minLength: 24)

            OnboardingDots(
                page: store.onboardingPage,
                includesAllSet: store.scheduleMode != .off
            )
            Button(
                store.t("onboardingStartExperience"),
                action: finish
            )
            .buttonStyle(OWCPrimaryButtonStyle())
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 560)
        .sensoryFeedback(.success, trigger: finishFeedback)
    }

    private func finish() {
        finishFeedback += 1
        // RootView owns the single completion transition: this page fades and
        // expands slightly while the correctly sized timer shell fades in.
        // Keeping the state change here unwrapped avoids two competing
        // animation transactions and the settling jump they used to create.
        onFinish()
    }
}
