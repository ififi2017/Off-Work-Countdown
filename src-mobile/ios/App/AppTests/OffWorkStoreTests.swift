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
@Test("Completing setup arms scheduled countdowns and stop cannot disarm them")
func completingSetupArmsScheduledCountdowns() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = OffWorkStore(defaults: defaults)
    store.scheduleMode = .classic
    store.completeOnboarding(enableNotifications: false)

    #expect(store.countdownStarted)

    store.stopCountdown()
    let relaunched = OffWorkStore(defaults: defaults)
    #expect(relaunched.countdownStarted)
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
    #expect(relaunched.countdownStarted)
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
    store.onboardingComplete = true
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

@MainActor
@Test("A completed shift stays on settlement; there is no dismiss back to setup")
func completedShiftStaysOnSettlement() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let afterWork = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 18
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.startCountdown(at: afterWork)

    let shift = try #require(store.snapshot(at: afterWork))
    #expect(shift.remainingMs <= 0)
    #expect(store.visualPhase(snapshot: shift, at: afterWork) == .completed)

    store.dismissCompletedShift(at: afterWork)
    #expect(store.countdownStarted)
    #expect(store.visualPhase(snapshot: store.snapshot(at: afterWork), at: afterWork) == .completed)
}

@MainActor
@Test("Next-shift-only hour edits leave today's end unchanged")
func nextShiftOnlyHourEditsLeaveTodayUnchanged() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let afterWork = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 16
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.startCountdown(at: afterWork)

    store.applyScheduleChange(
        ScheduleFieldChange(endMinutes: 18 * 60),
        decision: .nextShiftOnly,
        at: afterWork
    )
    #expect(store.endMinutes == 18 * 60)
    #expect(store.effectiveEndMinutes(at: afterWork) == 17 * 60)
    let today = try #require(store.snapshot(at: afterWork))
    #expect(store.visualPhase(snapshot: today, at: afterWork) == .running)

    let todayEnd = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 17
    )))
    let tuesdayEnd = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 25, hour: 18
    )))
    #expect(abs(today.endAtMs - todayEnd.timeIntervalSince1970 * 1_000) < 1)
    let nextEnd = try #require(today.nextShiftEndAtMs)
    #expect(abs(nextEnd - tuesdayEnd.timeIntervalSince1970 * 1_000) < 1)

    let tuesdayAtWork = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 25, hour: 10
    )))
    let widget = WidgetSnapshotPublisher.shared.makeSnapshot(
        store: store,
        shift: today,
        active: true,
        nowMs: Int64(afterWork.timeIntervalSince1970 * 1_000)
    )
    let tuesdayEntry = try #require(widget.entry(
        atMs: Int64(tuesdayAtWork.timeIntervalSince1970 * 1_000)
    ))
    #expect(tuesdayEntry.phase == .working)
    let target = try #require(tuesdayEntry.countdownTargetAtMs)
    #expect(abs(target - Int64(tuesdayEnd.timeIntervalSince1970 * 1_000)) < 1_000)
}

@MainActor
@Test("Enabled lunch stays on in the preview even when it does not fit the hours")
func shiftPreviewKeepsEnabledLunchWhenItDoesNotFit() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let morning = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 10
    )))

    let store = previewStore(defaults)
    store.endMinutes = 11 * 60

    let snapshot = try #require(store.snapshot(at: morning))
    let preview = store.shiftPreview(for: snapshot, at: morning)
    #expect(!preview.disabled.contains { $0.id == "lunch-off" })
    #expect(preview.upcoming.contains { $0.kind == .lunchStart })
}

@MainActor
@Test("Enabled health reminders stay on after the shift has ended")
func shiftPreviewKeepsEnabledHealthAfterClockOff() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let afterClockOff = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 18
    )))

    let store = previewStore(defaults)
    store.microBreakEnabled = true

    let snapshot = try #require(store.snapshot(at: afterClockOff))
    let preview = store.shiftPreview(for: snapshot, at: afterClockOff)
    #expect(!preview.disabled.contains { $0.kind == .health })
    #expect(preview.upcoming.contains { $0.kind == .health })
}

@MainActor
@Test("A shift too short for a micro-break still lists health without a fake time")
func healthPreviewHasNoDateWhenRulesScheduleNone() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let beforeShift = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 8
    )))

    let store = previewStore(defaults)
    store.endMinutes = 10 * 60
    store.lunchEnabled = false
    store.microBreakEnabled = true
    store.microBreakIntervalMinutes = 60

    let snapshot = try #require(store.snapshot(at: beforeShift))
    let reminders = try CountdownRules.shared.reminders(
        input: store.rulesInput(at: beforeShift),
        reminderInputs: store.reminderInputs()
    )
    #expect(!reminders.contains { $0.kind == "microBreak" })

    let preview = store.shiftPreview(for: snapshot, at: beforeShift)
    let health = try #require(preview.upcoming.first { $0.kind == .health })
    #expect(health.date == nil)
}

@MainActor
@Test("Health preview times match the earliest shared micro-break reminder")
func healthPreviewDateMatchesSharedReminders() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let beforeShift = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 8
    )))

    let store = previewStore(defaults)
    store.microBreakEnabled = true
    store.microBreakIntervalMinutes = 60

    let snapshot = try #require(store.snapshot(at: beforeShift))
    let reminders = try CountdownRules.shared.reminders(
        input: store.rulesInput(at: beforeShift),
        reminderInputs: store.reminderInputs()
    )
    let earliest = try #require(reminders.filter { $0.kind == "microBreak" }.min(by: { $0.atMs < $1.atMs }))
    let preview = store.shiftPreview(for: snapshot, at: beforeShift)
    let health = try #require(preview.upcoming.first { $0.kind == .health })
    #expect(health.date == Date(timeIntervalSince1970: earliest.atMs / 1_000))
}

