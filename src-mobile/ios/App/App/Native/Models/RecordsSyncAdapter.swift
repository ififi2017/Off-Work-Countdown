import Foundation

enum SyncOutboxAction: String, Codable, Sendable {
    case save
    case erasePair
}

struct SyncAdapterRow: Equatable, Codable, Sendable {
    var entityType: RecordEntityType
    var logicalKey: String
    var recordName: String
    var dirty: Bool
    var generation: Int
    var lastKnownRecord: Data?
    var lastKnownErasedRecord: Data? = nil
    var lastKnownPayload: Data?
    var pendingErase: Bool
    /// This row was recorded again after being erased, so the push has to
    /// delete the `erased.*` record as well as save the data record. Optional
    /// because archives written before revocation existed must still decode.
    var pendingEraseRevocation: Bool? = nil
    var editCount: Int
    var editTieBreaker: String

    var revokesErase: Bool { pendingEraseRevocation == true }
}

struct SyncConflictCopy: Equatable, Codable, Sendable {
    enum Winner: String, Codable, Sendable {
        case local
        case incoming
        /// Archives written before both sides were retained. The UI must not
        /// invent a local/cloud label for this case.
        case unknown
    }

    var id: UUID = UUID()
    var entityType: RecordEntityType
    var logicalKey: String
    /// Legacy alternate payload. Kept so old local archives remain readable.
    var payload: Data
    var lostAtMs: Double
    /// `import` when parked from a file import; nil for CloudKit copies.
    var source: String? = nil
    /// Both concrete candidates, when the conflict was produced by a current
    /// build. `payload` remains the fallback alternate for old archives.
    var localPayload: Data? = nil
    var incomingPayload: Data? = nil
    var baselinePayload: Data? = nil
    var localEditedAtMs: Double? = nil
    var incomingEditedAtMs: Double? = nil
    var currentWinner: Winner = .unknown

    var effectiveIncomingPayload: Data { incomingPayload ?? payload }

    /// The payload that is not currently applied. Older archives retained only
    /// `payload`, which is therefore presented as a neutral “other version”.
    var effectiveAlternatePayload: Data {
        switch currentWinner {
        case .local:
            return incomingPayload ?? payload
        case .incoming:
            return localPayload ?? payload
        case .unknown:
            return payload
        }
    }

    var effectiveCurrentPayload: Data {
        switch currentWinner {
        case .local: return localPayload ?? payload
        case .incoming: return incomingPayload ?? payload
        case .unknown: return payload
        }
    }

    /// Immutable history rows are intentionally whole-version choices. For
    /// editable records, each JSON field is a selectable value; array/object
    /// fields (for example shift segments) stay atomic by construction.
    var supportsFieldMerge: Bool {
        switch entityType {
        case .workObservation, .focusSession, .scheduleSnapshot, .focusPlanningConfiguration,
             .syncedPreferences:
            return false
        default:
            return localPayload != nil && incomingPayload != nil
        }
    }

    init(
        id: UUID = UUID(),
        entityType: RecordEntityType,
        logicalKey: String,
        payload: Data,
        lostAtMs: Double,
        source: String? = nil,
        localPayload: Data? = nil,
        incomingPayload: Data? = nil,
        baselinePayload: Data? = nil,
        localEditedAtMs: Double? = nil,
        incomingEditedAtMs: Double? = nil,
        currentWinner: Winner = .unknown
    ) {
        self.id = id
        self.entityType = entityType
        self.logicalKey = logicalKey
        self.payload = payload
        self.lostAtMs = lostAtMs
        self.source = source
        self.localPayload = localPayload
        self.incomingPayload = incomingPayload
        self.baselinePayload = baselinePayload
        self.localEditedAtMs = localEditedAtMs
        self.incomingEditedAtMs = incomingEditedAtMs
        self.currentWinner = currentWinner
    }

    private enum CodingKeys: String, CodingKey {
        case id, entityType, logicalKey, payload, lostAtMs, source
        case localPayload, incomingPayload, baselinePayload
        case localEditedAtMs, incomingEditedAtMs, currentWinner
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        entityType = try container.decode(RecordEntityType.self, forKey: .entityType)
        logicalKey = try container.decode(String.self, forKey: .logicalKey)
        payload = try container.decode(Data.self, forKey: .payload)
        lostAtMs = try container.decode(Double.self, forKey: .lostAtMs)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        localPayload = try container.decodeIfPresent(Data.self, forKey: .localPayload)
        incomingPayload = try container.decodeIfPresent(Data.self, forKey: .incomingPayload)
        baselinePayload = try container.decodeIfPresent(Data.self, forKey: .baselinePayload)
        localEditedAtMs = try container.decodeIfPresent(Double.self, forKey: .localEditedAtMs)
        incomingEditedAtMs = try container.decodeIfPresent(Double.self, forKey: .incomingEditedAtMs)
        currentWinner = try container.decodeIfPresent(Winner.self, forKey: .currentWinner) ?? .unknown
    }
}

struct SyncLocalState: Equatable, Codable, Sendable {
    var accountID: String?
    var generation: Int
    var syncEnabled: Bool
    var engineState: Data?
    var rows: [String: SyncAdapterRow]
    var conflicts: [SyncConflictCopy]
    var deletingCloud: Bool

    static let empty = SyncLocalState(
        accountID: nil,
        generation: 1,
        syncEnabled: false,
        engineState: nil,
        rows: [:],
        conflicts: [],
        deletingCloud: false
    )
}

enum RecordsSyncIdentity {
    static let controlZone = "owc-control"
    static let fenceRecord = "fence"

    static func dataZone(generation: Int) -> String {
        "owc-records.\(generation)"
    }

    static func generation(fromZoneName name: String) -> Int? {
        let prefix = "owc-records."
        guard name.hasPrefix(prefix) else { return nil }
        return Int(name.dropFirst(prefix.count))
    }

