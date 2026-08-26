import Foundation
import Testing
@testable import App

@MainActor
@Test("A fresh install uses the documented iOS defaults")
func freshInstallDefaults() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = OffWorkStore(defaults: defaults)
    #expect(store.onboardingComplete == false)
    #expect(store.startMinutes == 9 * 60)
    #expect(store.endMinutes == 17 * 60)
    #expect(store.lunchEnabled == false)
    #expect(store.lunchDurationMinutes == 60)
    #expect(store.notificationMode == .off)
    #expect(store.salaryEnabled == false)
}

@MainActor
@Test("Persisted settings survive store recreation")
func persistedSettingsSurviveRelaunch() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let first = OffWorkStore(defaults: defaults)
    first.onboardingComplete = true
    first.startMinutes = 7 * 60 + 30
    first.endMinutes = 16 * 60 + 45
    first.lunchEnabled = true
    first.lunchDurationMinutes = 45
    first.notificationMode = .milestones

    let reloaded = OffWorkStore(defaults: defaults)
    #expect(reloaded.onboardingComplete)
    #expect(reloaded.startMinutes == 7 * 60 + 30)
    #expect(reloaded.endMinutes == 16 * 60 + 45)
    #expect(reloaded.lunchEnabled)
    #expect(reloaded.lunchDurationMinutes == 45)
    #expect(reloaded.notificationMode == .milestones)
}

@MainActor
@Test("A completed countdown resets after its end day")
func completedCountdownResetsAcrossDayBoundary() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let calendar = Calendar.current
    let start = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 8,
        day: 24,
        hour: 10
    )))
    let sameDayEvening = try #require(calendar.date(bySettingHour: 22, minute: 0, second: 0, of: start))
    let followingDay = try #require(calendar.date(byAdding: .day, value: 1, to: start))

    let first = OffWorkStore(defaults: defaults)
    first.scheduleMode = .off
    first.startMinutes = 9 * 60
    first.endMinutes = 17 * 60
    first.startCountdown(at: start)

    #expect(first.reconcileCountdownSession(at: sameDayEvening) == false)
    #expect(first.countdownStarted)

    let relaunched = OffWorkStore(defaults: defaults)
    #expect(relaunched.reconcileCountdownSession(at: followingDay))
    #expect(relaunched.countdownStarted == false)
}

@MainActor
@Test("Completing setup arms scheduled countdowns until the user stops them")
func completingSetupArmsScheduledCountdowns() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = OffWorkStore(defaults: defaults)
    store.scheduleMode = .classic
    store.completeOnboarding(enableNotifications: false)

    #expect(store.countdownStarted)

    store.stopCountdown()
    let relaunched = OffWorkStore(defaults: defaults)
    #expect(relaunched.countdownStarted == false)
}

@MainActor
@Test("Existing configured schedules are armed once on upgrade")
func existingSchedulesMigrateToAutomaticCountdowns() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    defaults.set(true, forKey: "ios.native.onboardingComplete")
    defaults.set("classic", forKey: "ios.native.scheduleMode")
    defaults.set(false, forKey: "ios.native.countdownStarted")

    let migrated = OffWorkStore(defaults: defaults)
    #expect(migrated.countdownStarted)

    migrated.stopCountdown()
    let relaunched = OffWorkStore(defaults: defaults)
    #expect(relaunched.countdownStarted == false)
}

@MainActor
@Test("A scheduled countdown stays armed when the next workday begins")
func scheduledCountdownStaysArmedAcrossWorkdays() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let calendar = Calendar.current
    let monday = try #require(calendar.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 10
    )))
    let tuesday = try #require(calendar.date(byAdding: .day, value: 1, to: monday))

    let store = OffWorkStore(defaults: defaults)
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.startCountdown(at: monday)

    #expect(store.reconcileCountdownSession(at: tuesday))
    #expect(store.countdownStarted)
    // Compared with a tolerance: this value crosses the JavaScript bridge as a
    // Double, and an exact match on the way back is a coin toss.
    let tuesdayRemaining = try #require(store.snapshot(at: tuesday)?.remainingMs)
    #expect(abs(tuesdayRemaining - 7 * 60 * 60 * 1_000) < 1)
}

