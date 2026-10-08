import SwiftUI

/// A complete month, with the selected proposal drawn over it. Neighbouring
/// dates stay neutral: this preview does not infer work from weekdays.
struct LeavePlanCalendar: View {
    let shifts: ShiftSessionStore
    let proposal: LeavePlanProposal
    var showsEstimatedLabel = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var monthIndex = 0
    @State private var revealed = false
    @State private var holidayDetails: SelectedHoliday?
    @State private var gridWidth: CGFloat = 0
    @ScaledMetric(relativeTo: .caption) private var cellHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .subheadline) private var numberHeight: CGFloat = 20
    @ScaledMetric(relativeTo: .caption2) private var captionHeight: CGFloat = 14

    private var cellSide: CGFloat { max(cellHeight, numberHeight + captionHeight + 6, gridWidth / 7) }
    private var text: AppText { shifts.text }
    private var calendar: Calendar { shifts.preferences.recordsCalendar }
    private var months: [Int] { LeavePlanCalendarPage.months(for: proposal) }
    private var activeMonth: Int { min(monthIndex, months.count - 1) }
    private var page: LeavePlanCalendarPage {
        LeavePlanCalendarPage(containing: months[activeMonth], firstWeekday: calendar.firstWeekday)
    }
    private var proposalID: String { "\(proposal.firstRestDayNumber):\(proposal.lastRestDayNumber)" }
    private var revealID: String { "\(proposalID):\(page.firstDayNumber)" }

    private struct SelectedHoliday: Identifiable {
        let day: Int
        let annotation: HolidayDayAnnotation
        var id: Int { day }
    }

    private enum Mark: CaseIterable {
        case rest, holiday, leave, halfLeave

        var symbol: String {
            switch self {
            case .rest: "moon.zzz"
            case .holiday: "flag"
            case .leave: "suitcase.fill"
            case .halfLeave: "circle.lefthalf.filled"
            }
        }
        var titleKey: String {
            switch self {
            case .rest: "leaveDayRest"
            case .holiday: "leaveDayHoliday"
            case .leave: "leaveDayLeave"
            case .halfLeave: "leaveDayHalf"
            }
        }
        var isLeave: Bool { self == .leave || self == .halfLeave }
    }

    private func mark(_ day: Int) -> Mark? {
        if let item = proposal.items.first(where: { $0.dayNumber == day }) {
            return item.portion == .whole ? .leave : .halfLeave
        }
        let offset = day - proposal.firstRestDayNumber
        guard proposal.dayKinds.indices.contains(offset) else { return nil }
        switch proposal.dayKinds[offset] {
        case .holiday: return .holiday
        case .leave: return .leave
        case .rest: return .rest
        }
    }

    var body: some View {
        let region = holidayRegion
        VStack(spacing: 10) {
            HStack {
                Text(shifts.leaveDayLabel(page.firstDayNumber, template: "yMMMM"))
                    .font(.headline)
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                if months.count > 1 {
                    monthButton(-1, titleKey: "extendedPreviousMonth", symbol: "chevron.backward")
                    monthButton(1, titleKey: "extendedNextMonth", symbol: "chevron.forward")
                }
            }
            .frame(minHeight: 44)
            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        Text(weekdaySymbol(column))
                            .font(.caption2)
                            .foregroundStyle(OWCDesign.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<6, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { column in
                            cell(page.days[row * 7 + column], region: region)
                        }
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
            .id(page.firstDayNumber)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
            ForEach((showsEstimatedLabel ? proposal.caveats : []).compactMap { caveat -> Int? in
                if case .holidaysEstimated(let year) = caveat { return year }
                return nil
            }.sorted(), id: \.self) { year in
                Text(text.t("leaveEstimatedHolidaysYear", values: ["year": text.formatYear(year)]))
                    .font(.caption)
                    .foregroundStyle(OWCDesign.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { legends }
                VStack(alignment: .leading, spacing: 6) { legends }
            }
            .font(.caption2)
            .foregroundStyle(OWCDesign.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $holidayDetails) { selection in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(selection.annotation.name.isEmpty ? text.t("holidayRestDay") : selection.annotation.name)
                            .font(.title2.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        Text(text.t(selection.annotation.isMakeupWorkday ? "holidayMakeupWorkday" : "holidayRestDay"))
                            .foregroundStyle(OWCDesign.secondary)
                        if selection.annotation.isEstimated {
                            let year = CivilZone.civilDate(dayNumber: selection.day).year
                            Text(text.t("holidayEstimatedYearWarning", values: ["year": text.formatYear(year)]))
                                .font(.subheadline).foregroundStyle(OWCDesign.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(OWCDesign.pageInset)
                }
                .navigationTitle(shifts.leaveDayLabel(selection.day, template: "yMMMd"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(text.t("close")) { holidayDetails = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: proposalID) { monthIndex = 0 }
        .task(id: revealID) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { revealed = false }
            // Commit the starting state, then bridge the leave dates in the
            // same staggered spring as the welcome-page rest demo.
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(30))
            }
            guard !Task.isCancelled else { return }
            revealed = true
        }
    }

    private var holidayRegion: String? {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "ios.native.qaLeavePlanner") {
            return UserDefaults.standard.string(forKey: "ios.native.qaLeaveRegion") ?? "CN"
        }
        #endif
        return shifts.leavePlannerConfiguration().extendedSchedule?.holidayRegionIdentifier
    }

    private func monthButton(_ delta: Int, titleKey: String, symbol: String) -> some View {
        Button {
            withAnimation(reduceMotion ? OWCMotion.reduced : OWCMotion.navigation) {
                monthIndex = activeMonth + delta
            }
        } label: {
            Image(systemName: symbol).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(OWCDesign.accent)
        .accessibilityLabel(text.t(titleKey))
        .disabled(!months.indices.contains(activeMonth + delta))
    }

    private func weekdaySymbol(_ column: Int) -> String {
        var localized = calendar
        localized.locale = shifts.preferences.locale
        return localized.veryShortStandaloneWeekdaySymbols[(column + calendar.firstWeekday - 1) % 7]
    }

    private func cell(_ day: Int, region: String?) -> some View {
        let mark = mark(day)
        let holiday = annotation(day, region: region)
        let inMonth = page.contains(day)
        let inBreak = (proposal.firstRestDayNumber...proposal.lastRestDayNumber).contains(day)
        let first = day == proposal.firstRestDayNumber
        let last = day == proposal.lastRestDayNumber
        let delayIndex = max(0, day - LeavePlanCalendarPage.coverage(of: proposal).lowerBound)
        let content = VStack(spacing: 2) {
            Text(text.formatCount(CivilZone.civilDate(dayNumber: day).day))
                .font(.subheadline.monospacedDigit().weight(mark == nil ? .regular : .semibold))
                .foregroundStyle(mark != nil || inMonth ? OWCDesign.primary : OWCDesign.tertiary)
                .frame(height: numberHeight)
            Group {
                if let holiday {
                    HolidayDayCaption(annotation: holiday, text: text)
                } else if let mark {
                    Image(systemName: mark.symbol)
                        .foregroundStyle(mark.isLeave ? OWCDesign.accent : OWCDesign.secondary)
                        .scaleEffect(revealed || reduceMotion ? 1 : 0.72)
                        .opacity(revealed ? 1 : 0)
                } else {
                    Color.clear
                }
            }
            .font(.caption2)
            .frame(height: captionHeight)
        }
        .frame(maxWidth: .infinity)
        .frame(height: cellSide)
        .background {
            if inBreak {
                UnevenRoundedRectangle(
                    topLeadingRadius: first ? 10 : 0, bottomLeadingRadius: first ? 10 : 0,
                    bottomTrailingRadius: last ? 10 : 0, topTrailingRadius: last ? 10 : 0
                )
                .fill(OWCDesign.accent.opacity(revealed ? 0.08 : 0))
            }
            if let mark, mark.isLeave {
                RoundedRectangle(cornerRadius: 8)
                    .fill(OWCDesign.accent.opacity(revealed ? 0.18 : 0))
                    .padding(2)
                    .scaleEffect(revealed || reduceMotion ? 1 : 0.86)
            }
        }
        .overlay(alignment: .topTrailing) {
            if holiday != nil, let mark, mark.isLeave {
                Image(systemName: mark.symbol).font(.system(size: 8))
                    .foregroundStyle(OWCDesign.accent).padding(2)
            }
        }
        .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.leaveCalendarDay(delayIndex), value: revealed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([shifts.leaveDayLabel(day), holiday?.accessibilityLabel(text: text), mark.map { text.t($0.titleKey) }].compactMap { $0 }.joined(separator: ", "))
        return Group {
            if let holiday {
                Button { holidayDetails = SelectedHoliday(day: day, annotation: holiday) } label: {
                    content.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("leave-holiday-\(day)")
            } else {
                content
            }
        }
    }

    private func annotation(_ day: Int, region: String?) -> HolidayDayAnnotation? {
        HolidayDayAnnotation.make(dayKey: ExtendedScheduleEditing.dayKey(dayNumber: day),
                                 region: region, language: shifts.preferences.languageCode)
    }

    @ViewBuilder private var legends: some View {
        ForEach(Mark.allCases.filter { kind in
            page.days.contains {
                mark($0) == kind && (kind.isLeave || annotation($0, region: holidayRegion) == nil)
            }
        }, id: \.self) { kind in
            Label(text.t(kind.titleKey), systemImage: kind.symbol)
                .foregroundStyle(kind.isLeave ? OWCDesign.accent : OWCDesign.secondary)
        }
    }
}