    static func recordName(type: RecordEntityType, key: String) -> String {
        switch type {
        case .dayOverride: return "day.\(key)"
        case .calendarException: return "calx.\(key)"
        case .lifeProfile: return "profile"
        case .careerPeriod: return "period.\(key.lowercased())"
        case .scheduleSnapshot: return "snapshot.\(key.lowercased())"
        case .workObservation: return "obs.\(key.lowercased())"
        case .focusTask: return "task.\(key.lowercased())"
        case .focusSession: return "session.\(key.lowercased())"
        case .focusPlanningConfiguration: return FocusPlanningConfiguration.logicalKey
        case .syncedPreferences: return SyncedPreferences.logicalKey
        }
    }

    static func erasedName(type: RecordEntityType, key: String) -> String {
        "erased.\(type.rawValue).\(key)"
    }
}

enum RecordsSyncConflict {
    /// Winner = larger editCount; tie uses larger editTieBreaker string.
    static func localWins(
        localCount: Int,
        localTie: String,
        serverCount: Int,
        serverTie: String
    ) -> Bool {
        if localCount != serverCount { return localCount > serverCount }
        return localTie > serverTie
    }

    /// Chooses a business version without asking the user whenever the edit
    /// history gives us a meaningful ordering.
    ///
    /// `editCount` is authoritative across devices. Equal counts describe two
    /// edits made from the same revision, so the later user edit wins. Only an
    /// exact count-and-time tie is ambiguous enough to require review; the
    /// random tie-breaker still keeps the currently applied copy deterministic
    /// while that review is pending, but is never presented as user intent.
    static func automaticallyPreferredWinner(
        localCount: Int,
        localEditedAtMs: Double?,
        incomingCount: Int,
        incomingEditedAtMs: Double?
    ) -> SyncConflictCopy.Winner? {
        if localCount != incomingCount {
            return localCount > incomingCount ? .local : .incoming
        }
        guard let localEditedAtMs, let incomingEditedAtMs,
              localEditedAtMs != incomingEditedAtMs
        else { return nil }
        return localEditedAtMs > incomingEditedAtMs ? .local : .incoming
    }

    static func mergeLifeProfile(
        local: LifeProfile,
        server: LifeProfile,
        baseline: LifeProfile?
    ) -> LifeProfile {
        let automaticWinner = automaticallyPreferredWinner(
            localCount: local.editCount,
            localEditedAtMs: local.editedAt.timeIntervalSince1970 * 1_000,
            incomingCount: server.editCount,
            incomingEditedAtMs: server.editedAt.timeIntervalSince1970 * 1_000
        )
        let localWinsOverall = automaticWinner == .local || (
            automaticWinner == nil
            && localWins(
                localCount: local.editCount,
                localTie: local.editTieBreaker.uuidString,
                serverCount: server.editCount,
                serverTie: server.editTieBreaker.uuidString
            )
        )
        var merged = server
        var conflicted = false
        func take<T: Equatable>(_ localValue: T, _ serverValue: T, _ baselineValue: T?) -> T {
            let localChanged = localValue != baselineValue
            let serverChanged = serverValue != baselineValue
            switch (localChanged, serverChanged) {
            case (true, false):
                return localValue
            case (false, true):
                return serverValue
            case (true, true) where localValue != serverValue:
                conflicted = true
                return localWinsOverall ? localValue : serverValue
            default:
                return serverValue
            }
        }
        merged.birthYear = take(local.birthYear, server.birthYear, baseline?.birthYear)
        merged.workStartedOn = take(local.workStartedOn, server.workStartedOn, baseline?.workStartedOn)
        merged.retirementAge = take(local.retirementAge, server.retirementAge, baseline?.retirementAge)
        merged.averageSleepHours = take(local.averageSleepHours, server.averageSleepHours, baseline?.averageSleepHours)
        merged.hidesExactAges = take(local.hidesExactAges, server.hidesExactAges, baseline?.hidesExactAges)
        merged.bornOn = take(local.bornOn, server.bornOn, baseline?.bornOn)
        merged.schoolStartedOn = take(local.schoolStartedOn, server.schoolStartedOn, baseline?.schoolStartedOn)
        merged.workStartedPartial = take(local.workStartedPartial, server.workStartedPartial, baseline?.workStartedPartial)
        merged.retirementOn = take(local.retirementOn, server.retirementOn, baseline?.retirementOn)
        merged.averageSleepMinutes = take(local.averageSleepMinutes, server.averageSleepMinutes, baseline?.averageSleepMinutes)
        merged.sleepSource = take(local.sleepSource, server.sleepSource, baseline?.sleepSource)
        merged.sleepSourceUpdatedAt = take(local.sleepSourceUpdatedAt, server.sleepSourceUpdatedAt, baseline?.sleepSourceUpdatedAt)
        merged.workHistoryMode = take(local.workHistoryMode, server.workHistoryMode, baseline?.workHistoryMode)
        merged.roughCurrentSalary = take(local.roughCurrentSalary, server.roughCurrentSalary, baseline?.roughCurrentSalary)
        merged.employmentPeriods = take(local.employmentPeriods, server.employmentPeriods, baseline?.employmentPeriods)
        merged.futureIncomeDecline = take(
            local.futureIncomeDecline,
            server.futureIncomeDecline,
            baseline?.futureIncomeDecline
        )
        merged.editCount = max(local.editCount, server.editCount) + (conflicted ? 1 : 0)
        merged.editTieBreaker = conflicted
            ? UUID()
            : (localWinsOverall ? local.editTieBreaker : server.editTieBreaker)
        merged.editedAt = max(local.editedAt, server.editedAt)
        return merged
    }

