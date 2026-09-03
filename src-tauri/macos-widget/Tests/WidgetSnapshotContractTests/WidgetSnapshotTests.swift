import Foundation
import Testing
import WidgetKit
@testable import OffWorkCountdownWidgetUI
@testable import WidgetSnapshotContract

@Test("A missing snapshot schedules another WidgetKit read")
func missingSnapshotRetriesInsteadOfSticking() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let provider = OffWorkCountdownTimelineProvider(appGroupIdentifier: nil)
    let timeline = provider.makeTimeline(now: now)

    #expect(timeline.entries.count == 1)
    #expect(timeline.entries[0].snapshotEntry == nil)
    guard case let .after(retryAt) = timeline.policy else {
        Issue.record("Missing snapshot timeline must use an after policy")
        return
    }
    #expect(
        retryAt == now.addingTimeInterval(
            OffWorkCountdownTimelineProvider.unavailableSnapshotRetryInterval
        )
    )
}

@Test("Swift decodes the fixture serialized by TypeScript")
func decodesTypeScriptFixture() throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "widget-snapshot-v1",
            withExtension: "json",
            subdirectory: "Fixtures"
        )
    )
    let snapshot = try JSONDecoder().decode(
        WidgetSnapshot.self,
        from: Data(contentsOf: fixtureURL)
    )

    #expect(snapshot.schemaVersion == widgetSnapshotSchemaVersion)
    #expect(snapshot.locale == "en")
    #expect(snapshot.entries.map(\.phase) == [.working, .break, .working, .done])
    #expect(snapshot.entries[1].remainingEffectiveMsAtDateMs == 4_000)
    #expect(snapshot.entries[1].progressAtDate == 50)
    #expect(snapshot.entry(atMs: 7_500)?.phase == .working)
    #expect(snapshot.entry(atMs: 13_000) == nil)
    // Working entries name the wall-clock finish (11_000), not
    // dateMs + remainingEffective (3_000 + 6_000 = 9_000). That sum
    // skips the lunch gap and is what the circular complication used
    // to print as the clock-off time.
    #expect(snapshot.entries[0].countdownTargetAtMs == 11_000)
    #expect(snapshot.entries[2].countdownTargetAtMs == 11_000)
    #expect(snapshot.upcoming.isEmpty)
    #expect(snapshot.clockOffsetMs == 0)
}

@Test("A clock offset remaps WidgetKit's real now onto the logical timeline")
func clockOffsetRemapsLookup() {
    let logicalNow: Int64 = 1_724_400_000_000
    let offset: Int64 = 63_072_000_000
    let working = WidgetTimelineEntry(
        dateMs: logicalNow,
        validUntilMs: logicalNow + 10_000,
        phase: .working,
        labelKey: "widgetWorking",
        countdownKind: .workRemaining,
        countdownValueAtDateMs: 8_000,
        countdownTargetAtMs: logicalNow + 8_000,
        remainingEffectiveMsAtDateMs: 8_000,
        progressAtDate: 20,
        nextBoundaryAtMs: logicalNow + 10_000
    )
    let snapshot = WidgetSnapshot(
        schemaVersion: widgetSnapshotSchemaVersion,
        generatedAtMs: logicalNow,
        expiresAtMs: logicalNow + 10_000,
        locale: "en",
        shift: nil,
        entries: [working],
        clockOffsetMs: offset
    )
    let realNow = logicalNow + offset

    #expect(snapshot.logicalNowMs(fromRealMs: realNow) == logicalNow)
    #expect(snapshot.entry(atMs: logicalNow)?.phase == .working)
    #expect(snapshot.entry(atMs: realNow) == nil)
    #expect(
        snapshot.realDate(fromLogicalMs: logicalNow).timeIntervalSince1970
            == Double(realNow) / 1_000
    )
}

@Test("Unknown schemas and pre-generation dates are not rendered")
func rejectsUnsupportedOrPrematureSnapshots() throws {
    let data = try #require(
        """
        {
          "schemaVersion": 2,
          "generatedAtMs": 100,
          "expiresAtMs": 200,
          "locale": "en",
          "shift": null,
          "entries": []
        }
        """.data(using: .utf8)
    )
    let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

    #expect(snapshot.entry(atMs: 150) == nil)
    #expect(snapshot.entry(atMs: 50) == nil)
}

@Test("Working entries project progress without crossing their boundary")
func projectsWorkingProgress() {
    let entry = WidgetTimelineEntry(
        dateMs: 1_000,
        validUntilMs: 6_000,
        phase: .working,
        labelKey: "widgetWorking",
        countdownKind: .workRemaining,
        countdownValueAtDateMs: 8_000,
        countdownTargetAtMs: 9_000,
        remainingEffectiveMsAtDateMs: 8_000,
        progressAtDate: 20,
        nextBoundaryAtMs: 6_000
    )

    let projected = entry.projected(atMs: 3_000)
    #expect(projected.dateMs == 3_000)
    #expect(projected.remainingEffectiveMsAtDateMs == 6_000)
    #expect(projected.countdownValueAtDateMs == 6_000)
    #expect(projected.progressAtDate == 40)

    let capped = entry.projected(atMs: 10_000)
    #expect(capped.dateMs == 6_000)
    #expect(capped.remainingEffectiveMsAtDateMs == 3_000)
    #expect(capped.progressAtDate == 70)
}

