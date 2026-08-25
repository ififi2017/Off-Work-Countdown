import Foundation
import WidgetKit

@MainActor
final class WidgetSnapshotPublisher {
    static let shared = WidgetSnapshotPublisher()
    static let appGroupIdentifier = "group.com.rainif.offworkcountdown.macappstore"
    private let snapshotFileName = "widget-snapshot-v1.json"
    private let widgetKind = "com.rainif.offworkcountdown.macappstore.widget"

    func publish(store: OffWorkStore, now: Date = .now) {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ) else { return }

        let nowMs = Int64(now.timeIntervalSince1970 * 1_000)
        let snapshot = store.snapshot(at: now)
        let payload = makeSnapshot(store: store, shift: snapshot, active: store.countdownStarted, nowMs: nowMs)
        guard let data = try? JSONEncoder().encode(payload) else { return }

        let destination = container.appendingPathComponent(snapshotFileName)
        let temporary = container.appendingPathComponent("\(snapshotFileName).tmp")
        do {
            try data.write(to: temporary, options: .atomic)
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } catch {
            try? data.write(to: destination, options: .atomic)
            try? FileManager.default.removeItem(at: temporary)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    private func countdownToNextShift(
        store: OffWorkStore,
        target: Int64,
        nowMs: Int64,
        label: String = "nextShiftLabelShort"
    ) -> WidgetSnapshot {
        let end = max(nowMs + 60_000, target)
        return WidgetSnapshot(
            schemaVersion: widgetSnapshotSchemaVersion,
            generatedAtMs: nowMs,
            expiresAtMs: end,
            locale: store.languageCode,
            shift: nil,
            entries: [entry(
                date: nowMs,
                end: end,
                phase: .before,
                label: label,
                kind: .shiftStarts,
                remaining: max(0, target - nowMs),
                progress: 0,
                boundary: target,
                target: target
            )]
        )
    }

    private func makeSnapshot(store: OffWorkStore, shift: NativeShiftSnapshot?, active: Bool, nowMs: Int64) -> WidgetSnapshot {
        if !active,
           store.scheduleMode != .off,
           let shift,
           !shift.isWorkday,
           let nextStart = shift.nextShiftStartAtMs {
            return countdownToNextShift(
                store: store,
                target: Int64(nextStart),
                nowMs: nowMs,
                label: "widgetRestDay"
            )
        }

        guard active else {
            // A configured schedule is enough to know when work starts again,
            // so the widget counts down to it rather than sitting on "not
            // started" until the user opens the app and presses a button.
            if store.scheduleMode != .off, let shift {
                // `nextShiftStartAtMs` is deliberately searched after this
                // shift ends. Before today's shift starts that makes it point
                // at tomorrow (or later), so prefer today's valid future start.
                let currentStart = Int64(shift.startAtMs)
                if shift.isWorkday, currentStart > nowMs {
                    return countdownToNextShift(store: store, target: currentStart, nowMs: nowMs)
                }

                if let nextStart = shift.nextShiftStartAtMs {
                    let target = Int64(nextStart)
                    if target > nowMs {
                        return countdownToNextShift(store: store, target: target, nowMs: nowMs)
                    }
                }
            }
            return WidgetSnapshot(
                schemaVersion: widgetSnapshotSchemaVersion,
                generatedAtMs: nowMs,
                expiresAtMs: nowMs + 24 * 60 * 60 * 1_000,
                locale: store.languageCode,
                shift: nil,
                entries: [entry(date: nowMs, end: nowMs + 24 * 60 * 60 * 1_000, phase: .idle, label: "countdownNotStarted", kind: .none, remaining: 0, progress: 0, boundary: nil, target: nil)]
            )
        }

        guard let shift else {
            return WidgetSnapshot(
                schemaVersion: widgetSnapshotSchemaVersion,
                generatedAtMs: nowMs,
                expiresAtMs: nowMs + 24 * 60 * 60 * 1_000,
                locale: store.languageCode,
                shift: nil,
                entries: [entry(date: nowMs, end: nowMs + 24 * 60 * 60 * 1_000, phase: .idle, label: "countdownNotStarted", kind: .none, remaining: 0, progress: 0, boundary: nil, target: nil)]
            )
        }

        let segments = shift.segments.map {
            WidgetShiftSegment(startAtMs: Int64($0.startAtMs), endAtMs: Int64($0.endAtMs))
        }
        let endMs = Int64(shift.endAtMs)
        let endDate = Date(timeIntervalSince1970: Double(endMs) / 1_000)
        let endDay = Calendar.current.startOfDay(for: endDate)
        let rolloverDate = Calendar.current.date(byAdding: .day, value: 1, to: endDay) ?? endDate
        let rolloverAtMs = Int64(rolloverDate.timeIntervalSince1970 * 1_000)
        let fallbackExpires = max(
            rolloverAtMs + 24 * 60 * 60 * 1_000,
            nowMs + 60 * 60 * 1_000
        )
        let nextShiftStartAtMs = shift.nextShiftStartAtMs.map(Int64.init)
        let expires = nextShiftStartAtMs.flatMap { $0 > nowMs ? $0 : nil } ?? fallbackExpires
        var entries: [WidgetTimelineEntry] = []

        if nowMs < Int64(shift.startAtMs) {
            entries.append(entry(
                date: nowMs,
                end: Int64(shift.startAtMs),
                phase: .before,
                label: "nextShiftLabelShort",
                kind: .shiftStarts,
                remaining: Int64(shift.startAtMs) - nowMs,
                progress: 0,
                boundary: Int64(shift.startAtMs),
                target: Int64(shift.startAtMs)
            ))
        }

        for (index, segment) in segments.enumerated() {
            let date = max(nowMs, segment.startAtMs)
            guard date < segment.endAtMs else { continue }
            let completedBefore = segments.prefix(index).reduce(Int64(0)) { $0 + $1.endAtMs - $1.startAtMs }
            let elapsed = completedBefore + max(0, date - segment.startAtMs)
            let duration = max(Int64(1), Int64(shift.durationMs))
            let remaining = max(0, duration - elapsed)
            entries.append(entry(
                date: date,
                end: segment.endAtMs,
                phase: .working,
                label: "widgetWorking",
                kind: .workRemaining,
                remaining: remaining,
                progress: Double(elapsed) / Double(duration) * 100,
                boundary: segment.endAtMs,
                target: date + remaining
            ))

            if index + 1 < segments.count {
                let next = segments[index + 1]
                if next.startAtMs > segment.endAtMs, next.startAtMs > nowMs {
                    entries.append(entry(
                        date: max(nowMs, segment.endAtMs),
                        end: next.startAtMs,
                        phase: .break,
                        label: "lunchInProgress",
                        kind: .breakEnds,
                        remaining: remaining,
                        progress: Double(elapsed + (segment.endAtMs - date)) / Double(duration) * 100,
                        boundary: next.startAtMs,
                        target: next.startAtMs
                    ))
                }
            }
        }

        // Completion belongs to the calendar day that contains the shift end.
        // At the following midnight the widget advances on its own instead of
        // keeping yesterday's "Done for today" until the app is reopened.
        let doneStart = max(nowMs, endMs)
        let doneUntil = min(expires, rolloverAtMs)
        if doneStart < doneUntil {
            entries.append(entry(
                date: doneStart,
                end: doneUntil,
                phase: .done,
                label: "offWorkToday",
                kind: .complete,
                remaining: 0,
                progress: 100,
                boundary: nil,
                target: nil
            ))
        }

        let postCompletionStart = max(nowMs, doneUntil)
        if let target = nextShiftStartAtMs, target > postCompletionStart {
            entries.append(entry(
                date: postCompletionStart,
                end: target,
                phase: .before,
                label: "nextShiftLabelShort",
                kind: .shiftStarts,
                remaining: target - postCompletionStart,
                progress: 0,
                boundary: target,
                target: target
            ))
        } else if postCompletionStart < expires {
            entries.append(entry(
                date: postCompletionStart,
                end: expires,
                phase: .idle,
                label: "countdownNotStarted",
                kind: .none,
                remaining: 0,
                progress: 0,
                boundary: nil,
                target: nil
            ))
        }

        return WidgetSnapshot(
            schemaVersion: widgetSnapshotSchemaVersion,
            generatedAtMs: nowMs,
            expiresAtMs: expires,
            locale: store.languageCode,
            shift: WidgetShiftTimeline(
                segments: segments,
                plannedEndAtMs: Int64(shift.plannedEndAtMs),
                overtimeEndAtMs: shift.overtimeEndAtMs.map(Int64.init)
            ),
            entries: entries
        )
    }

    private func entry(
        date: Int64,
        end: Int64,
        phase: WidgetTimelinePhase,
        label: String,
        kind: WidgetCountdownKind,
        remaining: Int64,
        progress: Double,
        boundary: Int64?,
        target: Int64?
    ) -> WidgetTimelineEntry {
        WidgetTimelineEntry(
            dateMs: date,
            validUntilMs: end,
            phase: phase,
            labelKey: label,
            countdownKind: kind,
            countdownValueAtDateMs: remaining,
            countdownTargetAtMs: target,
            remainingEffectiveMsAtDateMs: remaining,
            progressAtDate: min(100, max(0, progress)),
            nextBoundaryAtMs: boundary
        )
    }
}
