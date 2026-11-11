import Foundation

/// Plan 021 §3.11: how a records day explains where its adopted start and
/// end came from. Derived on display from the synced `WorkTimeProvenance`,
/// the day's current override and whether this device still holds the raw
/// detection; nothing here is stored.
nonisolated struct WorkTimeVerificationSummary: Equatable, Sendable {
    /// The label a boundary earns. Named, never a score (§3.11).
    enum Mark: Equatable, Sendable {
        /// A system-observed workplace crossing, adopted unchanged, with
        /// nothing that weakens it.
        case locationVerified
        /// Detected by location, but the timing evidence is weaker.
        case systemDetected
        /// A Shortcuts or other external action said so; DoneAt saw no location.
        case shortcutAction
        /// The person said so.
        case personConfirmed
        /// Detected, then changed or cleared by hand. The detection stays visible.
        case adjusted
    }

    enum Headline: Equatable, Sendable {
        /// Every recorded boundary is location-verified, and both ends exist.
        case verified
        /// At least one boundary is, but not the whole day.
        case partial
        /// None is; the card still lists the sources.
        case sources
    }

    struct Item: Equatable, Sendable, Identifiable {
        var boundary: WorkTimeBoundary
        var mark: Mark
        var entry: WorkTimeProvenance.Boundary
        /// This device no longer holds (or never held) the raw detection:
        /// the row came from iCloud, a backup or an older archive.
        var isHistorical: Bool

        var id: WorkTimeBoundary { boundary }
    }

    var items: [Item]
    var headline: Headline

    /// Reasons that say the timing evidence itself is weak. The others
    /// (automatic apply off, early start, left early, ...) are about what to
    /// ask, not about how good the location evidence was.
    static let weakEvidenceReasons: Set<String> = [
        AutomationReviewReason.unknownObservationTime.rawValue,
        AutomationReviewReason.staleEvent.rawValue,
        AutomationReviewReason.beyondAutomaticWindow.rawValue,
        AutomationReviewReason.arrivalTimeUncertain.rawValue,
    ]

    /// Only the verified headline is shown as "historical": the other marks
    /// make no claim this device could have re-checked.
    var isHistorical: Bool {
        headline != .sources && items.contains { $0.mark == .locationVerified && $0.isHistorical }
    }

    /// nil when the day has no automation source at all.
    static func make(
        provenance: WorkTimeProvenance?,
        override: DayOverride?,
        hasLocalDetection: (WorkTimeBoundary, Date) -> Bool
    ) -> WorkTimeVerificationSummary? {
        guard let provenance, !provenance.boundaries.isEmpty else { return nil }
        let items: [Item] = [WorkTimeBoundary.start, .end].compactMap { kind in
            let verification = WorkTimeProvenance.verification(of: kind, provenance: provenance, override: override)
            switch verification {
            case .none:
                return nil
            case .adjustedAfterDetection(let entry):
                return Item(boundary: kind, mark: .adjusted, entry: entry, isHistorical: false)
            case .verified(let entry):
                return Item(boundary: kind, mark: mark(for: entry), entry: entry,
                            isHistorical: !hasLocalDetection(kind, entry.time))
            }
        }
        guard !items.isEmpty else { return nil }
        let verified = items.filter { $0.mark == .locationVerified }.count
        let headline: Headline = if verified == 0 {
            .sources
        } else if verified == items.count, items.count == 2 {
            .verified
        } else {
            .partial
        }
        return WorkTimeVerificationSummary(items: items, headline: headline)
    }

    /// A person adopting a suggestion never raises its level (§3.11).
    static func mark(for entry: WorkTimeProvenance.Boundary) -> Mark {
        switch entry.evidenceLevel {
        case .externalAction: return .shortcutAction
        case .personStatement: return .personConfirmed
        case .callbackReceipt: return entry.source == .nativeGeofence ? .systemDetected : sourceMark(entry.source)
        case .systemObservation:
            guard entry.source == .nativeGeofence else { return sourceMark(entry.source) }
            return entry.reasons.contains(where: weakEvidenceReasons.contains) || entry.observedAt == nil
                ? .systemDetected
                : .locationVerified
        }
    }

    private static func sourceMark(_ source: WorkTimeProvenance.Source) -> Mark {
        switch source {
        case .nativeGeofence: .systemDetected
        case .appIntentAutomation: .shortcutAction
        case .userConfirmation: .personConfirmed
        }
    }
}