@MainActor
@Test("The upcoming timeline starts with clock-in and always ends with clock-off")
func upcomingTimelineIncludesShiftBoundaries() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let calendar = Calendar.current
    let beforeShift = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 8,
        day: 24,
        hour: 8
    )))

    let store = OffWorkStore(defaults: defaults)
    store.scheduleMode = .off
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.lunchEnabled = true
    store.lunchStartMinutes = 12 * 60
    store.lunchDurationMinutes = 60

    let snapshot = try #require(store.snapshot(at: beforeShift))
    let events = store.upcomingTimelineEvents(for: snapshot, at: beforeShift)

    #expect(events.map(\.kind) == [.shiftStart, .lunchStart, .lunchEnd, .shiftEnd])
    #expect(events.last?.date == snapshot.endDate)
}

/// One row of `relativeDurationFormatting`. A named struct rather than a tuple
/// literal: a heterogeneous tuple array this size defeated the type checker.
struct DurationCase: Sendable {
    let milliseconds: Double
    let language: String
    let expected: String
}

@Test("Whole hours drop the trailing zero-minute unit", arguments: [
    DurationCase(milliseconds: 43_200_000, language: "en", expected: "12 h"),
    DurationCase(milliseconds: 5_400_000, language: "en", expected: "1 h 30 m"),
    DurationCase(milliseconds: 2_700_000, language: "en", expected: "45 m"),
    DurationCase(milliseconds: 0, language: "en", expected: "0 m"),
    DurationCase(milliseconds: 43_200_000, language: "zh-CN", expected: "12小时"),
    DurationCase(milliseconds: 5_400_000, language: "zh-CN", expected: "1小时30分钟"),
    DurationCase(milliseconds: 0, language: "zh-CN", expected: "0分钟"),
])
func relativeDurationFormatting(_ testCase: DurationCase) {
    let formatted = RelativeDurationFormatter.string(
        milliseconds: testCase.milliseconds,
        languageCode: testCase.language
    )
    #expect(formatted == testCase.expected)
}

@MainActor
@Test("An overnight shift keeps its after-midnight events in the timeline")
func overnightTimelineKeepsEventsAfterMidnight() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    // 23:30, half an hour into a 23:00 → 07:00 shift. Lunch at 02:00 and the
    // shift's end are both on the following calendar day.
    let duringShift = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 23, minute: 30
    )))

    let store = OffWorkStore(defaults: defaults)
    store.scheduleMode = .off
    store.startMinutes = 23 * 60
    store.endMinutes = 7 * 60
    store.lunchEnabled = true
    store.lunchStartMinutes = 2 * 60
    store.lunchDurationMinutes = 30

    let snapshot = try #require(store.snapshot(at: duringShift))
    let events = store.upcomingTimelineEvents(for: snapshot, at: duringShift)

    #expect(events.map(\.kind) == [.lunchStart, .lunchEnd, .shiftEnd])
}

@MainActor
@Test("The widget timeline has an entry covering the lunch break")
func widgetTimelineCoversLunchBreak() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    // 12:45, inside a 12:30-13:30 break in an 09:00-18:00 shift.
    let duringLunch = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 12, minute: 45
    )))

    let store = OffWorkStore(defaults: defaults)
    store.scheduleMode = .off
    store.startMinutes = 9 * 60
    store.endMinutes = 18 * 60
    store.lunchEnabled = true
    store.lunchStartMinutes = 12 * 60 + 30
    store.lunchDurationMinutes = 60
    store.countdownStarted = true

    let nowMs = Int64(duringLunch.timeIntervalSince1970 * 1_000)
    let snapshot = WidgetSnapshotPublisher.shared.makeSnapshot(
        store: store,
        shift: store.snapshot(at: duringLunch),
        active: true,
        nowMs: nowMs
    )

    // The entry WidgetKit would pick: the most recent one already due.
    let current = try #require(snapshot.entries.last { $0.dateMs <= nowMs })
    #expect(current.phase == .break)
    #expect(current.labelKey == "lunchInProgress")
    #expect(nowMs < current.validUntilMs)
}

