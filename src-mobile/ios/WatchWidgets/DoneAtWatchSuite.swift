import RelevanceKit
import SwiftUI
import WidgetKit

// Plan 023 W5: complications that read only the schedule configuration the
// Watch already caches (`WatchScheduleV2`). Every shift comes from
// `ShiftRuleCore`; nothing here schedules, and no salary, record or leave
// data reaches the Watch. All of them are free.

/// The next shifts from the cached configuration, resolved by the shared rules.
nonisolated enum WatchScheduleOutlook {
    struct Shift: Equatable {
        let startMs: Int64
        let endMs: Int64
        let segments: [(Int64, Int64)]
        let dayNumber: Int
        let shiftName: String?

        static func == (lhs: Shift, rhs: Shift) -> Bool {
            lhs.startMs == rhs.startMs && lhs.endMs == rhs.endMs && lhs.dayNumber == rhs.dayNumber
        }

        var workMs: Int64 { segments.reduce(0) { $0 + max(0, $1.1 - $1.0) } }
        func remainingMs(at ms: Int64) -> Int64 { segments.reduce(0) { $0 + max(0, $1.1 - max($1.0, ms)) } }
    }

    static func shifts(_ input: ScheduleRuleInput, fromMs: Int64, throughMs: Int64, limit: Int = 20) -> [Shift] {
        var probe = input
        probe.nowMs = Double(fromMs)
        let resolver = ExtendedScheduleResolver(plan: probe.extendedSchedule)
        let zone = CivilZone(identifier: probe.timeZoneIdentifier, extended: resolver)
        var result: [Shift] = []
        var current = ShiftRuleCore.resolveCurrentShift(probe, zone)
        if ShiftRuleCore.isActualShift(current, probe, zone), current.endAtMs > Double(fromMs) {
            result.append(shift(current, zone: zone, input: probe, resolver: resolver))
        }
        while result.count < limit, let next = ShiftRuleCore.nextShift(after: current, probe, zone),
              next.startAtMs <= Double(throughMs) {
            if !result.contains(where: { $0.startMs == Int64(next.startAtMs) }) {
                result.append(shift(next, zone: zone, input: probe, resolver: resolver))
            }
            current = next
            probe.nowMs = next.endAtMs
        }
        return result
    }

    private static func shift(_ timeline: ShiftTimeline, zone: CivilZone, input: ScheduleRuleInput,
                              resolver: ExtendedScheduleResolver?) -> Shift {
        let day = zone.civil(timeline.startAtMs).dayNumber
        let name = input.extendedSchedule.flatMap { plan in
            resolver?.day(dayNumber: day).shiftTypeID.flatMap { id in plan.shiftTypes.first { $0.id == id }?.name }
        }
        return Shift(startMs: Int64(timeline.startAtMs), endMs: Int64(timeline.endAtMs),
                     segments: timeline.segments.map { (Int64($0.startAtMs), Int64($0.endAtMs)) },
                     dayNumber: day, shiftName: name)
    }

    static func zone(_ input: ScheduleRuleInput) -> CivilZone {
        CivilZone(identifier: input.timeZoneIdentifier, extended: ExtendedScheduleResolver(plan: input.extendedSchedule))
    }
}

private struct WatchSuiteEntry: TimelineEntry {
    let date: Date
    let schedule: WatchScheduleV2?
}