@MainActor
@Test("Health preview does not invent start-plus-interval across a lunch gap")
func healthPreviewDoesNotUseShiftStartPlusIntervalAcrossLunch() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let afterLunch = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 13, minute: 30
    )))

    let store = previewStore(defaults)
    store.microBreakEnabled = true
    store.microBreakIntervalMinutes = 60

    let snapshot = try #require(store.snapshot(at: afterLunch))
    let reminders = try CountdownRules.shared.reminders(
        input: store.rulesInput(at: afterLunch),
        reminderInputs: store.reminderInputs()
    )
    let earliestRemaining = try #require(
        reminders
            .filter { $0.kind == "microBreak" && $0.atMs > afterLunch.timeIntervalSince1970 * 1_000 }
            .min(by: { $0.atMs < $1.atMs })
    )
    let preview = store.shiftPreview(for: snapshot, at: afterLunch)
    let health = try #require(preview.upcoming.first { $0.kind == .health })
    #expect(health.date == Date(timeIntervalSince1970: earliestRemaining.atMs / 1_000))
    #expect(health.date != snapshot.startDate.addingTimeInterval(60 * 60))
}

@MainActor
@Test("The widget shows done, not a rest day, after an early clock-off")
func widgetShowsDoneForTheRestOfAWorkdayAfterEarlyClockOff() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let mondayAtWork = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 11
    )))
    let mondayAfternoon = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 15
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
    let stillToday = try #require(snapshot.entry(atMs: Int64(mondayAfternoon.timeIntervalSince1970 * 1_000)))
    #expect(stillToday.phase == .done)
    #expect(stillToday.labelKey == "offWorkToday")

    let tomorrow = try #require(snapshot.entry(atMs: Int64(tuesdayAtWork.timeIntervalSince1970 * 1_000)))
    #expect(tomorrow.phase == .working)
}

@MainActor
@Test("Early clock-off drops reminders that still belong to the ended shift")
func earlyClockOffSuppressesRemainingRemindersForThatShift() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let mondayAtWork = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 11
    )))
    let clockOff = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 17
    )))
    let nextStart = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 25, hour: 9
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.startCountdown(at: mondayAtWork)
    store.clockOffEarly(at: mondayAtWork)

    let shift = try #require(store.snapshot(at: mondayAtWork))
    let today = NativeReminder(
        id: "today-end",
        kind: "shiftEnd",
        atMs: clockOff.timeIntervalSince1970 * 1_000,
        expiresAtMs: nil,
        maxTickGapMs: nil,
        collapseGroup: nil,
        title: "end",
        body: "end"
    )
    let tomorrow = NativeReminder(
        id: "tomorrow-start",
        kind: "shiftStart",
        atMs: nextStart.timeIntervalSince1970 * 1_000,
        expiresAtMs: nil,
        maxTickGapMs: nil,
        collapseGroup: nil,
        title: "start",
        body: "start"
    )
    #expect(!store.shouldDeliverReminder(today, for: shift))
    #expect(store.shouldDeliverReminder(tomorrow, for: shift))
}

@MainActor
@Test("Before clock-in the shared remaining time counts to the start")
func heroRemainingCountsToClockInBeforeStart() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let beforeShift = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 8
    )))

    let store = OffWorkStore(defaults: defaults)
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60

    let shift = try #require(store.snapshot(at: beforeShift))
    #expect(shift.isBeforeStart(at: beforeShift))
    let remaining = shift.heroRemainingMs(at: beforeShift)
    #expect(abs(remaining - 60 * 60 * 1_000) < 1)
}

@MainActor
@Test("Clocking off early lands on completed, not setup")
func clockingOffEarlyLandsOnCompleted() throws {
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

    let shift = try #require(store.snapshot(at: mondayAtWork))
    #expect(store.isEndedEarly(shift))
    #expect(store.isShiftComplete(shift))
    #expect(store.visualPhase(snapshot: shift, at: mondayAtWork) == .completed)
    #expect(store.countdownStarted)

    store.dismissCompletedShift(at: mondayAtWork)
    #expect(store.countdownStarted)
    #expect(store.visualPhase(snapshot: store.snapshot(at: mondayAtWork), at: mondayAtWork) == .completed)

    store.undoEarlyClockOff()
    #expect(store.visualPhase(snapshot: store.snapshot(at: mondayAtWork), at: mondayAtWork) == .running)
}

@MainActor
@Test("Overtime after an early clock-off resumes the shift")
func applyingOvertimeClearsAnEarlyClockOff() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let mondayAtWork = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 11
    )))
    let overtimeEnd = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 20
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.startCountdown(at: mondayAtWork)
    store.clockOffEarly(at: mondayAtWork)
    store.applyOvertime(date: overtimeEnd)

    #expect(store.earlyOffAtMs == nil)
    let shift = try #require(store.snapshot(at: mondayAtWork))
    #expect(!store.isEndedEarly(shift))
    #expect(store.visualPhase(snapshot: shift) == .running)
}

