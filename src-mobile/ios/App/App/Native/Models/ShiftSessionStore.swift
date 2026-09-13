import Foundation
import Observation

/// Session commands coordinate the committed preferences, historical records
/// and Focus. Readers depend on ShiftSession, so this action owner creates no
/// cycle through Focus or Records and can run without an application scene.
@MainActor
@Observable
final class ShiftSessionStore {
    let session: ShiftSession
    let preferences: PreferencesStore
    let text: AppText
    let records: RecordCoordinator
    let queries: RecordsQueries
    let focus: FocusStore
    let plus: PlusEntitlement
    private let defaults: UserDefaults

    private enum Key {
        static let activeCountdownEndAtMs = "ios.native.activeCountdownEndAtMs"
        static let lastCelebratedEndAtMs = "ios.native.lastCelebratedEndAtMs"
        static let appReviewPrompt = "ios.native.appReviewPrompt.v1"
    }
    private var activeCountdownEndAtMs: Double? {
        didSet {
            guard activeCountdownEndAtMs != oldValue else { return }
            if let activeCountdownEndAtMs {
                defaults.set(activeCountdownEndAtMs, forKey: Key.activeCountdownEndAtMs)
            } else {
                defaults.removeObject(forKey: Key.activeCountdownEndAtMs)
            }
        }
    }
    /// In-memory only: neither tab switches nor a background/foreground cycle
    /// may replay the same completed shift. A true cold launch constructs a
    /// fresh store, so that launch may celebrate the already-completed shift
    /// once without persisting a permanent suppression flag.
    var lastCelebratedEndAtMs: Double = 0
    private var reviewPromptState = AppReviewPromptState()
    private var reviewPromptEligibleThisLaunch = false
    var cycleEndSummaryNotificationsAreActive: Bool {
        preferences.cycleEndSummaryNotificationEnabled && plus.isAuthorized
    }

    init(session: ShiftSession, records: RecordCoordinator, queries: RecordsQueries,
         focus: FocusStore, plus: PlusEntitlement, defaults: UserDefaults) {
        self.session = session
        self.preferences = session.preferences
        self.text = session.text
        self.records = records
        self.queries = queries
        self.focus = focus
        self.plus = plus
        self.defaults = defaults
        activeCountdownEndAtMs = defaults.object(forKey: Key.activeCountdownEndAtMs) as? Double
        reviewPromptState = defaults.data(forKey: Key.appReviewPrompt)
            .flatMap { try? JSONDecoder().decode(AppReviewPromptState.self, from: $0) }
            ?? AppReviewPromptState()
        reviewPromptEligibleThisLaunch = reviewPromptState.isEligibleOnLaunch(
            trackedCompletionAtMs: activeCountdownEndAtMs,
            nowMs: Date.now.timeIntervalSince1970 * 1_000
        )
        persistReviewPromptState()
        defaults.removeObject(forKey: Key.lastCelebratedEndAtMs)
        lastCelebratedEndAtMs = 0

    }

    /// Keeps the current/future schedule projection aligned with this device's
    /// local preferences while preserving every earlier schedule snapshot.
    /// A next-shift-only edit deliberately leaves today's snapshot untouched.
    @discardableResult
    func reconcileRecordSchedule(at date: Date = .now) -> RecordCommand<Bool> {
        records.submitCommand { [self] in
            guard preferences.onboardingComplete else { return false }
            let today = preferences.recordsCalendar.startOfDay(for: date)
            let effectiveFrom: Date
            if self.session.usesTodayOverride(at: date),
               let tomorrow = preferences.recordsCalendar.date(byAdding: .day, value: 1, to: today) {
                effectiveFrom = tomorrow
            } else {
                effectiveFrom = today
            }
            return records.withBatchedWrites {
                let wasEmpty = records.state.periods.isEmpty
                records.ensureSeeded(hours: self.session.hoursConfiguration(at: date), at: date, timeZone: preferences.recordsTimeZone)
                let seeded = wasEmpty && !records.state.periods.isEmpty
                let reconciled = records.reconcileExistingHours(
                    self.session.hoursConfiguration(at: date),
                    effectiveFrom: effectiveFrom,
                    at: date
                )
                return seeded || reconciled
            }
        }
    }

    @discardableResult
    func migrateRecordsTimeZone(to timeZone: TimeZone = .current, at date: Date = .now) -> RecordCommand<Void> {
        records.submitCommand { [self] in
            guard !records.blocksWrites, preferences.recordsTimeZoneIdentifier != timeZone.identifier else { return }
            let runningZone = self.session.countdownTimeZoneIdentifier
            records.withBatchedWrites {
                guard preferences.applyPreferences({ $0.recordsTimeZoneIdentifier = timeZone.identifier }).synchronousResult else { return }
                if self.session.countdownStarted { self.session.lockSessionTimeZone(to: runningZone, at: date) }
                records.migrateCalendarTimeZone(to: timeZone.identifier, at: date)
            }
        }
    }