@MainActor
@Test("Overtime carries the widget timeline past the planned end")
func widgetTimelineFollowsOvertime() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    // 17:30 — half an hour past a 09:00-17:00 shift extended to 18:00.
    let duringOvertime = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 17, minute: 30
    )))
    let overtimeEnd = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 18, minute: 0
    )))

    let store = OffWorkStore(defaults: defaults)
    store.scheduleMode = .off
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.lunchEnabled = false
    store.applyOvertime(date: overtimeEnd)

    let nowMs = Int64(duringOvertime.timeIntervalSince1970 * 1_000)
    let snapshot = WidgetSnapshotPublisher.shared.makeSnapshot(
        store: store,
        shift: store.snapshot(at: duringOvertime),
        active: true,
        nowMs: nowMs
    )

    let current = try #require(snapshot.entries.last { $0.dateMs <= nowMs })
    #expect(current.phase == .working)

    // Counting to the extended end, not to 17:00. A tolerance rather than an
    // equality: the duration crosses a Double on its way through the rules
    // engine, so sub-millisecond drift is expected and meaningless.
    let target = try #require(current.countdownTargetAtMs)
    let expected = Int64(overtimeEnd.timeIntervalSince1970 * 1_000)
    #expect(abs(target - expected) < 1_000)
}

@MainActor
@Test("The widget starts future scheduled shifts without reopening the app")
func widgetTimelineStartsFutureShiftAutomatically() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let mondayMorning = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 8
    )))
    let tuesdayMorning = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 25, hour: 10
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.countdownStarted = true

    let publishedAtMs = Int64(mondayMorning.timeIntervalSince1970 * 1_000)
    let snapshot = WidgetSnapshotPublisher.shared.makeSnapshot(
        store: store,
        shift: store.snapshot(at: mondayMorning),
        active: true,
        nowMs: publishedAtMs
    )
    let futureAtMs = Int64(tuesdayMorning.timeIntervalSince1970 * 1_000)
    let future = try #require(snapshot.entry(atMs: futureAtMs))

    #expect(future.phase == .working)
    #expect(future.labelKey == "widgetWorking")
}

@MainActor
@Test("Consecutive overnight shifts do not keep the previous done state")
func widgetTimelineAdvancesBetweenOvernightShifts() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let mondayMorning = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 8
    )))
    let tuesdayNight = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 25, hour: 23
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 23 * 60
    store.endMinutes = 7 * 60
    store.countdownStarted = true

    let nowMs = Int64(mondayMorning.timeIntervalSince1970 * 1_000)
    let snapshot = WidgetSnapshotPublisher.shared.makeSnapshot(
        store: store,
        shift: store.snapshot(at: mondayMorning),
        active: true,
        nowMs: nowMs
    )
    let nextNight = try #require(snapshot.entry(
        atMs: Int64(tuesdayNight.timeIntervalSince1970 * 1_000)
    ))

    #expect(nextNight.phase == .working)
}

@MainActor
@Test("Rest copy ends when the next workday begins")
func widgetRestCopyMatchesRestDays() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let fridayEvening = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 28, hour: 18
    )))
    let saturdayNoon = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 29, hour: 12
    )))
    let mondayMorning = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 31, hour: 8
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.countdownStarted = true

    let nowMs = Int64(fridayEvening.timeIntervalSince1970 * 1_000)
    let snapshot = WidgetSnapshotPublisher.shared.makeSnapshot(
        store: store,
        shift: store.snapshot(at: fridayEvening),
        active: true,
        nowMs: nowMs
    )
    let restEntry = try #require(snapshot.entry(
        atMs: Int64(saturdayNoon.timeIntervalSince1970 * 1_000)
    ))
    let workdayEntry = try #require(snapshot.entry(
        atMs: Int64(mondayMorning.timeIntervalSince1970 * 1_000)
    ))

    #expect(restEntry.labelKey == "widgetRestDay")
    #expect(workdayEntry.labelKey == "nextShiftLabelShort")
}