@MainActor
@Test("Changing today also clears an early clock-off")
func applyingSettingsDoesNotUndoAnEarlyClockOff() throws {
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
    #expect(store.visualPhase(snapshot: store.snapshot(at: mondayAtWork), at: mondayAtWork) == .completed)

    store.applyScheduleChange(
        ScheduleFieldChange(endMinutes: 18 * 60),
        decision: .applyToToday,
        at: mondayAtWork
    )
    #expect(store.endMinutes == 18 * 60)
    #expect(store.earlyOffAtMs == nil)
    #expect(store.visualPhase(snapshot: store.snapshot(at: mondayAtWork), at: mondayAtWork) == .running)
}

@MainActor
@Test("The next workday is not covered by yesterday's early clock-off")
func nextWorkdayIsNotCoveredByYesterdaysEarlyClockOff() throws {
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

    let monday = try #require(store.snapshot(at: mondayAtWork))
    let frozenMonday = store.clockOffSnapshot(for: monday)
    let tuesday = try #require(store.snapshot(at: tuesdayAtWork))
    #expect(!store.isEndedEarly(tuesday))
    #expect(store.visualPhase(snapshot: tuesday) == .running)
    #expect(frozenMonday.startAtMs != tuesday.startAtMs)
    #expect(store.clockOffSnapshot(for: tuesday).startAtMs == tuesday.startAtMs)
}

@MainActor
@Test("An early clock-off snapshot stays frozen after later settings edits")
func clockOffSnapshotDoesNotRebuildFromLaterSettings() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let mondayAfternoon = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 14
    )))
    let overtimeEnd = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 20
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.lunchEnabled = true
    store.lunchStartMinutes = 12 * 60
    store.lunchDurationMinutes = 60
    store.salaryEnabled = true
    store.salaryType = .monthly
    store.salaryAmount = "22000"
    store.monthlyWorkingDays = 22
    store.startCountdown(at: mondayAfternoon)
    store.clockOffEarly(at: mondayAfternoon)

    let original = try #require(store.snapshot(at: mondayAfternoon))
    let frozen = store.clockOffSnapshot(for: original)
    #expect(abs(frozen.elapsedMs - 4 * 3_600_000) < 1)
    let originalSalary = try #require(frozen.dailySalary)
    let originalPayRatio = frozen.payRatio
    let originalProgress = frozen.progress
    let originalSegments = frozen.segments
    #expect(store.takenLunchWindow(for: frozen, at: mondayAfternoon) != nil)

    store.lunchEnabled = false
    let afterLunchOff = try #require(store.snapshot(at: mondayAfternoon))
    let frozenAfterLunchOff = store.clockOffSnapshot(for: afterLunchOff)
    #expect(frozenAfterLunchOff.segments == originalSegments)
    #expect(abs(frozenAfterLunchOff.elapsedMs - frozen.elapsedMs) < 0.001)
    #expect(abs(frozenAfterLunchOff.progress - originalProgress) < 0.001)
    #expect(abs(frozenAfterLunchOff.payRatio - originalPayRatio) < 0.001)
    #expect(afterLunchOff.elapsedMs != frozen.elapsedMs)
    #expect(store.takenLunchWindow(for: frozenAfterLunchOff, at: mondayAfternoon) != nil)

    store.lunchEnabled = true
    store.lunchStartMinutes = 15 * 60
    store.lunchDurationMinutes = 30
    let afterLunchMoved = try #require(store.snapshot(at: mondayAfternoon))
    let frozenAfterLunchMoved = store.clockOffSnapshot(for: afterLunchMoved)
    #expect(frozenAfterLunchMoved.segments == originalSegments)
    #expect(abs(frozenAfterLunchMoved.elapsedMs - frozen.elapsedMs) < 0.001)

    store.salaryAmount = "44000"
    let afterSalary = try #require(store.snapshot(at: mondayAfternoon))
    let frozenAfterSalary = store.clockOffSnapshot(for: afterSalary)
    #expect(frozenAfterSalary.dailySalary == originalSalary)
    #expect(afterSalary.dailySalary != originalSalary)

    let reloaded = OffWorkStore(defaults: defaults)
    let reloadedShift = try #require(reloaded.snapshot(at: mondayAfternoon))
    let reloadedFrozen = reloaded.clockOffSnapshot(for: reloadedShift)
    #expect(reloadedFrozen.segments == originalSegments)
    #expect(abs(reloadedFrozen.elapsedMs - frozen.elapsedMs) < 0.001)
    #expect(abs(reloadedFrozen.progress - originalProgress) < 0.001)
    #expect(abs(reloadedFrozen.payRatio - originalPayRatio) < 0.001)
    #expect(reloadedFrozen.dailySalary == originalSalary)

    store.undoEarlyClockOff()
    #expect(store.earlyOffAtMs == nil)
    let afterUndo = try #require(store.snapshot(at: mondayAfternoon))
    #expect(store.clockOffSnapshot(for: afterUndo).elapsedMs == afterUndo.elapsedMs)

    store.clockOffEarly(at: mondayAfternoon)
    store.applyOvertime(date: overtimeEnd)
    #expect(store.earlyOffAtMs == nil)
    let afterOvertime = try #require(store.snapshot(at: mondayAfternoon))
    #expect(!store.isEndedEarly(afterOvertime))
    #expect(store.clockOffSnapshot(for: afterOvertime).elapsedMs == afterOvertime.elapsedMs)
    #expect(store.visualPhase(snapshot: afterOvertime) == .running)
}

