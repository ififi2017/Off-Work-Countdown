import SwiftUI

extension PreferencesStore {
    /// Discrete controls submit an interaction; text fields keep a draft until
    /// editing ends.
    func preferenceBinding<Value>(_ field: WritableKeyPath<SyncedPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { self.currentSyncedPreferences()[keyPath: field] },
            set: { value in self.applyPreferences { $0[keyPath: field] = value } }
        )
    }
}
