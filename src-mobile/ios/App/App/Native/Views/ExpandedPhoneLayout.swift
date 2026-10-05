import SwiftUI

private struct ExpandedPhoneColumnsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var usesExpandedPhoneColumns: Bool {
        get { self[ExpandedPhoneColumnsKey.self] }
        set { self[ExpandedPhoneColumnsKey.self] = newValue }
    }
}
