import SwiftUI

struct RecordsSyncSettingsView: View {
    let store: OffWorkStore

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
    @State private var warningFeedback = 0
    @State private var successFeedback = 0
    @State private var errorFeedback = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OWCGroupCard {
                    OWCRow(icon: "icloud", title: store.t("syncToggle"), isLast: true) {
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

                statusFooter
                    .padding(.horizontal, OWCDesign.pageInset + 20)
                    .padding(.top, 10)

                OWCGroupCard {
                    actionRow(
                        .restore,
                        icon: "arrow.clockwise.icloud",
                        title: store.t("syncRestore"),
                        subtitle: store.t("syncRestoreDetail"),
                        isLast: true
                    ) { await store.cloudSync.restore() }
                }
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.top, 20)

                OWCSectionHeader(title: store.t("syncDangerZone"))
                    .padding(.horizontal, OWCDesign.pageInset)
                    .padding(.top, 22)

                OWCGroupCard {
                    dangerRow(
                        .deleteCloud,
                        icon: "trash",
                        title: store.t("syncDeleteiCloud"),
                        subtitle: store.t("syncDeleteiCloudDetail")
                    ) { confirmsDeleteCloud = true }

                    dangerRow(
                        .deleteDevice,
                        icon: "iphone.slash",
                        title: store.t("syncRemoveDevice"),
                        subtitle: store.t("syncRemoveDeviceDetail"),
                        isLast: true
                    ) { confirmsDeleteDevice = true }
                }
                .padding(.horizontal, OWCDesign.pageInset)
            }
        }
        .background(OWCDesign.page)
        .navigationTitle(store.t("syncTitle"))
        .navigationBarTitleDisplayMode(.large)
        .owcDetailBack(title: store.t("settings"), pageTitle: store.t("syncTitle"))
        .sensoryFeedback(.warning, trigger: warningFeedback)
        .sensoryFeedback(.success, trigger: successFeedback)
        .sensoryFeedback(.error, trigger: errorFeedback)
        .alert(store.t("syncDisableTitle"), isPresented: $confirmsDisable) {
            Button(store.t("syncDisable")) {
                run(.toggle) { await store.cloudSync.disable(deleteCloud: false) }
            }
            Button(store.t("cancel"), role: .cancel) {}
        } message: {
            Text(store.t("syncDisableConfirm"))
        }
        .confirmationDialog(
            store.t("syncDeleteiCloudTitle"),
            isPresented: $confirmsDeleteCloud,
            titleVisibility: .visible
        ) {
            Button(store.t("syncDeleteiCloud"), role: .destructive) {
                runAuthorized(.deleteCloud) { await store.cloudSync.deleteAllCloud() }
            }
            Button(store.t("cancel"), role: .cancel) {}
        } message: {
            Text(store.t("syncDeleteiCloudConfirm"))
        }
        .confirmationDialog(
            store.t("syncRemoveDeviceTitle"),
            isPresented: $confirmsDeleteDevice,
            titleVisibility: .visible
        ) {
            Button(store.t("syncRemoveDevice"), role: .destructive) {
                runAuthorized(.deleteDevice) { await store.cloudSync.wipeLocalRecords() }
            }
            Button(store.t("cancel"), role: .cancel) {}
        } message: {
            Text(store.t("syncRemoveDeviceConfirm"))
        }
    }

    /// Reads the persisted flag, never the tap. Turning sync on can be refused
    /// — by the paywall, or by CloudKit — and a `@State` mirror would have left
    /// the switch sitting in a position the app never reached.
    private var syncBinding: Binding<Bool> {
        Binding(
            get: { store.records.state.sync.syncEnabled },
            set: { wantsOn in
                if wantsOn {
                    if store.plus.isAuthorized {
                        run(.toggle) { await store.cloudSync.enable(authorized: true) }
                    } else {
                        store.openPaidOrRun(.sync, action: .enableSync)
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
            if let detail = store.cloudSync.lastError, isFailing {
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
            OWCRow(icon: icon, title: title, subtitle: subtitle, isLast: isLast) {
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
            guard await store.confirmRecordsOwnerIfNeeded(reasonKey: "recordsOwnerAuthReason") else {
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
        switch store.cloudSync.status {
        case .needsNetwork, .accountChanged, .noCloudRecords, .failed:
            true
        default:
            false
        }
    }

    private var statusText: String {
        switch store.cloudSync.status {
        case .off: store.t("syncOff")
        case .idle, .syncing: store.t("syncOn")
        case .deleting: store.t("syncDeleting")
        case .deleted: store.t("syncDeleted")
        case .needsNetwork: store.t("syncNeedNetwork")
        case .noCloudRecords: store.t("syncNoCloudRecords")
        case .accountChanged: store.t("syncAccountChanged")
        // `enable` reports "plus" when the purchase is missing. Everything else
        // is a CloudKit failure, and `lastError` carries the specifics.
        case .failed(let reason): store.t(reason == "plus" ? "syncNeedsPlus" : "syncFailed")
        }
    }
}
