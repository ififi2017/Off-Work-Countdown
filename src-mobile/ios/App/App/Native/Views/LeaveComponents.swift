import SwiftUI

// Time off (3.2.2) speaks the Records language: 15 pt bold card titles,
// rounded headline numbers, orange only for leave, green only for rest,
// indigo for work.

enum LeaveStyle {
    static let title = Font.subheadline.weight(.bold)
    static let number = Font.system(.title, design: .rounded).weight(.semibold)
    static let restBand = OWCDesign.recordsHoliday.opacity(0.14)
    /// Weekend and other ordinary rest inside a break: lighter than a holiday.
    static let weekend = Color(uiColor: UIColor { traits in
        UIColor.systemGreen.resolvedColor(with: traits).withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.40 : 0.38)
    })
    static let work = OWCDesign.control
}

/// "9 days" with the number set large and rounded, the unit small.
struct LeaveHeroNumber: View {
    let full: String
    let number: String
    var color: Color = OWCDesign.primary

    var body: some View {
        var value = AttributedString(full)
        value.font = .headline
        value.foregroundColor = color
        if let range = value.range(of: number) {
            value[range].font = LeaveStyle.number
        }
        return Text(value)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Used, planned and still free, as one bar.
struct LeaveBalanceBar: View {
    let totalHalfDays: Int
    let usedHalfDays: Int
    let plannedHalfDays: Int
    var plannedColor: Color = OWCDesign.accent

    var body: some View {
        GeometryReader { proxy in
            let total = CGFloat(max(1, totalHalfDays))
            let used = proxy.size.width * CGFloat(min(usedHalfDays, totalHalfDays)) / total
            let planned = proxy.size.width * CGFloat(min(plannedHalfDays, max(0, totalHalfDays - usedHalfDays))) / total
            HStack(spacing: 2) {
                if used > 0 {
                    Rectangle().fill(Color(uiColor: .systemGray3)).frame(width: max(2, used - 1))
                }
                if planned > 0 {
                    Rectangle().fill(plannedColor).frame(width: max(2, planned - 1))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OWCDesign.control)
            .clipShape(Capsule())
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// A break as one cell per day: orange leave, green holiday, pale green
/// weekend, grey work on either side. Cell width is shared across a list, so
/// a longer break is a longer strip.
struct LeaveDayStrip: View {
    enum Kind { case leave, halfLeave, holiday, rest, work }

    let kinds: [Kind]
    let cellWidth: CGFloat

    var body: some View {
        HStack(spacing: cellWidth < 12 ? 1 : 2) {
            ForEach(Array(kinds.enumerated()), id: \.offset) { _, kind in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(color(kind))
                    .frame(width: kind == .halfLeave ? cellWidth / 2 : cellWidth, height: 8)
                    .frame(width: cellWidth, alignment: .trailing)
            }
        }
        .accessibilityHidden(true)
    }

    private static func legendItem(_ kind: Kind, _ title: String) -> some View {
        HStack(spacing: 5) {
            LeaveDayStrip(kinds: [kind], cellWidth: 12)
            Text(title)
        }
    }

    private func color(_ kind: Kind) -> Color {
        switch kind {
        case .leave, .halfLeave: OWCDesign.accent
        case .holiday: OWCDesign.recordsHoliday
        case .rest: LeaveStyle.weekend
        case .work: LeaveStyle.work
        }
    }

    static func kinds(_ proposal: LeavePlanProposal) -> [Kind] {
        let before = proposal.items.first { $0.dayNumber < proposal.firstRestDayNumber }
        let after = proposal.items.last { $0.dayNumber > proposal.lastRestDayNumber }
        var result: [Kind] = [before.map { $0.portion == .whole ? .leave : .halfLeave } ?? .work]
        for (offset, kind) in proposal.dayKinds.enumerated() {
            let day = proposal.firstRestDayNumber + offset
            if let item = proposal.items.first(where: { $0.dayNumber == day }) {
                result.append(item.portion == .whole ? .leave : .halfLeave)
                continue
            }
            switch kind {
            case .leave: result.append(.leave)
            case .holiday: result.append(.holiday)
            case .rest: result.append(.rest)
            }
        }
        result.append(after.map { $0.portion == .whole ? .leave : .halfLeave } ?? .work)
        return result
    }

    static func legend(_ text: AppText) -> some View {
        HStack(spacing: 12) {
            legendItem(.leave, text.t("leaveDayLeave"))
            legendItem(.holiday, text.t("leaveDayHoliday"))
            legendItem(.rest, text.t("leaveLegendWeekend"))
            legendItem(.work, text.t("leaveLegendWork"))
        }
        .font(.caption2)
        .foregroundStyle(OWCDesign.secondary)
    }
}

/// The break on a few weeks of calendar: leave days carry an orange
/// suitcase, half days a half circle, holidays a green sun, and one green
/// band spans the whole break with its length written once.
struct LeaveBreakCalendar: View {
    let shifts: ShiftSessionStore
    let proposal: LeavePlanProposal
    @ScaledMetric(relativeTo: .subheadline) private var numberSize: CGFloat = 30

    private var text: AppText { shifts.text }
    private var calendar: Calendar { shifts.preferences.recordsCalendar }

    private var weeks: [[Int]] {
        let first = proposal.items.map(\.dayNumber).min().map { min($0, proposal.firstRestDayNumber) }
            ?? proposal.firstRestDayNumber
        let last = proposal.items.map(\.dayNumber).max().map { max($0, proposal.lastRestDayNumber) }
            ?? proposal.lastRestDayNumber
        let start = first - 1
        let end = last + 1
        // Day number 0 is 1970-01-01, a Thursday (weekday 5).
        let weekday = ((start % 7) + 7 + 4) % 7 + 1
        let lead = (weekday - calendar.firstWeekday + 7) % 7
        var rows: [[Int]] = []
        var day = start - lead
        while day <= end {
            rows.append(Array(day..<(day + 7)))
            day += 7
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { column in
                    Text(weekdaySymbol(column))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(OWCDesign.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)
            .accessibilityHidden(true)
            let rows = weeks
            let labelRow = labelRowIndex(rows)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index == 0 || month(row[0]) != month(rows[index - 1][0]) {
                    Text(shifts.leaveDayLabel(index == 0 ? row[0] : row[0], template: "yMMMM"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(OWCDesign.secondary)
                        .padding(.leading, 4)
                        .padding(.top, index == 0 ? 0 : 8)
                        .padding(.bottom, 2)
                }
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        ForEach(row, id: \.self) { day in cell(day) }
                    }
                    band(row, showsLabel: index == labelRow)
                }
                .frame(height: 66)
            }
            legend
                .padding(.top, 10)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func month(_ day: Int) -> Int {
        let civil = CivilZone.civilDate(dayNumber: day)
        return civil.year * 12 + civil.month
    }

    private func cell(_ day: Int) -> some View {
        let item = proposal.items.first { $0.dayNumber == day }
        let inBreak = (proposal.firstRestDayNumber...proposal.lastRestDayNumber).contains(day)
        let kind = inBreak ? proposal.dayKinds[day - proposal.firstRestDayNumber] : nil
        let weekday = ((day % 7) + 7 + 4) % 7 + 1
        let isWeekend = weekday == 1 || weekday == 7
        return VStack(spacing: 2) {
            Text(text.formatCount(CivilZone.civilDate(dayNumber: day).day))
                .font(.callout.weight(inBreak || item != nil ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(inBreak || item != nil ? OWCDesign.primary : isWeekend ? OWCDesign.secondary : OWCDesign.primary)
                .frame(width: numberSize, height: numberSize)
            Group {
                if let item {
                    Image(systemName: item.portion == .whole ? "suitcase.fill" : "circle.lefthalf.filled")
                        .foregroundStyle(OWCDesign.accent)
                } else if kind == .leave {
                    Image(systemName: "suitcase.fill").foregroundStyle(OWCDesign.accent)
                } else if kind == .holiday {
                    Image(systemName: "sun.max").fontWeight(.bold).foregroundStyle(OWCDesign.recordsHoliday)
                } else {
                    Color.clear
                }
            }
            .font(.system(size: 11))
            .frame(height: 12)
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([
            shifts.leaveDayLabel(day),
            item.map { text.t($0.portion == .whole ? "leaveDayLeave" : "leaveDayHalf") },
            kind == .holiday ? text.t("leaveDayHoliday") : nil,
        ].compactMap { $0 }.joined(separator: ", "))
    }

    private func breakColumns(_ row: [Int]) -> [Int] {
        row.indices.filter { (proposal.firstRestDayNumber...proposal.lastRestDayNumber).contains(row[$0]) }
    }

    /// The break's length is written on its widest week (the first, on a
    /// tie), so a break that starts on the last day of a week is not left
    /// with a one-day band too short for the label.
    private func labelRowIndex(_ rows: [[Int]]) -> Int? {
        var best: (index: Int, width: Int)?
        for (index, row) in rows.enumerated() {
            let width = breakColumns(row).count
            if width > (best?.width ?? 0) { best = (index, width) }
        }
        return best?.index
    }

    @ViewBuilder
    private func band(_ row: [Int], showsLabel: Bool) -> some View {
        let inside = breakColumns(row)
        if let first = inside.first, let last = inside.last {
            GeometryReader { proxy in
                let column = proxy.size.width / 7
                Text(showsLabel ? text.t("leaveDaysOff", count: proposal.fullRestDays) : "")
                    .font(.system(size: 9.5, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(OWCDesign.recordsHoliday)
                    .padding(.horizontal, 4)
                    .frame(width: column * CGFloat(last - first + 1) - 4, height: 13, alignment: .leading)
                    .background(LeaveStyle.restBand, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .offset(x: column * CGFloat(first) + 2, y: 50)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            if proposal.items.contains(where: { $0.portion == .whole }) || proposal.dayKinds.contains(.leave) {
                Label { Text(text.t("leaveDayLeave")) } icon: {
                    Image(systemName: "suitcase.fill").foregroundStyle(OWCDesign.accent)
                }
            }
            if proposal.items.contains(where: { $0.portion != .whole }) {
                Label { Text(text.t("leaveDayHalf")) } icon: {
                    Image(systemName: "circle.lefthalf.filled").foregroundStyle(OWCDesign.accent)
                }
            }
            if proposal.dayKinds.contains(.holiday) {
                Label { Text(text.t("leaveDayHoliday")) } icon: {
                    Image(systemName: "sun.max").foregroundStyle(OWCDesign.recordsHoliday)
                }
            }
            Label { Text(text.t("leaveLegendBreak")) } icon: {
                RoundedRectangle(cornerRadius: 2).fill(LeaveStyle.restBand).frame(width: 14, height: 7)
            }
        }
        .labelStyle(LeaveCompactLabelStyle())
        .font(.caption2)
        .foregroundStyle(OWCDesign.secondary)
        .frame(maxWidth: .infinity)
    }

    private func weekdaySymbol(_ column: Int) -> String {
        var localized = calendar
        localized.locale = shifts.preferences.locale
        return localized.veryShortStandaloneWeekdaySymbols[(column + calendar.firstWeekday - 1) % 7]
    }
}

struct LeaveCompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 10))
            configuration.title
        }
    }
}

/// Last shift before the break, the break, and the first shift back.
struct LeaveBridgeCard: View {
    let shifts: ShiftSessionStore
    let proposal: LeavePlanProposal

    var body: some View {
        let text = shifts.text
        HStack(spacing: 10) {
            end(titleKey: "leaveLastShiftEnds", ms: proposal.lastShiftEndAtMs)
            VStack(spacing: 2) {
                Image(systemName: "sun.max").font(.title3)
                Text(text.formatDays(Double(proposal.fullRestDays)))
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(OWCDesign.recordsHoliday)
            .frame(width: 56)
            .accessibilityElement(children: .combine)
            end(titleKey: "leaveNextShiftStarts", ms: proposal.nextShiftStartAtMs)
        }
    }

    private func end(titleKey: String, ms: Double?) -> some View {
        let zone = CivilZone(timeZone: shifts.preferences.recordsTimeZone)
        return VStack(alignment: .leading, spacing: 4) {
            Text(shifts.text.t(titleKey))
                .font(.caption)
                .foregroundStyle(OWCDesign.secondary)
            Text(ms.map { shifts.leaveTime($0) } ?? "—")
                .font(.headline.monospacedDigit())
                .foregroundStyle(OWCDesign.primary)
            if let ms {
                Text(shifts.leaveDayLabel(zone.civil(ms).dayNumber))
                    .font(.caption)
                    .foregroundStyle(OWCDesign.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(OWCDesign.control, in: RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A white card with an optional 15 pt bold title and a quiet trailing note.
struct LeaveCard<Content: View>: View {
    var title: String?
    var note: String?
    @ViewBuilder var content: Content

    var body: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 0) {
                if let title {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title)
                            .font(LeaveStyle.title)
                            .foregroundStyle(OWCDesign.primary)
                        Spacer(minLength: 8)
                        if let note {
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(OWCDesign.secondary)
                        }
                    }
                    .padding(.bottom, 10)
                    .accessibilityAddTraits(.isHeader)
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
    }
}

extension ShiftSessionStore {
    /// The public holiday a break is built around, if any.
    func leaveHolidayName(_ proposal: LeavePlanProposal) -> String? {
        var region = leavePlannerConfiguration().extendedSchedule?.holidayRegionIdentifier
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "ios.native.qaLeavePlanner") {
            region = UserDefaults.standard.string(forKey: "ios.native.qaLeaveRegion") ?? "CN"
        }
        #endif
        for (offset, kind) in proposal.dayKinds.enumerated() where kind == .holiday {
            let key = ExtendedScheduleEditing.dayKey(dayNumber: proposal.firstRestDayNumber + offset)
            if let annotation = HolidayDayAnnotation.make(dayKey: key, region: region, language: preferences.languageCode),
               !annotation.name.isEmpty, !annotation.isMakeupWorkday {
                return annotation.name
            }
        }
        return nil
    }

    func leaveRange(_ proposal: LeavePlanProposal, template: String = "MMMd") -> String {
        OWCText.ltrRange(leaveDayLabel(proposal.firstRestDayNumber, template: template),
                         leaveDayLabel(proposal.lastRestDayNumber, template: template))
    }

    func leaveCost(_ proposal: LeavePlanProposal) -> String {
        proposal.costHalfDays == 0 ? text.t("leaveNoLeaveNeeded")
            : text.t("leaveAskFor", values: ["days": text.formatDays(Double(proposal.costHalfDays) / 2)])
    }
}
