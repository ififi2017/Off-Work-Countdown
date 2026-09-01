import SwiftUI
import UIKit

/// Keeps UIKit's interactive navigation gestures available while settings
/// destinations replace the system back item so unsaved edits can be guarded.
///
/// iOS 26 installs a content-wide pop recognizer on `UINavigationController`.
/// UIKit owns that recognizer and its conflict handling. The bridge normally
/// preserves it, and temporarily disables it only when an unsaved draft must
/// be confirmed before navigation. The older leading-edge recognizer remains
/// active in that state so a swipe can still express the intent to go back.
struct OWCSystemBackSwipeBridge: UIViewControllerRepresentable {
    var blocksBackSwipe = false
    var onBlockedBackSwipe: () -> Void = {}

    func makeUIViewController(context: Context) -> UIViewController {
        Controller()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard let controller = uiViewController as? Controller else { return }
        controller.blocksBackSwipe = blocksBackSwipe
        controller.onBlockedBackSwipe = onBlockedBackSwipe
        controller.restoreSystemBackSwipeIfPossible()
    }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: ()) {
        guard let controller = uiViewController as? Controller else { return }
        controller.restoreOriginalDelegate()
    }

    @MainActor
    private final class Controller: UIViewController, UIGestureRecognizerDelegate {
        private weak var edgePopRecognizer: UIGestureRecognizer?
        private weak var originalDelegate: (any UIGestureRecognizerDelegate)?
        private weak var contentPopRecognizer: UIGestureRecognizer?
        private var originalContentPopEnabled: Bool?
        fileprivate var blocksBackSwipe = false
        fileprivate var onBlockedBackSwipe: () -> Void = {}

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            restoreSystemBackSwipeIfPossible()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            restoreSystemBackSwipeIfPossible()
        }

        fileprivate func restoreSystemBackSwipeIfPossible() {
            guard let navigationController, navigationController.viewControllers.count > 1 else { return }
            guard let recognizer = navigationController.interactivePopGestureRecognizer else { return }

            if recognizer !== edgePopRecognizer {
                restoreOriginalDelegate()
                edgePopRecognizer = recognizer
                originalDelegate = recognizer.delegate
            }

            if let contentRecognizer = navigationController.interactiveContentPopGestureRecognizer {
                if contentRecognizer !== contentPopRecognizer {
                    restoreOriginalContentRecognizerState()
                    contentPopRecognizer = contentRecognizer
                    originalContentPopEnabled = contentRecognizer.isEnabled
                }

                // A full-content pop cannot be cancelled cleanly from SwiftUI
                // once it has begun. While a page is dirty, leave the system
                // edge recognizer active as the intent detector and prevent
                // both system recognizers from moving the page until the user
                // decides.
                contentRecognizer.isEnabled = blocksBackSwipe ? false : (originalContentPopEnabled ?? true)
            }

            recognizer.delegate = self
            recognizer.isEnabled = true
        }

        fileprivate func restoreOriginalDelegate() {
            if let edgePopRecognizer, edgePopRecognizer.delegate === self {
                edgePopRecognizer.delegate = originalDelegate
            }
            restoreOriginalContentRecognizerState()
        }

        private func restoreOriginalContentRecognizerState() {
            if let contentPopRecognizer, let originalContentPopEnabled {
                contentPopRecognizer.isEnabled = originalContentPopEnabled
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === edgePopRecognizer else { return true }
            guard let navigationController, navigationController.viewControllers.count > 1 else { return false }
            if blocksBackSwipe {
                onBlockedBackSwipe()
                return false
            }
            return navigationController.transitionCoordinator == nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard gestureRecognizer === edgePopRecognizer,
                  let recognizerView = gestureRecognizer.view,
                  let otherView = otherGestureRecognizer.view else {
                return false
            }

            // Give the native edge transition priority over ScrollView and
            // control recognizers below it. UIKit can then decide whether the
            // gesture is a pop before vertical scrolling begins.
            return otherView.isDescendant(of: recognizerView)
        }
    }
}
