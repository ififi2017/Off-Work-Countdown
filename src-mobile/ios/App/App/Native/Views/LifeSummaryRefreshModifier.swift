import SwiftUI

struct LifeSummaryRefreshModifier: ViewModifier {
    let life: LifeSummaryModel
    let isLaunching: Bool
    let onboardingComplete: Bool
    let authorized: Bool
    @Environment(\.scenePhase) private var scenePhase

    private struct RefreshRequest: Equatable {
        var isLaunching: Bool
        var onboardingComplete: Bool
        var authorized: Bool
        var scenePhase: ScenePhase
        var input: LifeSummaryRefreshInput
    }

    private var refreshID: RefreshRequest {
        .init(isLaunching: isLaunching, onboardingComplete: onboardingComplete,
              authorized: authorized, scenePhase: scenePhase,
              input: life.lifeSummaryRefreshInput())
    }

    func body(content: Content) -> some View {
        content.task(id: refreshID) {
            guard !isLaunching, onboardingComplete, authorized,
                  scenePhase == .active else { return }
            await life.refreshLifeSummary()
        }
    }
}
