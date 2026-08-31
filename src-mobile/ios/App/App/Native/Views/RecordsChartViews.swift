import SwiftUI

struct RecordsChartsHomeView: View {
    let store: OffWorkStore
    var period: RecordsChartPeriod

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                metricsCard
                chartCard
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .background(OWCDesign.page)
        .navigationTitle(store.t(period.titleKey))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var window: (Date, Date) {
        store.recordsChartWindow(for: period)
    }

    private var days: [DayResolution] {
        store.resolvedDays(from: window.0, through: window.1)
    }

    private var metrics: RecordsPeriodMetrics {
        store.recordsMetrics(for: days)
    }

    private var metricsCard: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 10) {
                metric(store.t("recordsWorkdays"), value: "\(metrics.workdayCount)")
                metric(
                    store.t("recordsTotalHours"),
                    value: RelativeDurationFormatter.string(
                        milliseconds: Double(metrics.workDurationMs),
                        languageCode: store.languageCode
                    )
                )
                metric(store.t("recordsShareOfDay"), value: percent(metrics.shareOfDay))
                metric(store.t("recordsShareOfAwake"), value: percent(metrics.shareOfAwake))
                metric(
                    store.t("recordsDeclaredOvertime"),
                    value: RelativeDurationFormatter.string(
                        milliseconds: Double(metrics.declaredOvertimeMs),
                        languageCode: store.languageCode
                    )
                )
                metric(store.t("recordsLongestStreak"), value: "\(metrics.longestStreak)")
                metric(
                    store.t("recordsOwnTime"),
                    value: RelativeDurationFormatter.string(
                        milliseconds: Double(metrics.ownAwakeMs),
                        languageCode: store.languageCode
                    )
                )
                if metrics.usesCurrentSalary {
                    metric(
                        store.t("recordsIncomeCurrentSalary"),
                        value: metrics.estimatedIncome.formatted(.number.precision(.fractionLength(0...2)))
                    )
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var chartCard: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 10) {
                switch period {
                case .week:
                    weekBars
                case .month:
                    monthHeat
                case .year:
                    yearDensity
                }
            }
            .padding(16)
        }
    }

    private var weekBars: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(days, id: \.dayKey) { day in
                VStack(spacing: 6) {
                    Capsule()
                        .fill(day.isScheduledWorkday ? OWCDesign.accent : OWCDesign.control)
                        .frame(width: 14, height: barHeight(day))
                    if observationMarks(on: day) > 0 {
                        Circle()
                            .fill(OWCDesign.secondary)
                            .frame(width: 4, height: 4)
                    }
                    Text(weekday(day.shiftAnchorDate))
                        .font(.caption2)
                        .foregroundStyle(OWCDesign.secondary)
                }
                .frame(maxWidth: .infinity)
                .onTapGesture {
                    store.recordsPath.append(.day(day.dayKey))
                }
            }
        }
        .frame(height: 160)
    }

    private var monthHeat: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(days, id: \.dayKey) { day in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(heatColor(day))
                    .frame(height: 28)
                    .overlay {
                        if day.layer == .override {
                            Circle().stroke(OWCDesign.primary, lineWidth: 1.2).padding(7)
                        }
                    }
                    .onTapGesture { store.recordsPath.append(.day(day.dayKey)) }
            }
        }
    }

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
                                .onTapGesture { store.recordsPath.append(.day(day.dayKey)) }
                        }
                    }
                }
            }
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(OWCDesign.secondary)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
        }
        .font(.body)
    }

    private func percent(_ value: Double) -> String {
        (value * 100).formatted(.number.precision(.fractionLength(0...1))) + "%"
    }

    private func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.narrow))
    }

    private func barHeight(_ day: DayResolution) -> CGFloat {
        let ms = day.segments.reduce(0.0) { $0 + ($1.endAtMs - $1.startAtMs) }
        return max(8, min(120, CGFloat(ms / 3_600_000) * 12))
    }

    private func heatColor(_ day: DayResolution) -> Color {
        guard day.isScheduledWorkday else { return OWCDesign.control }
        let hours = day.segments.reduce(0.0) { $0 + ($1.endAtMs - $1.startAtMs) } / 3_600_000
        return OWCDesign.accent.opacity(min(1, 0.25 + hours / 12))
    }

    private func observationMarks(on day: DayResolution) -> Int {
        store.observations(on: day.shiftAnchorDate)
            .filter { $0.kind != .timerSurfaceFirstSeen }
            .count
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
