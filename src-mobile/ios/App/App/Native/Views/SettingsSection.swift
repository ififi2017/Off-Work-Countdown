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
    case recordsData
    case about

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .shift: "shiftSection"
        case .reminders: "remindersSection"
        case .appearance: "appearanceSection"
        case .recordsData: "recordsDataSection"
        case .about: "aboutSection"
        }
    }

    /// The two-column arrangement landscape and iPad share, derived from
    /// `allCases`.
    ///
    /// Splitting `allCases` here means a new section appears in every layout
    /// at once. Plus is a shared title action rather than a list section.
    /// The shift and reminder sections share the left column: with lunch and
    /// the health reminder moved out of `shift`, neither is tall enough to
    /// stand alone against the rest.
    static var twoColumns: [[SettingsSection]] {
        let all = allCases
        let left = Array(all.prefix(2))
        return [left, Array(all.dropFirst(left.count))]
    }
}
