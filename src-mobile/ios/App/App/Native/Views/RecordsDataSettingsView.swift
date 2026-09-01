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
    let store: OffWorkStore
    @State private var showsLifeEditor = false
    @State private var importing = false
    @State private var importPreview: RecordImportReport?
    @State private var pendingImportData: Data?
    @State private var exportURL: URL?
    @State private var confirmsDeleteDevice = false
    @State private var importReport: String?
    @State private var operationError: RecordsOperationError?

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: store.t("recordsDataTitle"))
                    .padding(.top, 14)
                OWCGroupCard {
                    Button {
                        if store.plus.isAuthorized {
                            showsLifeEditor = true
                        } else {
                            store.paywallSheet = .life
                        }
                    } label: {
                        OWCRow(
                            icon: "person.crop.circle",
                            title: store.t("recordsLifeProfileRow"),
                            subtitle: store.records.state.lifeProfile == nil
                                ? store.t("recordsLifeProfileUnset")
                                : store.t("recordsLifeProfileReady"),
                            centersVertically: true
                        ) {
                            OWCDetailAccessory(text: nil)
                        }
                    }
                    .buttonStyle(OWCRowButtonStyle())

                    NavigationLink(value: AppRoute.iCloudSync) {
                        OWCRow(
                            icon: "icloud",
                            title: store.t("syncTitle"),
                            subtitle: store.recordsDataStatusLabel,
                            centersVertically: true
                        ) {
                            OWCDetailAccessory(text: nil)
                        }
                    }
                    .buttonStyle(OWCRowButtonStyle())

                    NavigationLink(value: AppRoute.recordsConflicts) {
                        OWCRow(icon: "exclamationmark.arrow.triangle.2.circlepath", title: store.t("recordsConflictCenter")) {
                            OWCDetailAccessory(
                                text: store.records.state.sync.conflicts.isEmpty
                                    ? store.t("recordsConflictNone")
                                    : store.t(
                                        "recordsConflictCount",
                                        values: ["count": "\(store.records.state.sync.conflicts.count)"]
                                    )
                            )
                        }
                    }
                    .buttonStyle(OWCRowButtonStyle())

                    NavigationLink(value: AppRoute.recordsTimeZone) {
                        OWCRow(
                            icon: "clock",
                            title: store.t("recordsTimeZone"),
                            isLast: true
                        ) {
                            OWCDetailAccessory(text: store.recordsTimeZoneLabel)
                        }
                    }
                    .buttonStyle(OWCRowButtonStyle())
                }
                .padding(.horizontal, OWCDesign.pageInset)

                OWCSectionHeader(title: store.t("recordsExport"))
                    .padding(.top, 22)
                OWCGroupCard {
                    Button { importFile() } label: {
                        OWCRow(icon: "square.and.arrow.down", title: store.t("recordsImport")) {
                            OWCDetailAccessory(text: nil)
                        }
                    }
                    .buttonStyle(OWCRowButtonStyle())

                    Button { export(includeLife: true) } label: {
                        OWCRow(icon: "square.and.arrow.up", title: store.t("recordsExportFull")) {
                            OWCDetailAccessory(text: nil)
                        }
                    }
                    .buttonStyle(OWCRowButtonStyle())

                    Button { export(includeLife: false) } label: {
                        OWCRow(icon: "square.and.arrow.up", title: store.t("recordsExportWithoutLife"), isLast: true) {
                            OWCDetailAccessory(text: nil)
                        }
                    }
                    .buttonStyle(OWCRowButtonStyle())
                }
                .padding(.horizontal, OWCDesign.pageInset)

                OWCSectionHeader(title: store.t("syncDangerZone"))
                    .padding(.top, 22)
                OWCGroupCard {
                    Button { confirmsDeleteDevice = true } label: {
                        OWCRow(
                            icon: "trash",
                            title: store.t("recordsDeleteAll"),
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
        .navigationTitle(store.t("recordsDataTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsLifeEditor) {
            LifeProfileEditView(store: store)
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
            store.t("recordsDeleteAllConfirm"),
            isPresented: $confirmsDeleteDevice,
            titleVisibility: .visible
        ) {
            Button(store.t("recordsDeleteAll"), role: .destructive) {
                Task { await wipeDevice() }
            }
            Button(store.t("cancel"), role: .cancel) {}
        }
        .alert(store.t("recordsImportPreviewTitle"), isPresented: Binding(
            get: { importPreview != nil },
            set: { if !$0 { importPreview = nil; pendingImportData = nil } }
        )) {
            Button(store.t("recordsImportApplyNew")) {
                Task { await applyImport() }
            }
            if importPreview?.conflicts.isEmpty == false {
                Button(store.t("recordsConflictCenter")) {
                    Task { await applyImport(openConflicts: true) }
                }
            }
            Button(store.t("cancel"), role: .cancel) {
                importPreview = nil
                pendingImportData = nil
            }
        } message: {
            if let importPreview {
                Text(previewMessage(importPreview))
            }
        }
        .alert(store.t("recordsImport"), isPresented: Binding(
            get: { importReport != nil },
            set: { if !$0 { importReport = nil } }
        )) {
            Button(store.t("close"), role: .cancel) { importReport = nil }
        } message: {
            Text(importReport ?? "")
        }
        .alert(store.t("recordsDataTitle"), isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button(store.t("close"), role: .cancel) { operationError = nil }
        } message: {
            Text(operationError.map { store.t($0.messageKey) } ?? "")
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
    }

    private func importFile() {
        importing = true
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else {
            if case .failure(let error) = result {
                operationError = RecordsOperationError.fileImporterFailure(error)
            }
            return
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let report = try store.previewRecordsImport(data)
            pendingImportData = data
            importPreview = report
        } catch {
            operationError = RecordsOperationError.from(
                error,
                fallback: access ? .previewFailed : .securityScopedFileUnavailable
            )
        }
    }

    private func applyImport(openConflicts: Bool = false) async {
        guard let pendingImportData else {
            operationError = .previewFailed
            return
        }
        guard await store.confirmRecordsOwnerIfNeeded(reasonKey: "recordsOwnerAuthReason") else {
            operationError = .ownerAuthenticationFailed
            return
        }
        do {
            let report = try store.records.import(pendingImportData)
            importReport = store.t("recordsImportReport", values: ["skipped": "\(report.skippedErasedTotal)"])
            importPreview = nil
            self.pendingImportData = nil
            if openConflicts, !store.settingsPath.contains(.recordsConflicts) {
                store.settingsPath.append(.recordsConflicts)
            }
        } catch {
            operationError = RecordsOperationError.from(error, fallback: .importFailed)
        }
    }

    private func export(includeLife: Bool) {
        Task {
            guard await store.confirmRecordsOwnerIfNeeded(reasonKey: "recordsOwnerAuthReason") else {
                operationError = .ownerAuthenticationFailed
                return
            }
            do {
                exportURL = try store.exportRecordsFile(includeLifeProfile: includeLife)
            } catch {
                operationError = RecordsOperationError.from(error, fallback: .exportFailed)
            }
        }
    }

    private func wipeDevice() async {
        guard await store.confirmRecordsOwnerIfNeeded(reasonKey: "recordsOwnerAuthReason") else {
            operationError = .ownerAuthenticationFailed
            return
        }
        await store.cloudSync.wipeLocalRecords()
    }

    private func previewMessage(_ report: RecordImportReport) -> String {
        let added = report.inserted.values.reduce(0, +) + report.adopted.count
        let same = report.unchanged.values.reduce(0, +)
        return [
            store.t("recordsImportAdded", values: ["count": "\(added)"]),
            store.t("recordsImportSame", values: ["count": "\(same)"]),
            store.t("recordsImportConflicts", values: ["count": "\(report.conflicts.count)"]),
            store.t("recordsImportSkipped", values: ["count": "\(report.skippedErasedTotal)"]),
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
