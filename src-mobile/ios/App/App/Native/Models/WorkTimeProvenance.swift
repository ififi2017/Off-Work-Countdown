import Foundation

/// Which end of a shift a time belongs to.
nonisolated enum WorkTimeBoundary: String, Codable, Sendable {
    case start
    case end
}

/// Plan 021 §0.3/§3.7/§3.11: the minimal summary of how workplace automation
/// arrived at a day's adopted start or end time.
///
/// One row per records day (`dayKey`, the shift's anchor day), matching that
/// day's `DayOverride`. It joins the user's private iCloud sync and backups;
/// it never holds coordinates, Wi-Fi names, place names or geofence
/// identifiers — those stay in `WorkplaceAutomationStore` on this device.
///
/// It is copied when an adoption writes the day and is not rewritten by later
/// manual edits. Whether a boundary is still "location verified" is decided at
/// display time by comparing it with the day's current `DayOverride`
/// (`verification(of:provenance:override:)`), never stored.
nonisolated struct WorkTimeProvenance: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    /// More than enough for a start and an end; keeps a damaged row small.
    static let maximumBoundaries = 8

    nonisolated enum Source: String, Codable, Sendable, CaseIterable {
        case nativeGeofence
        case appIntentAutomation
        case userConfirmation
    }

    nonisolated enum AppliedBy: String, Codable, Sendable, CaseIterable {
        /// Applied automatically under the automatic-apply setting.
        case automatic
        /// The person adopted it from the review list (single or batch).
        case reviewed
    }

    /// How strong the evidence behind the adopted time is (§3.11). Named, not
    /// scored; a person adopting a suggestion never raises it.
    nonisolated enum EvidenceLevel: String, Codable, Sendable, CaseIterable {
        /// The system reported when it observed the crossing.
        case systemObservation
        /// Only when the app received the callback is known.
        case callbackReceipt
        /// A Shortcuts or other external action reported it; DoneAt saw no location.
        case externalAction
        /// The person said so.
        case personStatement
    }

    nonisolated struct Boundary: Codable, Equatable, Sendable {
        var boundary: WorkTimeBoundary
        /// The time adopted for this boundary.
        var time: Date
        var source: Source
        /// When the system observed it; unknown stays nil.
        var observedAt: Date?
        var receivedAt: Date
        var appliedAt: Date
        var appliedBy: AppliedBy
        var batchID: UUID?
        var rulesVersion: Int
        var evidenceLevel: EvidenceLevel
        /// Why the decision went as it did (`AutomationReviewReason` raw
        /// values). Kept as text so a reason a newer build adds survives.
        var reasons: [String]

        var isValid: Bool {
            time.timeIntervalSince1970.isFinite
                && receivedAt.timeIntervalSince1970.isFinite
                && appliedAt.timeIntervalSince1970.isFinite
                && (observedAt?.timeIntervalSince1970.isFinite ?? true)
                && rulesVersion >= 1
                && reasons.count <= 16
                && reasons.allSatisfy { !$0.isEmpty && $0.count <= 64 }
        }
    }

    var dayKey: String
    var boundaries: [Boundary]
    /// Civil day this row was recorded in. Travel does not rewrite it.
    var timeZoneIdentifier: String
    var editedAt: Date = .distantPast
    var editCount: Int = 0
    var editTieBreaker: UUID = WorkObservation.unsetTieBreaker

    var isValid: Bool {
        ExtendedScheduleResolver.parse(dayKey: dayKey) != nil
            && TimeZone(identifier: timeZoneIdentifier) != nil
            && !boundaries.isEmpty
            && boundaries.count <= Self.maximumBoundaries
            && Set(boundaries.map(\.boundary)).count == boundaries.count
            && boundaries.allSatisfy(\.isValid)
            && editCount >= 0
    }

    func boundary(_ kind: WorkTimeBoundary) -> Boundary? {
        boundaries.first { $0.boundary == kind }
    }

    /// The row after adopting `entry`: it replaces any earlier entry for the
    /// same boundary and keeps the other one, start first.
    func adopting(_ entry: Boundary) -> WorkTimeProvenance {
        var next = self
        next.boundaries.removeAll { $0.boundary == entry.boundary }
        next.boundaries.append(entry)
        next.boundaries.sort { $0.boundary == .start && $1.boundary == .end }
        return next
    }

    // MARK: Display-time verification

    nonisolated enum Verification: Equatable, Sendable {
        /// No automation summary for this boundary.
        case none
        /// The day still uses the adopted time.
        case verified(Boundary)
        /// Automation detected it, then the time was changed or cleared by hand.
        case adjustedAfterDetection(Boundary)
    }

    /// Derived on display (§0.3): a boundary is verified only while the day's
    /// current override still starts (or ends) at the adopted time. A cleared
    /// override, or none, never counts as verified.
    static func verification(
        of kind: WorkTimeBoundary,
        provenance: WorkTimeProvenance?,
        override: DayOverride?
    ) -> Verification {
        guard let entry = provenance?.boundary(kind) else { return .none }
        guard let override, override.kind == .customSegments, !override.segments.isEmpty else {
            return .adjustedAfterDetection(entry)
        }
        let adoptedMs = entry.time.timeIntervalSince1970 * 1_000
        let currentMs = kind == .start
            ? override.segments.map(\.startAtMs).min()
            : override.segments.map(\.endAtMs).max()
        guard let currentMs, abs(currentMs - adoptedMs) < 1 else { return .adjustedAfterDetection(entry) }
        return .verified(entry)
    }
}

