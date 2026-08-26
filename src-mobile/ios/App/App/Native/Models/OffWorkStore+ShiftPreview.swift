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

        // Everything still to come today belongs to a shift the user has said
        // they are done with, so none of it is coming. Move the whole list past
        // it and read from the next shift instead — otherwise the page answers
        // "what happens next" with a lunch and a clock-off that will not.
        let endedEarly = isEndedEarly(snapshot)
        let floorMs = endedEarly ? snapshot.endAtMs : nowMs

        func isAhead(_ atMs: Double) -> Bool { atMs > floorMs && atMs <= snapshot.endAtMs }

        // Once the shift has begun, "start time" means the *next* one. Giving it
        // that date rather than today's is what moves it to the end of the list
        // on its own, and the row's weekday tells the user which day it is.
        let startHasPassed = endedEarly || nowMs >= snapshot.startAtMs
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

            // One row, not two. On the running page the two boundaries are
            // separate events you are waiting for; here it is a setting, and a
            // setting is a window — "12:00 – 13:00" says everything the two
            // rows said, in half the space, on a page whose job is to be
            // scannable.
            let windowStart = (!endedEarly && lunch.start > now) ? lunch.start : nextOccurrence(of: lunch.start)
            let windowEnd = (!endedEarly && lunch.end > now) ? lunch.end : nextOccurrence(of: lunch.end)
            if let windowStart, let windowEnd {
                upcoming.append(.init(
                    id: "lunch",
                    kind: .lunchStart,
                    title: t("lunchBreak"),
                    detail: t("lunchWindow", values: [
                        "start": formatTime(windowStart),
                        "end": formatTime(windowEnd)
                    ]),
                    date: windowStart,
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
            // Hangs off whichever shift end is still ahead. Opening the app
            // after clocking off otherwise put this at the top of the list,
            // announcing a lock-screen banner that came and went hours ago.
            let lead = Double(-liveActivityLeadMinutes * 60)
            let thisShift = snapshot.plannedEndDate.addingTimeInterval(lead)
            let at = (!endedEarly && thisShift > now)
                ? thisShift
                : snapshot.nextShiftEndDate?.addingTimeInterval(lead)
            if let at {
                upcoming.append(.init(
                    id: "live-activity",
                    kind: .liveActivity,
                    title: t("liveActivity"),
                    detail: t("liveActivityLead", values: ["count": "\(liveActivityLeadMinutes)"]),
                    date: at,
                    route: .notifications
                ))
            }
        }

        // One row for the whole off-work reminder, named after the page it opens
        // rather than after the Live Activity, which is only one switch on that
        // page. The timed row above keeps the Live Activity's own name, because
        // that is the thing that actually appears at 22:45.
        //
        // Both switches, not either. This asked `||`, so turning off just one
        // of the two mechanisms printed "off-work reminder: disabled" while the
        // other was still firing — and with the Live Activity on and
        // notifications off the list contradicted itself outright, showing the
        // timed Live Activity row directly above a row calling the same feature
        // disabled.
        if !liveActivityEnabled && notificationMode == .off {
            disabled.append(.init(
                id: "off-work-reminder-off",
                kind: .offWorkReminder,
                title: t("offWorkReminder"),
                detail: t("disabledShort"),
                date: nil,
                route: .notifications
            ))
        }

        // The last row that still described a moment already behind us. With
        // clock-in, the break and the Live Activity all rolling forward, leaving
        // this one on today's date put "off at 14:00" under tomorrow's 09:00 —
        // the list read backwards at its own finish line. Rolled, the whole
        // thing runs in one direction again, and clock-off lands where it
        // belongs: last.
        //
        // `nextShiftEndDate` rather than an offset from the next start: the
        // rules already resolved it, including any day whose shift the schedule
        // shapes differently.
        let endDate: Date? = (!endedEarly && snapshot.endDate > now) ? snapshot.endDate : snapshot.nextShiftEndDate
        if let endDate {
            upcoming.append(.init(
                id: "shift-end",
                kind: .shiftEnd,
                title: t("endTime"),
                // Same as the start row: "today's shift" is a lie once it is
                // tomorrow's, and the weekday in the time column says which day.
                detail: (!endedEarly && snapshot.endDate > now) ? t("todaysShift") : nil,
                date: endDate,
                route: nil
            ))
        }

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
