import SwiftUI

// The Records calendar (3.2.2). One vocabulary at every scale: a solid mark
// is something that happened, an outlined mark is planned or estimated, orange
// is overtime and today, green is a public holiday. Locked days are only
// greyed; the single way into Plus sits under the calendar.

/// How one day is drawn, shared by the week, month and year so the same day
/// cannot read differently on two scales.
struct RecordsDayLook {
    let cell: RecordsDayCell
    let holiday: HolidayDayAnnotation?

    init(_ cell: RecordsDayCell, preferences: PreferencesStore) {
        self.cell = cell
        holiday = RecordsDayMarks.holiday(cell, preferences: preferences)
    }

    var isLocked: Bool { cell.appearance == .locked }
    var holidayName: String? {
        guard let holiday, !holiday.isMakeupWorkday, !isLocked else { return nil }
        return holiday.name
    }
    var isMakeupWorkday: Bool { holiday?.isMakeupWorkday == true && !isLocked }
    var isHoliday: Bool { holiday != nil && !isMakeupWorkday && !isLocked }
    var totalMs: Int64 { max(0, cell.workMs) + max(0, cell.overtimeMs) }
    /// Today's saved schedule has not happened yet, so it is drawn as planned.
    var isEstimated: Bool {
        RecordsDayMarks.isEstimated(cell) || (cell.isToday && cell.isFromSavedSchedule && totalMs > 0)
    }
    /// Solid hours: anything that already happened, including a saved schedule.
    var hasSolidHours: Bool {
        !isLocked && !isEstimated && totalMs > 0
            && (cell.appearance == .recorded || cell.appearance == .corrected)
    }
    var hasHours: Bool { !isLocked && totalMs > 0 && (hasSolidHours || isEstimated) }
    var isUnrecordedWorkday: Bool { !isLocked && cell.appearance == .unrecorded && !cell.isFuture }
    var isQuietDay: Bool {
        isHoliday || cell.appearance == .rest
    }
}

/// Number circle: orange for today, the label colour for the selection.
private struct RecordsDayNumber: View {
    let label: String
    let look: RecordsDayLook
    let isSelected: Bool
    let size: CGFloat
    var font: Font = .body

    var body: some View {
        Text(label)
            .font(font.weight(look.cell.isToday || isSelected ? .semibold : .regular).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background {
                if look.cell.isToday {
                    Circle().fill(OWCDesign.accent)
                } else if isSelected {
                    Circle().fill(OWCDesign.primary)
                }
            }
    }

    private var foreground: Color {
        if look.cell.isToday { return .white }
        if isSelected { return OWCDesign.card }
        if look.isLocked { return OWCDesign.tertiary }
        if look.isQuietDay { return OWCDesign.secondary }
        return OWCDesign.primary
    }
}

/// The corner mark: a conflict outranks the holiday and make-up marks.
private struct RecordsDayBadge: View {
    let look: RecordsDayLook

    var body: some View {
        Group {
            if look.cell.hasConflict && !look.isLocked {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(OWCDesign.orangeDeep)
            } else if look.isMakeupWorkday {
                Image(systemName: "briefcase.fill")
                    .foregroundStyle(OWCDesign.secondary)
            } else if look.isHoliday {
                Image(systemName: "sun.max")
                    .fontWeight(.bold)
                    .foregroundStyle(OWCDesign.recordsHoliday)
            }
        }
        .font(.system(size: 8, weight: .semibold))
        .accessibilityHidden(true)
    }
}

/// The month mark: bar length follows the hours, overtime is the orange tail,
/// an outlined bar is planned or estimated, a dot says you changed the day.
struct RecordsDayBar: View {
    let look: RecordsDayLook
    var height: CGFloat = 4

