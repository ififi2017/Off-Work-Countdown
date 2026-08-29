import Foundation

/// One life-view archive per store. The id is a constant so two offline
/// devices first-write the same row. Matches 002 §6.
struct LifeProfile: Equatable, Sendable {
    static let schemaVersion = 1
    static let profileID = UUID(uuidString: "00000000-0000-0000-0000-00574F524B01")!

    var profileID: UUID = LifeProfile.profileID
    var birthYear: Int?
    var workStartedOn: Date?
    var retirementAge: Int?
    var averageSleepHours: Double?
    var hidesExactAges: Bool = false
    var editedAt: Date
    var editCount: Int
    var editTieBreaker: UUID
}
