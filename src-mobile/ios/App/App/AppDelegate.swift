import os
import ObjectiveC
import SwiftUI
import UIKit

private let orientationLog = Logger(
    subsystem: "com.rainif.offworkcountdown.macappstore",
    category: "orientation"
)

extension Notification.Name {
    static let owcOpenURL = Notification.Name("owc.openURL")
}

@MainActor
final class OffWorkCountdownApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppOrientationPolicy.shared.supportedOrientations
    }

    /// A warmed year or life expansion is the largest thing this app holds that
    /// nothing needs. Give it back rather than being the reason a background
    /// app is killed; the next read rebuilds it.
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        CountdownRules.shared.purgeExpansionCache()
    }
}

/// Keeps first-run setup upright without taking landscape away from the app.
///
/// iOS asks the window root, and SwiftUI's default `UIHostingController` does
/// not forward that question. Wrapping the host after `onAppear` loses the
/// race — SwiftUI puts its own host back. The policy therefore patches the
/// concrete root class so whichever host is currently root returns this mask.
@MainActor
final class AppOrientationPolicy {
    static let shared = AppOrientationPolicy()

    private(set) var supportedOrientations: UIInterfaceOrientationMask

    private init() {
        supportedOrientations = Self.mask(onboardingComplete: Self.storedOnboardingComplete)
    }

    static func prepare() {
        _ = shared
    }

    static func mask(onboardingComplete: Bool) -> UIInterfaceOrientationMask {
        if onboardingComplete {
            UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
        } else {
            .portrait
        }
    }

    func update(onboardingComplete: Bool) {
        let requested = Self.mask(onboardingComplete: onboardingComplete)
        let changed = supportedOrientations != requested
        supportedOrientations = requested
        RootOrientationSwizzle.installOnKeyWindow()
        applyToWindows(forceGeometryUpdate: changed)
    }

    private func applyToWindows(forceGeometryUpdate: Bool) {
        let mask = supportedOrientations
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                visit(window.rootViewController) {
                    $0.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            }
            let current = scene.effectiveGeometry.interfaceOrientation
            let alreadyLegal = mask.contains(Self.bit(for: current))
            guard forceGeometryUpdate, !alreadyLegal else { continue }
            DispatchQueue.main.async {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                    orientationLog.error(
                        "Geometry update failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
    }

    private static func bit(for orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask {
        switch orientation {
        case .portrait: .portrait
        case .portraitUpsideDown: .portraitUpsideDown
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        default: .portrait
        }
    }

    private func visit(_ controller: UIViewController?, _ body: (UIViewController) -> Void) {
        guard let controller else { return }
        body(controller)
        visit(controller.presentedViewController, body)
        controller.children.forEach { visit($0, body) }
    }

    static var storedOnboardingComplete: Bool {
        let defaults = UserDefaults.standard
#if DEBUG
        if defaults.bool(forKey: "ios.native.debugAlwaysOnboarding") { return false }
#endif
        return defaults.bool(forKey: "ios.native.onboardingComplete")
    }
}

/// Patches the live root class (a SwiftUI host specialization) so iOS reads
/// `AppOrientationPolicy` instead of the host's launch-time snapshot.
enum RootOrientationSwizzle {
    private static var patched = Set<ObjectIdentifier>()

    static func installOnKeyWindow() {
        let roots = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { $0.windowLevel == .normal }
            .compactMap(\.rootViewController)
        roots.forEach(install(on:))
    }

    static func install(on controller: UIViewController) {
        let cls: AnyClass = type(of: controller)
        let id = ObjectIdentifier(cls)
        guard !patched.contains(id) else { return }
        patched.insert(id)

        swizzle(
            class: cls,
            original: #selector(getter: UIViewController.supportedInterfaceOrientations),
            swizzled: #selector(UIViewController.owc_supportedInterfaceOrientations)
        )
    }

    private static func swizzle(class cls: AnyClass, original: Selector, swizzled: Selector) {
        guard let template = class_getInstanceMethod(UIViewController.self, swizzled) else { return }
        let encoding = method_getTypeEncoding(template)
        // Copy inherited IMPs onto this class first. Exchanging a method
        // that still lives on `UIViewController` would patch every screen.
        if let inherited = class_getInstanceMethod(cls, original) {
            class_addMethod(cls, original, method_getImplementation(inherited), method_getTypeEncoding(inherited))
        }
        class_addMethod(cls, swizzled, method_getImplementation(template), encoding)
        guard
            let originalMethod = class_getInstanceMethod(cls, original),
            let swizzledMethod = class_getInstanceMethod(cls, swizzled)
        else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

extension UIViewController {
    @objc func owc_supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
        if isViewLoaded, view.window?.rootViewController === self {
            return AppOrientationPolicy.shared.supportedOrientations
        }
        return owc_supportedInterfaceOrientations()
    }
}

@main
struct OffWorkCountdownApp: App {
    @UIApplicationDelegateAdaptor(OffWorkCountdownApplicationDelegate.self) private var appDelegate

    init() {
        LaunchTrace.beginAppInit()
        AppOrientationPolicy.prepare()
    }

    var body: some Scene {
        WindowGroup {
            OffWorkCountdownRootView()
        }
    }
}
