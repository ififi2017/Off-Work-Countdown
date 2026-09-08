import SwiftUI
import UIKit

/// A separate scene window covers sheets as well as navigation destinations.
/// The underlying phone UI stays mounted so rotating back restores edits and paths.
struct PhoneLandscapePresentation: UIViewRepresentable {
    let store: OffWorkStore

    func makeUIView(context: Context) -> LandscapeAnchorView {
        LandscapeAnchorView(store: store)
    }

    func updateUIView(_ uiView: LandscapeAnchorView, context: Context) {
        uiView.updatePresentation()
    }

    static func dismantleUIView(_ uiView: LandscapeAnchorView, coordinator: ()) {
        uiView.hidePresentation()
    }
}

final class LandscapeAnchorView: UIView {
    private let store: OffWorkStore
    private var timerWindow: UIWindow?
    private weak var coveredWindow: UIWindow?
    private var coveredAccessibilityWasHidden = false

    init(store: OffWorkStore) {
        self.store = store
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePresentation()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updatePresentation()
    }

    func updatePresentation() {
        guard store.selectedTab == .timer,
              UIDevice.current.userInterfaceIdiom == .phone,
              let sourceWindow = window,
              let scene = sourceWindow.windowScene,
              sourceWindow.bounds.width > sourceWindow.bounds.height else {
            hidePresentation()
            return
        }
        guard timerWindow == nil else { return }
        let overlay = UIWindow(windowScene: scene)
        overlay.windowLevel = .alert + 1
        overlay.backgroundColor = .black
        overlay.rootViewController = LandscapeTimerHost(rootView: PhoneLandscapeShellView(store: store, immersive: true))
        overlay.accessibilityViewIsModal = true
        coveredWindow = sourceWindow
        coveredAccessibilityWasHidden = sourceWindow.accessibilityElementsHidden
        sourceWindow.accessibilityElementsHidden = true
        // Do not take key-window ownership from a sheet or an active text field.
        overlay.isHidden = false
        timerWindow = overlay
    }

    func hidePresentation() {
        coveredWindow?.accessibilityElementsHidden = coveredAccessibilityWasHidden
        coveredWindow = nil
        timerWindow?.isHidden = true
        timerWindow = nil
    }
}

private final class LandscapeTimerHost: UIHostingController<PhoneLandscapeShellView> {
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
}