    @discardableResult
    func noteTimerSurfaceVisible(at date: Date = .now) -> RecordCommand<Void> {
        records.submitCommand { [self] in
            guard plus.shouldCollectObservations else { return }
            // The first-seen row is one per civil day. Calling this on every tab
            // switch used to rebuild a JavaScriptCore snapshot just to write nothing.
            let dayKey = RecordJSON.dayKey(date, calendar: preferences.recordsCalendar)
            if (queries.observationIndex()[dayKey] ?? []).contains(where: { $0.kind == .timerSurfaceFirstSeen }) {
                return
            }
            writeObservation(.timerSurfaceFirstSeen, at: date, eventID: UUID())
        }
    }

    @discardableResult
    func writeObservation(
        _ kind: WorkObservationKind,
        at date: Date,
        eventID: UUID
    ) -> RecordCommand<Void> {
        records.submitCommand { [self] in
            guard plus.shouldCollectObservations else { return }
            records.ensureSeeded(hours: self.session.hoursConfiguration(at: date), at: date, timeZone: preferences.recordsTimeZone)
            let shift = self.session.snapshot(at: date)
            let anchor = shift?.startDate ?? date
            var valueData: Data?
            if kind == .overtimeDeclared, let overtimeEndAtMs = self.session.overtimeEndAtMs {
                valueData = try? JSONEncoder().encode(OvertimeDeclarationPayload(
                    overtimeEndAtMs: overtimeEndAtMs,
                    plannedEndAtMs: shift?.plannedEndAtMs
                ))
            }
            let zone = self.session.writingTimeZone()
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            records.recordObservation(
                kind: kind,
                eventID: eventID,
                shiftAnchorDate: calendar.startOfDay(for: anchor),
                occurredAt: date,
                snapshotID: records.currentSnapshotID(on: anchor) ?? UUID(),
                valueData: valueData,
                timeZoneIdentifier: zone.identifier
            )
        }
    }

    func shiftReminders(at date: Date = .now) throws -> [NativeReminder] {
        let currentSnapshot = self.session.snapshot(at: date)
        let inputs = reminderInputs(
            cycleEndSummaryBody: currentSnapshot.flatMap {
                cycleEndSummaryNotificationBody(for: $0, at: date)
            }
        )
        let effective = try CountdownRules.shared.reminders(
            input: self.session.rulesInput(at: date),
            reminderInputs: inputs
        )
        let current = effective.filter { $0.id.hasPrefix("current:") }
        let nextSnapshot = currentSnapshot?.nextShiftStartDate.flatMap {
            self.session.snapshot(at: $0.addingTimeInterval(1))
        }
        let nextInputs = reminderInputs(
            cycleEndSummaryBody: nextSnapshot.flatMap {
                cycleEndSummaryNotificationBody(for: $0, at: $0.startDate)
            }
        )
        let next = try CountdownRules.shared.reminders(
            input: self.session.rulesInput(
                at: date,
                using: self.session.projectsFutureFromBase(at: date) ? .base : .effective
            ),
            reminderInputs: nextInputs
        ).filter { $0.id.hasPrefix("next:") }
        guard let snapshot = currentSnapshot else { return current + next }
        // Rest days and settlement both still produce a `current:` window from
        // `getShiftBounds` — Saturday 09:00–17:00 on a weekend, or Saturday
        // 22:00 after a Friday overnight ended at 06:00. Those are not a shift
        // the user is in, so they must not be scheduled.
        let includeCurrent = (snapshot.isWorkday || self.session.isForcedWorkday(snapshot))
            && !self.session.isShiftComplete(snapshot)
        // One place decides what "time to get up" means, so the scheduler and
        // the "up next" list cannot disagree about it.
        return focus.applyingFocusBreakTakeover(to: (includeCurrent ? current : []) + next, at: date)
    }

