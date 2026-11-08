import Foundation

// Plan 021 §0.3: everything workplace automation keeps before a time is
// adopted. Coordinates, geofence state, raw events, pending proposals and
// command receipts stay on this device: the file never joins CloudKit, the
// records JSON or an iCloud/Finder device backup. Adopted times go to
// `DayOverride`; their minimal provenance is a separate synced entity.

nonisolated struct SavedWorkplace: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var innerRadius: Double
    var outerRadius: Double
    /// A disabled workplace still uses one of the five places (§3.1).
    var isEnabled: Bool
    /// Changes whenever the region changes, so an event from the old
    /// registration can never match the new one (§I2).
    var registrationGeneration: Int
}

nonisolated enum WorkTimeProposalStatus: String, Codable, Sendable {
    case pendingReview
    case autoApplied
    case manuallyApplied
    case dismissed
    case superseded
}

/// A reviewable suggestion for one boundary of one shift (§3.4). It keeps
/// the planned shift it was made against, so reviewing it weeks later does
/// not depend on today's schedule.
nonisolated struct WorkTimeProposal: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var shift: AutomationShift
    var boundary: WorkTimeBoundary
    var proposedTime: Date
    var sourceEventIDs: [UUID]
    var status: WorkTimeProposalStatus
    var reasons: [AutomationReviewReason]
    var createdAt: Date
    var resolvedAt: Date?
    var batchID: UUID?
    var rulesVersion: Int = WorkplaceAutomation.rulesVersion

    var shiftKey: String { shift.shiftKey }
    var isAdopted: Bool { status == .autoApplied || status == .manuallyApplied }
}

/// The structured result every automation command reports (§3.3).
nonisolated enum AutomationCommandOutcome: String, Codable, Sendable {
    case recordedForReview
    case applied
    case alreadyApplied
    case ignored
    case needsReview
    case temporarilyUnavailable
}

/// Proof a command finished, keyed by a stable command ID so a retry after
/// a crash or a second delivery never applies twice (§3.6).
nonisolated struct AutomationCommandReceipt: Codable, Equatable, Sendable {
    var commandID: UUID
    var outcome: AutomationCommandOutcome
    var completedAt: Date
    var batchID: UUID? = nil
    /// Set when the command wrote a day: what an undo needs.
    var dayKey: String? = nil
    var shiftKey: String? = nil
    var previousOverride: DayOverride? = nil
    var writtenEditCount: Int? = nil
    /// The day's provenance before this write (C1), for undo.
    var provenanceWrite: AutomationProvenanceWrite? = nil
    var undoneAt: Date? = nil
}

nonisolated enum WorkplaceAutomationError: Error, Equatable {
    case workplaceLimitReached
    case unknownWorkplace
}