@MainActor
@Test("Clocking off during overtime keeps the overtime record")
func clockingOffDuringOvertimeKeepsTheExtendedShift() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let mondayMorning = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 11
    )))
    let duringOvertime = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 18
    )))
    let overtimeEnd = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 20
    )))
    let stillOvertime = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 18, minute: 30
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.startCountdown(at: mondayMorning)
    store.applyOvertime(date: overtimeEnd)
    store.clockOffEarly(at: duringOvertime)

    #expect(store.overtimeEndAtMs != nil)
    let shift = try #require(store.snapshot(at: duringOvertime))
    #expect(store.isEndedEarly(shift))
    #expect(store.visualPhase(snapshot: shift) == .completed)
    let frozen = store.clockOffSnapshot(for: shift)
    #expect(frozen.elapsedMs > frozen.plannedDurationMs)
    #expect(frozen.elapsedMs < frozen.durationMs)

    let widget = WidgetSnapshotPublisher.shared.makeSnapshot(
        store: store,
        shift: store.snapshot(at: duringOvertime),
        active: store.countdownStarted,
        nowMs: Int64(duringOvertime.timeIntervalSince1970 * 1_000)
    )
    let current = try #require(widget.entry(atMs: Int64(stillOvertime.timeIntervalSince1970 * 1_000)))
    #expect(current.phase == .done)
}

@MainActor
@Test("Week summary after an early clock-off stays frozen at that moment")
func weekSummaryDoesNotKeepGrowingAfterAnEarlyClockOff() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let mondayAtWork = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 11
    )))
    let mondayAfternoon = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 15
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.startCountdown(at: mondayAtWork)
    store.clockOffEarly(at: mondayAtWork)

    let laterShift = try #require(store.snapshot(at: mondayAfternoon))
    #expect(store.isEndedEarly(laterShift))
    let frozen = store.clockOffSnapshot(for: laterShift)
    let weekFrozen = try #require(store.periodSummary("week", asOf: mondayAtWork, snapshot: frozen))
    let weekLaterFrozen = try #require(store.periodSummary("week", asOf: mondayAfternoon, snapshot: frozen))
    let weekLive = try #require(store.periodSummary("week", asOf: mondayAfternoon, snapshot: laterShift))

    #expect(abs(weekFrozen.hours - weekLaterFrozen.hours) < 0.0001)
    #expect(weekLive.hours > weekFrozen.hours)
}

@MainActor
@Test("Lunch taken only counts after the break has actually ended")
func takenLunchWindowIgnoresABreakThatNeverFinished() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let beforeLunch = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 11
    )))
    let duringLunch = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 12, minute: 30
    )))
    let afterLunch = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 14
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.lunchEnabled = true
    store.lunchStartMinutes = 12 * 60
    store.lunchDurationMinutes = 60
    store.startCountdown(at: beforeLunch)

    store.clockOffEarly(at: beforeLunch)
    let morning = try #require(store.snapshot(at: beforeLunch))
    #expect(store.takenLunchWindow(for: store.clockOffSnapshot(for: morning), at: beforeLunch) == nil)

    store.undoEarlyClockOff()
    store.clockOffEarly(at: duringLunch)
    let midday = try #require(store.snapshot(at: duringLunch))
    #expect(store.takenLunchWindow(for: store.clockOffSnapshot(for: midday), at: duringLunch) == nil)

    store.undoEarlyClockOff()
    store.clockOffEarly(at: afterLunch)
    let afternoon = try #require(store.snapshot(at: afterLunch))
    let taken = try #require(store.takenLunchWindow(for: store.clockOffSnapshot(for: afternoon), at: afterLunch))
    #expect(Calendar.current.component(.hour, from: taken.start) == 12)
    #expect(Calendar.current.component(.hour, from: taken.end) == 13)
}

@MainActor
@Test("Draft overnight hours decide whether today is a rest day")
func setupSnapshotUsesDraftHoursForTheWorkday() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    // Saturday 00:30. The committed 09:00–17:00 day is a rest day; a drafted
    // overnight shift that started Friday night is still Friday's workday.
    let saturdayMorning = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 22, hour: 0, minute: 30
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.setDisplayedStartMinutes(22 * 60)
    store.setDisplayedEndMinutes(6 * 60)

    #expect(store.snapshot(at: saturdayMorning)?.isWorkday == false)
    #expect(store.setupSnapshot(at: saturdayMorning)?.isWorkday == true)
}

@MainActor
@Test("During lunch the shared remaining time counts to the break end")
func heroRemainingCountsToBreakEndDuringLunch() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let duringLunch = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 12, minute: 30
    )))

    let store = OffWorkStore(defaults: defaults)
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.lunchEnabled = true
    store.lunchStartMinutes = 12 * 60
    store.lunchDurationMinutes = 60

    let shift = try #require(store.snapshot(at: duringLunch))
    #expect(shift.isOnBreak)
    let remaining = shift.heroRemainingMs(at: duringLunch)
    #expect(abs(remaining - 30 * 60 * 1_000) < 1)
}

@MainActor
@Test("A rules error stays a banner; stopping does not leave the schedule")
func stoppingACountdownLeavesARulesError() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.countdownStarted = true

    #expect(store.visualPhase(snapshot: nil) == .rulesError)
    store.stopCountdown()
    #expect(store.countdownStarted)
    #expect(store.visualPhase(snapshot: nil) == .rulesError)
}

@MainActor
@Test("The last classic workday cannot be removed")
func lastClassicWorkdayCannotBeRemoved() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1]
    store.toggleWorkday(1)
    #expect(store.workdays == Set([1]))
}