    func reminderInputs(cycleEndSummaryBody: String? = nil) -> NativeReminderInputs {
        func title(_ remaining: Int) -> String {
            text.t("notificationMilestoneTitle", values: ["percent": "\(remaining)"])
        }
        return .init(
            mode: self.session.presentationNotificationMode.rawValue,
            fallbackTitle: text.t("offWorkReminder"),
            breakTitle: text.t("breakReminder"),
            milestoneTitles: .init(
                milestone50: title(50),
                milestone75: title(25),
                milestone90: title(10),
                milestone95: title(5),
                milestone100: text.t("offWorkTime")
            ),
            milestoneMessages: .init(
                milestone50: [text.t("notificationMilestone50")],
                milestone75: [text.t("notificationMilestone75")],
                milestone90: [text.t("notificationMilestone90")],
                milestone95: [text.t("notificationMilestone95")],
                milestone100: [text.t("offWorkTime")]
            ),
            lunchStartEnabled: self.session.presentationLunchStartReminderEnabled,
            lunchStartBody: text.t("lunchStartNotification"),
            lunchEndEnabled: self.session.presentationLunchEndReminderEnabled,
            lunchEndBody: text.t("lunchEndNotification"),
            microBreakEnabled: self.session.presentationMicroBreakEnabled,
            microBreakTitle: text.t("microBreakReminder"),
            microBreakIntervalMinutes: self.session.presentationMicroBreakIntervalMinutes,
            microBreakMessages: text.strings("microBreakMessages"),
            cycleEndSummaryBody: cycleEndSummaryBody
        )
    }
    /// Builds the body only for the last resolved workday before a rest day.
    /// Work/rest classification has already come from the shared TypeScript
    /// expansion and then passed through calendar exceptions and manual edits.
    func cycleEndSummaryNotificationBody(
        for snapshot: NativeShiftSnapshot,
        at date: Date = .now
    ) -> String? {
        guard cycleEndSummaryNotificationsAreActive,
              preferences.scheduleMode != .off,
              snapshot.isWorkday || self.session.isForcedWorkday(snapshot)
        else { return nil }

        let calendar = preferences.recordsCalendar
        let anchor = calendar.startOfDay(for: snapshot.startDate)
        guard let from = calendar.date(byAdding: .day, value: -31, to: anchor),
              let through = calendar.date(byAdding: .day, value: 1, to: anchor)
        else { return nil }
        let resolved = queries.resolvedDays(from: from, through: through, now: date)
        let days = resolved.map { day in
            ScheduleCycleDay(
                dayKey: day.dayKey,
                isWorkday: day.isScheduledWorkday,
                workMs: day.segments.reduce(0) { partial, segment in
                    partial + Int64(max(0, segment.endAtMs - segment.startAtMs).rounded())
                },
                overtimeMs: queries.overtimeSegments(on: day).reduce(0) { partial, segment in
                    partial + Int64(max(0, segment.endAtMs - segment.startAtMs).rounded())
                },
                isComplete: !day.expansionFailed
            )
        }
        let dayKey = RecordJSON.dayKey(snapshot.startDate, calendar: calendar)
        guard let summary = ScheduleCycleSummaryCalculator.summary(endingAt: dayKey, in: days) else {
            return nil
        }
        return text.t("cycleEndSummaryNotificationBody", values: [
            "days": text.formatCount(summary.workdayCount),
            "work": text.formatDuration(Double(summary.workMs), includeSeconds: false),
            "overtime": text.formatDuration(Double(summary.overtimeMs), includeSeconds: false),
        ])
    }

    func noteCountdownCompleted(endAtMs: Double) {
        let previous = reviewPromptState
        reviewPromptState.noteCompletion(atMs: endAtMs)
        if reviewPromptState != previous { persistReviewPromptState() }
    }

    /// Claims the launch opportunity once; the requesting scene owns its alert.
    func claimReviewPromptIfEligible() -> Bool {
        guard reviewPromptEligibleThisLaunch,
              preferences.onboardingComplete,
              plus.hasSeenIntro
        else { return false }
        reviewPromptEligibleThisLaunch = false
        return true
    }

    func acceptReviewPrompt() {
        reviewPromptState.disable()
        persistReviewPromptState()
    }

    func deferReviewPrompt() {
        reviewPromptState.deferUntilNextCompletion()
        persistReviewPromptState()
    }