nonisolated struct WorkplaceAutomationState: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = WorkplaceAutomationState.currentVersion
    var settings = WorkplaceAutomationSettings()
    private(set) var workplaces: [SavedWorkplace] = []
    private(set) var events: [AutomationEvent] = []
    private(set) var proposals: [WorkTimeProposal] = []
    private(set) var receipts: [AutomationCommandReceipt] = []
    /// Workplaces the latest accepted events place the person inside.
    private(set) var insideWorkplaceIDs: Set<UUID> = []
    /// Shifts a person corrected, ended or undid by hand. Kept by shift
    /// identity, not reset at midnight (§3.1).
    private(set) var suppressedShiftKeys: [String: Date] = [:]
    /// Monotonic across edits and deletions so a generation never repeats.
    private(set) var lastRegistrationGeneration = 0
    /// The day row's `editCount` right after automation last wrote it. A
    /// different count means the person or another device changed the day.
    private(set) var adoptedEditCounts: [String: Int] = [:]
    /// Field work, business trips, remote work and rest by day range (§3.10).
    private(set) var contexts: [WorkContextRange] = []
    /// Shifts whose status the person already settled; never asked again.
    private(set) var settledShiftKeys: [String: WorkdayStatusAnswer] = [:]
    /// Early and off-shift arrivals waiting for, or answered by, the person.
    private(set) var visits: [AutomationVisit] = []
    /// Exits before a shift's planned end with no return yet, kept out of
    /// the review list. A return clears one; once the shift is over it
    /// becomes a review item (§3.9 missing end).
    private(set) var earlyExits: [String: WorkTimeProposal] = [:]
    /// Monitored circles added but not yet reported. Their first report is
    /// where the person already is, not a crossing (§3.4 initial state).
    private(set) var awaitingBaseline: Set<String> = []

    var canAddWorkplace: Bool { workplaces.count < WorkplaceAutomation.maximumWorkplaces }

    // MARK: Workplaces

    @discardableResult
    mutating func addWorkplace(
        id: UUID = UUID(),
        name: String,
        latitude: Double,
        longitude: Double,
        innerRadius: Double = WorkplaceAutomation.defaultInnerRadius,
        outerMargin: Double = WorkplaceAutomation.defaultOuterRadiusMargin
    ) throws -> SavedWorkplace {
        guard canAddWorkplace else { throw WorkplaceAutomationError.workplaceLimitReached }
        lastRegistrationGeneration += 1
        let workplace = SavedWorkplace(
            id: id,
            name: name,
            latitude: latitude,
            longitude: longitude,
            innerRadius: innerRadius,
            outerRadius: innerRadius + outerMargin,
            isEnabled: true,
            registrationGeneration: lastRegistrationGeneration
        )
        workplaces.append(workplace)
        return workplace
    }

    /// Moving or resizing a region retires its old registration.
    mutating func updateWorkplace(
        _ id: UUID,
        name: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        innerRadius: Double? = nil,
        outerRadius: Double? = nil,
        isEnabled: Bool? = nil
    ) throws {
        guard let index = workplaces.firstIndex(where: { $0.id == id }) else {
            throw WorkplaceAutomationError.unknownWorkplace
        }
        var workplace = workplaces[index]
        if let name { workplace.name = name }
        let regionChanged = (latitude.map { $0 != workplace.latitude } ?? false)
            || (longitude.map { $0 != workplace.longitude } ?? false)
            || (innerRadius.map { $0 != workplace.innerRadius } ?? false)
            || (outerRadius.map { $0 != workplace.outerRadius } ?? false)
            || (isEnabled.map { $0 != workplace.isEnabled } ?? false)
        workplace.latitude = latitude ?? workplace.latitude
        workplace.longitude = longitude ?? workplace.longitude
        workplace.innerRadius = innerRadius ?? workplace.innerRadius
        workplace.outerRadius = max(outerRadius ?? workplace.outerRadius, workplace.innerRadius)
        workplace.isEnabled = isEnabled ?? workplace.isEnabled
        if regionChanged {
            lastRegistrationGeneration += 1
            workplace.registrationGeneration = lastRegistrationGeneration
            insideWorkplaceIDs.remove(id)
        }
        workplaces[index] = workplace
    }

    /// Deleting a workplace drops its region; adopted times and their
    /// provenance live elsewhere and stay (§3.7).
    mutating func removeWorkplace(_ id: UUID) {
        workplaces.removeAll { $0.id == id }
        insideWorkplaceIDs.remove(id)
    }

    func workplace(_ id: UUID) -> SavedWorkplace? {
        workplaces.first { $0.id == id }
    }

    // MARK: Events

    /// Stores an event once. A redelivered event returns false and changes
    /// nothing, including presence.
    @discardableResult
    mutating func record(_ event: AutomationEvent) -> Bool {
        guard !events.contains(where: { $0.id == event.id }) else { return false }
        events.append(event)
        if let workplaceID = event.workplaceID,
           workplace(workplaceID)?.registrationGeneration == event.registrationGeneration {
            switch event.type {
            case .enterInner: insideWorkplaceIDs.insert(workplaceID)
            case .exitOuter: insideWorkplaceIDs.remove(workplaceID)
            }
        }
        return true
    }

    // MARK: Proposals

    mutating func upsert(_ proposal: WorkTimeProposal) {
        if let index = proposals.firstIndex(where: { $0.id == proposal.id }) {
            proposals[index] = proposal
        } else {
            proposals.append(proposal)
        }
    }

    func event(_ id: UUID) -> AutomationEvent? {
        events.first { $0.id == id }
    }

    func proposal(_ id: UUID) -> WorkTimeProposal? {
        proposals.first { $0.id == id }
    }

    /// Whether this device still holds the adopted detection behind a records
    /// day's boundary (§3.11). A synced or restored day without it is shown
    /// as a historical source, never as re-checked here.
    func hasAdoptedDetection(dayKey: String, boundary: WorkTimeBoundary, at time: Date) -> Bool {
        proposals.contains {
            $0.isAdopted && $0.shift.anchorDayKey == dayKey && $0.boundary == boundary
                && abs($0.proposedTime.timeIntervalSince(time)) < 1
        }
    }

    /// The adopted time for a shift boundary, latest first.
    func adoptedTime(shiftKey: String, boundary: WorkTimeBoundary) -> Date? {
        proposals
            .filter { $0.shiftKey == shiftKey && $0.boundary == boundary && $0.isAdopted }
            .max { ($0.resolvedAt ?? $0.createdAt) < ($1.resolvedAt ?? $1.createdAt) }?
            .proposedTime
    }

    /// A newer suggestion for the same boundary replaces a pending one.
    mutating func supersedePending(shiftKey: String, boundary: WorkTimeBoundary, at date: Date) {
        for index in proposals.indices
        where proposals[index].shiftKey == shiftKey
            && proposals[index].boundary == boundary
            && proposals[index].status == .pendingReview {
            proposals[index].status = .superseded
            proposals[index].resolvedAt = date
        }
    }

    var pendingProposals: [WorkTimeProposal] {
        proposals.filter { $0.status == .pendingReview }.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: Commands

    func receipt(for commandID: UUID) -> AutomationCommandReceipt? {
        receipts.first { $0.commandID == commandID }
    }

    /// Keeps the first receipt for a command; a retry gets that one back.
    @discardableResult
    mutating func recordReceipt(_ receipt: AutomationCommandReceipt) -> AutomationCommandReceipt {
        if let existing = self.receipt(for: receipt.commandID) { return existing }
        receipts.append(receipt)
        return receipt
    }

    mutating func markUndone(commandID: UUID, at date: Date) {
        guard let index = receipts.firstIndex(where: { $0.commandID == commandID }) else { return }
        receipts[index].undoneAt = date
    }

    func adoptedEditCount(dayKey: String) -> Int? { adoptedEditCounts[dayKey] }

    mutating func setAdoptedEditCount(_ count: Int?, dayKey: String) {
        adoptedEditCounts[dayKey] = count
    }

    // MARK: Manual priority

    mutating func suppress(shiftKey: String, at date: Date) {
        suppressedShiftKeys[shiftKey] = date
    }

    mutating func resumeAutomation(shiftKey: String) {
        suppressedShiftKeys.removeValue(forKey: shiftKey)
    }

    func isSuppressed(_ shiftKey: String) -> Bool {
        suppressedShiftKeys[shiftKey] != nil
    }

    // MARK: Work status

    /// The context for a day: the latest range covering it, else regular.
    func context(for dayKey: String) -> WorkDayContext {
        contexts.last { $0.contains(dayKey) }?.context ?? .regular
    }

    /// A newer range wins over the days it covers; older ones are trimmed
    /// rather than deleted so their other days keep their context.
    mutating func setContext(_ context: WorkDayContext, from firstDayKey: String, through lastDayKey: String) {
        let range = WorkContextRange(id: UUID(), context: context, firstDayKey: min(firstDayKey, lastDayKey),
                                     lastDayKey: max(firstDayKey, lastDayKey))
        contexts = contexts.flatMap { $0.removing(range) }
        if context != .regular { contexts.append(range) }
    }

    mutating func removeContext(_ id: UUID) {
        contexts.removeAll { $0.id == id }
    }

    func statusAnswer(shiftKey: String) -> WorkdayStatusAnswer? { settledShiftKeys[shiftKey] }

    mutating func settleStatus(shiftKey: String, answer: WorkdayStatusAnswer) {
        settledShiftKeys[shiftKey] = answer
    }

    // MARK: Visits

    func visit(_ id: UUID) -> AutomationVisit? { visits.first { $0.id == id } }

    mutating func upsert(_ visit: AutomationVisit) {
        if let index = visits.firstIndex(where: { $0.id == visit.id }) {
            visits[index] = visit
        } else {
            visits.append(visit)
        }
    }

    /// The visit still open at a workplace, if any: unanswered or working.
    var openVisit: AutomationVisit? {
        visits.last { $0.leftAt == nil && ($0.status == .waiting || $0.status == .working) }
    }

    mutating func recordEarlyExit(_ candidate: WorkTimeProposal) { earlyExits[candidate.shiftKey] = candidate }
    mutating func clearEarlyExit(shiftKey: String) { earlyExits.removeValue(forKey: shiftKey) }

    // MARK: Monitoring baseline

    mutating func awaitBaseline(_ identifiers: some Sequence<String>) {
        awaitingBaseline.formUnion(identifiers)
    }

    /// True once per circle: its first report after being added.
    mutating func takeBaseline(_ identifier: String) -> Bool {
        awaitingBaseline.remove(identifier) != nil
    }

    /// Forgets circles that are no longer watched.
    mutating func keepBaseline(only identifiers: Set<String>) {
        awaitingBaseline.formIntersection(identifiers)
    }

    // MARK: Retention

    /// Whether anything automation keeps on this device is worth deleting.
    var hasDeviceData: Bool {
        !workplaces.isEmpty || !events.isEmpty || !proposals.isEmpty || !receipts.isEmpty
            || !contexts.isEmpty || !visits.isEmpty || !earlyExits.isEmpty
            || !suppressedShiftKeys.isEmpty || !settledShiftKeys.isEmpty
    }

    /// "Delete Automation Data" (§3.7): removes every workplace, event,
    /// pending time, answer and receipt this device keeps, and turns
    /// monitoring off. Adopted work times and their provenance live in the
    /// records and stay. The registration generation keeps counting, so a
    /// late system event can never match a workplace saved afterwards.
    mutating func eraseDeviceData() {
        var erased = WorkplaceAutomationState()
        erased.settings = settings
        erased.settings.isMonitoringEnabled = false
        erased.lastRegistrationGeneration = lastRegistrationGeneration
        self = erased
    }

    /// Drops what is older than the retention window. Unadopted references
    /// keep 90 days; events a kept proposal still explains are kept with it.
    mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-WorkplaceAutomation.unadoptedRetention)
        proposals.removeAll { ($0.resolvedAt ?? $0.createdAt) < cutoff }
        let referenced = Set(proposals.flatMap(\.sourceEventIDs))
        events.removeAll { event in
            !referenced.contains(event.id) && event.receivedAt < cutoff
        }
        receipts.removeAll { $0.completedAt < cutoff }
        suppressedShiftKeys = suppressedShiftKeys.filter { $0.value >= cutoff }
        visits.removeAll { $0.arrivedAt < cutoff }
        let cutoffKey = RecordJSON.dayKey(cutoff, calendar: Calendar(identifier: .gregorian))
        contexts.removeAll { $0.lastDayKey < cutoffKey }
        settledShiftKeys = settledShiftKeys.filter { String($0.key.prefix(10)) >= cutoffKey }
    }
}