@MainActor
@Test("Early clock-off with no next shift drops the planned end reminder")
func earlyClockOffWithoutNextShiftDropsEndReminder() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let mondayAtWork = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 11
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = []
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.startCountdown(force: true, at: mondayAtWork)
    store.clockOffEarly(at: mondayAtWork)

    let shift = try #require(store.snapshot(at: mondayAtWork))
    #expect(shift.nextShiftStartAtMs == nil)
    let endMilestone = NativeReminder(
        id: "milestone:100",
        kind: "milestone",
        atMs: shift.endAtMs,
        expiresAtMs: nil,
        maxTickGapMs: nil,
        collapseGroup: "milestone",
        title: "end",
        body: "end"
    )
    #expect(!store.shouldDeliverReminder(endMilestone, for: shift))
}

@MainActor
@Test("Starting in manual mode clears a leftover early clock-off")
func manualStartClearsLeftoverEarlyClockOff() throws {
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
    store.dismissCompletedShift(at: mondayAtWork)

    store.scheduleMode = .off
    store.startCountdown(at: mondayAtWork)

    #expect(store.earlyOffAtMs == nil)
    let shift = try #require(store.snapshot(at: mondayAtWork))
    #expect(!store.isEndedEarly(shift))
    #expect(store.visualPhase(snapshot: shift) == .running)
}

@MainActor
@Test("A forced overnight shift is still forced after midnight")
func forcedOvernightShiftSurvivesMidnight() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    // Saturday is a rest day. The user works it anyway, on hours that run past
    // midnight — the one case where "today" and "this shift" disagree.
    let saturdayNight = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 29, hour: 23
    )))
    let sundayMorning = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 30, hour: 3
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 22 * 60
    store.endMinutes = 6 * 60
    store.startCountdown(force: true, at: saturdayNight)

    let beforeMidnight = try #require(store.snapshot(at: saturdayNight))
    #expect(!beforeMidnight.isWorkday)
    #expect(store.isForcedWorkday(beforeMidnight))
    #expect(store.visualPhase(snapshot: beforeMidnight, at: saturdayNight) == .running)

    // Same run, three hours later and one calendar day on. Keying the mark to
    // `.now` turned this into "today is off" with three hours still to work.
    let afterMidnight = try #require(store.snapshot(at: sundayMorning))
    #expect(afterMidnight.startAtMs == beforeMidnight.startAtMs)
    #expect(store.isForcedWorkday(afterMidnight))
    #expect(store.visualPhase(snapshot: afterMidnight, at: sundayMorning) == .running)

    // And the day-change reconcile must not delete a mark that still matches.
    #expect(store.reconcileCountdownSession(at: sundayMorning) == false)
    #expect(store.isForcedWorkday(afterMidnight))
}

@MainActor
@Test("A forced overnight shift stays on settlement until the end calendar day is over")
func forcedOvernightShiftSettlesUntilEndCalendarMidnight() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let saturdayNight = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 29, hour: 23
    )))
    let sundayAfterEnd = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 30, hour: 6, minute: 30
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 22 * 60
    store.endMinutes = 6 * 60
    store.startCountdown(force: true, at: saturdayNight)

    let settled = try #require(store.snapshot(at: sundayAfterEnd))
    #expect(store.isForcedWorkday(settled))
    #expect(settled.remainingMs <= 0)
    #expect(store.visualPhase(snapshot: settled, at: sundayAfterEnd) == .completed)
    _ = store.reconcileCountdownSession(at: sundayAfterEnd)
    #expect(store.isForcedWorkday(try #require(store.snapshot(at: sundayAfterEnd))))
    #expect(store.visualPhase(at: sundayAfterEnd) == .completed)
}

@MainActor
@Test("Next-shift-only weekday edits do not make today look like rest")
func nextShiftOnlyWorkdayEditsKeepTodaysRestDistance() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let mondayAfternoon = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 16
    )))
    let saturday = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 29
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.startCountdown(at: mondayAfternoon)
    store.applyScheduleChange(
        ScheduleFieldChange(workdays: [2, 3, 4, 5]),
        decision: .nextShiftOnly,
        at: mondayAfternoon
    )

    let today = try #require(store.snapshot(at: mondayAfternoon))
    let rest = try #require(today.nextRestAtMs)
    let saturdayStart = Calendar.current.startOfDay(for: saturday).timeIntervalSince1970 * 1_000
    #expect(abs(rest - saturdayStart) < 1)
    #expect(store.visualPhase(snapshot: today, at: mondayAfternoon) == .running)
}

@MainActor
@Test("Forcing an overnight shift from after midnight marks the run on screen")
func forcingAnOvernightShiftAfterMidnightMarksThatRun() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let sundayMorning = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 30, hour: 1
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 22 * 60
    store.endMinutes = 6 * 60
    store.startCountdown(force: true, at: sundayMorning)

    // The shift began on Saturday. Stamping Sunday would mark a run nobody is
    // looking at, and the button would appear to do nothing.
    let running = try #require(store.snapshot(at: sundayMorning))
    #expect(store.isForcedWorkday(running))
    #expect(store.visualPhase(snapshot: running, at: sundayMorning) == .running)
}

@MainActor
@Test("Records for a shift the schedule has left behind are cleared")
func staleCompletionRecordsAreClearedOnTheNextShift() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let mondayAtWork = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 11
    )))
    let tuesdayAfterMidnight = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 25, hour: 0, minute: 30
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.startCountdown(at: mondayAtWork)
    store.clockOffEarly(at: mondayAtWork)

    #expect(store.earlyOffAtMs != nil)
    #expect(defaults.data(forKey: "ios.native.earlyOffSnapshot") != nil)

    // Absolute timestamps: no later shift can ever match them again, so
    // nothing else would have removed them. Settlement is not dismissible,
    // so there is no `dismissedCompleted` mark to clear.
    #expect(store.reconcileCountdownSession(at: tuesdayAfterMidnight))
    #expect(store.earlyOffAtMs == nil)
    #expect(store.earlyOffShiftEndAtMs == nil)
    #expect(defaults.data(forKey: "ios.native.earlyOffSnapshot") == nil)

    let tuesday = try #require(store.snapshot(at: tuesdayAfterMidnight))
    #expect(store.visualPhase(snapshot: tuesday) == .running)
}

