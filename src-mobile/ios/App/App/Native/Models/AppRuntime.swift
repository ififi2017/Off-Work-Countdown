import Foundation

/// Owns process dependencies; scenes own navigation and drafts, feature
/// objects own their actions. System entry points share this same assembly.
@MainActor
final class AppRuntime {
    private struct SharedLoad {
        let id: UUID
        let task: Task<AppRuntime, Error>
    }
    private static var sharedRuntime: AppRuntime?
    private static var sharedLoad: SharedLoad?

    static func loadShared() async throws -> AppRuntime {
        if let sharedRuntime { return sharedRuntime }
        if let sharedLoad { return try await sharedLoad.task.value }
        let id = UUID()
        let task = Task { @MainActor in
            let runtime: AppRuntime
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-owcPerformanceFixture"),
               let fixtureDefaults = UserDefaults(suiteName: "owc.performance.fixture") {
                fixtureDefaults.removePersistentDomain(forName: "owc.performance.fixture")
                runtime = AppRuntime(defaults: fixtureDefaults)
            } else {
                runtime = try await load(
                    defaults: .standard,
                    archiveURL: RecordCoordinator.persistedArchiveURL
                )
            }
#else
            runtime = try await load(
                defaults: .standard,
                archiveURL: RecordCoordinator.persistedArchiveURL
            )
#endif
            runtime.services.start()
            return runtime
        }
        sharedLoad = SharedLoad(id: id, task: task)
        do {
            let runtime = try await task.value
            guard sharedLoad?.id == id else { return runtime }
            sharedRuntime = runtime
            sharedLoad = nil
            return runtime
        } catch {
            if sharedLoad?.id == id { sharedLoad = nil }
            throw error
        }
    }

    static func load(
        defaults: UserDefaults,
        archiveURL: URL,
        archiveReset: @escaping @Sendable (URL) async throws -> Void = resetArchiveFile
    ) async throws -> AppRuntime {
        try await prepareArchiveDirectory(for: archiveURL)
        var didReset = false
#if DEBUG
        if defaults.bool(forKey: DebugScenarioController.resetKey) {
            try await archiveReset(archiveURL)
            clear(defaults)
            didReset = true
        }
#endif
        let loadedArchive = await RecordArchive.load(from: archiveURL)
        return LaunchTrace.interval("storeInit") {
            AppRuntime(
                defaults: defaults,
                records: RecordCoordinator(fileURL: archiveURL, loadedArchive: loadedArchive),
                debugDidResetOnLaunch: didReset
            )
        }
    }

    @concurrent
    nonisolated private static func prepareArchiveDirectory(for fileURL: URL) async throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    @concurrent
    nonisolated static func resetArchiveFile(at fileURL: URL) async throws {
        let prepared = try await RecordArchive.prepare(RecordState(), for: fileURL)
        do {
            try await RecordArchive.publishPrepared(prepared, at: fileURL)
        } catch {
            await RecordArchive.discardPrepared(prepared)
            throw error
        }
    }

    private static func clear(_ defaults: UserDefaults) {
        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }
    }

    let notifications = NotificationService()
    let liveActivities = LiveActivityService()
    let watchSnapshots = WatchSnapshotPublisher()
    private(set) lazy var services = ServiceCoordinator(operations: .app(
        shifts: shifts, recovery: recovery, notifications: notifications, liveActivities: liveActivities,
        watchSnapshots: watchSnapshots,
        debugDidResetOnLaunch: debugDidResetOnLaunch
    ))

    private(set) lazy var recordActions: RecordsActions = {
        let session = session
        return RecordsActions(records: records, preferences: preferences, plus: plus,
            text: text, currentHours: { session.hoursConfiguration(at: $0) })
    }()

    private(set) lazy var shifts = ShiftSessionStore(
        session: session, records: records, queries: queries,
        focus: focus, plus: plus, defaults: defaults
    )

    private(set) lazy var queries: RecordsQueries = {
        let session = session
        let preferences = preferences
        return RecordsQueries(records: records, plus: plus, localizer: text.localizer, sources: .init(
            calendar: { preferences.recordsCalendar },
            hours: { session.hoursConfiguration(at: $0) },
            rules: { date, source in session.rulesInput(at: date, using: source) },
            snapshot: { session.snapshot(at: $0) },
            isCounting: { session.countdownStarted },
            salaryIsVisible: { session.presentationSalaryEnabled },
            salaryType: { preferences.salaryType },
            language: { preferences.languageCode }
        ))
    }()

    private(set) lazy var life: LifeSummaryModel = {
        let session = session
        let preferences = preferences
        return LifeSummaryModel(queries: queries, readPreferences: { date in
            LifeSummaryPreferences(hours: session.hoursConfiguration(at: date),
                salary: LifeSalaryPreferences(amount: preferences.salaryAmount, enabled: preferences.salaryEnabled,
                    type: preferences.salaryType.rawValue, workingDays: preferences.monthlyWorkingDays,
                    bonusMonths: preferences.annualBonusEnabled ? preferences.annualBonusMonths : 0))
        })
    }()

    private(set) lazy var focus: FocusStore = {
        let session = session
        let preferences = preferences
        let text = text
        return FocusStore(records: records, defaults: defaults, plus: plus, sources: .init(
            calendar: { preferences.recordsCalendar },
            snapshot: { session.snapshot(at: $0) },
            scheduleEnabled: { date in session.effectiveScheduleMode(at: date) != .off || session.countdownStarted },
            shouldQuerySnapshot: { session.shouldQuerySnapshot(at: $0) },
            isWorkday: { shift, date in
                !session.isEndedEarly(shift) && (shift.isWorkday || session.isForcedWorkday(shift)
                    || (session.effectiveScheduleMode(at: date) == .off && session.countdownStarted))
            },
            overtimeEnd: { session.overtimeEndAtMs },
            microBreakEnabled: { preferences.microBreakEnabled },
            text: { key, values in text.t(key, values: values) },
            count: { text.formatCount($0) },
            time: { text.formatTime($0) }
        ))
    }()

    private enum Key {
#if DEBUG
        static let qaDebugScenario = "ios.native.qaDebugScenario"
        static let qaRoute = "ios.native.qaRoute"
        static let qaRecordsRoute = "ios.native.qaRecordsRoute"
        static let qaRecordsScale = "ios.native.qaRecordsScale"
        static let qaFocusScenario = "ios.native.qaFocusScenario"
#endif
        static let theme = "theme"
        static let languageOverride = "ios.native.languageOverride"
    }

    let text: AppText
    let session: ShiftSession
    let records: RecordCoordinator
    let preferences: PreferencesStore
    let plus: PlusEntitlement
    let recovery: RecoveryStore
    let defaults: UserDefaults
    private(set) var debugDidResetOnLaunch = false
