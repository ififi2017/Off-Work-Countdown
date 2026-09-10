import Foundation

/// One time zone for every test store.
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
/// **This writes only the stored preference, never `NSTimeZone.default`.**
/// Setting the process default looked like the wider fix, because assertions
/// that read `TimeZone.current` directly never see a store. It also took main
/// from five failures to 465 crashes: Swift Testing runs tests in parallel in
/// one process, `NSTimeZone.default` is process-global, and mutating it while
/// other tests read it trips Foundation. The window is narrow enough that a
/// single idle simulator never hit it and four contending ones always did.
/// A per-suite `UserDefaults` write shares nothing and cannot race.
enum TestTimeZone {
    /// The zone the fixed instants throughout the suite were chosen for.
    /// Changing it will fail tests whose epochs were picked to sit inside a
    /// working day here; convert those to `DateComponents` first.
    static let identifier = "Asia/Shanghai"

    /// Pins the store built from these defaults, before it reads them.
    static func pin(_ defaults: UserDefaults) {
        defaults.set(identifier, forKey: "ios.native.recordsTimeZone")
    }
}
