import Foundation

/// Calendar facts, independent of the user's actual shift or leave override.
/// A manually assigned shift must not rename a holiday or makeup workday.
nonisolated struct HolidayDayAnnotation: Equatable, Sendable {
    let name: String
    let isMakeupWorkday: Bool
    let isEstimated: Bool

    static func make(dayKey: String, region: String?, language: String,
                     calendar: HolidayCalendar = .shared) -> Self? {
        guard let region, !region.isEmpty,
              let day = calendar.day(dayKey: dayKey, regionIdentifier: region),
              let date = ExtendedScheduleResolver.parse(dayKey: dayKey) else { return nil }
        return Self(name: day.name(language: language), isMakeupWorkday: day.isWorkday,
                    isEstimated: calendar.isEstimated(year: date.year, regionIdentifier: region))
    }
}
