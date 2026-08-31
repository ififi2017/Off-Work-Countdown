import SwiftUI

struct FocusDesignView: View {
    let store: OffWorkStore
    @State private var title = ""
    @State private var pomodoros = "1"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let session = store.activeFocusSession() {
                    OWCGroupCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(store.t("focusTitle"))
                                .font(.body.weight(.medium))
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                let remaining = max(0, session.plannedEndAt.timeIntervalSince(context.date))
                                Text(
                                    Duration.seconds(remaining).formatted(
                                        .time(pattern: .minuteSecond)
                                    )
                                )
                                .font(.title3.monospacedDigit())
                                .onChange(of: remaining) { _, value in
                                    if value <= 0 {
                                        store.stopFocus(reason: .stoppedAtBoundary)
                                    }
                                }
                            }
                            Button(store.t("focusStop")) {
                                store.stopFocus(reason: .stoppedByUser)
                            }
                            .buttonStyle(OWCPrimaryButtonStyle())
                        }
                        .padding(16)
                    }
                } else {
                    OWCGroupCard {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField(store.t("focusTaskTitle"), text: $title)
                                .textFieldStyle(.roundedBorder)
                            TextField(store.t("focusPomodoros"), text: $pomodoros)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                            Button(store.t("focusNewTask"), action: addTask)
                                .buttonStyle(OWCPrimaryButtonStyle())
                        }
                        .padding(16)
                    }
                }

                if store.focusRejectedNoRoom || !store.focusOverflow().isEmpty {
                    Text(store.t("focusNoRoom"))
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                        .padding(.horizontal, 8)
                }

                OWCGroupCard {
                    ForEach(Array(store.focusTasksForToday().enumerated()), id: \.element.id) { index, task in
                        if index > 0 { Divider().padding(.leading, 16) }
                        HStack {
                            Text(task.title)
                            Spacer()
                            if task.completedAt == nil {
                                Button(store.t("focusStart")) {
                                    store.startFocus(task: task)
                                }
                            } else {
                                Text(store.t("focusDone"))
                                    .foregroundStyle(OWCDesign.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .background(OWCDesign.page)
        .navigationTitle(store.t("focusTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: .OWCFocusBoundaryReached)) { _ in
            store.stopFocus(reason: .stoppedAtBoundary)
        }
    }

    private func addTask() {
        store.addFocusTask(title: title, pomodoros: Int(pomodoros) ?? 1)
        title = ""
        pomodoros = "1"
    }
}

extension Notification.Name {
    static let OWCFocusBoundaryReached = Notification.Name("OWCFocusBoundaryReached")
}
