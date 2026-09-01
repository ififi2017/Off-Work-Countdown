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
    let store: OffWorkStore
    var focusedYear: Int?

    private var presentation: RecordsAllRecordsPresentation {
        RecordsAllRecordsPresentation(
            entries: store.recordDayIndex(),
            isAuthorized: store.plus.isAuthorized,
            today: .now,
            calendar: store.recordsCalendar
        )
    }

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if presentation.years.isEmpty && !presentation.hasLockedHistory {
                    OWCGroupCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.t("recordsEmptyTitle"))
                                .font(.body.weight(.medium))
                            Text(store.t("recordsEmptyBody"))
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
                                OWCRow(
                                    title: "\(year)",
                                    subtitle: store.plus.isAuthorized
                                        ? store.t(
                                            "recordsMonthWorkdays",
                                            values: ["count": "\(presentation.count(in: year))"]
                                        )
                                        : nil,
                                    isLast: index == presentation.years.count - 1
                                ) {
                                    OWCDetailAccessory(text: nil)
                                }
                            }
                            .buttonStyle(OWCRowButtonStyle())
                        }
                    }
                }
                if presentation.hasLockedHistory {
                    OWCGroupCard {
                        OWCRow(title: store.t("recordsLockedDay"), isLast: true) {
                            Image(systemName: "lock.fill")
                                .font(.footnote)
                                .foregroundStyle(OWCDesign.tertiary)
                        }
                        .accessibilityLabel(store.t("recordsLockedDay"))
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 14)
        }
        .background(OWCDesign.page)
        .navigationTitle(store.t("recordsAllRecords"))
        .navigationBarTitleDisplayMode(.inline)
    }

}

struct RecordsYearRecordsView: View {
    let store: OffWorkStore
    let year: Int

    private var visibleEntries: [RecordDayIndexEntry] {
        let entries = store.recordDayIndex()
        guard !store.plus.isAuthorized else { return entries }
        return entries.filter {
            RecordsAccess.freeWindowContains(dayKey: $0.dayKey, today: .now, calendar: store.recordsCalendar)
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
        if canReadYear {
            yearContent
        } else {
            RecordsLockedHistoryPlaceholder(store: store)
        }
    }

    private var canReadYear: Bool {
        store.plus.isAuthorized || !months.isEmpty
    }

    private var yearContent: some View {
        OWCContentSizedScrollView {
            OWCGroupCard {
                ForEach(Array(months.enumerated()), id: \.element) { index, month in
                    NavigationLink(value: RecordsRoute.monthList(year: year, month: month)) {
                        OWCRow(
                            title: monthTitle(month),
                            isLast: index == months.count - 1
                        ) {
                            OWCDetailAccessory(text: nil)
                        }
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
        return store.formatRecordsMonthYear(store.recordsCalendar.date(from: parts) ?? .now)
    }
}

struct RecordsMonthRecordsView: View {
    let store: OffWorkStore
    let year: Int
    let month: Int

    private var days: [RecordDayIndexEntry] {
        let prefix = String(format: "%04d-%02d-", year, month)
        let entries = store.recordDayIndex().filter { $0.dayKey.hasPrefix(prefix) }
        guard !store.plus.isAuthorized else { return entries }
        return entries.filter {
            RecordsAccess.freeWindowContains(dayKey: $0.dayKey, today: .now, calendar: store.recordsCalendar)
        }
    }

    var body: some View {
        if canReadMonth {
            monthContent
        } else {
            RecordsLockedHistoryPlaceholder(store: store)
        }
    }

    private var canReadMonth: Bool {
        store.plus.isAuthorized || !days.isEmpty
    }

    private var monthContent: some View {
        OWCContentSizedScrollView {
            OWCGroupCard {
                ForEach(Array(days.enumerated()), id: \.element.dayKey) { index, day in
                    NavigationLink(value: RecordsRoute.day(day.dayKey)) {
                        OWCRow(
                            title: store.formatRecordsDayTitle(dayKey: day.dayKey),
                            isLast: index == days.count - 1
                        ) {
                            OWCDetailAccessory(text: nil)
                        }
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
        return store.formatRecordsMonthYear(store.recordsCalendar.date(from: parts) ?? .now)
    }
}
