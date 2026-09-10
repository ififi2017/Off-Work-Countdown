import Foundation

/// One time zone for the whole test process.
///
/// The store's zone falls through to `TimeZone.current` when nothing has been
/// stored, and everything it schedules against is civil time — the default
/// shift is 09:00–17:00, day keys come from `recordsCalendar`. Tests that
/// inject an absolute `Date(timeIntervalSince1970:)` therefore land at a
/// different hour, and sometimes a different day, on every machine. That went
/// unnoticed for as long as everyone ran the suite in one zone, and five tests
/// failed the first time Xcode Cloud ran them in another.
///
/// This is a test-only pin. Following the device is the correct product
/// behaviour — a shift belongs to the wall clock the person works against —
/// so the fix belongs here rather than in `OffWorkStore`.
///
/// `NSTimeZone.default` is the lever rather than the stored preference key,
/// because 140-odd assertions read `TimeZone.current` or `Calendar.current`
/// directly and never see a store at all.
enum TestTimeZone {
    /// The zone the fixed instants throughout the suite were chosen for.
    /// Changing it will fail tests whose epochs were picked to sit inside a
    /// working day here; convert those to `DateComponents` first.
    static let identifier = "Asia/Shanghai"

    /// Idempotent, and safe to call from anything that builds a test store.
    static func pin() {
        guard let zone = TimeZone(identifier: identifier) else { return }
        if NSTimeZone.default.identifier != identifier {
            NSTimeZone.default = zone
        }
    }

    /// Also writes the stored preference, so a store reads the pin directly
    /// instead of relying on the process default still being in place.
    static func pin(_ defaults: UserDefaults) {
        pin()
        defaults.set(identifier, forKey: "ios.native.recordsTimeZone")
    }
}
