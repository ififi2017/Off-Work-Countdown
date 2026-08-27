import Foundation
import WidgetKit

@MainActor
final class WidgetSnapshotPublisher {
    static let shared = WidgetSnapshotPublisher()
    static let appGroupIdentifier = "group.com.rainif.offworkcountdown.macappstore"

    private let snapshotFileName = "widget-snapshot-v1.json"
    private let widgetKind = "com.rainif.offworkcountdown.macappstore.widget"
    private let recurringHorizonDays = 370
    private let maximumRecurringShifts = 400

    func publish(store: OffWorkStore, now: Date = .now) {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ) else { return }

        let nowMs = Int64(now.timeIntervalSince1970 * 1_000)
        let snapshot = store.snapshot(at: now)
        let payload = makeSnapshot(
            store: store,
            shift: snapshot,
            active: store.countdownStarted,
            nowMs: nowMs
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }

        let destination = container.appending(path: snapshotFileName)
        let temporary = container.appending(path: "\(snapshotFileName).tmp")
        do {
            try data.write(to: temporary, options: .atomic)
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } catch {
            try? data.write(to: destination, options: .atomic)
            try? FileManager.default.removeItem(at: temporary)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    /// Internal so phase coverage can be unit-tested without an App Group.
    /// Swift never resolves a workday or constructs a shift here: every future
    /// shift is obtained from the shared TypeScript rules through `store.snapshot`.
    func makeSnapshot(
        store: OffWorkStore,
        shift: NativeShiftSnapshot?,
        active: Bool,
        nowMs: Int64
    ) -> WidgetSnapshot {
        // On a schedule the schedule is the authority, not a flag. `active` only
        // decides anything for manual mode, which genuinely has sessions.
        //
        // This used to gate the recurring path on `countdownStarted`, so one
        // press of the stop button left the widget with nothing to say for every
        // day afterwards. The user's ask was the opposite: set it up once and
        // never think about it again.
        if store.followsSchedule, let shift {
            return makeRecurringSnapshot(store: store, initialShift: shift, nowMs: nowMs)
        }
        guard active else {
            return makeInactiveSnapshot(store: store, shift: shift, nowMs: nowMs)
        }
        guard let shift else {
            return idleSnapshot(store: store, nowMs: nowMs)
        }
        return makeSingleShiftSnapshot(store: store, shift: shift, nowMs: nowMs)
    }

    private func makeInactiveSnapshot(
        store: OffWorkStore,
        shift: NativeShiftSnapshot?,
        nowMs: Int64
    ) -> WidgetSnapshot {
        guard store.followsSchedule, let shift else {
            return idleSnapshot(store: store, nowMs: nowMs)
        }

        let currentStart = Int64(shift.startAtMs)
        if shift.isWorkday, currentStart > nowMs {
            return countdownToNextShift(
                store: store,
                target: currentStart,
                anchor: Int64(shift.countdownAnchorAtMs ?? shift.startAtMs),
                nowMs: nowMs
            )
        }
        if let nextStart = shift.nextShiftStartAtMs.map(Int64.init), nextStart > nowMs {
            return countdownToNextShift(
                store: store,
                target: nextStart,
                anchor: Int64(shift.countdownAnchorAtMs ?? shift.startAtMs),
                nowMs: nowMs
            )
        }
        return idleSnapshot(store: store, nowMs: nowMs)
    }

    private func makeRecurringSnapshot(
        store: OffWorkStore,
        initialShift: NativeShiftSnapshot,
        nowMs: Int64
    ) -> WidgetSnapshot {
        let now = Date(timeIntervalSince1970: Double(nowMs) / 1_000)
        let horizon = Calendar.current.date(
            byAdding: .day,
            value: recurringHorizonDays,
            to: now
        ) ?? now.addingTimeInterval(Double(recurringHorizonDays) * 86_400)
        let expiresAtMs = Int64(horizon.timeIntervalSince1970 * 1_000)
        let forcedCurrentShift = store.isForcedWorkday(initialShift)
        var entries: [WidgetTimelineEntry] = []
        var cursor = nowMs
        var diagnosticShift: WidgetShiftTimeline?
        let futureShifts = (try? CountdownRules.shared.widgetShifts(
            input: store.rulesInput(at: now, using: .base),
            throughMs: Double(expiresAtMs),
            maximumCount: maximumRecurringShifts
        )) ?? []

        // An early clock-off ends the shift it happened in and nothing else.
        // The rest of that workday is still "done for today"; rest-day copy
        // starts at the following midnight, not at the clock-off moment.
        if let endedEarlyAtMs = store.isEndedEarly(initialShift) ? store.earlyOffAtMs : nil {
            cursor = max(cursor, Int64(endedEarlyAtMs))
            appendDoneWindow(
                startingAtMs: cursor,
                shiftEndAtMs: Int64(initialShift.endAtMs),
                nextShiftStartAtMs: futureShifts.first.map { Int64($0.startAtMs) },
                cursor: &cursor,
                expiresAtMs: expiresAtMs,
                entries: &entries
            )
        } else if initialShift.isWorkday || forcedCurrentShift {
            let currentShift = widgetProjection(from: initialShift)
            diagnosticShift = widgetShift(from: currentShift)
            appendShift(
                currentShift,
                nextShiftStartAtMs: futureShifts.first.map { Int64($0.startAtMs) },
                cursor: &cursor,
                expiresAtMs: expiresAtMs,
                entries: &entries
            )
        }

        for (index, nextShift) in futureShifts.enumerated() {
            let resolvedStartAtMs = Int64(nextShift.startAtMs)
            guard resolvedStartAtMs > nowMs,
                  resolvedStartAtMs > cursor || Int64(nextShift.endAtMs) > cursor
            else { continue }
            appendCountdown(
                from: &cursor,
                to: resolvedStartAtMs,
                anchor: Int64(nextShift.countdownAnchorAtMs),
                expiresAtMs: expiresAtMs,
                entries: &entries
            )
            guard resolvedStartAtMs < expiresAtMs else { break }
            appendShift(
                nextShift,
                nextShiftStartAtMs: futureShifts.index(after: index) < futureShifts.endIndex
                    ? Int64(futureShifts[futureShifts.index(after: index)].startAtMs)
                    : nil,
                cursor: &cursor,
                expiresAtMs: expiresAtMs,
                entries: &entries
            )
        }

        if cursor < expiresAtMs {
            entries.append(idleEntry(nowMs: cursor, expiresAtMs: expiresAtMs))
        }

        return WidgetSnapshot(
            schemaVersion: widgetSnapshotSchemaVersion,
            generatedAtMs: nowMs,
            expiresAtMs: expiresAtMs,
            locale: store.languageCode,
            shift: diagnosticShift,
            entries: entries.isEmpty ? [idleEntry(nowMs: nowMs, expiresAtMs: expiresAtMs)] : entries
        )
    }

    private func makeSingleShiftSnapshot(
        store: OffWorkStore,
        shift: NativeShiftSnapshot,
        nowMs: Int64
    ) -> WidgetSnapshot {
        let endMs = Int64(shift.endAtMs)
        let endDate = Date(timeIntervalSince1970: Double(endMs) / 1_000)
        let endDay = Calendar.current.startOfDay(for: endDate)
        let rolloverDate = Calendar.current.date(byAdding: .day, value: 1, to: endDay) ?? endDate
        let rolloverAtMs = Int64(rolloverDate.timeIntervalSince1970 * 1_000)
        let expiresAtMs = max(
            rolloverAtMs + 24 * 60 * 60 * 1_000,
            nowMs + 60 * 60 * 1_000
        )
        var entries: [WidgetTimelineEntry] = []
        var cursor = nowMs
        let projectedShift = widgetProjection(from: shift)

        appendShift(
            projectedShift,
            nextShiftStartAtMs: nil,
            cursor: &cursor,
            expiresAtMs: expiresAtMs,
            entries: &entries
        )
        if cursor < expiresAtMs {
            entries.append(idleEntry(nowMs: cursor, expiresAtMs: expiresAtMs))
        }

        return WidgetSnapshot(
            schemaVersion: widgetSnapshotSchemaVersion,
            generatedAtMs: nowMs,
            expiresAtMs: expiresAtMs,
            locale: store.languageCode,
            shift: widgetShift(from: projectedShift),
            entries: entries
        )
    }

    private func appendCountdown(
        from cursor: inout Int64,
        to targetAtMs: Int64,
        anchor anchorAtMs: Int64,
        expiresAtMs: Int64,
        entries: inout [WidgetTimelineEntry]
    ) {
        guard cursor < targetAtMs, cursor < expiresAtMs else { return }

        let targetDate = Date(timeIntervalSince1970: Double(targetAtMs) / 1_000)
        let targetDayAtMs = Int64(
            Calendar.current.startOfDay(for: targetDate).timeIntervalSince1970 * 1_000
        )
        let restEndAtMs = min(targetDayAtMs, min(targetAtMs, expiresAtMs))

        // Whole calendar days before the workday are rest days. Once the clock
        // reaches midnight on the shift's own day, the copy changes to the
        // ordinary pre-work countdown.
        if cursor < restEndAtMs {
            entries.append(countdownEntry(
                date: cursor,
                end: restEndAtMs,
                target: targetAtMs,
                anchor: anchorAtMs,
                progressEnd: targetDayAtMs,
                label: "widgetRestDay"
            ))
            cursor = restEndAtMs
        }

        let countdownEndAtMs = min(targetAtMs, expiresAtMs)
        if cursor < countdownEndAtMs {
            entries.append(countdownEntry(
                date: cursor,
                end: countdownEndAtMs,
                target: targetAtMs,
                anchor: targetDayAtMs,
                progressEnd: targetAtMs,
                label: "nextShiftLabelShort"
            ))
            cursor = countdownEndAtMs
        }
    }

    private func appendShift(
        _ shift: NativeWidgetShiftSnapshot,
        nextShiftStartAtMs: Int64?,
        cursor: inout Int64,
        expiresAtMs: Int64,
        entries: inout [WidgetTimelineEntry]
    ) {
        let shiftStartAtMs = Int64(shift.startAtMs)
        if cursor < shiftStartAtMs {
            appendCountdown(
                from: &cursor,
                to: shiftStartAtMs,
                anchor: Int64(shift.countdownAnchorAtMs),
                expiresAtMs: expiresAtMs,
                entries: &entries
            )
        }

        let segments = shift.segments.map {
            WidgetShiftSegment(startAtMs: Int64($0.startAtMs), endAtMs: Int64($0.endAtMs))
        }
        let duration = max(Int64(1), Int64(shift.durationMs))

        for (index, segment) in segments.enumerated() {
            guard cursor < expiresAtMs else { return }
            let completedBefore = segments.prefix(index).reduce(Int64(0)) {
                $0 + $1.endAtMs - $1.startAtMs
            }

            if cursor < segment.startAtMs {
                let breakStartAtMs = max(
                    cursor,
                    index == 0 ? shiftStartAtMs : segments[index - 1].endAtMs
                )
                let breakEndAtMs = min(segment.startAtMs, expiresAtMs)
                if breakStartAtMs < breakEndAtMs {
                    entries.append(entry(
                        date: breakStartAtMs,
                        end: breakEndAtMs,
                        phase: .break,
                        label: "lunchInProgress",
                        kind: .breakEnds,
                        remaining: max(0, duration - completedBefore),
                        progress: Double(completedBefore) / Double(duration) * 100,
                        boundary: segment.startAtMs,
                        target: segment.startAtMs
                    ))
                    cursor = breakEndAtMs
                }
            }

            let workStartAtMs = max(cursor, segment.startAtMs)
            let workEndAtMs = min(segment.endAtMs, expiresAtMs)
            if workStartAtMs < workEndAtMs {
                let elapsed = completedBefore + max(0, workStartAtMs - segment.startAtMs)
                let remaining = max(0, duration - elapsed)
                entries.append(entry(
                    date: workStartAtMs,
                    end: workEndAtMs,
                    phase: .working,
                    label: "widgetWorking",
                    kind: .workRemaining,
                    remaining: remaining,
                    progress: Double(elapsed) / Double(duration) * 100,
                    boundary: segment.endAtMs,
                    target: workStartAtMs + remaining
                ))
                cursor = workEndAtMs
            }
        }

        let endAtMs = Int64(shift.endAtMs)
        appendDoneWindow(
            startingAtMs: endAtMs,
            shiftEndAtMs: endAtMs,
            nextShiftStartAtMs: nextShiftStartAtMs,
            cursor: &cursor,
            expiresAtMs: expiresAtMs,
            entries: &entries
        )
    }

    /// "Done for today" from `startingAtMs` until the next midnight of the
    /// shift's end day, or the next shift, whichever is sooner. Early clock-off
    /// starts this window at the moment they finished rather than the planned
    /// end, so the rest of a workday is not painted as a rest day.
    private func appendDoneWindow(
        startingAtMs: Int64,
        shiftEndAtMs: Int64,
        nextShiftStartAtMs: Int64?,
        cursor: inout Int64,
        expiresAtMs: Int64,
        entries: inout [WidgetTimelineEntry]
    ) {
        let endDate = Date(timeIntervalSince1970: Double(shiftEndAtMs) / 1_000)
        let endDay = Calendar.current.startOfDay(for: endDate)
        let rolloverDate = Calendar.current.date(byAdding: .day, value: 1, to: endDay) ?? endDate
        let rolloverAtMs = Int64(rolloverDate.timeIntervalSince1970 * 1_000)
        let doneStartAtMs = max(cursor, startingAtMs)
        let doneEndAtMs = min(
            min(rolloverAtMs, expiresAtMs),
            nextShiftStartAtMs ?? Int64.max
        )

        if doneStartAtMs < doneEndAtMs {
            entries.append(entry(
                date: doneStartAtMs,
                end: doneEndAtMs,
                phase: .done,
                label: "offWorkToday",
                kind: .complete,
                remaining: 0,
                progress: 100,
                boundary: nil,
                target: nil
            ))
            cursor = doneEndAtMs
        }
    }

    private func countdownToNextShift(
        store: OffWorkStore,
        target: Int64,
        anchor: Int64,
        nowMs: Int64
    ) -> WidgetSnapshot {
        let endAtMs = max(nowMs + 60_000, target)
        var cursor = nowMs
        var entries: [WidgetTimelineEntry] = []
        appendCountdown(
            from: &cursor,
            to: target,
            anchor: anchor,
            expiresAtMs: endAtMs,
            entries: &entries
        )
        return WidgetSnapshot(
            schemaVersion: widgetSnapshotSchemaVersion,
            generatedAtMs: nowMs,
            expiresAtMs: endAtMs,
            locale: store.languageCode,
            shift: nil,
            entries: entries
        )
    }

    private func idleSnapshot(store: OffWorkStore, nowMs: Int64) -> WidgetSnapshot {
        let expiresAtMs = nowMs + 24 * 60 * 60 * 1_000
        return WidgetSnapshot(
            schemaVersion: widgetSnapshotSchemaVersion,
            generatedAtMs: nowMs,
            expiresAtMs: expiresAtMs,
            locale: store.languageCode,
            shift: nil,
            entries: [idleEntry(nowMs: nowMs, expiresAtMs: expiresAtMs)]
        )
    }

    private func countdownEntry(
        date: Int64,
        end: Int64,
        target: Int64,
        anchor: Int64,
        progressEnd: Int64,
        label: String
    ) -> WidgetTimelineEntry {
        let duration = max(Int64(1), progressEnd - anchor)
        let elapsed = min(duration, max(0, date - anchor))
        return entry(
            date: date,
            end: end,
            phase: .before,
            label: label,
            kind: .shiftStarts,
            remaining: max(0, target - date),
            progress: Double(elapsed) / Double(duration) * 100,
            boundary: target,
            target: target
        )
    }

    private func idleEntry(nowMs: Int64, expiresAtMs: Int64) -> WidgetTimelineEntry {
        entry(
            date: nowMs,
            end: expiresAtMs,
            phase: .idle,
            label: "countdownNotStarted",
            kind: .none,
            remaining: 0,
            progress: 0,
            boundary: nil,
            target: nil
        )
    }

    private func widgetProjection(from shift: NativeShiftSnapshot) -> NativeWidgetShiftSnapshot {
        NativeWidgetShiftSnapshot(
            segments: shift.segments,
            startAtMs: shift.startAtMs,
            endAtMs: shift.endAtMs,
            plannedEndAtMs: shift.plannedEndAtMs,
            overtimeEndAtMs: shift.overtimeEndAtMs,
            durationMs: shift.durationMs,
            countdownAnchorAtMs: shift.countdownAnchorAtMs ?? shift.startAtMs
        )
    }

    private func widgetShift(from shift: NativeWidgetShiftSnapshot) -> WidgetShiftTimeline {
        WidgetShiftTimeline(
            segments: shift.segments.map {
                WidgetShiftSegment(startAtMs: Int64($0.startAtMs), endAtMs: Int64($0.endAtMs))
            },
            plannedEndAtMs: Int64(shift.plannedEndAtMs),
            overtimeEndAtMs: shift.overtimeEndAtMs.map(Int64.init)
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
