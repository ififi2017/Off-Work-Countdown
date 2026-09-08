import SwiftUI

struct LifeSummaryRefreshModifier: ViewModifier {
    let store: OffWorkStore
    let isLaunching: Bool
    @Environment(\.scenePhase) private var scenePhase

    private var refreshID: String {
        "\(isLaunching):\(store.onboardingComplete):\(store.plus.isAuthorized):\(store.records.revision):\(scenePhase)"
    }

    func body(content: Content) -> some View {
        content.task(id: refreshID) {
            guard !isLaunching, store.onboardingComplete, store.plus.isAuthorized,
                  scenePhase == .active else { return }
            await store.refreshLifeSummary()
        }
    }
}