    func disableAutomaticReviewPrompt() {
        reviewPromptEligibleThisLaunch = false
        reviewPromptState.disable()
        persistReviewPromptState()
    }
    private func revokeCountdownCompletion(endAtMs: Double?) {
        guard let endAtMs else { return }
        let previous = reviewPromptState
        reviewPromptState.revokeCompletion(atMs: endAtMs)
        if reviewPromptState != previous { persistReviewPromptState() }
    }
    private func persistReviewPromptState() {
        guard let data = try? JSONEncoder().encode(reviewPromptState) else { return }
        defaults.set(data, forKey: Key.appReviewPrompt)
    }
    /// Builds the presentation timeline from shared absolute boundaries.
    /// Scheduled reminders stay scoped to today, while the shift start/end
    /// boundaries remain visible for a complete (including overnight) flow.
    func upcomingTimelineEvents(
        for snapshot: NativeShiftSnapshot,
        at now: Date = .now
    ) -> [UpcomingTimelineEvent] {
        let nowMs = now.timeIntervalSince1970 * 1_000
        var events: [UpcomingTimelineEvent] = []

        // Bounded by the shift, not by the calendar day. Requiring the same day
        // as `now` silently dropped lunch, health reminders and the Live
        // Activity lead-in from every overnight shift — they all land after
        // midnight, so only the shift's own start and end rows survived.
        func isDuringShift(_ atMs: Double) -> Bool {
            atMs > nowMs && atMs <= snapshot.endAtMs
        }

        if snapshot.startAtMs > nowMs {
            events.append(.init(
                id: "shift-start-\(Int64(snapshot.startAtMs))",
                kind: .shiftStart,
                date: snapshot.startDate,
                title: text.t("startTime"),
                detail: text.t("todaysShift")
            ))
        }

        for (index, segment) in snapshot.segments.dropLast().enumerated() {
            let nextSegment = snapshot.segments[index + 1]
            guard nextSegment.startAtMs > segment.endAtMs else { continue }

            if isDuringShift(segment.endAtMs) {
                events.append(.init(
                    id: "lunch-start-\(Int64(segment.endAtMs))",
                    kind: .lunchStart,
                    date: Date(timeIntervalSince1970: segment.endAtMs / 1_000),
                    title: text.t("lunchBreak"),
                    detail: text.t("lunchStartTime")
                ))
            }

            if isDuringShift(nextSegment.startAtMs) {
                events.append(.init(
                    id: "lunch-end-\(Int64(nextSegment.startAtMs))",
                    kind: .lunchEnd,
                    date: Date(timeIntervalSince1970: nextSegment.startAtMs / 1_000),
                    title: text.t("lunchBreak"),
                    detail: text.t("lunchBackAt")
                ))
            }
        }

        // Exactly one micro-break row, carrying its interval, rather than one
        // per firing — eight identical hourly rows buried the two that matter.
        // It is effectively permanent near the top of the list, which is the
        // point: this is the seam a pomodoro timer will plug into later.
        //
        // The Live Activity lead-in stays out of the running list. It is a
        // notification about this countdown rather than an event within it, and
        // by the time it fires the user is already looking at the screen.
        if self.session.presentationMicroBreakEnabled,
           let reminders = try? CountdownRules.shared.reminders(
               input: self.session.rulesInput(at: now),
               reminderInputs: reminderInputs()
           ),
           let next = reminders
               .filter({ $0.kind == "microBreak" && isDuringShift($0.atMs) })
               .min(by: { $0.atMs < $1.atMs }) {
            events.append(.init(
                id: next.id,
                kind: .health,
                date: Date(timeIntervalSince1970: next.atMs / 1_000),
                title: text.t("microBreakReminder"),
                detail: text.t("minutesShort", values: ["count": "\(self.session.presentationMicroBreakIntervalMinutes)"])
            ))
        }

        events.append(contentsOf: focus.focusUpcomingTimelineEvents(for: snapshot, at: now))

        // One row per push. Unlike the micro-break these fire at distinct points
        // rather than on a cycle, and seeing them is what turns "ends at 23:00"
        // into a shift broken into markers — which is why they live here, on the
        // running screen, and not in the pre-start preview.
        //
        // A milestone the rules engine left untitled is a silent tick rather
        // than a push, so it gets no row; that is also what keeps "at off-work
        // time only" from listing anything, since its one audible milestone is
        // the shift's end and the list already has a row for that.
        if self.session.presentationNotificationMode == .milestones {
            events.append(contentsOf: (try? CountdownRules.shared.reminders(
                input: self.session.rulesInput(at: now),
                reminderInputs: reminderInputs()
            ))?
                // The 100% milestone lands on the stroke of the shift's end,
                // where the list already has a row saying exactly that. Two
                // rows at 19:00 is not two events.
                //
                // Matched by suffix, not equality: the JS bridge re-keys every
                // reminder as "<scope>:<shiftEnd>:<id>" before handing it back,
                // so the rule engine's own "milestone:100" is only ever the tail
                // of what arrives here.
                .filter {
                    $0.kind == "milestone" && !$0.id.hasSuffix(":milestone:100")
                        && $0.title != nil && isDuringShift($0.atMs)
                }
                .map { reminder in
                    UpcomingTimelineEvent(
                        id: reminder.id,
                        kind: .milestone,
                        date: Date(timeIntervalSince1970: reminder.atMs / 1_000),
                        title: text.t("offWorkReminder"),
                        detail: reminder.title ?? ""
                    )
                } ?? [])
        }

        if snapshot.endAtMs > nowMs {
            events.append(.init(
                id: "shift-end-\(Int64(snapshot.endAtMs))",
                kind: .shiftEnd,
                date: snapshot.endDate,
                title: text.t("endTime"),
                detail: snapshot.overtimeEndAtMs == nil ? text.t("todaysShift") : text.t("overtime")
            ))
        }

        func boundaryOrder(_ kind: UpcomingTimelineEvent.Kind) -> Int {
            switch kind {
            case .shiftStart: 0
            case .shiftEnd: 2
            default: 1
            }
        }

        return events.sorted {
            if $0.date == $1.date {
                let leftOrder = boundaryOrder($0.kind)
                let rightOrder = boundaryOrder($1.kind)
                if leftOrder != rightOrder { return leftOrder < rightOrder }
                return $0.id < $1.id
            }
            return $0.date < $1.date
        }
    }

    @discardableResult
    func startCountdown(
        force: Bool = false, startMinutes: Int? = nil, endMinutes: Int? = nil, at date: Date = .now
    ) -> RecordCommand<Bool> {
        records.submitCommand { [self] in
            guard !records.blocksWrites else { return false }
            let previous = preferences.currentSyncedPreferences()
            var draft = previous
            if let startMinutes { draft.startMinutes = startMinutes }
            if let endMinutes { draft.endMinutes = endMinutes }
            guard draft.isValid else { return false }
            let settingsChanged = !draft.hasSameSettings(as: previous)
            let startsManualSession = preferences.scheduleMode == .off
                && (session.sessionTimeZoneIdentifier == nil || session.earlyOffAtMs != nil)
            if !settingsChanged, !startsManualSession, session.countdownStarted,
               let current = session.snapshot(at: date),
               activeCountdownEndAtMs == current.endAtMs,
               force == session.isForcedWorkday(current) {
                return false
            }
            return records.withBatchedWrites {
                if preferences.scheduleMode == .off {
                    // Manual "start" is a new session. A leftover early-off from a
                    // scheduled day that was then switched to off would otherwise pin
                    // this button to settlement: ended-early never runs.
                    self.session.clearEarlyClockOffRecord()
                    self.session.clearEarlyClockInRecord()
                }
                preferences.applyPreferences { $0 = draft }
                let wasRunning = self.session.countdownStarted
                self.session.beginSession()
                if force || preferences.scheduleMode == .off, !wasRunning || self.session.sessionTimeZoneIdentifier == nil {
                    self.session.lockSessionTimeZone(
                        to: self.session.timeZoneIdentifierForWriting(startingNewSession: true),
                        at: date
                    )
                }
                let shift = self.session.snapshot(at: date)
                // The day the shift starts, not the day the button was pressed. They
                // differ for an overnight shift forced after midnight, and marking the
                // press day there would mark a run nobody is looking at.
                self.session.forcedWorkdayDate = force
                    ? ShiftSession.dayKey(for: shift?.startDate ?? date, timeZone: self.session.countdownTimeZone)
                    : nil
                if let shift, self.session.isEndedEarly(shift) {
                    // Same shift, possibly with nudged hours. Keep the early-off
                    // record so settlement stays on this run.
                } else {
                    self.session.clearEarlyClockOffRecord()
                }
                recordActiveCountdownBoundary(at: date)
                writeObservation(.countdownStarted, at: date, eventID: UUID())
                persistProjectedDayOverride(at: date)
                return true
            }
        }
    }