/// Builds a store whose only timed preview rows are the shift boundaries and
/// the break, so an order assertion reads as the order and nothing else.
@MainActor
private func previewStore(_ defaults: UserDefaults) -> OffWorkStore {
    let store = OffWorkStore(defaults: defaults)
    // Not `.off`: that mode reports no `nextShiftStartAtMs` at all, because
    // without a schedule the rules have no way to say which day comes next.
    // Rows that have already happened are then dropped rather than moved, for
    // the break exactly as for the start time.
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.lunchEnabled = true
    store.lunchStartMinutes = 12 * 60
    store.lunchDurationMinutes = 60
    store.microBreakEnabled = false
    store.liveActivityEnabled = false
    store.notificationMode = .off
    return store
}

@MainActor
@Test("A break that has been and gone queues behind the next clock-in")
func shiftPreviewMovesFinishedBreakToTheNextShift() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let calendar = Calendar.current
    let afterLunch = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 8,
        day: 24,
        hour: 15
    )))

    let store = previewStore(defaults)
    let snapshot = try #require(store.snapshot(at: afterLunch))
    let preview = store.shiftPreview(for: snapshot, at: afterLunch)

    // Clock-off is the only thing left today; everything else has rolled onto
    // tomorrow and lines up behind the next clock-in rather than heading a list
    // of things that are supposedly still coming.
    // One break row, not two: this is the settings page, where the break is a
    // window rather than two events being waited for.
    #expect(preview.upcoming.map(\.kind) == [.shiftEnd, .shiftStart, .lunchStart])

    // Monday 24 August 2026, so the next shift is Tuesday morning.
    let nextStart = try #require(snapshot.nextShiftStartDate)
    #expect(preview.upcoming[1].date == nextStart)
    #expect(preview.upcoming[2].date == nextStart.addingTimeInterval(3 * 3_600))
}

@MainActor
@Test("Mid-break, only the half that has passed rolls to the next shift")
func shiftPreviewRollsBreakBoundariesIndependently() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let calendar = Calendar.current
    let duringLunch = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 8,
        day: 24,
        hour: 12,
        minute: 30
    )))

    let store = previewStore(defaults)
    let snapshot = try #require(store.snapshot(at: duringLunch))
    let preview = store.shiftPreview(for: snapshot, at: duringLunch)

    // Merged into one window row, the break is keyed on when it opens — and
    // that has passed — so the whole window moves to the next shift. The
    // running page still splits the two boundaries, which is where a user
    // actually waits for "back at 13:00"; this page is for setting the window,
    // not for living through it.
    #expect(preview.upcoming.map(\.kind) == [.shiftEnd, .shiftStart, .lunchStart])
    let nextDayStart = try #require(snapshot.nextShiftStartDate)
    #expect(preview.upcoming[2].date == nextDayStart.addingTimeInterval(3 * 3_600))
}

@MainActor
@Test("After clocking off, the whole preview reads as the next shift, in order")
func shiftPreviewRollsEveryPastRowToTheNextShift() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let calendar = Calendar.current
    let afterClockOff = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 8,
        day: 24,
        hour: 18
    )))

    let store = previewStore(defaults)
    store.liveActivityEnabled = true
    store.liveActivityLeadMinutes = 30

    let snapshot = try #require(store.snapshot(at: afterClockOff))
    let preview = store.shiftPreview(for: snapshot, at: afterClockOff)

    // Everything is behind us, so everything belongs to tomorrow and the list
    // reads in one direction: in, break, warning, out. It used to open with the
    // Live Activity and clock-off, both hours gone, and close with tomorrow's
    // clock-in — backwards at its own finish line.
    #expect(preview.upcoming.map(\.kind) == [
        .shiftStart, .lunchStart, .liveActivity, .shiftEnd,
    ])

    let nextStart = try #require(snapshot.nextShiftStartDate)
    let nextEnd = try #require(snapshot.nextShiftEndDate)
    #expect(preview.upcoming.first?.date == nextStart)
    #expect(preview.upcoming.last?.date == nextEnd)
    #expect(preview.upcoming[2].date == nextEnd.addingTimeInterval(-30 * 60))

    // "Today's shift" would be a lie on a row that is now tomorrow's.
    #expect(preview.upcoming.last?.detail == nil)
}

