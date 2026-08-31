import Foundation

enum RecordsRoute: Hashable, Sendable {
    case day(String)
    case week
    case month
    case year
    case life
    case editDay(String)
    case paywall(PlusPaywallReason)
    case focus
}
