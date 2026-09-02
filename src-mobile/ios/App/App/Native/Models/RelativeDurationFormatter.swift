import Foundation

/// Formats a span of time the way it reads in a sentence — "12 h", "1小时30分钟" —
/// as opposed to the clock form `formatDuration` produces.
///
/// This lives outside `OffWorkStore` because the store takes its language from
/// the system bundle and exposes it `private(set)`, which left the formatting
/// untestable at any language but the simulator's.
nonisolated enum RelativeDurationFormatter {
    static func string(milliseconds: Double, languageCode: String) -> String {
        let total = max(0, Int(milliseconds / 1_000))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60

        if languageCode == "en" {
            // Grouped, not interpolated: a life-scale projection reaches five
            // and six figures, and "67571 h" is a number nobody can read.
            // Below a thousand this changes nothing.
            let locale = Locale(identifier: languageCode)
            let hourText = hours.formatted(.number.locale(locale))
            let minuteText = minutes.formatted(.number.locale(locale))
            if hours == 0 { return "\(minuteText) m" }
            return minutes == 0 ? "\(hourText) h" : "\(hourText) h \(minuteText) m"
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        // dropTrailing is what removes the "0 minutes" that used to trail every
        // whole hour ("12小时0分钟"). Both together still keep the last unit for a
        // zero duration, so the result is never empty.
        formatter.zeroFormattingBehavior = [.dropLeading, .dropTrailing]
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: languageCode)
        formatter.calendar = calendar
        return formatter.string(from: TimeInterval(total)) ?? "—"
    }
}
