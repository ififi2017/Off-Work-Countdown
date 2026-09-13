import Foundation
import Observation

/// One scene owns this draft for the lifetime of its editor, including when
/// SwiftUI replaces the surrounding navigation layout. Archive refreshes do
/// not silently replace edits that the user has not submitted.
@MainActor
@Observable
final class RecordDayEditDraft: Identifiable {
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case customHours, asScheduled, leave, restDay, makeupDay

        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .customHours: "recordsKindCustomHours"
            case .asScheduled: "recordsConfirmScheduled"
            case .leave: "recordsMarkLeave"
            case .restDay: "recordsMarkRest"
            case .makeupDay: "recordsMarkMakeup"
            }
        }

        var icon: String {
            switch self {
            case .customHours: "clock"
            case .asScheduled: "calendar"
            case .leave: "airplane"
            case .restDay: "bed.double"
            case .makeupDay: "arrow.uturn.forward"
            }
        }

        var write: DayRecordWrite {
            switch self {
            case .customHours: .customHours
            case .asScheduled: .confirmed
            case .leave: .leave
            case .restDay: .rest
            case .makeupDay: .makeup
            }
        }
    }

    let id = UUID()
    let dayKey: String
    let calendar: Calendar
    let loadedKind: Kind
    let loadedStart: Int
    let loadedEnd: Int
    let hasStoredOverride: Bool
    var startMinutes: Int { didSet { noteEdit(from: oldValue, to: startMinutes) } }
    var endMinutes: Int { didSet { noteEdit(from: oldValue, to: endMinutes) } }
    var kind: Kind { didSet { noteEdit(from: oldValue, to: kind) } }
    var pendingKind: Kind?
    var confirmsClear = false
    var confirmsDiscard = false
    private(set) var editGeneration = 0

    init(dayKey: String, queries: RecordsQueries) {
        self.dayKey = dayKey
        calendar = queries.recordsCalendar
        let resolution = queries.resolvedDay(dayKey: dayKey)
        func minutes(_ milliseconds: Double?, fallback: Int) -> Int {
            guard let milliseconds else { return fallback }
            let date = Date(timeIntervalSince1970: milliseconds / 1_000)
            let parts = queries.recordsCalendar.dateComponents([.hour, .minute], from: date)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
        loadedStart = minutes(resolution?.segments.first?.startAtMs, fallback: 9 * 60)
        loadedEnd = minutes(resolution?.segments.last?.endAtMs, fallback: 18 * 60)
        startMinutes = loadedStart
        endMinutes = loadedEnd
        let override = queries.records.state.overrides.first { $0.dayKey == dayKey && $0.kind != .cleared }
        hasStoredOverride = override != nil
        if let override {
            loadedKind = switch override.kind {
            case .customSegments, .cleared: .customHours
            case .confirmedAsScheduled: .asScheduled
            case .notWorking: .leave
            }
        } else if let exception = queries.records.state.exceptions.first(where: {
            $0.matches(dateKey: dayKey) && !$0.isCleared
        }) {
            loadedKind = exception.effect == .rest ? .restDay : .makeupDay
        } else {
            loadedKind = .customHours
        }
        kind = loadedKind
    }

    var hasChanges: Bool {
        kind != loadedKind || (kind == .customHours && (startMinutes != loadedStart || endMinutes != loadedEnd))
    }

    struct Submission: Equatable, Sendable {
        let dayKey: String
        let write: DayRecordWrite
        let startMinutes: Int
        let endMinutes: Int
        let editGeneration: Int
    }

    var submission: Submission {
        Submission(
            dayKey: dayKey,
            write: kind.write,
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            editGeneration: editGeneration
        )
    }

    func stillMatches(_ submission: Submission) -> Bool {
        self.submission == submission
    }

    private func noteEdit<Value: Equatable>(from oldValue: Value, to newValue: Value) {
        if oldValue != newValue { editGeneration &+= 1 }
    }
}
