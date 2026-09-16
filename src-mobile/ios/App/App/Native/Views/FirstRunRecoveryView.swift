import SwiftUI

/// Before setup can edit shared preferences, find a returning owner's data.
struct FirstRunRecoveryView: View {
    let recovery: RecoveryStore
    let actions: RecordsActions
    @Environment(SceneState.self) private var scene
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
                                actions.text.t(isExistingLocalSetup ? "cancel" : "firstRunBackToWelcome"),
                                systemImage: "chevron.backward"
                            )
                        }
                        .font(.body.weight(.medium))
                        Spacer()
                    }

                    Spacer(minLength: 8)
                    CelebratingBrandMark()
                        .frame(width: 112, height: 112)
                    Text(actions.text.t(isExistingLocalSetup ? "firstRunRestoreTitle" : "firstRunReturningTitle"))
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    Text(actions.text.t(bodyKey))
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
                        if recovery.plus.isAuthorized {
                            Label(actions.text.t("firstRunPlusRestored"), systemImage: "checkmark.circle")
                                .font(.footnote)
                                .foregroundStyle(OWCDesign.secondary)
                        } else if !recovery.plus.hasCheckedCurrentEntitlements {
                            Text(actions.text.t("firstRunCheckingPurchase"))
                                .font(.footnote)
                                .foregroundStyle(OWCDesign.secondary)
                        }
                    }
                    Spacer(minLength: 24)
                    recoveryButtons
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
        .alert(actions.text.t("recordsOperationExportFailed"), isPresented: $backupFailed) {
            Button(actions.text.t("okAction"), role: .cancel) {}
        }
        .confirmationDialog(actions.text.t("firstRunReplaceConfirm"), isPresented: $confirmsReplacement) {
            Button(actions.text.t("firstRunReplaceWithCloud"), role: .destructive) {
                restore(allowReplacingLocalData: true)
            }
            Button(actions.text.t("cancel"), role: .cancel) {}
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

    @ViewBuilder private var recoveryButtons: some View {
        VStack(spacing: 14) {
            if phase == .empty || phase == .needsSetup {
                Button(actions.text.t("retryAction")) { startRecovery() }
                    .buttonStyle(OWCPrimaryButtonStyle())
                Button(actions.text.t(isExistingLocalSetup ? "continue" : "firstRunContinueSetup")) {
                    continueLocally(checkedEmpty: phase == .empty)
                }
                .font(.body.weight(.medium))
            } else if phase == .localDataNeedsReview {
                Button(actions.text.t("recordsExportFull")) {
                    Task {
                        do { backupURL = try await actions.exportRecordsFile() }
                        catch { backupFailed = true }
                    }
                }
                .buttonStyle(OWCPrimaryButtonStyle())
                if backupWasExported {
                    Button(actions.text.t("firstRunReplaceWithCloud")) { confirmsReplacement = true }
                        .font(.body.weight(.medium))
                }
            } else if phase == .failed {
                Button(actions.text.t("retryAction")) { startRecovery() }
                    .buttonStyle(OWCPrimaryButtonStyle())
                if !isExistingLocalSetup {
                    Button(actions.text.t("firstRunContinueSetup")) {
                        continueLocally(checkedEmpty: false)
                    }
                    .font(.body.weight(.medium))
                }
            }
            if isExistingLocalSetup, phase != .restoring, phase != .empty, phase != .needsSetup {
                Button(actions.text.t("cancel"), action: leaveRecovery)
                .font(.body.weight(.medium))
            }
            if cloudRequestSucceeded, !recovery.plus.isAuthorized, phase != .restoring {
                Button(actions.text.t("plusRestore")) {
                    Task { await recovery.plus.restore() }
                }
                .font(.footnote)
                .disabled(recovery.plus.restoreInFlight)
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
                    let found = try await recovery.cloudSync.checkForExistingData()
                    guard !Task.isCancelled else { return }
                    cloudRequestSucceeded = true
                    purchaseCheckTask = Task { await recovery.plus.checkCurrentEntitlements() }
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
        let hasPreferences = try await recovery.cloudSync.restoreFirstRunData(
            allowReplacingLocalData: allowReplacingLocalData
        )
        try Task.checkCancellation()
        recovery.finishFirstRunCloudRestore(hasPreferences: hasPreferences)
        if isExistingLocalSetup {
            scene.showsFirstRunCloudChoice = false
            dismiss()
        } else if !hasPreferences {
            phase = .needsSetup
        }
    }

    private func continueLocally(checkedEmpty: Bool) {
        checkTask?.cancel()
        recovery.continueFirstRunLocally()
        if isExistingLocalSetup {
            scene.showsFirstRunCloudChoice = false
            if checkedEmpty {
                Task {
                    if await recovery.confirmEmptyCloudAndEnableSync() == .needsDataReview {
                        scene.showsFirstRunCloudChoice = true
                    }
                }
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
