import Foundation

/// Reshaping an extended schedule on the schedule page (plan 018 P8-c1b).
///
/// The page keeps `ExtendedScheduleContent` as a draft and saves it with the
/// rest of the page, so every step here returns a new value and stores
/// nothing.
nonisolated enum ExtendedScheduleEditing {
    /// Longest cycle the page offers. The data allows a year; a rotation longer
    /// than eight weeks is not something people set up one day at a time.
    static let maximumCycleLength = 60
    static let restColor = "#8E8E93"
    /// The system accent hues, which stay legible as small dots in both
    /// appearances. A new type takes the first one no active type uses.
    static let palette = ["#FF9500", "#007AFF", "#AF52DE", "#34C759", "#FF2D55", "#30B0C7", "#5856D6", "#A2845E"]

    static func nextColor(after types: [ShiftType]) -> String {
        let used = Set(types.filter { !$0.isArchived }.map { $0.colorHex.uppercased() })
        return palette.first { !used.contains($0) } ?? palette[types.count % palette.count]
    }

    /// The types the page lists and offers for a day: archived ones are kept
    /// only so days already worked under them still resolve.
    static func activeTypes(in content: ExtendedScheduleContent) -> [ShiftType] {
        content.shiftTypes.filter { !$0.isArchived }
    }

    static func upserting(_ type: ShiftType, in content: ExtendedScheduleContent) -> ExtendedScheduleContent {
        var next = content
        if let index = next.shiftTypes.firstIndex(where: { $0.id == type.id }) {
            next.shiftTypes[index] = type
        } else {
            next.shiftTypes.append(type)
        }
        return next
    }

    /// Whether the rule still hands this type out. Such a type cannot go until
    /// its days are given another one, or those days would silently turn into
    /// rest.
    static func ruleUses(_ id: UUID, in content: ExtendedScheduleContent) -> Bool {
        content.rule?.days.contains(id) == true
    }

    /// Removes a type from the page. One that has been saved is archived
    /// instead, because days already worked under it still name it.
    static func removing(
        _ id: UUID,
        from content: ExtendedScheduleContent,
        saved: ExtendedScheduleContent?
    ) -> ExtendedScheduleContent {
        var next = content
        if saved?.shiftTypes.contains(where: { $0.id == id }) == true {
            if let index = next.shiftTypes.firstIndex(where: { $0.id == id }) {
                next.shiftTypes[index].isArchived = true
            }
        } else {
            next.shiftTypes.removeAll { $0.id == id }
        }
        return next
    }

    /// Gives the cycle's day at zero-based `index` another type.
    static func assigning(_ typeID: UUID, at index: Int, in content: ExtendedScheduleContent) -> ExtendedScheduleContent {
        guard var rule = content.rule, rule.days.indices.contains(index) else { return content }
        rule.days[index] = typeID
        var next = content
        next.rule = rule
        return next
    }

    /// Lengthens the cycle with rest days, or drops days from its end.
    static func resizing(_ content: ExtendedScheduleContent, to length: Int, restName: String) -> ExtendedScheduleContent {
        guard var rule = content.rule else { return content }
        let length = min(max(1, length), maximumCycleLength)
        var next = content
        if length < rule.days.count {
            rule.days.removeLast(rule.days.count - length)
        } else if length > rule.days.count {
            let rest = restTypeID(in: &next, name: restName)
            rule.days += Array(repeating: rest, count: length - rule.days.count)
        }
        next.rule = rule
        return next
    }

    /// Today's one-based place in the cycle.
    static func cycleDay(of rule: ShiftCycleRule, todayKey: String) -> Int? {
        guard !rule.days.isEmpty,
              let anchor = ExtendedScheduleResolver.dayNumber(dayKey: rule.anchorDayKey),
              let today = ExtendedScheduleResolver.dayNumber(dayKey: todayKey)
        else { return nil }
        let count = rule.days.count
        return ((today - anchor) % count + count) % count + 1
    }

    /// Moves the cycle so today is day `position`; what each day of the cycle
    /// works stays the same.
    static func anchoring(
        _ content: ExtendedScheduleContent,
        todayKey: String,
        atCycleDay position: Int
    ) -> ExtendedScheduleContent {
        guard var rule = content.rule,
              let today = ExtendedScheduleResolver.dayNumber(dayKey: todayKey)
        else { return content }
        rule.anchorDayKey = dayKey(dayNumber: today - (position - 1))
        var next = content
        next.rule = rule
        return next
    }

    /// The day key `offset` days after `dayKey`, counted on the civil calendar.
    static func dayKey(_ dayKey: String, plus offset: Int) -> String? {
        ExtendedScheduleResolver.dayNumber(dayKey: dayKey).map { self.dayKey(dayNumber: $0 + offset) }
    }

    static func dayKey(dayNumber: Int) -> String {
        let date = CivilZone.civilDate(dayNumber: dayNumber)
        return String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
    }

    /// The rule's work days get `workType`, its rest days a rest type — the
    /// first active one, or a new one when the user has none left.
    static func filling(
        _ content: ExtendedScheduleContent,
        preset: ShiftCycleRule.Preset,
        pattern: ExtendedSchedulePattern,
        workType: UUID,
        restName: String
    ) -> ExtendedScheduleContent {
        var next = content
        let rest = restTypeID(in: &next, name: restName)
        next.rule = ShiftCycleRule(
            preset: preset,
            anchorDayKey: pattern.anchorDayKey,
            days: pattern.workdays.map { $0 ? workType : rest }
        )
        return next
    }

    /// The work type a template fills its work days with: the one the rule
    /// already uses first, so changing the template keeps the shift the user
    /// picked.
    static func primaryWorkType(in content: ExtendedScheduleContent) -> UUID? {
        let active = activeTypes(in: content).filter { $0.kind == .work }
        let ids = Set(active.map(\.id))
        return content.rule?.days.first(where: ids.contains) ?? active.first?.id
    }

    private static func restTypeID(in content: inout ExtendedScheduleContent, name: String) -> UUID {
        if let rest = activeTypes(in: content).first(where: { $0.kind == .rest }) { return rest.id }
        let type = ShiftType(
            id: UUID(),
            name: name,
            kind: .rest,
            startMinutes: 9 * 60,
            endMinutes: 17 * 60,
            breakEnabled: false,
            breakStartMinutes: 12 * 60,
            breakDurationMinutes: 60,
            colorHex: restColor,
            isArchived: false
        )
        content.shiftTypes.append(type)
        return type.id
    }
}

