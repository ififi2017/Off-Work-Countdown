import SwiftUI

/// The focus canvas: one page, three scales.
///
/// It replaces the pair of pages this feature used to be. Putting a task in a
/// block took four levels and, if the task did not exist yet, the fourth level
/// sent you back two to make it. Creation and placement are the same action
/// here, so it takes two.
///
/// Each scale answers exactly one question. Now: what am I in, how long is
/// left, what happens after. Today: does this shift hold what I want to do.
/// Usual: what does an ordinary day of mine look like.
struct FocusCanvasView: View {
    let store: OffWorkStore

    enum Scale: String, CaseIterable, Identifiable {
        case today
        case usual
        var id: String { rawValue }
    }

    @State private var scale: Scale = {
#if DEBUG
        Scale(rawValue: UserDefaults.standard.string(forKey: "ios.native.qaFocusScale") ?? "") ?? .today
#else
        .today
#endif
    }()
    @State private var selectedBlock: Int64?
    @State private var editingBlock: FocusDayCanvasModel.Block?
    @State private var editingTask: FocusTask?
    @State private var confirmsClearDay = false
    @State private var namesDayTemplate = false
    @State private var dayTemplateName = ""
    @State private var favoriteToCreate: FocusTask?
    @State private var quickCreateLanding: FocusQuickCreateSheet.Landing?
    @State private var now = Date.now
    @State private var scrollPosition = ScrollPosition()
    @State private var bandTop: CGFloat?
    @State private var needsCurrentPosition = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsTimerSettings = false
    @State private var editingTemplate: FocusTemplateDraft?
    @State private var notice: String?
    @State private var confirmsStop = false
    @State private var taskToExtend: UUID?
    @State private var selectionFeedback = 0
    @State private var placedFeedback = 0
    @State private var warningFeedback = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var session: FocusSession? { store.activeFocusSession() }

