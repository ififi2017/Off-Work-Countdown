import SwiftUI

/// Before setup can edit shared preferences, find a returning owner's data.
struct FirstRunRecoveryView: View {
    let store: OffWorkStore
    var isExistingLocalSetup = false
    var onConfigure: (() -> Void)?
    @State private var phase: FirstRunRecoveryPhase = .checking
    @State private var backupURL: URL?
    @State private var backupFailed = false
    @State private var backupWasExported = false
    @State private var confirmsReplacement = false
    @State private var checkTask: Task<Void, Never>?
    @State private var purchaseCheckTask: Task<Void, Never>?
    @State private var cloudRequestSucceeded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        Button {
                            leaveRecovery()
                        } label: {
                            Label(
                                store.t(isExistingLocalSetup ? "cancel" : "firstRunBackToWelcome"),
                                systemImage: "chevron.backward"
                            )
                        }
                        .font(.body.weight(.medium))
                        Spacer()
                    }

                    Spacer(minLength: 8)
                    CelebratingBrandMark()
                        .frame(width: 112, height: 112)
                    Text(store.t(isExistingLocalSetup ? "firstRunRestoreTitle" : "firstRunReturningTitle"))
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    Text(store.t(bodyKey))
                        .foregroundStyle(OWCDesign.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .id(bodyKey)
                        .transition(recoveryTransition)
                    if phase == .checking || phase == .restoring {
                        ProgressView()
                            .transition(.opacity)
                    }
                    if cloudRequestSucceeded {
                        if store.plus.isAuthorized {
                            Label(store.t("firstRunPlusRestored"), systemImage: "checkmark.circle")
                                .font(.footnote)
                                .foregroundStyle(OWCDesign.secondary)
                        } else if !store.plus.hasCheckedCurrentEntitlements {
                            Text(store.t("firstRunCheckingPurchase"))
                                .font(.footnote)
                                .foregroundStyle(OWCDesign.secondary)
                        }
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
        .task { startRecovery() }
        .onDisappear {
            checkTask?.cancel()
            purchaseCheckTask?.cancel()
        }
        .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.stateEnter, value: phase)
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
        case .empty: "firstRunCloudEmpty"
        case .needsSetup: "firstRunCloudNeedsSetup"
        case .failed: "firstRunCloudUnavailable"
        case .localDataNeedsReview: "firstRunLocalDataNeedsReview"
        case .restoring: "firstRunCloudRestoring"
        }
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: 14) {
            if phase == .empty || phase == .needsSetup {
                Button(store.t("retryAction")) { startRecovery() }
                    .buttonStyle(OWCPrimaryButtonStyle())
                Button(store.t(isExistingLocalSetup ? "continue" : "firstRunContinueSetup")) {
                    continueLocally(checkedEmpty: phase == .empty)
                }
                .font(.body.weight(.medium))
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
                Button(store.t("retryAction")) { startRecovery() }
                    .buttonStyle(OWCPrimaryButtonStyle())
                if !isExistingLocalSetup {
                    Button(store.t("firstRunContinueSetup")) {
                        continueLocally(checkedEmpty: false)
                    }
                    .font(.body.weight(.medium))
                }
            }
            if isExistingLocalSetup, phase != .restoring, phase != .empty, phase != .needsSetup {
                Button(store.t("cancel"), action: leaveRecovery)
                .font(.body.weight(.medium))
            }
            if cloudRequestSucceeded, !store.plus.isAuthorized, phase != .restoring {
                Button(store.t("plusRestore")) {
                    Task { await store.plus.restore() }
                }
                .font(.footnote)
                .disabled(store.plus.restoreInFlight)
            }
        }
    }

    private func startRecovery() {
        checkTask?.cancel()
        purchaseCheckTask?.cancel()
        cloudRequestSucceeded = false
        phase = .checking
        checkTask = Task {
            let retryUntil = Date.now.addingTimeInterval(30)
            while !Task.isCancelled {
                do {
                    let found = try await store.cloudSync.checkForExistingData()
                    guard !Task.isCancelled else { return }
                    cloudRequestSucceeded = true
                    purchaseCheckTask = Task { await store.plus.checkCurrentEntitlements() }
                    guard found else {
                        phase = .empty
                        return
                    }
                    phase = .restoring
                    try await restoreDownloadedData()
                    return
                } catch FirstRunRecoveryError.localDataNeedsReview {
                    guard !Task.isCancelled else { return }
                    phase = .localDataNeedsReview
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    guard let delay = FirstRunRecoveryRetryPolicy.delay(for: error),
                          Date.now.addingTimeInterval(delay) <= retryUntil
                    else {
                        phase = .failed
                        return
                    }
                    do { try await Task.sleep(for: .seconds(delay)) }
                    catch { return }
                }
            }
        }
    }

    private func restore(allowReplacingLocalData: Bool = false) {
        phase = .restoring
        checkTask = Task {
            do {
                try await restoreDownloadedData(allowReplacingLocalData: allowReplacingLocalData)
            } catch FirstRunRecoveryError.localDataNeedsReview {
                guard !Task.isCancelled else { return }
                phase = .localDataNeedsReview
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed
            }
        }
    }

    private func restoreDownloadedData(allowReplacingLocalData: Bool = false) async throws {
        let hasPreferences = try await store.cloudSync.restoreFirstRunData(
            allowReplacingLocalData: allowReplacingLocalData
        )
        try Task.checkCancellation()
        store.finishFirstRunCloudRestore(hasPreferences: hasPreferences)
        if isExistingLocalSetup {
            dismiss()
        } else if !hasPreferences {
            phase = .needsSetup
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
        } else {
            dismiss()
            onConfigure?()
        }
    }

    private func leaveRecovery() {
        checkTask?.cancel()
        purchaseCheckTask?.cancel()
        dismiss()
    }

    private var recoveryTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: .bottom))
    }
}
