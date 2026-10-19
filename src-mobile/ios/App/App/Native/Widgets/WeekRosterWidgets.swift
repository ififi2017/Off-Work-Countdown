import SwiftUI
import WidgetKit

// MARK: - Timeline

nonisolated struct CalendarWidgetEntry: TimelineEntry {
    let date: Date
    let payload: WidgetCalendarPayload?
}

nonisolated struct CalendarWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarWidgetEntry {
        CalendarWidgetEntry(date: .now, payload: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (CalendarWidgetEntry) -> Void) {
        completion(CalendarWidgetEntry(date: .now, payload: WidgetSuiteStore.load(WidgetCalendarPayload.self, from: .calendar)))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<CalendarWidgetEntry>) -> Void) {
        let now = Date()
        let payload = WidgetSuiteStore.load(WidgetCalendarPayload.self, from: .calendar)
        let dates = WidgetSuiteTimeline.dates(days: payload?.days ?? [], now: now)
        let entries = dates.map { CalendarWidgetEntry(date: $0, payload: payload) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3_600))))
    }
}

/// Entry dates for widgets that move with work: every boundary and a filler
/// every 15 minutes inside work within 36 hours, plus each midnight for a
/// week. Bounded so a reload stays inside the extension's memory budget.
nonisolated enum WidgetSuiteTimeline {
    static let stepMs: Int64 = 15 * 60 * 1_000
    static let windowMs: Int64 = 36 * 3_600 * 1_000

    static func dates(days: [WidgetCalendarDay], now: Date, extra: [Int64] = []) -> [Date] {
        let nowMs = WidgetSuiteTime.ms(now)
        let endMs = nowMs + windowMs
        var points = Set<Int64>([nowMs])
        for day in days where day.startMs < endMs && day.startMs + 86_400_000 > nowMs {
            for segment in day.segments {
                points.insert(segment[0])
                points.insert(segment[1])
                var cursor = max(segment[0], nowMs) + stepMs
                while cursor < min(segment[1], endMs) {
                    points.insert(cursor)
                    cursor += stepMs
                }
            }
        }
        for midnight in WidgetSuiteTime.midnights(after: now, count: 7) { points.insert(WidgetSuiteTime.ms(midnight)) }
        for point in extra { points.insert(point) }
        return points.filter { $0 >= nowMs && $0 <= nowMs + 8 * 86_400_000 }
            .sorted()
            .prefix(160)
            .map(WidgetSuiteTime.date)
    }
}

// MARK: - Week progress

/// This week's work as of `atMs`, from the calendar payload alone.
nonisolated struct WeekProgress {
    let days: [WidgetCalendarDay]
    let totalMs: Int64
    let remainingMs: Int64
    /// Workdays still ahead, a partly worked day counting by what is left of it.
    let remainingDays: Double
    let finishMs: Int64?
    let isBigWeek: Bool

    init(payload: WidgetCalendarPayload, atMs: Int64) {
        days = Array(payload.week(containingMs: atMs))
        let work = days.filter(\.isWork)
        totalMs = work.reduce(0) { $0 + $1.workMs }
        remainingMs = work.reduce(0) { $0 + $1.remainingMs(atMs: atMs) }
        remainingDays = work.reduce(0) { total, day in
            day.workMs > 0 ? total + Double(day.remainingMs(atMs: atMs)) / Double(day.workMs) : total
        }
        finishMs = work.last?.endAtMs
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: payload.timeZoneIdentifier) ?? .current
        isBigWeek = work.contains { calendar.isDateInWeekend(WidgetSuiteTime.date($0.startMs)) }
    }

    var progress: Double { totalMs > 0 ? 1 - Double(remainingMs) / Double(totalMs) : 0 }

    func fill(of day: WidgetCalendarDay, atMs: Int64) -> Double {
        guard day.isWork, day.workMs > 0 else { return 0 }
        return 1 - Double(day.remainingMs(atMs: atMs)) / Double(day.workMs)
    }
}

