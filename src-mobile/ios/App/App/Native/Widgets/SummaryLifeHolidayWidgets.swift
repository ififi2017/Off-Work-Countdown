import SwiftUI
import WidgetKit

// MARK: - Period summary (Plus)

nonisolated struct SummaryWidgetEntry: TimelineEntry {
    let date: Date
    let payload: WidgetSummaryPayload?
}

nonisolated struct SummaryWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryWidgetEntry { SummaryWidgetEntry(date: .now, payload: nil) }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (SummaryWidgetEntry) -> Void) {
        completion(SummaryWidgetEntry(date: .now, payload: WidgetSuiteStore.load(WidgetSummaryPayload.self, from: .summary)))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<SummaryWidgetEntry>) -> Void) {
        let now = Date()
        let payload = WidgetSuiteStore.load(WidgetSummaryPayload.self, from: .summary)
        let live = (payload?.liveSegments ?? []).map {
            WidgetCalendarDay(dayKey: "", startMs: $0[0], kind: .work, title: nil, colorHex: nil, segments: [$0])
        }
        var extra: [Int64] = []
        if let until = payload?.access.validUntilMs { extra.append(until) }
        let entries = WidgetSuiteTimeline.dates(days: live, now: now, extra: extra)
            .map { SummaryWidgetEntry(date: $0, payload: payload) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3_600))))
    }
}

struct SummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSuiteKind.summary, provider: SummaryWidgetProvider()) { entry in
            SummaryWidgetView(entry: entry).widgetSuiteLocale(entry.payload?.locale)
        }
        .configurationDisplayName(WidgetSuiteCopy.t("widgetSuiteSummaryName", locale: WidgetSuiteCopy.systemLocale))
        .description(WidgetSuiteCopy.t("widgetSuiteSummaryDescription", locale: WidgetSuiteCopy.systemLocale))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular])
    }
}

struct SummaryWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    /// Settings › Widgets renders these views at sizes the app's own
    /// environment cannot claim; widgets leave it nil.
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? environmentFamily }
    let entry: SummaryWidgetEntry

    private var locale: String { entry.payload?.locale ?? WidgetSuiteCopy.systemLocale }
    private func t(_ key: String, _ values: [String: String] = [:]) -> String {
        WidgetSuiteCopy.t(key, locale: locale, values: values)
    }

    /// The size picks the period: week on the smallest faces, the year on Large.
    private var kind: WidgetSummaryPeriod.Kind {
        switch family {
        case .systemSmall, .accessoryCircular: .week
        case .systemLarge: .year
        default: .month
        }
    }

    var body: some View {
        content
            .widgetSuiteBackground()
            .widgetURL(URL(string: "offworkcountdown://records"))
    }

    @ViewBuilder private var content: some View {
        let atMs = WidgetSuiteTime.ms(entry.date)
        if let payload = entry.payload, payload.access.isUnlocked(atMs: atMs) {
            if let period = payload.period(kind) {
                SummaryPeriodView(payload: payload, period: period, atMs: atMs, family: family)
            } else {
                WidgetSuiteEmpty(title: t("widgetSuiteSummaryName"), message: t("widgetSuiteOpenToRefresh"), symbol: "chart.bar")
            }
        } else if family == .accessoryCircular {
            Image(systemName: "lock.fill").font(.title3).widgetAccentable()
        } else {
            WidgetSuitePlusLock(title: t("widgetSuiteSummaryName"), promise: t("widgetSuiteSummaryPromise"),
                                locale: locale, compact: family == .accessoryRectangular)
        }
    }
}

private struct SummaryPeriodView: View {
    let payload: WidgetSummaryPayload
    let period: WidgetSummaryPeriod
    let atMs: Int64
    let family: WidgetFamily

    private var locale: String { payload.locale }
    private func t(_ key: String, _ values: [String: String] = [:]) -> String {
        WidgetSuiteCopy.t(key, locale: locale, values: values)
    }

    private var workedMs: Int64 {
        period.workedMs(liveSegments: payload.liveSegments, since: payload.generatedAtMs, atMs: atMs)
    }

