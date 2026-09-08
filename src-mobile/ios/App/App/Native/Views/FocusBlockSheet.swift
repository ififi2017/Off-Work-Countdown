import SwiftUI

/// All creation entry points share these fields and the same sheet shell.
struct FocusTaskEditorDraft {
    var title = ""
    var icon = FocusTaskIcon.focus
    var pomodoros = 1
    var isFavorite = false
    var favoriteID: UUID?
    var existingTaskID: UUID?

    var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    mutating func select(_ task: FocusTask, favorite: Bool, remaining: Int? = nil) {
        title = task.title
        icon = task.icon
        pomodoros = max(1, remaining ?? task.estimatedPomodoros)
        isFavorite = favorite
        favoriteID = favorite ? task.id : nil
        existingTaskID = favorite ? nil : task.id
    }
}

struct FocusTaskEditorShell<Content: View>: View {
    let store: OffWorkStore
    var saveTitle: String
    var titleKey = "focusNewTask"
    var canSave: Bool
    var onCancel: () -> Void
    var onSave: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            OWCContentSizedScrollView {
                VStack(alignment: .leading, spacing: 16) { content }
                    .padding(.horizontal, OWCDesign.pageInset)
                    .padding(.top, 18)
                    .padding(.bottom, OWCDesign.detailBottomInset)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(OWCDesign.page)
            .navigationTitle(store.t(titleKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(store.t("cancel"), action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(saveTitle) {
                        // Finish any active composition before reading the draft.
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                        )
                        onSave()
                    }.disabled(!canSave)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

struct FocusTaskEditorFields: View {
    let store: OffWorkStore
    @Binding var draft: FocusTaskEditorDraft
    let destination: String
    let finish: Date?
    var referenceDate = Date.now
    var showsDate = true
    var showsFinish = true
    var minimumPomodoros = 1
    var maximumPomodoros: Int?
    var capacityNote: String?
    @State private var titleFocused = false

    var body: some View {
        Label(destination, systemImage: "calendar.badge.plus")
            .fixedSize(horizontal: false, vertical: true)
            .font(.footnote)
            .foregroundStyle(OWCDesign.secondary)
        if let capacityNote {
            Text(capacityNote)
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        FocusTitleField(store: store, title: $draft.title, icon: draft.icon,
                        focused: $titleFocused, placeholder: store.t("focusTaskPlaceholder"))
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 4) {
                OWCRow(icon: "number", title: store.t("focusEstimate"),
                       subtitle: store.t("focusEstimateDetail", values: [
                        "count": "\(draft.pomodoros)",
                        "minutes": "\(store.focusTimerSettings.normalized.focusMinutes)"
                       ]), isLast: true) {
                    Stepper(value: $draft.pomodoros, in: minimumPomodoros...max(maximumPomodoros ?? 12, draft.pomodoros, minimumPomodoros)) {
                        Text("\(draft.pomodoros)")
                    }
                    .labelsHidden()
                    .accessibilityLabel(store.t("focusEstimate"))
                    .accessibilityValue("\(draft.pomodoros)")
                    .fixedSize()
                }
                if showsFinish {
                Text(finish.map { date in
                    let time = showsDate && !store.recordsCalendar.isDate(date, inSameDayAs: referenceDate)
                        ? store.formatDate(date) + " · " + store.formatTime(date)
                        : store.formatTime(date)
                    return store.t("focusEstimatedFinish", values: ["time": time])
                } ?? store.t("focusNoRoomThisShift"))
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .accessibilityIdentifier("focus.estimatedFinish")
                }
            }
        }
        FocusTaskIconPicker(store: store, selection: $draft.icon)
        FocusFavoriteToggle(store: store, isFavorite: $draft.isFavorite)
        FocusFavoritePicker(store: store, title: $draft.title, icon: $draft.icon, selectedID: $draft.favoriteID) {
            draft.select($0, favorite: true)
            draft.pomodoros = max(minimumPomodoros, min(draft.pomodoros, maximumPomodoros ?? draft.pomodoros))
        }
    }
}

/// The occupied-block actions stay small; empty blocks use the unified editor.
struct FocusBlockSheet: View {
    let store: OffWorkStore
    let block: FocusDayCanvasModel.Block
    var onResult: (FocusPlacementResult) -> Void
    @ScaledMetric(relativeTo: .body) private var assignedSheetHeight: CGFloat = 240
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let taskID = block.taskID,
           let task = store.records.state.focusTasks.first(where: { $0.id == taskID && $0.deletedAt == nil }) {
            FocusTaskEditSheet(store: store, task: task)
        } else if block.hasAssignment {
            NavigationStack {
                VStack(spacing: 14) {
                    OWCGroupCard {
                        OWCRow(icon: block.isUserBreak ? "cup.and.saucer.fill" : (block.taskIcon ?? .focus).systemName,
                               title: block.isUserBreak ? store.t("focusBreak") : (block.taskTitle ?? store.t("focusTaskTitle")),
                               isLast: true) {
                            Image(systemName: "checkmark").foregroundStyle(OWCDesign.accent)
                        }
                    }
                    Button(store.t("focusBlockClear"), role: .destructive) {
                        store.clearBlock(startingAt: block.startAtMs)
                        dismiss()
                    }.buttonStyle(OWCSecondaryButtonStyle())
                }
                .padding(OWCDesign.pageInset)
                .background(OWCDesign.page)
                .toolbar { ToolbarItem(placement: .topBarLeading) {
                    Button(store.t("close")) { dismiss() }
                } }
            }
            .presentationDetents([.height(assignedSheetHeight)])
            .presentationDragIndicator(.visible)
        } else {
            FocusQuickCreateSheet(store: store, blockStartAtMs: block.startAtMs, onResult: onResult)
        }
    }
}

struct FocusQuickCreateSheet: View {
    let store: OffWorkStore
    var blockStartAtMs: Int64?
    var onResult: (FocusPlacementResult) -> Void
    @State private var draft: FocusTaskEditorDraft
    @State private var landing: Landing
    @Environment(\.dismiss) private var dismiss

    init(store: OffWorkStore, initialLanding: Landing = .nextBlock,
         blockStartAtMs: Int64? = nil, favorite: FocusTask? = nil,
         onResult: @escaping (FocusPlacementResult) -> Void) {
        self.store = store
        self.blockStartAtMs = blockStartAtMs
        self.onResult = onResult
        _landing = State(initialValue: initialLanding)
        var draft = FocusTaskEditorDraft()
        if let favorite { draft.select(favorite, favorite: true) }
        _draft = State(initialValue: draft)
    }

    enum Landing: String, Identifiable {
        case nextBlock, currentOrNextBlock, startNow, unscheduled
        var id: String { rawValue }
    }

    private var canStart: Bool {
        if let existingTask { return store.focusStartAvailability(existingTask) == .ready }
        return store.activeFocusSession() == nil && store.hasFocusRoom()
    }
    private var tasks: [FocusTask] { store.focusTasksForCanvas().filter { $0.completedAt == nil } }
    private var existingTask: FocusTask? { tasks.first { $0.id == draft.existingTaskID } }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let canvas = store.focusDayCanvas(at: context.date)
            let target = blockStartAtMs ?? canvas.nextEmptyBlock?.startAtMs
            let finish = store.focusCreationFinish(pomodoros: draft.pomodoros, startingAt: target,
                                                   startNow: landing == .startNow, taskID: draft.existingTaskID,
                                                   at: context.date)
            FocusTaskEditorShell(store: store,
                saveTitle: store.t(landing == .startNow ? "focusAddAndStart" : "focusSaveTask"),
                canSave: draft.canSave && (landing != .startNow || canStart)
                    && (landing != .unscheduled || draft.isFavorite)
                    && (draft.existingTaskID == nil || landing == .startNow || landing == .unscheduled || target != nil),
                onCancel: { dismiss() }, onSave: save) {
                FocusTaskEditorFields(store: store, draft: $draft,
                                      destination: landing == .unscheduled ? store.t("focusLeaveUnscheduled") : (landing == .startNow ? store.t("focusStartNow") : destination(target)),
                                      finish: finish, referenceDate: context.date, showsFinish: landing != .unscheduled)
                if (blockStartAtMs == nil && landing != .currentOrNextBlock) || draft.isFavorite {
                    OWCSectionHeader(title: store.t("focusLanding"))
                    OWCGroupCard {
                        landingRow(.nextBlock, icon: "calendar.badge.plus", title: destination(target))
                        landingRow(.startNow, icon: "play.fill", title: store.t("focusStartNow"), isLast: !draft.isFavorite)
                        if draft.isFavorite {
                            landingRow(.unscheduled, icon: "tray", title: store.t("focusLeaveUnscheduled"), isLast: true)
                        }
                    }
                }
                if !tasks.isEmpty {
                    OWCSectionHeader(title: store.t("focusBlockExisting"))
                    OWCGroupCard {
                        ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                            Button {
                                draft.select(task, favorite: false,
                                             remaining: max(1, task.estimatedPomodoros - store.completedFocusBlocks(for: task)))
                                draft.isFavorite = store.savedFocusFavorite(title: task.title, icon: task.icon) != nil
                            } label: {
                                OWCRow(icon: task.icon.systemName, title: task.title,
                                       subtitle: store.t("focusEstimateDetail", values: [
                                        "count": "\(max(1, task.estimatedPomodoros - store.completedFocusBlocks(for: task)))",
                                        "minutes": "\(store.focusTimerSettings.normalized.focusMinutes)"
                                       ]), isLast: index == tasks.count - 1) {
                                    if draft.existingTaskID == task.id {
                                        Image(systemName: "checkmark").foregroundStyle(OWCDesign.accent)
                                    }
                                }
                            }.buttonStyle(OWCRowButtonStyle())
                        }
                    }
                }
                if let blockStartAtMs {
                    Button(store.t("focusBlockMakeBreak")) {
                        store.markBlockAsBreak(startingAt: blockStartAtMs)
                        onResult(.placed(taskID: UUID(), blockStartAtMs: blockStartAtMs))
                        dismiss()
                    }.buttonStyle(OWCSecondaryButtonStyle())
                }
            }
        }
        .onChange(of: draft.isFavorite) {
            if !draft.isFavorite, landing == .unscheduled { landing = .nextBlock }
        }
        .onChange(of: draft.title) {
            if let existingTask, existingTask.title != draft.title { draft.existingTaskID = nil }
        }
        .onChange(of: draft.icon) {
            if let existingTask, existingTask.icon != draft.icon { draft.existingTaskID = nil }
        }
    }

    private func destination(_ target: Int64?) -> String {
        guard let target else { return store.t("focusNoEmptyBlockShort") }
        let date = Date(timeIntervalSince1970: Double(target) / 1_000)
        let time = store.recordsCalendar.isDateInToday(date)
            ? store.formatTime(date) : store.formatDate(date) + " · " + store.formatTime(date)
        return store.t(blockStartAtMs == nil ? "focusLandingNextBlock" : "focusFavoriteLands", values: ["time": time])
    }

    private var startDisabledReason: String? {
        guard !canStart else { return nil }
        if store.activeFocusSession() != nil { return store.t("focusStartAlreadyRunning") }
        if !store.isWithinFocusWorkTime() { return store.t("focusOutsideWorkHours") }
        if let existingTask, case .notYetAvailable(let date) = store.focusStartAvailability(existingTask) {
            return store.t("focusStartAfter", values: ["time": store.formatDate(date) + " · " + store.formatTime(date)])
        }
        return store.t("focusNoRoom")
    }

    private func landingRow(_ value: Landing, icon: String, title: String, isLast: Bool = false) -> some View {
        let unavailable = value == .startNow && !canStart
        return VStack(spacing: 0) {
            Button { landing = value } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: icon).frame(width: 24).foregroundStyle(OWCDesign.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(unavailable ? OWCDesign.tertiary : OWCDesign.primary)
                        if unavailable, let reason = startDisabledReason {
                            Text(reason).font(.footnote).foregroundStyle(OWCDesign.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if landing == value || (value == .nextBlock && landing == .currentOrNextBlock) {
                        Image(systemName: "checkmark").foregroundStyle(OWCDesign.accent)
                    }
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(OWCRowButtonStyle())
            .disabled(unavailable)
            if !isLast { Divider().padding(.leading, 52) }
        }
    }

    private func save() {
        guard draft.canSave else { return }
        if landing == .unscheduled {
            guard draft.isFavorite else { return }
            store.saveFocusFavorite(title: draft.title, pomodoros: draft.pomodoros, icon: draft.icon)
            dismiss()
            return
        }
        if landing == .startNow {
            guard canStart else { return }
            if var existingTask {
                existingTask.estimatedPomodoros = store.completedFocusBlocks(for: existingTask) + draft.pomodoros
                store.records.upsertFocusTask(existingTask)
                guard store.startFocus(task: existingTask) else { return }
            } else {
                store.addAndStartFocusTask(title: draft.title, pomodoros: draft.pomodoros,
                                          icon: draft.icon, isFavorite: draft.isFavorite)
            }
        } else if var existingTask {
            let target = blockStartAtMs ?? store.focusDayCanvas().nextEmptyBlock?.startAtMs
            guard let target else { return }
            existingTask.estimatedPomodoros = store.completedFocusBlocks(for: existingTask) + draft.pomodoros
            store.records.upsertFocusTask(existingTask)
            onResult(store.placeFocusTask(existingTask, pomodoros: draft.pomodoros, startingAt: target))
        } else if let blockStartAtMs {
            onResult(store.createFocusTask(title: draft.title, icon: draft.icon, pomodoros: draft.pomodoros,
                                           inBlockStartingAt: blockStartAtMs, scheduleAllPomodoros: true))
        } else {
            onResult(store.createFocusTaskInNextEmptyBlock(title: draft.title, pomodoros: draft.pomodoros,
                                                          icon: draft.icon, scheduleAllPomodoros: true))
        }
        if draft.isFavorite {
            store.saveFocusFavorite(title: draft.title, pomodoros: draft.pomodoros, icon: draft.icon)
        }
        dismiss()
    }
}

/// The title row both creation paths use, so they cannot drift apart again.
struct FocusTitleField: View {
    let store: OffWorkStore
    @Binding var title: String
    let icon: FocusTaskIcon
    @Binding var focused: Bool
    let placeholder: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon.systemName)
                .foregroundStyle(focused ? OWCDesign.accent : OWCDesign.secondary)
                .accessibilityHidden(true)
            FocusTaskTitleInput(
                text: $title, placeholder: placeholder,
                accessibilityTitle: store.t("focusTaskTitle"),
                onFocusChange: { focused = $0 }
            )
            .transaction { $0.animation = nil }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
        .background(
            focused ? OWCDesign.accent.opacity(0.08) : OWCDesign.control,
            in: RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous)
                .strokeBorder(
                    focused ? OWCDesign.accent.opacity(0.72) : OWCDesign.separator,
                    lineWidth: focused ? 1.5 : 1
                )
        }
        .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.press, value: focused)
    }
}
