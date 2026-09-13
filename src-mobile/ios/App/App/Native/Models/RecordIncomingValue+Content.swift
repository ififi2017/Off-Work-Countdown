import Foundation

extension RecordIncomingValue {
    /// Compare typed values without manufacturing a new edit stamp or encoding
    /// JSON. Identity, deletion state and all business fields still participate.
    func hasSameBusinessContent(as other: Self) -> Bool {
        withoutEditStamp == other.withoutEditStamp
    }

    private var withoutEditStamp: Self {
        switch self {
        case .period(var value):
            value.editedAt = .distantPast
            value.editCount = 0
            value.editTieBreaker = WorkObservation.unsetTieBreaker
            return .period(value)
        case .snapshot(var value):
            value.editedAt = .distantPast
            value.editCount = 0
            value.editTieBreaker = WorkObservation.unsetTieBreaker
            return .snapshot(value)
        case .exception(var value):
            value.editedAt = .distantPast
            value.editCount = 0
            value.editTieBreaker = WorkObservation.unsetTieBreaker
            return .exception(value)
        case .override(var value):
            value.editedAt = .distantPast
            value.editCount = 0
            value.editTieBreaker = WorkObservation.unsetTieBreaker
            return .override(value)
        case .observation(var value):
            value.editedAt = .distantPast
            value.editCount = 0
            value.editTieBreaker = WorkObservation.unsetTieBreaker
            return .observation(value)
        case .lifeProfile(var value):
            value.editedAt = .distantPast
            value.editCount = 0
            value.editTieBreaker = WorkObservation.unsetTieBreaker
            return .lifeProfile(value)
        case .focusTask(var value):
            value.editedAt = .distantPast
            value.editCount = 0
            value.editTieBreaker = WorkObservation.unsetTieBreaker
            return .focusTask(value)
        case .focusSession(var value):
            value.editedAt = .distantPast
            value.editCount = 0
            value.editTieBreaker = WorkObservation.unsetTieBreaker
            return .focusSession(value)
        case .focusPlanningConfiguration(var value):
            value.editedAt = .distantPast
            value.editCount = 0
            value.editTieBreaker = WorkObservation.unsetTieBreaker
            return .focusPlanningConfiguration(value)
        case .syncedPreferences(var value):
            value.editedAt = .distantPast
            value.editCount = 0
            value.editTieBreaker = WorkObservation.unsetTieBreaker
            return .syncedPreferences(value)
        }
    }
}
