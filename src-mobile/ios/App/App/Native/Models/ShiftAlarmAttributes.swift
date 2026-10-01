import AlarmKit
import Foundation

/// What a shift alarm carries to the Lock Screen and Dynamic Island while it
/// snoozes (plan 020 §3). Shared verbatim with the Widget extension. The text
/// arrives finished, because the extension cannot compose a sentence in the
/// user's language.
nonisolated struct ShiftAlarmMetadata: AlarmMetadata {
    /// "Early at 08:00", as on the alarm itself.
    var title: String
    /// "Snoozing".
    var snoozeLabel: String
}
