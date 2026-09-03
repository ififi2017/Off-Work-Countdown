import Foundation
import SwiftUI
import WidgetKit
import Darwin
import os
#if OWC_SWIFT_PACKAGE
import WidgetSnapshotContract
#endif

public let offWorkCountdownWidgetKind = "com.rainif.offworkcountdown.macappstore.widget"

private func widgetProductName(locale: String) -> String {
    #if os(iOS)
    "DoneAt"
    #else
    WidgetCopy.text("appShortName", locale: locale)
    #endif
}

func widgetUpcomingDateShowsWeekday(
    _ date: Date,
    relativeTo referenceDate: Date,
    calendar: Calendar
) -> Bool {
    // Same rule as ShiftPreviewRow: only today's clock can stand alone. A
    // rest-day "coming up" row for Monday 10:00 is tomorrow on Sunday; without
    // the weekday it reads as today.
    !calendar.isDate(date, inSameDayAs: referenceDate)
}

public let widgetSnapshotFileName = "widget-snapshot-v1.json"
public let localWidgetSnapshotDirectoryName =
    "com.rainif.offworkcountdown.macappstore.local-widget"

/// One log line per timeline build, readable in Console.app and in a
/// sysdiagnose without a debugger attached.
///
/// A Lock Screen complication stuck on the redacted placeholder is never a
/// drawing bug: it means the extension did not deliver a rendered timeline,
/// and the usual reason is that the process was killed for exceeding its
/// memory footprint while WidgetKit rendered the entries. That is invisible
/// from inside the app, so the numbers that decide it — how many entries this
/// build asked WidgetKit to render, and the process footprint when it
/// finished — are recorded here rather than reconstructed from a user report.
/// `phys_footprint` is the figure jetsam compares against the extension limit.
enum WidgetDiagnostics {
    private static let log = Logger(
        subsystem: "com.rainif.offworkcountdown.widget",
        category: "timeline"
    )

    static func timelineBuilt(
        family: String,
        snapshotBytes: Int,
        snapshotEntries: Int,
        timelineEntries: Int,
        elapsed: TimeInterval
    ) {
        log.info(
            "timeline family=\(family, privacy: .public) snapshotBytes=\(snapshotBytes, privacy: .public) snapshotEntries=\(snapshotEntries, privacy: .public) timelineEntries=\(timelineEntries, privacy: .public) elapsedMs=\(Int(elapsed * 1_000), privacy: .public) footprintKB=\(footprintBytes() / 1_024, privacy: .public)"
        )
    }

    static func snapshotUnavailable(family: String, reason: String) {
        log.info(
            "snapshot-unavailable family=\(family, privacy: .public) reason=\(reason, privacy: .public) footprintKB=\(footprintBytes() / 1_024, privacy: .public)"
        )
    }

    /// Resident footprint as jetsam measures it, not `resident_size`.
    private static func footprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}

private enum WidgetCopy {
    static var currentLocaleIdentifier: String {
        let preferred = (Locale.preferredLanguages.first ?? "en")
            .replacingOccurrences(of: "_", with: "-")
        let lowercased = preferred.lowercased()
        if lowercased.hasPrefix("zh") {
            if lowercased.contains("-hk") {
                return "zh-HK"
            }
            if lowercased.contains("hant") || lowercased.contains("-tw") || lowercased.contains("-mo") {
                return "zh-TW"
            }
            return "zh-CN"
        }

        switch lowercased.split(separator: "-").first.map(String.init) {
        case "hi": return "hi-IN"
        case "mr": return "mr-IN"
        case let base?: return base
        case nil: return "en"
        }
    }

    /// Compact families prefer a `<key>Short` variant when the bundle has one.
    /// Keys without a short form are unaffected, so this stays language-safe:
    /// nothing is truncated by guessing, only by a translator having supplied a
    /// deliberate short string.
    static func text(_ key: String, locale: String, compact: Bool) -> String {
        if compact {
            let short = text("\(key)Short", locale: locale)
            if short != "\(key)Short" { return short }
        }
        return text(key, locale: locale)
    }

    static func text(_ key: String, locale: String) -> String {
        for candidate in [locale, "en"] {
            if let value = table.value(forKey: key, locale: candidate) {
                return value
            }
        }
        return key
    }

    /// Every lookup used to re-open and re-parse the locale's ~45 KB,
    /// 800-key translation file. WidgetKit renders every timeline entry up
    /// front, so a single accessory reload paid that cost once per entry —
    /// around two hundred times — and the autoreleased dictionaries were a
    /// large share of what a widget extension is allowed to hold before
    /// jetsam takes it, which is what leaves a Lock Screen complication
    /// stuck on the redacted placeholder. A resource inside the bundle
    /// cannot change while the process lives, so one parse per locale is
    /// enough for all of them.
    private static let table = TranslationTable()

    /// WidgetKit can build timelines for several families off the main
    /// thread, so the table is guarded by a lock rather than isolated to an
    /// actor: every caller is a synchronous `View` body and has to stay that
    /// way.
    private final class TranslationTable: @unchecked Sendable {
        private let lock = NSLock()
        private var loaded: [String: [String: String]] = [:]

        func value(forKey key: String, locale: String) -> String? {
            lock.lock()
            defer { lock.unlock() }
            if let cached = loaded[locale] {
                return cached[key]
            }
            let table = Self.read(locale: locale)
            // A locale with no bundled file caches as empty on purpose, so a
            // missing translation costs one failed lookup instead of one per
            // entry.
            loaded[locale] = table
            return table[key]
        }

