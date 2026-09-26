import os
import ObjectiveC
import SwiftUI
import UIKit

private let orientationLog = Logger(
    subsystem: "com.rainif.offworkcountdown.macappstore",
    category: "orientation"
)

@MainActor
final class OffWorkCountdownApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let localizer = NativeLocalizer()
        let locale = NativeLocalizer.systemLanguage()
        application.shortcutItems = HomeQuickAction.allCases.map { action in
            UIApplicationShortcutItem(
                type: action.rawValue,
                localizedTitle: localizer.string(action.titleKey, locale: locale),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: action.systemImage),
                userInfo: nil
            )
        }
        Task { _ = try? await AppRuntime.loadShared() }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = HomeQuickActionSceneDelegate.self
        }
        return configuration
    }

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
        ScheduleExpansionCache.shared.purge()
    }
}

enum HomeQuickAction: String, CaseIterable {
    case timer = "com.rainif.doneat.shortcut.timer"
    case focus = "com.rainif.doneat.shortcut.focus"
    case records = "com.rainif.doneat.shortcut.records"

    var tab: AppTab {
        switch self {
        case .timer: .timer
        case .focus: .focus
        case .records: .records
        }
    }

    var titleKey: String {
        switch self {
        case .timer: "timerTab"
        case .focus: "focusTitle"
        case .records: "recordsTab"
        }
    }

    var systemImage: String {
        switch self {
        case .timer: "timer"
        case .focus: "stopwatch"
        case .records: "calendar"
        }
    }
}

/// SwiftUI installs one instance in each window's environment. A shortcut is
/// held here until that window has passed first-run setup and its intro.
@MainActor
final class HomeQuickActionSceneDelegate: NSObject, UIWindowSceneDelegate, ObservableObject {
    @Published private(set) var pendingShortcut: AppTab?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let item = connectionOptions.shortcutItem { enqueue(item.type) }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(enqueue(shortcutItem.type))
    }

    @discardableResult
    func enqueue(_ type: String) -> Bool {
        guard let action = HomeQuickAction(rawValue: type) else { return false }
        pendingShortcut = action.tab
        return true
    }

    func takePending(when ready: Bool) -> AppTab? {
        guard ready else { return nil }
        defer { pendingShortcut = nil }
        return pendingShortcut
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

    /// The mask the policy should be reporting, given first-run state and any
    /// orientation a QA screenshot run has pinned.
    ///
    /// A pin outranks the ordinary policy for the life of the process. Without
    /// that, the next `.active` transition would hand the policy back and turn
    /// the window away from the orientation the sweep asked for.
    static func resolvedMask(
        onboardingComplete: Bool,
        qaPinned: UIInterfaceOrientationMask?
    ) -> UIInterfaceOrientationMask {
        qaPinned ?? mask(onboardingComplete: onboardingComplete)
    }

    func update(onboardingComplete: Bool) {
        let requested = Self.resolvedMask(
            onboardingComplete: onboardingComplete,
            qaPinned: qaPinnedOrientations
        )
        let changed = supportedOrientations != requested
        supportedOrientations = requested
        RootOrientationSwizzle.installOnKeyWindow()
        applyToWindows(forceGeometryUpdate: changed)
    }

#if DEBUG
    private var qaPinnedOrientations: UIInterfaceOrientationMask?

    /// Turns the window for a QA screenshot run and keeps it turned.
    ///
    /// `requestGeometryUpdate` on its own does not hold. iOS re-reads the root
    /// controller's `supportedInterfaceOrientations` the moment the request
    /// lands, and while that still answers `.allButUpsideDown` the physically
    /// portrait simulator wins and the window turns straight back — which is
    /// why every landscape column of the sweep came back "still portrait".
    /// Narrowing the policy to the requested orientation first is what makes
    /// the turn stick.
    func pinOrientationsForQA(_ mask: UIInterfaceOrientationMask) {
        qaPinnedOrientations = mask
        supportedOrientations = mask
        RootOrientationSwizzle.installOnKeyWindow()
        applyToWindows(forceGeometryUpdate: true)
    }
#else
    private var qaPinnedOrientations: UIInterfaceOrientationMask? { nil }
#endif

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
#if DEBUG
                    // The screenshot sweep reads this key to explain a miss.
                    UserDefaults.standard.set(
                        error.localizedDescription,
                        forKey: "ios.native.qaOrientationError"
                    )
#endif
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
#if DEBUG
        // Keep marketing fixtures and native date formatting in the same zone.
        // This changes only this process, never the simulator or device settings.
        if let identifier = UserDefaults.standard.string(forKey: "ios.native.qaTimeZone"),
           let zone = TimeZone(identifier: identifier) {
            setenv("TZ", zone.identifier, 1)
            NSTimeZone.resetSystemTimeZone()
            NSTimeZone.default = zone
        }
#endif
        LaunchTrace.beginAppInit()
        AppOrientationPolicy.prepare()
    }

    var body: some Scene {
        WindowGroup {
            AppRuntimeLoadingView()
        }
    }
}