nonisolated extension WorkplaceAutomationState {
    private enum CodingKeys: String, CodingKey {
        case version, settings, workplaces, events, proposals, receipts, insideWorkplaceIDs
        case suppressedShiftKeys, lastRegistrationGeneration, adoptedEditCounts
        case contexts, settledShiftKeys, visits, earlyExits, awaitingBaseline
    }

    /// Fields added after the first internal builds decode as empty.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        version = try container.decode(Int.self, forKey: .version)
        settings = try container.decode(WorkplaceAutomationSettings.self, forKey: .settings)
        workplaces = try container.decode([SavedWorkplace].self, forKey: .workplaces)
        events = try container.decode([AutomationEvent].self, forKey: .events)
        proposals = try container.decode([WorkTimeProposal].self, forKey: .proposals)
        receipts = try container.decode([AutomationCommandReceipt].self, forKey: .receipts)
        insideWorkplaceIDs = try container.decode(Set<UUID>.self, forKey: .insideWorkplaceIDs)
        suppressedShiftKeys = try container.decode([String: Date].self, forKey: .suppressedShiftKeys)
        lastRegistrationGeneration = try container.decode(Int.self, forKey: .lastRegistrationGeneration)
        adoptedEditCounts = try container.decode([String: Int].self, forKey: .adoptedEditCounts)
        contexts = try container.decodeIfPresent([WorkContextRange].self, forKey: .contexts) ?? []
        settledShiftKeys = try container.decodeIfPresent([String: WorkdayStatusAnswer].self, forKey: .settledShiftKeys) ?? [:]
        visits = try container.decodeIfPresent([AutomationVisit].self, forKey: .visits) ?? []
        earlyExits = try container.decodeIfPresent([String: WorkTimeProposal].self, forKey: .earlyExits) ?? [:]
        awaitingBaseline = try container.decodeIfPresent(Set<String>.self, forKey: .awaitingBaseline) ?? []
    }
}

