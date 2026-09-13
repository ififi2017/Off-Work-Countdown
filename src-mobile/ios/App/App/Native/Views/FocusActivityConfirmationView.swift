import SwiftUI

struct FocusActivityConfirmationView: View {
    let focus: FocusStore
    let request: FocusActivityRequest
    @State private var count = 1
    @State private var revision = 0
    @State private var isSubmitting = false
    @ScaledMetric(relativeTo: .body) private var sheetHeight: CGFloat = 240
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                let matches = focus.matchesFocusActivity(request, at: timeline.date)
                let maximum = matches ? focus.addableFocusBlocks(at: timeline.date).count : 0
                Form {
                    Section {
                        if !matches {
                            Text(focus.t("focusPhaseComplete"))
                        } else if maximum > 0 {
                            Stepper(value: $count, in: 1...maximum) {
                                LabeledContent(focus.t("focusAddPomodoroCount"), value: "\(count)")
                                    .monospacedDigit()
                            }
                        } else {
                            Text(focus.t("focusNoEmptyBlockShort"))
                        }
                    } footer: {
                        if matches {
                            Text(focus.t("focusAddPomodoroCapacity", values: ["count": "\(maximum)"]))
                        }
                    }
                }
                .onChange(of: maximum) { count = min(count, max(1, maximum)) }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(focus.t("focusSaveTask")) {
                            let submittedCount = count
                            let command = focus.addFocusPomodoroToRunningTask(
                                count: submittedCount,
                                matching: request
                            )
                            if let saved = command.immediateResult {
                                guard saved else { revision += 1; return }
                                dismiss()
                                return
                            }
                            isSubmitting = true
                            Task { @MainActor in
                                let saved = await command.value
                                isSubmitting = false
                                guard saved else { revision += 1; return }
                                dismiss()
                            }
                        }
                        .disabled(!matches || maximum == 0 || count > maximum)
                    }
                }
            }
            .id(revision)
            .navigationTitle(focus.t("focusActivityAddPomodoro"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(focus.t("cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationSizing(.form)
        .disabled(isSubmitting)
        .interactiveDismissDisabled(isSubmitting)
    }
}

struct FocusActivityConfirmationModifier: ViewModifier {
    @Environment(SceneState.self) private var scene
    let focus: FocusStore
    @State private var dismissingSheetRequestID: String?

    func body(content: Content) -> some View {
        content
        .sheet(item: Binding(
            get: {
                let request = scene.focusActivityPresentationReady ? scene.focusActivityRequest : nil
                return request?.action == .addPomodoros ? request : nil
            },
            set: {
                if $0 == nil, dismissingSheetRequestID == nil {
                    dismissingSheetRequestID = scene.beginDismissingFocusActivitySheet()
                }
            }
        ), onDismiss: {
            guard let id = dismissingSheetRequestID else { return }
            dismissingSheetRequestID = nil
            scene.finishDismissingFocusActivitySheet(id: id)
        }) { request in
            FocusActivityConfirmationView(focus: focus, request: request)
        }
        .alert(focus.t("focusStopTitle"), isPresented: Binding(
            get: { scene.focusActivityPresentationReady && scene.focusActivityRequest?.action == .stop },
            set: { if !$0 { scene.dismissFocusActivityAlert() } }
        ), presenting: scene.focusActivityRequest) { request in
            Button(focus.t("focusStop"), role: .destructive) {
                _ = focus.stopFocusFromActivity(startAtMs: request.startAtMs)
            }
            .disabled(!focus.matchesFocusActivity(request))
            Button(focus.t("cancel"), role: .cancel) {}
        } message: { request in
            Text(focus.t(focus.matchesFocusActivity(request) ? "focusStopConfirm" : "focusPhaseComplete"))
        }
    }
}
