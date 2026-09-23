import Foundation

// Android task T08. Extended scheduling (plan 018 P8) is iOS-only behaviour with
// no TypeScript oracle, so the Swift implementation is the specification. This
// tool compiles the real `src-mobile/ios/Shared` sources plus the rules models
// and prints deterministic cases; `scripts/generate-android-extended-fixtures.mjs`
// runs it and writes the JSON the Kotlin port is tested against. Not shipped.

// MARK: - Minimal JSON

indirect enum J: Encodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([J])
    case object([(String, J)])

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .null:
            var c = encoder.singleValueContainer(); try c.encodeNil()
        case .bool(let v):
            var c = encoder.singleValueContainer(); try c.encode(v)
        case .number(let v):
            var c = encoder.singleValueContainer()
            if v.rounded() == v, abs(v) < 9e15 { try c.encode(Int64(v)) } else { try c.encode(v) }
        case .string(let v):
            var c = encoder.singleValueContainer(); try c.encode(v)
        case .array(let v):
            var c = encoder.unkeyedContainer()
            for item in v { try c.encode(item) }
        case .object(let pairs):
            var c = encoder.container(keyedBy: Key.self)
            for (key, value) in pairs { try c.encode(value, forKey: Key(key)) }
        }
    }

    struct Key: CodingKey {
        let stringValue: String
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }
}

func n(_ v: Double?) -> J { v.map(J.number) ?? .null }
func n(_ v: Int?) -> J { v.map { J.number(Double($0)) } ?? .null }
func s(_ v: String?) -> J { v.map(J.string) ?? .null }

let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return e
}()

func line(_ value: J) -> String { String(decoding: try! encoder.encode(value), as: UTF8.self) }

// MARK: - Inputs