/// A work context over consecutive records days, both ends included.
nonisolated struct WorkContextRange: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var context: WorkDayContext
    var firstDayKey: String
    var lastDayKey: String

    func contains(_ dayKey: String) -> Bool { dayKey >= firstDayKey && dayKey <= lastDayKey }

    /// This range minus `other`: none, itself, or the parts on either side.
    func removing(_ other: WorkContextRange) -> [WorkContextRange] {
        guard other.firstDayKey <= lastDayKey, other.lastDayKey >= firstDayKey else { return [self] }
        var parts: [WorkContextRange] = []
        if firstDayKey < other.firstDayKey, let before = ExtendedScheduleEditing.dayKey(other.firstDayKey, plus: -1) {
            parts.append(WorkContextRange(id: id, context: context, firstDayKey: firstDayKey, lastDayKey: before))
        }
        if lastDayKey > other.lastDayKey, let after = ExtendedScheduleEditing.dayKey(other.lastDayKey, plus: 1) {
            parts.append(WorkContextRange(id: parts.isEmpty ? id : UUID(), context: context,
                                          firstDayKey: after, lastDayKey: lastDayKey))
        }
        return parts
    }
}

/// How the person settled a shift's status question (§3.10).
nonisolated enum WorkdayStatusAnswer: String, Codable, Sendable {
    /// Keep recording by the existing rules; nothing else is approved.
    case continueRecording
    case rest
    case fieldwork
    case businessTrip
    case remote
}