    static func focusPlanningContentIsEqual(
        _ lhs: FocusPlanningConfiguration,
        _ rhs: FocusPlanningConfiguration
    ) -> Bool {
        lhs.planning == rhs.planning
            && lhs.timerSettings.normalized == rhs.timerSettings.normalized
    }

    /// Planning is one CloudKit identity but not one merge field. Templates
    /// merge by UUID, plans by civil day, and cadence values independently.
    /// A same-key concurrent edit still converges deterministically: revision
    /// count first, then the user edit time, with the random tie-breaker only
    /// for an exact timestamp tie.
    static func mergeFocusPlanningConfiguration(
        local: FocusPlanningConfiguration,
        server: FocusPlanningConfiguration,
        baseline: FocusPlanningConfiguration?
    ) -> FocusPlanningConfiguration {
        let automaticWinner = automaticallyPreferredWinner(
            localCount: local.editCount,
            localEditedAtMs: local.editedAt.timeIntervalSince1970 * 1_000,
            incomingCount: server.editCount,
            incomingEditedAtMs: server.editedAt.timeIntervalSince1970 * 1_000
        )
        let localWinsOverall = automaticWinner == .local || (
            automaticWinner == nil
            && localWins(
                localCount: local.editCount,
                localTie: local.editTieBreaker.uuidString,
                serverCount: server.editCount,
                serverTie: server.editTieBreaker.uuidString
            )
        )
        func take<T: Equatable>(_ localValue: T, _ serverValue: T, _ baselineValue: T?) -> T {
            let localChanged = baselineValue.map { localValue != $0 } ?? true
            let serverChanged = baselineValue.map { serverValue != $0 } ?? true
            switch (localChanged, serverChanged) {
            case (true, false): return localValue
            case (false, true): return serverValue
            case (true, true) where localValue != serverValue:
                return localWinsOverall ? localValue : serverValue
            default: return serverValue
            }
        }
        func takeOptional<T: Equatable>(_ localValue: T?, _ serverValue: T?, _ baselineValue: T?) -> T? {
            let localChanged = localValue != baselineValue
            let serverChanged = serverValue != baselineValue
            switch (localChanged, serverChanged) {
            case (true, false): return localValue
            case (false, true): return serverValue
            case (true, true) where localValue != serverValue:
                return localWinsOverall ? localValue : serverValue
            default: return serverValue
            }
        }

        let baselineSettings = baseline?.timerSettings.normalized ?? .default
        let localSettings = local.timerSettings.normalized
        let serverSettings = server.timerSettings.normalized
        let settings = FocusTimerSettings(
            focusMinutes: take(localSettings.focusMinutes, serverSettings.focusMinutes, baselineSettings.focusMinutes),
            shortBreakMinutes: take(localSettings.shortBreakMinutes, serverSettings.shortBreakMinutes, baselineSettings.shortBreakMinutes),
            longBreakMinutes: take(localSettings.longBreakMinutes, serverSettings.longBreakMinutes, baselineSettings.longBreakMinutes),
            longBreakEvery: take(localSettings.longBreakEvery, serverSettings.longBreakEvery, baselineSettings.longBreakEvery)
        ).normalized

        let localTemplates = Dictionary(uniqueKeysWithValues: local.planning.templates.map { ($0.id, $0) })
        let serverTemplates = Dictionary(uniqueKeysWithValues: server.planning.templates.map { ($0.id, $0) })
        let baselineTemplates = Dictionary(uniqueKeysWithValues: (baseline?.planning.templates ?? []).map { ($0.id, $0) })
        let templateIDs = Set(localTemplates.keys).union(serverTemplates.keys).union(baselineTemplates.keys)
        let templates = templateIDs.compactMap { id in
            takeOptional(localTemplates[id], serverTemplates[id], baselineTemplates[id])
        }.sorted { $0.id.uuidString < $1.id.uuidString }

        let planKeys = Set(local.planning.plans.keys)
            .union(server.planning.plans.keys)
            .union(Set(baseline?.planning.plans.keys.map { $0 } ?? []))
        var plans: [String: FocusDayPlan] = [:]
        for key in planKeys {
            plans[key] = takeOptional(
                local.planning.plans[key],
                server.planning.plans[key],
                baseline?.planning.plans[key]
            )
        }

        let templateIDsAfterMerge = Set(templates.map(\.id))
        let defaultTemplateID = takeOptional(
            local.planning.defaultTemplateID,
            server.planning.defaultTemplateID,
            baseline?.planning.defaultTemplateID
        ).flatMap { templateIDsAfterMerge.contains($0) ? $0 : nil }

        return FocusPlanningConfiguration(
            planning: FocusPlanningState(
                plans: plans,
                templates: templates,
                defaultTemplateID: defaultTemplateID,
                autoAppliedDayKeys: local.planning.autoAppliedDayKeys.union(server.planning.autoAppliedDayKeys)
            ),
            timerSettings: settings,
            editedAt: max(local.editedAt, server.editedAt),
            editCount: max(local.editCount, server.editCount) + 1,
            editTieBreaker: UUID()
        )
    }