    private var title: String { [period.title, period.subtitle].compactMap { $0 }.joined(separator: " · ") }
    private var hours: String { WidgetSuiteFormat.hours(workedMs, locale: locale) }
    private var hoursUnit: String { payload.labels["hoursUnit"] ?? "h" }
    private var remaining: String {
        t("widgetSuiteWorkdaysRemaining", ["count": WidgetSuiteFormat.count(period.remainingWorkdays, locale: locale)])
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                WidgetSuiteSegmentRing(segments: [1], progress: period.progress, lineWidth: 5, tint: .primary,
                                       track: .primary.opacity(0.25))
                VStack(spacing: 0) {
                    Text(hours).font(.system(.callout, design: .rounded, weight: .bold)).minimumScaleFactor(0.6)
                    Text(hoursUnit).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1).widgetAccentable()
                Text(t("widgetSuiteWorkdayProgress", [
                    "done": WidgetSuiteFormat.count(period.workdays, locale: locale),
                    "total": WidgetSuiteFormat.count(period.plannedWorkdays, locale: locale),
                ])).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                WidgetSuiteSegmentBar(segments: [(weight: 1, fill: period.progress)], height: 5, tint: .primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemSmall:
            VStack(alignment: .leading, spacing: 0) {
                WidgetSuiteHeader(title: period.title, trailing: period.subtitle)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(hours).font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(hoursUnit).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                .padding(.top, 8)
                Spacer(minLength: 6)
                bars(height: 48, labels: true)
            }
        case .systemLarge:
            VStack(alignment: .leading, spacing: 0) {
                WidgetSuiteHeader(title: title, trailing: remaining)
                stats.padding(.top, 12)
                Text(t("widgetSuiteMonthlyHours")).font(.caption).foregroundStyle(.secondary).padding(.top, 16)
                bars(height: 150, labels: true).padding(.top, 6)
                Spacer(minLength: 8)
                if let comparison = period.comparison {
                    Divider()
                    Label(comparison, systemImage: "arrow.left.arrow.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 8)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 0) {
                WidgetSuiteHeader(title: title, trailing: remaining)
                stats.padding(.top, 10)
                Spacer(minLength: 8)
                WidgetSuiteSegmentBar(segments: [(weight: 1, fill: period.progress)])
                HStack {
                    Text(period.comparison ?? "").lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Text(WidgetSuiteFormat.percent(period.progress, locale: locale)).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 5)
            }
        }
    }

    private var stats: some View {
        Grid(alignment: .leading, horizontalSpacing: 12) {
            GridRow {
                stat(t("widgetSuiteTimeWorked"), value: hours, unit: hoursUnit)
                stat(t("widgetSuiteWorkdays"), value: WidgetSuiteFormat.count(period.workdays, locale: locale),
                     unit: "/ \(WidgetSuiteFormat.count(period.plannedWorkdays, locale: locale))")
                stat(t("widgetSuiteOvertime"), value: WidgetSuiteFormat.hours(period.overtimeMs, locale: locale),
                     unit: hoursUnit, emphasised: period.overtimeMs > 0)
            }
        }
    }

    private func stat(_ label: String, value: String, unit: String, emphasised: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(emphasised ? WidgetSuitePalette.accentText : .primary)
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bars(height: CGFloat, labels: Bool) -> some View {
        let values = period.bars.enumerated().map { index, bar in
            bar.state == .current && period.kind == .week ? max(bar.valueMs, todayBarMs(base: bar.valueMs)) : bar.valueMs
        }
        let top = max(Double(values.max() ?? 0), 1)
        return HStack(alignment: .bottom, spacing: period.bars.count > 7 ? 5 : 8) {
            ForEach(Array(period.bars.enumerated()), id: \.offset) { index, bar in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(fill(bar.state))
                        .frame(height: max(4, height * Double(values[index]) / top))
                        .frame(height: height, alignment: .bottom)
                    if labels {
                        Text(bar.label).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
            }
        }
    }

    /// Today's bar keeps growing with the live segments.
    private func todayBarMs(base: Int64) -> Int64 {
        let added = payload.liveSegments.reduce(Int64(0)) { total, segment in
            total + max(0, min(segment[1], atMs) - max(segment[0], payload.generatedAtMs))
        }
        return base + added
    }

    private func fill(_ state: WidgetSummaryPeriod.Bar.State) -> Color {
        switch state {
        case .current: WidgetSuitePalette.accent
        case .past: WidgetSuitePalette.accentSoft
        case .future, .rest: WidgetSuitePalette.track
        }
    }
}

// MARK: - Year progress (free) and Life (Plus)

nonisolated struct LifeWidgetEntry: TimelineEntry {
    let date: Date
    let payload: WidgetLifePayload?
}

nonisolated struct LifeWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> LifeWidgetEntry { LifeWidgetEntry(date: .now, payload: nil) }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (LifeWidgetEntry) -> Void) {
        completion(LifeWidgetEntry(date: .now, payload: WidgetSuiteStore.load(WidgetLifePayload.self, from: .life)))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<LifeWidgetEntry>) -> Void) {
        let now = Date()
        let payload = WidgetSuiteStore.load(WidgetLifePayload.self, from: .life)
        var dates = [now] + WidgetSuiteTime.midnights(after: now, count: 30)
        if let until = payload?.access.validUntilMs, until > WidgetSuiteTime.ms(now) {
            dates.append(WidgetSuiteTime.date(until))
            dates.sort()
        }
        completion(Timeline(entries: dates.map { LifeWidgetEntry(date: $0, payload: payload) }, policy: .atEnd))
    }
}

/// Shares of the calendar the user is in, from dates alone.
nonisolated struct CalendarProgress {
    let today: Double
    let week: Double
    let month: Double
    let year: Double
    let daysLeftInYear: Int

    init(date: Date, calendar: Calendar = .current) {
        func share(_ component: Calendar.Component) -> Double {
            guard let interval = calendar.dateInterval(of: component, for: date) else { return 0 }
            return min(1, max(0, date.timeIntervalSince(interval.start) / interval.duration))
        }
        today = share(.day)
        week = share(.weekOfYear)
        month = share(.month)
        year = share(.year)
        let end = calendar.dateInterval(of: .year, for: date)?.end ?? date
        daysLeftInYear = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: end).day ?? 0)
    }
}

