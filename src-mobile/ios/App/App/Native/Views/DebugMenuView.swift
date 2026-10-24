#if DEBUG
import SwiftUI

struct DebugMenuView: View {
    @Environment(SceneState.self) private var scene
    let debug: DebugScenarioController

    @Environment(LiveActivityService.self) private var liveActivities
    @Environment(\.dismiss) private var dismiss
    @State private var isStartingLiveActivity = false
    @State private var resultTitle = ""
    @State private var resultMessage = ""
    @State private var showsResult = false
    @State private var actionFeedback = 0
    @State private var pendingScenario: DebugTimerScenario?
    @State private var ignoreReviewThresholds = AppReviewDebugSwitch.ignoresThresholds
    @State private var reviewForceArmed = AppReviewDebugSwitch.forceArmed

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: scheduleReset) {
                        Label(debug.shifts.text.t("debugResetNextLaunch"), systemImage: "arrow.counterclockwise")
                    }
                    .foregroundStyle(.red)
                } footer: {
                    Text(debug.shifts.text.t("debugResetNextLaunchDetail"))
                }

                Section {
                    Button(action: seedSampleRecords) {
                        Label(debug.shifts.text.t("debugSeedRecords"), systemImage: "calendar.badge.plus")
                    }
                    .foregroundStyle(.primary)
                } footer: {
                    Text(debug.shifts.text.t("debugSeedRecordsDetail"))
                }

                Section {
                    ForEach(DebugTimerScenario.allCases) { scenario in
                        Button {
                            open(scenario)
                        } label: {
                            Label(debug.shifts.text.t(scenario.titleKey), systemImage: scenario.symbol)
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text(debug.shifts.text.t("debugCaptureScenarios"))
                } footer: {
                    Text(debug.shifts.text.t("debugCaptureScenariosDetail"))
                }

                Section {
                    Button {
                        debug.shifts.plus.debugSetAuthorized(!debug.shifts.plus.isAuthorized)
                        actionFeedback += 1
                    } label: {
                        Label(
                            debug.shifts.plus.isAuthorized ? debug.shifts.text.t("plusStatusLifetime") : debug.shifts.text.t("plusStatusNone"),
                            systemImage: "star"
                        )
                    }
                    Button {
                        debug.shifts.plus.manageSubscriptions()
                    } label: {
                        Label(debug.shifts.text.t("plusManage"), systemImage: "cart")
                    }
                }

                Section {
                    Toggle(isOn: $ignoreReviewThresholds) {
                        Label("忽略评分门槛", systemImage: "star.bubble")
                    }
                    .onChange(of: ignoreReviewThresholds) { _, value in
                        AppReviewDebugSwitch.ignoresThresholds = value
                    }
                    Button {
                        AppReviewDebugSwitch.forceArmed = true
                        reviewForceArmed = true
                        actionFeedback += 1
                    } label: {
                        Label(
                            reviewForceArmed ? "已预约：下次回到前台强制请求评分" : "下次回到前台强制请求评分",
                            systemImage: "star.leadinghalf.filled"
                        )
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text("评分请求")
                } footer: {
                    Text("仅 Debug。忽略门槛仍要下班后当天第一次打开，一天一次；付费墙、终身礼包、新版说明、编辑器、排班、专注和其它弹层会推迟到下一次打开。强制请求只生效一次，遇到这些弹层会继续等到下一次打开。Release 构建没有这些开关。")
                }

                Section {
                    Button(action: startLiveActivity) {
                        HStack {
                            Label(debug.shifts.text.t("debugLiveActivity"), systemImage: "platter.filled.bottom.and.arrow.down.iphone")
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
                    Text(debug.shifts.text.t("debugLiveActivityDetail"))
                }
            }
            .navigationTitle(debug.shifts.text.t("debugMenu"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(debug.shifts.text.t("close"), action: dismiss.callAsFunction)
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
        debug.scheduleDebugResetOnNextLaunch()
        actionFeedback += 1
        resultTitle = debug.shifts.text.t("debugResetNextLaunch")
        resultMessage = debug.shifts.text.t("debugResetNextLaunchDetail")
        showsResult = true
    }

    private func seedSampleRecords() {
        let command = debug.debugSeedSampleRecords()
        Task { @MainActor in
            let wrote = await command.value
            if wrote { scene.selectedTab = .records }
            actionFeedback += 1
            resultTitle = debug.shifts.text.t("debugSeedRecords")
            resultMessage = debug.shifts.text.t(wrote ? "debugSeedRecordsDone" : "debugSeedRecordsAlready")
            showsResult = true
        }
    }

    private func open(_ scenario: DebugTimerScenario) {
        actionFeedback += 1
        pendingScenario = scenario
        dismiss()
    }

    private func activatePendingScenario() {
        guard let pendingScenario else { return }
        self.pendingScenario = nil
        debug.activateDebugTimerScenario(pendingScenario)
        scene.openTimer()
    }

    private func startLiveActivity() {
        guard !isStartingLiveActivity else { return }
        isStartingLiveActivity = true
        actionFeedback += 1
        Task {
            do {
                try await liveActivities.startDebugLiveActivity(shifts: debug.shifts)
                resultTitle = debug.shifts.text.t("debugLiveActivity")
                resultMessage = debug.shifts.text.t("done")
            } catch {
                resultTitle = debug.shifts.text.t("debugLiveActivity")
                resultMessage = error.localizedDescription
            }
            isStartingLiveActivity = false
            showsResult = true
        }
    }
}
#endif
