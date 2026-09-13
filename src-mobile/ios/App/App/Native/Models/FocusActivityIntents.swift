import Foundation

struct FocusActivityRequest: Identifiable, Equatable {
    enum Action: String { case addPomodoros, stop }
    let action: Action
    let startAtMs: Int64
    var id: String { "\(action.rawValue):\(startAtMs)" }
}