    var body: some View {
        HStack(spacing: 0) {
            if look.hasHours {
                let hours = Double(look.totalMs) / 3_600_000
                let width = min(24, 6 + hours * 1.8)
                let overtime = Double(max(0, look.cell.overtimeMs))
                let overtimeWidth = overtime > 0 ? max(3, width * overtime / Double(look.totalMs)) : 0
                let shape = RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                Group {
                    if look.isEstimated {
                        shape.strokeBorder(OWCDesign.recordsWork, lineWidth: 1.25).opacity(0.65)
                    } else {
                        shape.fill(OWCDesign.recordsWork)
                    }
                }
                .frame(width: max(2, width - overtimeWidth), height: height)
                if overtimeWidth > 0 {
                    shape.fill(OWCDesign.recordsOvertime)
                        .frame(width: overtimeWidth, height: height)
                        .padding(.leading, 1.5)
                }
            }
            if look.cell.appearance == .corrected && !look.isLocked {
                Circle().fill(OWCDesign.secondary)
                    .frame(width: 4, height: 4)
                    .padding(.leading, 3)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A holiday name written once per run and spanning the run's days in one
/// week row, like an all-day event in Calendar.
private struct RecordsHolidayRuns: View {
    struct Run: Identifiable {
        var id: Int { start }
        let start: Int
        let length: Int
        let name: String
    }

    let runs: [Run]
    var height: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            let column = proxy.size.width / 7
            ForEach(runs) { run in
                Text(run.name)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(OWCDesign.recordsHoliday)
                    .padding(.horizontal, 4)
                    .frame(width: max(0, column * CGFloat(run.length) - 4), height: height, alignment: .leading)
                    .background(OWCDesign.recordsHoliday.opacity(0.14), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .offset(x: column * CGFloat(run.start) + 2)
            }
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// `looks` is one row in column order; `nil` is a blank column.
    static func runs(_ looks: [RecordsDayLook?]) -> [Run] {
        var result: [Run] = []
        var index = 0
        while index < looks.count {
            guard let name = looks[index]?.holidayName, !name.isEmpty else {
                index += 1
                continue
            }
            var length = 1
            while index + length < looks.count, looks[index + length]?.holidayName == name { length += 1 }
            result.append(Run(start: index, length: length, name: name))
            index += length
        }
        return result
    }
}

// MARK: - Month

struct RecordsMonthCalendar: View {
    let queries: RecordsQueries
    let preferences: PreferencesStore
    let text: AppText
    let cells: [RecordsDayCell]
    let selectedDayKey: String?
    var onSelect: (RecordsDayCell) -> Void
    var onOpen: (RecordsDayCell) -> Void
    @ScaledMetric(relativeTo: .body) private var numberSize: CGFloat = 32
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 60

    var body: some View {
        let looks = cells.map { RecordsDayLook($0, preferences: preferences) }
        let blanks = cells.first.map { queries.recordsGridLeadingBlanks(before: $0.date) } ?? 0
        let slots: [RecordsDayLook?] = Array(repeating: nil, count: blanks) + looks
        let rows = stride(from: 0, to: slots.count, by: 7).map { start in
            Array(slots[start..<min(start + 7, slots.count)])
                + Array(repeating: nil, count: max(0, start + 7 - slots.count))
        }
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(Array(queries.recordsWeekdayGridSymbols().enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(OWCDesign.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 2)
            .accessibilityHidden(true)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, look in
                            if let look {
                                dayButton(look)
                            } else {
                                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
                    RecordsHolidayRuns(runs: RecordsHolidayRuns.runs(row))
                        .padding(.top, 3 + numberSize + 1)
                }
                .frame(height: rowHeight)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func dayButton(_ look: RecordsDayLook) -> some View {
        Button { onSelect(look.cell) } label: {
            VStack(spacing: 0) {
                RecordsDayNumber(
                    label: text.formatCount(preferences.recordsCalendar.component(.day, from: look.cell.date)),
                    look: look,
                    isSelected: look.cell.dayKey == selectedDayKey,
                    size: numberSize
                )
                Color.clear.frame(height: 13)
                RecordsDayBar(look: look)
                    .frame(height: 8)
                Spacer(minLength: 0)
            }
            .padding(.top, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                RecordsDayBadge(look: look).padding(.top, 3).padding(.trailing, 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(RecordsDayMarks.accessibilityLabel(look.cell, queries: queries, text: text, holiday: look.holiday))
        .accessibilityAddTraits(look.cell.dayKey == selectedDayKey ? .isSelected : [])
        .accessibilityAction(named: Text(text.t("recordsSeeThisDay"))) { onOpen(look.cell) }
    }
}

// MARK: - Week

struct RecordsWeekChart: View {
    let queries: RecordsQueries
    let preferences: PreferencesStore
    let text: AppText
    let cells: [RecordsDayCell]
    let selectedDayKey: String?
    let isAuthorized: Bool
    let overtimeMs: Double?
    var onSelect: (RecordsDayCell) -> Void
    var onOpen: (RecordsDayCell) -> Void
    @ScaledMetric(relativeTo: .subheadline) private var numberSize: CGFloat = 30
    private let chartHeight: CGFloat = 148

    var body: some View {
        let looks = cells.map { RecordsDayLook($0, preferences: preferences) }
        VStack(alignment: .leading, spacing: 0) {
            header(looks)
                .padding(.bottom, 14)
            ZStack(alignment: .topLeading) {
                if let guide = guideMs(looks) {
                    guideLine(guide)
                }
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(looks, id: \.cell.dayKey) { look in
                        column(look)
                    }
                }
            }
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(looks, id: \.cell.dayKey) { look in
                        weekdayLabel(look)
                    }
                }
                RecordsHolidayRuns(runs: RecordsHolidayRuns.runs(looks), height: 14)
            }
            .padding(.top, 8)
            HStack(spacing: 0) {
                ForEach(looks, id: \.cell.dayKey) { look in
                    Button { onSelect(look.cell) } label: {
                        RecordsDayNumber(
                            label: text.formatCount(preferences.recordsCalendar.component(.day, from: look.cell.date)),
                            look: look,
                            isSelected: look.cell.dayKey == selectedDayKey,
                            size: numberSize,
                            font: .subheadline
                        )
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(RecordsDayMarks.accessibilityLabel(look.cell, queries: queries, text: text, holiday: look.holiday))
                    .accessibilityAddTraits(look.cell.dayKey == selectedDayKey ? .isSelected : [])
                    .accessibilityAction(named: Text(text.t("recordsSeeThisDay"))) { onOpen(look.cell) }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    @ViewBuilder
    private func header(_ looks: [RecordsDayLook]) -> some View {
        if isAuthorized {
            let total = looks.filter(\.hasSolidHours).reduce(Int64(0)) { $0 + $1.totalMs }
            VStack(alignment: .leading, spacing: 2) {
                RecordsHeroDuration(text: text, milliseconds: Double(total))
                Text(weekSubtitle(looks))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(overtimeMs.map { [text.t("recordsOvertimeRecorded"), text.formatRelativeDuration($0)].joined(separator: " ") }
                 ?? text.t("recordsNoOvertime"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OWCDesign.primary)
        }
    }

    private func weekSubtitle(_ looks: [RecordsDayLook]) -> String {
        let recorded = looks.filter(\.hasSolidHours)
        var first = text.t("recordsWorkdaysRecorded", values: ["count": text.formatCount(recorded.count)])
        let overtime = recorded.reduce(Int64(0)) { $0 + max(0, $1.cell.overtimeMs) }
        if overtime > 0 {
            first = text.t("recordsListJoin", values: [
                "first": first,
                "second": text.t("recordsOvertimeAmount", values: ["duration": text.formatRelativeDuration(Double(overtime))]),
            ])
        }
        var parts = [first]
        parts += RecordsHolidaySummary.parts(looks, text: text)
        return parts.joined(separator: " · ")
    }

    /// The day's planned length, drawn once as a dashed reference line.
    private func guideMs(_ looks: [RecordsDayLook]) -> Int64? {
        let planned = looks.filter { $0.hasHours }.map { max(0, $0.cell.workMs) }
        guard !planned.isEmpty else { return nil }
        var counts: [Int64: Int] = [:]
        for value in planned { counts[value, default: 0] += 1 }
        return counts.max { $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value }?.key
    }

    private func scaleMs(_ looks: [RecordsDayLook]) -> Double {
        max(12 * 3_600_000, Double(looks.map(\.totalMs).max() ?? 0))
    }

    private func guideLine(_ ms: Int64) -> some View {
        let looks = cells.map { RecordsDayLook($0, preferences: preferences) }
        let y = 16 + chartHeight * (1 - CGFloat(Double(ms) / scaleMs(looks)))
        return ZStack(alignment: .topTrailing) {
            Line()
                .stroke(OWCDesign.separator, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(height: 1)
            Text(text.formatHours(Double(ms) / 3_600_000))
                .font(.system(size: 10))
                .foregroundStyle(OWCDesign.tertiary)
                .offset(y: -14)
        }
        .padding(.top, y)
        .accessibilityHidden(true)
    }

    private func column(_ look: RecordsDayLook) -> some View {
        let scale = scaleMs(cells.map { RecordsDayLook($0, preferences: preferences) })
        let work = CGFloat(Double(max(0, look.cell.workMs)) / scale) * chartHeight
        let overtime = CGFloat(Double(max(0, look.cell.overtimeMs)) / scale) * chartHeight
        return Button { onSelect(look.cell) } label: {
            VStack(spacing: 0) {
                Text(valueLabel(look))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(height: 16)
                VStack(spacing: 2) {
                    if look.hasHours {
                        if overtime > 0 {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(OWCDesign.recordsOvertime)
                                .frame(width: 16, height: max(4, overtime))
                        }
                        if work > 0 {
                            Group {
                                if look.isEstimated {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(OWCDesign.recordsWork, lineWidth: 1.5)
                                        .opacity(0.65)
                                } else {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(OWCDesign.recordsWork)
                                }
                            }
                            .frame(width: 16, height: max(4, work))
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: chartHeight, maxHeight: chartHeight, alignment: .bottom)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }

    private func valueLabel(_ look: RecordsDayLook) -> String {
        if look.hasHours {
            let hours = Double(look.totalMs) / 3_600_000
            return hours.formatted(.number.precision(.fractionLength(0...1)).locale(preferences.locale))
        }
        return look.isUnrecordedWorkday ? text.t("recordsUnrecorded") : ""
    }

    private func weekdayLabel(_ look: RecordsDayLook) -> some View {
        HStack(spacing: 2) {
            if look.isMakeupWorkday {
                Image(systemName: "briefcase.fill").font(.system(size: 7))
            }
            Text(look.holidayName == nil ? queries.formatRecordsWeekdayNarrow(look.cell.date) : " ")
        }
        .font(.caption2)
        .foregroundStyle(OWCDesign.tertiary)
        .frame(maxWidth: .infinity, minHeight: 14)
        .accessibilityHidden(true)
    }

    private nonisolated struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

/// "17 hours" with the number set large and the unit small.
struct RecordsHeroDuration: View {
    let text: AppText
    let milliseconds: Double

    var body: some View {
        let hours = milliseconds / 3_600_000
        let rounded = (hours * 10).rounded() / 10
        let full = text.formatHours(rounded)
        let number = rounded.formatted(.number.precision(.fractionLength(0...1)).locale(text.locale))
        Text(RecordsHeroDuration.attributed(full, number: number))
    }

    static func attributed(_ full: String, number: String,
                           numberFont: Font = .system(.largeTitle, design: .rounded).weight(.bold),
                           unitFont: Font = .subheadline.weight(.semibold),
                           unitColor: Color = OWCDesign.secondary) -> AttributedString {
        var value = AttributedString(full)
        value.font = unitFont
        value.foregroundColor = unitColor
        if let range = value.range(of: number) {
            value[range].font = numberFont
            value[range].foregroundColor = OWCDesign.primary
        }
        return value
    }
}

enum RecordsHolidaySummary {
    /// "National Day · 4 days off", once per holiday visible in the period.
    static func parts(_ looks: [RecordsDayLook], text: AppText) -> [String] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for look in looks {
            guard let name = look.holidayName, !name.isEmpty else { continue }
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += 1
        }
        return order.map {
            text.t("recordsHolidayDaysOff", values: ["name": $0, "count": text.formatCount(counts[$0] ?? 0)])
        }
    }
}

// MARK: - Year

struct RecordsYearCalendar: View {
    let queries: RecordsQueries
    let preferences: PreferencesStore
    let text: AppText
    let cells: [RecordsDayCell]
    let selectedMonth: Int?
    var onSelectMonth: (Int) -> Void
    var onOpenMonth: (Int) -> Void

    var body: some View {
        let calendar = preferences.recordsCalendar
        let byMonth = Dictionary(grouping: cells) { calendar.component(.month, from: $0.date) }
        let currentMonth = cells.first(where: \.isToday).map { calendar.component(.month, from: $0.date) }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 6) {
            ForEach(1...12, id: \.self) { month in
                let monthCells = byMonth[month] ?? []
                Button { onSelectMonth(month) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(monthLabel(month))
                            .font(.footnote.weight(month == selectedMonth || month == currentMonth ? .semibold : .regular))
                            .foregroundStyle(month == selectedMonth ? OWCDesign.accent : OWCDesign.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.leading, 2)
                        dots(monthCells)
                    }
                    .padding(EdgeInsets(top: 6, leading: 6, bottom: 8, trailing: 6))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(
                        month == selectedMonth ? OWCDesign.control : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture(count: 2).onEnded { onOpenMonth(month) })
                .accessibilityLabel(monthLabel(month))
                .accessibilityAddTraits(month == selectedMonth ? .isSelected : [])
                .accessibilityAction(named: Text(text.t("recordsSeeThisMonth"))) { onOpenMonth(month) }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func dots(_ monthCells: [RecordsDayCell]) -> some View {
        let blanks = monthCells.first.map { queries.recordsGridLeadingBlanks(before: $0.date) } ?? 0
        let slots: [RecordsDayCell?] = Array(repeating: nil, count: blanks) + monthCells
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 3) {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, cell in
                Group {
                    if let cell { dot(RecordsDayLook(cell, preferences: preferences)) } else { Color.clear }
                }
                .frame(height: 8)
            }
        }
    }

    @ViewBuilder
    private func dot(_ look: RecordsDayLook) -> some View {
        if look.cell.isToday {
            Circle().fill(OWCDesign.accent)
                .frame(width: 5, height: 5)
                .padding(1.5)
                .overlay(Circle().stroke(OWCDesign.accent, lineWidth: 1.2))
        } else if look.hasSolidHours {
            Circle().fill(look.cell.overtimeMs > 0 ? OWCDesign.recordsOvertime : OWCDesign.recordsWork)
                .frame(width: 6, height: 6)
        } else if look.isHoliday {
            Circle().fill(OWCDesign.recordsHoliday).frame(width: 5, height: 5)
        } else if look.hasHours {
            Circle().strokeBorder(OWCDesign.recordsWork, lineWidth: 1)
                .opacity(0.55)
                .frame(width: 6, height: 6)
        } else {
            Circle().fill(OWCDesign.tertiary).opacity(0.7).frame(width: 3, height: 3)
        }
    }

    private func monthLabel(_ month: Int) -> String {
        var parts = preferences.recordsCalendar.dateComponents([.year], from: cells.first?.date ?? .now)
        parts.month = month
        parts.day = 1
        return queries.formatRecordsMonthShort(preferences.recordsCalendar.date(from: parts) ?? .now)
    }
}

// MARK: - Life

/// One square per year of age, a row per decade, in the stage colours. Years
/// behind you are filled, years ahead are outlined, this year has an orange ring.
struct RecordsLifeYears: View {
    let preferences: PreferencesStore
    let text: AppText
    let stages: [LifeStageSpan]
    let bounds: (Date, Date)
    let referenceDate: Date
    @Binding var selectedDate: Date?

    var body: some View {
        let calendar = preferences.recordsCalendar
        let birth = bounds.0
        let currentAge = max(0, calendar.dateComponents([.year], from: birth, to: referenceDate).year ?? 0)
        let span = max(1, (calendar.dateComponents([.year], from: birth, to: bounds.1).year ?? 80))
        // Retirement is open-ended, so the grid always reaches 80.
        let rows = max(8, Int((Double(span) / 10).rounded(.up)))
        let selectedAge = selectedDate.map { max(0, calendar.dateComponents([.year], from: birth, to: $0).year ?? currentAge) } ?? currentAge
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 6) {
                    Text(text.formatCount(row * 10))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(OWCDesign.tertiary)
                        .frame(width: 28, alignment: .trailing)
                        .accessibilityHidden(true)
                    HStack(spacing: 4) {
                        ForEach(0..<10, id: \.self) { column in
                            yearCell(age: row * 10 + column, birth: birth, currentAge: currentAge, selectedAge: selectedAge)
                        }
                    }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func yearCell(age: Int, birth: Date, currentAge: Int, selectedAge: Int) -> some View {
        let calendar = preferences.recordsCalendar
        let start = calendar.date(byAdding: .year, value: age, to: birth) ?? birth
        let middle = calendar.date(byAdding: .month, value: 6, to: start) ?? start
        let stage = LifeStageCalculator.stage(at: middle, stages: stages)
        let color = (stage?.kind ?? .unset).owcColor
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return Button {
            selectedDate = age == currentAge ? nil : middle
        } label: {
            Group {
                if age < currentAge {
                    shape.fill(color)
                } else if age == currentAge {
                    shape.fill(color)
                        .padding(2)
                        .overlay(shape.strokeBorder(OWCDesign.accent, lineWidth: 1.5))
                } else {
                    shape.strokeBorder(color, lineWidth: 1.25).opacity(0.6)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 18)
            .overlay {
                if age == selectedAge && age != currentAge {
                    shape.stroke(OWCDesign.primary, lineWidth: 2).padding(-2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text.t("lifeYearAgeTitle", values: [
            "year": text.formatYear(calendar.component(.year, from: start)),
            "age": text.formatCount(age),
        ]))
        .accessibilityValue(stage.map { text.t($0.kind.titleKey) } ?? "")
        .accessibilityAddTraits(age == selectedAge ? .isSelected : [])
    }
}

// MARK: - Shared pieces under the calendar

/// What the selected day, month or year is, in one tappable row.
struct RecordsSelectionRow: View {
    let title: String
    let subtitle: String
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) { content(showsChevron: true) }
                    .buttonStyle(.plain)
            } else {
                content(showsChevron: false)
            }
        }
        .padding(.top, 10)
    }

    private func content(showsChevron: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OWCDesign.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OWCDesign.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(OWCDesign.control, in: RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

enum RecordsDayDescription {
    @MainActor static func subtitle(_ look: RecordsDayLook, text: AppText) -> String {
        if look.isLocked { return text.t("recordsLockedDayDetail") }
        var parts: [String] = []
        let cell = look.cell
        if cell.isToday { parts.append(text.t("focusToday")) }
        if let name = look.holidayName {
            parts.append(name.isEmpty ? text.t("holidayRestDay") : "\(name) · \(text.t("holidayRestDay"))")
        }
        if look.isMakeupWorkday, let holiday = look.holiday {
            parts.append(holiday.name.isEmpty ? text.t("holidayMakeupWorkday") : "\(holiday.name) · \(text.t("holidayMakeupWorkday"))")
        }
        let hours = text.formatRelativeDuration(Double(look.totalMs))
        if look.hasSolidHours {
            parts.append(cell.overtimeMs > 0
                ? text.t("recordsDayHoursWithOvertime", values: [
                    "hours": hours, "overtime": text.formatRelativeDuration(Double(cell.overtimeMs)),
                ])
                : hours)
            parts.append(text.t(RecordsDayMarks.sourceKey(cell)))
        } else if look.hasHours {
            parts.append(text.t(cell.isProjection ? "recordsDayProjectedHours" : "recordsDayPlannedHours", values: ["hours": hours]))
        } else if look.isUnrecordedWorkday {
            parts.append(text.t("recordsDayUnrecordedWorkday"))
        } else if look.holidayName == nil {
            parts.append(text.t("recordsRestDay"))
        }
        if cell.hasConflict { parts.append(text.t("recordsConflictCopy")) }
        return parts.joined(separator: " · ")
    }

    @MainActor static func periodSubtitle(_ cells: [RecordsDayCell], preferences: PreferencesStore, text: AppText) -> String {
        let looks = cells.map { RecordsDayLook($0, preferences: preferences) }
        if !looks.isEmpty, looks.allSatisfy(\.isLocked) { return text.t("recordsLockedDayDetail") }
        let recorded = looks.filter(\.hasSolidHours)
        let projected = looks.filter { $0.hasHours && $0.cell.isProjection }
        let planned = looks.filter { $0.hasHours && !$0.cell.isProjection && $0.isEstimated }
        let overtime = recorded.reduce(Int64(0)) { $0 + max(0, $1.cell.overtimeMs) }
        var parts: [String] = []
        if !recorded.isEmpty {
            parts.append(text.t("recordsDaysRecordedTotal", values: [
                "count": text.formatCount(recorded.count),
                "hours": text.formatRelativeDuration(Double(recorded.reduce(Int64(0)) { $0 + $1.totalMs })),
            ]))
        }
        if !projected.isEmpty {
            parts.append(text.t("recordsProjectedWorkdays", values: ["count": text.formatCount(projected.count)]))
        }
        if overtime > 0 {
            parts.append(text.t("recordsOvertimeAmount", values: ["duration": text.formatRelativeDuration(Double(overtime))]))
        }
        if !planned.isEmpty {
            parts.append(text.t("recordsPlannedWorkdaysLeft", values: ["count": text.formatCount(planned.count)]))
        }
        let holidays = looks.filter(\.isHoliday).count
        if holidays > 0 {
            parts.append(text.t("recordsDaysOff", values: ["count": text.formatCount(holidays)]))
        }
        return parts.isEmpty ? text.t("recordsUnrecorded") : parts.joined(separator: " · ")
    }
}

/// One centred line of keys, with an optional second line for holiday marks.
struct RecordsCalendarLegend: View {
    enum Style { case bars, dots }

    let text: AppText
    var style: Style = .bars
    var showsHolidays = false
    var showsMakeup = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                item(text.t("recordsLegendRecordedShort")) { solid(OWCDesign.recordsWork) }
                if style == .dots {
                    item(text.t("recordsOvertime")) { solid(OWCDesign.recordsOvertime) }
                }
                item(text.t("recordsPlanned")) { hollow }
                if style == .bars {
                    item(text.t("recordsOvertime")) {
                        HStack(spacing: 1.5) {
                            Capsule().fill(OWCDesign.recordsWork).frame(width: 8, height: 4)
                            Capsule().fill(OWCDesign.recordsOvertime).frame(width: 3, height: 4)
                        }
                    }
                } else if showsHolidays {
                    item(text.t("holidayRestDay")) { solid(OWCDesign.recordsHoliday) }
                }
            }
            if style == .bars, showsHolidays || showsMakeup {
                HStack(spacing: 14) {
                    if showsHolidays {
                        item(text.t("holidayRestDay")) {
                            Image(systemName: "sun.max").fontWeight(.bold).font(.system(size: 9)).foregroundStyle(OWCDesign.recordsHoliday)
                        }
                    }
                    if showsMakeup {
                        item(text.t("holidayMakeupWorkday")) {
                            Image(systemName: "briefcase.fill").font(.system(size: 8)).foregroundStyle(OWCDesign.secondary)
                        }
                    }
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(OWCDesign.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }

    private func item<Mark: View>(_ title: String, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: 5) {
            mark()
            Text(title).lineLimit(1)
        }
    }

    @ViewBuilder
    private func solid(_ color: Color) -> some View {
        if style == .bars {
            Capsule().fill(color).frame(width: 12, height: 4)
        } else {
            Circle().fill(color).frame(width: 6, height: 6)
        }
    }

    @ViewBuilder
    private var hollow: some View {
        if style == .bars {
            Capsule().strokeBorder(OWCDesign.recordsWork, lineWidth: 1.25).opacity(0.65).frame(width: 12, height: 4)
        } else {
            Circle().strokeBorder(OWCDesign.recordsWork, lineWidth: 1).opacity(0.65).frame(width: 6, height: 6)
        }
    }
}

/// The one way into Plus on a calendar with locked days.
struct RecordsFreeWindowNote: View {
    let text: AppText
    var onUnlock: () -> Void

    var body: some View {
        Button(action: onUnlock) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                (Text(text.t("recordsFreeWindowNote")) + Text(" ")
                    + Text(text.t("recordsFreeWindowAction")).fontWeight(.semibold).foregroundStyle(OWCDesign.accent))
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(OWCDesign.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(OWCDesign.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
    }
}

// MARK: - Locked year and life

/// A soft impression of the year or life view behind the Plus card. It is
/// decoration only and never reads the user's records.
struct RecordsLockedPreviewArt: View {
    let scale: RecordsScale

    var body: some View {
        if scale == .life {
            VStack(spacing: 6) {
                ForEach(0..<8, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<10, id: \.self) { column in
                            let age = row * 10 + column
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(color(age: age))
                                .frame(height: 18)
                        }
                    }
                }
            }
            .padding(.top, 60)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 14) {
                ForEach(0..<12, id: \.self) { month in
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 3) {
                        ForEach(0..<30, id: \.self) { day in
                            Circle()
                                .fill((month * 7 + day) % 9 == 0 ? OWCDesign.recordsOvertime
                                      : day % 7 > 4 ? OWCDesign.tertiary : OWCDesign.recordsWork)
                                .frame(width: day % 7 > 4 ? 3 : 6, height: day % 7 > 4 ? 3 : 6)
                                .frame(height: 8)
                        }
                    }
                    .padding(.top, 18)
                }
            }
        }
    }

    private func color(age: Int) -> Color {
        switch age {
        case ..<6: OWCDesign.lifeChildhood
        case ..<22: OWCDesign.lifeStudy
        case ..<62: OWCDesign.lifeWork
        default: OWCDesign.lifeRetirement
        }
    }
}

/// Capability, then reassurance, then the way in, on one raised card.
struct RecordsLockedCard: View {
    let text: AppText
    var onUnlock: () -> Void

    var body: some View {
        Button(action: onUnlock) {
            VStack(spacing: 0) {
                Image(systemName: "lock.fill")
                    .font(.title3)
                    .foregroundStyle(OWCDesign.accent)
                Text(text.t("recordsLockedScale"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OWCDesign.primary)
                    .padding(.top, 8)
                Text(text.t("recordsLockedKeepsSaving"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .padding(.top, 6)
                Text(text.t("plusSeePlans"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OWCDesign.accent)
                    .padding(.top, 10)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            .frame(maxWidth: 280)
            .background(OWCDesign.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(OWCDesign.separator, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.14), radius: 16, y: 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(text.t("recordsLockedScale")). \(text.t("recordsLockedKeepsSaving"))")
        .accessibilityHint(text.t("plusSeePlans"))
    }
}

extension RecordsHolidaySummary {
    /// Each holiday on screen once, with how many of its rest days are visible.
    static func counts(_ looks: [RecordsDayLook]) -> [(String, Int)] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for look in looks {
            guard let name = look.holidayName, !name.isEmpty else { continue }
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += 1
        }
        return order.map { ($0, counts[$0] ?? 0) }
    }
}