/// One early or off-shift arrival and the person's answer about it (§3.9).
nonisolated struct AutomationVisit: Codable, Equatable, Identifiable, Sendable {
    enum Kind: Codable, Equatable, Sendable {
        /// Before a shift: answering "started work" adopts this suggestion.
        case early(proposalID: UUID)
        /// No shift: answering "started work" records extra work from arrival.
        case offShift(dayKey: String)
    }

    enum Status: String, Codable, Sendable {
        case waiting
        /// Confirmed; extra work runs until the person leaves.
        case working
        case declined
        case closed
    }

    var id: UUID
    var kind: Kind
    var workplaceID: UUID?
    var arrivalEventID: UUID
    var arrivedAt: Date
    var promptAt: Date
    var status: Status = .waiting
    var leftAt: Date?
    /// The day's planned segments when it has a shift, kept with extra work.
    var plannedSegments: [NativeShiftSegment] = []
    /// Set when the person said this was a move between workplaces: the
    /// extra work counts from the earlier end instead of the arrival.
    var countsFrom: Date? = nil

    /// Where the confirmed stretch starts.
    var workStart: Date { countsFrom ?? arrivedAt }
}

/// Reads and writes the device-only automation file.
nonisolated enum WorkplaceAutomationArchive {
    enum LoadResult: Equatable {
        case missing
        case loaded(WorkplaceAutomationState)
        /// Unreadable or from a newer app. Left untouched, never overwritten.
        case unreadable
    }

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "WorkplaceAutomation", directoryHint: .isDirectory)
            .appending(path: "state.json", directoryHint: .notDirectory)
    }

    static func load(from url: URL = defaultURL) -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return .missing }
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(WorkplaceAutomationState.self, from: data),
              state.version <= WorkplaceAutomationState.currentVersion
        else { return .unreadable }
        return .loaded(state)
    }

    /// Writable after the first unlock so a locked phone can still record a
    /// geofence event, like `LifeSummaryCache`. The folder and the file are
    /// both excluded from device backups (plan 021 privacy exception).
    static func save(_ state: WorkplaceAutomationState, to url: URL = defaultURL) throws {
        var directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var directoryValues = URLResourceValues()
        directoryValues.isExcludedFromBackup = true
        try directory.setResourceValues(directoryValues)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var file = url
        var fileValues = URLResourceValues()
        fileValues.isExcludedFromBackup = true
        try file.setResourceValues(fileValues)
    }
}