@MainActor
@Test("A forced run survives a relaunch")
func forcedRunSurvivesARelaunch() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let saturday = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 29, hour: 11
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.startCountdown(force: true, at: saturday)
    #expect(store.forcedWorkdayKey != nil)

    // The mark is persisted, so the run is still forced after a cold start —
    // it is no longer re-derived from whatever day it happens to be.
    let relaunched = OffWorkStore(defaults: defaults)
    #expect(relaunched.forcedWorkdayKey != nil)
    let saturdayShift = try #require(relaunched.snapshot(at: saturday))
    #expect(relaunched.isForcedWorkday(saturdayShift))
}

@MainActor
@Test("Clocking in early moves start to now and keeps the planned end")
func clockingInEarlyLengthensTodayWithoutMovingTheEnd() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let beforeStart = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 8
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.startCountdown(at: beforeStart)

    let waiting = try #require(store.snapshot(at: beforeStart))
    #expect(waiting.isBeforeStart(at: beforeStart))
    #expect(store.visualPhase(snapshot: waiting, at: beforeStart) == .clockIn)

    store.requestClockInEarly(at: beforeStart)
    #expect(store.clockInConfirmPending)
    #expect(store.snapshot(at: beforeStart)?.isBeforeStart(at: beforeStart) == true)

    store.clockInEarly(at: beforeStart)
    let running = try #require(store.snapshot(at: beforeStart))
    #expect(!running.isBeforeStart(at: beforeStart))
    #expect(store.effectiveStartMinutes(at: beforeStart) == 8 * 60)
    #expect(store.effectiveEndMinutes(at: beforeStart) == 17 * 60)
    #expect(store.visualPhase(snapshot: running, at: beforeStart) == .running)

    let tuesdayStart = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 25, hour: 9
    )))
    let nextStart = try #require(running.nextShiftStartAtMs)
    #expect(abs(nextStart - tuesdayStart.timeIntervalSince1970 * 1_000) < 1)

    store.undoEarlyClockIn()
    let restored = try #require(store.snapshot(at: beforeStart))
    #expect(restored.isBeforeStart(at: beforeStart))
}

@MainActor
@Test("Cancelling rest-day manual timing returns to rest without an early clock-off")
func cancellingManualTimingReturnsToRest() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let saturday = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 29, hour: 11
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.startCountdown(force: true, at: saturday)

    let working = try #require(store.snapshot(at: saturday))
    #expect(store.visualPhase(snapshot: working, at: saturday) == .running)
    store.cancelManualTiming()

    let rest = try #require(store.snapshot(at: saturday))
    #expect(!store.isForcedWorkday(rest))
    #expect(store.earlyOffAtMs == nil)
    #expect(store.visualPhase(snapshot: rest, at: saturday) == .rest)
}

@MainActor
@Test("Unscheduled idle is its own phase, then a session, then midnight resets")
func unscheduledSessionResetsAfterTheEndDay() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let monday = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 10
    )))
    let nextDay = try #require(Calendar.current.date(byAdding: .day, value: 1, to: monday))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .off
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60

    #expect(store.visualPhase(at: monday) == .unscheduled)
    store.startCountdown(at: monday)
    let running = try #require(store.snapshot(at: monday))
    #expect(store.visualPhase(snapshot: running, at: monday) == .running)

    store.clockOffEarly(at: monday)
    #expect(store.visualPhase(snapshot: store.snapshot(at: monday), at: monday) == .completed)

    #expect(store.reconcileCountdownSession(at: nextDay))
    #expect(store.visualPhase(at: nextDay) == .unscheduled)
}

@MainActor
@Test("Share copy before clock-in does not claim the shift is ending")
func shareCopyBeforeClockInCountsToStart() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let beforeStart = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 8
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.languageOverride = "en"
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.startCountdown(at: beforeStart)

    let copy = store.shareCopy(at: beforeStart)
    #expect(copy.contains("starts"))
    #expect(!copy.lowercased().contains("off work in"))
}

@MainActor
@Test("An overnight shift stays on settlement until the end calendar day is over")
func overnightShiftSettlesUntilEndCalendarMidnight() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let fridayNight = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 7, day: 3, hour: 23
    )))
    let saturdayMorning = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 7, day: 4, hour: 6, minute: 30
    )))
    let sundayMorning = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 7, day: 5, hour: 0, minute: 30
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 22 * 60
    store.endMinutes = 6 * 60
    store.startCountdown(at: fridayNight)

    let saturday = try #require(store.snapshot(at: saturdayMorning))
    #expect(saturday.isWorkday)
    #expect(saturday.remainingMs <= 0)
    #expect(store.visualPhase(snapshot: saturday, at: saturdayMorning) == .completed)

    let fromFridayNight = WidgetSnapshotPublisher.shared.makeSnapshot(
        store: store,
        shift: store.snapshot(at: fridayNight),
        active: true,
        nowMs: Int64(fridayNight.timeIntervalSince1970 * 1_000)
    )
    let fridaySeam = try #require(fromFridayNight.entry(
        atMs: Int64(saturdayMorning.timeIntervalSince1970 * 1_000)
    ))
    #expect(fridaySeam.labelKey == "offWorkToday")

    let fromSaturdayMorning = WidgetSnapshotPublisher.shared.makeSnapshot(
        store: store,
        shift: saturday,
        active: true,
        nowMs: Int64(saturdayMorning.timeIntervalSince1970 * 1_000)
    )
    let saturdaySeam = try #require(fromSaturdayMorning.entry(
        atMs: Int64(saturdayMorning.timeIntervalSince1970 * 1_000)
    ))
    #expect(saturdaySeam.labelKey == "offWorkToday")

    store.clockOffEarly(at: fridayNight)
    _ = store.reconcileCountdownSession(at: saturdayMorning)
    #expect(store.isEndedEarly(try #require(store.snapshot(at: saturdayMorning))))

    _ = store.reconcileCountdownSession(at: sundayMorning)
    #expect(store.earlyOffAtMs == nil)
    #expect(store.visualPhase(at: sundayMorning) == .rest)
}