private struct WatchSuiteProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchSuiteEntry { .init(date: .now, schedule: nil) }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (WatchSuiteEntry) -> Void) {
        Task { completion(.init(date: .now, schedule: await Self.schedule())) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<WatchSuiteEntry>) -> Void) {
        Task {
            let now = Date.now
            let schedule = await Self.schedule()
            var dates = [now]
            if let schedule, schedule.isConfigured {
                let nowMs = Int64(now.timeIntervalSince1970 * 1_000)
                // Boundaries and a quarter-hour filler inside work, for a day and a half.
                for shift in WatchScheduleOutlook.shifts(schedule.configuration, fromMs: nowMs, throughMs: nowMs + 36 * 3_600_000) {
                    for segment in shift.segments {
                        for point in stride(from: max(segment.0, nowMs), through: segment.1, by: 15 * 60_000) {
                            dates.append(Date(timeIntervalSince1970: Double(point) / 1_000))
                        }
                        dates.append(Date(timeIntervalSince1970: Double(segment.1) / 1_000))
                    }
                }
            }
            var calendar = Calendar.current
            calendar.timeZone = .current
            var cursor = calendar.startOfDay(for: now)
            for _ in 0..<3 {
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                dates.append(next)
                cursor = next
            }
            let entries = Array(Set(dates.filter { $0 >= now })).sorted().prefix(120).map { WatchSuiteEntry(date: $0, schedule: schedule) }
            completion(.init(entries: entries, policy: .after(now.addingTimeInterval(4 * 3_600))))
        }
    }

    static func schedule() async -> WatchScheduleV2? {
        guard let fileURL = WatchSnapshotCache.appGroupFileURL() else { return nil }
        let package = await WatchSnapshotCache.open(fileURL: fileURL).currentPackage()
        guard let schedule = package?.schedule, schedule.isValid else { return nil }
        return schedule
    }
}

/// Copy and formatting in the iPhone's language, which the schedule carries.
nonisolated private struct WatchSuiteText {
    let presentation: WatchPresentationV1?

    var localeIdentifier: String? { presentation?.localeIdentifier }
    var locale: Locale { presentation.map(WatchDisplayFormat.locale) ?? .current }

    func t(_ key: String, _ values: [String: String] = [:]) -> String {
        WatchDisplayFormat.fill(WatchLocalizations.text(key, localeIdentifier: localeIdentifier), values)
    }

    func time(_ ms: Int64) -> String {
        Date(timeIntervalSince1970: Double(ms) / 1_000).formatted(.dateTime.hour().minute().locale(locale))
    }

    func weekday(_ ms: Int64) -> String {
        Date(timeIntervalSince1970: Double(ms) / 1_000).formatted(.dateTime.weekday(.abbreviated).locale(locale))
    }

    func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
    }

    func count(_ value: Int) -> String { value.formatted(.number.locale(locale)) }
}

private struct WatchSuiteUnconfigured: View {
    let text: WatchSuiteText
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).widgetAccentable()
            Label(text.t("watchOpenIPhone"), systemImage: "iphone")
                .font(.caption)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - This week