    var body: some View {
        // Built once per pass and threaded down. Every shift snapshot is a
        // JavaScriptCore round trip through the shared rules, and the canvas
        // needs two of them plus a scan of today's sessions — as a computed
        // property this ran six times for one render.
        let model = store.focusDayCanvas(at: now)
        return VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                Picker(store.t("focusScale"), selection: $scale) {
                    ForEach(Scale.allCases) { value in
                        Text(store.t(value == .today ? "focusScaleToday" : "focusScaleUsual"))
                            .tag(value)
                    }
                }
                .pickerStyle(.segmented)

                FocusNowBand(
                    store: store,
                    model: model,
                    now: now,
                    onExtend: extend,
                    onStop: { confirmsStop = true },
                    onStart: { start($0) },
                    onAdd: {
                        quickCreateLanding = .currentOrNextBlock
                    }
                )
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 14) {
                            switch scale {
                            case .today: todayScale(model)
                            case .usual: usualScale(model)
                            }
                        }
                        // Match Records: only the selected canvas cross-fades.
                        // The status card and picker keep their position and identity.
                        .id(scale)
                        .transition(.opacity)
                        .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.recordsScaleChange, value: scale)
                    }
                    .padding(.horizontal, OWCDesign.pageInset)
                    .padding(.top, 8)
                    .padding(.bottom, OWCDesign.detailBottomInset)
                    .coordinateSpace(.named("focus-content"))
                }
                .scrollPosition($scrollPosition)
                .scrollIndicators(.hidden)
                .onChange(of: store.selectedTab, initial: true) { _, tab in
                    if tab == .focus {
                        needsCurrentPosition = true
                        scrollToNow(model, proxy: proxy)
                    }
                }
                .onChange(of: scale) {
                    needsCurrentPosition = true
                    scrollToNow(model, proxy: proxy)
                }
                .onChange(of: bandTop) { scrollToNow(model, proxy: proxy) }
                .onChange(of: now) { scrollToNow(model, proxy: proxy) }
                .onChange(of: scenePhase) {
                    if scenePhase == .active, store.selectedTab == .focus {
                        needsCurrentPosition = true
                        scrollToNow(store.focusDayCanvas(), proxy: proxy)
                    }
                }
                .onChange(of: selectedBlock) { _, value in
                    guard let value else { return }
                    needsCurrentPosition = false
                    let position = {
                        if dynamicTypeSize.isAccessibilitySize {
                            proxy.scrollTo(value, anchor: .center)
                        } else if let bandTop {
                            scrollPosition.scrollTo(y: max(0, bandTop + model.offset(ofMs: value) - 8))
                        }
                    }
                    if reduceMotion { position() }
                    else { withAnimation(OWCMotion.stateEnter, position) }
                }
            }
        }
        .background(OWCDesign.page)
        .navigationTitle(store.t("focusTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                quickCreateButton
            }
            ToolbarItem(placement: .topBarTrailing) {
                timerSettingsButton
            }
        }
        .owcTabletDetailNavigation(
            backTitle: store.t("timerTab"),
            pageTitle: store.t("focusTitle")
        ) {
            quickCreateButton.owcTabletGlassAction()
            timerSettingsButton.owcTabletGlassAction()
        }
        .sheet(item: $editingBlock) { block in
            FocusBlockSheet(store: store, block: block) { result in
                apply(result)
            }
        }
        .sheet(item: $editingTask) { task in
            FocusTaskEditSheet(store: store, task: task)
        }
        .alert(store.t("focusClearDayTasks"), isPresented: $confirmsClearDay) {
            Button(store.t("focusClearDayTasks"), role: .destructive) { store.clearFocusDay(at: now) }
            Button(store.t("cancel"), role: .cancel) {}
        } message: {
            Text(store.t("focusClearDayTasksBody"))
        }
        .alert(store.t("focusSaveDayAsTemplate"), isPresented: $namesDayTemplate) {
            TextField(store.t("focusUsualDayName"), text: $dayTemplateName)
            Button(store.t("saveAction")) {
                _ = store.saveFocusTemplate(name: dayTemplateName, slots: store.focusTemplateDraftFromToday(at: now))
            }.disabled(dayTemplateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(store.t("cancel"), role: .cancel) {}
        }
        .sheet(item: $quickCreateLanding) { landing in
            FocusQuickCreateSheet(store: store, initialLanding: landing) { result in apply(result) }
        }
        .sheet(item: $favoriteToCreate) { favorite in
            FocusQuickCreateSheet(store: store, initialLanding: .currentOrNextBlock, favorite: favorite) { result in
                if case .placed = result { scale = .today }
                apply(result)
            }
        }
        .sheet(isPresented: $showsTimerSettings) {
            FocusTimerSettingsSheet(store: store)
        }
        .sheet(item: $editingTemplate) { draft in
            FocusTemplateEditorView(store: store, draft: draft)
        }
        .alert(store.t(session?.kind == .focus ? "focusStopTitle" : "focusEndBreakTitle"), isPresented: $confirmsStop) {
            Button(store.t("focusStop"), role: .destructive) {
                store.stopFocus(reason: .stoppedByUser)
            }
            Button(store.t("cancel"), role: .cancel) {}
        } message: {
            Text(store.t(session?.kind == .focus ? "focusStopConfirm" : "focusEndBreakBody"))
        }
        .alert(store.t("focusExtendOne"), isPresented: Binding(
            get: { taskToExtend != nil },
            set: { if !$0 { taskToExtend = nil } }
        ), presenting: taskToExtend) { taskID in
            Button(store.t("focusSaveTask")) { confirmExtension(taskID) }
            Button(store.t("cancel"), role: .cancel) {}
        } message: { taskID in
            Text(store.records.state.focusTasks.first(where: { $0.id == taskID })?.title ?? store.t("focusTaskTitle"))
        }
        .alert(
            notice ?? "",
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
        ) {
            Button(store.t("okAction"), role: .cancel) { notice = nil }
        }
        .task(id: scenePhase == .active && store.selectedTab == .focus) {
            guard scenePhase == .active, store.selectedTab == .focus else { return }
            store.writeQASurfaceMarker("route.focus")
            while !Task.isCancelled {
                now = .now
                _ = store.finishElapsedFocusSession(at: now)
                // Refresh the whole canvas only on a minute or a block boundary.
                // Timer Text/ProgressView animate their own seconds independently.
                let canvas = store.focusDayCanvas(at: now)
                let nextMinute = Date(timeIntervalSince1970: (floor(now.timeIntervalSince1970 / 60) + 1) * 60)
                let boundary = canvas.blocks.flatMap { [$0.startAtMs, $0.endAtMs] }
                    .map { Date(timeIntervalSince1970: Double($0) / 1_000) }
                    .filter { $0 > now }.min() ?? nextMinute
                let wake = min(boundary, nextMinute, session?.plannedEndAt ?? nextMinute)
                do { try await Task.sleep(for: .seconds(max(0.1, wake.timeIntervalSinceNow))) }
                catch { return }
            }
        }
        .sensoryFeedback(.selection, trigger: selectionFeedback)
        .sensoryFeedback(.success, trigger: placedFeedback)
        .sensoryFeedback(.warning, trigger: warningFeedback)
    }

    private var quickCreateButton: some View {
        Button { quickCreateLanding = .nextBlock } label: {
            Label(store.t("focusQuickCreate"), systemImage: "plus")
        }
        .disabled(store.focusDayCanvasIsLocked)
    }

    private func scrollToNow(_ model: FocusDayCanvasModel, proxy: ScrollViewProxy) {
        guard needsCurrentPosition, scale == .today, !model.isLocked,
              let nowAtMs = model.nowAtMs, let bandTop else { return }
        // Start at the current block's top so its title and full interval remain visible.
        // Only entry repositions the page;
        // clock ticks must never pull it away from a task the user is reading.
        if dynamicTypeSize.isAccessibilitySize {
            if let block = model.blocks.first(where: { $0.endAtMs > nowAtMs }) {
                proxy.scrollTo(block.startAtMs, anchor: .top)
            }
        } else {
            let block = model.blocks.first { $0.startAtMs <= nowAtMs && nowAtMs < $0.endAtMs }
            let start = block?.startAtMs ?? nowAtMs
            scrollPosition.scrollTo(y: max(0, bandTop + model.offset(ofMs: start) - 8))
        }
        needsCurrentPosition = false
    }

    private var timerSettingsButton: some View {
        Button { showsTimerSettings = true } label: {
            Label(store.t("focusTimerSettings"), systemImage: "gearshape")
        }
        .accessibilityHint(store.t("focusTimerSettingsHint"))
    }

    // MARK: - today

    @ViewBuilder
    private func todayScale(_ model: FocusDayCanvasModel) -> some View {
        if model.isLocked {
            FocusLockedCanvas(store: store)
        } else if model.isEmpty {
            Text(store.t("focusNoShift"))
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 24)
        } else {
            if model.isNextShift {
                Text(store.t("focusBandNextShift", values: [
                    "day": store.formatRecordsDayTitle(Date(timeIntervalSince1970: Double(model.shiftStartAtMs) / 1_000))
                ]))
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
            }
            FocusBandView(store: store, model: model, selectedBlock: $selectedBlock) { block in
                guard block.isEditable || block.isAssigned else { return }
                selectedBlock = block.startAtMs
                editingBlock = block
            }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("focus-content")).minY } action: {
                bandTop = $0
            }
            FocusTaskLedger(store: store, model: model, onExtend: extend, onEdit: { editingTask = $0 })
            if !model.tasks.isEmpty || model.blocks.contains(where: \.hasAssignment) {
                VStack(spacing: 10) {
                    if store.appliedFocusTemplate(at: now) == nil, model.blocks.contains(where: \.hasAssignment) {
                        Button(store.t("focusSaveDayAsTemplate")) {
                            dayTemplateName = store.t("focusUsualDayDefaultName")
                            namesDayTemplate = true
                        }.buttonStyle(OWCSecondaryButtonStyle())
                    }
                    Button(store.t("focusClearDayTasks"), role: .destructive) { confirmsClearDay = true }
                        .buttonStyle(OWCSecondaryButtonStyle())
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - usual

    @ViewBuilder
    private func usualScale(_ model: FocusDayCanvasModel) -> some View {
        if model.isLocked {
            FocusLockedUsualScale(store: store)
        } else {
            FocusUsualScale(
                store: store,
                model: model,
                onPlaceFavorite: { favoriteToCreate = $0 },
                onEditTemplate: { editingTemplate = $0 }
            )
        }
    }

    // MARK: - actions

    private func extend(_ taskID: UUID) {
        if let session = store.activeFocusSession(),
           session.kind == .focus, session.taskID == taskID {
            store.requestFocusActivityConfirmation(
                .addPomodoros,
                startAtMs: Int64(session.startedAt.timeIntervalSince1970 * 1_000)
            )
            return
        }
        taskToExtend = taskID
    }

    private func confirmExtension(_ taskID: UUID) {
        switch store.addOneFocusBlock(taskID: taskID) {
        case .success(let start):
            scale = .today
            apply(.placed(taskID: taskID, blockStartAtMs: start))
            notice = store.t("focusExtendScheduled", values: [
                "time": store.formatTime(Date(timeIntervalSince1970: Double(start) / 1_000))
            ])
        case .failure(let error):
            notice = store.t(error == .conflict ? "focusExtendConflict" : "focusExtendNoRoom")
            warningFeedback &+= 1
        }
    }

    private func start(_ block: FocusDayCanvasModel.Block) {
        guard let task = store.records.state.focusTasks.first(where: { $0.id == block.taskID }),
              store.startFocus(task: task, inBlockStartingAt: block.startAtMs)
        else { now = .now; return }
        selectionFeedback &+= 1
    }

    private func apply(_ result: FocusPlacementResult) {
        switch result {
        case .placed(_, let blockStartAtMs):
            selectedBlock = blockStartAtMs
            placedFeedback &+= 1
        case .addedUnscheduled:
            // Not a failure and not a silent drop: the task exists, this shift
            // just has no room for it.
            notice = store.t("focusNoEmptyBlock")
            warningFeedback &+= 1
        case .noShift:
            notice = store.t("focusNoShift")
            warningFeedback &+= 1
        case .locked:
            break
        }
    }
}

/// The one conclusion at the top of the page: running, just finished, or the
/// block you are in.
struct FocusNowBand: View {
    let store: OffWorkStore
    let model: FocusDayCanvasModel
    let now: Date
    var onExtend: (UUID) -> Void
    var onStop: () -> Void
    var onStart: (FocusDayCanvasModel.Block) -> Void
    var onAdd: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL
    @State private var showsNotificationIssue = false

    private var session: FocusSession? { store.activeFocusSession() }
    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    }

    var body: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 0) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                if let template = store.appliedFocusTemplate(at: now), !model.isLocked {
                    Text(store.t("focusAppliedTemplateNote", values: ["name": template.name]))
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                }
                if session != nil, let issue = store.focusNotificationIssue {
                    notificationIssue(issue).padding(.horizontal, 18).padding(.bottom, 12)
                }
                if let session, session.plannedEndAt > .now {
                    ProgressView(timerInterval: session.startedAt...session.plannedEndAt, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear)
                    .tint(session.kind == .focus ? OWCDesign.accent : OWCDesign.recordsBreak)
                    .labelsHidden()
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLocked {
            VStack(alignment: .leading, spacing: 8) {
                Label(store.t("focusLockedTitle"), systemImage: "lock").font(.headline)
                Text(store.t("focusLockedBody")).font(.footnote).foregroundStyle(OWCDesign.secondary)
                Button(store.t("plusSeePlans")) { store.presentedRoute = .plus }
                    .buttonStyle(OWCPrimaryButtonStyle(minimumHeight: 36))
            }
        } else if let session {
            runningContent(session)
        } else if store.focusDayComplete(at: now) {
            completedContent
        } else if now.timeIntervalSince1970 * 1_000 < Double(model.shiftStartAtMs) {
            VStack(alignment: .leading, spacing: 8) {
                if let first = model.blocks.first(where: { $0.isAssigned && !$0.isUserBreak }) {
                    Text(first.taskTitle ?? store.t("focusTitle"))
                        .font(.headline)
                    let start = Date(timeIntervalSince1970: Double(first.startAtMs) / 1_000)
                    Text(timerInterval: now...max(now, start), countsDown: true)
                        .font(.title.monospacedDigit().weight(.semibold))
                    Label(range(first), systemImage: "clock")
                        .font(.footnote).foregroundStyle(OWCDesign.secondary)
                } else {
                    Text(store.t("focusBandEmptyBlock"))
                        .font(.headline).foregroundStyle(OWCDesign.secondary)
                }
            }
        } else if store.focusLastNextAction == .startShortBreak || store.focusLastNextAction == .startLongBreak {
            breakOffer
        } else if let block = model.currentBlock, block.kind == .task, !block.isUserBreak {
            idleContent(block)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(store.t(store.focusLastNextAction == .startNextFocus ? "focusStartNextFocus" : "focusTitle"))
                    .font(.headline)
                if let next = model.blocks.first(where: { $0.state == .future && $0.kind == .task && !$0.isUserBreak }) {
                    Text(next.taskTitle.map { "\($0) · \(range(next))" } ?? range(next))
                        .font(.footnote).foregroundStyle(OWCDesign.secondary)
                } else {
                    Text(store.t("focusNoShift")).font(.footnote).foregroundStyle(OWCDesign.secondary)
                }
                Button(store.t("focusQuickCreate"), action: onAdd)
                    .buttonStyle(OWCPrimaryButtonStyle(filled: false, minimumHeight: 44))
            }
        }
    }

    private func runningContent(_ session: FocusSession) -> some View {
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(runningTitle(session))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(session.kind == .focus ? OWCDesign.accent : OWCDesign.recordsBreak)
                Text(timerInterval: session.startedAt...max(session.startedAt, session.plannedEndAt), countsDown: true)
                    .font(.title.monospacedDigit().weight(.semibold))
                    .foregroundStyle(OWCDesign.primary)
                Text(store.t("focusEndsAt", values: ["time": store.formatTime(session.plannedEndAt)]))
                    .font(.caption).foregroundStyle(OWCDesign.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                if let taskID = store.focusContinuationTaskID() {
                    Button(store.t("focusExtendOne"), systemImage: "plus") { onExtend(taskID) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(OWCSecondaryButtonStyle())
                        .frame(width: 50)
                        .help(store.t("focusExtendOne"))
                }
                Button(store.t("focusStop"), systemImage: "stop.fill", action: onStop)
                    .labelStyle(.iconOnly)
                    .buttonStyle(OWCSecondaryButtonStyle())
                    .frame(width: 50)
                    .help(store.t("focusStop"))
            }
        }
    }

    private var completedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.t("focusCompletedTasksTitle")).font(.headline)
            quickAddButton
        }
    }

    private var breakOffer: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Unfinished tasks must not be described as a completed day.
            Text(store.t("focusTitle")).font(.headline)
            quickAddButton
        }
    }

    private var quickAddButton: some View {
        Button(store.t("focusQuickCreate"), action: onAdd)
            .buttonStyle(OWCPrimaryButtonStyle(minimumHeight: 44))
    }

    private func notificationIssue(_ issue: FocusNotificationIssue) -> some View {
        Button { showsNotificationIssue = true } label: {
            Label(store.t("focusNotificationIssue"), systemImage: "bell.badge")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .alert(store.t("focusTitle"), isPresented: $showsNotificationIssue) {
            if issue == .permissionDenied {
                Button(store.t("focusNotificationOpenSettings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } else {
                Button(store.t("focusNotificationRetry")) { store.retryFocusNotification() }
            }
            Button(store.t("cancel"), role: .cancel) {}
        } message: {
            Text(store.t(issue == .permissionDenied ? "focusNotificationPermissionDenied" : "focusNotificationIssue"))
        }
    }

    private func runningTitle(_ session: FocusSession) -> String {
        if session.kind != .focus { return store.t(session.kind == .shortBreak ? "focusShortBreak" : "focusLongBreak") }
        let title = session.taskID.flatMap { id in store.records.state.focusTasks.first(where: { $0.id == id }) }?.title
        return title ?? store.t("focusRunning")
    }

    private func idleContent(_ block: FocusDayCanvasModel.Block) -> some View {
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.t(store.focusLastNextAction == .startNextFocus ? "focusStartNextFocus" : "focusThisBlock")).font(.footnote).foregroundStyle(OWCDesign.secondary)
                Text(block.taskTitle ?? range(block))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(OWCDesign.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(block.taskTitle == nil ? store.t("focusBandEmptyBlock") : range(block))
                    .font(.caption).foregroundStyle(OWCDesign.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let task = store.records.state.focusTasks.first(where: { $0.id == block.taskID }) {
                Button(store.t("focusStart"), systemImage: "play.fill") { onStart(block) }
                    .buttonStyle(OWCPrimaryButtonStyle(minimumHeight: 44))
                    .frame(minWidth: dynamicTypeSize.isAccessibilitySize ? nil : 92)
                    .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
                    .disabled(store.focusStartAvailability(task) != .ready || Double(block.endAtMs) / 1_000 - Date.now.timeIntervalSince1970 < 60)
            } else {
                Button(store.t("focusQuickCreate"), action: onAdd)
                    .buttonStyle(OWCPrimaryButtonStyle(minimumHeight: 44))
                    .frame(minWidth: dynamicTypeSize.isAccessibilitySize ? nil : 112)
                    .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
                    .disabled(!store.hasFocusRoom())
            }
        }
    }

    private func range(_ block: FocusDayCanvasModel.Block) -> String {
        let start = Date(timeIntervalSince1970: Double(block.startAtMs) / 1_000)
        let end = Date(timeIntervalSince1970: Double(block.endAtMs) / 1_000)
        return "\(store.formatTime(start)) – \(store.formatTime(end))"
    }
}

/// The explanation under the band. Progress is "done of scheduled" — what you
/// drew — while the estimate stays what you intended.
struct FocusTaskLedger: View {
    let store: OffWorkStore
    let model: FocusDayCanvasModel
    var onExtend: (UUID) -> Void
    var onEdit: (FocusTask) -> Void

    var body: some View {
        if !model.tasks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                OWCSectionHeader(title: store.t("focusTodayTasks"))
                OWCGroupCard {
                    ForEach(Array(model.tasks.enumerated()), id: \.element.id) { index, row in
                        OWCRow(
                            icon: store.savedFocusFavorite(title: row.title, icon: row.icon) != nil ? "star.fill" : row.icon.systemName,
                            title: row.title,
                            subtitle: subtitle(row),
                            isLast: index == model.tasks.count - 1,
                            centersVertically: true
                        ) {
                            HStack(spacing: 8) {
                                if row.isRunning {
                                    Text(store.t("focusRunning"))
                                        .font(.caption)
                                        .foregroundStyle(OWCDesign.accent)
                                } else if row.isDone {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(OWCDesign.secondary)
                                }
                                if let task = store.records.state.focusTasks.first(where: { $0.id == row.id }) {
                                    let favorite = store.savedFocusFavorite(title: task.title, icon: task.icon)
                                    Menu {
                                        Button(store.t("focusEditTask"), systemImage: "pencil") { onEdit(task) }
                                        Button(store.t("focusStartNow"), systemImage: "play.fill") {
                                            _ = store.startFocus(task: task)
                                        }
                                        .disabled(store.focusStartAvailability(task) != .ready)
                                        Button(store.t("focusExtendOne"), systemImage: "plus") {
                                            onExtend(task.id)
                                        }
                                        Button(store.t(favorite != nil ? "focusRemoveFavorite" : "focusMakeFavorite"), systemImage: favorite != nil ? "star.fill" : "star") {
                                            store.toggleFocusFavorite(favorite ?? task)
                                        }
                                        Button(store.t("focusDeleteTask"), systemImage: "trash", role: .destructive) {
                                            _ = store.deleteFocusTask(task)
                                        }
                                        .disabled(row.isRunning)
                                    } label: {
                                        Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
                                    }
                                    .accessibilityLabel(store.t("moreActions") + " · " + row.title)
                                }
                            }
                        }
                    }
                }
                if !model.overflow.isEmpty {
                    Text(store.t("focusOverflowNote", values: [
                        "tasks": model.overflow.map(\.title).joined(separator: "、")
                    ]))
                    .font(.caption)
                    .foregroundStyle(OWCDesign.secondary)
                    .padding(.horizontal, 6)
                    .padding(.top, 2)
                }
            }
        }
    }

    private func subtitle(_ row: FocusDayCanvasModel.TaskRow) -> String {
        guard row.isScheduled else { return store.t("focusUnscheduled") }
        return store.t("focusBlocksDoneOfScheduled", values: [
            "done": "\(row.completedBlocks)",
            "total": "\(row.assignedBlocks)"
        ])
    }
}

