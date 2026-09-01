import Foundation

enum RecordsRoute: Hashable, Sendable {
    case allRecords
    case yearList(Int)
    case monthList(year: Int, month: Int)
    case day(String)
    case conflictCenter
}

struct RecordsDayIdentified: Identifiable, Hashable {
    var id: String { dayKey }
    var dayKey: String
}
