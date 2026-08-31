import SwiftUI
import UniformTypeIdentifiers

/// Free records surface: days the user actually started or finished.
/// Charts, life view, and history edit stay behind the 006 paywall.
struct RecordsDesignView: View {
    let store: OffWorkStore
    @State private var days: [RecordedWorkDay] = []
    @State private var exportURL: URL?
    @State private var confirmsDelete = false
    @State private var confirmsQuarantine = false
    @State private var importing = false
    @State private var importReport: String?
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
                            recordsLink(.week, title: store.t("recordsWeek"), icon: "chart.bar")
                            Divider().padding(.leading, 16)
                            recordsLink(.month, title: store.t("recordsMonth"), icon: "calendar")
                            Divider().padding(.leading, 16)
                            recordsLink(.year, title: store.t("recordsYear"), icon: "chart.dots.scatter")
                            Divider().padding(.leading, 16)
                            recordsLink(.life, title: store.t("recordsLife"), icon: "circle.grid.3x3")
                            Divider().padding(.leading, 16)
                            recordsLink(.focus, title: store.t("recordsFocus"), icon: "timer", isLast: true)
                        }
                        .padding(.horizontal, OWCDesign.pageInset)
                        .padding(.top, 14)

                        if days.isEmpty {
                            emptyCard
                                .padding(.horizontal, OWCDesign.pageInset)
                                .padding(.top, 14)
                        } else {
                            OWCGroupCard {
                                ForEach(Array(days.enumerated()), id: \.element.dayKey) { index, day in
                                    if index > 0 { Divider().padding(.leading, 16) }
                                    NavigationLink(value: RecordsRoute.day(day.dayKey)) {
                                        RecordDayRow(store: store, day: day)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, OWCDesign.pageInset)
                            .padding(.top, 14)
                        }

                        OWCGroupCard {
                            Button {
                                importing = true
                            } label: {
                                settingsRow(store.t("recordsImport"), systemImage: "square.and.arrow.down")
                            }
                            Divider().padding(.leading, 16)
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
        .navigationDestination(for: RecordsRoute.self) { route in
            recordsDestination(route)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            importFile(result)
        }
        .alert(store.t("recordsImport"), isPresented: Binding(
            get: { importReport != nil },
            set: { if !$0 { importReport = nil } }
        )) {
            Button(store.t("close"), role: .cancel) { importReport = nil }
        } message: {
            Text(importReport ?? "")
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

    @ViewBuilder
    private func recordsDestination(_ route: RecordsRoute) -> some View {
        switch route {
        case .day(let dayKey):
            RecordDayDetailHost(store: store, dayKey: dayKey)
        case .week:
            gated(.charts) { RecordsChartsHomeView(store: store, period: .week) }
        case .month:
            gated(.charts) { RecordsChartsHomeView(store: store, period: .month) }
        case .year:
            gated(.charts) { RecordsChartsHomeView(store: store, period: .year) }
        case .life:
            gated(.life) { LifeView(store: store) }
        case .editDay(let dayKey):
            RecordDayEditView(store: store, dayKey: dayKey)
        case .paywall(let reason):
            PaywallView(store: store, reason: reason, showsSkip: false) {
                if !store.recordsPath.isEmpty { store.recordsPath.removeLast() }
            }
        case .focus:
            gated(.focus) { FocusDesignView(store: store) }
        }
    }

    @ViewBuilder
    private func gated<Content: View>(_ reason: PlusPaywallReason, @ViewBuilder content: () -> Content) -> some View {
        if store.plus.isAuthorized {
            content()
        } else {
            PaywallView(store: store, reason: reason, showsSkip: false) {
                if !store.recordsPath.isEmpty { store.recordsPath.removeLast() }
            }
        }
    }

    private func recordsLink(_ route: RecordsRoute, title: String, icon: String, isLast _: Bool = false) -> some View {
        NavigationLink(value: route) {
            settingsRow(title, systemImage: icon)
        }
        .buttonStyle(.plain)
    }

    private func importFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let report = try? store.records.import(data)
        else { return }
        importReport = store.t(
            "recordsImportReport",
            values: ["skipped": "\(report.skippedErasedTotal)"]
        )
        refresh()
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

