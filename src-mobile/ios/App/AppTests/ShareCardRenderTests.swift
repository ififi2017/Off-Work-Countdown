import SwiftUI
import Testing
@testable import App

/// The share button rasterises `ShareCard` with `ImageRenderer`, which renders
/// a view with nothing above it: no environment, no scene. Reading
/// `@Environment(SceneState.self)` there trapped in SwiftUI's environment
/// lookup and took the app down as the share sheet opened (iOS 27).
///
/// This renders the card exactly as the button does, so the same mistake fails
/// here instead of on someone's phone.
@MainActor
@Suite("Share card rendering")
struct ShareCardRenderTests {
    @Test("The share card renders outside any view hierarchy", arguments: ShareMood.allCases)
    func rendersWithoutEnvironment(mood: ShareMood) throws {
        let suite = "ShareCardRenderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let runtime = AppRuntime(defaults: defaults)

        let renderer = ImageRenderer(
            content: ShareCard(shifts: runtime.shifts, mood: mood).frame(width: 360, height: 450)
        )
        renderer.proposedSize = ProposedViewSize(width: 360, height: 450)
        renderer.isOpaque = true
        let image = try #require(renderer.uiImage)
        #expect(image.size.width > 0 && image.size.height > 0)
    }
}
