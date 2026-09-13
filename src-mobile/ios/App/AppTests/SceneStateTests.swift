import Foundation
import Testing
@testable import App

@MainActor
@Suite("Scene ownership")
struct SceneStateTests {
    @Test("Canvas selection and pending editor state are independent between scenes")
    func independentCanvasState() {
        let first = SceneState(recordsScale: .year)
        let second = SceneState(recordsScale: .month)
        let records = first.records
        records.anchor = Date(timeIntervalSince1970: 1_788_775_200)
        records.selectedDayKey = "2026-09-07"
        records.selectedYearMonth = 9
        records.expanded[.year] = true
        first.focus.scale = .usual
        first.focus.dayTemplateName = "Morning routine"
        first.focus.namesDayTemplate = true
        first.focus.quickCreateLanding = .nextBlock

        #expect(first.records === records)
        #expect(first.records.selectedDayKey == "2026-09-07")
        #expect(first.records.expanded[.year] == true)
        #expect(first.focus.dayTemplateName == "Morning routine")
        #expect(second.records.scale == .month)
        #expect(second.records.selectedDayKey == nil)
        #expect(second.records.expanded.isEmpty)
        #expect(second.focus.scale == .today)
        #expect(second.focus.dayTemplateName.isEmpty)
        #expect(!second.focus.namesDayTemplate)
        #expect(second.focus.quickCreateLanding == nil)
    }

    @Test("Two scenes submit only their edited time fields to the latest preferences")
    func independentTimeDrafts() throws {
        let suite = "SceneTimeDraft.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "ios.native.onboardingComplete")
        defaults.set(true, forKey: "ios.native.automaticCountdownMigrationCompleted")
        let store = AppRuntime(defaults: defaults, records: .inMemory())
        let first = SceneState()
        let second = SceneState()
        first.setDisplayedStartMinutes(8 * 60, using: store.preferences)
        second.setDisplayedEndMinutes(19 * 60, using: store.preferences)
        #expect(first.draftEndMinutes == nil)
        #expect(second.draftStartMinutes == nil)
        second.commitDisplayedHours(using: store.shifts)
        #expect(first.displayedEndMinutes(using: store.preferences) == 19 * 60)
        #expect(first.draftStartMinutes == 8 * 60)
        first.commitDisplayedHours(using: store.shifts)
        #expect(store.preferences.startMinutes == 8 * 60)
        #expect(store.preferences.endMinutes == 19 * 60)
        #expect(first.draftStartMinutes == nil)
        #expect(second.draftEndMinutes == nil)
    }

    @Test("A scene clears a valid draft another scene already committed without writing again")
    func fulfilledTimeDraftIsNoOpSuccess() throws {
        let suite = "SceneFulfilledDraft.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "ios.native.onboardingComplete")
        defaults.set(true, forKey: "ios.native.automaticCountdownMigrationCompleted")
        let store = AppRuntime(defaults: defaults, records: .inMemory())
        let first = SceneState()
        let second = SceneState()
        first.setDisplayedEndMinutes(19 * 60, using: store.preferences)
        second.setDisplayedEndMinutes(19 * 60, using: store.preferences)

        #expect(first.commitDisplayedHours(using: store.shifts).synchronousResult)
        let revision = store.records.revision
        #expect(second.commitDisplayedHours(using: store.shifts).synchronousResult)
        #expect(second.draftEndMinutes == nil)
        #expect(store.preferences.endMinutes == 19 * 60)
        #expect(store.records.revision == revision)
    }