    static func mergeSyncedPreferences(
        local: SyncedPreferences,
        server: SyncedPreferences,
        baseline: SyncedPreferences?
    ) -> SyncedPreferences {
        let automaticWinner = automaticallyPreferredWinner(
            localCount: local.editCount,
            localEditedAtMs: local.editedAt.timeIntervalSince1970 * 1_000,
            incomingCount: server.editCount,
            incomingEditedAtMs: server.editedAt.timeIntervalSince1970 * 1_000
        )
        let localWinsOverall = automaticWinner == .local || (
            automaticWinner == nil
            && localWins(
                localCount: local.editCount,
                localTie: local.editTieBreaker.uuidString,
                serverCount: server.editCount,
                serverTie: server.editTieBreaker.uuidString
            )
        )
        func take<T: Equatable>(_ localValue: T, _ serverValue: T, _ baselineValue: T?) -> T {
            let localChanged = baselineValue.map { localValue != $0 } ?? true
            let serverChanged = baselineValue.map { serverValue != $0 } ?? true
            switch (localChanged, serverChanged) {
            case (true, false): return localValue
            case (false, true): return serverValue
            case (true, true) where localValue != serverValue:
                return localWinsOverall ? localValue : serverValue
            default: return serverValue
            }
        }
        func takeOptional<T: Equatable>(
            _ localValue: T?,
            _ serverValue: T?,
            _ baselineValue: T??
        ) -> T? {
            let baselineExists = baselineValue != nil
            let baselineValue = baselineValue ?? nil
            let localChanged = !baselineExists || localValue != baselineValue
            let serverChanged = !baselineExists || serverValue != baselineValue
            switch (localChanged, serverChanged) {
            case (true, false): return localValue
            case (false, true): return serverValue
            case (true, true) where localValue != serverValue:
                return localWinsOverall ? localValue : serverValue
            default: return serverValue
            }
        }

        return SyncedPreferences(
            startMinutes: take(local.startMinutes, server.startMinutes, baseline?.startMinutes),
            endMinutes: take(local.endMinutes, server.endMinutes, baseline?.endMinutes),
            workdays: take(local.workdays, server.workdays, baseline?.workdays),
            scheduleMode: take(local.scheduleMode, server.scheduleMode, baseline?.scheduleMode),
            alternatingWeekType: take(local.alternatingWeekType, server.alternatingWeekType, baseline?.alternatingWeekType),
            alternatingWeekendWorkday: take(local.alternatingWeekendWorkday, server.alternatingWeekendWorkday, baseline?.alternatingWeekendWorkday),
            alternatingReferenceWeekStartMs: take(local.alternatingReferenceWeekStartMs, server.alternatingReferenceWeekStartMs, baseline?.alternatingReferenceWeekStartMs),
            rotationWorkDays: take(local.rotationWorkDays, server.rotationWorkDays, baseline?.rotationWorkDays),
            rotationRestDays: take(local.rotationRestDays, server.rotationRestDays, baseline?.rotationRestDays),
            rotationAnchorMs: take(local.rotationAnchorMs, server.rotationAnchorMs, baseline?.rotationAnchorMs),
            lunchEnabled: take(local.lunchEnabled, server.lunchEnabled, baseline?.lunchEnabled),
            lunchStartMinutes: take(local.lunchStartMinutes, server.lunchStartMinutes, baseline?.lunchStartMinutes),
            lunchDurationMinutes: take(local.lunchDurationMinutes, server.lunchDurationMinutes, baseline?.lunchDurationMinutes),
            recordsTimeZoneIdentifier: take(local.recordsTimeZoneIdentifier, server.recordsTimeZoneIdentifier, baseline?.recordsTimeZoneIdentifier),
            salaryAmount: take(local.salaryAmount, server.salaryAmount, baseline?.salaryAmount),
            salaryEnabled: take(local.salaryEnabled, server.salaryEnabled, baseline?.salaryEnabled),
            salaryType: take(local.salaryType, server.salaryType, baseline?.salaryType),
            monthlyWorkingDays: take(local.monthlyWorkingDays, server.monthlyWorkingDays, baseline?.monthlyWorkingDays),
            annualBonusEnabled: take(local.annualBonusEnabled, server.annualBonusEnabled, baseline?.annualBonusEnabled),
            annualBonusMonths: take(local.annualBonusMonths, server.annualBonusMonths, baseline?.annualBonusMonths),
            notificationMode: take(local.notificationMode, server.notificationMode, baseline?.notificationMode),
            cycleEndSummaryNotificationEnabled: take(local.cycleEndSummaryNotificationEnabled, server.cycleEndSummaryNotificationEnabled, baseline?.cycleEndSummaryNotificationEnabled),
            lunchStartReminderEnabled: take(local.lunchStartReminderEnabled, server.lunchStartReminderEnabled, baseline?.lunchStartReminderEnabled),
            lunchEndReminderEnabled: take(local.lunchEndReminderEnabled, server.lunchEndReminderEnabled, baseline?.lunchEndReminderEnabled),
            microBreakEnabled: take(local.microBreakEnabled, server.microBreakEnabled, baseline?.microBreakEnabled),
            microBreakIntervalMinutes: take(local.microBreakIntervalMinutes, server.microBreakIntervalMinutes, baseline?.microBreakIntervalMinutes),
            theme: take(local.theme, server.theme, baseline?.theme),
            languageOverride: takeOptional(
                local.languageOverride,
                server.languageOverride,
                baseline.map(\.languageOverride)
            ),
            editedAtMs: max(local.editedAtMs, server.editedAtMs),
            editCount: max(local.editCount, server.editCount) + 1,
            editTieBreaker: UUID()
        )
    }

    private static let syncMetadataKeys = Set(["editCount", "editTieBreaker", "editedAt", "editedAtMs"])

    /// JSON encoders may emit different byte order for equivalent objects.
    /// Compare the decoded business dictionary and deliberately ignore only
    /// revision metadata; structural fields remain part of identity safety.
    static func payloadsHaveSameBusinessContent(_ lhs: Data, _ rhs: Data) -> Bool {
        guard var left = (try? JSONSerialization.jsonObject(with: lhs)) as? [String: Any],
              var right = (try? JSONSerialization.jsonObject(with: rhs)) as? [String: Any]
        else { return false }
        for key in syncMetadataKeys {
            left.removeValue(forKey: key)
            right.removeValue(forKey: key)
        }
        return NSDictionary(dictionary: left).isEqual(to: right)
    }

