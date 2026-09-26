import Testing
@testable import App

@MainActor
@Suite("Home Screen quick actions")
struct HomeQuickActionTests {
    @Test("Each shortcut has a distinct tab and existing localized title")
    func destinations() {
        #expect(HomeQuickAction.allCases.map(\.tab) == [.timer, .focus, .records])
        #expect(HomeQuickAction.allCases.map(\.titleKey) == ["timerTab", "focusTitle", "recordsTab"])
    }

    @Test("A scene keeps its shortcut until setup is ready, then consumes it once")
    func pendingIsSceneOwned() {
        let first = HomeQuickActionSceneDelegate()
        let second = HomeQuickActionSceneDelegate()
        #expect(first.enqueue(HomeQuickAction.focus.rawValue))
        #expect(first.takePending(when: false) == nil)
        #expect(first.pendingShortcut == .focus)
        #expect(second.pendingShortcut == nil)
        #expect(first.takePending(when: true) == .focus)
        #expect(first.takePending(when: true) == nil)
        #expect(!first.enqueue("unknown"))
        #expect(first.pendingShortcut == nil)
    }
}
