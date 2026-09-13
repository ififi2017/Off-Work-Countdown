import SwiftUI

struct RecordsSyncSettingsView: View {
    @Environment(SceneState.self) private var scene
    let recovery: RecoveryStore
    let actions: RecordsActions

    /// One lock for the whole page. Every one of these actions talks to
    /// CloudKit, and two of them delete; letting a second tap start while the
    /// first is in flight is how "delete from iCloud" raced "restore".
    private enum Action: Equatable {
        case toggle
        case restore
        case deleteCloud
        case deleteDevice
    }

    @State private var running: Action?
    @State private var confirmsDisable = false
    @State private var confirmsDeleteCloud = false
    @State private var confirmsDeleteDevice = false
    @State private var confirmsCloudReset = false
    @State private var warningFeedback = 0
    @State private var successFeedback = 0
    @State private var errorFeedback = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OWCGroupCard {
                    OWCRow(icon: "icloud", title: actions.text.t("syncToggle"), isLast: true) {
                        if running == .toggle {
                            ProgressView()
                        } else {
                            Toggle("", isOn: syncBinding)
                                .labelsHidden()
                                .disabled(running != nil)
                        }
                    }
                }
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.top, 14)

                Text(actions.text.t("syncPrivacyDetail"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, OWCDesign.pageInset + 20)
                    .padding(.top, 10)

                statusFooter
                    .padding(.horizontal, OWCDesign.pageInset + 20)
                    .padding(.top, 10)

                OWCGroupCard {
                    actionRow(
                        .restore,
                        icon: "arrow.clockwise.icloud",
                        title: actions.text.t("syncRestore"),
                        subtitle: actions.text.t("syncRestoreDetail"),
                        isLast: true
                    ) { if await recovery.restoreCloudSyncFromSettings() == .needsDataReview {
                        scene.showsFirstRunCloudChoice = true
                    } }
                }
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.top, 20)

                OWCSectionHeader(title: actions.text.t("syncDangerZone"))
                    .padding(.horizontal, OWCDesign.pageInset)
                    .padding(.top, 22)

                OWCGroupCard {
                    dangerRow(
                        .deleteCloud,
                        icon: "trash",
                        title: actions.text.t("syncDeleteiCloud"),
                        subtitle: actions.text.t("syncDeleteiCloudDetail")
                    ) { confirmsDeleteCloud = true }

                    dangerRow(
                        .deleteDevice,
                        icon: "iphone.slash",
                        title: actions.text.t("syncRemoveDevice"),
                        subtitle: actions.text.t("syncRemoveDeviceDetail"),
                        isLast: true
                    ) { confirmsDeleteDevice = true }
                }
                .padding(.horizontal, OWCDesign.pageInset)
            }
        }
        .background(OWCDesign.page)
        .sheet(isPresented: Binding(
            get: { scene.showsFirstRunCloudChoice },
            set: { scene.showsFirstRunCloudChoice = $0 }
        )) {
            FirstRunRecoveryView(recovery: recovery, actions: actions, isExistingLocalSetup: true)
        }
        // Another device deleted the cloud copy while this one still held work
        // CloudKit never received. The wipe follows the contract, but not
        // before the user has had the chance to export what only lives here.
        .onChange(of: recovery.cloudSync.higherFenceNeedsReview, initial: true) { _, needsReview in
            if needsReview {
                warningFeedback += 1
                confirmsCloudReset = true
            }
        }
        .confirmationDialog(
            actions.text.t("firstRunLocalDataNeedsReview"),
            isPresented: $confirmsCloudReset,
            titleVisibility: .visible
        ) {
            Button(actions.text.t("firstRunReplaceWithCloud"), role: .destructive) {
                run(.toggle) { await recovery.cloudSync.adoptPendingHigherFence() }
            }
            Button(actions.text.t("cancel"), role: .cancel) {
                run(.toggle) { await recovery.cloudSync.keepLocalWorkAfterCloudReset() }
            }
        }
        .navigationTitle(actions.text.t("syncTitle"))
        .navigationBarTitleDisplayMode(.large)
        .owcDetailBack(title: actions.text.t("settings"), pageTitle: actions.text.t("syncTitle"))
        .sensoryFeedback(.warning, trigger: warningFeedback)
        .sensoryFeedback(.success, trigger: successFeedback)
        .sensoryFeedback(.error, trigger: errorFeedback)
        .alert(actions.text.t("syncDisableTitle"), isPresented: $confirmsDisable) {
            Button(actions.text.t("syncDisable")) {
                run(.toggle) { await recovery.cloudSync.disable(deleteCloud: false) }
            }
            Button(actions.text.t("cancel"), role: .cancel) {}
        } message: {
            Text(actions.text.t("syncDisableConfirm"))
        }
        .confirmationDialog(
            actions.text.t("syncDeleteiCloudTitle"),
            isPresented: $confirmsDeleteCloud,
            titleVisibility: .visible
        ) {
            Button(actions.text.t("syncDeleteiCloud"), role: .destructive) {
                runAuthorized(.deleteCloud) { await recovery.cloudSync.deleteAllCloud() }
            }
            Button(actions.text.t("cancel"), role: .cancel) {}
        } message: {
            Text(actions.text.t("syncDeleteiCloudConfirm"))
        }
        .confirmationDialog(
            actions.text.t("syncRemoveDeviceTitle"),
            isPresented: $confirmsDeleteDevice,
            titleVisibility: .visible
        ) {
            Button(actions.text.t("syncRemoveDevice"), role: .destructive) {
                runAuthorized(.deleteDevice) { await recovery.cloudSync.wipeLocalRecords() }
            }
            Button(actions.text.t("cancel"), role: .cancel) {}
        } message: {
            Text(actions.text.t("syncRemoveDeviceConfirm"))
        }
    }

    /// Reads the persisted flag, never the tap. Turning sync on can be refused
    /// — by the paywall, or by CloudKit — and a `@State` mirror would have left
    /// the switch sitting in a position the app never reached.
    private var syncBinding: Binding<Bool> {
        Binding(
            get: { recovery.records.state.sync.syncEnabled },
            set: { wantsOn in
                if wantsOn {
                    if recovery.plus.isAuthorized {
                        run(.toggle) { await scene.enableCloudSync(using: recovery) }
                    } else {
                        scene.requestEnableCloudSync(using: recovery)
                    }
                } else {
                    warningFeedback += 1
                    confirmsDisable = true
                }
            }
        )
    }

    @ViewBuilder
    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(statusText)
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = recovery.cloudSync.lastError, isFailing {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.stateEnter, value: statusText)
    }

    private func actionRow(
        _ action: Action,
        icon: String,
        title: String,
        subtitle: String,
        isLast: Bool = false,
        perform: @escaping () async -> Void
    ) -> some View {
        Button {
            run(action) { await perform() }
        } label: {
            OWCRow(
                icon: icon,
                title: title,
                subtitle: subtitle,
                isLast: isLast,
                centersVertically: true
            ) {
                if running == action { ProgressView() }
            }
        }
        .buttonStyle(OWCRowButtonStyle())
        .disabled(running != nil)
    }

    private func dangerRow(
        _ action: Action,
        icon: String,
        title: String,
        subtitle: String,
        isLast: Bool = false,
        perform: @escaping () -> Void
    ) -> some View {
        Button {
            warningFeedback += 1
            perform()
        } label: {
            OWCRow(
                icon: icon,
                title: title,
                subtitle: subtitle,
                isLast: isLast,
                centersVertically: true,
                isDestructive: true
            ) {
                if running == action { ProgressView() }
            }
        }
        .buttonStyle(OWCRowButtonStyle())
        .disabled(running != nil)
    }

    private func run(_ action: Action, _ work: @escaping () async -> Void) {
        guard running == nil else { return }
        running = action
        Task {
            await work()
            running = nil
            if isFailing {
                errorFeedback += 1
            } else {
                successFeedback += 1
            }
        }
    }

    private func runAuthorized(_ action: Action, _ work: @escaping () async -> Void) {
        guard running == nil else { return }
        running = action
        Task {
            guard await actions.confirmRecordsOwnerIfNeeded(reasonKey: "recordsOwnerAuthReason") else {
                running = nil
                return
            }
            await work()
            running = nil
            if isFailing {
                errorFeedback += 1
            } else {
                successFeedback += 1
            }
        }
    }

    private var isFailing: Bool {
        switch recovery.cloudSync.status {
        case .needsNetwork, .accountChanged, .noCloudRecords, .failed:
            true
        default:
            false
        }
    }

    private var statusText: String {
        // Transport status and the persisted opt-in are intentionally stored
        // separately. Never claim syncing when the durable source of truth is
        // off, even if an interrupted CloudKit callback left a stale idle
        // status behind.
        if !recovery.records.state.sync.syncEnabled {
            switch recovery.cloudSync.status {
            case .accountChanged: return actions.text.t("syncAccountChanged")
            case .needsNetwork: return actions.text.t("syncNeedNetwork")
            case .noCloudRecords: return actions.text.t("syncNoCloudRecords")
            case .failed(let reason): return actions.text.t(syncFailureKey(reason))
            case .deleted: return actions.text.t("syncDeleted")
            default: return actions.text.t("syncOff")
            }
        }

        return switch recovery.cloudSync.status {
        case .off: actions.text.t("syncOff")
        case .idle, .syncing: actions.text.t("syncOn")
        case .deleting: actions.text.t("syncDeleting")
        case .deleted: actions.text.t("syncDeleted")
        case .needsNetwork: actions.text.t("syncNeedNetwork")
        case .noCloudRecords: actions.text.t("syncNoCloudRecords")
        case .accountChanged: actions.text.t("syncAccountChanged")
        // `enable` reports "plus" when the purchase is missing. Everything else
        // is a CloudKit failure, and `lastError` carries the specifics.
        case .failed(let reason): actions.text.t(syncFailureKey(reason))
        }
    }

    private func syncFailureKey(_ reason: String) -> String {
        switch reason {
        case "plus": "syncNeedsPlus"
        case RecordsCloudSync.localDataNeedsReviewReason: "firstRunLocalDataNeedsReview"
        default: "syncFailed"
        }
    }
}