/// The iCloud and backup form. Instants are Unix milliseconds; enum values
/// are strings, so a value a newer build adds rejects only its row.
nonisolated struct WorkTimeProvenanceDTO: Codable, Equatable, Sendable {
    struct Boundary: Codable, Equatable, Sendable {
        var boundary: String
        var timeMs: Double
        var source: String
        var observedAtMs: Double?
        var receivedAtMs: Double
        var appliedAtMs: Double
        var appliedBy: String
        var batchID: String?
        var rulesVersion: Int
        var evidenceLevel: String
        var reasons: [String]
    }

    var dayKey: String
    var boundaries: [Boundary]
    var timeZoneIdentifier: String
    var editedAtMs: Double
    var editCount: Int
    var editTieBreaker: String

    init(_ value: WorkTimeProvenance) {
        dayKey = value.dayKey
        boundaries = value.boundaries.map {
            Boundary(
                boundary: $0.boundary.rawValue,
                timeMs: $0.time.timeIntervalSince1970 * 1_000,
                source: $0.source.rawValue,
                observedAtMs: $0.observedAt.map { $0.timeIntervalSince1970 * 1_000 },
                receivedAtMs: $0.receivedAt.timeIntervalSince1970 * 1_000,
                appliedAtMs: $0.appliedAt.timeIntervalSince1970 * 1_000,
                appliedBy: $0.appliedBy.rawValue,
                batchID: $0.batchID?.uuidString,
                rulesVersion: $0.rulesVersion,
                evidenceLevel: $0.evidenceLevel.rawValue,
                reasons: $0.reasons
            )
        }
        timeZoneIdentifier = value.timeZoneIdentifier
        editedAtMs = value.editedAt.timeIntervalSince1970 * 1_000
        editCount = value.editCount
        editTieBreaker = value.editTieBreaker.uuidString
    }

    func value() -> WorkTimeProvenance? {
        guard let editTieBreaker = UUID(uuidString: editTieBreaker), editedAtMs.isFinite else { return nil }
        var parsed: [WorkTimeProvenance.Boundary] = []
        for dto in boundaries {
            guard let kind = WorkTimeBoundary(rawValue: dto.boundary),
                  let source = WorkTimeProvenance.Source(rawValue: dto.source),
                  let appliedBy = WorkTimeProvenance.AppliedBy(rawValue: dto.appliedBy),
                  let evidence = WorkTimeProvenance.EvidenceLevel(rawValue: dto.evidenceLevel),
                  dto.timeMs.isFinite, dto.receivedAtMs.isFinite, dto.appliedAtMs.isFinite,
                  dto.observedAtMs?.isFinite ?? true
            else { return nil }
            var batch: UUID?
            if let batchID = dto.batchID {
                guard let id = UUID(uuidString: batchID) else { return nil }
                batch = id
            }
            parsed.append(WorkTimeProvenance.Boundary(
                boundary: kind,
                time: Date(timeIntervalSince1970: dto.timeMs / 1_000),
                source: source,
                observedAt: dto.observedAtMs.map { Date(timeIntervalSince1970: $0 / 1_000) },
                receivedAt: Date(timeIntervalSince1970: dto.receivedAtMs / 1_000),
                appliedAt: Date(timeIntervalSince1970: dto.appliedAtMs / 1_000),
                appliedBy: appliedBy,
                batchID: batch,
                rulesVersion: dto.rulesVersion,
                evidenceLevel: evidence,
                reasons: dto.reasons
            ))
        }
        let row = WorkTimeProvenance(
            dayKey: dayKey,
            boundaries: parsed,
            timeZoneIdentifier: timeZoneIdentifier,
            editedAt: Date(timeIntervalSince1970: editedAtMs / 1_000),
            editCount: editCount,
            editTieBreaker: editTieBreaker
        )
        return row.isValid ? row : nil
    }
}