func id(_ value: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012X", value))! }

func type(
    _ number: Int, _ name: String, _ kind: ShiftType.Kind, _ start: Int, _ end: Int,
    breakAt: Int? = nil, breakMinutes: Int = 0, breakEnabled: Bool? = nil, archived: Bool = false
) -> ShiftType {
    ShiftType(
        id: id(number), name: name, kind: kind, startMinutes: start, endMinutes: end,
        breakEnabled: breakEnabled ?? (breakAt != nil), breakStartMinutes: breakAt ?? 0,
        breakDurationMinutes: breakMinutes, colorHex: "#FF8800", isArchived: archived
    )
}

let dayType = type(1, "Day", .work, 540, 1_080, breakAt: 720, breakMinutes: 60)
let nightType = type(2, "Night", .work, 1_320, 360, breakAt: 120, breakMinutes: 30)
let earlyType = type(3, "Early", .work, 360, 840)
let restType = type(4, "Rest", .rest, 0, 0)
let lateArchived = type(5, "Late", .work, 780, 1_380, archived: true)
let fullDay = type(6, "Full", .work, 480, 480, breakAt: 780, breakMinutes: 60)
let invalidType = type(7, "   ", .work, 540, 1_020)
let breakOff = type(8, "NoBreak", .work, 600, 1_080, breakAt: 700, breakMinutes: 45, breakEnabled: false)
let restArchived = type(9, "Off", .rest, 0, 0, archived: true)
let allTypes = [dayType, nightType, earlyType, restType, lateArchived, fullDay, invalidType, breakOff]
let unknownID = id(0x99)

var dayFrozen = dayType
dayFrozen.startMinutes = 480
dayFrozen.endMinutes = 1_020
dayFrozen.name = "Day (old)"

func roster(_ key: String, _ typeID: UUID, frozen: ShiftType? = nil) -> RosterDay {
    RosterDay(
        dayKey: key, shiftTypeID: typeID, assignedShiftType: frozen, generatedFromPattern: nil,
        timeZoneIdentifier: "Asia/Shanghai", editedAt: Date(timeIntervalSince1970: 0), editCount: 1, editTieBreaker: id(0)
    )
}

func month(_ prefix: String, days: ClosedRange<Int>, pick: (Int) -> UUID?) -> [String: UUID] {
    var result: [String: UUID] = [:]
    for day in days { if let typeID = pick(day) { result["\(prefix)-\(day < 10 ? "0" : "")\(day)"] = typeID } }
    return result
}

let janHandSet = month("2026-01", days: 1...31) { day in
    if day == 15 { return nil }
    return [dayType.id, dayType.id, nightType.id, restType.id, earlyType.id][day % 5]
}
let aprilHandSet = month("2026-04", days: 1...3) { [dayType.id, nightType.id, fullDay.id][$0 - 1] }
let leapHandSet = month("2028-01", days: 27...31) { [dayType.id, earlyType.id][$0 % 2] }
let carryDays = janHandSet.merging(aprilHandSet) { a, _ in a }.merging(leapHandSet) { a, _ in a }

/// How the fixture builds a plan, so Kotlin exercises the same constructors.
struct Recipe {
    let name: String
    let json: J
    let plan: ExtendedSchedulePlan
}

func typeJSON(_ t: ShiftType) -> J {
    .object([
        ("id", .string(t.id.uuidString)), ("name", .string(t.name)), ("kind", .string(t.kind.rawValue)),
        ("startMinutes", n(t.startMinutes)), ("endMinutes", n(t.endMinutes)), ("breakEnabled", .bool(t.breakEnabled)),
        ("breakStartMinutes", n(t.breakStartMinutes)), ("breakDurationMinutes", n(t.breakDurationMinutes)),
        ("colorHex", .string(t.colorHex)), ("isArchived", .bool(t.isArchived)),
    ])
}

func ruleJSON(_ r: ShiftCycleRule?) -> J {
    guard let r else { return .null }
    return .object([("preset", .string(r.preset.rawValue)), ("anchorDayKey", .string(r.anchorDayKey)), ("days", .array(r.days.map { .string($0.uuidString) }))])
}

func rosterJSON(_ d: RosterDay) -> J {
    .object([("dayKey", .string(d.dayKey)), ("shiftTypeID", .string(d.shiftTypeID.uuidString)), ("assignedShiftType", d.assignedShiftType.map(typeJSON) ?? .null)])
}

func direct(
    _ name: String, types: [ShiftType] = allTypes, rule: ShiftCycleRule? = nil, handSet: [String: UUID] = [:],
    region: String? = nil, cleared: String? = nil, overrides: [Int: Bool]? = nil
) -> Recipe {
    let plan = ExtendedSchedulePlan(
        shiftTypes: types, rule: rule, handSetDays: handSet,
        holidayRegionIdentifier: region, clearedFromDayKey: cleared, holidayOverrides: overrides
    )
    let json = J.object([
        ("kind", .string("direct")),
        ("shiftTypes", .array(types.map(typeJSON))),
        ("rule", ruleJSON(rule)),
        ("handSetDays", .object(handSet.sorted { $0.key < $1.key }.map { ($0.key, .string($0.value.uuidString)) })),
        ("holidayRegionIdentifier", s(region)),
        ("clearedFromDayKey", s(cleared)),
        ("holidayOverrides", overrides.map { o in .object(o.sorted { $0.key < $1.key }.map { ("\($0.key)", .bool($0.value)) }) } ?? .null),
    ])
    return Recipe(name: name, json: json, plan: plan)
}

let weeklyRule = ShiftCycleRule(preset: .weekly, anchorDayKey: "2026-03-02",
                                days: [dayType.id, dayType.id, nightType.id, nightType.id, restType.id, restType.id, earlyType.id])
let weeklyHandSet: [String: UUID] = [
    "2026-03-10": fullDay.id, "2026-03-11": lateArchived.id, "2026-03-12": invalidType.id,
    "2026-03-13": unknownID, "2026-03-14": breakOff.id, "2026-03-29": nightType.id, "2026-03-07": dayType.id,
    "2026-13-01": dayType.id, "abc": dayType.id,
]
let weekly = direct("weekly-rule", rule: weeklyRule, handSet: weeklyHandSet)

let rotationRule = ShiftCycleRule(preset: .alternatingWeeks, anchorDayKey: "2026-10-01", days: [
    dayType.id, dayType.id, nightType.id, nightType.id, restType.id, restType.id, restArchived.id,
    earlyType.id, earlyType.id, dayType.id, lateArchived.id, restType.id, unknownID, fullDay.id,
])
let rotation = direct("rotation-14", types: allTypes + [restArchived], rule: rotationRule, cleared: "2026-03-01")

let carry = direct("carry-over", handSet: carryDays)
let carryCleared = direct("carry-cleared", handSet: carryDays.merging(["2026-04-20": dayType.id]) { a, _ in a }, cleared: "2026-03-15")

let workweek = ShiftCycleRule(preset: .weekly, anchorDayKey: "2026-01-05",
                              days: [dayType.id, dayType.id, dayType.id, dayType.id, dayType.id, restType.id, restType.id])
let holidayCN = direct("holiday-cn", rule: workweek, region: "CN")
let holidayNoDefaults = direct("holiday-cn-no-defaults", types: [nightType], handSet: month("2026-09", days: 1...30) { $0 % 3 == 0 ? nil : nightType.id }, region: "CN")
let holidayOverrides = direct("holiday-overrides", rule: workweek, region: "US", overrides: [20260704: false, 20260705: true, 20261012: false, 20260101: true])
let holidayOff = direct("holiday-disabled", rule: workweek, region: "")
let archivedDefaults = direct("archived-defaults", types: [lateArchived, restArchived, dayType], rule: workweek, region: "CN")
let garbage = direct("garbage-rule", rule: ShiftCycleRule(preset: .custom, anchorDayKey: "2026-02-30", days: [dayType.id]),
                     handSet: month("2026-02", days: 1...5) { _ in earlyType.id })

let historicalRows = [
    roster("2026-03-03", dayType.id, frozen: dayFrozen),
    roster("2026-03-04", nightType.id, frozen: nightType),
    roster("2026-03-05", lateArchived.id),
    roster("2026-03-06", restType.id, frozen: restType),
    roster("2026-03-09", unknownID),
]
func historical(_ name: String, legacy: [ShiftType], includesLegacy: Bool) -> Recipe? {
    guard let plan = ExtendedSchedulePlan(historicalRosterDays: historicalRows, legacyShiftTypes: legacy, includesLegacyRows: includesLegacy) else { return nil }
    return Recipe(name: name, json: .object([
        ("kind", .string("historical")),
        ("rosterDays", .array(historicalRows.map(rosterJSON))),
        ("legacyShiftTypes", .array(legacy.map(typeJSON))),
        ("includesLegacyRows", .bool(includesLegacy)),
    ]), plan: plan)
}

let fromScheduleRows = [roster("2026-03-10", dayType.id, frozen: dayFrozen), roster("2026-03-11", earlyType.id), roster("2026-03-11", nightType.id, frozen: nightType)]
let fromSchedule: Recipe = {
    let schedule = ExtendedSchedule(
        isEnabled: true, shiftTypes: allTypes, rule: weeklyRule, holidayRegionIdentifier: "CN", clearedFromDayKey: nil,
        timeZoneIdentifier: "Asia/Shanghai", editedAt: Date(timeIntervalSince1970: 0), editCount: 1, editTieBreaker: id(0)
    )
    let plan = ExtendedSchedulePlan(schedule: schedule, rosterDays: fromScheduleRows)!
    return Recipe(name: "from-schedule", json: .object([
        ("kind", .string("schedule")),
        ("shiftTypes", .array(allTypes.map(typeJSON))),
        ("rule", ruleJSON(weeklyRule)),
        ("holidayRegionIdentifier", .string("CN")),
        ("clearedFromDayKey", .null),
        ("rosterDays", .array(fromScheduleRows.map(rosterJSON))),
    ]), plan: plan)
}()

let pinHours = ExtendedScheduleDayHours(startTime: "07:30", endTime: "16:00", breakStartTime: "11:30", breakDurationMinutes: 30)
let pinned = Recipe(name: "pinned", json: .object([
    ("kind", .string("pinned")), ("base", .string("weekly-rule")), ("dayKey", .string("2026-03-05")),
    ("hours", .object([("startTime", .string("07:30")), ("endTime", .string("16:00")), ("breakStartTime", .string("11:30")), ("breakDurationMinutes", n(30))])),
]), plan: weekly.plan.pinning(dayKey: "2026-03-05", to: pinHours))

let recipes: [Recipe] = [
    weekly, rotation, carry, carryCleared, holidayCN, holidayNoDefaults, holidayOverrides, holidayOff, archivedDefaults, garbage,
    historical("historical-legacy", legacy: [lateArchived, dayType], includesLegacy: true)!,
    historical("historical-frozen", legacy: [], includesLegacy: false)!,
    fromSchedule, pinned,
]

// MARK: - Day resolution

func dayRanges() -> [(Int, Int)] {
    [("2025-12-20", "2026-05-10"), ("2026-09-15", "2026-10-20"), ("2028-01-20", "2028-03-05")].map {
        (ExtendedScheduleResolver.dayNumber(dayKey: $0.0)!, ExtendedScheduleResolver.dayNumber(dayKey: $0.1)!)
    }
}

func dayRow(_ dayNumber: Int, _ day: ExtendedScheduleDay) -> J {
    .array([
        .string(ExtendedScheduleEditingKey.dayKey(dayNumber)),
        .bool(day.isWorkday),
        day.hours.map { h in .array([.string(h.startTime), .string(h.endTime), s(h.breakStartTime), n(h.breakDurationMinutes)]) } ?? .null,
        s(day.shiftTypeID?.uuidString),
        .string(day.source.rawValue),
    ])
}

enum ExtendedScheduleEditingKey {
    static func dayKey(_ dayNumber: Int) -> String {
        let c = CivilZone.civilDate(dayNumber: dayNumber)
        return String(format: "%04d-%02d-%02d", c.year, c.month, c.day)
    }
}

var daysSection: [String] = []
for recipe in recipes {
    let resolver = ExtendedScheduleResolver(plan: recipe.plan)
    var rows: [J] = []
    for (from, through) in dayRanges() {
        for dayNumber in from...through { rows.append(dayRow(dayNumber, resolver.day(dayNumber: dayNumber))) }
    }
    daysSection.append(line(.object([("plan", .string(recipe.name)), ("days", .array(rows))])))
}

// MARK: - Rules over extended plans

let zones = ["Asia/Shanghai", "Europe/Berlin", "America/New_York"]
let bases: [(String, ScheduleHoursConfiguration)] = [
    ("classic", ScheduleHoursConfiguration(
        startTime: "09:00", endTime: "17:00", workdays: [1, 2, 3, 4, 5],
        schedule: NativeWorkSchedule(mode: "classic", referenceWeekStartMs: nil, referenceWeekType: nil, singleWeekendWorkday: nil, rotationAnchorMs: nil, rotationWorkDays: nil, rotationRestDays: nil),
        breakStartTime: "12:00", breakDurationMinutes: 60)),
    ("manual", ScheduleHoursConfiguration(
        startTime: "08:00", endTime: "16:00", workdays: [],
        schedule: NativeWorkSchedule(mode: "off", referenceWeekStartMs: nil, referenceWeekType: nil, singleWeekendWorkday: nil, rotationAnchorMs: nil, rotationWorkDays: nil, rotationRestDays: nil),
        breakStartTime: nil, breakDurationMinutes: 0)),
]
let ruleRecipes = ["weekly-rule", "rotation-14", "carry-over", "carry-cleared", "holiday-cn", "historical-legacy", "pinned", "from-schedule"]

func input(_ base: ScheduleHoursConfiguration, _ plan: ExtendedSchedulePlan, _ zone: String, now: Double, ot: Double? = nil, forced: Double? = nil) -> NativeRulesInput {
    NativeRulesInput(
        startTime: base.startTime, endTime: base.endTime, nowMs: now, workdays: base.workdays, schedule: base.schedule,
        breakStartTime: base.breakStartTime, breakDurationMinutes: base.breakDurationMinutes, overtimeEndAtMs: ot,
        salaryAmount: "22000", salaryType: "monthly", monthlyWorkingDays: 21.75, annualBonusMonths: 1,
        forcedWorkdayStartMs: forced, timeZoneIdentifier: zone, extendedSchedule: plan
    )
}

func segmentsJSON(_ segments: [NativeShiftSegment]) -> J { .array(segments.map { .array([.number($0.startAtMs), .number($0.endAtMs)]) }) }

func snapshotJSON(_ x: NativeShiftSnapshot) -> J {
    .array([
        segmentsJSON(x.segments), n(x.startAtMs), n(x.endAtMs), n(x.plannedEndAtMs), n(x.overtimeEndAtMs),
        n(x.durationMs), n(x.plannedDurationMs), n(x.elapsedMs), n(x.remainingMs), n(x.progress), n(x.payRatio),
        n(x.activeBreakEndAtMs), .bool(x.isWorkday), n(x.nextRestAtMs), n(x.dailySalary), n(x.earnedSoFar),
        n(x.nextShiftStartAtMs), n(x.nextShiftEndAtMs), n(x.countdownTargetAtMs), n(x.countdownAnchorAtMs), n(x.countdownProgress),
    ])
}

let hour = 3_600_000.0
let windows: [(Double, Double)] = [
    (1_772_323_200_000, 1_775_606_400_000), // 2026-03-01 … 2026-04-08 UTC: both March DST changes
    (1_790_208_000_000, 1_791_763_200_000), // 2026-09-25 … 2026-10-13: CN golden week
    (1_767_139_200_000, 1_768_435_200_000), // 2025-12-31 … 2026-01-15
]
func instants(_ seed: Int) -> [Double] {
    let span = windows.reduce(0) { $0 + $1.1 - $1.0 }
    let stride = 19 * hour + 41 * 60_000 + 7_125
    return (0..<36).map { k in
        var r = (Double(seed) * 7 * hour + Double(k) * stride).truncatingRemainder(dividingBy: span)
        for (from, through) in windows {
            if r < through - from { return from + r + (k % 4 == 1 ? 0.5 : 0) }
            r -= through - from
        }
        fatalError()
    }
}

let byName = Dictionary(uniqueKeysWithValues: recipes.map { ($0.name, $0.plan) })
var snapshots: [String] = []
var widgets: [String] = []
var expansions: [String] = []
var breaks: [String] = []
var applyToday: [String] = []
var plannedHours: [String] = []
var seed = 0
for name in ruleRecipes {
    let plan = byName[name]!
    for zone in zones {
        for (baseName, base) in bases {
            seed += 1
            let times = instants(seed)
            for (k, now) in times.enumerated() {
                let plain = ScheduleRules.snapshot(input: input(base, plan, zone, now: now))
                let ot: Double? = k % 5 == 2 ? plain.plannedEndAtMs + Double(40 + k) * 60_000 : nil
                let forced: Double? = k % 7 == 3 ? now - Double(k % 2) * 86_400_000 : nil
                let x = (ot == nil && forced == nil) ? plain : ScheduleRules.snapshot(input: input(base, plan, zone, now: now, ot: ot, forced: forced))
                snapshots.append(line(.object([("plan", .string(name)), ("zone", .string(zone)), ("base", .string(baseName)), ("now", n(now)), ("ot", n(ot)), ("forced", n(forced)), ("expected", snapshotJSON(x))])))
            }
            let now = times[3]
            let through = now + 21 * 86_400_000
            let shifts = ScheduleRules.widgetShifts(input: input(base, plan, zone, now: now), throughMs: through, maximumCount: 30)
            widgets.append(line(.object([("plan", .string(name)), ("zone", .string(zone)), ("base", .string(baseName)), ("now", n(now)), ("through", n(through)), ("max", n(30)),
                ("expected", .array(shifts.map { w in .array([segmentsJSON(w.segments), n(w.startAtMs), n(w.endAtMs), n(w.plannedEndAtMs), n(w.overtimeEndAtMs), n(w.durationMs), n(w.countdownAnchorAtMs)]) }))])))

            var configuration = base
            configuration.extendedSchedule = plan
            let from = times[5]
            let until = from + 45 * 86_400_000
            let days = ScheduleRules.expandScheduleRange(configuration: configuration, from: Date(timeIntervalSince1970: from / 1_000), through: Date(timeIntervalSince1970: until / 1_000), timeZone: TimeZone(identifier: zone))
            expansions.append(line(.object([("plan", .string(name)), ("zone", .string(zone)), ("base", .string(baseName)), ("from", n(from)), ("through", n(until)),
                ("expected", .array(days.map { d in .array([.string(d.dayKey), n(d.shiftAnchorStartAtMs), .bool(d.isWorkday), segmentsJSON(d.segments)]) }))])))

            for k in [0, 6, 12, 18] {
                breaks.append(line(.object([("plan", .string(name)), ("zone", .string(zone)), ("base", .string(baseName)), ("now", n(times[k])),
                    ("expected", .bool(ScheduleRules.validateBreak(input: input(base, plan, zone, now: times[k]))))])))
            }
            for k in [1, 8, 15, 22, 29] {
                let current = input(base, plan, zone, now: times[k])
                let candidate = input(bases[(baseName == "classic") ? 1 : 0].1, plan, zone, now: times[k])
                applyToday.append(line(.object([("plan", .string(name)), ("zone", .string(zone)), ("base", .string(baseName)), ("now", n(times[k])),
                    ("expected", .bool(ScheduleRules.shouldPromptApplyToday(current: current, candidate: candidate)))])))
            }
        }
        let civil = CivilZone(identifier: zone, extended: ExtendedScheduleResolver(plan: plan))
        let start = ExtendedScheduleResolver.dayNumber(dayKey: "2026-03-01")!
        plannedHours.append(line(.object([("plan", .string(name)), ("zone", .string(zone)), ("fromDayKey", .string("2026-03-01")),
            ("expected", .array((start..<(start + 40)).map { n(civil.plannedHours(dayNumber: $0)) }))])))
    }
}

// The raw window at hours where last night's assignment can still be running.
// resolveCurrentShift's settlement fallback hides these, so they are sampled
// directly: after a night shift, before a day shift, across the DST weekends.
var timelines: [String] = []
for name in ["weekly-rule", "rotation-14", "pinned", "carry-over"] {
    for zone in zones {
        let civil = CivilZone(identifier: zone, extended: ExtendedScheduleResolver(plan: byName[name]!))
        let first = ExtendedScheduleResolver.dayNumber(dayKey: name == "rotation-14" ? "2026-09-28" : "2026-03-01")!
        var rows: [J] = []
        for dayNumber in first..<(first + 21) {
            for hour in [0, 3, 5, 6, 8, 21, 23] {
                let now = civil.utcMs(dayNumber: dayNumber, Clock(hour: hour, minute: hour == 5 ? 59 : 30))
                let t = civil.shiftTimeline("09:00", "17:00", nowMs: now, options: ShiftOptions(breakStartTime: "12:00", breakDurationMinutes: 60))
                rows.append(.array([n(now), segmentsJSON(t.segments), n(t.plannedEndAtMs)]))
            }
        }
        timelines.append(line(.object([("plan", .string(name)), ("zone", .string(zone)), ("expected", .array(rows))])))
    }
}

// MARK: - Validation

let longASCII = String(repeating: "a", count: 40)
let family = "👨‍👩‍👧"
let combining = "e\u{301}"
let nameCases = ["Day", "  padded  ", "", "   ", longASCII, longASCII + "b", String(repeating: family, count: 40), String(repeating: family, count: 41),
                 String(repeating: combining, count: 40), String(repeating: combining, count: 41), "\n\tNight\n", "\u{3000}全角\u{3000}"]
var typeCases: [String] = []
for name in nameCases {
    var t = dayType
    t.name = name
    typeCases.append(line(.object([("type", typeJSON(t)), ("expected", .bool(t.isValid))])))
}
for mutate in [
    { (t: inout ShiftType) in t.startMinutes = 1_440 }, { t in t.endMinutes = -1 }, { t in t.breakStartMinutes = 1_439 },
    { t in t.breakDurationMinutes = 0 }, { t in t.breakEnabled = false; t.breakDurationMinutes = 0 }, { t in t.colorHex = "#12345G" },
    { t in t.colorHex = "#abcdef" }, { t in t.colorHex = "abcdef" }, { t in t.colorHex = "#ABCDEF0" }, { t in t.breakDurationMinutes = 1_440 },
] as [(inout ShiftType) -> Void] {
    var t = dayType
    mutate(&t)
    typeCases.append(line(.object([("type", typeJSON(t)), ("expected", .bool(t.isValid))])))
}

let dayKeyCases = ["2026-02-28", "2026-02-29", "2028-02-29", "2100-02-29", "2000-02-29", "2026-13-01", "2026-00-10", "0000-01-01", "0001-01-01",
                   "9999-12-31", "2026-1-01", "2026-01-1", " 2026-01-01", "20260101", "abcd-ef-gh", "٢٠٢٦-٠١-٠١", "+026-01-01", "2026-04-31", "2026-12-31"]
let dayKeys = dayKeyCases.map { key in line(.object([("dayKey", .string(key)), ("expected", n(ExtendedScheduleResolver.dayNumber(dayKey: key)))])) }

var contentCases: [String] = []
let contents: [(String, ExtendedScheduleContent)] = [
    ("valid", ExtendedScheduleContent(shiftTypes: allTypes.filter { $0.isValid }, rule: weeklyRule)),
    ("invalid-type", ExtendedScheduleContent(shiftTypes: allTypes, rule: nil)),
    ("duplicate-ids", ExtendedScheduleContent(shiftTypes: [dayType, dayType], rule: nil)),
    ("unknown-rule-day", ExtendedScheduleContent(shiftTypes: [dayType], rule: ShiftCycleRule(preset: .custom, anchorDayKey: "2026-01-01", days: [unknownID]))),
    ("empty-rule", ExtendedScheduleContent(shiftTypes: [dayType], rule: ShiftCycleRule(preset: .custom, anchorDayKey: "2026-01-01", days: []))),
    ("rule-366", ExtendedScheduleContent(shiftTypes: [dayType], rule: ShiftCycleRule(preset: .custom, anchorDayKey: "2026-01-01", days: Array(repeating: dayType.id, count: 366)))),
    ("rule-367", ExtendedScheduleContent(shiftTypes: [dayType], rule: ShiftCycleRule(preset: .custom, anchorDayKey: "2026-01-01", days: Array(repeating: dayType.id, count: 367)))),
    ("bad-anchor", ExtendedScheduleContent(shiftTypes: [dayType], rule: ShiftCycleRule(preset: .custom, anchorDayKey: "2026-02-30", days: [dayType.id]))),
    ("bad-cleared", ExtendedScheduleContent(shiftTypes: [dayType], rule: nil, clearedFromDayKey: "2026-1-1")),
    ("good-cleared", ExtendedScheduleContent(shiftTypes: [dayType], rule: nil, clearedFromDayKey: "2026-01-01")),
    ("region-lower", ExtendedScheduleContent(shiftTypes: [dayType], rule: nil, holidayRegionIdentifier: "cn")),
    ("region-three", ExtendedScheduleContent(shiftTypes: [dayType], rule: nil, holidayRegionIdentifier: "CHN")),
    ("region-empty", ExtendedScheduleContent(shiftTypes: [dayType], rule: nil, holidayRegionIdentifier: "")),
    ("region-cn", ExtendedScheduleContent(shiftTypes: [dayType], rule: nil, holidayRegionIdentifier: "CN")),
]
for (name, content) in contents {
    contentCases.append(line(.object([
        ("name", .string(name)),
        ("shiftTypes", .array(content.shiftTypes.map(typeJSON))), ("rule", ruleJSON(content.rule)),
        ("holidayRegionIdentifier", s(content.holidayRegionIdentifier)), ("clearedFromDayKey", s(content.clearedFromDayKey)),
        ("expected", .bool(content.isValid(in: TimeZone(identifier: "Asia/Shanghai")!))),
    ])))
}

// MARK: - Output

precondition(HolidayCalendar.shared.coveredThroughYear(regionIdentifier: "CN") != nil, "HolidayTemplates.json was not found next to the tool")

func section(_ name: String, _ rows: [String]) -> String { "\"\(name)\":[\n\(rows.joined(separator: ",\n"))\n]" }
let plansSection = recipes.map { line(.object([("name", .string($0.name)), ("recipe", $0.json)])) }
print("""
{"holidayDataset":\(line(.string(HolidayCalendar.shared.datasetVersion))),
\(section("plans", plansSection)),
\(section("days", daysSection)),
\(section("snapshots", snapshots)),
\(section("widgetShifts", widgets)),
\(section("expansions", expansions)),
\(section("validateBreak", breaks)),
\(section("applyToday", applyToday)),
\(section("plannedHours", plannedHours)),
\(section("timelines", timelines)),
\(section("shiftTypeValidity", typeCases)),
\(section("dayKeys", dayKeys)),
\(section("contentValidity", contentCases))
}
""")