#if DEBUG
    private(set) lazy var debug = DebugScenarioController(shifts: shifts, defaults: defaults, actions: recordActions, life: life)
#endif


    init(
        defaults: UserDefaults = .standard,
        records: RecordCoordinator? = nil,
        debugDidResetOnLaunch: Bool = false
    ) {
#if DEBUG
        let debugRoute = AppRoute(rawValue: defaults.string(forKey: Key.qaRoute) ?? "")
        let debugRecordsRoute = RecordsRoute.debugRoute(
            defaults.string(forKey: Key.qaRecordsRoute)
        )
        let debugRecordsScale = RecordsScale(
            rawValue: defaults.string(forKey: Key.qaRecordsScale) ?? ""
        )
        let debugScenario = DebugTimerScenario(
            rawValue: defaults.string(forKey: Key.qaDebugScenario) ?? ""
        )
        let debugFocusScenario = defaults.string(forKey: Key.qaFocusScenario)
#endif
        self.defaults = defaults
        self.debugDidResetOnLaunch = debugDidResetOnLaunch
        self.records = records ?? RecordCoordinator.inMemory()
        self.plus = PlusEntitlement(defaults: defaults)
        self.preferences = PreferencesStore(defaults: defaults, records: self.records)
        self.text = AppText(preferences: self.preferences)
        self.session = ShiftSession(defaults: defaults, preferences: self.preferences, text: self.text)
        self.recovery = RecoveryStore(records: self.records, preferences: self.preferences, plus: self.plus, defaults: defaults)
        _ = focus
        _ = shifts
#if DEBUG
        // Screenshot launch arguments deliberately override the persisted
        // appearance, including preferences restored from the record archive.
        let launchPreferences = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        if let requestedTheme = launchPreferences[Key.theme] as? String,
           let requestedTheme = AppTheme(rawValue: requestedTheme) {
            preferences.applyPreferences { $0.theme = requestedTheme }
        }
        if let requestedLanguage = launchPreferences[Key.languageOverride] as? String,
           NativeLocalizer.supportedLanguages.contains(where: { $0.id == requestedLanguage }) {
            preferences.applyPreferences { $0.languageOverride = requestedLanguage }
        }
#endif
        _ = focus.carryIncompleteFocusTasks(at: .now)
#if DEBUG
        if let debugRoute {
            if debugRoute == .focus || debugRoute == .focusPlan {
                // Focus QA uses the same realistic sample archive as Records.
                // Keep this behind DEBUG so release launches never synthesize
                // user tasks or history.
                _ = debug.debugSeedSampleRecords()
            }
        }
        if let debugRecordsRoute {
            // Charts, Life and day detail all render from stored records, so a
            // route with an empty store would only ever screenshot empty states.
            _ = debug.debugSeedSampleRecords()
            if case .conflictCenter = debugRecordsRoute {
                Task { await debug.debugSeedSampleConflict(at: .now) }
            }
        }
        if debugRecordsScale != nil {
            _ = debug.debugSeedSampleRecords()
        }
        if let debugScenario {
            debug.activateDebugTimerScenario(debugScenario)
        }
        if let debugFocusScenario, !debugFocusScenario.isEmpty {
            defaults.removeObject(forKey: Key.qaFocusScenario)
            _ = focus.activateDebugFocusScenario(debugFocusScenario, at: .now)
        }
#endif
        // Reconcile imported data even when no scene has ever mounted. Captures
        // retain only feature owners, never the runtime or record coordinator.
        let preferences = preferences
        let life = life
        let focus = focus
        let shifts = shifts
        self.records.onExternalStateApplied = { [weak preferences, weak life, weak focus, weak shifts] in
            let previousPreferences = preferences?.currentSyncedPreferences()
            preferences?.reloadFromArchive()
            if let previousPreferences, let shifts {
                _ = shifts.reconcileExternalState(from: previousPreferences).synchronousResult
            }
            life?.reconcileExternalState(at: .now)
            _ = focus?.reconcileExternalState(at: .now)
        }
        // StoreKit's own failures arrive already localized by the system. The
        // one message the entitlement layer writes itself has to follow the
        // in-app language choice, provided by the committed preferences.
        let text = text
        self.plus.localize = { key in text.t(key) }
    }
}