    @discardableResult
    func clockOffEarly(at date: Date = .now) -> RecordCommand<Bool> {
        records.submitCommand { [self] in
            guard !records.blocksWrites else { return false }
            return records.withBatchedWrites {
                guard let shift = session.snapshot(at: date), !shift.isBeforeStart(at: date),
                      !session.isEndedEarly(shift) else { return false }
                self.session.earlyOffAtMs = date.timeIntervalSince1970 * 1_000
                self.session.earlyOffShiftEndAtMs = shift.endAtMs
                self.session.earlyOffSnapshot = shift

                // Leave a forced rest-day run in place until settlement: cancelling
                // manual timing is a different action. Clocking off still ends the day.
                self.session.forcedWorkdayDate = self.session.isForcedWorkday(shift) ? self.session.forcedWorkdayDate : nil
                // Keep the session boundary so an unscheduled midnight reset still
                // knows which calendar day this run belonged to. Overtime stays too:
                // clearing it here would shrink the window and settlement would lose
                // the extra hours.
                writeObservation(.countdownStopped, at: date, eventID: UUID())
                persistProjectedDayOverride(at: date)
                noteCountdownCompleted(endAtMs: self.session.earlyOffAtMs ?? date.timeIntervalSince1970 * 1_000)
                return true
            }
        }
    }
    /// Takes it back. Deliberately its own action rather than a side effect of
    /// editing the schedule: changing tomorrow's hours must never quietly
    /// resurrect today, or every settings visit becomes a coin toss.
    @discardableResult
    func undoEarlyClockOff() -> RecordCommand<Void> {
        records.submitCommand { [self] in
            guard !records.blocksWrites else { return }
            let revokedCompletionAtMs = self.session.earlyOffAtMs
            self.session.clearEarlyClockOffRecord()
            revokeCountdownCompletion(endAtMs: revokedCompletionAtMs)
            recordActiveCountdownBoundary()
        }
    }

    @discardableResult
    func clockInEarly(at date: Date = .now) -> RecordCommand<Bool> {
        records.submitCommand { [self] in
            guard !records.blocksWrites else { return false }
            return records.withBatchedWrites {
                guard let shift = self.session.snapshot(at: date), shift.isBeforeStart(at: date) else { return false }
                let calendar = session.countdownCalendar
                let floored = Self.floorToMinute(date, calendar: calendar)
                self.session.earlyStartAtMs = floored.timeIntervalSince1970 * 1_000
                let endDay = calendar.startOfDay(for: shift.endDate)
                self.session.earlyStartUntilMs = calendar.date(byAdding: .day, value: 1, to: endDay)
                    .map { $0.timeIntervalSince1970 * 1_000 }

                writeObservation(.countdownStarted, at: date, eventID: UUID())
                persistProjectedDayOverride(at: date)
                return true
            }
        }
    }

    @discardableResult
    func undoEarlyClockIn() -> RecordCommand<Void> {
        records.submitCommand { [self] in
            guard !records.blocksWrites else { return }
            self.session.clearEarlyClockInRecord()
            recordActiveCountdownBoundary()
        }
    }
    /// Rest-day manual timing only. Does not leave an "I worked" record.
    @discardableResult
    func cancelManualTiming() -> RecordCommand<Bool> {
        records.submitCommand { [self] in
            guard !records.blocksWrites, session.forcedWorkdayDate != nil else { return false }
            self.session.forcedWorkdayDate = nil

            self.session.clearEarlyClockOffRecord()
            self.session.clearEarlyClockInRecord()
            clearOvertime()
            recordActiveCountdownBoundary()
            return true
        }
    }
    /// Live Activity + notifications-off still needs a clock-off ping, but
    /// only for a shift the user is actually in. Rest-day dummy windows must
    /// not go through this side door.
    func shouldScheduleLiveActivityEndFallback(
        snapshot: NativeShiftSnapshot?,
        at date: Date = .now
    ) -> Bool {
        guard preferences.liveActivityEnabled, preferences.notificationMode == .off else { return false }
        guard self.session.publishesLiveSurfaces else { return false }
        guard let snapshot else { return false }
        guard cycleEndSummaryNotificationBody(for: snapshot, at: date) == nil else { return false }
        guard snapshot.endAtMs > date.timeIntervalSince1970 * 1_000 else { return false }
        guard !self.session.isEndedEarly(snapshot) else { return false }
        return (snapshot.isWorkday || self.session.isForcedWorkday(snapshot)) && !self.session.isShiftComplete(snapshot)
    }

