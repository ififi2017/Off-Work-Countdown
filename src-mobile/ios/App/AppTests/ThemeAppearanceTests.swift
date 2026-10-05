import Testing
import UIKit
@testable import App

@Suite @MainActor
struct ThemeAppearanceTests {
    @Test func appliesInitialThemeWhenAttached() throws {
        let view = ThemeAppearanceView(theme: .dark, reduceMotion: false)
        let window = try makeWindow()
        window.addSubview(view)
        #expect(window.overrideUserInterfaceStyle == .dark)
    }

    @Test func updatesAndRestoresSystemAppearance() throws {
        let view = ThemeAppearanceView(theme: .light, reduceMotion: true)
        let window = try makeWindow()
        window.addSubview(view)
        view.update(theme: .dark, reduceMotion: true)
        #expect(window.overrideUserInterfaceStyle == .dark)
        view.update(theme: .auto, reduceMotion: true)
        #expect(window.overrideUserInterfaceStyle == .unspecified)
    }

    @Test func followsItsOwnWindowAfterReattachment() throws {
        let view = ThemeAppearanceView(theme: .dark, reduceMotion: false)
        let first = try makeWindow()
        first.addSubview(view)
        let second = try makeWindow()
        view.removeFromSuperview()
        view.update(theme: .light, reduceMotion: false)
        second.addSubview(view)
        #expect(first.overrideUserInterfaceStyle == .dark)
        #expect(second.overrideUserInterfaceStyle == .light)
    }

    private func makeWindow() throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        return UIWindow(windowScene: scene)
    }
}
