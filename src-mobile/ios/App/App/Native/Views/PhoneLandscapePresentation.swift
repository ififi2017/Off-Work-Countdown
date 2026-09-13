import SwiftUI
import UIKit

/// Reports this scene's actual phone-window orientation without creating a
/// second window. SwiftUI keeps the navigation and editor tree mounted while
/// the root overlays its landscape timer.
struct PhoneLandscapePresentation: UIViewRepresentable {
    @Binding var isLandscapePhone: Bool

    func makeUIView(context: Context) -> PhoneOrientationObserverView {
        PhoneOrientationObserverView { isLandscapePhone = $0 }
    }

    func updateUIView(_ uiView: PhoneOrientationObserverView, context: Context) {
        uiView.onChange = { isLandscapePhone = $0 }
        uiView.reportOrientation()
    }

    static func dismantleUIView(_ uiView: PhoneOrientationObserverView, coordinator: ()) {
        uiView.onChange = nil
    }
}

final class PhoneOrientationObserverView: UIView {
    var onChange: (@MainActor (Bool) -> Void)?
    private var lastReportedValue: Bool?

    init(onChange: @escaping @MainActor (Bool) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reportOrientation()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportOrientation()
    }

    func reportOrientation() {
        guard let window else { return }
        let value = PhoneLandscapePresentationPolicy.isLandscapePhone(
            idiom: traitCollection.userInterfaceIdiom,
            width: window.bounds.width,
            height: window.bounds.height
        )
        guard value != lastReportedValue else { return }
        lastReportedValue = value
        // UIKit can call layout while SwiftUI is updating the representable.
        // Publish on the next MainActor turn to avoid mutating view state there.
        Task { @MainActor [weak self] in
            guard let self, self.lastReportedValue == value else { return }
            self.onChange?(value)
        }
    }
}

enum PhoneLandscapePresentationPolicy {
    static func isLandscapePhone(idiom: UIUserInterfaceIdiom, width: CGFloat, height: CGFloat) -> Bool {
        idiom == .phone && width > height
    }

    static func shouldPresent(
        isLandscapePhone: Bool,
        selectedTab: AppTab,
        onboardingComplete: Bool,
        hasSeenPlusIntro: Bool,
        timerIsAtRoot: Bool,
        hasBlockingPresentation: Bool
    ) -> Bool {
        isLandscapePhone
            && selectedTab == .timer
            && onboardingComplete
            && hasSeenPlusIntro
            && timerIsAtRoot
            && !hasBlockingPresentation
    }
}
