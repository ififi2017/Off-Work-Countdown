import Foundation

/// Civil calendars for the records zone. Same reason as the date formatters:
/// caching them on the observable store would invalidate every reader.
@MainActor
final class CivilCalendarCache {
    private var timeZoneIdentifier = ""
    private var localeIdentifier = ""
    private var cachedTimeZone = TimeZone.current
    private var cachedLocale = Locale.current
    private var cachedRecordsCalendar = Calendar(identifier: .gregorian)
    private var cachedGridCalendar = Calendar(identifier: .gregorian)

    func timeZone(identifier: String) -> TimeZone {
        prepare(timeZoneIdentifier: identifier, localeIdentifier: localeIdentifier)
        return cachedTimeZone
    }

    func locale(identifier: String) -> Locale {
        prepare(timeZoneIdentifier: timeZoneIdentifier, localeIdentifier: identifier)
        return cachedLocale
    }

    func recordsCalendar(timeZoneIdentifier: String) -> Calendar {
        prepare(timeZoneIdentifier: timeZoneIdentifier, localeIdentifier: localeIdentifier)
        return cachedRecordsCalendar
    }

    func gridCalendar(timeZoneIdentifier: String, localeIdentifier: String) -> Calendar {
        prepare(timeZoneIdentifier: timeZoneIdentifier, localeIdentifier: localeIdentifier)
        return cachedGridCalendar
    }

    private static func firstWeekdayIndex(of locale: Locale) -> Int {
        switch locale.firstDayOfWeek {
        case .sunday: 1
        case .monday: 2
        case .tuesday: 3
        case .wednesday: 4
        case .thursday: 5
        case .friday: 6
        case .saturday: 7
        @unknown default: 1
        }
    }

    private func prepare(timeZoneIdentifier: String, localeIdentifier: String) {
        if timeZoneIdentifier == self.timeZoneIdentifier, localeIdentifier == self.localeIdentifier {
            return
        }
        self.timeZoneIdentifier = timeZoneIdentifier
        self.localeIdentifier = localeIdentifier
        cachedTimeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        cachedLocale = Locale(identifier: localeIdentifier)
        var records = Calendar(identifier: .gregorian)
        records.timeZone = cachedTimeZone
        cachedRecordsCalendar = records
        var grid = Calendar(identifier: .gregorian)
        grid.timeZone = cachedTimeZone
        grid.locale = cachedLocale
        grid.firstWeekday = Self.firstWeekdayIndex(of: cachedLocale)
        cachedGridCalendar = grid
    }
}

/// Skeleton-based date formatters, kept alive between rows.
///
/// Deliberately outside the observable store: caching in a stored property
/// there would register a mutation on every formatted date and invalidate the
/// views that asked for it.
@MainActor
final class RecordsDateFormatters {
    static let shared = RecordsDateFormatters()

    private var cache: [String: DateFormatter] = [:]

    func formatter(template: String, locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let key = "\(template)|\(locale.identifier)|\(timeZone.identifier)"
        if let cached = cache[key] { return cached }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        // A template, not a format string: ICU reorders the fields per locale,
        // so the same call gives "Aug 26" and "8月26日".
        formatter.setLocalizedDateFormatFromTemplate(template)
        cache[key] = formatter
        return formatter
    }
}