/// A rotation's next days, and how many workdays stand before the next rest.
nonisolated struct RotationOutlook {
    let days: [WidgetCalendarDay]
    let workdaysBeforeRest: Int
    let nextRest: WidgetCalendarDay?
    let today: WidgetCalendarDay?

    init(payload: WidgetCalendarPayload, atMs: Int64, count: Int = 14) {
        let start = payload.dayIndex(containingMs: atMs) ?? 0
        days = Array(payload.days.dropFirst(start).prefix(count))
        today = days.first
        var workdays = 0
        var rest: WidgetCalendarDay?
        for day in days {
            if day.isWork {
                if day.remainingMs(atMs: atMs) > 0 { workdays += 1 }
            } else {
                rest = day
                break
            }
        }
        workdaysBeforeRest = workdays
        nextRest = rest
    }
}

struct WeekProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSuiteKind.week, provider: CalendarWidgetProvider()) { entry in
            WeekProgressView(entry: entry).widgetSuiteLocale(entry.payload?.locale)
        }
        .configurationDisplayName(WidgetSuiteCopy.t("widgetSuiteWeekName", locale: WidgetSuiteCopy.systemLocale))
        .description(WidgetSuiteCopy.t("widgetSuiteWeekDescription", locale: WidgetSuiteCopy.systemLocale))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

struct WeekProgressView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    /// Settings › Widgets renders these views at sizes the app's own
    /// environment cannot claim; widgets leave it nil.
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? environmentFamily }
    let entry: CalendarWidgetEntry

    var body: some View {
        content
            .widgetSuiteBackground()
            .widgetURL(URL(string: "offworkcountdown://timer"))
    }

    @ViewBuilder private var content: some View {
        if let payload = entry.payload, payload.scheduleKind != .none, !payload.days.isEmpty {
            let atMs = WidgetSuiteTime.ms(entry.date)
            if payload.scheduleKind == .rotation {
                RotationView(payload: payload, outlook: RotationOutlook(payload: payload, atMs: atMs),
                             atMs: atMs, family: family)
            } else {
                WeekView(payload: payload, week: WeekProgress(payload: payload, atMs: atMs), atMs: atMs, family: family)
            }
        } else {
            let locale = entry.payload?.locale ?? WidgetSuiteCopy.systemLocale
            if family == .accessoryCircular {
                Image(systemName: "calendar").font(.title3).widgetAccentable()
            } else {
                WidgetSuiteEmpty(
                    title: WidgetSuiteCopy.t("widgetSuiteThisWeek", locale: locale),
                    message: WidgetSuiteCopy.t("widgetSuiteNoScheduleMessage", locale: locale),
                    action: family == .accessoryRectangular ? nil : WidgetSuiteCopy.t("widgetSuiteOpenSettings", locale: locale)
                )
            }
        }
    }
}

private struct WeekView: View {
    let payload: WidgetCalendarPayload
    let week: WeekProgress
    let atMs: Int64
    let family: WidgetFamily

    private var locale: String { payload.locale }
    private func t(_ key: String, _ values: [String: String] = [:]) -> String {
        WidgetSuiteCopy.t(key, locale: locale, values: values)
    }

    private var weekLabel: String? {
        guard payload.scheduleKind == .alternatingWeeks else { return nil }
        return payload.labels[week.isBigWeek ? WidgetCalendarLabel.bigWeek : WidgetCalendarLabel.smallWeek]
    }

    private var title: String {
        [t("widgetSuiteThisWeek"), weekLabel].compactMap { $0 }.joined(separator: " · ")
    }