    /// Three-way merge only the entities whose payload relationships are
    /// explicitly modelled here. Internal history rows and career boundaries
    /// remain whole-version choices; guessing their field relationships can
    /// manufacture an invalid record.
    static func automaticallyMergedPayload(
        local: Data,
        server: Data,
        baseline: Data?,
        type: RecordEntityType
    ) -> Data? {
        guard let baseline,
              var localValues = (try? JSONSerialization.jsonObject(with: local)) as? [String: Any],
              let serverValues = (try? JSONSerialization.jsonObject(with: server)) as? [String: Any],
              let baselineValues = (try? JSONSerialization.jsonObject(with: baseline)) as? [String: Any]
        else { return nil }

        let groups: [Set<String>]
        let editable: Set<String>
        let structural: Set<String>
        switch type {
        case .dayOverride:
            groups = [["kind", "segments"]]
            editable = ["kind", "segments", "note"]
            structural = ["dayKey", "timeZoneIdentifier"]
        case .calendarException:
            groups = [["effect", "isCleared"]]
            editable = ["effect", "isCleared", "label"]
            structural = ["dayKey", "date", "origin", "regionIdentifier", "datasetVersion", "timeZoneIdentifier"]
        case .focusTask:
            groups = [
                ["plannedForDate", "scheduledStartAtMs"],
                ["templateID", "templateTaskKey"],
                ["completedAtMs", "deletedAtMs"],
            ]
            editable = [
                "plannedForDate", "scheduledStartAtMs", "templateID", "templateTaskKey",
                "completedAtMs", "deletedAtMs", "title", "estimatedPomodoros", "icon",
                "isFavorite", "sortIndex",
            ]
            structural = ["id", "createdAtMs"]
        default:
            return nil
        }

        for key in structural where !jsonValuesEqual(localValues[key], serverValues[key]) {
            return nil
        }

        var handled = Set<String>()
        for group in groups {
            handled.formUnion(group)
            let localChanged = group.contains { !jsonValuesEqual(localValues[$0], baselineValues[$0]) }
            let serverChanged = group.contains { !jsonValuesEqual(serverValues[$0], baselineValues[$0]) }
            if localChanged, serverChanged {
                guard group.allSatisfy({ jsonValuesEqual(localValues[$0], serverValues[$0]) }) else {
                    return nil
                }
            } else if serverChanged {
                for key in group { copyJSONValue(for: key, from: serverValues, to: &localValues) }
            }
        }

        for key in editable.subtracting(handled) {
            let localChanged = !jsonValuesEqual(localValues[key], baselineValues[key])
            let serverChanged = !jsonValuesEqual(serverValues[key], baselineValues[key])
            if localChanged, serverChanged, !jsonValuesEqual(localValues[key], serverValues[key]) {
                return nil
            }
            if serverChanged { copyJSONValue(for: key, from: serverValues, to: &localValues) }
        }
        return try? JSONSerialization.data(withJSONObject: localValues, options: [.sortedKeys])
    }

    private static func copyJSONValue(
        for key: String,
        from source: [String: Any],
        to target: inout [String: Any]
    ) {
        if let value = source[key] { target[key] = value }
        else { target.removeValue(forKey: key) }
    }

    private static func jsonValuesEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        case let (left?, right?): return (left as AnyObject).isEqual(right)
        }
    }
}

enum RecordsConflictFieldSelection {
    /// Some decoded fields only make sense as one unit. The conflict UI may
    /// name the individual differences, but choosing any member always copies
    /// the whole unit from the selected side.
    static func expanded(_ fields: Set<String>, for type: RecordEntityType) -> Set<String> {
        let groups: [Set<String>]
        switch type {
        case .dayOverride:
            groups = [["kind", "segments"]]
        case .calendarException:
            groups = [["effect", "isCleared"]]
        default:
            groups = []
        }
        return groups.reduce(into: fields) { result, group in
            if !result.isDisjoint(with: group) {
                result.formUnion(group)
            }
        }
    }
}

enum RecordsSyncSent {
    /// N's acknowledgement must not clear an N+1 edit that landed while N was in flight.
    ///
    /// A revival is a save plus the deletion of its `erased.*` record. Clearing
    /// on the save alone would leave that tombstone in iCloud, and every other
    /// device would erase the row again the next time it fetched.
    static func shouldClearSave(
        row: SyncAdapterRow,
        savedCount: Int,
        savedTie: String,
        deletedNames: Set<String> = []
    ) -> Bool {
        guard !row.pendingErase, row.dirty else { return false }
        guard row.editCount == savedCount, row.editTieBreaker == savedTie else { return false }
        guard row.revokesErase else { return true }
        return deletedNames.contains(
            RecordsSyncIdentity.erasedName(type: row.entityType, key: row.logicalKey)
        )
    }

    static func shouldClearErase(
        row: SyncAdapterRow,
        savedNames: Set<String>,
        deletedNames: Set<String>
    ) -> Bool {
        guard row.pendingErase else { return false }
        let erased = RecordsSyncIdentity.erasedName(type: row.entityType, key: row.logicalKey)
        return deletedNames.contains(row.recordName) && savedNames.contains(erased)
    }
}

enum DayRecordWrite: Equatable, Sendable {
    case customHours
    case confirmed
    case leave
    case rest
    case makeup
    case clear
}

enum DayLayerPlan: Equatable, Sendable {
    case overrideOnly(DayOverrideKind)
    case exception(override: DayOverrideKind, effect: CalendarEffect, exceptionCleared: Bool)
}

enum DayRecordLayers {
    /// Override wins over exception, so a rest/makeup/clear write must also
    /// neutralize any leftover hours override in the same mutation.
    static func plan(for write: DayRecordWrite) -> DayLayerPlan {
        switch write {
        case .customHours: return .overrideOnly(.customSegments)
        case .confirmed: return .overrideOnly(.confirmedAsScheduled)
        case .leave: return .overrideOnly(.notWorking)
        case .rest: return .exception(override: .cleared, effect: .rest, exceptionCleared: false)
        case .makeup: return .exception(override: .cleared, effect: .work, exceptionCleared: false)
        case .clear: return .exception(override: .cleared, effect: .rest, exceptionCleared: true)
        }
    }
}

