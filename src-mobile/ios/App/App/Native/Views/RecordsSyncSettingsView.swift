import SwiftUI

struct RecordsSyncSettingsView: View {
    let store: OffWorkStore
    @State private var confirmsDisable = false

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 14) {
                OWCGroupCard {
                    Text(statusText)
                        .font(.body)
                        .padding(16)
                }

                OWCGroupCard {
                    Button(store.t("syncEnable")) {
                        store.openPaidOrRun(.sync) {
                            Task { await store.cloudSync.enable(authorized: store.plus.isAuthorized) }
                        }
                    }
                    Divider().padding(.leading, 16)
                    Button(store.t("syncRestore")) {
                        Task { await store.cloudSync.restore() }
                    }
                    Divider().padding(.leading, 16)
                    Button(store.t("syncDisable")) {
                        confirmsDisable = true
                    }
                    Divider().padding(.leading, 16)
                    Button(role: .destructive) {
                        Task { await store.cloudSync.deleteAllCloud() }
                    } label: {
                        Text(store.t("syncDeleteiCloud"))
                    }
                    Divider().padding(.leading, 16)
                    Button(role: .destructive) {
                        store.records.deleteAllLocalData()
                    } label: {
                        Text(store.t("syncRemoveDevice"))
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .background(OWCDesign.page)
        .navigationTitle(store.t("syncTitle"))
        .navigationBarTitleDisplayMode(.large)
        .owcDetailBack(title: store.t("settings"), pageTitle: store.t("syncTitle"))
        .confirmationDialog(store.t("syncDisable"), isPresented: $confirmsDisable) {
            Button(store.t("syncDisable")) {
                Task { await store.cloudSync.disable(deleteCloud: false) }
            }
            Button(store.t("syncDeleteiCloud"), role: .destructive) {
                Task { await store.cloudSync.disable(deleteCloud: true) }
            }
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
        case .failed: store.t("plusSyncLocked")
        }
    }
}