        private static func read(locale: String) -> [String: String] {
            guard let url = Bundle.main.url(
                forResource: "translation",
                withExtension: "json",
                subdirectory: "locales/\(locale)"
            ),
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
            else {
                return [:]
            }
            // `notificationToneMessages` and `microBreakMessages` are arrays.
            // Decoding straight into `[String: String]` would fail on them and
            // take every other key down with it, so non-strings are dropped
            // the same way the original `as? String` cast dropped them.
            return object.compactMapValues { $0 as? String }
        }
    }
}

public struct SharedWidgetSnapshotLoader: Sendable {
    public let appGroupIdentifier: String?
    public let storageMode: String

    public init(appGroupIdentifier: String?, storageMode: String = "app-group") {
        self.appGroupIdentifier = appGroupIdentifier
        self.storageMode = storageMode
    }

    public func load() -> WidgetSnapshot? {
        loadMeasured()?.snapshot
    }

    /// The decoded snapshot together with the size of the file it came from,
    /// so the diagnostic log line can report what this reload actually read.
    func loadMeasured() -> (snapshot: WidgetSnapshot, bytes: Int)? {
        guard let snapshotURL else { return nil }
        return Self.cache.snapshot(at: snapshotURL)
    }

    private var snapshotURL: URL? {
        let containerURL: URL?
        if storageMode == "local-support" {
            if let user = getpwuid(getuid()), let home = user.pointee.pw_dir {
                containerURL = URL(
                    fileURLWithPath: String(cString: home),
                    isDirectory: true
                )
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent(localWidgetSnapshotDirectoryName, isDirectory: true)
            } else {
                containerURL = nil
            }
        } else if let appGroupIdentifier, !appGroupIdentifier.isEmpty {
            containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier
            )
        } else {
            containerURL = nil
        }

        guard let containerURL else { return nil }
        return containerURL.appendingPathComponent(
            widgetSnapshotFileName,
            isDirectory: false
        )
    }

    /// One extension process serves every placed family, so a user with two
    /// Lock Screen complications and a Home Screen tile decoded the same
    /// half-megabyte file three times in a row, sometimes concurrently. The
    /// producer replaces the file atomically and never edits it in place, so
    /// its modification date and size together identify a generation.
    private static let cache = SnapshotCache()

    private final class SnapshotCache: @unchecked Sendable {
        private let lock = NSLock()
        private var url: URL?
        private var modified: Date?
        private var bytes: Int?
        private var cached: WidgetSnapshot?

        func snapshot(at url: URL) -> (snapshot: WidgetSnapshot, bytes: Int)? {
            // Stat outside the lock: it is the common path and it does not
            // touch anything shared.
            let attributes = try? FileManager.default
                .attributesOfItem(atPath: url.path)
            let modified = attributes?[.modificationDate] as? Date
            let size = (attributes?[.size] as? NSNumber)?.intValue

            lock.lock()
            defer { lock.unlock() }

            if let cached,
               self.url == url,
               let modified,
               let size,
               self.modified == modified,
               self.bytes == size {
                return (cached, size)
            }

            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder()
                    .decode(WidgetSnapshot.self, from: data)
            else {
                // A miss is never cached: the file is expected to appear as
                // soon as the app publishes, and the next read must see it.
                self.cached = nil
                self.url = nil
                self.modified = nil
                self.bytes = nil
                return nil
            }

            self.url = url
            self.modified = modified
            self.bytes = data.count
            self.cached = decoded
            return (decoded, data.count)
        }
    }
}

public struct OffWorkCountdownWidgetEntry: TimelineEntry, Sendable {
    public let date: Date
    public let snapshotEntry: WidgetTimelineEntry?
    public let locale: String
    public let upcoming: [WidgetUpcomingItem]
    public let clockOffsetMs: Int64

    public init(
        date: Date,
        snapshotEntry: WidgetTimelineEntry?,
        locale: String,
        upcoming: [WidgetUpcomingItem] = [],
        clockOffsetMs: Int64 = 0
    ) {
        self.date = date
        self.snapshotEntry = snapshotEntry
        self.locale = locale
        self.upcoming = upcoming
        self.clockOffsetMs = clockOffsetMs
    }

    var logicalNowMs: Int64 {
        Int64(date.timeIntervalSince1970 * 1_000) - clockOffsetMs
    }
}

public struct OffWorkCountdownTimelineProvider: TimelineProvider, Sendable {
    /// How far ahead one timeline reaches, and how finely a working interval
    /// is expanded inside it.
    ///
    /// WidgetKit renders every entry of a timeline up front, inside the
    /// extension's memory budget, so the entry count is a price paid on every
    /// reload — and an extension killed mid-render does not show an error, it
    /// leaves the Lock Screen sitting on its redacted placeholder. A
    /// five-minute step across this window produced around two hundred entries
    /// for an ordinary nine-to-six schedule. Fifteen minutes brings the same
    /// window under eighty while the ring still advances about 3% per entry,
    /// which is finer than the eye reads on a 58pt circle.
    ///
    /// The window stays at 36 hours deliberately. WidgetKit is asked to rebuild
    /// every 12 hours but may defer that under its refresh budget, and the
    /// extra day of slack is what stops a deferred reload from stranding the
    /// complication on the last entry it was handed.
    static let presentationWindowMs: Int64 = 36 * 60 * 60 * 1_000
    static let progressStepMs: Int64 = 15 * 60 * 1_000

    /// A snapshot can be briefly unavailable while the app is making its first
    /// App Group write, or while iOS is restoring the widget extension. Never
    /// let that transient read become the final timeline: `.never` would leave
    /// the widget on its empty state until the app next runs.
    ///
    /// Half an hour, not five minutes. Every real recovery is pushed rather
    /// than polled — the app calls `WidgetCenter.reloadTimelines` the moment it
    /// writes a snapshot — so this interval only has to catch the case where
    /// the app never runs again. WidgetKit grants a widget on the order of tens
    /// of reloads a day, and asking for 288 of them does not produce more; it
    /// just spends the allowance on reads that will fail again, which is its
    /// own way of leaving a widget looking stuck.
    static let unavailableSnapshotRetryInterval: TimeInterval = 30 * 60