private struct WatchWeekView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchSuiteEntry

    var body: some View {
        let text = WatchSuiteText(presentation: entry.schedule?.presentation)
        Group {
            if let schedule = entry.schedule, schedule.isConfigured {
                let figures = Self.figures(schedule, at: entry.date)
                switch family {
                case .accessoryCircular:
                    Gauge(value: figures.progress) {
                        Image(systemName: "calendar")
                    } currentValueLabel: {
                        Text(text.decimal(figures.remainingDays)).font(.system(.body, design: .rounded, weight: .bold))
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(.orange)
                    .widgetAccentable()
                default:
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(text.t("widgetSuiteThisWeek")).font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                                .widgetAccentable()
                            Spacer(minLength: 2)
                            if let finish = figures.finishMs {
                                Text(text.t("widgetSuiteFinishAt", ["time": "\(text.weekday(finish)) \(text.time(finish))"]))
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                            }
                        }
                        if figures.remainingMs == 0, figures.totalMs > 0 {
                            Text(text.t("widgetSuiteWeekDone")).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
                        } else {
                            Text("\(text.decimal(figures.remainingDays)) \(text.t("widgetSuiteDaysUnit"))")
                                .font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        HStack(spacing: 2) {
                            ForEach(Array(figures.fills.enumerated()), id: \.offset) { _, fill in
                                Gauge(value: fill) { EmptyView() }
                                    .gaugeStyle(.accessoryLinearCapacity)
                                    .tint(.orange)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                WatchSuiteUnconfigured(text: text, title: text.t("widgetSuiteThisWeek"))
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "offworkcountdown://timer"))
    }

    struct Figures {
        let totalMs: Int64
        let remainingMs: Int64
        let remainingDays: Double
        let finishMs: Int64?
        let fills: [Double]
        var progress: Double { totalMs > 0 ? 1 - Double(remainingMs) / Double(totalMs) : 0 }
    }

    static func figures(_ schedule: WatchScheduleV2, at date: Date) -> Figures {
        let input = schedule.configuration
        let zone = WatchScheduleOutlook.zone(input)
        let nowMs = Int64(date.timeIntervalSince1970 * 1_000)
        let weekStart = Int64(zone.weekStartMs(Double(nowMs)))
        let weekEnd = Int64(zone.addCivilDaysMs(Double(weekStart), 7))
        let shifts = WatchScheduleOutlook.shifts(input, fromMs: weekStart, throughMs: weekEnd - 1)
            .filter { $0.startMs >= weekStart && $0.startMs < weekEnd }
        let total = shifts.reduce(Int64(0)) { $0 + $1.workMs }
        let remaining = shifts.reduce(Int64(0)) { $0 + $1.remainingMs(at: nowMs) }
        let days = shifts.reduce(0.0) { $1.workMs > 0 ? $0 + Double($1.remainingMs(at: nowMs)) / Double($1.workMs) : $0 }
        let fills = shifts.map { $0.workMs > 0 ? 1 - Double($0.remainingMs(at: nowMs)) / Double($0.workMs) : 0 }
        let finish = shifts.last.map(\.endMs).flatMap { $0 > nowMs ? $0 : nil }
        return Figures(totalMs: total, remainingMs: remaining, remainingDays: days, finishMs: finish, fills: fills)
    }
}

struct DoneAtWatchWeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DoneAtWatchWeek", provider: WatchSuiteProvider()) { WatchWeekView(entry: $0).watchSuiteLocale($0) }
            .configurationDisplayName(WatchLocalizations.text("widgetSuiteWeekName"))
            .description(WatchLocalizations.text("widgetSuiteWeekDescription"))
            .supportedFamilies([.accessoryRectangular, .accessoryCircular])
    }
}

// MARK: - Today / tomorrow's shift

private struct WatchShiftDayView: View {
    let entry: WatchSuiteEntry

    var body: some View {
        let text = WatchSuiteText(presentation: entry.schedule?.presentation)
        Group {
            if let schedule = entry.schedule, schedule.isConfigured {
                let nowMs = Int64(entry.date.timeIntervalSince1970 * 1_000)
                let shifts = WatchScheduleOutlook.shifts(schedule.configuration, fromMs: nowMs, throughMs: nowMs + 8 * 86_400_000, limit: 8)
                let zone = WatchScheduleOutlook.zone(schedule.configuration)
                let today = zone.civil(Double(nowMs)).dayNumber
                VStack(alignment: .leading, spacing: 1) {
                    if let shift = shifts.first {
                        let isToday = shift.dayNumber == today
                        let isTomorrow = shift.dayNumber == today + 1
                        let when = isToday ? text.t("widgetSuiteToday") : (isTomorrow ? text.t("widgetSuiteTomorrow") : text.weekday(shift.startMs))
                        Text("\(when) · \(shift.shiftName ?? text.t("widgetSuiteWork"))")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.indigo).lineLimit(1).widgetAccentable()
                        Text("\(text.time(shift.startMs)) – \(text.time(shift.endMs))")
                            .font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        if let note = restNote(shifts: shifts, today: today, text: text) {
                            Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    } else {
                        Text(text.t("widgetSuiteRosterName")).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Text(text.t("widgetSuiteRestingNow")).font(.caption).lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                WatchSuiteUnconfigured(text: text, title: text.t("widgetSuiteRosterName"))
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "offworkcountdown://timer"))
    }

    /// The first days off after the shown shift, by weekday.
    private func restNote(shifts: [WatchScheduleOutlook.Shift], today: Int, text: WatchSuiteText) -> String? {
        guard let first = shifts.first else { return nil }
        var restDays: [Int] = []
        var day = first.dayNumber + 1
        let workDays = Set(shifts.map(\.dayNumber))
        while day <= first.dayNumber + 7, restDays.count < 3 {
            if workDays.contains(day) { if !restDays.isEmpty { break } } else { restDays.append(day) }
            day += 1
        }
        guard let firstRest = restDays.first, firstRest - first.dayNumber <= 6 else { return nil }
        let zone = WatchScheduleOutlook.zone(entry.schedule!.configuration)
        let names = restDays.map { text.weekday(Int64(zone.utcMs(dayNumber: $0, Clock(hour: 12, minute: 0)))) }
        let formatter = ListFormatter()
        formatter.locale = text.locale
        return formatter.string(from: names).map { text.t("widgetSuiteRestOn", ["days": $0]) }
    }
}

struct DoneAtWatchShiftWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DoneAtWatchShift", provider: WatchSuiteProvider()) { WatchShiftDayView(entry: $0).watchSuiteLocale($0) }
            .configurationDisplayName(WatchLocalizations.text("widgetSuiteRosterName"))
            .description(WatchLocalizations.text("widgetSuiteRosterDescription"))
            .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - Weekend and next holiday

private struct WatchHolidayView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchSuiteEntry

    var body: some View {
        let text = WatchSuiteText(presentation: entry.schedule?.presentation)
        Group {
            if let schedule = entry.schedule, schedule.isConfigured {
                let nowMs = Int64(entry.date.timeIntervalSince1970 * 1_000)
                let weekend = Self.weekendStart(schedule, nowMs: nowMs)
                let holiday = Self.nextHoliday(schedule, nowMs: nowMs, language: text.localeIdentifier ?? "en")
                switch family {
                case .accessoryCircular:
                    VStack(spacing: 0) {
                        Image(systemName: "sun.max.fill").font(.caption2).widgetAccentable()
                        if let weekend {
                            Text(Date(timeIntervalSince1970: Double(weekend) / 1_000), style: .relative)
                                .font(.system(size: 11, weight: .bold)).multilineTextAlignment(.center)
                                .minimumScaleFactor(0.5).lineLimit(2)
                        } else {
                            Text(text.t("widgetSuiteRest")).font(.caption2.weight(.bold))
                        }
                    }
                default:
                    VStack(alignment: .leading, spacing: 1) {
                        let isWeekly = schedule.configuration.extendedSchedule == nil
                        Text(text.t(isWeekly ? "widgetSuiteUntilWeekend" : "widgetSuiteUntilRestDay"))
                            .font(.caption2.weight(.semibold)).foregroundStyle(.green).widgetAccentable()
                        if let weekend {
                            Text(Date(timeIntervalSince1970: Double(weekend) / 1_000), style: .relative)
                                .font(.headline).lineLimit(1).minimumScaleFactor(0.6)
                        } else {
                            Text(text.t("widgetSuiteRestingNow")).font(.caption).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        if let holiday {
                            Text(text.t("widgetSuiteHolidayIn", ["name": holiday.name, "days": text.count(holiday.days)]))
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                WatchSuiteUnconfigured(text: text, title: text.t("widgetSuiteUntilWeekend"))
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "offworkcountdown://timer"))
    }

    /// The end of the last work segment before the next day without work.
    static func weekendStart(_ schedule: WatchScheduleV2, nowMs: Int64) -> Int64? {
        let shifts = WatchScheduleOutlook.shifts(schedule.configuration, fromMs: nowMs, throughMs: nowMs + 14 * 86_400_000)
        guard var last = shifts.first else { return nil }
        for shift in shifts.dropFirst() {
            if shift.dayNumber > last.dayNumber + 1 { break }
            last = shift
        }
        return last.endMs > nowMs ? last.endMs : nil
    }

    /// The next named day off in the holiday calendar the schedule uses, and
    /// whole days until it. No region, no holiday.
    static func nextHoliday(_ schedule: WatchScheduleV2, nowMs: Int64, language: String) -> (name: String, days: Int)? {
        guard let region = schedule.configuration.extendedSchedule?.holidayRegionIdentifier, !region.isEmpty else { return nil }
        let zone = WatchScheduleOutlook.zone(schedule.configuration)
        let today = zone.civil(Double(nowMs)).dayNumber
        for offset in 0..<400 {
            let date = CivilZone.civilDate(dayNumber: today + offset)
            let key = String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
            if let day = HolidayCalendar.shared.day(dayKey: key, regionIdentifier: region), !day.isWorkday {
                return (day.name(language: language), offset)
            }
        }
        return nil
    }
}

struct DoneAtWatchHolidayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DoneAtWatchHoliday", provider: WatchSuiteProvider()) { WatchHolidayView(entry: $0).watchSuiteLocale($0) }
            .configurationDisplayName(WatchLocalizations.text("widgetSuiteWeekendName"))
            .description(WatchLocalizations.text("widgetSuiteWeekendDescription"))
            .supportedFamilies([.accessoryRectangular, .accessoryCircular])
    }
}

// MARK: - Coming up (Smart Stack)

private struct WatchUpNextView: View {
    let entry: WatchSuiteEntry

    var body: some View {
        let text = WatchSuiteText(presentation: entry.schedule?.presentation)
        Group {
            if let schedule = entry.schedule, schedule.isConfigured {
                let nowMs = Int64(entry.date.timeIntervalSince1970 * 1_000)
                let items = Self.items(schedule, nowMs: nowMs, text: text)
                VStack(alignment: .leading, spacing: 1) {
                    Text(text.t("comingUp")).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).widgetAccentable()
                    if let first = items.first {
                        Text("\(text.time(first.ms)) \(first.title)").font(.headline).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    if items.count > 1 {
                        Text("\(text.time(items[1].ms)) \(items[1].title)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                WatchSuiteUnconfigured(text: text, title: text.t("comingUp"))
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "offworkcountdown://timer"))
    }

    nonisolated static func items(_ schedule: WatchScheduleV2, nowMs: Int64, text: WatchSuiteText) -> [(ms: Int64, title: String)] {
        var result: [(Int64, String)] = []
        for shift in WatchScheduleOutlook.shifts(schedule.configuration, fromMs: nowMs, throughMs: nowMs + 2 * 86_400_000, limit: 3) {
            result.append((shift.startMs, text.t("startTime")))
            for (index, segment) in shift.segments.enumerated() where index < shift.segments.count - 1 {
                result.append((segment.1, text.t("lunchShort")))
                result.append((shift.segments[index + 1].0, text.t("lunchBackAt")))
            }
            result.append((shift.endMs, text.t("endTime")))
        }
        return result.filter { $0.0 > nowMs }.sorted { $0.0 < $1.0 }.map { (ms: $0.0, title: $0.1) }
    }
}

private struct WatchUpNextProvider: TimelineProvider {
    let base = WatchSuiteProvider()
    func placeholder(in context: Context) -> WatchSuiteEntry { base.placeholder(in: context) }
    func getSnapshot(in context: Context, completion: @escaping @Sendable (WatchSuiteEntry) -> Void) {
        base.getSnapshot(in: context, completion: completion)
    }
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<WatchSuiteEntry>) -> Void) {
        base.getTimeline(in: context, completion: completion)
    }

    /// Smart Stack: the hour around each upcoming boundary is when this matters.
    func relevance() async -> WidgetRelevance<Void> {
        guard let schedule = await WatchSuiteProvider.schedule(), schedule.isConfigured else { return WidgetRelevance([]) }
        let nowMs = Int64(Date.now.timeIntervalSince1970 * 1_000)
        let text = WatchSuiteText(presentation: schedule.presentation)
        let intervals = WatchUpNextView.items(schedule, nowMs: nowMs, text: text).prefix(6).map { item in
            let date = Date(timeIntervalSince1970: Double(item.ms) / 1_000)
            return DateInterval(start: date.addingTimeInterval(-30 * 60), end: date.addingTimeInterval(5 * 60))
        }
        return WidgetRelevance(intervals.map {
            WidgetRelevanceAttribute(context: RelevantContext.date(interval: $0, kind: .scheduled))
        })
    }
}

struct DoneAtWatchUpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DoneAtWatchUpNext", provider: WatchUpNextProvider()) { WatchUpNextView(entry: $0).watchSuiteLocale($0) }
            .configurationDisplayName(WatchLocalizations.text("comingUp"))
            .description(WatchLocalizations.text("widgetSuiteWeekDescription"))
            .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - Shared drawing for the upgraded countdown complication

/// Work segments of the shift the countdown complication shows.
nonisolated enum WatchCountdownSegments {
    static func segments(_ package: WatchSnapshotPackageV1?, nowMs: Int64) -> [(Int64, Int64)] {
        let content = package?.schedule?.content(at: nowMs) ?? package?.content
        return content?.shift?.segments.map { ($0.startAtMs, $0.endAtMs) } ?? []
    }
}

/// A ring cut at lunch. `Gauge` cannot leave a gap, so this draws arcs.
struct WatchSegmentRing: View {
    let weights: [Double]
    let progress: Double
    var lineWidth: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            let total = max(0.000_1, weights.reduce(0, +))
            // Round caps reach half a line width into the gap from each side,
            // so the gap is a line width plus clear space, in points.
            let circumference = max(1, Double(min(proxy.size.width, proxy.size.height)) * .pi)
            let gap = weights.count > 1 ? min(0.2, Double(lineWidth + max(2.5, lineWidth * 0.6)) / circumference) : 0
            ZStack {
                ForEach(Array(arcs(total: total, gap: gap).enumerated()), id: \.offset) { _, arc in
                    Circle().trim(from: arc.0, to: arc.1)
                        .stroke(Color.orange.opacity(0.3), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    if arc.2 > arc.0 {
                        Circle().trim(from: arc.0, to: arc.2)
                            .stroke(Color.orange, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                            .widgetAccentable()
                    }
                }
            }
            .rotationEffect(.degrees(-90))
            // A square centred in whatever frame the ring is given.
            .frame(width: min(proxy.size.width, proxy.size.height), height: min(proxy.size.width, proxy.size.height))
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .padding(lineWidth / 2)
    }

    private func arcs(total: Double, gap: Double) -> [(Double, Double, Double)] {
        var result: [(Double, Double, Double)] = []
        var cursor = 0.0
        var remaining = min(1, max(0, progress)) * total
        for weight in weights {
            let share = weight / total
            let start = cursor + gap / 2
            let end = max(start, cursor + share - gap / 2)
            let filled = min(weight, max(0, remaining))
            remaining -= weight
            result.append((start, end, start + (end - start) * (weight > 0 ? filled / weight : 0)))
            cursor += share
        }
        return result
    }
}

private extension View {
    /// Matches the countdown complication: system-formatted text and layout
    /// follow the iPhone's chosen language rather than the extension bundle.
    func watchSuiteLocale(_ entry: WatchSuiteEntry) -> some View {
        let text = WatchSuiteText(presentation: entry.schedule?.presentation)
        return environment(\.locale, text.locale)
            .environment(\.layoutDirection, WatchDisplayFormat.isRightToLeft(
                localeIdentifier: text.localeIdentifier ?? Locale.preferredLanguages.first ?? "en"
            ) ? .rightToLeft : .leftToRight)
    }
}
