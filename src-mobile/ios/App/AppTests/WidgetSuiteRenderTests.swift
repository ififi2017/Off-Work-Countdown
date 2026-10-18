import Foundation
import SwiftUI
import Testing
import WidgetKit
@testable import App

/// Every widget-suite view at every size it declares, rendered off screen
/// (plan 023). Always a smoke test: no size may fail to draw. With
/// `TEST_RUNNER_OWC_WIDGET_RENDER_DIR` set it also writes contact sheets for
/// visual review.
@MainActor
@Suite("Widget suite rendering")
struct WidgetSuiteRenderTests {
    @Test("Every widget renders at every declared size", arguments: ["zh-CN", "en"], [ColorScheme.light, .dark])
    func contactSheet(language: String, scheme: ColorScheme) async throws {
        let suite = "owc.widget.render.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Self.workingNow
        let runtime = AppRuntime(defaults: defaults, records: .inMemory())
        let shifts = runtime.shifts
        runtime.preferences.onboardingComplete = true
        runtime.preferences.applyPreferences {
            $0.scheduleMode = .classic
            $0.workdays = [1, 2, 3, 4, 5]
            $0.startMinutes = 9 * 60
            $0.endMinutes = 18 * 60
            $0.lunchEnabled = true
            $0.lunchStartMinutes = 12 * 60
            $0.lunchDurationMinutes = 60
            $0.languageOverride = language
        }
        shifts.startCountdown(at: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: now)!)

        let composer = WidgetSuiteComposer.shared
        let calendar = composer.calendarPayload(shifts: shifts, now: now, locale: language)
        let samples = WidgetGallerySamples(now: now, locale: language, text: shifts.text)
        let holiday = samples.holiday(base: composer.holidayPayload(shifts: shifts, calendar: calendar,
                                                                    access: .locked, now: now, locale: language))
        let locked = WidgetSummaryPayload(generatedAtMs: WidgetSuiteTime.ms(now), locale: language, access: .locked,
                                          periods: [], liveSegments: [], labels: [:])
        let snapshot = WidgetSnapshotComposer.shared.publishedSnapshot(shifts: shifts, now: now)
        let logical = snapshot.logicalNowMs(fromRealMs: WidgetSuiteTime.ms(now))
        let countdown = CountdownStyleEntry(
            base: OffWorkCountdownWidgetEntry(date: now, snapshotEntry: snapshot.entry(atMs: logical), locale: snapshot.locale,
                                              upcoming: snapshot.upcoming, clockOffsetMs: snapshot.clockOffsetMs),
            segments: snapshot.shift?.segments ?? []
        )
        let model = CountdownStyleModel(entry: countdown)
        let calendarEntry = CalendarWidgetEntry(date: now, payload: calendar)
        let holidayEntry = HolidayWidgetEntry(date: now, payload: holiday, calendar: calendar)

        let home: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
        let rows: [(String, [WidgetFamily], (WidgetFamily) -> AnyView)] = [
            ("Classic", home + [.accessoryCircular, .accessoryRectangular], { AnyView(OffWorkCountdownWidgetView(entry: countdown.base, familyOverride: $0)) }),
            ("Big digits · Ring · Timeline", [.systemSmall, .systemSmall, .accessoryCircular, .systemSmall], { _ in AnyView(EmptyView()) }),
            ("Detail", [.systemMedium, .systemLarge], { AnyView(CountdownDetailView(familyOverride: $0, model: model)) }),
            ("Week", [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular], { AnyView(WeekProgressView(familyOverride: $0, entry: calendarEntry)) }),
            ("Roster", home + [.accessoryRectangular], { AnyView(RosterView(familyOverride: $0, entry: calendarEntry)) }),
            ("Weekend · Holiday", [.systemSmall, .accessoryRectangular, .systemSmall, .systemMedium], { _ in AnyView(EmptyView()) }),
            ("Summary (sample)", home + [.accessoryRectangular, .accessoryCircular], { AnyView(SummaryWidgetView(familyOverride: $0, entry: SummaryWidgetEntry(date: now, payload: samples.summary))) }),
            ("Summary (locked)", [.systemSmall, .accessoryRectangular], { AnyView(SummaryWidgetView(familyOverride: $0, entry: SummaryWidgetEntry(date: now, payload: locked))) }),
            ("Life (sample) · Year", home + [.accessoryRectangular], { AnyView(LifeWidgetView(familyOverride: $0, entry: LifeWidgetEntry(date: now, payload: samples.life))) }),
            ("Focus (sample)", [.systemSmall, .systemMedium], { AnyView(FocusWidgetView(familyOverride: $0, entry: FocusWidgetEntry(date: now, payload: samples.focus))) }),
        ]
        let special: [String: [AnyView]] = [
            "Big digits · Ring · Timeline": [
                AnyView(CountdownBigDigitsView(model: model)),
                AnyView(CountdownRingView(familyOverride: .systemSmall, model: model)),
                AnyView(CountdownRingView(familyOverride: .accessoryCircular, model: model)),
                AnyView(CountdownTimelineView(model: model)),
            ],
            "Weekend · Holiday": [
                AnyView(WeekendWidgetView(familyOverride: .systemSmall, entry: holidayEntry)),
                AnyView(WeekendWidgetView(familyOverride: .accessoryRectangular, entry: holidayEntry)),
                AnyView(HolidayWidgetView(familyOverride: .systemSmall, entry: holidayEntry)),
                AnyView(HolidayWidgetView(familyOverride: .systemMedium, entry: holidayEntry)),
            ],
        ]

        let sheet = VStack(alignment: .leading, spacing: 24) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 8) {
                    Text(row.0).font(.headline)
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Array(row.1.enumerated()), id: \.offset) { index, family in
                            WidgetGalleryFrame(family: family) {
                                if let views = special[row.0] { views[index] } else { row.2(family) }
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
        .background(Color(uiColor: .systemGroupedBackground))
        .environment(\.colorScheme, scheme)

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        let image = try #require(renderer.uiImage)
        #expect(image.size.width > 0)

        if let directory = ProcessInfo.processInfo.environment["OWC_WIDGET_RENDER_DIR"],
           let data = image.pngData() {
            let name = "widgets-\(language)-\(scheme == .dark ? "dark" : "light").png"
            try data.write(to: URL(fileURLWithPath: directory).appending(path: name))
        }
    }

    /// A Monday at 15:19, inside the afternoon segment.
    static var workingNow: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 15, minute: 19))!
    }
}