enum RecordsSyncGeneration {
    static func shouldDiscard(recordGeneration: Int, fence: Int) -> Bool {
        recordGeneration < fence
    }

    static func staleZones(named names: [String], fence: Int) -> [String] {
        names.filter { name in
            guard let generation = RecordsSyncIdentity.generation(fromZoneName: name) else {
                return false
            }
            return generation < fence
        }
    }
}

enum RecordsSyncCloudPrerequisites {
    static func acceptsAccount(
        storedAccountID: String?,
        currentAccountID: String,
        mayAdoptCurrentAccount: Bool
    ) -> Bool {
        guard let storedAccountID else { return mayAdoptCurrentAccount }
        return storedAccountID == currentAccountID
    }

    static func canResume(localGeneration: Int, remoteFence: Int) -> Bool {
        remoteFence > 0 && remoteFence >= localGeneration
    }

    static func hasRestorableData(fence: Int, zoneNames: [String]) -> Bool {
        fence > 0 && zoneNames.contains(RecordsSyncIdentity.dataZone(generation: fence))
    }
}

enum RecordsSyncApplyAction: Equatable, Sendable {
    case reassertErase
    case ignore
    case insert
    case takeServer
    case keepLocalAndCopyServer
    case takeServerAndCopyLocal
    case mergeLife
    case mergeFocusPlanning
    case mergeSyncedPreferences
}

enum RecordsSyncApply {
    static func action(
        type: RecordEntityType,
        locallyErased: Bool,
        localCount: Int?,
        localTie: String?,
        serverCount: Int,
        serverTie: String
    ) -> RecordsSyncApplyAction {
        // Only reassert an erasure that still describes this device. A natural
        // key (dayKey) can be recorded again under the same identity, and
        // re-deleting that row everywhere would throw away the new record.
        //
        // A row revived on another device is not detectable here: a tombstone
        // buried at editCount 0 and a straggler row at editCount 9 look exactly
        // like a revival. The revival is recognised instead by the `erased.*`
        // deletion that ships atomically with it, which clears the tombstone
        // before this runs. An erase therefore still outlives a stale row.
        if locallyErased, localCount == nil { return .reassertErase }
        guard let localCount, let localTie else { return .insert }
        if type == .lifeProfile { return .mergeLife }
        if type == .focusPlanningConfiguration { return .mergeFocusPlanning }
        if type == .syncedPreferences { return .mergeSyncedPreferences }
        if RecordsSyncConflict.localWins(
            localCount: localCount,
            localTie: localTie,
            serverCount: serverCount,
            serverTie: serverTie
        ) {
            return .keepLocalAndCopyServer
        }
        return .takeServerAndCopyLocal
    }
}

enum RecordsSyncPayload {
    static func encode(_ value: RecordIncomingValue, calendar: Calendar) -> Data? {
        switch value {
        case .period(let period):
            return try? JSONEncoder().encode(CareerPeriodDTO(period, calendar: period.civilCalendar()))
        case .snapshot(let snapshot):
            return try? JSONEncoder().encode(ScheduleSnapshotDTO(snapshot, calendar: calendar))
        case .exception(let exception):
            return try? JSONEncoder().encode(CalendarExceptionDTO(exception, calendar: calendar))
        case .override(let override):
            return try? JSONEncoder().encode(DayOverrideDTO(override, calendar: calendar))
        case .observation(let observation):
            return try? JSONEncoder().encode(WorkObservationDTO(observation, calendar: calendar))
        case .lifeProfile(let profile):
            return try? JSONEncoder().encode(LifeProfileDTO(profile, calendar: calendar))
        case .focusTask(let task):
            return try? JSONEncoder().encode(FocusTaskDTO(task, calendar: calendar))
        case .focusSession(let session):
            return try? JSONEncoder().encode(FocusSessionDTO(session, calendar: calendar))
        case .focusPlanningConfiguration(let configuration):
            return try? JSONEncoder().encode(FocusPlanningConfigurationDTO(configuration))
        case .syncedPreferences(let preferences):
            return try? JSONEncoder().encode(preferences)
        }
    }

