import SwiftUI

struct FocusDesignView: View {
    let store: OffWorkStore

    @State private var title = ""
    @State private var pomodoros = 1
    @State private var icon = FocusTaskIcon.focus
    @State private var isFavorite = false
    @State private var pendingDeleteTask: FocusTask?
    @State private var confirmsStop = false
    @State private var startFeedback = 0
    @State private var addedFeedback = 0
    @State private var completedFeedback = 0
    @State private var warningFeedback = 0
    @State private var showsTimerSettings = false
    @FocusState private var taskFieldFocused: Bool
    @Environment(NotificationService.self) private var notifications
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var session: FocusSession? { store.activeFocusSession() }

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Group {
                    if let session {
                        activeCard(session)
                    } else {
                        newTaskCard
                    }
                }
                .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.stateEnter, value: session?.id)

                nextActionCard
                notificationIssueCard
                favoritesSection
                planningLink
                taskList
                overflowNotice
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 14)
        }
        .background(OWCDesign.page)
        .navigationTitle(store.t("focusTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsTimerSettings = true
                } label: {
                    Label(store.t("focusTimerSettings"), systemImage: "gearshape")
                }
                .accessibilityHint(store.t("focusTimerSettingsHint"))
            }
        }
        .sheet(isPresented: $showsTimerSettings) {
            FocusTimerSettingsSheet(store: store)
        }
        .sensoryFeedback(.selection, trigger: startFeedback)
        .sensoryFeedback(.success, trigger: addedFeedback)
        .sensoryFeedback(.success, trigger: completedFeedback)
        .sensoryFeedback(.warning, trigger: warningFeedback)
        .alert(store.t("focusStopTitle"), isPresented: $confirmsStop) {
            Button(store.t("focusStop"), role: .destructive) {
                store.stopFocus(reason: .stoppedByUser)
            }
            Button(store.t("cancel"), role: .cancel) {}
        } message: {
            Text(store.t("focusStopConfirm"))
        }
        .confirmationDialog(
            store.t("focusDeleteTaskTitle"),
            isPresented: Binding(
                get: { pendingDeleteTask != nil },
                set: { if !$0 { pendingDeleteTask = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingDeleteTask {
                Button(store.t("focusDeleteTask"), role: .destructive) {
                    _ = store.deleteFocusTask(pendingDeleteTask)
                    self.pendingDeleteTask = nil
                }
            }
            Button(store.t("cancel"), role: .cancel) { pendingDeleteTask = nil }
        } message: {
            Text(store.t("focusDeleteTaskBody"))
        }
        // The page may have been open across a suspend, so reconcile on the way
        // in rather than waiting for the next tick.
        .onAppear { store.finishElapsedFocusSession() }
    }

    // MARK: - Running

    private func activeCard(_ session: FocusSession) -> some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Label(phaseTitle(for: session), systemImage: phaseSymbol(for: session))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(session.kind == .focus ? OWCDesign.accent : OWCDesign.secondary)
                    // The task, not the word "Focus" a second time. The card
                    // used to repeat the page title and never say what was
                    // being worked on.
                    Text(session.kind == .focus ? sessionTitle(for: session) : phaseTitle(for: session))
                        .font(.title3.weight(.semibold))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, session.plannedEndAt.timeIntervalSince(context.date))
                    let total = max(1, session.plannedEndAt.timeIntervalSince(session.startedAt))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            Duration.seconds(remaining).formatted(
                            .time(pattern: .minuteSecond).locale(store.locale)
                            )
                        )
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold).monospacedDigit())
                        .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))

                        ProgressView(value: min(1, max(0, 1 - remaining / total)))
                            .tint(OWCDesign.accent)

                        Text(
                            store.t("focusEndsAt", values: ["time": store.formatTime(session.plannedEndAt)])
                        )
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(phaseTitle(for: session))
                    .accessibilityValue(store.formatRelativeDuration(remaining * 1_000))
                    .onChange(of: remaining <= 0) { _, elapsed in
                        guard elapsed else { return }
                        if store.finishElapsedFocusSession() { completedFeedback += 1 }
                    }
                }

                // Not the orange primary button. Stopping early is the opposite
                // of the action that started this, and shared styling made the
                // most destructive control on the page the most inviting one.
                Button(store.t("focusStop")) {
                    warningFeedback += 1
                    confirmsStop = true
                }
                .buttonStyle(OWCSecondaryButtonStyle())
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var nextActionCard: some View {
        if let action = visibleNextAction {
            OWCGroupCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label(store.t("focusPhaseComplete"), systemImage: "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(OWCDesign.accent)

                    Text(nextActionBody(for: action))
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    switch action {
                    case .startShortBreak:
                        Button {
                            if store.startBreak(kind: .shortBreak) { startFeedback += 1 }
                        } label: {
                            Label(store.t("focusStartShortBreak"), systemImage: "cup.and.saucer.fill")
                        }
                        .buttonStyle(OWCPrimaryButtonStyle())

                        Button(store.t("focusSkipBreak")) {
                            skipSuggestedBreak()
                        }
                        .buttonStyle(.borderless)
                        .frame(maxWidth: .infinity, minHeight: 44)
                    case .startLongBreak:
                        Button {
                            if store.startBreak(kind: .longBreak) { startFeedback += 1 }
                        } label: {
                            Label(store.t("focusStartLongBreak"), systemImage: "cup.and.saucer.fill")
                        }
                        .buttonStyle(OWCPrimaryButtonStyle())

                        Button(store.t("focusSkipBreak")) {
                            skipSuggestedBreak()
                        }
                        .buttonStyle(.borderless)
                        .frame(maxWidth: .infinity, minHeight: 44)
                    case .startNextFocus:
                        if let task = nextFocusTask {
                            Button {
                                if store.startFocus(task: task) { startFeedback += 1 }
                            } label: {
                                Label(store.t("focusStartNextFocus"), systemImage: "timer")
                            }
                            .buttonStyle(OWCPrimaryButtonStyle())
                        } else {
                            Text(store.t("focusNoNextTask"))
                                .font(.footnote)
                                .foregroundStyle(OWCDesign.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    case .none:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private var notificationIssueCard: some View {
        if let issue = store.focusNotificationIssue {
            OWCGroupCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label(store.t("focusNotificationIssue"), systemImage: "bell.badge")
                        .font(.body.weight(.semibold))
                    switch issue {
                    case .permissionDenied:
                        Text(store.t("focusNotificationPermissionDenied"))
                            .font(.footnote)
                            .foregroundStyle(OWCDesign.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(store.t("focusNotificationOpenSettings")) {
                            notifications.openSystemSettings()
                        }
                        .buttonStyle(.borderless)
                        .frame(minHeight: 44)
                    case .schedulingFailed:
                        Text(store.t("focusNotificationSchedulingFailed"))
                            .font(.footnote)
                            .foregroundStyle(OWCDesign.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(store.t("focusNotificationRetry"), action: retryNotification)
                            .buttonStyle(.borderless)
                            .frame(minHeight: 44)
                            .accessibilityHint(store.t("focusNotificationRetryHint"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private var visibleNextAction: FocusNextAction? {
        guard session == nil,
              store.focusLastNextAction != .none,
              let latestEndedSession,
              latestEndedSession.endReason == .completed
        else { return nil }
        return store.focusLastNextAction
    }

    private var latestEndedSession: FocusSession? {
        store.records.state.focusSessions
            .filter { $0.endedAt != nil }
            .max { lhs, rhs in
                let lhsDate = lhs.endedAt ?? lhs.startedAt
                let rhsDate = rhs.endedAt ?? rhs.startedAt
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private var nextFocusTask: FocusTask? {
        store.focusTasksForFocusPage().first { task in
            if case .ready = store.focusStartAvailability(task) { return true }
            return false
        }
    }

    private func nextActionBody(for action: FocusNextAction) -> String {
        switch action {
        case .startShortBreak, .startLongBreak:
            store.t("focusNextBreakBody")
        case .startNextFocus:
            store.t("focusNextFocusBody")
        case .none:
            ""
        }
    }

    private func skipSuggestedBreak() {
        _ = store.skipSuggestedFocusBreak()
    }

    private func retryNotification() {
        // Core owns the request and reports the result back through
        // `focusNotificationIssue`; the view does not claim success before
        // that state changes.
        store.retryFocusNotification()
    }

    // MARK: - Adding

    private var newTaskCard: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.t("focusTaskTitle"))
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                    taskTitleField
                }

                FocusTaskIconPicker(store: store, selection: $icon)

                Button {
                    isFavorite.toggle()
                } label: {
                    Label(
                        store.t(isFavorite ? "focusFavoriteOn" : "focusMakeFavorite"),
                        systemImage: isFavorite ? "star.fill" : "star"
                    )
                    .font(.callout.weight(.medium))
                    .foregroundStyle(isFavorite ? OWCDesign.orangeDeep : OWCDesign.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)

                // A Stepper, not a number pad. The bare field showed "1" with
                // no unit and no way to dismiss the keyboard, and nothing on
                // screen said what the number counted.
                Stepper(value: $pomodoros, in: 1...12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.t("focusPomodoros"))
                            .font(.footnote)
                            .foregroundStyle(OWCDesign.secondary)
                        Text(pomodoroSummary(pomodoros))
                            .font(.body.monospacedDigit())
                    }
                }

                Button(store.t("focusNewTask"), action: addTask)
                    .buttonStyle(OWCPrimaryButtonStyle())
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
    }

    private var taskTitleField: some View {
        HStack(spacing: 10) {
            Image(systemName: icon.systemName)
                .font(.body.weight(.medium))
                .foregroundStyle(taskFieldFocused ? OWCDesign.accent : OWCDesign.secondary)
                .accessibilityHidden(true)

            TextField(store.t("focusTaskPlaceholder"), text: $title)
                .textFieldStyle(.plain)
                .font(.body)
                .accessibilityLabel(store.t("focusTaskTitle"))
                .focused($taskFieldFocused)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .onSubmit(addTask)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
        .background(
            taskFieldFocused
                ? OWCDesign.accent.opacity(0.08)
                : OWCDesign.control,
            in: RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous)
                .strokeBorder(
                    taskFieldFocused ? OWCDesign.accent.opacity(0.72) : Color.clear,
                    lineWidth: 1.5
                )
        }
        .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.press, value: taskFieldFocused)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Today's tasks

    @ViewBuilder
    private var favoritesSection: some View {
        let favorites = store.favoriteFocusTasks()
        if !favorites.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: store.t("focusFavorites"))
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(favorites) { task in
                            Button {
                                if store.applyFavoriteFocusTask(task) != nil { addedFeedback += 1 }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: task.icon.systemName)
                                        .foregroundStyle(OWCDesign.accent)
                                    Text(task.title)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.callout.weight(.medium))
                                .foregroundStyle(OWCDesign.primary)
                                .padding(.horizontal, 13)
                                .frame(minHeight: 44)
                                .background(OWCDesign.card, in: Capsule())
                                .overlay(Capsule().strokeBorder(OWCDesign.separator, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var planningLink: some View {
        NavigationLink(value: AppRoute.focusPlan) {
            OWCGroupCard {
                OWCRow(
                    icon: "rectangle.3.group.fill",
                    title: store.t("focusPlanToday"),
                    subtitle: store.t("focusPlanTodayBody"),
                    isLast: true,
                    centersVertically: true
                ) {
                    OWCDetailAccessory(text: nil)
                }
            }
        }
        .buttonStyle(OWCRowButtonStyle())
    }

    @ViewBuilder
    private var taskList: some View {
        let tasks = store.focusTasksForFocusPage()
        if tasks.isEmpty {
            OWCGroupCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.t("focusEmptyTitle"))
                        .font(.body.weight(.medium))
                    Text(
                        store.t(
                            "focusEmptyBody",
                            values: ["minutes": store.formatCount(store.focusTimerSettings.normalized.focusMinutes)]
                        )
                    )
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: store.t("focusTitle"))
                OWCGroupCard {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        taskRow(task, isLast: index == tasks.count - 1)
                    }
                }
            }
        }
    }

    /// Planning can legitimately leave more requested work than this shift
    /// can hold. Keep that fact visible, but frame it as a gentle heads-up and
    /// leave the tasks available for the next shift rather than hiding them.
    @ViewBuilder
    private var overflowNotice: some View {
        let overflow = store.focusOverflow()
        if !overflow.isEmpty {
            OWCGroupCard {
                VStack(alignment: .leading, spacing: 6) {
                    Label(store.t("focusNoRoomThisShift"), systemImage: "info.circle")
                        .font(.body.weight(.medium))
                    Text(overflow.map(\.title).joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func taskRow(_ task: FocusTask, isLast: Bool) -> some View {
        OWCRow(
            icon: task.icon.systemName,
            title: task.title,
            subtitle: taskSubtitle(task),
            isLast: isLast,
            centersVertically: true
        ) {
            HStack(spacing: 4) {
                switch store.focusStartAvailability(task) {
            case .completed:
                Label(store.t("focusDone"), systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(OWCDesign.secondary)
            case .running:
                Text(store.t("focusRunning"))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(OWCDesign.accent)
            case .noRoom:
                Text(store.t("focusNoRoomThisShift"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            case .blockedByOther:
                Button(store.t("focusStart")) {}
                    .buttonStyle(.borderless)
                    .font(.body.weight(.semibold))
                    .disabled(true)
                    .frame(minWidth: 44, minHeight: 44)
            case .ready:
                Button(store.t("focusStart")) {
                    if store.startFocus(task: task) {
                        startFeedback += 1
                    }
                }
                .buttonStyle(.borderless)
                .font(.body.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
            case .notYetAvailable(let availableAt):
                VStack(alignment: .trailing, spacing: 2) {
                    Text(store.t("focusSchedule"))
                        .font(.footnote.weight(.medium))
                    Text(
                        store.t(
                            "focusScheduleSegment",
                            values: ["label": store.formatTime(availableAt)]
                        )
                    )
                    .font(.caption)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(OWCDesign.secondary)
            }
                Menu {
                    Button {
                        store.toggleFocusFavorite(task)
                    } label: {
                        Label(
                            store.t(task.isFavorite ? "focusRemoveFavorite" : "focusMakeFavorite"),
                            systemImage: task.isFavorite ? "star.slash" : "star"
                        )
                    }
                    Button(role: .destructive) {
                        pendingDeleteTask = task
                    } label: {
                        Label(store.t("focusDeleteTask"), systemImage: "trash")
                    }
                    .disabled(store.activeFocusSession()?.taskID == task.id)
                } label: {
                    Label(store.t("focusTaskTitle"), systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(OWCDesign.secondary)
                .accessibilityLabel(store.t("focusTaskTitle"))
            }
        }
        .contextMenu {
            Button {
                store.toggleFocusFavorite(task)
            } label: {
                Label(
                    store.t(task.isFavorite ? "focusRemoveFavorite" : "focusMakeFavorite"),
                    systemImage: task.isFavorite ? "star.slash" : "star"
                )
            }
            Button(role: .destructive) { pendingDeleteTask = task } label: {
                Label(store.t("focusDeleteTask"), systemImage: "trash")
            }
            .disabled(store.activeFocusSession()?.taskID == task.id)
        }
    }

    private func taskTitle(for session: FocusSession) -> String? {
        guard let id = session.taskID else { return nil }
        return store.records.state.focusTasks.first { $0.id == id }?.title
    }

    private func sessionTitle(for session: FocusSession) -> String {
        guard session.kind == .focus else { return phaseTitle(for: session) }
        return taskTitle(for: session) ?? store.t("focusTitle")
    }

    private func phaseTitle(for session: FocusSession) -> String {
        switch session.kind {
        case .focus: store.t("focusTitle")
        case .shortBreak: store.t("focusShortBreak")
        case .longBreak: store.t("focusLongBreak")
        }
    }

    private func phaseSymbol(for session: FocusSession) -> String {
        switch session.kind {
        case .focus: "timer"
        case .shortBreak, .longBreak: "cup.and.saucer.fill"
        }
    }

    /// Shows how many configured focus blocks the estimate represents.
    private func pomodoroSummary(_ count: Int) -> String {
        store.t(
            "focusPomodoroSummary",
            values: [
                "count": store.formatCount(count),
                "minutes": store.formatCount(store.focusTimerSettings.normalized.focusMinutes),
            ]
        )
    }

    /// Without this, `estimatedPomodoros` is stored, planned against, and never
    /// shown to the person who typed it.
    private func progressSummary(_ task: FocusTask) -> String {
        store.t(
            "focusTaskProgress",
            values: [
                "count": store.formatCount(store.completedFocusBlocks(for: task)),
                "total": store.formatCount(max(1, task.estimatedPomodoros)),
            ]
        )
    }

    private func taskSubtitle(_ task: FocusTask) -> String {
        let progress = progressSummary(task)
        guard let scheduled = task.scheduledStartAt, scheduled > .now else { return progress }
        return "\(store.formatRecordsDayTitle(scheduled)) · \(store.formatTime(scheduled)) · \(progress)"
    }

    private func addTask() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addFocusTask(
            title: trimmed,
            pomodoros: pomodoros,
            icon: icon,
            isFavorite: isFavorite
        )
        addedFeedback += 1
        title = ""
        pomodoros = 1
        icon = .focus
        isFavorite = false
        taskFieldFocused = false
    }
}

struct FocusTaskIconPicker: View {
    let store: OffWorkStore
    @Binding var selection: FocusTaskIcon

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.t("focusChooseIcon"))
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(FocusTaskIcon.allCases) { option in
                        Button {
                            selection = option
                        } label: {
                            Image(systemName: option.systemName)
                                .font(.body.weight(.medium))
                                .foregroundStyle(selection == option ? .white : OWCDesign.secondary)
                                .frame(width: 44, height: 44)
                                .background(
                                    selection == option ? OWCDesign.accent : OWCDesign.control,
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(store.t(option.titleKey))
                        .accessibilityAddTraits(selection == option ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct FocusTimerSettingsSheet: View {
    let store: OffWorkStore

    @Environment(\.dismiss) private var dismiss
    @State private var focusMinutes: Int
    @State private var shortBreakMinutes: Int
    @State private var longBreakMinutes: Int
    @State private var longBreakEvery: Int

    init(store: OffWorkStore) {
        self.store = store
        let settings = store.focusTimerSettings.normalized
        _focusMinutes = State(initialValue: settings.focusMinutes)
        _shortBreakMinutes = State(initialValue: settings.shortBreakMinutes)
        _longBreakMinutes = State(initialValue: settings.longBreakMinutes)
        _longBreakEvery = State(initialValue: settings.longBreakEvery)
    }

    private var hasSavedPlan: Bool {
        store.focusPlanning.plans.values.contains { !$0.assignments.isEmpty }
    }

    private var isLocked: Bool {
        store.activeFocusSession() != nil || hasSavedPlan
    }

    private var lockMessage: String? {
        if store.activeFocusSession() != nil {
            return store.t("focusTimerSettingsLockedRunning")
        }
        if hasSavedPlan {
            return store.t("focusTimerSettingsLockedPlan")
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(store.t("focusTimerSettingsBody"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section(store.t("focusTimerSettingsSection")) {
                    durationStepper(
                        titleKey: "focusFocusDuration",
                        value: $focusMinutes,
                        range: 10...60
                    )
                    durationStepper(
                        titleKey: "focusShortBreakDuration",
                        value: $shortBreakMinutes,
                        range: 1...15
                    )
                    durationStepper(
                        titleKey: "focusLongBreakDuration",
                        value: $longBreakMinutes,
                        range: 5...30
                    )
                    Stepper(value: $longBreakEvery, in: 2...6) {
                        LabeledContent {
                            Text(
                                store.t(
                                    "focusRoundsValue",
                                    values: ["count": store.formatCount(longBreakEvery)]
                                )
                            )
                            .monospacedDigit()
                        } label: {
                            Text(store.t("focusLongBreakEvery"))
                        }
                    }
                }
                .disabled(isLocked)

                if let lockMessage {
                    Section {
                        Label(lockMessage, systemImage: "lock.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle(store.t("focusTimerSettings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.t("cancel"), role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("saveAction"), action: save)
                        .disabled(isLocked)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func durationStepper(
        titleKey: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        Stepper(value: value, in: range) {
            LabeledContent {
                Text(
                    store.t(
                        "minutesShort",
                        values: ["count": store.formatCount(value.wrappedValue)]
                    )
                )
                .monospacedDigit()
            } label: {
                Text(store.t(titleKey))
            }
        }
    }

    private func save() {
        guard !isLocked else { return }
        store.updateFocusTimerSettings(
            FocusTimerSettings(
                focusMinutes: focusMinutes,
                shortBreakMinutes: shortBreakMinutes,
                longBreakMinutes: longBreakMinutes,
                longBreakEvery: longBreakEvery
            )
        )
        dismiss()
    }
}