struct YearProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "\(WidgetSuiteKind.prefix).year", provider: LifeWidgetProvider()) { entry in
            YearProgressView(entry: entry).widgetSuiteLocale(entry.payload?.locale)
        }
        .configurationDisplayName(WidgetSuiteCopy.t("widgetSuiteYearName", locale: WidgetSuiteCopy.systemLocale))
        .description(WidgetSuiteCopy.t("widgetSuiteYearDescription", locale: WidgetSuiteCopy.systemLocale))
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

struct YearProgressView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    /// Settings › Widgets renders these views at sizes the app's own
    /// environment cannot claim; widgets leave it nil.
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? environmentFamily }
    let entry: LifeWidgetEntry

    var body: some View {
        let locale = entry.payload?.locale ?? WidgetSuiteCopy.systemLocale
        let progress = CalendarProgress(date: entry.date)
        let year = entry.date.formatted(.dateTime.year().locale(WidgetSuiteFormat.locale(locale)))
        let percent = WidgetSuiteFormat.percent(progress.year, locale: locale)
        Group {
            switch family {
            case .accessoryInline:
                Text(WidgetSuiteCopy.t("widgetSuiteYearInline", locale: locale, values: ["year": year, "percent": percent]))
            case .accessoryCircular:
                Gauge(value: progress.year) {
                    Text(year)
                } currentValueLabel: {
                    Text(WidgetSuiteFormat.decimal(progress.year * 100, locale: locale, digits: 0))
                }
                .gaugeStyle(.accessoryCircularCapacity)
            default:
                VStack(spacing: 6) {
                    WidgetSuiteHeader(title: year, trailing: WidgetSuiteCopy.t("widgetSuiteDaysLeft", locale: locale, values: [
                        "count": WidgetSuiteFormat.count(progress.daysLeftInYear, locale: locale),
                    ]))
                    ZStack {
                        WidgetSuiteSegmentRing(segments: [1], progress: progress.year, lineWidth: 9)
                        VStack(spacing: 0) {
                            Text(percent).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                            Text(WidgetSuiteCopy.t("widgetSuitePassed", locale: locale)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .widgetSuiteBackground()
    }
}

struct LifeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSuiteKind.life, provider: LifeWidgetProvider()) { entry in
            LifeWidgetView(entry: entry).widgetSuiteLocale(entry.payload?.locale)
        }
        .configurationDisplayName(WidgetSuiteCopy.t("widgetSuiteLifeName", locale: WidgetSuiteCopy.systemLocale))
        .description(WidgetSuiteCopy.t("widgetSuiteLifeDescription", locale: WidgetSuiteCopy.systemLocale))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

/// Life as the widget draws it: whole days since birth, shares of an 80-year
/// span, and the career between starting work and retirement.
nonisolated struct LifeFigures {
    let daysLived: Int
    let lifeShare: Double
    let careerShare: Double?
    let monthsWorked: Int?
    let monthsToRetirement: Int?
    let ageMonths: Int

    init?(payload: WidgetLifePayload, date: Date) {
        guard let born = payload.bornDay else { return nil }
        let today = Int(floor(Calendar.current.startOfDay(for: date).timeIntervalSince1970 / 86_400 + 0.5))
        daysLived = max(0, today - born)
        let lifeDays = Double(payload.lifeYears) * 365.2425
        lifeShare = min(1, Double(daysLived) / lifeDays)
        ageMonths = Int(Double(daysLived) / 30.436875)
        if let start = payload.careerStartDay, let end = payload.retirementDay, end > start {
            careerShare = min(1, max(0, Double(today - start) / Double(end - start)))
            monthsWorked = today > start ? Int(Double(today - start) / 30.436875) : 0
            monthsToRetirement = end > today ? Int(Double(end - today) / 30.436875) : 0
        } else {
            careerShare = nil
            monthsWorked = nil
            monthsToRetirement = payload.retirementDay.map { max(0, Int(Double($0 - today) / 30.436875)) }
        }
    }
}

struct LifeWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    /// Settings › Widgets renders these views at sizes the app's own
    /// environment cannot claim; widgets leave it nil.
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? environmentFamily }
    let entry: LifeWidgetEntry

    private var locale: String { entry.payload?.locale ?? WidgetSuiteCopy.systemLocale }
    private func t(_ key: String, _ values: [String: String] = [:]) -> String {
        WidgetSuiteCopy.t(key, locale: locale, values: values)
    }

    var body: some View {
        content
            .widgetSuiteBackground()
            .widgetURL(URL(string: "offworkcountdown://records"))
    }

    @ViewBuilder private var content: some View {
        let atMs = WidgetSuiteTime.ms(entry.date)
        if let payload = entry.payload, payload.access.isUnlocked(atMs: atMs) {
            if let figures = LifeFigures(payload: payload, date: entry.date) {
                LifeFiguresView(payload: payload, figures: figures, date: entry.date, family: family)
            } else {
                WidgetSuiteEmpty(title: t("widgetSuiteLifeName"), message: t("widgetSuiteLifeSetup"),
                                 action: family == .accessoryRectangular ? nil : t("widgetSuiteOpenDoneAt"), symbol: "hourglass")
            }
        } else {
            WidgetSuitePlusLock(title: t("widgetSuiteLifeName"), promise: t("widgetSuiteLifePromise"),
                                locale: locale, compact: family == .accessoryRectangular)
        }
    }
}

private struct LifeFiguresView: View {
    let payload: WidgetLifePayload
    let figures: LifeFigures
    let date: Date
    let family: WidgetFamily

    private var locale: String { payload.locale }
    private func t(_ key: String, _ values: [String: String] = [:]) -> String {
        WidgetSuiteCopy.t(key, locale: locale, values: values)
    }

    private func span(_ months: Int) -> String {
        t("widgetSuiteYearsMonths", ["years": WidgetSuiteFormat.count(months / 12, locale: locale),
                                     "months": WidgetSuiteFormat.count(months % 12, locale: locale)])
    }

    private var daysLived: String {
        let value = t("widgetSuiteDaysCount", ["count": WidgetSuiteFormat.count(figures.daysLived, locale: locale)])
        return payload.bornIsApproximate ? t("widgetSuiteApproximately", ["value": value]) : value
    }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(t("widgetSuiteUntilRetirement")).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).widgetAccentable()
                Text(figures.monthsToRetirement.map(span) ?? daysLived).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                WidgetSuiteSegmentBar(segments: [(weight: 1, fill: figures.careerShare ?? figures.lifeShare)], height: 5, tint: .primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemSmall:
            VStack(alignment: .leading, spacing: 0) {
                WidgetSuiteHeader(title: t("widgetSuiteLifeName"), symbol: "hourglass")
                Text(t("widgetSuiteLived")).font(.caption).foregroundStyle(.secondary).padding(.top, 10)
                Text(daysLived).font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(t("widgetSuiteLifeShare", ["percent": WidgetSuiteFormat.percent(figures.lifeShare, locale: locale),
                                                "years": WidgetSuiteFormat.count(payload.lifeYears, locale: locale)]))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 6)
                lifeBar
            }
        case .systemMedium:
            let progress = CalendarProgress(date: date)
            VStack(alignment: .leading, spacing: 7) {
                WidgetSuiteHeader(title: t("widgetSuiteProgress"),
                                  trailing: date.formatted(.dateTime.month().day().weekday(.abbreviated).locale(WidgetSuiteFormat.locale(locale))))
                row(t("widgetSuiteToday"), progress.today)
                row(t("widgetSuiteThisWeek"), progress.week)
                row(t("widgetSuiteThisMonth"), progress.month)
                row(t("widgetSuiteThisYear"), progress.year)
                if let career = figures.careerShare { row(t("widgetSuiteCareer"), career) }
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                WidgetSuiteHeader(title: t("widgetSuiteLifeYears", ["years": WidgetSuiteFormat.count(payload.lifeYears, locale: locale)]),
                                  trailing: payload.hidesExactAges ? WidgetSuiteFormat.percent(figures.lifeShare, locale: locale) : span(figures.ageMonths),
                                  symbol: "hourglass")
                LifeGrid(payload: payload, ageMonths: figures.ageMonths)
                Divider()
                HStack {
                    if let worked = figures.monthsWorked {
                        stat(t("widgetSuiteWorked"), span(worked))
                    }
                    if let left = figures.monthsToRetirement {
                        stat(t("widgetSuiteUntilRetirement"), span(left))
                    }
                }
            }
        }
    }

    private func row(_ label: String, _ value: Double) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).frame(width: 46, alignment: .leading).lineLimit(1).minimumScaleFactor(0.7)
            WidgetSuiteSegmentBar(segments: [(weight: 1, fill: value)])
            Text(WidgetSuiteFormat.percent(value, locale: locale)).font(.caption.weight(.semibold)).monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 16, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lifeBar: some View {
        let years = Double(payload.lifeYears) * 365.2425
        let start = payload.careerStartDay.flatMap { career in payload.bornDay.map { Double(career - $0) / years } } ?? 0.275
        let end = payload.retirementDay.flatMap { retire in payload.bornDay.map { Double(retire - $0) / years } } ?? 0.75
        let now = figures.lifeShare
        return GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(WidgetSuitePalette.track)
                Rectangle().fill(WidgetSuitePalette.accentSoft)
                    .frame(width: max(0, (min(end, 1) - start) * width)).offset(x: start * width)
                Rectangle().fill(WidgetSuitePalette.accent)
                    .frame(width: max(0, (min(now, end) - start) * width)).offset(x: start * width)
                    .opacity(now > start ? 1 : 0)
                Rectangle().fill(Color.secondary.opacity(0.6))
                    .frame(width: max(0, min(now, start) * width))
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
    }
}