    private let loader: SharedWidgetSnapshotLoader

    public init(appGroupIdentifier: String?, storageMode: String = "app-group") {
        loader = SharedWidgetSnapshotLoader(
            appGroupIdentifier: appGroupIdentifier,
            storageMode: storageMode
        )
    }

    public func placeholder(in _: Context) -> OffWorkCountdownWidgetEntry {
        OffWorkCountdownWidgetEntry(
            date: Date(),
            snapshotEntry: nil,
            locale: WidgetCopy.currentLocaleIdentifier
        )
    }

    public func getSnapshot(
        in context: Context,
        completion: @escaping @Sendable (OffWorkCountdownWidgetEntry) -> Void
    ) {
        completion(makeSnapshotEntry(now: Date(), family: context.family))
    }

    public func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<OffWorkCountdownWidgetEntry>) -> Void
    ) {
        completion(makeTimeline(now: Date(), family: context.family))
    }

    /// The single entry WidgetKit asks for when it wants a preview instead of a
    /// timeline. This used to be `makeTimeline(now:).entries[0]`: it built a
    /// full presentation timeline and threw all but one entry away, which is
    /// the most expensive possible answer to the cheapest question the provider
    /// is asked.
    func makeSnapshotEntry(
        now: Date,
        family: WidgetFamily? = nil
    ) -> OffWorkCountdownWidgetEntry {
        let nowMs = Int64(now.timeIntervalSince1970 * 1_000)
        guard let snapshot = loader.load() else {
            return OffWorkCountdownWidgetEntry(
                date: now,
                snapshotEntry: nil,
                locale: WidgetCopy.currentLocaleIdentifier
            )
        }
        let logicalNowMs = snapshot.logicalNowMs(fromRealMs: nowMs)
        return OffWorkCountdownWidgetEntry(
            date: now,
            snapshotEntry: snapshot.entry(atMs: logicalNowMs),
            locale: snapshot.locale,
            upcoming: Self.familyCarriesUpcoming(family) ? snapshot.upcoming : [],
            clockOffsetMs: snapshot.clockOffsetMs
        )
    }

    func makeTimeline(
        now: Date,
        family: WidgetFamily? = nil
    ) -> Timeline<OffWorkCountdownWidgetEntry> {
        let startedAt = Date()
        let familyName = Self.familyName(family)
        let nowMs = Int64(now.timeIntervalSince1970 * 1_000)
        guard let measured = loader.loadMeasured() else {
            WidgetDiagnostics.snapshotUnavailable(
                family: familyName,
                reason: "no-snapshot"
            )
            return unavailableSnapshotTimeline(
                now: now,
                locale: WidgetCopy.currentLocaleIdentifier
            )
        }
        let snapshot = measured.snapshot
        let logicalNowMs = snapshot.logicalNowMs(fromRealMs: nowMs)
        guard let current = snapshot.entry(atMs: logicalNowMs) else {
            WidgetDiagnostics.snapshotUnavailable(
                family: familyName,
                reason: "no-current-entry"
            )
            return unavailableSnapshotTimeline(
                now: now,
                locale: snapshot.locale,
                clockOffsetMs: snapshot.clockOffsetMs
            )
        }
        let carriesUpcoming = Self.familyCarriesUpcoming(family)

        #if os(iOS)
        var timelineEntries = makeIOSTimelineEntries(
            snapshot: snapshot,
            nowMs: logicalNowMs,
            carriesUpcoming: carriesUpcoming
        )
        let refreshAtMs = min(
            snapshot.expiresAtMs + snapshot.clockOffsetMs,
            nowMs + 12 * 60 * 60 * 1_000
        )
        let reloadPolicy: TimelineReloadPolicy = .after(
            Date(timeIntervalSince1970: Double(refreshAtMs) / 1_000)
        )
        #else
        var timelineEntries = [
            OffWorkCountdownWidgetEntry(
                date: now,
                snapshotEntry: current,
                locale: snapshot.locale,
                upcoming: carriesUpcoming ? snapshot.upcoming : [],
                clockOffsetMs: snapshot.clockOffsetMs
            )
        ]
        timelineEntries.append(
            contentsOf: snapshot.entries
                .filter { $0.dateMs > logicalNowMs && $0.dateMs < snapshot.expiresAtMs }
                .map {
                    OffWorkCountdownWidgetEntry(
                        date: snapshot.realDate(fromLogicalMs: $0.dateMs),
                        snapshotEntry: $0,
                        locale: snapshot.locale,
                        upcoming: carriesUpcoming ? snapshot.upcoming : [],
                        clockOffsetMs: snapshot.clockOffsetMs
                    )
                }
        )
        let reloadPolicy: TimelineReloadPolicy = .never
        #endif
        // 到期时主动切到保守空态，不继续用旧班次猜算。iOS 会在到期前周期性
        // 重建轻量展示时间线；macOS 仍由宿主在状态变化时主动 reload。
        timelineEntries.append(
            OffWorkCountdownWidgetEntry(
                date: snapshot.realDate(fromLogicalMs: snapshot.expiresAtMs),
                snapshotEntry: nil,
                locale: snapshot.locale,
                clockOffsetMs: snapshot.clockOffsetMs
            )
        )
        WidgetDiagnostics.timelineBuilt(
            family: familyName,
            snapshotBytes: measured.bytes,
            snapshotEntries: snapshot.entries.count,
            timelineEntries: timelineEntries.count,
            elapsed: Date().timeIntervalSince(startedAt)
        )
        return Timeline(entries: timelineEntries, policy: reloadPolicy)
    }

    private func unavailableSnapshotTimeline(
        now: Date,
        locale: String,
        clockOffsetMs: Int64 = 0
    ) -> Timeline<OffWorkCountdownWidgetEntry> {
        Timeline(
            entries: [
                OffWorkCountdownWidgetEntry(
                    date: now,
                    snapshotEntry: nil,
                    locale: locale,
                    clockOffsetMs: clockOffsetMs
                )
            ],
            policy: .after(
                now.addingTimeInterval(Self.unavailableSnapshotRetryInterval)
            )
        )
    }

    /// Only the families that actually draw the "coming up" list need to carry
    /// it. A recurring snapshot's list runs to roughly a thousand localized
    /// rows, and every entry of every timeline used to hold one — including on
    /// a Lock Screen complication with no room to show a single row of it.
    static func familyCarriesUpcoming(_ family: WidgetFamily?) -> Bool {
        #if os(iOS)
        // No family means a caller that is not WidgetKit (a test, or the
        // default path); keep the whole payload rather than guessing.
        guard let family else { return true }
        if family == .systemLarge || family == .systemExtraLarge { return true }
        if #available(iOS 27.0, *),
           family.rawValue
               == OffWorkCountdownWidgetView.systemExtraLargePortraitRawValue {
            return true
        }
        return false
        #else
        return true
        #endif
    }

    private static func familyName(_ family: WidgetFamily?) -> String {
        guard let family else { return "unspecified" }
        return String(describing: family)
    }

    #if os(iOS)
    /// Home Screen and accessory widgets only redraw reliably when WidgetKit
    /// advances to a new timeline entry. `Text(style: .timer)` keeps counting on
    /// its own, but ordinary rings and bars do not, so working intervals include
    /// lightweight presentation entries. Schedule decisions remain in the
    /// producer snapshot and macOS keeps its existing boundary-only path.
    private func makeIOSTimelineEntries(
        snapshot: WidgetSnapshot,
        nowMs: Int64,
        carriesUpcoming: Bool
    ) -> [OffWorkCountdownWidgetEntry] {
        let presentationEndMs = min(
            snapshot.expiresAtMs,
            nowMs + Self.presentationWindowMs
        )
        var presentation = snapshot.presentationEntries(
            startingAtMs: nowMs,
            progressStepMs: Self.progressStepMs,
            endingAtMs: presentationEndMs
        )
        let existingDates = Set(presentation.map(\.dateMs))
        // The upcoming list still schedules redraws at event boundaries even
        // for families that do not carry it: knowing when to redraw is not the
        // same as needing the rows in the payload.
        for item in snapshot.upcoming
        where item.dateMs > nowMs && item.dateMs < presentationEndMs {
            guard !existingDates.contains(item.dateMs),
                  let source = snapshot.entry(atMs: item.dateMs)
            else { continue }
            presentation.append(source.projected(atMs: item.dateMs))
        }
        return presentation
            .sorted { $0.dateMs < $1.dateMs }
            .map {
                widgetEntry($0, snapshot: snapshot, carriesUpcoming: carriesUpcoming)
            }
    }

    private func widgetEntry(
        _ snapshotEntry: WidgetTimelineEntry,
        snapshot: WidgetSnapshot,
        carriesUpcoming: Bool
    ) -> OffWorkCountdownWidgetEntry {
        OffWorkCountdownWidgetEntry(
            date: snapshot.realDate(fromLogicalMs: snapshotEntry.dateMs),
            snapshotEntry: snapshotEntry,
            locale: snapshot.locale,
            upcoming: carriesUpcoming ? snapshot.upcoming : [],
            clockOffsetMs: snapshot.clockOffsetMs
        )
    }
    #endif
}

