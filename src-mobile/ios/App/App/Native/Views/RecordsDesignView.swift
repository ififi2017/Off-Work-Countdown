import SwiftUI

/// Free P1 surface: a read-only year of conclusions plus export / delete.
/// Charts, life view, and history edit stay behind the 006 paywall.
struct RecordsDesignView: View {
    let store: OffWorkStore
    @State private var days: [DayResolution] = []
    @State private var exportURL: URL?
    @State private var confirmsDelete = false
    @State private var confirmsQuarantine = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(store.t("recordsTitle"))
                .font(.largeTitle.bold())
                .tracking(-0.85)
                .padding(.horizontal, OWCDesign.contentInset)
                .padding(.top, 14)
                .padding(.bottom, 4)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if let banner = store.records.archiveBanner {
                        archiveBannerCard(banner)
                            .padding(.horizontal, OWCDesign.pageInset)
                            .padding(.top, 14)
                            .padding(.bottom, banner == .damaged ? 24 : 0)
                    }

                    if store.records.archiveBanner != .damaged {
                        OWCGroupCard {
                            ForEach(Array(days.enumerated()), id: \.element.dayKey) { index, day in
                                if index > 0 { Divider().padding(.leading, 16) }
                                NavigationLink(value: day.dayKey) {
                                    RecordDayRow(store: store, day: day)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, OWCDesign.pageInset)
                        .padding(.top, 14)

                        OWCGroupCard {
                            if let exportURL {
                                ShareLink(item: exportURL) {
                                    settingsRow(store.t("recordsExport"), systemImage: "square.and.arrow.up")
                                }
                            } else {
                                settingsRow(store.t("recordsExport"), systemImage: "square.and.arrow.up")
                                    .foregroundStyle(OWCDesign.tertiary)
                            }
                            Divider().padding(.leading, 16)
                            Button(role: .destructive) {
                                confirmsDelete = true
                            } label: {
                                settingsRow(store.t("recordsDeleteAll"), systemImage: "trash")
                            }
                        }
                        .padding(.horizontal, OWCDesign.pageInset)
                        .padding(.top, 14)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OWCDesign.page)
        .navigationTitle("")
        .navigationDestination(for: String.self) { dayKey in
            if let day = days.first(where: { $0.dayKey == dayKey }) {
                RecordDayDetailView(store: store, day: day)
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: store.selectedTab) { _, tab in
            if tab == .records { refresh() }
        }
        .onChange(of: store.records.state) { _, _ in
            refresh()
        }
        .onChange(of: store.records.persistenceError) { _, _ in
            refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refresh()
        }
        .confirmationDialog(
            store.t("recordsDeleteAllConfirm"),
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button(store.t("recordsDeleteAll"), role: .destructive) {
                store.records.deleteAllLocalData()
                refresh()
            }
        }
        .confirmationDialog(
            store.t("recordsArchiveQuarantineConfirm"),
            isPresented: $confirmsQuarantine,
            titleVisibility: .visible
        ) {
            Button(store.t("recordsArchiveQuarantine")) {
                do {
                    try store.records.quarantineCorruptedArchive()
                    refresh()
                } catch {
                    refresh()
                }
            }
        }
    }

    private func archiveBannerCard(_ banner: RecordsArchiveBanner) -> some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(store.t(banner == .saveFailed ? "recordsArchiveSaveFailedTitle" : "recordsArchiveDamagedTitle"))
                    .font(.body.weight(.medium))
                Text(store.t(banner == .saveFailed ? "recordsArchiveSaveFailedBody" : "recordsArchiveDamagedBody"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                if banner == .damaged {
                    Button(store.t("recordsArchiveQuarantine")) {
                        confirmsQuarantine = true
                    }
                    .font(.body.weight(.semibold))
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private func refresh() {
        if store.records.archiveBanner == .damaged {
            days = []
            exportURL = nil
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = store.recordsTimeZone
        // The seeded career period starts in 2000 so it can cover any later
        // day. That is not user history — using it here would expand ~26 years
        // on every visit. Only authored rows may pull the window earlier than
        // 1 January of this year.
        let earliest = (
            store.records.state.overrides.map(\.shiftAnchorDate)
                + store.records.state.exceptions.map(\.date)
                + store.records.state.observations.map(\.shiftAnchorDate)
                + (store.records.state.lifeProfile?.workStartedOn.map { [$0] } ?? [])
        ).min()
        let (from, through) = Self.recordsYearBounds(for: Date(), earliest: earliest, calendar: calendar)
        days = store.resolvedDays(from: from, through: through).reversed()
        exportURL = try? store.exportRecordsFile()
    }

    static func recordsYearBounds(
        for date: Date,
        earliest: Date? = nil,
        calendar: Calendar
    ) -> (from: Date, through: Date) {
        let year = calendar.component(.year, from: date)
        let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
            ?? calendar.startOfDay(for: date)
        let through = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? startOfYear
        let from = earliest.map { min(startOfYear, calendar.startOfDay(for: $0)) } ?? startOfYear
        return (from, through)
    }

    private func settingsRow(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
            Text(title)
            Spacer()
        }
        .font(.body)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

private struct RecordDayRow: View {
    let store: OffWorkStore
    let day: DayResolution

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dayTitle)
                    .font(.body.weight(.medium))
                Text(store.t(sourceKey))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
            }
            Spacer(minLength: 8)
            Text(hoursLabel)
                .font(.body.monospacedDigit())
                .foregroundStyle(day.isScheduledWorkday ? OWCDesign.primary : OWCDesign.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var dayTitle: String {
        day.shiftAnchorDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private var sourceKey: String {
        switch day.layer {
        case .override: "recordsSourceOverride"
        case .calendarException: "recordsSourceException"
        case .schedule: "recordsSourceSchedule"
        case .none: "recordsSourceNone"
        }
    }

    private var hoursLabel: String {
        if !day.isScheduledWorkday { return store.t("recordsRestDay") }
        let ms = day.segments.reduce(0) { $0 + ($1.endAtMs - $1.startAtMs) }
        return RelativeDurationFormatter.string(milliseconds: ms, languageCode: store.languageCode)
    }
}

private struct RecordDayDetailView: View {
    let store: OffWorkStore
    let day: DayResolution

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                OWCGroupCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.t(sourceKey))
                            .font(.body.weight(.medium))
                        Text(hoursLabel)
                            .font(.title3.monospacedDigit())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }

                OWCGroupCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.t("recordsObservations"))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(OWCDesign.secondary)
                        if observations.isEmpty {
                            Text(store.t("recordsNoObservations"))
                                .font(.body)
                                .foregroundStyle(OWCDesign.tertiary)
                        } else {
                            ForEach(observations) { item in
                                Text(observationLabel(item))
                                    .font(.body)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .background(OWCDesign.page)
        .navigationTitle(day.shiftAnchorDate.formatted(.dateTime.month(.abbreviated).day()))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var observations: [WorkObservation] {
        store.observations(on: day.shiftAnchorDate)
    }

    private var sourceKey: String {
        switch day.layer {
        case .override: "recordsSourceOverride"
        case .calendarException: "recordsSourceException"
        case .schedule: "recordsSourceSchedule"
        case .none: "recordsSourceNone"
        }
    }

    private var hoursLabel: String {
        if !day.isScheduledWorkday { return store.t("recordsRestDay") }
        let ms = day.segments.reduce(0) { $0 + ($1.endAtMs - $1.startAtMs) }
        return RelativeDurationFormatter.string(milliseconds: ms, languageCode: store.languageCode)
    }

    private func observationLabel(_ item: WorkObservation) -> String {
        let time = item.occurredAt.formatted(date: .omitted, time: .shortened)
        let kind: String
        switch item.kind {
        case .timerSurfaceFirstSeen: kind = store.t("recordsObservedFirstSeen")
        case .countdownStarted: kind = store.t("recordsObservedStarted")
        case .countdownStopped: kind = store.t("recordsObservedStopped")
        case .overtimeDeclared: kind = store.t("recordsObservedOvertime")
        }
        return "\(time) · \(kind)"
    }
}