    @Test("A repeated running start clears hours already fulfilled by another scene")
    func fulfilledStartDraftIsNoOpSuccess() throws {
        let suite = "SceneFulfilledStart.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "ios.native.onboardingComplete")
        defaults.set(true, forKey: "ios.native.automaticCountdownMigrationCompleted")
        defaults.set("UTC", forKey: "ios.native.recordsTimeZone")
        let store = AppRuntime(defaults: defaults, records: .inMemory())
        #expect(store.preferences.applyPreferences { $0.scheduleMode = .off }.synchronousResult)
        let first = SceneState()
        let second = SceneState()
        first.setDisplayedEndMinutes(18 * 60, using: store.preferences)
        second.setDisplayedEndMinutes(18 * 60, using: store.preferences)
        let date = try #require(store.preferences.recordsCalendar.date(from:
            DateComponents(year: 2026, month: 9, day: 7, hour: 10)))

        #expect(first.startCountdown(at: date, using: store.shifts).synchronousResult)
        let revision = store.records.revision
        let sessionID = store.session.sessionID
        #expect(second.startCountdown(at: date, using: store.shifts).synchronousResult)
        #expect(second.draftEndMinutes == nil)
        #expect(store.records.revision == revision)
        #expect(store.session.sessionID == sessionID)
    }

    @Test("Restarting rest-day manual timing invalidates old confirmation and expansion")
    func restDayRestartHasNewIdentity() throws {
        let suite = "SceneRestDayRestart.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // A new manual session is written in the device zone, so pin records to it:
        // a UTC pin puts 10:00 before the shift on runners west of UTC.
        defaults.set(TimeZone.current.identifier, forKey: "ios.native.recordsTimeZone")
        let store = AppRuntime(defaults: defaults, records: .inMemory())
        let scene = SceneState()
        let date = try #require(store.preferences.recordsCalendar.date(from:
            DateComponents(year: 2026, month: 9, day: 12, hour: 10)))
        #expect(store.shifts.startCountdown(force: true, at: date).synchronousResult)
        let shift = try #require(store.session.snapshot(at: date))
        let identity = store.session.sessionID
        scene.timelineExpandedBinding(for: shift, at: date, session: store.session).wrappedValue = true
        scene.requestClockOffEarly(at: date, using: store.shifts)
        #expect(store.shifts.cancelManualTiming().synchronousResult)
        #expect(store.shifts.startCountdown(force: true, at: date).synchronousResult)
        #expect(store.session.sessionID != identity)
        let restarted = try #require(store.session.snapshot(at: date))
        #expect(!scene.timelineExpanded(for: restarted, at: date, session: store.session))
        #expect(!scene.isClockOffConfirmationArmed(at: date, using: store.shifts))
    }

    @Test("Timer confirmations are scene-local and bind to the shift that was armed")
    func timerConfirmationContext() throws {
        let suite = "SceneTimerConfirmation.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "ios.native.onboardingComplete")
        defaults.set(true, forKey: "ios.native.automaticCountdownMigrationCompleted")
        defaults.set("UTC", forKey: "ios.native.recordsTimeZone")
        let store = AppRuntime(defaults: defaults, records: .inMemory())
        let first = SceneState()
        let second = SceneState()
        let date = try #require(store.preferences.recordsCalendar.date(from:
            DateComponents(year: 2026, month: 9, day: 7, hour: 10)))
        #expect(store.shifts.startCountdown(at: date).synchronousResult)

        first.requestClockOffEarly(at: date, using: store.shifts)
        #expect(first.isClockOffConfirmationArmed(at: date, using: store.shifts))
        #expect(!second.isClockOffConfirmationArmed(at: date, using: store.shifts))

        #expect(store.preferences.applyPreferences { $0.endMinutes = 19 * 60 }.synchronousResult)
        #expect(!first.isClockOffConfirmationArmed(at: date, using: store.shifts))
        first.requestClockOffEarly(at: date, using: store.shifts)
        #expect(store.session.earlyOffAtMs == nil)
        #expect(first.isClockOffConfirmationArmed(at: date, using: store.shifts))
    }

    @Test("Timer confirmation expiry is exact and an old timeout cannot cancel its replacement")
    func timerConfirmationExpiry() throws {
        let suite = "SceneTimerExpiry.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // A new manual session is written in the device zone, so pin records to it:
        // a UTC pin puts 10:00 before the shift on runners west of UTC.
        defaults.set(TimeZone.current.identifier, forKey: "ios.native.recordsTimeZone")
        let store = AppRuntime(defaults: defaults, records: .inMemory())
        let scene = SceneState()
        let date = try #require(store.preferences.recordsCalendar.date(from:
            DateComponents(year: 2026, month: 9, day: 12, hour: 10)))
        #expect(store.shifts.startCountdown(force: true, at: date).synchronousResult)

        scene.requestClockOffEarly(at: date, using: store.shifts)
        let oldID = try #require(scene.clockOffConfirmationID(at: date, using: store.shifts))
        #expect(scene.isClockOffConfirmationArmed(
            at: date.addingTimeInterval(4.999),
            using: store.shifts
        ))
        #expect(!scene.isClockOffConfirmationArmed(
            at: date.addingTimeInterval(5),
            using: store.shifts
        ))
        scene.requestClockOffEarly(at: date.addingTimeInterval(5), using: store.shifts)
        #expect(store.session.earlyOffAtMs == nil)
        let replacedID = try #require(scene.clockOffConfirmationID(
            at: date.addingTimeInterval(5),
            using: store.shifts
        ))
        #expect(replacedID != oldID)

        scene.requestCancelManualTiming(at: date.addingTimeInterval(6), using: store.shifts)
        let replacementID = try #require(scene.cancelManualTimingConfirmationID(
            at: date.addingTimeInterval(6),
            using: store.shifts
        ))
        #expect(replacementID != replacedID)
        scene.cancelTimerConfirmation(id: replacedID)
        #expect(scene.cancelManualTimingConfirmationID(
            at: date.addingTimeInterval(6),
            using: store.shifts
        ) == replacementID)
    }

    @Test("Timeline expansion follows one session and does not return for a new run with the same hours")
    func timelineExpansionSessionIdentity() throws {
        let suite = "SceneTimelineSession.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "ios.native.onboardingComplete")
        defaults.set(true, forKey: "ios.native.automaticCountdownMigrationCompleted")
        // A new manual session is written in the device zone, so pin records to it:
        // a UTC pin puts 10:00 before the shift on runners west of UTC.
        defaults.set(TimeZone.current.identifier, forKey: "ios.native.recordsTimeZone")
        let store = AppRuntime(defaults: defaults, records: .inMemory())
        #expect(store.preferences.applyPreferences { $0.scheduleMode = .off }.synchronousResult)
        let scene = SceneState()
        let date = try #require(store.preferences.recordsCalendar.date(from:
            DateComponents(year: 2026, month: 9, day: 7, hour: 10)))
        #expect(store.shifts.startCountdown(at: date).synchronousResult)
        let first = try #require(store.session.snapshot(at: date))
        let expansion = scene.timelineExpandedBinding(for: first, at: date, session: store.session)
        expansion.wrappedValue = true
        #expect(scene.timelineExpanded(for: first, at: date, session: store.session))
        #expect(scene.timelineExpanded(for: first, at: date, session: store.session))
        scene.requestClockOffEarly(at: date, using: store.shifts)
        #expect(scene.isClockOffConfirmationArmed(at: date, using: store.shifts))

        #expect(store.shifts.stopCountdown(at: date.addingTimeInterval(60)).synchronousResult)
        #expect(store.shifts.startCountdown(at: date.addingTimeInterval(120)).synchronousResult)
        let restarted = try #require(store.session.snapshot(at: date.addingTimeInterval(120)))
        #expect(!scene.timelineExpanded(
            for: restarted,
            at: date.addingTimeInterval(120),
            session: store.session
        ))
        #expect(!scene.isClockOffConfirmationArmed(
            at: date.addingTimeInterval(120),
            using: store.shifts
        ))
        scene.requestClockOffEarly(at: date.addingTimeInterval(120), using: store.shifts)
        #expect(store.session.earlyOffAtMs == nil)
    }

    @Test("A rejected timer start keeps the scene's edited hours")
    func rejectedStartKeepsDraft() throws {
        let suite = "SceneRejectedStart.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "ios.native.onboardingComplete")
        defaults.set(true, forKey: "ios.native.automaticCountdownMigrationCompleted")
        defaults.set("UTC", forKey: "ios.native.recordsTimeZone")
        let store = AppRuntime(defaults: defaults, records: .inMemory())
        let scene = SceneState()
        let date = try #require(store.preferences.recordsCalendar.date(from:
            DateComponents(year: 2026, month: 9, day: 7, hour: 10)))
        scene.draftEndMinutes = -1

        #expect(!scene.startCountdown(at: date, using: store.shifts).synchronousResult)
        #expect(scene.draftEndMinutes == -1)
        #expect(!store.session.countdownStarted)
        #expect(store.records.state.observations.isEmpty)
    }

    @Test("Scenes keep independent navigation, presentations and editing drafts")
    func independentScenes() {
        let first = SceneState()
        let second = SceneState()
        first.selectedTab = .settings
        first.settingsPath = [.salary]
        first.scheduleSettingsDraft.startMinutes = 480
        first.paywallSheet = .focus
        second.requestFocusActivityConfirmation(.stop, startAtMs: 1_788_775_200_000)
        #expect(first.selectedTab == .settings)
        #expect(first.settingsPath == [.salary])
        #expect(first.focusActivityRequest == nil)
        // A request waits for its scene to be free before it moves that scene's tab.
        #expect(second.focusActivityRequest != nil)
        #expect(second.selectedTab == .timer)
        second.activateFocusActivityPresentationIfPossible(isBlocked: false)
        #expect(first.selectedTab == .settings)
        #expect(second.selectedTab == .focus)
        #expect(second.settingsPath.isEmpty)
        #expect(second.scheduleSettingsDraft.isEmpty)
        #expect(second.paywallSheet == nil)
        #expect(second.dayEditor?.dayKey == nil)
    }

    @Test("A Focus deep link opens confirmation only in its receiving scene")
    func deepLinkDelivery() throws {
        let receiving = SceneState()
        let other = SceneState()
        receiving.settingsPath = [.language]
        receiving.focusPath = [.plus]
        let url = try #require(URL(string: "offworkcountdown://focus?action=stop&start=1788775200000"))
        receiving.handleOpenURL(url)
        #expect(receiving.focusActivityRequest == .init(action: .stop, startAtMs: 1_788_775_200_000))
        #expect(receiving.focusPath == [.plus])
        #expect(receiving.settingsPath == [.language])
        #expect(other.selectedTab == .timer)
        #expect(other.focusActivityRequest == nil)
        receiving.handleOpenURL(try #require(URL(string: "https://focus?action=stop&start=1")))
        #expect(receiving.focusActivityRequest?.startAtMs == 1_788_775_200_000)
    }

    @Test("The Apple Watch explainer is reachable as a settings route and listed as a Plus benefit")
    func appleWatchExplainerRoute() throws {
        let scene = SceneState()
        scene.settingsPath = [.language]
        scene.handleOpenURL(try #require(URL(string: "offworkcountdown://appleWatch")))
        #expect(scene.selectedTab == .settings)
        #expect(scene.settingsPath.isEmpty)
        #expect(scene.presentedRoute == .appleWatch)
        #expect(PlusBenefit.all.contains { $0.id == "watch" && $0.titleKey == "plusBenefitWatch" })
    }

    @Test("A Focus activity request waits without replacing an existing presentation")
    func focusActivityPresentationArbitration() {
        let scene = SceneState()
        scene.selectedTab = .settings
        scene.settingsPath = [.salary]
        scene.pendingPlusAction = .enableSync
        scene.paywallSheet = .sync
        scene.requestFocusActivityConfirmation(.stop, startAtMs: 42)

        scene.activateFocusActivityPresentationIfPossible(isBlocked: true)
        #expect(!scene.focusActivityPresentationReady)
        #expect(scene.selectedTab == .settings)
        #expect(scene.settingsPath == [.salary])
        #expect(scene.pendingPlusAction == .enableSync)
        #expect(scene.focusActivityRequest?.startAtMs == 42)

        scene.paywallSheet = nil
        scene.pendingPlusAction = nil
        scene.activateFocusActivityPresentationIfPossible(isBlocked: false)
        #expect(scene.focusActivityPresentationReady)
        #expect(scene.focusActivityRequest?.startAtMs == 42)
        #expect(scene.selectedTab == .focus)
        #expect(scene.settingsPath == [.salary])
    }

    @Test("A second Focus activity request waits for the visible confirmation")
    func focusActivityRequestsStayOrdered() {
        let scene = SceneState()
        scene.requestFocusActivityConfirmation(.stop, startAtMs: 41)
        scene.activateFocusActivityPresentationIfPossible(isBlocked: false)
        scene.requestFocusActivityConfirmation(.addPomodoros, startAtMs: 42)

        #expect(scene.focusActivityRequest == .init(action: .stop, startAtMs: 41))
        #expect(scene.focusActivityPresentationReady)

        scene.dismissFocusActivityAlert()
        #expect(scene.focusActivityRequest == .init(action: .addPomodoros, startAtMs: 42))
        #expect(!scene.focusActivityPresentationReady)
        scene.activateFocusActivityPresentationIfPossible(isBlocked: false)
        #expect(scene.focusActivityPresentationReady)
    }

    @Test("A queued Focus request waits for the previous sheet onDismiss")
    func focusActivitySheetDismissalOrdering() throws {
        let scene = SceneState()
        scene.requestFocusActivityConfirmation(.addPomodoros, startAtMs: 41)
        scene.activateFocusActivityPresentationIfPossible(isBlocked: false)

        let closingID = try #require(scene.beginDismissingFocusActivitySheet())
        #expect(scene.focusActivityRequest == nil)
        #expect(scene.hasFocusActivityPresentation)
        #expect(!scene.focusActivityPresentationReady)
        scene.requestFocusActivityConfirmation(.stop, startAtMs: 42)
        #expect(scene.focusActivityRequest == nil)

        scene.finishDismissingFocusActivitySheet(id: "stale-id")
        #expect(scene.focusActivityRequest == nil)
        scene.finishDismissingFocusActivitySheet(id: closingID)
        #expect(scene.focusActivityRequest == .init(action: .stop, startAtMs: 42))
        #expect(!scene.focusActivityPresentationReady)

        scene.activateFocusActivityPresentationIfPossible(isBlocked: false)
        #expect(scene.focusActivityPresentationReady)
        scene.finishDismissingFocusActivitySheet(id: closingID)
        #expect(scene.focusActivityRequest == .init(action: .stop, startAtMs: 42))
        #expect(scene.focusActivityPresentationReady)
    }

    @Test("Life setup is consumed only by a user choice and stays scene-local")
    func lifeSetupConsumption() throws {
        let suite = "LifeSetupConsumption.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runtime = AppRuntime(defaults: defaults, records: .inMemory())
        let first = SceneState()
        let second = SceneState()

        first.presentLifeSetupOffer()
        #expect(!runtime.preferences.lifeSetupPromptDismissed)
        #expect(first.lifeSetupOfferPresented)
        #expect(!second.lifeSetupOfferPresented)

        first.consumeLifeSetupOffer(preferences: runtime.preferences, opensEditor: true)
        #expect(runtime.preferences.lifeSetupPromptDismissed)
        #expect(!first.lifeSetupOfferPresented)
        #expect(first.lifeSetupEditorPresented)
    }

    @Test("Only one eligible scene claims a review prompt and a blocked scene does not consume it")
    func reviewPromptBelongsToTheClaimingScene() throws {
        let suite = "SceneReviewPrompt.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var review = AppReviewPromptState()
        review.noteCompletion(atMs: 1_000)
        defaults.set(try JSONEncoder().encode(review), forKey: "ios.native.appReviewPrompt.v1")
        defaults.set(true, forKey: "ios.native.onboardingComplete")
        let runtime = AppRuntime(defaults: defaults, records: .inMemory())
        runtime.plus.markIntroSeen()
        let first = SceneState()
        let second = SceneState()

        first.presentReviewPromptIfEligible(using: runtime.shifts, isBlocked: true)
        #expect(!first.reviewPromptPresented)
        second.presentReviewPromptIfEligible(using: runtime.shifts, isBlocked: false)
        #expect(second.reviewPromptPresented)
        first.presentReviewPromptIfEligible(using: runtime.shifts, isBlocked: false)
        #expect(!first.reviewPromptPresented)

        runtime.shifts.deferReviewPrompt()
        second.reviewPromptPresented = false
        second.presentReviewPromptIfEligible(using: runtime.shifts, isBlocked: false)
        #expect(!second.reviewPromptPresented)
        let saved = try JSONDecoder().decode(AppReviewPromptState.self,
            from: #require(defaults.data(forKey: "ios.native.appReviewPrompt.v1")))
        #expect(saved.phase == .waitingForCompletion)
    }

    @Test("Remembering the last tab does not drive another existing scene")
    func remembersInitialTab() throws {
        let suite = "SceneInitialTab.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("records", forKey: "ios.native.selectedTab")
        let first = SceneState(defaults: defaults)
        let second = SceneState(defaults: defaults)
        #expect(first.selectedTab == .records)
        first.selectedTab = .settings
        #expect(second.selectedTab == .records)
        #expect(SceneState(defaults: defaults).selectedTab == .settings)
    }
}