public struct OffWorkCountdownWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.calendar) private var calendar
    #if os(iOS)
    @Environment(\.widgetContentMargins) private var widgetContentMargins
    #endif
    public let entry: OffWorkCountdownWidgetEntry

    public init(entry: OffWorkCountdownWidgetEntry) {
        self.entry = entry
    }

    public var body: some View {
        widgetBackground {
            contentInset {
                Group {
                    if let snapshotEntry = entry.snapshotEntry {
                        #if os(iOS)
                        if family == .accessoryCircular {
                            // Fill the slot and centre. Only the `Gauge`
                            // branches size themselves to the circle; a bare
                            // glyph or a stacked label keeps its intrinsic size
                            // and the container parks it in the corner, which is
                            // what put the "off work" checkmark in the top-left.
                            // `rectangularAccessory` has carried the same frame
                            // from the start, which is why it looked right.
                            circularAccessory(snapshotEntry)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if family == .accessoryRectangular {
                            rectangularAccessory(snapshotEntry)
                        } else if family == .systemLarge {
                            largeContent(snapshotEntry)
                        } else if family == .systemExtraLarge {
                            extraLargeContent(snapshotEntry)
                        } else if isSystemExtraLargePortrait {
                            extraLargePortraitContent(snapshotEntry)
                        } else if family == .systemMedium {
                            mediumContent(snapshotEntry)
                        } else {
                            smallContent(snapshotEntry)
                        }
                        #else
                        if family == .systemMedium {
                            mediumContent(snapshotEntry)
                        } else {
                            smallContent(snapshotEntry)
                        }
                        #endif
                    } else {
                        #if os(iOS)
                        if family == .accessoryCircular {
                            // A circular complication has room for one glyph.
                            // The full empty state — a header, a 42pt badge and
                            // two lines of copy — was being crammed into it.
                            Image(systemName: "play.fill")
                                .font(.body.bold())
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .accessibilityLabel(
                                    WidgetCopy.text("countdownNotStarted", locale: entry.locale)
                                )
                        } else if family == .accessoryRectangular {
                            Label {
                                Text(WidgetCopy.text("countdownNotStarted", locale: entry.locale))
                            } icon: {
                                Image(systemName: "play.fill")
                            }
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        } else {
                            emptyContent
                        }
                        #else
                        emptyContent
                        #endif
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .environment(\.locale, Locale(identifier: entry.locale))
        .widgetURL(URL(string: "offworkcountdown://open"))
    }

    #if os(iOS)
    /// A 58pt monochrome circle. The ring carries the progress; the middle
    /// carries the moment it is counting toward.
    ///
    /// It used to read "73%", which says something is three-quarters done
    /// without saying three-quarters of what — on a Lock Screen full of rings
    /// that reads like a battery. A nearly-full ring around "19:00" says the
    /// same thing and names the finish line, in the same five glyphs.
    ///
    /// The done state has no ring, so the checkmark and label use the whole
    /// circle — not the Gauge inner-hole sizes the countdown labels need.
    @ViewBuilder
    private func circularAccessory(_ snapshotEntry: WidgetTimelineEntry) -> some View {
        if snapshotEntry.phase == .done {
            VStack(spacing: 2) {
                Image(systemName: "checkmark")
                    .font(.title2.bold())
                Text(WidgetCopy.text("shareDone", locale: entry.locale))
                    .font(.footnote.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(WidgetCopy.text("offWorkToday", locale: entry.locale))
        } else if snapshotEntry.phase == .idle {
            Image(systemName: "play.fill")
                .font(.body.bold())
                .accessibilityLabel(WidgetCopy.text(snapshotEntry.labelKey, locale: entry.locale))
        } else if let targetAtMs = snapshotEntry.countdownTargetAtMs {
            // One branch for every timed phase. Before the shift the ring is
            // empty and the time is when work starts; during it the ring fills
            // toward the time work ends; through lunch the ring holds still and
            // the time is when it resumes.
            Gauge(value: snapshotEntry.progressAtDate, in: 0...100) {
                EmptyView()
            } currentValueLabel: {
                Text(Date(timeIntervalSince1970: Double(targetAtMs) / 1_000), style: .time)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.52)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessibilityLabel(WidgetCopy.text(snapshotEntry.labelKey, locale: entry.locale))
        } else {
            // No target to name — fall back to the ring alone rather than an
            // empty circle.
            Gauge(value: snapshotEntry.progressAtDate, in: 0...100) {
                EmptyView()
            } currentValueLabel: {
                Text("\(roundedProgress(snapshotEntry.progressAtDate))%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessibilityLabel(WidgetCopy.text(snapshotEntry.labelKey, locale: entry.locale))
        }
    }

    /// The wide Lock Screen family, and the one that can actually say what it
    /// is. A circle this app's size has room for a ring and four or five
    /// glyphs; naming itself as well would shrink both past legibility. Here
    /// there is room for the name, the countdown and the bar together.
    @ViewBuilder
    private func rectangularAccessory(_ snapshotEntry: WidgetTimelineEntry) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Label {
                    Text(verbatim: widgetProductName(locale: entry.locale))
                } icon: {
                    brandMark.frame(width: 12, height: 12)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                // On a rest day and on a workday morning this complication
                // draws the same countdown and the same bar, so the state it
                // is in was the one thing it never said. The glyph is the
                // cheapest place to say it: the name row already exists and
                // its trailing end was empty.
                if let status = rectangularStatus(snapshotEntry) {
                    Spacer(minLength: 2)
                    Image(systemName: status.symbol)
                        .accessibilityLabel(
                            WidgetCopy.text(status.labelKey, locale: entry.locale)
                        )
                }
            }
            .font(.caption2)
            .widgetAccentable()

            if snapshotEntry.countdownTargetAtMs != nil {
                countdown(for: snapshotEntry, size: 21)
                Gauge(value: snapshotEntry.progressAtDate, in: 0...100) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
            } else {
                Text(WidgetCopy.text(snapshotEntry.labelKey, locale: entry.locale))
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The four states worth a mark, in the symbols the app already uses for
    /// them elsewhere. "Done for today" is deliberately absent: it arrives as
    /// a notification and the complication says it in words, so a glyph would
    /// be the third time.
    private func rectangularStatus(
        _ snapshotEntry: WidgetTimelineEntry
    ) -> (symbol: String, labelKey: String)? {
        switch snapshotEntry.labelKey {
        case "widgetWorking": ("briefcase.fill", "widgetWorking")
        case "lunchInProgress": ("cup.and.saucer.fill", "lunchInProgress")
        case "overtime": ("clock.arrow.circlepath", "overtime")
        case "widgetRestDay": ("bed.double.fill", "recordsRestDay")
        default: nil
        }
    }
    #endif

    /// macOS 14 起 WidgetKit 自己就会给内容加一圈默认 content margins（实测
    /// 16pt），`containerBackground` 只保证**背景**铺满整块，内容仍然被缩进。
    /// 这里再叠一层自己的 padding 就是双重内边距：medium 实际缩进 34pt、small
    /// 31pt，small 的可用宽度被压到 ~96pt，倒计时会被截断成 `0:0…`。
    ///
    /// 不用 `contentMarginsDisabled()` 关掉系统那层：它是 macOS 14+ API，而
    /// `WidgetConfigurationBuilder` 没有 `buildLimitedAvailability`，`if
    /// #available` 的两个分支类型对不上（实测编译报 "branches have mismatching
    /// types"）。为它把 Widget 的部署目标抬到 14 又与决策 5「最低系统版本统一为
    /// macOS 13」冲突。ViewBuilder 有 `buildLimitedAvailability`，所以按版本决定
    /// 要不要自己加内边距，把分叉留在 View 层。
    ///
    /// iOS Home Screen widgets usually arrive already inset (~16pt). iPad
    /// `.systemLarge` / extra-large often report zero `widgetContentMargins`,
    /// so the same layout that looks fine on iPhone sits on the rounded
    /// corners. Top up to 16pt instead of always padding, so iPhone is not
    /// double-inset.
    @ViewBuilder
    private func contentInset<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        #if os(iOS)
        content().padding(missingHomeScreenMargins(minimum: 16))
        #else
        if #available(macOS 14.0, *) {
            content()
        } else {
            content().padding(family == .systemMedium ? 18 : 15)
        }
        #endif
    }

    #if os(iOS)
    private func missingHomeScreenMargins(minimum: CGFloat) -> EdgeInsets {
        switch family {
        case .accessoryCircular, .accessoryRectangular:
            return EdgeInsets()
        default:
            break
        }
        return EdgeInsets(
            top: max(0, minimum - widgetContentMargins.top),
            leading: max(0, minimum - widgetContentMargins.leading),
            bottom: max(0, minimum - widgetContentMargins.bottom),
            trailing: max(0, minimum - widgetContentMargins.trailing)
        )
    }
    #endif

    private func header(compact: Bool) -> some View {
        HStack(spacing: 8) {
            brandMark
                .frame(width: compact ? 20 : 22, height: compact ? 20 : 22)

            // Short name here too: the header sits beside a 22pt mark on a
            // small widget, and the full name wrapped onto a second line in
            // every language that is not CJK.
            Text(verbatim: widgetProductName(locale: entry.locale))
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 0)
        }
    }

    /// Bare Open Day mark, not the plated app icon. The widget is already a
    /// rounded container; a second grey plate inside it reads as a sticker.
    @ViewBuilder
    private var brandMark: some View {
        #if os(iOS)
        Image("BrandMark")
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
        #else
        WidgetBrandMark()
            .accessibilityHidden(true)
        #endif
    }

    private func statusBadge(_ snapshotEntry: WidgetTimelineEntry, compact: Bool = false) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(phaseColor(snapshotEntry.phase))
                .frame(width: 6, height: 6)
            Text(WidgetCopy.text(snapshotEntry.labelKey, locale: entry.locale, compact: compact))
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(.primary.opacity(0.82))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(phaseColor(snapshotEntry.phase).opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func smallContent(_ snapshotEntry: WidgetTimelineEntry) -> some View {
        smallContentBody(snapshotEntry, progress: snapshotEntry.progressAtDate)
    }

    private func smallContentBody(
        _ snapshotEntry: WidgetTimelineEntry,
        progress: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(compact: true)
            Spacer(minLength: 7)
            statusBadge(snapshotEntry, compact: true)
            Spacer(minLength: 6)
            countdown(for: snapshotEntry, size: 33)
            Spacer(minLength: 7)
            progressBar(progress)
            Spacer(minLength: 5)
            HStack(spacing: 6) {
                Text("\(roundedProgress(progress))%")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(accentColor)
                Spacer(minLength: 4)
                boundaryTime(snapshotEntry)
            }
        }
    }

    @ViewBuilder
    private func mediumContent(_ snapshotEntry: WidgetTimelineEntry) -> some View {
        mediumContentBody(snapshotEntry, progress: snapshotEntry.progressAtDate)
    }

    private func mediumContentBody(
        _ snapshotEntry: WidgetTimelineEntry,
        progress: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(compact: false)
            Spacer(minLength: 9)
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    statusBadge(snapshotEntry)
                    countdown(for: snapshotEntry, size: 38)
                    boundaryTime(snapshotEntry)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                progressRing(progress)
            }
        }
    }

    #if os(iOS)
    /// 4×6 Home Screen / Today View family. The named
    /// `WidgetFamily.systemExtraLargePortrait` case is visionOS-only in the
    /// iOS 26 SDK (`@available(iOS, unavailable)`) and becomes an iOS 27
    /// family in Xcode 27. Raw value 4 is stable across both, so both
    /// toolchains compile without referencing the unavailable case.
    fileprivate static let systemExtraLargePortraitRawValue = 4

    private var isSystemExtraLargePortrait: Bool {
        guard #available(iOS 27.0, *) else { return false }
        return family.rawValue == Self.systemExtraLargePortraitRawValue
    }

    private var remainingUpcoming: [WidgetUpcomingItem] {
        let nowMs = entry.logicalNowMs
        return entry.upcoming.filter { $0.dateMs > nowMs }
    }

    @ViewBuilder
    private func largeContent(_ snapshotEntry: WidgetTimelineEntry) -> some View {
        stackedUpcomingContent(snapshotEntry, countdownSize: 40, upcomingLimit: 4)
    }

    /// iOS 27 4×6 portrait XL. Same width as `.systemLarge`, extra height
    /// for more of the coming-up list. Not the iPad landscape two-column XL.
    @ViewBuilder
    private func extraLargePortraitContent(_ snapshotEntry: WidgetTimelineEntry) -> some View {
        stackedUpcomingContent(snapshotEntry, countdownSize: 40, upcomingLimit: 6)
    }

    @ViewBuilder
    private func stackedUpcomingContent(
        _ snapshotEntry: WidgetTimelineEntry,
        countdownSize: CGFloat,
        upcomingLimit: Int
    ) -> some View {
        let upcoming = remainingUpcoming
        VStack(alignment: .leading, spacing: 0) {
            header(compact: false)
            Spacer(minLength: 8)
            statusBadge(snapshotEntry)
            Spacer(minLength: 6)
            countdown(for: snapshotEntry, size: countdownSize)
            Spacer(minLength: 8)
            progressBar(snapshotEntry.progressAtDate)
            HStack(spacing: 6) {
                Text("\(roundedProgress(snapshotEntry.progressAtDate))%")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(accentColor)
                Spacer(minLength: 4)
                boundaryTime(snapshotEntry)
            }
            .padding(.top, 6)
            if !upcoming.isEmpty {
                Spacer(minLength: 14)
                upcomingSection(upcoming, limit: upcomingLimit)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func extraLargeContent(_ snapshotEntry: WidgetTimelineEntry) -> some View {
        let upcoming = remainingUpcoming
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 0) {
                header(compact: false)
                Spacer(minLength: 10)
                statusBadge(snapshotEntry)
                Spacer(minLength: 8)
                countdown(for: snapshotEntry, size: 46)
                Spacer(minLength: 10)
                progressBar(snapshotEntry.progressAtDate)
                HStack(spacing: 6) {
                    Text("\(roundedProgress(snapshotEntry.progressAtDate))%")
                        .font(.callout.weight(.bold).monospacedDigit())
                        .foregroundStyle(accentColor)
                    Spacer(minLength: 4)
                    boundaryTime(snapshotEntry)
                }
                .padding(.top, 8)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !upcoming.isEmpty {
                upcomingSection(upcoming, limit: 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func upcomingSection(_ items: [WidgetUpcomingItem], limit: Int) -> some View {
        let visible = Array(items.prefix(limit))
        return VStack(alignment: .leading, spacing: 0) {
            Text(WidgetCopy.text("comingUp", locale: entry.locale))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            ForEach(visible) { item in
                upcomingRow(item, isLast: item.id == visible.last?.id)
            }
        }
    }

    private func upcomingRow(_ item: WidgetUpcomingItem, isLast: Bool) -> some View {
        let date = Date(timeIntervalSince1970: Double(item.dateMs) / 1_000)
        let showsWeekday = widgetUpcomingDateShowsWeekday(
            date,
            relativeTo: Date(timeIntervalSince1970: Double(entry.logicalNowMs) / 1_000),
            calendar: calendar
        )
        return HStack(spacing: 8) {
            Image(systemName: upcomingGlyph(item))
                .font(.caption.weight(.semibold))
                .foregroundStyle(accentColor)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 6)
            Group {
                if showsWeekday {
                    Text(date, format: .dateTime.weekday(.abbreviated).hour().minute())
                } else {
                    Text(date, style: .time)
                }
            }
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 0.5)
                    .padding(.leading, 24)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func upcomingGlyph(_ item: WidgetUpcomingItem) -> String {
        if let symbolName = item.symbolName, !symbolName.isEmpty { return symbolName }
        return switch item.kind {
        case "shiftStart": "sunrise.fill"
        case "lunchStart": "cup.and.saucer.fill"
        case "lunchEnd": "arrow.right.circle.fill"
        case "health": "figure.walk"
        case "focus": "timer"
        case "focusBreak": "cup.and.saucer.fill"
        case "milestone": "bell.badge.fill"
        case "shiftEnd": "flag.checkered"
        default: "clock"
        }
    }
    #endif

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(compact: family == .systemSmall)
            Spacer(minLength: 8)
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accentColor.opacity(colorScheme == .dark ? 0.22 : 0.12))
                    Image(systemName: "sun.horizon.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    // Small has roughly 100pt left once the badge is placed,
                    // which wrapped even five CJK glyphs onto a second line.
                    // Shrink to fit there; medium has the width to spare.
                    Text(WidgetCopy.text("countdownNotStarted", locale: entry.locale))
                        .font(.callout.weight(.bold))
                        .lineLimit(family == .systemMedium ? 2 : 1)
                        .minimumScaleFactor(0.6)
                    Text(WidgetCopy.text("widgetOpenToRefresh", locale: entry.locale))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func countdown(
        for snapshotEntry: WidgetTimelineEntry,
        size: CGFloat
    ) -> some View {
        if let timerDate = timerDate(for: snapshotEntry) {
            Text(timerDate, style: .timer)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: true))
            .lineLimit(1)
            .minimumScaleFactor(0.62)
        } else {
            // 收缩规则要和上面的动态分支一致：少了 lineLimit / minimumScaleFactor
            // 时，宽度不够不会缩字号而是直接截断，small 上就是截图里那个 `0:0…`。
            Text(verbatim: "0:00:00")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
    }

    /// `.timer` counts remaining *effective* work during a shift, so it must
    /// not use `countdownTargetAtMs` — that field is the wall-clock finish
    /// (19:00), and treating it as a timer would eat the lunch gap.
    ///
    /// Debug captures keep those finish times on the virtual clock so
    /// `Text(style: .time)` still reads 17:00. The system timer itself has
    /// to land in real time, which is what `clockOffsetMs` is for.
    private func timerDate(for snapshotEntry: WidgetTimelineEntry) -> Date? {
        switch snapshotEntry.countdownKind {
        case .workRemaining:
            let remaining = snapshotEntry.remainingEffectiveMsAtDateMs
            guard remaining > 0 else { return nil }
            return Date(
                timeIntervalSince1970: Double(
                    snapshotEntry.dateMs + remaining + entry.clockOffsetMs
                ) / 1_000
            )
        default:
            guard let targetAtMs = snapshotEntry.countdownTargetAtMs else { return nil }
            return Date(
                timeIntervalSince1970: Double(targetAtMs + entry.clockOffsetMs) / 1_000
            )
        }
    }

    private func progressBar(_ progress: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.10))
                Capsule()
                    .fill(accentGradient)
                    .frame(width: geometry.size.width * progressFraction(progress))
            }
        }
        .frame(height: 7)
    }

    private func progressRing(_ progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.08), lineWidth: 8)
            Circle()
                .trim(from: 0, to: progressFraction(progress))
                .stroke(
                    accentGradient,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(roundedProgress(progress))%")
                .font(.system(.callout, design: .rounded, weight: .bold))
                .monospacedDigit()
        }
        .frame(width: 76, height: 76)
        .padding(.trailing, 3)
    }

    @ViewBuilder
    private func boundaryTime(_ snapshotEntry: WidgetTimelineEntry) -> some View {
        if let nextBoundaryAtMs = snapshotEntry.nextBoundaryAtMs {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 9, weight: .semibold))
                Text(
                    Date(timeIntervalSince1970: Double(nextBoundaryAtMs) / 1_000),
                    style: .time
                )
                .monospacedDigit()
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        }
    }

    private var accentColor: Color {
        Color(red: 1.0, green: 0.38, blue: 0.08)
    }

    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accentColor, Color(red: 1.0, green: 0.68, blue: 0.16)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func phaseColor(_ phase: WidgetTimelinePhase) -> Color {
        switch phase {
        case .before: return .indigo
        case .working: return accentColor
        case .break: return .cyan
        case .done: return .green
        case .idle: return .secondary
        }
    }

    private func progressFraction(_ progress: Double) -> Double {
        min(1, max(0, progress / 100))
    }

    private func roundedProgress(_ progress: Double) -> Int {
        Int(min(100, max(0, progress)).rounded())
    }

    @ViewBuilder
    private func widgetBackground<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(macOS 14.0, *) {
            content()
                .containerBackground(for: .widget) {
                    // Accessory families render vibrant on the Lock Screen and
                    // the system discards whatever the widget draws behind
                    // them. The gradient and its 38pt blur were being
                    // composited once per timeline entry and then thrown away,
                    // on the one surface where the extension can least afford
                    // it. The container background itself still has to be
                    // declared — iOS 17 requires it of every widget.
                    if isAccessoryFamily {
                        Color.clear
                    } else {
                        backgroundLayer
                    }
                }
        } else {
            content().background(backgroundLayer)
        }
    }

    private var isAccessoryFamily: Bool {
        #if os(iOS)
        family == .accessoryCircular || family == .accessoryRectangular
        #else
        false
        #endif
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.10, green: 0.10, blue: 0.12),
                        Color(red: 0.14, green: 0.12, blue: 0.11),
                    ]
                    : [
                        Color(red: 1.0, green: 0.99, blue: 0.98),
                        Color(red: 0.98, green: 0.96, blue: 0.93),
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(accentColor.opacity(colorScheme == .dark ? 0.10 : 0.08))
                .frame(width: 180, height: 180)
                .blur(radius: 38)
                .offset(x: 95, y: -80)
        }
    }
}

