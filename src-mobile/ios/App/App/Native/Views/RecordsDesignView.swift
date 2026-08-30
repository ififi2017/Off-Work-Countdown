import SwiftUI

/// Free records surface: days the user actually started or finished.
/// Charts, life view, and history edit stay behind the 006 paywall.
struct RecordsDesignView: View {
    let store: OffWorkStore
    @State private var days: [RecordedWorkDay] = []
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
                        if days.isEmpty {
                            emptyCard
                                .padding(.horizontal, OWCDesign.pageInset)
                                .padding(.top, 14)
                        } else {
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
                        }

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

    private var emptyCard: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(store.t("recordsEmptyTitle"))
                    .font(.body.weight(.medium))
                Text(store.t("recordsEmptyBody"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .lineSpacing(3)
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
        days = store.recordedWorkDays()
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
    let day: RecordedWorkDay

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dayTitle)
                    .font(.body.weight(.medium))
                Text(timesLabel)
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .environment(\.layoutDirection, .leftToRight)
            }
            Spacer(minLength: 8)
            if let hoursLabel {
                Text(hoursLabel)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(OWCDesign.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var dayTitle: String {
        day.shiftAnchorDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private var timesLabel: String {
        let start = day.firstStart
        let stop = day.lastStop
        if let start, let stop {
            return "\(timeString(start)) – \(timeString(stop))"
        }
        if let start { return timeString(start) }
        if let stop { return timeString(stop) }
        if let overtime = day.observations.last(where: { $0.kind == .overtimeDeclared }) {
            return timeString(overtime.occurredAt)
        }
        return store.t("recordsObservedOvertime")
    }

    private var hoursLabel: String? {
        guard let start = day.firstStart, let stop = day.lastStop, stop > start else { return nil }
        return RelativeDurationFormatter.string(
            milliseconds: stop.timeIntervalSince(start) * 1_000,
            languageCode: store.languageCode
        )
    }

    private func timeString(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

private struct RecordDayDetailView: View {
    let store: OffWorkStore
    let day: RecordedWorkDay

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                OWCGroupCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(timesLabel)
                            .font(.body.weight(.medium))
                            .environment(\.layoutDirection, .leftToRight)
                        if let hoursLabel {
                            Text(hoursLabel)
                                .font(.title3.monospacedDigit())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }

                OWCGroupCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.t("recordsObservations"))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(OWCDesign.secondary)
                        ForEach(day.observations) { item in
                            Text(observationLabel(item))
                                .font(.body)
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

    private var timesLabel: String {
        let start = day.firstStart
        let stop = day.lastStop
        if let start, let stop {
            return "\(timeString(start)) – \(timeString(stop))"
        }
        if let start { return timeString(start) }
        if let stop { return timeString(stop) }
        if let overtime = day.observations.last(where: { $0.kind == .overtimeDeclared }) {
            return timeString(overtime.occurredAt)
        }
        return store.t("recordsObservedOvertime")
    }

    private var hoursLabel: String? {
        guard let start = day.firstStart, let stop = day.lastStop, stop > start else { return nil }
        return RelativeDurationFormatter.string(
            milliseconds: stop.timeIntervalSince(start) * 1_000,
            languageCode: store.languageCode
        )
    }

    private func timeString(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
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
