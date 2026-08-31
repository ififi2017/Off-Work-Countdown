#if DEBUG
import SwiftUI

struct DebugMenuView: View {
    let store: OffWorkStore

    @Environment(LiveActivityService.self) private var liveActivities
    @Environment(\.dismiss) private var dismiss
    @State private var isStartingLiveActivity = false
    @State private var resultTitle = ""
    @State private var resultMessage = ""
    @State private var showsResult = false
    @State private var actionFeedback = 0
    @State private var pendingScenario: DebugTimerScenario?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: scheduleReset) {
                        Label(store.t("debugResetNextLaunch"), systemImage: "arrow.counterclockwise")
                    }
                    .foregroundStyle(.red)
                } footer: {
                    Text(store.t("debugResetNextLaunchDetail"))
                }

                Section {
                    Button(action: seedSampleRecords) {
                        Label(store.t("debugSeedRecords"), systemImage: "calendar.badge.plus")
                    }
                    .foregroundStyle(.primary)
                } footer: {
                    Text(store.t("debugSeedRecordsDetail"))
                }

                Section {
                    ForEach(DebugTimerScenario.allCases) { scenario in
                        Button {
                            open(scenario)
                        } label: {
                            Label(store.t(scenario.titleKey), systemImage: scenario.symbol)
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text(store.t("debugCaptureScenarios"))
                } footer: {
                    Text(store.t("debugCaptureScenariosDetail"))
                }

                Section {
                    Button {
                        store.plus.debugSetAuthorized(!store.plus.isAuthorized)
                        actionFeedback += 1
                    } label: {
                        Label(
                            store.plus.isAuthorized ? store.t("plusStatusLifetime") : store.t("plusStatusNone"),
                            systemImage: "star"
                        )
                    }
                    Button {
                        store.plus.manageSubscriptions()
                    } label: {
                        Label(store.t("plusManage"), systemImage: "cart")
                    }
                }

                Section {
                    Button(action: startLiveActivity) {
                        HStack {
                            Label(store.t("debugLiveActivity"), systemImage: "platter.filled.bottom.and.arrow.down.iphone")
                            Spacer()
                            if isStartingLiveActivity {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    .disabled(isStartingLiveActivity)
                } footer: {
                    Text(store.t("debugLiveActivityDetail"))
                }
            }
            .navigationTitle(store.t("debugMenu"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("close"), action: dismiss.callAsFunction)
                }
            }
        }
        .presentationSizing(.form)
        .sensoryFeedback(.selection, trigger: actionFeedback)
        .alert(resultTitle, isPresented: $showsResult) { } message: {
            Text(resultMessage)
        }
        .onDisappear(perform: activatePendingScenario)
    }

    private func scheduleReset() {
        store.scheduleDebugResetOnNextLaunch()
        actionFeedback += 1
        resultTitle = store.t("debugResetNextLaunch")
        resultMessage = store.t("debugResetNextLaunchDetail")
        showsResult = true
    }

    private func seedSampleRecords() {
        let wrote = store.debugSeedSampleRecords()
        actionFeedback += 1
        resultTitle = store.t("debugSeedRecords")
        resultMessage = store.t(wrote ? "debugSeedRecordsDone" : "debugSeedRecordsAlready")
        showsResult = true
    }

    private func open(_ scenario: DebugTimerScenario) {
        actionFeedback += 1
        pendingScenario = scenario
        dismiss()
    }

    private func activatePendingScenario() {
        guard let pendingScenario else { return }
        self.pendingScenario = nil
        store.activateDebugTimerScenario(pendingScenario)
    }

    private func startLiveActivity() {
        guard !isStartingLiveActivity else { return }
        isStartingLiveActivity = true
        actionFeedback += 1
        Task {
            do {
                try await liveActivities.startDebugLiveActivity(store: store)
                resultTitle = store.t("debugLiveActivity")
                resultMessage = store.t("done")
            } catch {
                resultTitle = store.t("debugLiveActivity")
                resultMessage = error.localizedDescription
            }
            isStartingLiveActivity = false
            showsResult = true
        }
    }
}
#endif
