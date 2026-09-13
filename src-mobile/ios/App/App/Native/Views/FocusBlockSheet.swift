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
    var title: String
    var cancelTitle: String
    var saveTitle: String
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
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(cancelTitle, action: onCancel)
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
    let focus: FocusStore
    let text: AppText
    @Binding var draft: FocusTaskEditorDraft
    let destination: String?
    let finish: Date?
    var referenceDate = Date.now
    var showsDate = true
    var showsFinish = true
    var showsOptions = true
    var minimumPomodoros = 1
    var maximumPomodoros: Int?
    var capacityNote: String?
    @State private var titleFocused = false

    var body: some View {
        if let destination {
            Label(destination, systemImage: "calendar.badge.plus")
                .fixedSize(horizontal: false, vertical: true)
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
        }
        if let capacityNote {
            Text(capacityNote)
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        FocusTitleField(focus: focus, title: $draft.title, icon: draft.icon,
                        focused: $titleFocused, placeholder: focus.t("focusTaskPlaceholder"))
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 4) {
                OWCRow(icon: "number", title: focus.t("focusEstimate"),
                       subtitle: focus.t("focusEstimateDetail", values: [
                        "count": "\(draft.pomodoros)",
                        "minutes": "\(focus.focusTimerSettings.normalized.focusMinutes)"
                       ]), isLast: true) {
                    Stepper(value: $draft.pomodoros, in: minimumPomodoros...max(maximumPomodoros ?? 12, draft.pomodoros, minimumPomodoros)) {
                        Text("\(draft.pomodoros)")
                    }
                    .labelsHidden()
                    .accessibilityLabel(focus.t("focusEstimate"))
                    .accessibilityValue("\(draft.pomodoros)")
                    .fixedSize()
                }
                if showsFinish {
                Text(finish.map { date in
                    let time = showsDate && !focus.recordsCalendar.isDate(date, inSameDayAs: referenceDate)
                        ? text.formatDate(date) + " · " + focus.formatTime(date)
                        : focus.formatTime(date)
                    return focus.t("focusEstimatedFinish", values: ["time": time])
                } ?? focus.t("focusNoRoomThisShift"))
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .accessibilityIdentifier("focus.estimatedFinish")
                }
            }
        }
        if showsOptions {
            FocusTaskEditorOptions(focus: focus, draft: $draft,
                                   minimumPomodoros: minimumPomodoros, maximumPomodoros: maximumPomodoros)
        }
    }
}

private struct FocusTaskEditorOptions: View {
    let focus: FocusStore
    @Binding var draft: FocusTaskEditorDraft
    var minimumPomodoros = 1
    var maximumPomodoros: Int?

    var body: some View {
        FocusTaskIconPicker(title: focus.t("focusChooseIcon"), label: { focus.t($0.titleKey) }, selection: $draft.icon)
        FocusFavoriteToggle(title: focus.t("focusMakeFavorite"), isFavorite: $draft.isFavorite)
        FocusFavoritePicker(focus: focus, title: $draft.title, icon: $draft.icon, selectedID: $draft.favoriteID) {
            draft.select($0, favorite: true)
            draft.pomodoros = max(minimumPomodoros, min(draft.pomodoros, maximumPomodoros ?? draft.pomodoros))
        }
    }
}

