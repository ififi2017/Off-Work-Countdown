import SwiftUI

/// The free history boundary is enforced before SwiftUI builds rows or
/// accessibility elements. Locked history is deliberately reduced to one
/// boolean so years, dates and counts outside the window cannot leak through
/// rendering, navigation or VoiceOver.
struct RecordsAllRecordsPresentation {
    let visibleEntries: [RecordDayIndexEntry]
    let hasLockedHistory: Bool
    let years: [Int]

    init(
        entries: [RecordDayIndexEntry],
        isAuthorized: Bool,
        today: Date,
        calendar: Calendar
    ) {
        let interval = LaunchTrace.signposter.beginInterval("recordsPresentation")
        defer { LaunchTrace.signposter.endInterval("recordsPresentation", interval) }
        if isAuthorized {
            visibleEntries = entries
            hasLockedHistory = false
        } else {
            visibleEntries = entries.filter {
                RecordsAccess.freeWindowContains(dayKey: $0.dayKey, today: today, calendar: calendar)
            }
            hasLockedHistory = entries.contains {
                !RecordsAccess.freeWindowContains(dayKey: $0.dayKey, today: today, calendar: calendar)
            }
        }

        let visibleYears = Set(visibleEntries.compactMap { entry -> Int? in
            guard let date = RecordJSON.date(fromDayKey: entry.dayKey, calendar: calendar) else { return nil }
            return calendar.component(.year, from: date)
        })
        years = visibleYears.sorted(by: >)
    }

    func count(in year: Int) -> Int {
        visibleEntries.count { $0.dayKey.hasPrefix(String(year)) }
    }
}

struct RecordsAllRecordsView: View {
    let queries: RecordsQueries
    let preferences: PreferencesStore
    let text: AppText
    var focusedYear: Int?

    private var presentation: RecordsAllRecordsPresentation {
        RecordsAllRecordsPresentation(
            entries: queries.recordDayIndex(),
            isAuthorized: queries.plus.isAuthorized,
            today: .now,
            calendar: preferences.recordsCalendar
        )
    }

    var body: some View {
        let presentation = presentation
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if presentation.years.isEmpty && !presentation.hasLockedHistory {
                    OWCGroupCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(text.t("recordsEmptyTitle"))
                                .font(.body.weight(.medium))
                            Text(text.t("recordsEmptyBody"))
                                .font(.footnote)
                                .foregroundStyle(OWCDesign.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    }
                } else if !presentation.years.isEmpty {
                    OWCGroupCard {
                        ForEach(Array(presentation.years.enumerated()), id: \.element) { index, year in
                            NavigationLink(value: RecordsRoute.yearList(year)) {
                                OWCDisclosureRow(
                                    title: "\(year)",
                                    subtitle: queries.plus.isAuthorized
                                        ? text.t(
                                            "recordsMonthWorkdays",
                                            count: presentation.count(in: year)
                                        )
                                        : nil,
                                    isLast: index == presentation.years.count - 1
                                )
                            }
                            .buttonStyle(OWCRowButtonStyle())
                        }
                    }
                }
                if presentation.hasLockedHistory {
                    OWCGroupCard {
                        OWCRow(title: text.t("recordsLockedDay"), isLast: true) {
                            Image(systemName: "lock.fill")
                                .font(.footnote)
                                .foregroundStyle(OWCDesign.tertiary)
                        }
                        .accessibilityLabel(text.t("recordsLockedDay"))
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 14)
        }
        .background(OWCDesign.page)
        .navigationTitle(text.t("recordsAllRecords"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                OWCEarningsVisibilityButton(preferences: preferences, text: text)
            }
        }
    }

}

struct RecordsYearRecordsView: View {
    let queries: RecordsQueries
    let preferences: PreferencesStore
    let text: AppText
    let year: Int

    private var visibleEntries: [RecordDayIndexEntry] {
        let entries = queries.recordDayIndex()
        guard !queries.plus.isAuthorized else { return entries }
        return entries.filter {
            RecordsAccess.freeWindowContains(dayKey: $0.dayKey, today: .now, calendar: preferences.recordsCalendar)
        }
    }

    private var months: [Int] {
        let prefix = String(format: "%04d-", year)
        let found = Set(
            visibleEntries.compactMap { day -> Int? in
                guard day.dayKey.hasPrefix(prefix) else { return nil }
                let parts = day.dayKey.split(separator: "-")
                return parts.count == 3 ? Int(parts[1]) : nil
            }
        )
        return found.sorted(by: >)
    }

    var body: some View {
        let months = months
        let canReadYear = queries.plus.isAuthorized || !months.isEmpty
        Group {
            if canReadYear {
                yearContent(months: months)
            } else {
                RecordsLockedHistoryPlaceholder(text: text)
            }
        }
    }

    private func yearContent(months: [Int]) -> some View {
        OWCContentSizedScrollView {
            OWCGroupCard {
                ForEach(Array(months.enumerated()), id: \.element) { index, month in
                    NavigationLink(value: RecordsRoute.monthList(year: year, month: month)) {
                        OWCDisclosureRow(
                            title: monthTitle(month),
                            isLast: index == months.count - 1
                        )
                    }
                    .buttonStyle(OWCRowButtonStyle())
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 14)
        }
        .background(OWCDesign.page)
        .navigationTitle("\(year)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func monthTitle(_ month: Int) -> String {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = 1
        return queries.formatRecordsMonthYear(preferences.recordsCalendar.date(from: parts) ?? .now)
    }
}

struct RecordsMonthRecordsView: View {
    let queries: RecordsQueries
    let preferences: PreferencesStore
    let text: AppText
    let year: Int
    let month: Int

    private var days: [RecordDayIndexEntry] {
        let prefix = String(format: "%04d-%02d-", year, month)
        let entries = queries.recordDayIndex().filter { $0.dayKey.hasPrefix(prefix) }
        guard !queries.plus.isAuthorized else { return entries }
        return entries.filter {
            RecordsAccess.freeWindowContains(dayKey: $0.dayKey, today: .now, calendar: preferences.recordsCalendar)
        }
    }

    var body: some View {
        let days = days
        let canReadMonth = queries.plus.isAuthorized || !days.isEmpty
        Group {
            if canReadMonth {
                monthContent(days: days)
            } else {
                RecordsLockedHistoryPlaceholder(text: text)
            }
        }
    }

    private func monthContent(days: [RecordDayIndexEntry]) -> some View {
        OWCContentSizedScrollView {
            OWCGroupCard {
                ForEach(Array(days.enumerated()), id: \.element.dayKey) { index, day in
                    NavigationLink(value: RecordsRoute.day(day.dayKey)) {
                        OWCDisclosureRow(
                            title: queries.formatRecordsDayTitle(dayKey: day.dayKey),
                            isLast: index == days.count - 1
                        )
                    }
                    .buttonStyle(OWCRowButtonStyle())
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 14)
        }
        .background(OWCDesign.page)
        .navigationTitle(monthTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var monthTitle: String {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = 1
        return queries.formatRecordsMonthYear(preferences.recordsCalendar.date(from: parts) ?? .now)
    }
}