/// One row of `shiftPreviewReminderDisabledState`.
struct ReminderSwitchCase: Sendable {
    let liveActivity: Bool
    let mode: OffWorkNotificationMode
    let showsDisabled: Bool
}

@MainActor
@Test("The off-work reminder reads as disabled only when both mechanisms are off", arguments: [
    ReminderSwitchCase(liveActivity: true, mode: .milestones, showsDisabled: false),
    // The case that contradicted itself: a timed Live Activity row sat directly
    // above a row calling the same feature disabled.
    ReminderSwitchCase(liveActivity: true, mode: .off, showsDisabled: false),
    ReminderSwitchCase(liveActivity: false, mode: .simple, showsDisabled: false),
    ReminderSwitchCase(liveActivity: false, mode: .off, showsDisabled: true),
])
func shiftPreviewReminderDisabledState(_ testCase: ReminderSwitchCase) throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let calendar = Calendar.current
    let beforeShift = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 8,
        day: 24,
        hour: 8
    )))

    let store = previewStore(defaults)
    store.liveActivityEnabled = testCase.liveActivity
    store.notificationMode = testCase.mode

    let snapshot = try #require(store.snapshot(at: beforeShift))
    let preview = store.shiftPreview(for: snapshot, at: beforeShift)

    let disabled = preview.disabled.contains { $0.id == "off-work-reminder-off" }
    #expect(disabled == testCase.showsDisabled)

    // And the timed row tracks the Live Activity switch on its own, so the two
    // rows can never describe the same feature differently.
    let timed = preview.upcoming.contains { $0.kind == .liveActivity }
    #expect(timed == testCase.liveActivity)
}

/// The scenario the automatic-countdown work is supposed to remove, written as
/// the user described it: configure a schedule, use it, press the button the
/// running screen puts in front of you, and then simply do not open the app.
@MainActor
@Test("Stopping once does not silence every scheduled shift after it")
func widgetKeepsCountingAfterAnExplicitStop() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let mondayAtWork = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 11
    )))
    let tuesdayAtWork = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 25, hour: 11
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.startCountdown(at: mondayAtWork)
    store.clockOffEarly(at: mondayAtWork)

    let snapshot = WidgetSnapshotPublisher.shared.makeSnapshot(
        store: store,
        shift: store.snapshot(at: mondayAtWork),
        active: store.countdownStarted,
        nowMs: Int64(mondayAtWork.timeIntervalSince1970 * 1_000)
    )

    // The next day has to carry itself without the app being opened. This is
    // the whole point: set it up once, then never think about it.
    let tomorrow = try #require(snapshot.entry(atMs: Int64(tuesdayAtWork.timeIntervalSince1970 * 1_000)))
    #expect(tomorrow.phase == .working)
    #expect(tomorrow.labelKey == "widgetWorking")
}

/// The case that made "clock off early" the right name for the button: editing
/// the schedule afterwards is a statement about the plan, and must not reach
/// back and un-end a shift the user said they had finished.
@MainActor
@Test("Changing the hours later does not resurrect a shift already clocked off")
func editingTheScheduleDoesNotUndoAnEarlyClockOff() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let mondayAtWork = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 11
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.startCountdown(at: mondayAtWork)
    store.clockOffEarly(at: mondayAtWork)

    // Same shift, hours nudged. Still finished.
    store.endMinutes = 18 * 60
    let shift = try #require(store.snapshot(at: mondayAtWork))
    #expect(store.isEndedEarly(shift))

    // A shift that begins after the moment they stopped is a different shift,
    // and gets counted — no special case, it simply falls outside the window.
    store.startMinutes = 20 * 60
    store.endMinutes = 23 * 60
    let nightShift = try #require(store.snapshot(at: mondayAtWork))
    #expect(!store.isEndedEarly(nightShift))

    // And undoing is its own deliberate action.
    store.undoEarlyClockOff()
    #expect(store.earlyOffAtMs == nil)
}

private func isolatedDefaults() throws -> (UserDefaults, String) {
    let suite = "OffWorkStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    return (defaults, suite)
}