/// The occupied-block actions stay small; empty blocks use the unified editor.
struct FocusBlockSheet: View {
    let focus: FocusStore
    let text: AppText
    let block: FocusDayCanvasModel.Block
    var onResult: (FocusPlacementResult) -> Void
    @ScaledMetric(relativeTo: .body) private var assignedSheetHeight: CGFloat = 240
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let taskID = block.taskID,
           let task = focus.records.state.focusTasks.first(where: { $0.id == taskID && $0.deletedAt == nil }) {
            FocusTaskEditSheet(focus: focus, text: text, task: task)
        } else if block.hasAssignment {
            NavigationStack {
                VStack(spacing: 14) {
                    OWCGroupCard {
                        OWCRow(icon: block.isUserBreak ? "cup.and.saucer.fill" : (block.taskIcon ?? .focus).systemName,
                               title: block.isUserBreak ? focus.t("focusBreak") : (block.taskTitle ?? focus.t("focusTaskTitle")),
                               isLast: true) {
                            Image(systemName: "checkmark").foregroundStyle(OWCDesign.accent)
                        }
                    }
                    Button(focus.t("focusBlockClear"), role: .destructive) {
                        Task { @MainActor in
                            await focus.clearBlock(startingAt: block.startAtMs).value
                            dismiss()
                        }
                    }.buttonStyle(OWCSecondaryButtonStyle())
                }
                .padding(OWCDesign.pageInset)
                .background(OWCDesign.page)
                .toolbar { ToolbarItem(placement: .topBarLeading) {
                    Button(focus.t("close")) { dismiss() }
                } }
            }
            .presentationDetents([.height(assignedSheetHeight)])
            .presentationDragIndicator(.visible)
        } else {
            FocusQuickCreateSheet(focus: focus, text: text, blockStartAtMs: block.startAtMs, onResult: onResult)
        }
    }
}

struct FocusQuickCreateSheet: View {
    @Environment(SceneState.self) private var scene
    let focus: FocusStore
    let text: AppText
    var blockStartAtMs: Int64?
    var onResult: (FocusPlacementResult) -> Void
    @State private var draft: FocusTaskEditorDraft
    @State private var landing: FocusQuickCreateLanding
    @State private var isSubmitting = false
    @Environment(\.dismiss) private var dismiss

    init(focus: FocusStore, text: AppText, initialLanding: FocusQuickCreateLanding = .nextBlock,
         blockStartAtMs: Int64? = nil, favorite: FocusTask? = nil,
         onResult: @escaping (FocusPlacementResult) -> Void) {
        self.focus = focus
        self.text = text
        self.blockStartAtMs = blockStartAtMs
        self.onResult = onResult
        _landing = State(initialValue: initialLanding)
        var draft = FocusTaskEditorDraft()
        if let favorite { draft.select(favorite, favorite: true) }
        _draft = State(initialValue: draft)
    }


