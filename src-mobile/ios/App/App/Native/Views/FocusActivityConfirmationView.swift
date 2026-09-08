import SwiftUI

struct FocusActivityConfirmationView: View {
    let store: OffWorkStore
    let request: FocusActivityRequest
    @State private var count = 1
    @State private var revision = 0
    @ScaledMetric(relativeTo: .body) private var sheetHeight: CGFloat = 240
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                let matches = store.matchesFocusActivity(request, at: timeline.date)
                let maximum = matches ? store.addableFocusBlocks(at: timeline.date).count : 0
                Form {
                    Section {
                        if !matches {
                            Text(store.t("focusPhaseComplete"))
                        } else if maximum > 0 {
                            Stepper(value: $count, in: 1...maximum) {
                                LabeledContent(store.t("focusAddPomodoroCount"), value: "\(count)")
                                    .monospacedDigit()
                            }
                        } else {
                            Text(store.t("focusNoEmptyBlockShort"))
                        }
                    } footer: {
                        if matches {
                            Text(store.t("focusAddPomodoroCapacity", values: ["count": "\(maximum)"]))
                        }
                    }
                }
                .onChange(of: maximum) { count = min(count, max(1, maximum)) }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(store.t("focusSaveTask")) {
                            guard store.matchesFocusActivity(request),
                                  store.addFocusPomodoroToRunningTask(count: count)
                            else { revision += 1; return }
                            dismiss()
                        }
                        .disabled(!matches || maximum == 0 || count > maximum)
                    }
                }
            }
            .id(revision)
            .navigationTitle(store.t("focusActivityAddPomodoro"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.t("cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationSizing(.form)
    }
}

struct FocusActivityConfirmationModifier: ViewModifier {
    @Bindable var store: OffWorkStore

    func body(content: Content) -> some View {
        content
        .sheet(item: Binding(
            get: { store.focusActivityRequest?.action == .addPomodoros ? store.focusActivityRequest : nil },
            set: { if $0 == nil { store.focusActivityRequest = nil } }
        )) { request in
            FocusActivityConfirmationView(store: store, request: request)
        }
        .alert(store.t("focusStopTitle"), isPresented: Binding(
            get: { store.focusActivityRequest?.action == .stop },
            set: { if !$0 { store.focusActivityRequest = nil } }
        ), presenting: store.focusActivityRequest) { request in
            Button(store.t("focusStop"), role: .destructive) {
                _ = store.stopFocusFromActivity(startAtMs: request.startAtMs)
            }
            .disabled(!store.matchesFocusActivity(request))
            Button(store.t("cancel"), role: .cancel) {}
        } message: { request in
            Text(store.t(store.matchesFocusActivity(request) ? "focusStopConfirm" : "focusPhaseComplete"))
        }
    }
}
