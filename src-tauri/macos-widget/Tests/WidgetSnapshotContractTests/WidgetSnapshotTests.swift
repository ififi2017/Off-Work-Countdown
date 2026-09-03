import Foundation
import Testing
import WidgetKit
@testable import OffWorkCountdownWidgetUI
@testable import WidgetSnapshotContract

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

/// A year of shifts, shaped like `WidgetSnapshotPublisher.makeRecurringSnapshot`
/// writes them: rest window, pre-work countdown, morning, lunch, afternoon,
/// then "done for today".
private func recurringSnapshot(
    days: Int = 370,
    startingAtMs day0: Int64 = 1_772_150_400_000
) -> WidgetSnapshot {
    let hour: Int64 = 3_600_000
    let dayMs: Int64 = 24 * hour
    var entries: [WidgetTimelineEntry] = []

    func entry(
        _ dateMs: Int64,
        _ validUntilMs: Int64,
        _ phase: WidgetTimelinePhase
    ) -> WidgetTimelineEntry {
        WidgetTimelineEntry(
            dateMs: dateMs,
            validUntilMs: validUntilMs,
            phase: phase,
            labelKey: "widgetWorking",
            countdownKind: phase == .working ? .workRemaining : .shiftStarts,
            countdownValueAtDateMs: validUntilMs - dateMs,
            countdownTargetAtMs: validUntilMs,
            remainingEffectiveMsAtDateMs: validUntilMs - dateMs,
            progressAtDate: 10,
            nextBoundaryAtMs: validUntilMs
        )
    }

    for day in 0..<Int64(days) {
        let midnight = day0 + day * dayMs
        let start = midnight + 9 * hour
        entries.append(entry(midnight, start, .before))
        entries.append(entry(start, start + 3 * hour, .working))
        entries.append(entry(start + 3 * hour, start + 4 * hour, .break))
        entries.append(entry(start + 4 * hour, start + 9 * hour, .working))
        entries.append(entry(start + 9 * hour, midnight + dayMs, .done))
    }

    return WidgetSnapshot(
        schemaVersion: widgetSnapshotSchemaVersion,
        generatedAtMs: day0,
        expiresAtMs: day0 + Int64(days) * dayMs,
        locale: "en",
        shift: nil,
        entries: entries
    )
}

/// The regression this guards is not a wrong number on screen — it is a Lock
/// Screen complication stuck on its redacted placeholder. WidgetKit renders
/// every entry of a timeline up front inside the extension's memory budget, so
/// the entry count is the cost of a reload. A five-minute step across the same
/// 36-hour window produced around two hundred entries for this schedule, which
/// is what a widget extension is killed for.
@Test("One reload stays small enough for WidgetKit to render")
func boundsTimelineSizeForAWorkingDay() {
    let snapshot = recurringSnapshot()
    // 08:00 on the first day: the window covers two full shifts, the worst
    // case for the expansion.
    let nowMs = snapshot.generatedAtMs + 8 * 3_600_000

    let entries = snapshot.presentationEntries(
        startingAtMs: nowMs,
        progressStepMs: OffWorkCountdownTimelineProvider.progressStepMs,
        endingAtMs: nowMs + OffWorkCountdownTimelineProvider.presentationWindowMs
    )

    // The shipped constants produce 70 entries for this schedule. A five-minute
    // step over the same window produced 198, and ten minutes 102, so this
    // bound fails on a regression toward density while leaving room for an
    // extra boundary or two.
    #expect(entries.count <= 80)
    // Shrinking the window is the tempting wrong way to cut the count. It must
    // still reach well past the 12 hours WidgetKit is asked to rebuild in,
    // because WidgetKit may defer that reload and the slack is what keeps a
    // deferred reload from stranding the complication on its last entry.
    #expect(entries.last.map { $0.dateMs > nowMs + 24 * 3_600_000 } == true)
}

@Test("A missing snapshot still answers WidgetKit's preview request")
func snapshotEntrySurvivesAMissingFile() {
    let provider = OffWorkCountdownTimelineProvider(appGroupIdentifier: nil)
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    let entry = provider.makeSnapshotEntry(now: now)

    #expect(entry.snapshotEntry == nil)
    #expect(entry.date == now)
    #expect(entry.upcoming.isEmpty)
}
