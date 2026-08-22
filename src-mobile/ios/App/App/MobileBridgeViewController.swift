import Capacitor
import UIKit
import WebKit

/// Capacitor still owns the WKWebView and all TypeScript business rules. This
/// controller supplies the iPhone navigation chrome so the packaged app uses
/// the system tab bar instead of a Web imitation. On iOS 26, UITabBar receives
/// the system Liquid Glass appearance automatically.
@objc(MobileBridgeViewController)
final class MobileBridgeViewController: CAPBridgeViewController, UITabBarDelegate, WKScriptMessageHandler {
    private enum Tab: Int {
        case timer = 0
        case settings = 1

        var name: String {
            switch self {
            case .timer:
                return "timer"
            case .settings:
                return "settings"
            }
        }
    }

    private let mobileTabBar = UITabBar()
    private lazy var timerItem = UITabBarItem(
        title: "Timer",
        image: UIImage(systemName: "timer"),
        selectedImage: UIImage(systemName: "timer")
    )
    private lazy var settingsItem = UITabBarItem(
        title: "Settings",
        image: UIImage(systemName: "gearshape"),
        selectedImage: UIImage(systemName: "gearshape.fill")
    )

    override func viewDidLoad() {
        super.viewDidLoad()

        // Capacitor finalizes its WKUserContentController while building the
        // bridge in super.viewDidLoad(). Register against that live controller
        // rather than the earlier configuration hook: otherwise Capacitor can
        // replace the controller and silently drop this message handler.
        if let userContentController = webView?.configuration.userContentController {
            userContentController.removeScriptMessageHandler(forName: "owcMobileTabs")
            userContentController.add(self, name: "owcMobileTabs")
        }

        timerItem.tag = Tab.timer.rawValue
        settingsItem.tag = Tab.settings.rawValue
        mobileTabBar.translatesAutoresizingMaskIntoConstraints = false
        mobileTabBar.delegate = self
        mobileTabBar.items = [timerItem, settingsItem]
        mobileTabBar.selectedItem = timerItem
        mobileTabBar.tintColor = .label
        mobileTabBar.unselectedItemTintColor = .secondaryLabel
        mobileTabBar.isTranslucent = true

        view.addSubview(mobileTabBar)
        NSLayoutConstraint.activate([
            mobileTabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mobileTabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // A standalone UITabBar does not have UITabBarController to extend
            // its frame through the home-indicator inset. Give the controls the
            // standard 49 pt content area and let the bar material continue to
            // the physical bottom edge.
            mobileTabBar.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -49
            ),
            mobileTabBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        guard let tab = Tab(rawValue: item.tag) else { return }
        dispatchTab(tab)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard
            message.name == "owcMobileTabs",
            let payload = message.body as? [String: Any]
        else { return }

        if let timer = payload["timer"] as? String, !timer.isEmpty {
            timerItem.title = timer
        }
        if let settings = payload["settings"] as? String, !settings.isEmpty {
            settingsItem.title = settings
        }
        if let selected = payload["selected"] as? String {
            mobileTabBar.selectedItem = selected == Tab.settings.name ? settingsItem : timerItem
        }
        if let direction = payload["direction"] as? String {
            mobileTabBar.semanticContentAttribute = direction == "rtl" ? .forceRightToLeft : .forceLeftToRight
        }
        if let appearance = payload["appearance"] as? String {
            switch appearance {
            case "dark":
                overrideUserInterfaceStyle = .dark
            case "light":
                overrideUserInterfaceStyle = .light
            default:
                overrideUserInterfaceStyle = .unspecified
            }
        }
    }

    private func dispatchTab(_ tab: Tab) {
        let source = """
        window.dispatchEvent(new CustomEvent('owc:native-tab', { detail: { tab: '\(tab.name)' } }));
        """
        webView?.evaluateJavaScript(source)
    }
}
