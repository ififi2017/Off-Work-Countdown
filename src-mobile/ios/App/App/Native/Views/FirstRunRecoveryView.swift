import SwiftUI

/// Before setup can edit shared preferences, find a returning owner's data.
struct FirstRunRecoveryView: View {
    let store: OffWorkStore
    var isExistingLocalSetup = false
    @State private var phase: FirstRunRecoveryPhase = .checking
    @State private var backupURL: URL?
    @State private var backupFailed = false
    @State private var backupWasExported = false
    @State private var confirmsReplacement = false
    @State private var checkTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    Spacer(minLength: 24)
                    CelebratingBrandMark()
                        .frame(width: 112, height: 112)
                    Text(store.t("firstRunRestoreTitle"))
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    Text(store.t(bodyKey))
                        .foregroundStyle(OWCDesign.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if phase == .checking || phase == .restoring { ProgressView() }
                    if store.plus.isAuthorized {
                        Label(store.t("firstRunPlusRestored"), systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(OWCDesign.secondary)
                    } else if !store.plus.hasCheckedCurrentEntitlements {
                        Text(store.t("firstRunCheckingPurchase"))
                            .font(.footnote)
                            .foregroundStyle(OWCDesign.secondary)
                    }
                    Spacer(minLength: 24)
                    actions
                }
                .frame(maxWidth: 520)
                .padding(24)
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height)
            }
        }
        .background(OWCDesign.page)
        .task { startCheck() }
        .onDisappear { checkTask?.cancel() }
        .sheet(item: Binding(
            get: { backupURL.map(RecordsExportItem.init) },
            set: { backupURL = $0?.url }
        )) { item in
            RecordsExportSheet(url: item.url) { completed, _, error in
                backupURL = nil
                backupWasExported = completed && error == nil
            }
        }
        .alert(store.t("recordsOperationExportFailed"), isPresented: $backupFailed) {
            Button(store.t("ok"), role: .cancel) {}
        }
        .confirmationDialog(store.t("firstRunReplaceConfirm"), isPresented: $confirmsReplacement) {
            Button(store.t("firstRunReplaceWithCloud"), role: .destructive) {
                restore(allowReplacingLocalData: true)
            }
            Button(store.t("cancel"), role: .cancel) {}
        }
    }

    private var bodyKey: String {
        switch phase {
        case .checking: "firstRunCheckingCloud"
        case .found: "firstRunCloudFound"
        case .empty: "firstRunCloudEmpty"
        case .failed: "firstRunCloudUnavailable"
        case .localDataNeedsReview: "firstRunLocalDataNeedsReview"
        case .restoring: "firstRunCloudRestoring"
        }
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: 14) {
            if phase == .found {
                Button(store.t("syncRestore")) { restore() }
                    .buttonStyle(OWCPrimaryButtonStyle())
            } else if phase == .empty {
                Button(store.t("continue")) { continueLocally(checkedEmpty: true) }
                    .buttonStyle(OWCPrimaryButtonStyle())
            } else if phase == .localDataNeedsReview {
                Button(store.t("recordsExportFull")) {
                    do { backupURL = try store.exportRecordsFile() }
                    catch { backupFailed = true }
                }
                .buttonStyle(OWCPrimaryButtonStyle())
                if backupWasExported {
                    Button(store.t("firstRunReplaceWithCloud")) { confirmsReplacement = true }
                        .font(.body.weight(.medium))
                }
            } else if phase == .failed {
                Button(store.t("retryAction")) { startCheck() }
                    .buttonStyle(OWCPrimaryButtonStyle())
            }
            if phase != .restoring && phase != .empty {
                Button(store.t(isExistingLocalSetup ? "cancel" : "firstRunContinueOffline")) {
                    if isExistingLocalSetup { dismiss() }
                    else { continueLocally(checkedEmpty: false) }
                }
                .font(.body.weight(.medium))
            }
            if !store.plus.isAuthorized && phase != .restoring {
                Button(store.t("plusRestore")) {
                    Task { await store.plus.restore() }
                }
                .font(.footnote)
                .disabled(store.plus.restoreInFlight)
            }
        }
    }

    private func startCheck() {
        checkTask?.cancel()
        phase = .checking
        checkTask = Task {
            do {
                let found = try await store.cloudSync.checkForExistingData()
                guard !Task.isCancelled else { return }
                phase = found ? .found : .empty
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed
            }
        }
    }

    private func restore(allowReplacingLocalData: Bool = false) {
        phase = .restoring
        checkTask = Task {
            do {
                await store.plus.checkCurrentEntitlements()
                let hasPreferences = try await store.cloudSync.restoreFirstRunData(authorized: store.plus.isAuthorized, allowReplacingLocalData: allowReplacingLocalData)
                guard !Task.isCancelled else { return }
                store.finishFirstRunCloudRestore(hasPreferences: hasPreferences)
                if isExistingLocalSetup { dismiss() }
            } catch FirstRunRecoveryError.localDataNeedsReview {
                guard !Task.isCancelled else { return }
                phase = .localDataNeedsReview
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed
            }
        }
    }

    private func continueLocally(checkedEmpty: Bool) {
        checkTask?.cancel()
        store.continueFirstRunLocally(cloudCheckWasEmpty: checkedEmpty)
        if isExistingLocalSetup {
            store.showsFirstRunCloudChoice = false
            if checkedEmpty {
                Task { await store.confirmEmptyCloudAndEnableSync() }
            }
            dismiss()
        }
    }
}
