import SwiftUI

struct RecordsChartsHomeView: View {
    let store: OffWorkStore
    var period: RecordsChartPeriod

    @State private var window: (Date, Date)?
    @State private var days: [DayResolution] = []
    @State private var metrics: RecordsPeriodMetrics?
    @State private var income: Double?
    @State private var selectionFeedback = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        // A scroll container with tab-bar clearance. The plain `ScrollView`
        // ended flush with the bottom of the window, so at large text sizes the
        // last chart row sat underneath the tab bar.
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let metrics {
                    metricsCard(metrics)
                    if let window {
                        chartCard(window: window)
                    }
                    if period == .year {
                        monthBreakdownCard
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 180)
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 14)
        }
        .background(OWCDesign.page)
        .navigationTitle(store.t(period.titleKey))
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: selectionFeedback)
        .task(id: period) { await load() }
        .onChange(of: store.records.revision) { _, _ in
            Task { await load() }
        }
    }

    private func load() async {
        let next = store.recordsChartWindow(for: period)
        let resolved = await store.prepareResolvedDays(from: next.0, through: next.1)
        window = next
        days = resolved
        metrics = store.recordsMetrics(for: resolved)
        income = store.recordsIncome(for: period)
    }

    // MARK: - Metrics

    /// Two columns, so eight numbers are a summary rather than eight lines of
    /// running text. One column at accessibility sizes, where two would put
    /// three words on each line.
    private func metricsCard(_ summary: RecordsPeriodMetrics) -> some View {
        let items = metricItems(summary)
        let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return OWCGroupCard {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 16, alignment: .topLeading),
                    count: columns
                ),
                alignment: .leading,
                spacing: 14
            ) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.footnote)
                            .foregroundStyle(OWCDesign.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(item.value)
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(item.title)
                    .accessibilityValue(item.value)
                }
            }
            .padding(16)
        }
    }

    private struct Metric: Identifiable {
        let id: String
        let title: String
        let value: String
    }

    private func metricItems(_ summary: RecordsPeriodMetrics) -> [Metric] {
        var items: [Metric] = [
            Metric(id: "workdays", title: store.t("recordsWorkdays"), value: store.formatCount(summary.workdayCount)),
            Metric(
                id: "hours",
                title: store.t("recordsTotalHours"),
                value: store.formatRelativeDuration(Double(summary.workDurationMs))
            ),
            Metric(id: "share", title: store.t("recordsShareOfDay"), value: percent(summary.shareOfDay)),
            Metric(id: "awake", title: store.t("recordsShareOfAwake"), value: percent(summary.shareOfAwake)),
            Metric(
                id: "overtime",
                title: store.t("recordsDeclaredOvertime"),
                value: store.formatRelativeDuration(Double(summary.declaredOvertimeMs))
            ),
            Metric(
                id: "streak",
                title: store.t("recordsLongestStreak"),
                value: store.formatCount(summary.longestStreak)
            ),
            Metric(
                id: "own",
                title: store.t("recordsOwnTime"),
                value: store.formatRelativeDuration(Double(summary.ownAwakeMs))
            ),
        ]
        if let income {
            items.append(
                Metric(
                    id: "income",
                    title: store.t("recordsIncomeCurrentSalary"),
                    value: store.moneyText(income)
                )
            )
        }
        return items
    }

    // MARK: - Charts

    private func chartCard(window: (Date, Date)) -> some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(windowLabel(window))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(OWCDesign.secondary)

                switch period {
                case .week:
                    weekBars
                case .month:
                    monthHeat
                case .year:
                    yearDensity
                }

                heatLegend
            }
            .padding(16)
        }
    }

    private func windowLabel(_ window: (Date, Date)) -> String {
        switch period {
        // Plain interpolation, unlike a clock range: month names are words, and
        // in Arabic the two ends of a date range belong in the paragraph's own
        // order.
        case .week:
            return "\(store.formatRecordsMonthDay(window.0)) – \(store.formatRecordsMonthDay(window.1))"
        case .month:
            return store.formatRecordsMonthYear(window.0)
        case .year:
            return "\(store.formatRecordsMonthYear(window.0)) – \(store.formatRecordsMonthYear(window.1))"
        }
    }

    private var weekBars: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(days, id: \.dayKey) { day in
                dayButton(day) {
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        Capsule()
                            .fill(day.isScheduledWorkday ? OWCDesign.accent : OWCDesign.control)
                            .frame(width: 14, height: barHeight(day))
                        if observationMarks(on: day) > 0 {
                            Circle()
                                .fill(OWCDesign.secondary)
                                .frame(width: 4, height: 4)
                        }
                        Text(store.formatRecordsWeekdayNarrow(day.shiftAnchorDate))
                            .font(.caption)
                            .foregroundStyle(OWCDesign.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
        .frame(height: 170)
    }

    private var monthHeat: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let blanks = days.first.map { store.recordsGridLeadingBlanks(before: $0.shiftAnchorDate) } ?? 0
        return VStack(spacing: 6) {
            // A weekday header, and blank cells before the first of the month.
            // Without the offset the grid simply filled from the top left, so
            // every date sat in the wrong column for the whole month.
            HStack(spacing: 4) {
                ForEach(Array(store.recordsWeekdayGridSymbols().enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption)
                        .foregroundStyle(OWCDesign.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(0..<blanks), id: \.self) { _ in
                    Color.clear.frame(height: 44)
                }
                ForEach(days, id: \.dayKey) { day in
                    dayButton(day) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(heatColor(day))
                            .frame(height: 44)
                            .overlay {
                                Text(store.formatCount(dayOfMonth(day)))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(heatLabelStyle(day))
                            }
                            .overlay {
                                if day.layer == .override {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(OWCDesign.primary, lineWidth: contrast == .increased ? 1.6 : 1.2)
                                }
                            }
                    }
                }
            }
        }
    }

    /// A summary, not a control surface. Three hundred and sixty-five 8pt cells
    /// cannot each carry a 44pt target without the targets overlapping, so the
    /// heat map is decoration and the month list below it is the accessible,
    /// tappable version of the same data.
    private var yearDensity: some View {
        let weeks = stride(from: 0, to: days.count, by: 7).map { start in
            Array(days[start..<min(start + 7, days.count)])
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 2) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 2) {
                        ForEach(week, id: \.dayKey) { day in
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .fill(heatColor(day))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Colour depth is the only thing separating a long day from a short one.
    /// The scale is spelled out here, and named in words when the system asks
    /// for something other than colour.
    private var heatLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(store.t("recordsHeatLess"))
                    .font(.caption)
                    .foregroundStyle(OWCDesign.secondary)
                ForEach([0.25, 0.45, 0.65, 0.85, 1.0], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(OWCDesign.accent.opacity(level))
                        .frame(width: 14, height: 10)
                }
                Text(store.t("recordsHeatMore"))
                    .font(.caption)
                    .foregroundStyle(OWCDesign.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(store.t("recordsHeatScale"))

            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(OWCDesign.primary, lineWidth: 1.2)
                    .frame(width: 10, height: 10)
                Text(store.t("recordsSourceOverride"))
                    .font(.caption)
                    .foregroundStyle(OWCDesign.secondary)
            }
            .accessibilityElement(children: .combine)

            if differentiateWithoutColor {
                Text(store.t("recordsHeatWithoutColor"))
                    .font(.caption)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Year month list

    private var monthBreakdownCard: some View {
        let months = MonthSummary.build(days: days, calendar: store.recordsCalendar)
        return VStack(alignment: .leading, spacing: 0) {
            OWCSectionHeader(title: store.t("recordsByMonth"))
            OWCGroupCard {
                ForEach(Array(months.enumerated()), id: \.element.id) { index, month in
                    OWCRow(
                        title: store.formatRecordsMonthYear(month.start),
                        subtitle: store.t(
                            "recordsMonthWorkdays",
                            values: ["count": store.formatCount(month.workdays)]
                        ),
                        isLast: index == months.count - 1,
                        centersVertically: true
                    ) {
                        Text(store.formatRelativeDuration(Double(month.durationMs)))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(OWCDesign.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Pieces

    /// A real button, so a chart cell has a pressed state, a VoiceOver label and
    /// a target the finger can actually hit. These were bare `onTapGesture`
    /// modifiers on 28pt and 8pt rectangles.
    private func dayButton<Content: View>(
        _ day: DayResolution,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button {
            selectionFeedback += 1
            store.recordsPath.append(.day(day.dayKey))
        } label: {
            content()
                .contentShape(Rectangle())
        }
        .buttonStyle(OWCChartCellButtonStyle())
        .accessibilityLabel(store.formatRecordsDayTitle(day.shiftAnchorDate))
        .accessibilityValue(dayAccessibilityValue(day))
    }

    private func dayAccessibilityValue(_ day: DayResolution) -> String {
        guard day.isScheduledWorkday, !day.segments.isEmpty else {
            return store.t("recordsRestDay")
        }
        let ms = day.segments.reduce(0.0) { $0 + ($1.endAtMs - $1.startAtMs) }
        return store.formatRelativeDuration(ms)
    }

    private func percent(_ value: Double) -> String {
        // `formatPercent` takes 0–100 and localises the symbol too; Turkish
        // puts it in front, and a hand-appended "%" cannot.
        store.formatPercent(value * 100)
    }

    private func dayOfMonth(_ day: DayResolution) -> Int {
        store.recordsCalendar.component(.day, from: day.shiftAnchorDate)
    }

    private func barHeight(_ day: DayResolution) -> CGFloat {
        let ms = day.segments.reduce(0.0) { $0 + ($1.endAtMs - $1.startAtMs) }
        return max(8, min(110, CGFloat(ms / 3_600_000) * 12))
    }

    private func heatFillOpacity(_ day: DayResolution) -> Double {
        let hours = day.segments.reduce(0.0) { $0 + ($1.endAtMs - $1.startAtMs) } / 3_600_000
        return min(1, 0.25 + hours / 12)
    }

    /// Saturated orange needs a light numeral; a wash of accent needs a
    /// dark one. Rest days stay secondary so they recede.
    private func heatLabelStyle(_ day: DayResolution) -> Color {
        guard day.isScheduledWorkday else { return OWCDesign.secondary }
        return heatFillOpacity(day) >= 0.55 ? .white : OWCDesign.primary
    }

    private func heatColor(_ day: DayResolution) -> Color {
        guard day.isScheduledWorkday else { return OWCDesign.control }
        return OWCDesign.accent.opacity(heatFillOpacity(day))
    }

    private func observationMarks(on day: DayResolution) -> Int {
        store.observations(on: day.shiftAnchorDate)
            .filter { $0.kind != .timerSurfaceFirstSeen }
            .count
    }
}

/// A month of the year chart, as a row.
private struct MonthSummary: Identifiable {
    var id: String
    var start: Date
    var workdays: Int
    var durationMs: Int64

    static func build(days: [DayResolution], calendar: Calendar) -> [MonthSummary] {
        let grouped = Dictionary(grouping: days) { day in
            calendar.dateComponents([.year, .month], from: day.shiftAnchorDate)
        }
        return grouped.compactMap { components, days -> MonthSummary? in
            guard let start = calendar.date(from: components) else { return nil }
            let working = days.filter { $0.isScheduledWorkday && !$0.segments.isEmpty }
            return MonthSummary(
                id: "\(components.year ?? 0)-\(components.month ?? 0)",
                start: start,
                workdays: working.count,
                durationMs: working.reduce(Int64(0)) { partial, day in
                    partial + day.segments.reduce(Int64(0)) { $0 + Int64($1.endAtMs - $1.startAtMs) }
                }
            )
        }
        .sorted { $0.start < $1.start }
    }
}

/// Press feedback for a chart cell. `OWCRowButtonStyle` tints a whole row's
/// background, which on a heat cell would read as a different value.
struct OWCChartCellButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.press, value: configuration.isPressed)
    }
}

enum RecordsChartPeriod: Hashable {
    case week
    case month
    case year

    var titleKey: String {
        switch self {
        case .week: "recordsWeek"
        case .month: "recordsMonth"
        case .year: "recordsYear"
        }
    }
}
