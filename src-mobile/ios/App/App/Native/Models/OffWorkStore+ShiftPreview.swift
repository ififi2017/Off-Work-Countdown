import Foundation

/// The pre-start preview, split into what will happen and what is switched off.
struct ShiftPreview {
    /// Things with a time, in the order they will occur.
    let upcoming: [ShiftPreviewEntry]
    /// Features the user has not turned on. They have no time, so they cannot
    /// sit in a list headed "coming up" — the view keeps them apart.
    let disabled: [ShiftPreviewEntry]
}

extension OffWorkStore {
    /// What today's shift will do, one row per kind of event.
    ///
    /// Everything that is switched on carries the time it will next happen and
    /// is sorted by it. Everything switched off is still listed, saying so,
    /// because someone opening the app for the first time cannot turn on a
    /// feature they have never seen.
    func shiftPreview(for snapshot: NativeShiftSnapshot, at now: Date = .now) -> ShiftPreview {
        var upcoming: [ShiftPreviewEntry] = []
        var disabled: [ShiftPreviewEntry] = []
        let nowMs = now.timeIntervalSince1970 * 1_000
        let reminders = (try? CountdownRules.shared.reminders(
            input: rulesInput(at: now),
            reminderInputs: reminderInputs()
        )) ?? []

        func isAhead(_ atMs: Double) -> Bool { atMs > nowMs && atMs <= snapshot.endAtMs }

        // Once the shift has begun, "start time" means the *next* one. Giving it
        // that date rather than today's is what moves it to the end of the list
        // on its own, and the row's weekday tells the user which day it is.
        let startHasPassed = nowMs >= snapshot.startAtMs
        if let start = startHasPassed ? snapshot.nextShiftStartDate : snapshot.startDate {
            upcoming.append(.init(
                id: "shift-start",
                kind: .shiftStart,
                title: t("startTime"),
                detail: startHasPassed ? nil : t("todaysShift"),
                date: start,
                route: nil
            ))
        }

        if lunchEnabled, let lunch = lunchWindow(in: snapshot) {
            // Each boundary rolls forward on its own once it has passed, the
            // same way the start time above does — otherwise an afternoon spent
            // on this page is headed by a break that finished hours ago.
            //
            // Rolling them separately is deliberate: during the break itself
            // "开始时间" is already the next shift's while "恢复时间" is still
            // today's, which is exactly what is true.
            //
            // The offset is taken from the resolved window rather than from
            // `lunchStartMinutes` so an overnight shift's after-midnight break
            // lands on the right day. Every shift is the same shape — one
            // start, one end, one break for all workdays — so carrying today's
            // offset onto the next start is exact, not an estimate.
            func nextOccurrence(of date: Date) -> Date? {
                snapshot.nextShiftStartDate.map {
                    $0.addingTimeInterval(date.timeIntervalSince(snapshot.startDate))
                }
            }

            // Nil only when the schedule has no further shift to hang it on, in
            // which case the row is dropped exactly like the start time is.
            if let start = lunch.start > now ? lunch.start : nextOccurrence(of: lunch.start) {
                upcoming.append(.init(
                    id: "lunch-start",
                    kind: .lunchStart,
                    title: t("lunchBreak"),
                    detail: t("lunchStartTime"),
                    date: start,
                    route: .lunch
                ))
            }
            if let end = lunch.end > now ? lunch.end : nextOccurrence(of: lunch.end) {
                upcoming.append(.init(
                    id: "lunch-end",
                    kind: .lunchEnd,
                    title: t("lunchBreak"),
                    detail: t("lunchBackAt"),
                    date: end,
                    route: .lunch
                ))
            }
        } else {
            disabled.append(.init(
                id: "lunch-off",
                kind: .lunchStart,
                title: t("lunchBreak"),
                detail: t("disabledShort"),
                date: nil,
                route: .lunch
            ))
        }

        // One row, not one per firing: an hourly reminder across a nine-hour
        // shift is eight identical lines. The detail carries the interval so the
        // single row still says it repeats.
        if microBreakEnabled {
            upcoming.append(.init(
                id: "micro-break",
                kind: .health,
                title: t("microBreakReminder"),
                detail: t("minutesShort", values: ["count": "\(microBreakIntervalMinutes)"]),
                date: reminders
                    .filter { $0.kind == "microBreak" && isAhead($0.atMs) }
                    .min(by: { $0.atMs < $1.atMs })
                    .map { Date(timeIntervalSince1970: $0.atMs / 1_000) },
                route: .health
            ))
        } else {
            disabled.append(.init(
                id: "micro-break-off",
                kind: .health,
                title: t("microBreakReminder"),
                detail: t("disabledShort"),
                date: nil,
                route: .health
            ))
        }


        if liveActivityEnabled {
            upcoming.append(.init(
                id: "live-activity",
                kind: .liveActivity,
                title: t("liveActivity"),
                detail: t("liveActivityLead", values: ["count": "\(liveActivityLeadMinutes)"]),
                date: snapshot.plannedEndDate.addingTimeInterval(Double(-liveActivityLeadMinutes * 60)),
                route: .notifications
            ))
        }

        // One row for the whole off-work reminder, named after the page it opens
        // rather than after the Live Activity, which is only one switch on that
        // page. The timed row above keeps the Live Activity's own name, because
        // that is the thing that actually appears at 22:45.
        if !liveActivityEnabled || notificationMode == .off {
            disabled.append(.init(
                id: "off-work-reminder-off",
                kind: .offWorkReminder,
                title: t("offWorkReminder"),
                detail: t("disabledShort"),
                date: nil,
                route: .notifications
            ))
        }

        upcoming.append(.init(
            id: "shift-end",
            kind: .shiftEnd,
            title: t("endTime"),
            detail: t("todaysShift"),
            date: snapshot.endDate,
            route: nil
        ))

        // The schedule has no single moment either — it decides *which days*
        // exist, not what happens within one — so it belongs with the standing
        // settings rather than in the timeline. It is always listed, because
        // unlike the rest it is never simply off.
        disabled.append(.init(
            id: "schedule",
            kind: .schedule,
            title: t("workSchedule"),
            detail: scheduleLabel,
            date: nil,
            route: .schedule
        ))

        return ShiftPreview(
            upcoming: upcoming.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) },
            disabled: disabled
        )
    }

    /// The break as the rules engine actually placed it — read off the gap
    /// between two work segments rather than from `lunchStartMinutes`, so an
    /// overnight shift's after-midnight break lands on the right day.
    private func lunchWindow(in snapshot: NativeShiftSnapshot) -> (start: Date, end: Date)? {
        for (index, segment) in snapshot.segments.dropLast().enumerated() {
            let next = snapshot.segments[index + 1]
            guard next.startAtMs > segment.endAtMs else { continue }
            return (
                Date(timeIntervalSince1970: segment.endAtMs / 1_000),
                Date(timeIntervalSince1970: next.startAtMs / 1_000)
            )
        }
        return nil
    }
}
