import Foundation

public let widgetSnapshotSchemaVersion = 1

public enum WidgetTimelinePhase: String, Codable, Sendable {
    case idle
    case before
    case working
    case `break`
    case done
}

public enum WidgetCountdownKind: String, Codable, Sendable {
    case none
    case shiftStarts
    case workRemaining
    case breakEnds
    case complete
}

public struct WidgetShiftSegment: Codable, Equatable, Sendable {
    public let startAtMs: Int64
    public let endAtMs: Int64

    public init(startAtMs: Int64, endAtMs: Int64) {
        self.startAtMs = startAtMs
        self.endAtMs = endAtMs
    }
}

public struct WidgetShiftTimeline: Codable, Equatable, Sendable {
    public let segments: [WidgetShiftSegment]
    public let plannedEndAtMs: Int64
    public let overtimeEndAtMs: Int64?

    public init(
        segments: [WidgetShiftSegment],
        plannedEndAtMs: Int64,
        overtimeEndAtMs: Int64?
    ) {
        self.segments = segments
        self.plannedEndAtMs = plannedEndAtMs
        self.overtimeEndAtMs = overtimeEndAtMs
    }
}

public struct WidgetTimelineEntry: Codable, Equatable, Sendable {
    public let dateMs: Int64
    public let validUntilMs: Int64
    public let phase: WidgetTimelinePhase
    public let labelKey: String
    public let countdownKind: WidgetCountdownKind
    public let countdownValueAtDateMs: Int64
    public let countdownTargetAtMs: Int64?
    public let remainingEffectiveMsAtDateMs: Int64
    public let progressAtDate: Double
    public let nextBoundaryAtMs: Int64?

    public init(
        dateMs: Int64,
        validUntilMs: Int64,
        phase: WidgetTimelinePhase,
        labelKey: String,
        countdownKind: WidgetCountdownKind,
        countdownValueAtDateMs: Int64,
        countdownTargetAtMs: Int64?,
        remainingEffectiveMsAtDateMs: Int64,
        progressAtDate: Double,
        nextBoundaryAtMs: Int64?
    ) {
        self.dateMs = dateMs
        self.validUntilMs = validUntilMs
        self.phase = phase
        self.labelKey = labelKey
        self.countdownKind = countdownKind
        self.countdownValueAtDateMs = countdownValueAtDateMs
        self.countdownTargetAtMs = countdownTargetAtMs
        self.remainingEffectiveMsAtDateMs = remainingEffectiveMsAtDateMs
        self.progressAtDate = progressAtDate
        self.nextBoundaryAtMs = nextBoundaryAtMs
    }
}

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAtMs: Int64
    public let expiresAtMs: Int64
    public let locale: String
    public let shift: WidgetShiftTimeline?
    public let entries: [WidgetTimelineEntry]

    public init(
        schemaVersion: Int,
        generatedAtMs: Int64,
        expiresAtMs: Int64,
        locale: String,
        shift: WidgetShiftTimeline?,
        entries: [WidgetTimelineEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAtMs = generatedAtMs
        self.expiresAtMs = expiresAtMs
        self.locale = locale
        self.shift = shift
        self.entries = entries
    }

    /// Selects a frontend-precomputed interval. This intentionally contains no
    /// workday, break, overtime, or cross-midnight rules.
    public func entry(atMs nowMs: Int64) -> WidgetTimelineEntry? {
        guard schemaVersion == widgetSnapshotSchemaVersion,
              nowMs >= generatedAtMs,
              nowMs < expiresAtMs
        else {
            return nil
        }

        return entries.first {
            nowMs >= $0.dateMs && nowMs < $0.validUntilMs
        }
    }
}