    @discardableResult
    func stopCountdown(at date: Date = .now, recordObservation: Bool = true) -> RecordCommand<Bool> {
        records.submitCommand { [self] in
            guard !records.blocksWrites, session.countdownStarted else { return false }
            return records.withBatchedWrites {
                // A schedule has no session to stop. Unscheduled midnight still
                // tears down today's manual run.
                guard !session.followsSchedule else { return false }

                self.session.countdownStarted = false

                self.session.forcedWorkdayDate = nil
                activeCountdownEndAtMs = nil
                clearOvertime()
                self.session.clearEarlyClockInRecord()
                self.session.clearEarlyClockOffRecord()
                if recordObservation {
                    writeObservation(.countdownStopped, at: date, eventID: UUID())
                }
                self.session.clearSessionTimeZone()
                return true
            }
        }
    }
    /// Scheduled countdowns stay armed across calendar days. The concrete
    /// boundary still scopes one-off state such as overtime and a forced rest-
    /// day run to the shift that created it. Manual (`preferences.scheduleMode == .off`)
    /// countdowns retain their one-session behavior and reset after the end day.
    @discardableResult
    func reconcileCountdownSession(at date: Date = .now) -> RecordCommand<Bool> {
        records.submitCommand { [self] in
            guard !records.blocksWrites else { return false }
            let calendar = session.countdownCalendar
            var changed = false
            _ = focus.carryIncompleteFocusTasks(at: date).synchronousResult
            _ = focus.restoreScheduledFocus(at: date).synchronousResult
            _ = focus.reconcileOpenFocusSessions(at: date).synchronousResult
            if !focus.finishElapsedFocusSession(at: date).synchronousResult, let session = focus.activeFocusSession() {
                _ = focus.scheduleFocusExpiry(for: session).synchronousResult
            }
            // A completed manual run stays on its own civil day until the midnight
            // reset. Dropping its timezone at shift end can move that reset to the
            // records timezone on the next lifecycle callback.
            if session.followsSchedule(at: date) { session.expireSessionTimeZone(at: date) }
            if let override = self.session.todayOverride, date.timeIntervalSince1970 * 1_000 >= override.untilMs {
                self.session.todayOverride = nil
                changed = true
                if preferences.scheduleMode == .off {
                    stopUnscheduledSession(at: date)
                }
            }
            if let earlyStartUntilMs = self.session.earlyStartUntilMs, date.timeIntervalSince1970 * 1_000 >= earlyStartUntilMs {
                self.session.clearEarlyClockInRecord()
                changed = true
            }

            guard self.session.countdownStarted || self.session.followsSchedule(at: date) else {
                activeCountdownEndAtMs = nil
                return changed
            }

            if self.session.followsSchedule(at: date) {
                let current = self.session.snapshot(at: date)

                if let overtimeEndAtMs = self.session.overtimeEndAtMs {
                    let overtimeEnd = Date(timeIntervalSince1970: overtimeEndAtMs / 1_000)
                    let overtimeEndDay = calendar.startOfDay(for: overtimeEnd)
                    if let resetDate = calendar.date(byAdding: .day, value: 1, to: overtimeEndDay),
                       date >= resetDate {
                        self.session.overtimeEndAtMs = nil
                        changed = true
                    }
                }

                // Everything below needs a shift to compare against. Without one
                // the rules are unavailable, and deleting a record because it
                // cannot be matched right now is how a forced run disappears.
                guard let current else { return changed }

                if self.session.forcedWorkdayDate != nil, !self.session.isForcedWorkday(current) {
                    self.session.forcedWorkdayDate = nil
                    changed = true
                }
                if self.session.earlyOffAtMs != nil, !self.session.isEndedEarly(current) {
                    self.session.clearEarlyClockOffRecord()
                    changed = true
                }

                if activeCountdownEndAtMs != current.endAtMs {
                    activeCountdownEndAtMs = current.endAtMs
                    changed = true
                }
                return changed
            }

            guard let activeCountdownEndAtMs else {
                // An early clock-off that lost its boundary (older builds cleared
                // it) must still wait until that end day's next midnight. The
                // snapshot on the following morning is a different shift, so
                // `isEndedEarly` would not catch it.
                if let endMs = self.session.earlyOffShiftEndAtMs ?? self.session.earlyOffAtMs {
                    let endDate = Date(timeIntervalSince1970: endMs / 1_000)
                    let endDay = calendar.startOfDay(for: endDate)
                    if let resetDate = calendar.date(byAdding: .day, value: 1, to: endDay),
                       date >= resetDate {
                        stopCountdown(at: date, recordObservation: false)
                        return true
                    }
                    return changed
                }
                // Migration for sessions created before the concrete boundary was
                // persisted. Preserve an actually running shift, but do not let an
                // already-finished or not-yet-started resolved shift masquerade as
                // the old session.
                guard let current = self.session.snapshot(at: date),
                      current.remainingMs > 0,
                      current.startAtMs <= date.timeIntervalSince1970 * 1_000
                else {
                    stopCountdown(at: date, recordObservation: false)
                    return true
                }
                self.activeCountdownEndAtMs = current.endAtMs
                return changed
            }

            let endDate = Date(timeIntervalSince1970: activeCountdownEndAtMs / 1_000)
            let endDay = calendar.startOfDay(for: endDate)
            guard let resetDate = calendar.date(byAdding: .day, value: 1, to: endDay),
                  date >= resetDate
            else { return changed }

            stopCountdown(at: date, recordObservation: false)
            return true
        }
    }

