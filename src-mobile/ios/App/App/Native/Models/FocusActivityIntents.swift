import AppIntents
import Foundation

/// What the app can do on behalf of a Live Activity button.
///
/// The intent below is compiled into the widget extension as well, because the
/// extension has to be able to construct it to draw the button. Only the app
/// can act on it, and only the app has an `OffWorkStore`, so the work is left
/// behind here as a closure the app registers at launch. Inside the extension
/// this stays `nil` and the intent is never performed there.
@MainActor
enum FocusActivityActions {
    static var stopFocus: (@MainActor (Int64) async -> Void)?
    static var addPomodoro: (@MainActor (Int64) async -> Void)?
}

/// Opens the app to choose and confirm an extension to this block.
struct AddFocusPomodoroIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add a pomodoro"
    static let description = IntentDescription(
        "Gives the running task one more focus block in today's plan."
    )
    static let isDiscoverable = false
    static let openAppWhenRun = true

    @Parameter(title: "Block start") var startAtMs: Int

    init() {}
    init(startAtMs: Int64) { self.startAtMs = Int(startAtMs) }

    @MainActor
    func perform() async throws -> some IntentResult {
        await FocusActivityActions.addPomodoro?(Int64(startAtMs))
        return .result()
    }
}

/// The start timestamp prevents a stale card from stopping a later block.
struct StopFocusActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop focus"
    static let isDiscoverable = false
    static let openAppWhenRun = true

    @Parameter(title: "Block start") var startAtMs: Int

    init() {}
    init(startAtMs: Int64) { self.startAtMs = Int(startAtMs) }

    @MainActor
    func perform() async throws -> some IntentResult {
        await FocusActivityActions.stopFocus?(Int64(startAtMs))
        return .result()
    }
}

struct FocusActivityRequest: Identifiable, Equatable {
    enum Action: String { case addPomodoros, stop }
    let action: Action
    let startAtMs: Int64
    var id: String { "\(action.rawValue):\(startAtMs)" }
}