@MainActor
@Test("Rest days do not schedule reminders for a phantom current shift")
func restDaysDoNotScheduleCurrentShiftReminders() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let saturdayAfternoon = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 29, hour: 13
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.notificationMode = .milestones
    store.startCountdown(at: saturdayAfternoon)

    let reminders = try store.shiftReminders(at: saturdayAfternoon)
    #expect(!reminders.contains { $0.id.hasPrefix("current:") })
    #expect(reminders.contains { $0.id.hasPrefix("next:") })
}

@MainActor
@Test("Day-shift overtime past midnight stays on settlement until the next window")
func dayShiftOvertimeSettlesUntilNextLiveWindow() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let mondayAfternoon = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 16
    )))
    let overtimeEnd = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 25, hour: 1
    )))
    let afterOvertime = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 25, hour: 1, minute: 30
    )))
    let nextOpen = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 25, hour: 9, minute: 30
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.startCountdown(at: mondayAfternoon)
    store.applyOvertime(date: overtimeEnd)

    let settled = try #require(store.snapshot(at: afterOvertime))
    #expect(Calendar.current.component(.day, from: settled.startDate) == 24)
    #expect(settled.remainingMs <= 0)
    #expect(store.visualPhase(snapshot: settled, at: afterOvertime) == .completed)

    let widget = WidgetSnapshotPublisher.shared.makeSnapshot(
        store: store,
        shift: settled,
        active: true,
        nowMs: Int64(afterOvertime.timeIntervalSince1970 * 1_000)
    )
    let current = try #require(widget.entry(
        atMs: Int64(afterOvertime.timeIntervalSince1970 * 1_000)
    ))
    #expect(current.phase == .done)

    let next = try #require(store.snapshot(at: nextOpen))
    #expect(Calendar.current.component(.day, from: next.startDate) == 25)
    #expect(next.remainingMs > 0)
    #expect(store.visualPhase(snapshot: next, at: nextOpen) == .running)
}

@MainActor
@Test("Next-shift-only on a rest day does not make today a workday")
func nextShiftOnlyAddingTodayOnARestDayKeepsRest() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let saturday = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 29, hour: 11
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.startCountdown(at: saturday)
    store.applyScheduleChange(
        ScheduleFieldChange(workdays: [1, 2, 3, 4, 5, 6]),
        decision: .nextShiftOnly,
        at: saturday
    )

    #expect(store.workdays.contains(6))
    #expect(!store.effectiveWorkdays(at: saturday).contains(6))
    let shift = try #require(store.snapshot(at: saturday))
    #expect(store.visualPhase(snapshot: shift, at: saturday) == .rest)
}

@MainActor
@Test("Next-shift-only leaving off keeps today unscheduled")
func nextShiftOnlyLeavingOffKeepsTodayUnscheduled() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let monday = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 11
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .off
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.applyScheduleChange(
        ScheduleFieldChange(scheduleMode: .classic),
        decision: .nextShiftOnly,
        at: monday
    )

    #expect(store.scheduleMode == .classic)
    #expect(store.effectiveScheduleMode(at: monday) == .off)
    #expect(store.visualPhase(at: monday) == .unscheduled)
}

@MainActor
@Test("Apply-to-today hours keep rest-day manual timing")
func applyToTodayHoursKeepForcedWorkday() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let saturday = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 29, hour: 11
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.startCountdown(force: true, at: saturday)
    store.applyScheduleChange(
        ScheduleFieldChange(endMinutes: 18 * 60),
        decision: .applyToToday,
        at: saturday
    )

    let shift = try #require(store.snapshot(at: saturday))
    #expect(store.isForcedWorkday(shift))
    #expect(store.visualPhase(snapshot: shift, at: saturday) == .running)
    #expect(store.effectiveEndMinutes(at: saturday) == 18 * 60)
}

@MainActor
@Test("Live Activity fallback skips rest-day phantom windows")
func liveActivityFallbackSkipsRestDayPhantomWindows() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let saturday = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 29, hour: 11
    )))
    let monday = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 11
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.liveActivityEnabled = true
    store.notificationMode = .off
    store.startCountdown(at: monday)

    #expect(!store.shouldScheduleLiveActivityEndFallback(
        snapshot: store.snapshot(at: saturday),
        at: saturday
    ))
    #expect(store.shouldScheduleLiveActivityEndFallback(
        snapshot: store.snapshot(at: monday),
        at: monday
    ))
}

