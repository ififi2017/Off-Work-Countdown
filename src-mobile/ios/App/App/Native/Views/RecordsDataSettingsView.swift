import SwiftUI
import UniformTypeIdentifiers

enum RecordsOperationError: Identifiable, Equatable {
    case securityScopedFileUnavailable
    case readFailed
    case invalidDocument
    case unsupportedVersion
    case previewFailed
    case importFailed
    case exportFailed
    case ownerAuthenticationFailed

    var id: String { String(describing: self) }

    var messageKey: String {
        switch self {
        case .securityScopedFileUnavailable:
            return "recordsOperationFileUnavailable"
        case .readFailed:
            return "recordsOperationReadFailed"
        case .invalidDocument:
            return "recordsOperationInvalidDocument"
        case .unsupportedVersion:
            return "recordsOperationUnsupportedVersion"
        case .previewFailed:
            return "recordsOperationPreviewFailed"
        case .importFailed:
            return "recordsOperationImportFailed"
        case .exportFailed:
            return "recordsOperationExportFailed"
        case .ownerAuthenticationFailed:
            return "recordsOperationOwnerAuthenticationFailed"
        }
    }

    static func from(_ error: any Error, fallback: RecordsOperationError) -> RecordsOperationError {
        if let error = error as? RecordJSONError {
            switch error {
            case .invalidDocument: return .invalidDocument
            case .unknownSchemaVersion: return .unsupportedVersion
            }
        }
        return fallback
    }

    static func fileImporterFailure(_ error: any Error) -> RecordsOperationError? {
        let nsError = error as NSError
        guard !(nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.Code.userCancelled.rawValue) else {
            return nil
        }
        return from(error, fallback: .readFailed)
    }

    static func exportShareFailure(
        completed: Bool,
        activityWasSelected: Bool,
        error: (any Error)?
    ) -> RecordsOperationError? {
        if error != nil { return .exportFailed }
        // Cancelling the sheet has neither an activity nor an error.
        guard completed || !activityWasSelected else { return .exportFailed }
        return nil
    }

#if DEBUG
    static func debugScenario(_ raw: String) -> Self? {
        switch raw {
        case "invalidDocument": .invalidDocument
        case "unsupportedVersion": .unsupportedVersion
        case "readFailed": .readFailed
        case "importFailed": .importFailed
        case "exportFailed": .exportFailed
        default: nil
        }
    }
#endif
}