@Test("Break entries keep the progress captured by the schedule producer")
func leavesBreakProgressPaused() {
    let entry = WidgetTimelineEntry(
        dateMs: 1_000,
        validUntilMs: 6_000,
        phase: .break,
        labelKey: "lunchInProgress",
        countdownKind: .breakEnds,
        countdownValueAtDateMs: 5_000,
        countdownTargetAtMs: 6_000,
        remainingEffectiveMsAtDateMs: 8_000,
        progressAtDate: 20,
        nextBoundaryAtMs: 6_000
    )

    #expect(entry.projected(atMs: 4_000) == entry)
}

@Test("Snapshot expands working progress but not paused intervals")
func expandsPresentationTimeline() {
    let working = WidgetTimelineEntry(
        dateMs: 1_000,
        validUntilMs: 5_000,
        phase: .working,
        labelKey: "widgetWorking",
        countdownKind: .workRemaining,
        countdownValueAtDateMs: 8_000,
        countdownTargetAtMs: 9_000,
        remainingEffectiveMsAtDateMs: 8_000,
        progressAtDate: 20,
        nextBoundaryAtMs: 5_000
    )
    let paused = WidgetTimelineEntry(
        dateMs: 5_000,
        validUntilMs: 8_000,
        phase: .break,
        labelKey: "lunchInProgress",
        countdownKind: .breakEnds,
        countdownValueAtDateMs: 3_000,
        countdownTargetAtMs: 8_000,
        remainingEffectiveMsAtDateMs: 4_000,
        progressAtDate: 60,
        nextBoundaryAtMs: 8_000
    )
    let snapshot = WidgetSnapshot(
        schemaVersion: widgetSnapshotSchemaVersion,
        generatedAtMs: 1_000,
        expiresAtMs: 8_000,
        locale: "en",
        shift: nil,
        entries: [working, paused]
    )

    let entries = snapshot.presentationEntries(startingAtMs: 2_000, progressStepMs: 1_000)
    #expect(entries.map(\.dateMs) == [2_000, 3_000, 4_000, 5_000])
    #expect(entries.map(\.progressAtDate) == [30, 40, 50, 60])
    #expect(entries.last?.phase == .break)
}

@Test("Presentation expansion stays inside the requested refresh window")
func boundsPresentationTimeline() {
    let working = WidgetTimelineEntry(
        dateMs: 1_000,
        validUntilMs: 10_000,
        phase: .working,
        labelKey: "widgetWorking",
        countdownKind: .workRemaining,
        countdownValueAtDateMs: 9_000,
        countdownTargetAtMs: 10_000,
        remainingEffectiveMsAtDateMs: 9_000,
        progressAtDate: 10,
        nextBoundaryAtMs: 10_000
    )
    let snapshot = WidgetSnapshot(
        schemaVersion: widgetSnapshotSchemaVersion,
        generatedAtMs: 1_000,
        expiresAtMs: 10_000,
        locale: "en",
        shift: nil,
        entries: [working]
    )

    let entries = snapshot.presentationEntries(
        startingAtMs: 2_000,
        progressStepMs: 1_000,
        endingAtMs: 5_000
    )

    #expect(entries.map(\.dateMs) == [2_000, 3_000, 4_000])
}

@Test("Portrait extra-large keeps raw value 4 across SDK availability flips")
func portraitExtraLargeRawValue() {
    #expect(
        WidgetFamily(rawValue: 4).map { String(describing: $0) } == "systemExtraLargePortrait"
    )
}

@Test("Upcoming widget dates add a weekday on any other calendar day")
func upcomingWidgetDateWeekdayVisibility() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
    let saturday = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 8,
        day: 29,
        hour: 14,
        minute: 22
    )))
    let laterToday = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 8,
        day: 29,
        hour: 17
    )))
    let sundayMorning = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 8,
        day: 30,
        hour: 1,
        minute: 33
    )))
    let sunday = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 8,
        day: 30,
        hour: 9
    )))
    let monday = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 8,
        day: 31,
        hour: 10
    )))

    #expect(!widgetUpcomingDateShowsWeekday(laterToday, relativeTo: saturday, calendar: calendar))
    #expect(widgetUpcomingDateShowsWeekday(sunday, relativeTo: saturday, calendar: calendar))
    #expect(widgetUpcomingDateShowsWeekday(monday, relativeTo: saturday, calendar: calendar))
    #expect(widgetUpcomingDateShowsWeekday(monday, relativeTo: sundayMorning, calendar: calendar))
}