    /// A full archive replacement updates preferences without going through the
    /// schedule editor. Local timer adjustments belong to the schedule they
    /// were created from, so do not carry them into a different imported shift.
    /// This intentionally changes only device-local session state: imported
    /// records and their historical schedule remain exactly as published.
    @discardableResult
    func reconcileExternalState(
        from previous: SyncedPreferences,
        at date: Date = .now
    ) -> RecordCommand<Bool> {
        records.submitCommand { [self] in
            let current = preferences.currentSyncedPreferences()
            guard !Self.hasSameShiftRules(previous, current) else { return false }

            stopUnscheduledSession(at: date)
            session.todayOverride = nil
            if preferences.onboardingComplete, current.scheduleMode != .off {
                session.countdownStarted = true
                recordActiveCountdownBoundary(at: date)
            }
            return true
        }
    }

    private static func hasSameShiftRules(_ lhs: SyncedPreferences, _ rhs: SyncedPreferences) -> Bool {
        lhs.startMinutes == rhs.startMinutes
            && lhs.endMinutes == rhs.endMinutes
            && lhs.workdays == rhs.workdays
            && lhs.scheduleMode == rhs.scheduleMode
            && lhs.alternatingWeekType == rhs.alternatingWeekType
            && lhs.alternatingWeekendWorkday == rhs.alternatingWeekendWorkday
            && lhs.alternatingReferenceWeekStartMs == rhs.alternatingReferenceWeekStartMs
            && lhs.rotationWorkDays == rhs.rotationWorkDays
            && lhs.rotationRestDays == rhs.rotationRestDays
            && lhs.rotationAnchorMs == rhs.rotationAnchorMs
            && lhs.lunchEnabled == rhs.lunchEnabled
            && lhs.lunchStartMinutes == rhs.lunchStartMinutes
            && lhs.lunchDurationMinutes == rhs.lunchDurationMinutes
            && lhs.recordsTimeZoneIdentifier == rhs.recordsTimeZoneIdentifier
    }
    private func stopUnscheduledSession(at date: Date) {
        _ = date
        self.session.countdownStarted = false

        self.session.forcedWorkdayDate = nil
        activeCountdownEndAtMs = nil
        clearOvertime()
        self.session.clearEarlyClockInRecord()
        self.session.clearEarlyClockOffRecord()
        self.session.clearSessionTimeZone()
    }
    /// Arms the schedule and records first-seen after onboarding's next frame.
    @discardableResult
    func finishOnboardingLaunch(at date: Date = .now) -> RecordCommand<Void> {
        records.submitCommand { [self] in
            if preferences.scheduleMode != .off, !self.session.countdownStarted {
                startCountdown(at: date)
            }
        }
    }

    @discardableResult
    func applyOvertime(date: Date, declaredAt: Date = .now) -> RecordCommand<Bool> {
        records.submitCommand { [self] in
            let endAtMs = date.timeIntervalSince1970 * 1_000
            guard !records.blocksWrites, endAtMs.isFinite,
                  session.overtimeEndAtMs != endAtMs || session.earlyOffAtMs != nil else { return false }
            return records.withBatchedWrites {
                let revokedCompletionAtMs = self.session.earlyOffAtMs ?? activeCountdownEndAtMs
                self.session.overtimeEndAtMs = date.timeIntervalSince1970 * 1_000
                self.session.countdownStarted = true
                activeCountdownEndAtMs = self.session.overtimeEndAtMs
                if self.session.sessionTimeZoneIdentifier != nil {
                    self.session.sessionTimeZoneUntilMs = self.session.overtimeEndAtMs
                }
                // Overtime after an early clock-off is "I wasn't done".
                self.session.clearEarlyClockOffRecord()
                revokeCountdownCompletion(endAtMs: revokedCompletionAtMs)
                // Declaring overtime creates a new completion boundary. If the normal
                // clock-off already celebrated during this warm session, let the new
                // boundary celebrate as well — including a retrospective declaration
                // whose end is the current device time.
                lastCelebratedEndAtMs = 0
                writeObservation(.overtimeDeclared, at: declaredAt, eventID: UUID())
                _ = focus.reflowLinkedFocusPlans(at: declaredAt).synchronousResult
                return true
            }
        }
    }

