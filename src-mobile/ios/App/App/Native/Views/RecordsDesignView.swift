import SwiftUI

/// Free P1 surface: a read-only year of conclusions plus export / delete.
/// Charts, life view, and history edit stay behind the 006 paywall.
struct RecordsDesignView: View {
    let store: OffWorkStore
    @State private var days: [DayResolution] = []
    @State private var exportURL: URL?
    @State private var confirmsDelete = false

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OWCDesign.page)
        .navigationTitle("")
        .navigationDestination(for: String.self) { dayKey in
            if let day = days.first(where: { $0.dayKey == dayKey }) {
                RecordDayDetailView(store: store, day: day)
            }
        }
        .onAppear(perform: refresh)
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
    }

    private func refresh() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let from = calendar.date(from: DateComponents(year: calendar.component(.year, from: today), month: 1, day: 1))
            ?? today
        let through = calendar.date(byAdding: .day, value: 14, to: today) ?? today
        days = store.resolvedDays(from: from, through: through).reversed()
        exportURL = try? store.exportRecordsFile()
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