/// Eighty years, one cell a year and one dot a month, ten years to a row.
private struct LifeGrid: View {
    let payload: WidgetLifePayload
    let ageMonths: Int

    var body: some View {
        let careerStart = monthIndex(payload.careerStartDay)
        let careerEnd = monthIndex(payload.retirementDay)
        let rows = payload.lifeYears / 10
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 5) {
                    Text(verbatim: "\(row * 10)").font(.system(size: 8)).foregroundStyle(.secondary).frame(width: 13, alignment: .trailing)
                    HStack(spacing: 4) {
                        ForEach(0..<10, id: \.self) { column in
                            let year = row * 10 + column
                            Grid(horizontalSpacing: 1.5, verticalSpacing: 1.5) {
                                ForEach(0..<3, id: \.self) { line in
                                    GridRow {
                                        ForEach(0..<4, id: \.self) { item in
                                            let month = year * 12 + line * 4 + item
                                            RoundedRectangle(cornerRadius: 1)
                                                .fill(color(month, careerStart: careerStart, careerEnd: careerEnd))
                                                .aspectRatio(1, contentMode: .fit)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if row < rows - 1 { Spacer(minLength: 2) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func monthIndex(_ day: Int?) -> Int? {
        guard let day, let born = payload.bornDay else { return nil }
        return Int(Double(day - born) / 30.436875)
    }

    private func color(_ month: Int, careerStart: Int?, careerEnd: Int?) -> Color {
        let career = careerStart.map { month >= $0 } == true && careerEnd.map { month < $0 } != false
        if month == ageMonths { return .primary }
        if month < ageMonths { return career ? WidgetSuitePalette.accent : Color.secondary.opacity(0.55) }
        return career ? WidgetSuitePalette.accentSoft : WidgetSuitePalette.track
    }
}

// MARK: - Weekend (free) and holidays (free, leave Plus)

nonisolated struct HolidayWidgetEntry: TimelineEntry {
    let date: Date
    let payload: WidgetHolidayPayload?
    let calendar: WidgetCalendarPayload?
}

nonisolated struct HolidayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HolidayWidgetEntry { HolidayWidgetEntry(date: .now, payload: nil, calendar: nil) }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (HolidayWidgetEntry) -> Void) {
        completion(HolidayWidgetEntry(date: .now,
                                      payload: WidgetSuiteStore.load(WidgetHolidayPayload.self, from: .holiday),
                                      calendar: WidgetSuiteStore.load(WidgetCalendarPayload.self, from: .calendar)))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<HolidayWidgetEntry>) -> Void) {
        let now = Date()
        let payload = WidgetSuiteStore.load(WidgetHolidayPayload.self, from: .holiday)
        let calendar = WidgetSuiteStore.load(WidgetCalendarPayload.self, from: .calendar)
        var extra: [Int64] = []
        if let weekend = payload?.weekendStartMs { extra.append(weekend) }
        if let until = payload?.access.validUntilMs { extra.append(until) }
        let entries = WidgetSuiteTimeline.dates(days: calendar?.days ?? [], now: now, extra: extra)
            .map { HolidayWidgetEntry(date: $0, payload: payload, calendar: calendar) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3_600))))
    }
}

struct WeekendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "\(WidgetSuiteKind.prefix).weekend", provider: HolidayWidgetProvider()) { entry in
            WeekendWidgetView(entry: entry).widgetSuiteLocale(entry.payload?.locale)
        }
        .configurationDisplayName(WidgetSuiteCopy.t("widgetSuiteWeekendName", locale: WidgetSuiteCopy.systemLocale))
        .description(WidgetSuiteCopy.t("widgetSuiteWeekendDescription", locale: WidgetSuiteCopy.systemLocale))
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

struct WeekendWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    /// Settings › Widgets renders these views at sizes the app's own
    /// environment cannot claim; widgets leave it nil.
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? environmentFamily }
    let entry: HolidayWidgetEntry

    private var locale: String { entry.payload?.locale ?? WidgetSuiteCopy.systemLocale }
    private func t(_ key: String, _ values: [String: String] = [:]) -> String {
        WidgetSuiteCopy.t(key, locale: locale, values: values)
    }

    var body: some View {
        content
            .widgetSuiteBackground()
            .widgetURL(URL(string: "offworkcountdown://timer"))
    }

    @ViewBuilder private var content: some View {
        let atMs = WidgetSuiteTime.ms(entry.date)
        let label = entry.payload?.labels["untilRest"] ?? t("widgetSuiteUntilWeekend")
        if let weekend = entry.payload?.weekendStartMs, weekend > atMs {
            let target = WidgetSuiteTime.date(weekend)
            switch family {
            case .accessoryInline:
                Text("\(label) \(Text(target, style: .relative))")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).widgetAccentable()
                    Text(target, style: .relative).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                    if let holiday = entry.payload?.nextHoliday {
                        Text(t("widgetSuiteHolidayIn", ["name": holiday.name, "days": daysUntil(holiday)]))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 0) {
                    WidgetSuiteHeader(title: label, symbol: "sun.max.fill")
                    Spacer(minLength: 6)
                    Text(target, style: .relative)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    Text(t("widgetSuiteStartsAt", ["time": "\(WidgetSuiteFormat.weekday(weekend, locale: locale)) \(WidgetSuiteFormat.time(weekend, locale: locale))"]))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 8)
                    if let calendar = entry.calendar {
                        let week = WeekProgress(payload: calendar, atMs: atMs)
                        WidgetSuiteSegmentBar(segments: week.days.filter(\.isWork).map { (weight: 1, fill: week.fill(of: $0, atMs: atMs)) })
                    }
                }
            }
        } else {
            switch family {
            case .accessoryInline:
                Text(t("widgetSuiteRestingNow"))
            default:
                WidgetSuiteEmpty(title: label, message: entry.payload == nil ? t("widgetSuiteOpenToRefresh") : t("widgetSuiteRestingNow"),
                                 symbol: "sun.max.fill")
            }
        }
    }

    private func daysUntil(_ holiday: WidgetHolidayPayload.Holiday) -> String {
        WidgetSuiteFormat.count(HolidayMath.daysUntil(holiday.startMs, from: entry.date), locale: locale)
    }
}

