import CryptoKit
import Foundation

// Plan 020 §3: a wake-up alarm a set time before each shift, planned from the
// same resolved schedule the countdown follows and handed to AlarmKit as
// one-off absolute times. Alarms belong to this device: the settings stay in
// local preferences and never sync.

/// How long before each shift its alarm rings.
nonisolated struct ShiftAlarmSettings: Codable, Equatable, Sendable {
    static let defaultLeadMinutes = 60
    /// 15 minutes to 3 hours.
    static let leadChoices = [15, 30, 45, 60, 75, 90, 105, 120, 150, 180]
    /// Matches the system Clock app.
    static let snoozeMinutes = 9

    var isEnabled = false
    /// Fixed hours, and any shift type without an entry of its own.
    var defaultLeadMinutes = Self.defaultLeadMinutes
    var leadMinutesByShiftType: [UUID: Int] = [:]
    /// Shift types the person wants no alarm for, such as a late shift they
    /// wake up for on their own.
    var silencedShiftTypeIDs: Set<UUID> = []

    /// Order-independent, for change detection.
    var signature: String {
        let leads = leadMinutesByShiftType.map { "\($0.key.uuidString)=\($0.value)" }.sorted()
        let silenced = silencedShiftTypeIDs.map(\.uuidString).sorted()
        return "alarms-\(isEnabled)-\(defaultLeadMinutes)-\(leads.joined(separator: ","))-\(silenced.joined(separator: ","))"
    }

    /// `nil` when this shift gets no alarm.
    func leadMinutes(for shiftTypeID: UUID?) -> Int? {
        guard let shiftTypeID else { return defaultLeadMinutes }
        if silencedShiftTypeIDs.contains(shiftTypeID) { return nil }
        return leadMinutesByShiftType[shiftTypeID] ?? defaultLeadMinutes
    }
}

/// One alarm the schedule asks for.
nonisolated struct PlannedShiftAlarm: Equatable, Sendable, Identifiable {
    /// Derived from everything the alarm says and when it rings, so the same
    /// alarm keeps its id across launches and any change to it is a new one.
    var id: UUID
    var fireAtMs: Double
    var shiftStartAtMs: Double
    /// The civil day the shift starts on.
    var dayKey: String
    var shiftTypeID: UUID?
    /// The shift type's name; `nil` for fixed hours.
    var shiftName: String?
}

nonisolated enum ShiftAlarmPlanner {
    /// The last moment alarms may ring for this entitlement, or `nil` when it
    /// allows none. A subscription stops at its exact expiry rather than that
    /// day's midnight and never assumes the next period; lifetime looks one
    /// calendar year ahead from `now`.
    static func windowEnd(for authorization: PlusAuthorization, now: Date, calendar: Calendar) -> Date? {
        switch authorization {
        case .authorized(.subscribed(let expiresAt)): expiresAt > now ? expiresAt : nil
        case .authorized(.inGracePeriod(let graceExpiresAt)): graceExpiresAt > now ? graceExpiresAt : nil
        case .authorized(.lifetime): calendar.date(byAdding: .year, value: 1, to: now)
        case .unauthorized, .pendingAskToBuy: nil
        }
    }

    /// Every alarm that rings after `nowMs` and strictly before `untilMs`,
    /// earliest first. Rest days, holidays and leave come from
    /// `configuration` exactly as the countdown sees them; a lead time can
    /// reach back into the previous day.
    static func alarms(
        configuration: ScheduleHoursConfiguration,
        timeZone: TimeZone,
        settings: ShiftAlarmSettings,
        nowMs: Double,
        untilMs: Double
    ) -> [PlannedShiftAlarm] {
        guard settings.isEnabled, untilMs > nowMs else { return [] }
        let zone = CivilZone(timeZone: timeZone)
        // A day either side: yesterday's overnight shift has started already,
        // and a shift just after the window can still ring inside it.
        let firstDay = zone.civil(nowMs).dayNumber - 1
        let lastDay = zone.civil(untilMs).dayNumber + 1
        func noon(_ dayNumber: Int) -> Date {
            Date(timeIntervalSince1970: zone.utcMs(dayNumber: dayNumber, Clock(hour: 12, minute: 0)) / 1_000)
        }
        let expanded = ScheduleRules.expandScheduleRange(
            configuration: configuration, from: noon(firstDay), through: noon(lastDay), timeZone: timeZone
        )
        guard expanded.count == lastDay - firstDay + 1 else { return [] }
        let plan = configuration.extendedSchedule
        let resolver = plan.map(ExtendedScheduleResolver.init(plan:))

        return expanded.enumerated().compactMap { offset, day -> PlannedShiftAlarm? in
            guard day.isWorkday, let start = day.segments.first?.startAtMs else { return nil }
            let typeID = resolver?.day(dayNumber: firstDay + offset).shiftTypeID
            guard let lead = settings.leadMinutes(for: typeID) else { return nil }
            let fireAtMs = start - Double(lead) * 60_000
            guard fireAtMs > nowMs, fireAtMs < untilMs else { return nil }
            let name = typeID.flatMap { id in plan?.shiftTypes.first { $0.id == id }?.name }
            return PlannedShiftAlarm(
                id: stableID(dayKey: day.dayKey, fireAtMs: fireAtMs, shiftStartAtMs: start, shiftName: name),
                fireAtMs: fireAtMs,
                shiftStartAtMs: start,
                dayKey: day.dayKey,
                shiftTypeID: typeID,
                shiftName: name
            )
        }
    }

    /// A name-based UUID (version 5 layout over SHA-256) of the alarm's
    /// content.
    static func stableID(dayKey: String, fireAtMs: Double, shiftStartAtMs: Double, shiftName: String?) -> UUID {
        let content = "owc.shiftAlarm|\(dayKey)|\(Int64(fireAtMs))|\(Int64(shiftStartAtMs))|\(shiftName ?? "")"
        var bytes = Array(SHA256.hash(data: Data(content.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
