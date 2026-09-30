import Testing
import UIKit
@testable import App

@Suite @MainActor
struct ThemeAppearanceTests {
    @Test func appliesInitialThemeWhenAttached() {
        let view = ThemeAppearanceView(theme: .dark, reduceMotion: false)
        let window = UIWindow()
        window.addSubview(view)
        #expect(window.overrideUserInterfaceStyle == .dark)
    }

    @Test func updatesAndRestoresSystemAppearance() {
        let view = ThemeAppearanceView(theme: .light, reduceMotion: true)
        let window = UIWindow()
        window.addSubview(view)
        view.update(theme: .dark, reduceMotion: true)
        #expect(window.overrideUserInterfaceStyle == .dark)
        view.update(theme: .auto, reduceMotion: true)
        #expect(window.overrideUserInterfaceStyle == .unspecified)
    }

    @Test func followsItsOwnWindowAfterReattachment() {
        let view = ThemeAppearanceView(theme: .dark, reduceMotion: false)
        let first = UIWindow()
        first.addSubview(view)
        let second = UIWindow()
        view.removeFromSuperview()
        view.update(theme: .light, reduceMotion: false)
        second.addSubview(view)
        #expect(first.overrideUserInterfaceStyle == .dark)
        #expect(second.overrideUserInterfaceStyle == .light)
    }
}
