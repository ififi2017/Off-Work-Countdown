import SwiftUI
import UIKit

/// Uses the owning scene's window so sheets, navigation bars and SwiftUI colours
/// fade together while the existing navigation and editing state stays mounted.
struct ThemeAppearance: UIViewRepresentable {
    let theme: AppTheme
    let reduceMotion: Bool

    func makeUIView(context: Context) -> ThemeAppearanceView {
        ThemeAppearanceView(theme: theme, reduceMotion: reduceMotion)
    }

    func updateUIView(_ uiView: ThemeAppearanceView, context: Context) {
        uiView.update(theme: theme, reduceMotion: reduceMotion)
    }
}

final class ThemeAppearanceView: UIView {
    private var theme: AppTheme
    private var reduceMotion: Bool
    private weak var appearanceWindow: UIWindow?

    init(theme: AppTheme, reduceMotion: Bool) {
        self.theme = theme
        self.reduceMotion = reduceMotion
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyAppearance(animated: false)
    }

    func update(theme: AppTheme, reduceMotion: Bool) {
        let changed = self.theme != theme
        self.theme = theme
        self.reduceMotion = reduceMotion
        applyAppearance(animated: changed)
    }

    private func applyAppearance(animated: Bool) {
        guard let window else { return }
        let isInitialAppearance = appearanceWindow !== window
        appearanceWindow = window
        let style: UIUserInterfaceStyle = switch theme {
        case .auto: .unspecified
        case .light: .light
        case .dark: .dark
        }
        guard window.overrideUserInterfaceStyle != style else { return }
        let apply = {
            window.overrideUserInterfaceStyle = style
            window.layoutIfNeeded()
        }
        guard animated, !isInitialAppearance, !reduceMotion, window.windowScene?.activationState == .foregroundActive else {
            UIView.performWithoutAnimation(apply)
            return
        }
        UIView.transition(
            with: window,
            duration: OWCMotion.themeDuration,
            options: [.transitionCrossDissolve, .curveEaseInOut, .beginFromCurrentState, .allowUserInteraction],
            animations: apply
        )
    }
}