/// One cycle of an existing schedule: where it starts and which of its days
/// are workdays.
nonisolated struct ExtendedSchedulePattern: Equatable, Sendable {
    var anchorDayKey: String
    var workdays: [Bool]
}

extension ShiftSession {
    /// A first extended schedule that works exactly the days the user's current
    /// schedule does: one work type with its hours and lunch as the break, one
    /// rest type, and a rule copied from the current mode.
    func seededExtendedContent(applying change: ScheduleFieldChange, at date: Date) -> ExtendedScheduleContent {
        let lunchOn = change.lunchEnabled ?? preferences.lunchEnabled
        let work = ShiftType(
            id: UUID(),
            name: text.t("extendedDefaultWorkShift"),
            kind: .work,
            startMinutes: change.startMinutes ?? preferences.startMinutes,
            endMinutes: change.endMinutes ?? preferences.endMinutes,
            breakEnabled: lunchOn,
            breakStartMinutes: change.lunchStartMinutes ?? preferences.lunchStartMinutes,
            breakDurationMinutes: change.lunchDurationMinutes ?? preferences.lunchDurationMinutes,
            colorHex: ExtendedScheduleEditing.palette[0],
            isArchived: false
        )
        let preset: ShiftCycleRule.Preset = switch change.scheduleMode ?? preferences.scheduleMode {
        case .alternating: .alternatingWeeks
        case .rotation: .rotation
        case .classic, .off: .weekly
        }
        return ExtendedScheduleEditing.filling(
            ExtendedScheduleContent(shiftTypes: [work], rule: nil),
            preset: preset,
            pattern: schedulePattern(for: preset, applying: change, at: date),
            workType: work.id,
            restName: text.t("extendedDefaultRest")
        )
    }