    static func encode(type: RecordEntityType, key: String, from state: RecordState) -> Data? {
        let calendar = fileCalendar(for: state)
        switch type {
        case .careerPeriod:
            return state.periods.first(where: { $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame })
                .flatMap { try? JSONEncoder().encode(CareerPeriodDTO($0, calendar: $0.civilCalendar())) }
        case .scheduleSnapshot:
            guard let snapshot = state.snapshots.first(where: {
                $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame
            }) else { return nil }
            let period = state.periods.first(where: { $0.id == snapshot.periodID })
            return try? JSONEncoder().encode(ScheduleSnapshotDTO(snapshot, calendar: period?.civilCalendar() ?? calendar))
        case .calendarException:
            return state.exceptions.first(where: { $0.dayKey == key })
                .flatMap { try? JSONEncoder().encode(CalendarExceptionDTO($0, calendar: calendar)) }
        case .dayOverride:
            return state.overrides.first(where: { $0.dayKey == key })
                .flatMap { try? JSONEncoder().encode(DayOverrideDTO($0, calendar: calendar)) }
        case .workObservation:
            return state.observations.first(where: {
                $0.eventID.uuidString.caseInsensitiveCompare(key) == .orderedSame
            }).flatMap { try? JSONEncoder().encode(WorkObservationDTO($0, calendar: calendar)) }
        case .lifeProfile:
            return state.lifeProfile.flatMap { try? JSONEncoder().encode(LifeProfileDTO($0, calendar: calendar)) }
        case .focusTask:
            return state.focusTasks.first(where: { $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame })
                .flatMap { try? JSONEncoder().encode(FocusTaskDTO($0, calendar: calendar)) }
        case .focusSession:
            return state.focusSessions.first(where: { $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame })
                .flatMap { try? JSONEncoder().encode(FocusSessionDTO($0, calendar: calendar)) }
        case .focusPlanningConfiguration:
            return state.focusPlanningConfiguration
                .flatMap { try? JSONEncoder().encode(FocusPlanningConfigurationDTO($0)) }
        case .syncedPreferences:
            return state.syncedPreferences.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    static func incoming(from data: Data, type: RecordEntityType, calendar: Calendar) -> RecordIncomingValue? {
        switch type {
        case .careerPeriod:
            return (try? JSONDecoder().decode(CareerPeriodDTO.self, from: data))
                .flatMap { $0.value(calendar: calendar) }
                .map { .period($0) }
        case .scheduleSnapshot:
            return (try? JSONDecoder().decode(ScheduleSnapshotDTO.self, from: data))
                .flatMap { $0.value(calendar: calendar) }
                .map { .snapshot($0) }
        case .calendarException:
            return (try? JSONDecoder().decode(CalendarExceptionDTO.self, from: data))
                .flatMap { $0.value(calendar: calendar) }
                .map { .exception($0) }
        case .dayOverride:
            return (try? JSONDecoder().decode(DayOverrideDTO.self, from: data))
                .flatMap { $0.value(calendar: calendar) }
                .map { .override($0) }
        case .workObservation:
            return (try? JSONDecoder().decode(WorkObservationDTO.self, from: data))
                .flatMap { $0.value(calendar: calendar) }
                .map { .observation($0) }
        case .lifeProfile:
            return (try? JSONDecoder().decode(LifeProfileDTO.self, from: data))
                .flatMap { $0.value(calendar: calendar) }
                .map { .lifeProfile($0) }
        case .focusTask:
            return (try? JSONDecoder().decode(FocusTaskDTO.self, from: data))
                .flatMap { $0.value(calendar: calendar) }
                .map { .focusTask($0) }
        case .focusSession:
            return (try? JSONDecoder().decode(FocusSessionDTO.self, from: data))
                .flatMap { $0.value(calendar: calendar) }
                .map { .focusSession($0) }
        case .focusPlanningConfiguration:
            return (try? JSONDecoder().decode(FocusPlanningConfigurationDTO.self, from: data))
                .flatMap { $0.value() }
                .map { .focusPlanningConfiguration($0) }
        case .syncedPreferences:
            return (try? JSONDecoder().decode(SyncedPreferences.self, from: data))
                .flatMap { $0.isValid ? .syncedPreferences($0) : nil }
        }
    }

    static func editedAtMs(from data: Data, type: RecordEntityType, calendar: Calendar) -> Double? {
        guard let value = incoming(from: data, type: type, calendar: calendar) else { return nil }
        switch value {
        case .period(let value): return value.editedAt.timeIntervalSince1970 * 1_000
        case .snapshot(let value): return value.editedAt.timeIntervalSince1970 * 1_000
        case .exception(let value): return value.editedAt.timeIntervalSince1970 * 1_000
        case .override(let value): return value.editedAt.timeIntervalSince1970 * 1_000
        case .observation(let value):
            return (value.editedAt == .distantPast ? value.occurredAt : value.editedAt)
                .timeIntervalSince1970 * 1_000
        case .lifeProfile(let value): return value.editedAt.timeIntervalSince1970 * 1_000
        case .focusTask(let value): return value.editedAt.timeIntervalSince1970 * 1_000
        case .focusSession(let value): return value.editedAt.timeIntervalSince1970 * 1_000
        case .focusPlanningConfiguration(let value): return value.editedAt.timeIntervalSince1970 * 1_000
        case .syncedPreferences(let value): return value.editedAt.timeIntervalSince1970 * 1_000
        }
    }

    static func editStamp(type: RecordEntityType, key: String, in state: RecordState) -> (Int, String)? {
        switch type {
        case .careerPeriod:
            return state.periods.first(where: { $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame })
                .map { ($0.editCount, $0.editTieBreaker.uuidString) }
        case .scheduleSnapshot:
            return state.snapshots.first(where: { $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame })
                .map { ($0.editCount, $0.editTieBreaker.uuidString) }
        case .calendarException:
            return state.exceptions.first(where: { $0.dayKey == key })
                .map { ($0.editCount, $0.editTieBreaker.uuidString) }
        case .dayOverride:
            return state.overrides.first(where: { $0.dayKey == key })
                .map { ($0.editCount, $0.editTieBreaker.uuidString) }
        case .workObservation:
            return state.observations.first(where: {
                $0.eventID.uuidString.caseInsensitiveCompare(key) == .orderedSame
            }).map {
                ($0.editCount > 0 ? $0.editCount : 1,
                 ($0.editTieBreaker == WorkObservation.unsetTieBreaker ? $0.eventID : $0.editTieBreaker).uuidString)
            }
        case .lifeProfile:
            return state.lifeProfile.map { ($0.editCount, $0.editTieBreaker.uuidString) }
        case .focusTask:
            return state.focusTasks.first(where: { $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame })
                .map { ($0.editCount, $0.editTieBreaker.uuidString) }
        case .focusSession:
            return state.focusSessions.first(where: { $0.id.uuidString.caseInsensitiveCompare(key) == .orderedSame })
                .map { ($0.editCount, $0.editTieBreaker.uuidString) }
        case .focusPlanningConfiguration:
            return state.focusPlanningConfiguration.map { ($0.editCount, $0.editTieBreaker.uuidString) }
        case .syncedPreferences:
            return state.syncedPreferences.map { ($0.editCount, $0.editTieBreaker.uuidString) }
        }
    }

    static func editStamp(from data: Data, type: RecordEntityType, calendar: Calendar) -> (Int, String)? {
        guard let value = incoming(from: data, type: type, calendar: calendar) else { return nil }
        switch value {
        case .period(let value): return (value.editCount, value.editTieBreaker.uuidString)
        case .snapshot(let value): return (value.editCount, value.editTieBreaker.uuidString)
        case .exception(let value): return (value.editCount, value.editTieBreaker.uuidString)
        case .override(let value): return (value.editCount, value.editTieBreaker.uuidString)
        case .observation(let value):
            return (value.editCount > 0 ? value.editCount : 1,
                    (value.editTieBreaker == WorkObservation.unsetTieBreaker ? value.eventID : value.editTieBreaker).uuidString)
        case .lifeProfile(let value): return (value.editCount, value.editTieBreaker.uuidString)
        case .focusTask(let value): return (value.editCount, value.editTieBreaker.uuidString)
        case .focusSession(let value): return (value.editCount, value.editTieBreaker.uuidString)
        case .focusPlanningConfiguration(let value): return (value.editCount, value.editTieBreaker.uuidString)
        case .syncedPreferences(let value): return (value.editCount, value.editTieBreaker.uuidString)
        }
    }

    static func fileCalendar(for state: RecordState) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: state.periods.first?.timeZoneIdentifier ?? "") ?? .current
        return calendar
    }
}