public struct OffWorkCountdownWidget: Widget {
    private let appGroupIdentifier: String?
    private let storageMode: String

    public init() {
        appGroupIdentifier = Bundle.main.object(
            forInfoDictionaryKey: "OWCAppGroupIdentifier"
        ) as? String
        storageMode = Bundle.main.object(
            forInfoDictionaryKey: "OWCWidgetStorageMode"
        ) as? String ?? "app-group"
    }

    public init(appGroupIdentifier: String?, storageMode: String = "app-group") {
        self.appGroupIdentifier = appGroupIdentifier
        self.storageMode = storageMode
    }

    public var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: offWorkCountdownWidgetKind,
            provider: OffWorkCountdownTimelineProvider(
                appGroupIdentifier: appGroupIdentifier,
                storageMode: storageMode
            )
        ) { entry in
            OffWorkCountdownWidgetView(entry: entry)
        }
        .configurationDisplayName(
            Text(
                verbatim: widgetProductName(
                    locale: WidgetCopy.currentLocaleIdentifier
                )
            )
        )
        .description(
            Text(
                verbatim: WidgetCopy.text(
                    "widgetDescription",
                    locale: WidgetCopy.currentLocaleIdentifier
                )
            )
        )
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        #if os(iOS)
        var families: [WidgetFamily] = [
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .systemExtraLarge,
            .accessoryCircular,
            .accessoryRectangular,
        ]
        if #available(iOS 27.0, *),
           let portraitXL = WidgetFamily(
               rawValue: OffWorkCountdownWidgetView.systemExtraLargePortraitRawValue
           ) {
            families.append(portraitXL)
        }
        return families
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