    @discardableResult
    func applyScheduleChange(
        _ change: ScheduleFieldChange,
        decision: ScheduleChangeDecision,
        at date: Date = .now
    ) -> RecordCommand<Bool> {
        records.submitCommand { [self] in
            let change = change.settled(against: preferences, at: date)
            guard !change.isEmpty, !records.blocksWrites else { return false }
            return records.withBatchedWrites {
                // Applying a change to today removes timer-only adjustments. Capture
                // their projection before mutating the schedule so a matching durable
                // override can be removed as well. Otherwise that old custom row keeps
                // winning over the new schedule snapshot in Records indefinitely.
                let replacedTimerProjection = decision == .applyToToday
                    ? self.session.projectedDayOverride(at: date)
                    : nil

                let preservedSchedule: TodayScheduleOverride?
                if decision == .nextShiftOnly, let until = self.session.overrideExpiry(at: date) {
                    preservedSchedule = self.session.captureSchedule(untilMs: until)
                } else {
                    preservedSchedule = nil
                }
                // Reject the entire action before touching the running session.
                guard preferences.applySetupScheduleChange(change, at: date).synchronousResult else { return false }
                self.session.todayOverride = preservedSchedule

                if decision == .applyToToday {
                    self.session.todayOverride = nil
                    clearTodayAdjustments()
                    // Hours and lunch must not cancel rest-day manual timing. Once
                    // today is a scheduled workday the forced mark is redundant.
                    if self.session.snapshot(at: date)?.isWorkday == true {
                        self.session.forcedWorkdayDate = nil
                    }
                    if self.preferences.scheduleMode == .off {
                        stopUnscheduledSession(at: date)
                    } else if preferences.onboardingComplete {
                        self.session.countdownStarted = true
                        recordActiveCountdownBoundary(at: date)
                    }
                } else if preferences.onboardingComplete, self.session.effectiveScheduleMode(at: date) != .off {
                    self.session.countdownStarted = true
                }

                let effectiveFrom: Date
                if decision == .applyToToday {
                    effectiveFrom = preferences.recordsCalendar.startOfDay(for: date)
                } else if let next = preferences.recordsCalendar.date(byAdding: .day, value: 1, to: preferences.recordsCalendar.startOfDay(for: date)) {
                    effectiveFrom = next
                } else {
                    effectiveFrom = date
                }
                records.commitHours(
                    self.session.hoursConfiguration(at: date),
                    effectiveFrom: effectiveFrom,
                    at: date,
                    timeZone: preferences.recordsTimeZone
                )
                if decision == .applyToToday {
                    replaceProjectedDayOverride(replacing: replacedTimerProjection, at: date)
                }
                _ = focus.reflowLinkedFocusPlans(at: date).synchronousResult
                return true
            }
        }
    }
    private func clearTodayAdjustments() {
        self.session.clearEarlyClockOffRecord()
        self.session.clearEarlyClockInRecord()
        clearOvertime()
    }

    @discardableResult
    func clearOvertime() -> RecordCommand<Void> {
        records.submitCommand { [self] in
            guard !records.blocksWrites else { return }
            if self.session.overtimeEndAtMs != nil { self.session.overtimeEndAtMs = nil }
            if self.session.countdownStarted { recordActiveCountdownBoundary() }
        }
    }
    private func recordActiveCountdownBoundary(at date: Date = .now) {
        activeCountdownEndAtMs = self.session.snapshot(at: date)?.endAtMs
    }

    @discardableResult
    func persistProjectedDayOverride(at date: Date = .now) -> RecordCommand<Void> {
        records.submitCommand { [self] in
            guard let override = self.session.projectedDayOverride(at: date) else { return }
            records.upsertOverride(override, at: date)
        }
    }
    /// Reconciles only the timer projection that existed before an explicit
    /// “change today too” decision. A Records-tab edit with different business
    /// content remains intact; it is not timer housekeeping.
    private func replaceProjectedDayOverride(
        replacing previous: DayOverride?,
        at date: Date
    ) {
        if let override = self.session.projectedDayOverride(at: date) {
            records.upsertOverride(override, at: date)
            return
        }
        guard let previous,
              let stored = records.state.overrides.first(where: { $0.dayKey == previous.dayKey }),
              Self.hasSameDayOverrideContent(stored, previous)
        else { return }
        records.erase(.dayOverride, key: previous.dayKey, at: date)
    }
    private static func hasSameDayOverrideContent(_ lhs: DayOverride, _ rhs: DayOverride) -> Bool {
        lhs.dayKey == rhs.dayKey
            && lhs.shiftAnchorDate == rhs.shiftAnchorDate
            && lhs.kind == rhs.kind
            && lhs.segments == rhs.segments
            && lhs.note == rhs.note
            && lhs.timeZoneIdentifier == rhs.timeZoneIdentifier
    }

    func markCelebrated(endAtMs: Double) {
        lastCelebratedEndAtMs = endAtMs
    }
    /// Debug capture scenarios may explicitly clear this in-memory token.
    /// Normal warm-session lifecycle never does: only constructing a fresh
    /// store on cold launch makes the completed shift celebrate again.
    func resetCelebratedSession() {
        lastCelebratedEndAtMs = 0
    }
    private static func floorToMinute(_ date: Date, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: parts) ?? date
    }
}
