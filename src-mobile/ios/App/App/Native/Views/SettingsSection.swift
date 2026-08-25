import Foundation

/// The settings list, as data.
///
/// Portrait, landscape and iPad each used to spell the same four sections out
/// by hand, which is how they drifted apart. They now differ only in how they
/// arrange these cases.
enum SettingsSection: String, CaseIterable, Identifiable {
    case shift
    case reminders
    case appearance
    case about

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .shift: "shiftSection"
        case .reminders: "remindersSection"
        case .appearance: "appearanceSection"
        case .about: "aboutSection"
        }
    }
}
