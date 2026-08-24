import SwiftUI
import UIKit

/// Keeps UIKit's interactive navigation gestures available while the app uses
/// its own SwiftUI header instead of a visible `UINavigationBar`.
///
/// iOS 26 installs a content-wide pop recognizer on `UINavigationController`.
/// UIKit owns that recognizer and its conflict handling, so this bridge leaves
/// it untouched. The older leading-edge recognizer is re-enabled as a fallback
/// because SwiftUI disables it when the navigation bar is hidden.
struct OWCSystemBackSwipeBridge: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        Controller()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard let controller = uiViewController as? Controller else { return }
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

            // Accessing the iOS 26 content recognizer is intentionally enough:
            // UIKit installs and coordinates it. Apple documents this property
            // only for establishing failure requirements with custom gestures.
            _ = navigationController.interactiveContentPopGestureRecognizer

            recognizer.delegate = self
            recognizer.isEnabled = true
        }

        fileprivate func restoreOriginalDelegate() {
            guard let edgePopRecognizer, edgePopRecognizer.delegate === self else { return }
            edgePopRecognizer.delegate = originalDelegate
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === edgePopRecognizer else { return true }
            guard let navigationController, navigationController.viewControllers.count > 1 else { return false }
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