@MainActor
@Test("A shift-end celebration is not persisted across launches")
func celebrationDoesNotSurviveRelaunch() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let first = OffWorkStore(defaults: defaults)
    first.markCelebrated(endAtMs: 1_700_000_000_000)
    #expect(first.lastCelebratedEndAtMs == 1_700_000_000_000)

    let relaunched = OffWorkStore(defaults: defaults)
    #expect(relaunched.lastCelebratedEndAtMs == 0)
}

@MainActor
@Test("Leaving the foreground forgets the shift-end celebration")
func celebrationResetsWhenLeavingForeground() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = OffWorkStore(defaults: defaults)
    store.markCelebrated(endAtMs: 1_700_000_000_000)
    store.resetCelebratedSession()
    #expect(store.lastCelebratedEndAtMs == 0)
}

@MainActor
@Test("Clock-in progress starts near zero instead of showing remaining percent")
func clockInProgressUsesElapsedDirection() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let justAfterMidnight = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 0, minute: 8
    )))

    let store = OffWorkStore(defaults: defaults)
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    let shift = try #require(store.snapshot(at: justAfterMidnight))

    #expect(store.countdownToClockInProgress(snapshot: shift) < 2)
    #expect(store.countdownToClockInProgress(snapshot: shift) > 1)
}

@MainActor
@Test("Rest-day widget progress advances across the same off-work interval")
func restDayWidgetProgressAdvances() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let saturdayNoon = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 29, hour: 12
    )))
    let saturdayEvening = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 29, hour: 18
    )))

    let store = OffWorkStore(defaults: defaults)
    store.onboardingComplete = true
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.startCountdown(at: saturdayNoon)

    let snapshot = WidgetSnapshotPublisher.shared.makeSnapshot(
        store: store,
        shift: store.snapshot(at: saturdayNoon),
        active: true,
        nowMs: Int64(saturdayNoon.timeIntervalSince1970 * 1_000)
    )
    let initial = try #require(snapshot.entry(
        atMs: Int64(saturdayNoon.timeIntervalSince1970 * 1_000)
    ))
    let projected = initial.projected(
        atMs: Int64(saturdayEvening.timeIntervalSince1970 * 1_000)
    )

    #expect(initial.phase == .before)
    #expect(projected.progressAtDate > initial.progressAtDate)
}

@MainActor
@Test("Schedule save asks only while today can still change")
func scheduleSavePromptTracksTodayImpact() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let mondayAfterWork = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 18
    )))
    let saturday = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 29, hour: 11
    )))

    let store = OffWorkStore(defaults: defaults)
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60

    #expect(!store.shouldPromptApplyingToToday(
        ScheduleFieldChange(startMinutes: 8 * 60, endMinutes: 16 * 60),
        scope: .schedule,
        at: mondayAfterWork
    ))
    #expect(store.shouldPromptApplyingToToday(
        ScheduleFieldChange(endMinutes: 19 * 60),
        scope: .schedule,
        at: mondayAfterWork
    ))
    #expect(!store.shouldPromptApplyingToToday(
        ScheduleFieldChange(startMinutes: 8 * 60),
        scope: .schedule,
        at: saturday
    ))
    #expect(store.shouldPromptApplyingToToday(
        ScheduleFieldChange(workdays: [1, 2, 3, 4, 5, 6]),
        scope: .schedule,
        at: saturday
    ))
}

@MainActor
@Test("Lunch save ignores a finished lunch but asks for a remaining one")
func lunchSavePromptTracksRemainingBreak() throws {
    let (defaults, suite) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let beforeLunch = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 11
    )))
    let afterLunch = try #require(Calendar.current.date(from: DateComponents(
        year: 2026, month: 8, day: 24, hour: 14
    )))

    let store = OffWorkStore(defaults: defaults)
    store.scheduleMode = .classic
    store.workdays = [1, 2, 3, 4, 5]
    store.startMinutes = 9 * 60
    store.endMinutes = 17 * 60
    store.lunchEnabled = true
    store.lunchStartMinutes = 12 * 60
    store.lunchDurationMinutes = 60

    #expect(!store.shouldPromptApplyingToToday(
        ScheduleFieldChange(lunchEnabled: false),
        scope: .lunch,
        at: afterLunch
    ))
    #expect(store.shouldPromptApplyingToToday(
        ScheduleFieldChange(lunchStartMinutes: 15 * 60),
        scope: .lunch,
        at: afterLunch
    ))
    #expect(store.shouldPromptApplyingToToday(
        ScheduleFieldChange(lunchEnabled: false),
        scope: .lunch,
        at: beforeLunch
    ))
}

@MainActor
@Test("Live Activity progress freezes between effective work segments")
func liveActivityProgressFreezesDuringLunch() {
    let hour = Int64(60 * 60 * 1_000)
    let state = OffWorkActivityAttributes.ContentState(
        endAtMs: 8 * hour,
        progress: 3.0 / 7.0 * 100,
        segments: [
            .init(startAtMs: 0, endAtMs: 3 * hour),
            .init(startAtMs: 4 * hour, endAtMs: 8 * hour),
        ],
        phase: "working",
        locale: "en",
        appTitle: "DoneAt",
        caption: "Time left",
        completedCaption: "Done",
        completedNote: "Well done"
    )

    let lunchProgress = state.projectedProgress(atMs: 3 * hour + hour / 2)
    let afterLunchProgress = state.projectedProgress(atMs: 5 * hour)
    #expect(abs(lunchProgress - 3.0 / 7.0 * 100) < 0.001)
    #expect(afterLunchProgress > lunchProgress)
}

private func isolatedDefaults() throws -> (UserDefaults, String) {
    let suite = "OffWorkStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    return (defaults, suite)
}