/// A fixed, synthetic plan previews the real canvas without reading or saving
/// any of the user's locked assignments.
struct FocusLockedCanvas: View {
    let store: OffWorkStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(store.t("focusLockedBand"))
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
            FocusBandView(store: store, model: demoModel, selectedBlock: .constant(nil), isPreview: true) { _ in
                store.presentedRoute = .plus
            }
        }
    }

    private var demoModel: FocusDayCanvasModel {
        let start = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 0))
            .addingTimeInterval(9 * 3_600)
        let startMs = Int64(start.timeIntervalSince1970 * 1_000)
        // Fixed sample times, not a second implementation of the shift planner.
        let samples: [(Int, Int, String?, FocusTaskIcon?)] = [
            (0, 25, "focusDemoWriting", .writing),
            (25, 30, nil, nil),
            (30, 55, "focusDemoWriting", .writing),
            (55, 60, nil, nil),
            (60, 85, "focusDemoMessages", .communication),
            (85, 90, nil, nil),
            (90, 115, "focusDemoLearning", .study),
            (115, 130, nil, nil)
        ]
        var model = FocusDayCanvasModel.empty
        model.shiftStartAtMs = startMs
        model.shiftEndAtMs = startMs + 130 * 60_000
        model.blocks = samples.enumerated().map { index, sample in
            FocusDayCanvasModel.Block(
                index: index,
                startAtMs: startMs + Int64(sample.0) * 60_000,
                endAtMs: startMs + Int64(sample.1) * 60_000,
                kind: sample.2 == nil ? .breakTime : .task,
                state: .future,
                taskID: sample.2 == nil ? nil : UUID(uuidString: "00000000-0000-0000-0000-000000000001"),
                taskTitle: sample.2.map { store.t($0) },
                taskIcon: sample.3
            )
        }
        return model
    }
}