struct RecordsDataSettingsView: View {
    @Environment(SceneState.self) private var scene
    let actions: RecordsActions
    let recovery: RecoveryStore
    let life: LifeSummaryModel
    @State private var showsLifeEditor = false
    @State private var importing = false
    @State private var importPreview: RecordImportReport?
    @State private var pendingImportData: Data?
    @State private var exportURL: URL?
    @State private var confirmsDeleteDevice = false
    @State private var importReport: String?
    @State private var operationError: RecordsOperationError?
    @State private var importPreviewInProgress = false
    @State private var importPreviewID: UUID?
    @State private var importPreviewTask: Task<Void, Never>?

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: actions.text.t("recordsDataTitle"))
                    .padding(.top, 14)
                OWCGroupCard {
                    Button {
                        if actions.plus.isAuthorized {
                            showsLifeEditor = true
                        } else {
                            scene.paywallSheet = .life
                        }
                    } label: {
                        OWCRow(
                            icon: "person.crop.circle",
                            title: actions.text.t("recordsLifeProfileRow"),
                            subtitle: actions.records.state.lifeProfile == nil
                                ? actions.text.t("recordsLifeProfileUnset")
                                : actions.text.t("recordsLifeProfileReady"),
                            centersVertically: true
                        ) {
                            OWCDetailAccessory(text: nil)
                        }
                    }
                    .buttonStyle(OWCRowButtonStyle())

                    NavigationLink(value: AppRoute.iCloudSync) {
                        OWCRow(
                            icon: "icloud",
                            title: actions.text.t("syncTitle"),
                            subtitle: recovery.recordsDataStatusLabel(using: actions.text),
                            centersVertically: true
                        ) {
                            OWCDetailAccessory(text: nil)
                        }
                    }
                    .buttonStyle(OWCRowButtonStyle())

                    if !actions.records.state.sync.conflicts.isEmpty {
                        NavigationLink(value: AppRoute.recordsConflicts) {
                            OWCRow(icon: "exclamationmark.arrow.triangle.2.circlepath", title: actions.text.t("recordsConflictCenter")) {
                                OWCDetailAccessory(
                                    text: actions.text.t(
                                        "recordsConflictCount",
                                        values: ["count": "\(actions.records.state.sync.conflicts.count)"]
                                    )
                                )
                            }
                        }
                        .buttonStyle(OWCRowButtonStyle())
                    }

                    NavigationLink(value: AppRoute.recordsTimeZone) {
                        OWCRow(
                            icon: "clock",
                            title: actions.text.t("recordsTimeZone"),
                            isLast: true
                        ) {
                            OWCDetailAccessory(text: actions.preferences.recordsTimeZoneLabel)
                        }
                    }
                    .buttonStyle(OWCRowButtonStyle())
                }
                .padding(.horizontal, OWCDesign.pageInset)

                OWCSectionHeader(title: actions.text.t("recordsExport"))
                    .padding(.top, 22)
                OWCGroupCard {
                    Button { importFile() } label: {
                        OWCRow(icon: "square.and.arrow.down", title: actions.text.t("recordsImport")) {
                            if importPreviewInProgress {
                                ProgressView().accessibilityLabel(actions.text.t("recordsImport"))
                            } else {
                                OWCDetailAccessory(text: nil)
                            }
                        }
                    }
                    .buttonStyle(OWCRowButtonStyle())

                    Button { export(includeLife: true) } label: {
                        OWCRow(icon: "square.and.arrow.up", title: actions.text.t("recordsExportFull")) {
                            OWCDetailAccessory(text: nil)
                        }
                    }
                    .buttonStyle(OWCRowButtonStyle())

                    Button { export(includeLife: false) } label: {
                        OWCRow(icon: "square.and.arrow.up", title: actions.text.t("recordsExportWithoutLife"), isLast: true) {
                            OWCDetailAccessory(text: nil)
                        }
                    }
                    .buttonStyle(OWCRowButtonStyle())
                }
                .padding(.horizontal, OWCDesign.pageInset)

                OWCSectionHeader(title: actions.text.t("syncDangerZone"))
                    .padding(.top, 22)
                OWCGroupCard {
                    Button { confirmsDeleteDevice = true } label: {
                        OWCRow(
                            icon: "trash",
                            title: actions.text.t("recordsDeleteAll"),
                            isLast: true,
                            isDestructive: true
                        )
                    }
                    .buttonStyle(OWCRowButtonStyle())
                }
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.bottom, 24)
            }
        }
        .background(OWCDesign.page)
        .navigationTitle(actions.text.t("recordsDataTitle"))
        .navigationBarTitleDisplayMode(.large)
        .owcDetailBack(title: actions.text.t("settings"), pageTitle: actions.text.t("recordsDataTitle"))
        .sheet(isPresented: $showsLifeEditor) {
            LifeProfileEditView(life: life, actions: actions, preferences: actions.preferences, text: actions.text)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .sheet(item: Binding(
            get: { exportURL.map(RecordsExportItem.init) },
            set: { exportURL = $0?.url }
        )) { item in
            RecordsExportSheet(url: item.url) { completed, activityWasSelected, error in
                exportURL = nil
                operationError = RecordsOperationError.exportShareFailure(
                    completed: completed,
                    activityWasSelected: activityWasSelected,
                    error: error
                )
            }
        }
        .confirmationDialog(
            actions.text.t("recordsDeleteAllConfirm"),
            isPresented: $confirmsDeleteDevice,
            titleVisibility: .visible
        ) {
            Button(actions.text.t("recordsDeleteAll"), role: .destructive) {
                Task { await wipeDevice() }
            }
            Button(actions.text.t("cancel"), role: .cancel) {}
        }
        .alert(actions.text.t("recordsImportPreviewTitle"), isPresented: Binding(
            get: { importPreview != nil },
            set: { if !$0 { importPreview = nil; pendingImportData = nil } }
        )) {
            Button(actions.text.t("recordsImportApplyNew")) {
                Task { await applyImport() }
            }
            if importPreview?.conflicts.isEmpty == false {
                Button(actions.text.t("recordsConflictCenter")) {
                    Task { await applyImport(openConflicts: true) }
                }
            }
            Button(actions.text.t("cancel"), role: .cancel) {
                importPreview = nil
                pendingImportData = nil
            }
        } message: {
            if let importPreview {
                Text(previewMessage(importPreview))
            }
        }
        .alert(actions.text.t("recordsImport"), isPresented: Binding(
            get: { importReport != nil },
            set: { if !$0 { importReport = nil } }
        )) {
            Button(actions.text.t("close"), role: .cancel) { importReport = nil }
        } message: {
            Text(importReport ?? "")
        }
        .alert(actions.text.t("recordsDataTitle"), isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button(actions.text.t("close"), role: .cancel) { operationError = nil }
        } message: {
            Text(operationError.map { actions.text.t($0.messageKey) } ?? "")
        }
        .onAppear {
#if DEBUG
            let key = "ios.native.qaRecordsOperationError"
            if let raw = UserDefaults.standard.string(forKey: key) {
                UserDefaults.standard.removeObject(forKey: key)
                operationError = RecordsOperationError.debugScenario(raw)
            }
#endif
        }
        .onDisappear { cancelImportPreview() }
    }

    private func importFile() {
        cancelImportPreview()
        importing = true
    }

    private func handleImport(_ result: Result<URL, Error>) {
        cancelImportPreview()
        guard case .success(let url) = result else {
            if case .failure(let error) = result {
                operationError = RecordsOperationError.fileImporterFailure(error)
            }
            return
        }
        let previewID = UUID()
        importPreviewID = previewID
        importPreviewInProgress = true
        importPreviewTask = Task {
            do {
                let data = try await RecordArchive.readSecurityScopedFile(url)
                try Task.checkCancellation()
                guard importPreviewID == previewID else { return }
                let report = try await actions.previewRecordsImport(data)
                try Task.checkCancellation()
                guard importPreviewID == previewID else { return }
                pendingImportData = data
                importPreview = report
                importPreviewInProgress = false
                importPreviewID = nil
                importPreviewTask = nil
            } catch is CancellationError {
            } catch RecordArchiveReadError.securityScopedFileUnavailable {
                guard importPreviewID == previewID else { return }
                finishImportPreview(with: .securityScopedFileUnavailable)
            } catch RecordArchiveReadError.readFailed {
                guard importPreviewID == previewID else { return }
                finishImportPreview(with: .readFailed)
            } catch {
                guard importPreviewID == previewID else { return }
                finishImportPreview(with: RecordsOperationError.from(error, fallback: .previewFailed))
            }
        }
    }

    private func cancelImportPreview() {
        importPreviewTask?.cancel()
        importPreviewTask = nil
        importPreviewID = nil
        importPreviewInProgress = false
        pendingImportData = nil
        importPreview = nil
    }

    private func finishImportPreview(with error: RecordsOperationError) {
        importPreviewInProgress = false
        importPreviewID = nil
        importPreviewTask = nil
        operationError = error
    }

    private func applyImport(openConflicts: Bool = false) async {
        guard let pendingImportData else {
            operationError = .previewFailed
            return
        }
        guard await actions.confirmRecordsOwnerIfNeeded(reasonKey: "recordsOwnerAuthReason") else {
            operationError = .ownerAuthenticationFailed
            return
        }
        do {
            let report = try await actions.records.import(pendingImportData)
            importReport = actions.text.t("recordsImportReport", values: ["skipped": "\(report.skippedErasedTotal)"])
            importPreview = nil
            self.pendingImportData = nil
            if openConflicts, !scene.settingsPath.contains(.recordsConflicts) {
                scene.settingsPath.append(.recordsConflicts)
            }
        } catch {
            operationError = RecordsOperationError.from(error, fallback: .importFailed)
        }
    }

    private func export(includeLife: Bool) {
        Task {
            guard await actions.confirmRecordsOwnerIfNeeded(reasonKey: "recordsOwnerAuthReason") else {
                operationError = .ownerAuthenticationFailed
                return
            }
            do {
                exportURL = try await actions.exportRecordsFile(includeLifeProfile: includeLife)
            } catch {
                operationError = RecordsOperationError.from(error, fallback: .exportFailed)
            }
        }
    }

    private func wipeDevice() async {
        guard await actions.confirmRecordsOwnerIfNeeded(reasonKey: "recordsOwnerAuthReason") else {
            operationError = .ownerAuthenticationFailed
            return
        }
        await recovery.cloudSync.wipeLocalRecords()
    }

    private func previewMessage(_ report: RecordImportReport) -> String {
        let added = report.inserted.values.reduce(0, +) + report.adopted.count
        let same = report.unchanged.values.reduce(0, +)
        return [
            actions.text.t("recordsImportAdded", values: ["count": "\(added)"]),
            actions.text.t("recordsImportSame", values: ["count": "\(same)"]),
            actions.text.t("recordsImportConflicts", values: ["count": "\(report.conflicts.count)"]),
            actions.text.t("recordsImportSkipped", values: ["count": "\(report.skippedErasedTotal)"]),
        ].joined(separator: "\n")
    }
}

struct RecordsExportItem: Identifiable {
    var id: String { url.path }
    let url: URL
}

struct RecordsExportSheet: UIViewControllerRepresentable {
    let url: URL
    let completion: @MainActor (_ completed: Bool, _ activityWasSelected: Bool, _ error: (any Error)?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { activityType, completed, _, error in
            Task { @MainActor in
                completion(completed, activityType != nil, error)
            }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
