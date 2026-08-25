import Foundation

/// Which end of the shift a time picker is editing.
enum SetupTimeField: String, Identifiable {
    case start
    case end

    var id: String { rawValue }
}