enum RecordsSyncOutbox {
    /// A missing server row needs a create, not another update with a stale
    /// change tag. Keep the local revision, payload and erase/revival intent.
    static func forgetMissingRecord(
        _ state: inout SyncLocalState,
        name: String,
        generation: Int,
        expectedSystemFields: Data
    ) -> Bool {
        guard state.generation == generation else { return false }
        for (key, var row) in state.rows where row.generation == generation {
            if row.recordName == name, row.lastKnownRecord == expectedSystemFields {
                row.lastKnownRecord = nil
            } else if RecordsSyncIdentity.erasedName(type: row.entityType, key: row.logicalKey) == name,
                      row.lastKnownErasedRecord == expectedSystemFields {
                row.lastKnownErasedRecord = nil
            } else {
                continue
            }
            state.rows[key] = row
            return true
        }
        return false
    }

    static func markDirty(
        _ state: inout SyncLocalState,
        type: RecordEntityType,
        key: String,
        editCount: Int,
        editTieBreaker: UUID,
        erase: Bool = false,
        revokeErase: Bool = false
    ) {
        let name = RecordsSyncIdentity.recordName(type: type, key: key)
        var row = state.rows[name] ?? SyncAdapterRow(
            entityType: type,
            logicalKey: key,
            recordName: name,
            dirty: true,
            generation: state.generation,
            lastKnownRecord: nil,
            lastKnownPayload: nil,
            pendingErase: erase,
            editCount: editCount,
            editTieBreaker: editTieBreaker.uuidString
        )
        row.dirty = true
        row.pendingErase = erase
        // An erase cancels a revocation that never shipped; otherwise the
        // revocation sticks until CloudKit confirms the tombstone is gone.
        row.pendingEraseRevocation = erase ? nil : (revokeErase || row.revokesErase)
        row.generation = state.generation
        row.editCount = editCount
        row.editTieBreaker = editTieBreaker.uuidString
        state.rows[name] = row
    }

    static func pending(_ state: SyncLocalState) -> [SyncAdapterRow] {
        state.rows.values.filter(\.dirty).sorted { $0.recordName < $1.recordName }
    }

    /// CloudKit accepts at most 250 record changes in one request. Erasure is
    /// a save-tombstone + delete-record pair and must remain atomic, so it gets
    /// a small batch of its own instead of making hundreds of unrelated saves
    /// atomic with it. A revival is the mirror image — save the record, delete
    /// the tombstone — and is isolated for the same reason: a fetching device
    /// must never see the row without also seeing that its tombstone is gone.
    static func nextBatch(_ state: SyncLocalState, limit: Int = 250) -> [SyncAdapterRow] {
        guard limit > 0 else { return [] }
        var result: [SyncAdapterRow] = []
        for row in pending(state) {
            if row.pendingErase || row.revokesErase {
                if result.isEmpty { result.append(row) }
                break
            }
            result.append(row)
            if result.count == limit { break }
        }
        return result
    }

    static func clearDirty(_ state: inout SyncLocalState, recordName: String) {
        state.rows[recordName]?.dirty = false
        state.rows[recordName]?.pendingErase = false
        state.rows[recordName]?.pendingEraseRevocation = nil
    }

    static func applyHigherFence(_ state: inout SyncLocalState, fence: Int) -> Bool {
        guard fence > state.generation else { return false }
        state.generation = fence
        state.rows.removeAll()
        state.conflicts.removeAll()
        state.deletingCloud = false
        state.engineState = nil
        return true
    }

    static func discardLocalArchive(_ archive: inout RecordState, fence: Int) -> Bool {
        guard applyHigherFence(&archive.sync, fence: fence) else { return false }
        let account = archive.sync.accountID
        let enabled = archive.sync.syncEnabled
        let generation = archive.sync.generation
        archive.deleteAllLocalData()
        archive.sync.accountID = account
        archive.sync.syncEnabled = enabled
        archive.sync.generation = generation
        archive.sync.engineState = nil
        return true
    }

    static func markAdopted(_ sync: inout SyncLocalState, report: RecordImportReport, state: RecordState) {
        for adoption in report.adopted {
            let tie = UUID(uuidString: adoption.editTieBreaker) ?? UUID()
            markDirty(
                &sync,
                type: adoption.entityType,
                key: adoption.logicalKey,
                editCount: adoption.editCount,
                editTieBreaker: tie
            )
        }
        _ = state
    }
}