nonisolated enum HolidayMath {
    static func daysUntil(_ startMs: Int64, from date: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: WidgetSuiteTime.date(startMs))
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: start).day ?? 0)
    }
}

struct HolidayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSuiteKind.holiday, provider: HolidayWidgetProvider()) { entry in
            HolidayWidgetView(entry: entry).widgetSuiteLocale(entry.payload?.locale)
        }
        .configurationDisplayName(WidgetSuiteCopy.t("widgetSuiteHolidayName", locale: WidgetSuiteCopy.systemLocale))
        .description(WidgetSuiteCopy.t("widgetSuiteHolidayDescription", locale: WidgetSuiteCopy.systemLocale))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct HolidayWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    /// Settings › Widgets renders these views at sizes the app's own
    /// environment cannot claim; widgets leave it nil.
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? environmentFamily }
    let entry: HolidayWidgetEntry

    private var locale: String { entry.payload?.locale ?? WidgetSuiteCopy.systemLocale }
    private func t(_ key: String, _ values: [String: String] = [:]) -> String {
        WidgetSuiteCopy.t(key, locale: locale, values: values)
    }

    var body: some View {
        content
            .widgetSuiteBackground()
            .widgetURL(URL(string: "offworkcountdown://leave"))
    }

    @ViewBuilder private var content: some View {
        if let payload = entry.payload {
            switch family {
            case .systemMedium: medium(payload)
            case .accessoryRectangular: rectangular(payload)
            default: small(payload)
            }
        } else {
            WidgetSuiteEmpty(title: t("widgetSuiteHolidayName"), message: t("widgetSuiteOpenToRefresh"), symbol: "gift")
        }
    }

    @ViewBuilder private func small(_ payload: WidgetHolidayPayload) -> some View {
        if let holiday = payload.nextHoliday {
            VStack(alignment: .leading, spacing: 0) {
                WidgetSuiteHeader(title: t("widgetSuiteNextHoliday"), trailing: holiday.name, symbol: "gift")
                Spacer(minLength: 6)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(WidgetSuiteFormat.count(HolidayMath.daysUntil(holiday.startMs, from: entry.date), locale: locale))
                        .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(t("widgetSuiteDaysUnit")).font(.subheadline.weight(.semibold))
                }
                Text(t("widgetSuiteHolidayRun", ["date": WidgetSuiteFormat.monthDay(holiday.startMs, locale: locale),
                                                 "days": WidgetSuiteFormat.count(holiday.days, locale: locale)]))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                if holiday.isEstimated {
                    Text(t("widgetSuiteHolidayEstimated")).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        } else {
            WidgetSuiteEmpty(title: t("widgetSuiteNextHoliday"), message: t("widgetSuiteHolidayRegionMissing"),
                             action: t("widgetSuiteOpenSettings"), symbol: "gift")
        }
    }

    @ViewBuilder private func medium(_ payload: WidgetHolidayPayload) -> some View {
        let atMs = WidgetSuiteTime.ms(entry.date)
        if payload.access.isUnlocked(atMs: atMs), let leave = payload.nextLeave {
            VStack(alignment: .leading, spacing: 0) {
                WidgetSuiteHeader(title: t("widgetSuiteNextLeave", ["days": WidgetSuiteFormat.count(HolidayMath.daysUntil(leave.startMs, from: entry.date), locale: locale)]),
                                  trailing: payload.labels["remaining"].flatMap { $0.isEmpty ? nil : $0 }, symbol: "suitcase")
                Text(payload.labels["requested"] ?? "")
                    .font(.system(size: 20, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6).padding(.top, 6)
                Spacer(minLength: 6)
                HStack(spacing: 3) {
                    ForEach(Array(leave.days.prefix(14).enumerated()), id: \.offset) { _, day in
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(color(day.kind))
                                .frame(height: 22)
                            Text(WidgetSuiteFormat.dayOfMonth(WidgetSuiteTime.ms(dayDate(day.dayKey)), locale: locale))
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                }
                legend.padding(.top, 6)
            }
        } else if payload.access.isUnlocked(atMs: atMs) {
            HStack(spacing: 16) {
                small(payload)
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text(t("widgetSuiteLeaveTitle")).font(.footnote.weight(.semibold))
                    Text(t("widgetSuiteLeaveEmpty")).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    Spacer(minLength: 0)
                    if let remaining = payload.labels["remaining"], !remaining.isEmpty {
                        Text(remaining).font(.caption.weight(.semibold))
                    }
                }
            }
        } else {
            HStack(spacing: 16) {
                small(payload)
                Divider()
                WidgetSuitePlusLock(title: t("widgetSuiteLeaveTitle"), promise: t("widgetSuiteLeavePromise"),
                                    locale: locale, compact: true)
            }
        }
    }

    @ViewBuilder private func rectangular(_ payload: WidgetHolidayPayload) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let holiday = payload.nextHoliday {
                Text(t("widgetSuiteNextHoliday")).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).widgetAccentable()
                Text(t("widgetSuiteHolidayIn", ["name": holiday.name,
                                                "days": WidgetSuiteFormat.count(HolidayMath.daysUntil(holiday.startMs, from: entry.date), locale: locale)]))
                    .font(.headline).lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text(t("widgetSuiteHolidayRegionMissing")).font(.caption).lineLimit(2)
            }
            if payload.access.isUnlocked(atMs: WidgetSuiteTime.ms(entry.date)),
               let remaining = payload.labels["remaining"], !remaining.isEmpty {
                Text(remaining).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendItem(t("widgetSuiteLegendHoliday"), WidgetSuitePalette.holiday)
            legendItem(t("widgetSuiteLeave"), WidgetSuitePalette.accent)
            legendItem(t("widgetSuiteRest"), Color.secondary.opacity(0.35))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    private func color(_ kind: WidgetHolidayPayload.Leave.DayKind) -> Color {
        switch kind {
        case .leave: WidgetSuitePalette.accent
        case .holiday: WidgetSuitePalette.holiday
        case .rest: Color.secondary.opacity(0.35)
        }
    }

    private func dayDate(_ key: String) -> Date {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return entry.date }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? entry.date
    }
}