    /// The same content with its rule replaced by a template, filled from the
    /// user's saved settings for that kind of schedule.
    func applyingTemplate(
        _ preset: ShiftCycleRule.Preset,
        to content: ExtendedScheduleContent,
        at date: Date
    ) -> ExtendedScheduleContent {
        guard let work = ExtendedScheduleEditing.primaryWorkType(in: content) else { return content }
        return ExtendedScheduleEditing.filling(
            content,
            preset: preset,
            pattern: schedulePattern(for: preset, applying: ScheduleFieldChange(), at: date),
            workType: work,
            restName: text.t("extendedDefaultRest")
        )
    }

    /// Today's day key in the zone the rules resolve in.
    func extendedTodayKey(at date: Date) -> String {
        Self.dayKey(for: date, timeZone: countdownTimeZone)
    }

    /// One cycle of the fixed-weekday, alternating or rotation schedule the
    /// page describes, answered by the shared rules rather than re-derived, so
    /// the extended copy works the same days.
    ///
    /// A mode other than the current one starts from today the way switching
    /// to it on the page would; the current one keeps its own anchor, since
    /// re-anchoring an alternating week would flip which week is which.
    func schedulePattern(
        for preset: ShiftCycleRule.Preset,
        applying change: ScheduleFieldChange,
        at date: Date
    ) -> ExtendedSchedulePattern {
        let mode: WorkScheduleMode = switch preset {
        case .weekly: .classic
        case .alternatingWeeks: .alternating
        case .rotation, .custom: .rotation
        }
        var probe = change
        probe.extendedScheduleEnabled = false
        probe.extendedContent = nil
        if mode != (change.scheduleMode ?? preferences.scheduleMode) { probe.scheduleMode = mode }
        let input = rulesInput(applying: probe, at: date)
        let zone = TimeZone(identifier: input.timeZoneIdentifier ?? "") ?? countdownTimeZone
        let today = ExtendedScheduleResolver.dayNumber(dayKey: Self.dayKey(for: date, timeZone: zone)) ?? 0

        let length: Int
        let startDay: Int
        switch mode {
        case .rotation:
            length = max(1, (input.schedule.rotationWorkDays ?? 1) + (input.schedule.rotationRestDays ?? 1))
            let anchorMs = input.schedule.rotationAnchorMs ?? date.timeIntervalSince1970 * 1_000
            let anchor = ExtendedScheduleResolver.dayNumber(
                dayKey: Self.dayKey(for: Date(timeIntervalSince1970: anchorMs / 1_000), timeZone: zone)
            ) ?? today
            startDay = today - ((today - anchor) % length + length) % length
        default:
            length = mode == .alternating ? 14 : 7
            let monday = PreferencesStore.startOfWeek(containing: date, timeZone: zone)
            startDay = ExtendedScheduleResolver.dayNumber(dayKey: Self.dayKey(for: monday, timeZone: zone)) ?? today
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let startKey = ExtendedScheduleEditing.dayKey(dayNumber: startDay)
        let workdays: [Bool]
        if let first = RecordJSON.date(fromDayKey: startKey, calendar: calendar),
           let last = calendar.date(byAdding: .day, value: length - 1, to: first) {
            let hours = ScheduleHoursConfiguration(
                startTime: input.startTime,
                endTime: input.endTime,
                workdays: input.workdays,
                schedule: input.schedule,
                breakStartTime: input.breakStartTime,
                breakDurationMinutes: input.breakDurationMinutes
            )
            let days = ScheduleRules.expandScheduleRange(configuration: hours, from: first, through: last, timeZone: zone)
            workdays = days.count == length ? days.map(\.isWorkday) : Array(repeating: true, count: length)
        } else {
            workdays = Array(repeating: true, count: length)
        }
        return ExtendedSchedulePattern(anchorDayKey: startKey, workdays: workdays)
    }
}