    private var canStart: Bool {
        if let existingTask { return focus.focusStartAvailability(existingTask) == .ready }
        return focus.activeFocusSession() == nil && focus.hasFocusRoom()
    }
    private var tasks: [FocusTask] { focus.focusTasksForCanvas().filter { $0.completedAt == nil } }
    private var existingTask: FocusTask? { tasks.first { $0.id == draft.existingTaskID } }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let canvas = focus.focusDayCanvas(at: context.date)
            let target = blockStartAtMs ?? canvas.nextEmptyBlock?.startAtMs
            let finish = focus.focusCreationFinish(pomodoros: draft.pomodoros, startingAt: target,
                                                   startNow: landing == .startNow, taskID: draft.existingTaskID,
                                                   at: context.date)
            FocusTaskEditorShell(title: focus.t("focusNewTask"), cancelTitle: focus.t("cancel"),
                saveTitle: focus.t(landing == .startNow ? "focusAddAndStart" : "focusSaveTask"),
                canSave: draft.canSave && (landing != .startNow || canStart)
                    && (landing != .unscheduled || draft.isFavorite)
                    && (draft.existingTaskID == nil || landing == .startNow || landing == .unscheduled || target != nil),
                onCancel: { dismiss() }, onSave: save) {
                FocusTaskEditorFields(focus: focus, text: text, draft: $draft, destination: nil,
                                      finish: finish,
                                      referenceDate: landing == .startNow ? context.date : target.map { Date(timeIntervalSince1970: Double($0) / 1_000) } ?? context.date,
                                      showsFinish: landing != .unscheduled, showsOptions: false)
                OWCSectionHeader(title: focus.t("focusLanding"))
                OWCGroupCard {
                    if (blockStartAtMs == nil && landing != .currentOrNextBlock) || draft.isFavorite {
                        landingRow(.nextBlock, icon: "calendar.badge.plus", title: focus.t("focusLandingNextBlock"),
                                   subtitle: destinationTime(target, relativeTo: context.date))
                        landingRow(.startNow, icon: "play.fill", title: focus.t("focusStartNow"), isLast: !draft.isFavorite)
                        if draft.isFavorite {
                            landingRow(.unscheduled, icon: "tray", title: focus.t("focusLeaveUnscheduled"), isLast: true)
                        }
                    } else {
                        OWCRow(icon: "calendar.badge.plus", title: focus.t(blockStartAtMs == nil ? "focusLandingNextBlock" : "focusThisBlock"),
                               subtitle: destinationTime(target, relativeTo: context.date), isLast: true) {
                            EmptyView()
                        }
                    }
                }
                FocusTaskEditorOptions(focus: focus, draft: $draft)
                if !tasks.isEmpty {
                    OWCSectionHeader(title: focus.t("focusBlockExisting"))
                    OWCGroupCard {
                        ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                            Button {
                                draft.select(task, favorite: false,
                                             remaining: max(1, task.estimatedPomodoros - focus.completedFocusBlocks(for: task)))
                                draft.isFavorite = focus.savedFocusFavorite(title: task.title, icon: task.icon) != nil
                            } label: {
                                OWCRow(icon: task.icon.systemName, title: task.title,
                                       subtitle: focus.t("focusEstimateDetail", values: [
                                        "count": "\(max(1, task.estimatedPomodoros - focus.completedFocusBlocks(for: task)))",
                                        "minutes": "\(focus.focusTimerSettings.normalized.focusMinutes)"
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
                    Button(focus.t("focusBlockMakeBreak")) {
                        Task { @MainActor in
                            await focus.markBlockAsBreak(startingAt: blockStartAtMs).value
                            onResult(.placed(taskID: UUID(), blockStartAtMs: blockStartAtMs))
                            dismiss()
                        }
                    }.buttonStyle(OWCSecondaryButtonStyle())
                }
            }
            .disabled(isSubmitting)
            .interactiveDismissDisabled(isSubmitting)
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

    private func destinationTime(_ target: Int64?, relativeTo reference: Date) -> String {
        guard let target else { return focus.t("focusNoEmptyBlockShort") }
        let date = Date(timeIntervalSince1970: Double(target) / 1_000)
        let calendar = focus.recordsCalendar
        let day: String
        if calendar.isDate(date, inSameDayAs: reference) {
            day = focus.t("focusToday")
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: reference),
                  calendar.isDate(date, inSameDayAs: tomorrow) {
            day = focus.t("tomorrow")
        } else {
            day = text.formatDate(date)
        }
        return day + " · " + focus.formatTime(date)
    }

    private var startDisabledReason: String? {
        guard !canStart else { return nil }
        if focus.activeFocusSession() != nil { return focus.t("focusStartAlreadyRunning") }
        if !focus.isWithinFocusWorkTime() { return focus.t("focusOutsideWorkHours") }
        if let existingTask, case .notYetAvailable(let date) = focus.focusStartAvailability(existingTask) {
            return focus.t("focusStartAfter", values: ["time": text.formatDate(date) + " · " + focus.formatTime(date)])
        }
        return focus.t("focusNoRoom")
    }

    private func landingRow(_ value: FocusQuickCreateLanding, icon: String, title: String, subtitle: String? = nil, isLast: Bool = false) -> some View {
        let unavailable = value == .startNow && !canStart
        return VStack(spacing: 0) {
            Button { landing = value } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: icon).frame(width: 24).foregroundStyle(OWCDesign.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(unavailable ? OWCDesign.tertiary : OWCDesign.primary)
                        if let subtitle {
                            Text(subtitle).font(.footnote).foregroundStyle(OWCDesign.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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
        let submitted = draft
        if landing == .unscheduled {
            guard draft.isFavorite else { return }
            let command = focus.saveFocusFavorite(title: submitted.title, pomodoros: submitted.pomodoros, icon: submitted.icon)
            if command.immediateResult != nil { dismiss(); return }
            isSubmitting = true
            Task { @MainActor in
                await command.value
                isSubmitting = false
                guard draftMatches(submitted) else { return }
                dismiss()
            }
            return
        }
        if landing == .startNow {
            guard canStart else { return }
            if let existingTask {
                let command = scene.startFocus(task: existingTask, pomodoros: submitted.pomodoros, using: focus)
                if let started = command.immediateResult {
                    if started {
                        if submitted.isFavorite {
                            _ = focus.saveFocusFavorite(title: submitted.title, pomodoros: submitted.pomodoros, icon: submitted.icon)
                        }
                        dismiss()
                    }
                    return
                }
                isSubmitting = true
                Task { @MainActor in
                    let started = await command.value
                    isSubmitting = false
                    guard started,
                          draftMatches(submitted) else { return }
                    if submitted.isFavorite {
                        await focus.saveFocusFavorite(title: submitted.title, pomodoros: submitted.pomodoros, icon: submitted.icon).value
                    }
                    dismiss()
                }
            } else {
                let command = scene.addAndStartFocusTask(title: submitted.title, pomodoros: submitted.pomodoros,
                                                         icon: submitted.icon, isFavorite: submitted.isFavorite,
                                                         using: focus)
                if let started = command.immediateResult {
                    if started { dismiss() }
                    return
                }
                isSubmitting = true
                Task { @MainActor in
                    let started = await command.value
                    isSubmitting = false
                    guard started,
                          draftMatches(submitted) else { return }
                    dismiss()
                }
            }
            return
        } else if let existingTask {
            let target = blockStartAtMs ?? focus.focusDayCanvas().nextEmptyBlock?.startAtMs
            guard let target else { return }
            let command = focus.placeFocusTask(existingTask, pomodoros: submitted.pomodoros,
                                               startingAt: target, updatingEstimateBy: submitted.pomodoros,
                                               makeFavorite: submitted.isFavorite)
            if let result = command.immediateResult { onResult(result); dismiss(); return }
            isSubmitting = true
            Task { @MainActor in
                let result = await command.value
                isSubmitting = false
                guard draftMatches(submitted) else { return }
                onResult(result)
                dismiss()
            }
            return
        } else if let blockStartAtMs {
            let command = focus.createFocusTask(title: submitted.title, icon: submitted.icon,
                                                pomodoros: submitted.pomodoros, isFavorite: submitted.isFavorite,
                                                inBlockStartingAt: blockStartAtMs, scheduleAllPomodoros: true)
            if let result = command.immediateResult { onResult(result); dismiss(); return }
            isSubmitting = true
            Task { @MainActor in
                let result = await command.value
                isSubmitting = false
                guard draftMatches(submitted) else { return }
                onResult(result)
                dismiss()
            }
            return
        } else {
            let command = focus.createFocusTaskInNextEmptyBlock(
                title: submitted.title, pomodoros: submitted.pomodoros, icon: submitted.icon,
                isFavorite: submitted.isFavorite, scheduleAllPomodoros: true
            )
            if let result = command.immediateResult { onResult(result); dismiss(); return }
            isSubmitting = true
            Task { @MainActor in
                let result = await command.value
                isSubmitting = false
                guard draftMatches(submitted) else { return }
                onResult(result)
                dismiss()
            }
            return
        }
    }

    private func draftMatches(_ submitted: FocusTaskEditorDraft) -> Bool {
        draft.title == submitted.title && draft.icon == submitted.icon
            && draft.pomodoros == submitted.pomodoros && draft.isFavorite == submitted.isFavorite
            && draft.favoriteID == submitted.favoriteID && draft.existingTaskID == submitted.existingTaskID
    }
}

/// The title row both creation paths use, so they cannot drift apart again.
struct FocusTitleField: View {
    let focus: FocusStore
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
                accessibilityTitle: focus.t("focusTaskTitle"),
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