    private var finishLine: String? {
        guard let finish = week.finishMs, finish > atMs else { return nil }
        return t("widgetSuiteFinishAt", ["time": "\(WidgetSuiteFormat.weekday(finish, locale: locale)) \(WidgetSuiteFormat.time(finish, locale: locale))"])
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                WidgetSuiteSegmentRing(segments: week.days.filter(\.isWork).map { Double($0.workMs) },
                                       progress: week.progress, lineWidth: 5, tint: .primary, track: .primary.opacity(0.25))
                WidgetSuiteCircularValue(value: WidgetSuiteFormat.decimal(week.remainingDays, locale: locale),
                                         unit: t("widgetSuiteDaysUnit"))
            }
            .accessibilityElement(children: .combine)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).widgetAccentable()
                headline(size: 17)
                bar(height: 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemSmall:
            VStack(alignment: .leading, spacing: 0) {
                WidgetSuiteHeader(title: title, symbol: "calendar")
                Spacer(minLength: 6)
                headline(size: 28)
                if let finishLine {
                    Text(finishLine).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                bar(height: 6)
            }
        default:
            VStack(alignment: .leading, spacing: 0) {
                WidgetSuiteHeader(title: title, trailing: WidgetSuiteFormat.monthDay(atMs, locale: locale), symbol: "calendar")
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    headline(size: 28)
                    if let finishLine {
                        Text(finishLine).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                .padding(.top, 6)
                Spacer(minLength: 8)
                dayColumns
            }
        }
    }

    @ViewBuilder private func headline(size: CGFloat) -> some View {
        if week.totalMs > 0, week.remainingMs == 0 {
            Text(t("widgetSuiteWeekDone"))
                .font(.system(size: size * 0.75, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(t("widgetSuiteWorkdaysLeft"))
                    .font(.system(size: max(11, size * 0.42), weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(WidgetSuiteFormat.decimal(week.remainingDays, locale: locale))
                        .font(.system(size: size, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(t("widgetSuiteDaysUnit"))
                        .font(.system(size: max(11, size * 0.45), weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func bar(height: CGFloat) -> some View {
        WidgetSuiteSegmentBar(
            segments: week.days.filter(\.isWork).map { (weight: 1, fill: week.fill(of: $0, atMs: atMs)) },
            height: height
        )
    }

    private var dayColumns: some View {
        HStack(spacing: 6) {
            ForEach(week.days) { day in
                let isToday = payload.day(containingMs: atMs)?.dayKey == day.dayKey
                VStack(spacing: 4) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(day.isWork ? WidgetSuitePalette.track : WidgetSuitePalette.restFill)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(WidgetSuitePalette.accent)
                            .frame(height: 30 * week.fill(of: day, atMs: atMs))
                            .widgetAccentable()
                        if day.kind == .holiday || day.kind == .leave {
                            Circle().fill(day.kind == .holiday ? WidgetSuitePalette.holiday : WidgetSuitePalette.accent)
                                .frame(width: 5, height: 5)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text(WidgetSuiteFormat.weekdayNarrow(day.startMs, locale: locale))
                        .font(.system(size: 11, weight: isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? .primary : .secondary)
                }
            }
        }
    }
}

private struct RotationView: View {
    let payload: WidgetCalendarPayload
    let outlook: RotationOutlook
    let atMs: Int64
    let family: WidgetFamily

    private var locale: String { payload.locale }
    private func t(_ key: String, _ values: [String: String] = [:]) -> String {
        WidgetSuiteCopy.t(key, locale: locale, values: values)
    }

    private var headline: String {
        outlook.today?.isWork == true || outlook.workdaysBeforeRest > 0
            ? t("widgetSuiteRestAfter", ["count": WidgetSuiteFormat.count(outlook.workdaysBeforeRest, locale: locale)])
            : t("widgetSuiteRestingToday")
    }

    private var cycleNote: String? {
        guard let day = outlook.today?.cycleDay, let length = outlook.today?.cycleLength else { return nil }
        return t("widgetSuiteCycleDay", ["day": WidgetSuiteFormat.count(day, locale: locale),
                                         "length": WidgetSuiteFormat.count(length, locale: locale)])
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            WidgetSuiteCircularValue(value: WidgetSuiteFormat.count(outlook.workdaysBeforeRest, locale: locale),
                                     unit: t("widgetSuiteDaysUnit"))
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(cycleNote ?? t("widgetSuiteThisWeek")).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(headline).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                strip(count: 7, compact: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemSmall:
            VStack(alignment: .leading, spacing: 0) {
                WidgetSuiteHeader(title: cycleNote ?? t("widgetSuiteThisWeek"), symbol: "arrow.triangle.2.circlepath")
                Spacer(minLength: 6)
                Text(headline).font(.system(size: 22, weight: .bold)).lineLimit(2).minimumScaleFactor(0.6)
                if let rest = outlook.nextRest {
                    Text(t("widgetSuiteRestOn", ["days": WidgetSuiteFormat.weekday(rest.startMs, locale: locale)]))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                strip(count: 7, compact: true)
            }
        default:
            VStack(alignment: .leading, spacing: 0) {
                WidgetSuiteHeader(title: cycleNote ?? t("widgetSuiteThisWeek"), trailing: outlook.nextRest.map {
                    t("widgetSuiteRestOn", ["days": WidgetSuiteFormat.weekday($0.startMs, locale: locale)])
                }, symbol: "arrow.triangle.2.circlepath")
                Text(headline).font(.system(size: 24, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6).padding(.top, 6)
                Spacer(minLength: 8)
                strip(count: 14, compact: false)
            }
        }
    }

    private func strip(count: Int, compact: Bool) -> some View {
        HStack(spacing: compact ? 2 : 3) {
            ForEach(Array(outlook.days.prefix(count))) { day in
                let isToday = day.dayKey == outlook.today?.dayKey
                VStack(spacing: 2) {
                    Text(day.isWork ? (payload.labels[WidgetCalendarLabel.work] ?? "") : (payload.labels[WidgetCalendarLabel.rest] ?? ""))
                        .font(.system(size: compact ? 8 : 10, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, minHeight: compact ? 12 : 22)
                        .background(day.isWork ? WidgetSuitePalette.accent.opacity(0.16) : WidgetSuitePalette.restFill,
                                    in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(isToday ? Color.primary : .clear, lineWidth: 1.5))
                        .foregroundStyle(day.isWork ? WidgetSuitePalette.accentText : .secondary)
                    if !compact {
                        Text(WidgetSuiteFormat.weekdayNarrow(day.startMs, locale: locale))
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Roster

struct RosterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSuiteKind.roster, provider: CalendarWidgetProvider()) { entry in
            RosterView(entry: entry).widgetSuiteLocale(entry.payload?.locale)
        }
        .configurationDisplayName(WidgetSuiteCopy.t("widgetSuiteRosterName", locale: WidgetSuiteCopy.systemLocale))
        .description(WidgetSuiteCopy.t("widgetSuiteRosterDescription", locale: WidgetSuiteCopy.systemLocale))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct RosterView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    /// Settings › Widgets renders these views at sizes the app's own
    /// environment cannot claim; widgets leave it nil.
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? environmentFamily }
    let entry: CalendarWidgetEntry

    var body: some View {
        content
            .widgetSuiteBackground()
            .widgetURL(URL(string: "offworkcountdown://schedule"))
    }

    @ViewBuilder private var content: some View {
        let locale = entry.payload?.locale ?? WidgetSuiteCopy.systemLocale
        if let payload = entry.payload, payload.scheduleKind != .none, !payload.days.isEmpty {
            let atMs = WidgetSuiteTime.ms(entry.date)
            switch family {
            case .systemLarge: RosterMonthView(payload: payload, atMs: atMs)
            case .systemMedium: RosterStripView(payload: payload, atMs: atMs)
            default: RosterDayView(payload: payload, atMs: atMs, family: family)
            }
        } else {
            WidgetSuiteEmpty(
                title: WidgetSuiteCopy.t("widgetSuiteRosterName", locale: locale),
                message: WidgetSuiteCopy.t("widgetSuiteNoScheduleMessage", locale: locale),
                action: family == .accessoryRectangular ? nil : WidgetSuiteCopy.t("widgetSuiteOpenSettings", locale: locale)
            )
        }
    }
}

/// Today until today's work is over, then tomorrow.
nonisolated enum RosterFocusDay {
    static func index(payload: WidgetCalendarPayload, atMs: Int64) -> (index: Int, isToday: Bool)? {
        guard let today = payload.dayIndex(containingMs: atMs) else { return nil }
        let day = payload.days[today]
        if day.isWork, let end = day.endAtMs, end > atMs { return (today, true) }
        return today + 1 < payload.days.count ? (today + 1, false) : nil
    }
}

private func chipTitle(_ day: WidgetCalendarDay, payload: WidgetCalendarPayload) -> String {
    if let title = day.title, !title.isEmpty { return title }
    switch day.kind {
    case .work: return payload.labels[WidgetCalendarLabel.work] ?? ""
    case .makeupWork: return payload.labels[WidgetCalendarLabel.makeupWork] ?? ""
    case .leave: return payload.labels[WidgetCalendarLabel.leave] ?? ""
    case .rest, .holiday: return payload.labels[WidgetCalendarLabel.rest] ?? ""
    }
}

private func chipColors(_ day: WidgetCalendarDay) -> (fill: Color, ink: Color) {
    switch day.kind {
    case .work, .makeupWork:
        let base = WidgetSuitePalette.color(hex: day.colorHex) ?? WidgetSuitePalette.accent
        return (base.opacity(0.18), day.colorHex == nil ? WidgetSuitePalette.accentText : .primary)
    case .holiday: return (WidgetSuitePalette.holiday.opacity(0.18), .primary)
    case .leave: return (WidgetSuitePalette.accent.opacity(0.28), .primary)
    case .rest: return (WidgetSuitePalette.restFill, .secondary)
    }
}

/// "Saturday, Sunday off" for the next run of days off within a week.
private func rosterRestNote(payload: WidgetCalendarPayload, after index: Int) -> String? {
    let locale = payload.locale
    let following = payload.days.dropFirst(index + 1).prefix(7)
    guard let start = following.firstIndex(where: { !$0.isWork }) else { return nil }
    let run = payload.days[start...].prefix { !$0.isWork }.prefix(4)
    let formatter = ListFormatter()
    formatter.locale = WidgetSuiteFormat.locale(locale)
    let names = run.map { WidgetSuiteFormat.weekday($0.startMs, locale: locale) }
    guard let list = formatter.string(from: names) else { return nil }
    return WidgetSuiteCopy.t("widgetSuiteRestOn", locale: locale, values: ["days": list])
}

/// "Today · Monday" and its hours, for the day the roster is about.
private func rosterFocusLine(payload: WidgetCalendarPayload, focus: (index: Int, isToday: Bool)) -> (heading: String, range: String?) {
    let locale = payload.locale
    let day = payload.days[focus.index]
    let when = WidgetSuiteCopy.t(focus.isToday ? "widgetSuiteToday" : "widgetSuiteTomorrow", locale: locale)
    let range = day.startAtMs.flatMap { start in
        day.endAtMs.map { "\(WidgetSuiteFormat.time(start, locale: locale)) – \(WidgetSuiteFormat.time($0, locale: locale))" }
    }
    return ("\(when) · \(WidgetSuiteFormat.weekday(day.startMs, locale: locale))", range)
}

private struct RosterDayView: View {
    let payload: WidgetCalendarPayload
    let atMs: Int64
    let family: WidgetFamily

    private var locale: String { payload.locale }
    private func t(_ key: String, _ values: [String: String] = [:]) -> String {
        WidgetSuiteCopy.t(key, locale: locale, values: values)
    }

    var body: some View {
        if let focus = RosterFocusDay.index(payload: payload, atMs: atMs) {
            let day = payload.days[focus.index]
            let (heading, range) = rosterFocusLine(payload: payload, focus: focus)
            if family == .accessoryRectangular {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(heading) · \(chipTitle(day, payload: payload))")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1).widgetAccentable()
                    Text(range ?? chipTitle(day, payload: payload)).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                    if let note = rosterRestNote(payload: payload, after: focus.index) {
                        Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let colors = chipColors(day)
                VStack(alignment: .leading, spacing: 0) {
                    Text(heading).font(.footnote.weight(.semibold)).lineLimit(1)
                    Text(chipTitle(day, payload: payload))
                        .font(.system(size: 20, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(colors.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(colors.ink)
                        .padding(.top, 10)
                    if let range {
                        Text(range).font(.system(size: 18, weight: .semibold)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.7).padding(.top, 8)
                    }
                    Spacer(minLength: 4)
                    if let note = rosterRestNote(payload: payload, after: focus.index) {
                        Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            WidgetSuiteEmpty(title: t("widgetSuiteRosterName"), message: t("widgetSuiteOpenToRefresh"))
        }
    }

}

private struct RosterStripView: View {
    let payload: WidgetCalendarPayload
    let atMs: Int64

    private var locale: String { payload.locale }

    var body: some View {
        let start = payload.dayIndex(containingMs: atMs) ?? 0
        let days = Array(payload.days.dropFirst(start).prefix(7))
        let focus = RosterFocusDay.index(payload: payload, atMs: atMs)
        VStack(alignment: .leading, spacing: 0) {
            WidgetSuiteHeader(title: WidgetSuiteCopy.t("widgetSuiteRosterName", locale: locale),
                              trailing: WidgetSuiteFormat.monthDay(atMs, locale: locale), symbol: "calendar")
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                ForEach(days) { day in
                    let colors = chipColors(day)
                    let isFocus = focus.map { payload.days[$0.index].dayKey == day.dayKey } ?? false
                    VStack(spacing: 3) {
                        Text(WidgetSuiteFormat.weekdayNarrow(day.startMs, locale: locale))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(WidgetSuiteFormat.dayOfMonth(day.startMs, locale: locale))
                            .font(.system(size: 14, weight: isFocus ? .bold : .medium)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(chipTitle(day, payload: payload))
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity, minHeight: 24)
                            .background(colors.fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .foregroundStyle(colors.ink)
                        Text(day.startAtMs.map { WidgetSuiteFormat.time($0, locale: locale) } ?? " ")
                            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .padding(.vertical, 4)
                    .background(isFocus ? WidgetSuitePalette.accent.opacity(0.08) : .clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            Spacer(minLength: 6)
            // The day the strip is about, and when the next days off begin.
            if let focus {
                let line = rosterFocusLine(payload: payload, focus: focus)
                HStack(spacing: 6) {
                    Text([line.heading, line.range].compactMap { $0 }.joined(separator: "  "))
                        .font(.caption.weight(.semibold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 4)
                    if let note = rosterRestNote(payload: payload, after: focus.index) {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                }
            }
        }
    }
}

private struct RosterMonthView: View {
    let payload: WidgetCalendarPayload
    let atMs: Int64

    private var locale: String { payload.locale }

    var body: some View {
        let calendar = gridCalendar
        let today = WidgetSuiteTime.date(atMs)
        let month = calendar.dateInterval(of: .month, for: today)
        let monthStartMs = month.map { WidgetSuiteTime.ms($0.start) } ?? atMs
        let monthEndMs = month.map { WidgetSuiteTime.ms($0.end) } ?? atMs
        let days = payload.days.filter { $0.startMs >= monthStartMs && $0.startMs < monthEndMs }
        let leading = days.first.map { (calendar.component(.weekday, from: WidgetSuiteTime.date($0.startMs)) - calendar.firstWeekday + 7) % 7 } ?? 0
        let workCount = days.filter(\.isWork).count
        let todayKey = payload.day(containingMs: atMs)?.dayKey
        VStack(alignment: .leading, spacing: 6) {
            WidgetSuiteHeader(
                title: WidgetSuiteCopy.t("widgetSuiteMonthRoster", locale: locale, values: [
                    "month": today.formatted(.dateTime.month(.wide).locale(WidgetSuiteFormat.locale(locale))),
                ]),
                trailing: WidgetSuiteCopy.t("widgetSuiteWorkdayCount", locale: locale, values: [
                    "count": WidgetSuiteFormat.count(workCount, locale: locale),
                ]),
                symbol: "calendar"
            )
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 3) {
                ForEach(0..<7, id: \.self) { offset in
                    Text(weekdaySymbol(offset, calendar: calendar))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 40) }
                ForEach(days) { day in
                    let colors = chipColors(day)
                    let isToday = day.dayKey == todayKey
                    VStack(spacing: 2) {
                        Text(WidgetSuiteFormat.dayOfMonth(day.startMs, locale: locale))
                            .font(.system(size: 12, weight: isToday ? .bold : .medium)).monospacedDigit()
                            .foregroundStyle(isToday ? WidgetSuitePalette.accentText : .primary)
                        Text(chipTitle(day, payload: payload))
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, 3)
                            .frame(maxWidth: .infinity, minHeight: 15)
                            .background(colors.fill, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .foregroundStyle(colors.ink)
                    }
                    .frame(height: 40)
                    .background(isToday ? WidgetSuitePalette.accent.opacity(0.10) : .clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var gridCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: payload.timeZoneIdentifier) ?? .current
        calendar.firstWeekday = payload.firstWeekday
        calendar.locale = WidgetSuiteFormat.locale(locale)
        return calendar
    }

    private func weekdaySymbol(_ offset: Int, calendar: Calendar) -> String {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return symbols[(calendar.firstWeekday - 1 + offset) % 7]
    }
}