#if !os(iOS)
/// Vector twin of `assets/brand/off-work-countdown-mark.svg` for the macOS
/// widget, which does not ship the iOS `BrandMark` catalog. Ring, hands and
/// endpoint only — no plated background.
private struct WidgetBrandMark: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 1024
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            var ring = Path()
            ring.addArc(
                center: centre,
                radius: 298 * scale,
                startAngle: .degrees(109),
                endAngle: .degrees(109 + 262),
                clockwise: false
            )
            context.stroke(
                ring,
                with: .color(Color(red: 0.976, green: 0.451, blue: 0.086)),
                style: StrokeStyle(lineWidth: 110 * scale, lineCap: .round)
            )

            let origin = CGPoint(
                x: centre.x - 512 * scale,
                y: centre.y - 512 * scale
            )
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
            }
            var hands = Path()
            hands.move(to: point(512, 347))
            hands.addLine(to: point(512, 512))
            hands.addLine(to: point(573, 617.7))
            let handColor = colorScheme == .dark
                ? Color(red: 1.0, green: 0.945, blue: 0.847)
                : Color(red: 0.169, green: 0.098, blue: 0.208)
            context.stroke(
                hands,
                with: .color(handColor),
                style: StrokeStyle(lineWidth: 88 * scale, lineCap: .round, lineJoin: .round)
            )

            let endpoint = CGRect(
                x: origin.x + 664.5 * scale - 86 * scale,
                y: origin.y + 776.1 * scale - 86 * scale,
                width: 172 * scale,
                height: 172 * scale
            )
            context.fill(
                Path(ellipseIn: endpoint),
                with: .color(Color(red: 0.976, green: 0.451, blue: 0.086))
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
#endif
