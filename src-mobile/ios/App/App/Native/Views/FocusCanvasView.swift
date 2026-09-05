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

    @State private var scale: Scale = .today
    @State private var selectedBlock: Int64?
    @State private var editingBlock: FocusDayCanvasModel.Block?
    @State private var quickCreateLanding: FocusQuickCreateSheet.Landing?
    @State private var now = Date.now
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsTimerSettings = false
    @State private var editingTemplate: FocusTemplateDraft?
    @State private var notice: String?
    @State private var confirmsStop = false
    @State private var selectionFeedback = 0
    @State private var placedFeedback = 0
    @State private var warningFeedback = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var session: FocusSession? { store.activeFocusSession() }

    var body: some View {
        // Built once per pass and threaded down. Every shift snapshot is a
        // JavaScriptCore round trip through the shared rules, and the canvas
        // needs two of them plus a scan of today's sessions — as a computed
        // property this ran six times for one render.
        let model = store.focusDayCanvas(at: now)
        return VStack(spacing: 0) {
            // Pinned, so "what am I in" survives scrolling to the far end of
            // the shift. Only this band is pinned: the scale picker costs
            // another 46 pt of the band's height and is not worth it.
            FocusNowBand(
                store: store,
                model: model,
                onStop: { confirmsStop = true },
                onStart: { start($0) },
                onAdd: {
                    quickCreateLanding = store.hasFocusRoom() ? .startNow : .nextBlock
                }
            )
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 14)
            .padding(.bottom, 12)
            Divider()

            OWCContentSizedScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 14) {
                        Picker(store.t("focusScale"), selection: $scale.animation(
                            reduceMotion ? OWCMotion.reduced : OWCMotion.stateEnter
                        )) {
                            ForEach(Scale.allCases) { value in
                                Text(store.t(value == .today ? "focusScaleToday" : "focusScaleUsual"))
                                    .tag(value)
                            }
                        }
                        .pickerStyle(.segmented)

                        switch scale {
                        case .today: todayScale(model)
                        case .usual: usualScale(model)
                        }
                    }
                    .padding(.horizontal, OWCDesign.pageInset)
                    .padding(.top, 14)
                    .padding(.bottom, OWCDesign.detailBottomInset)
                    .onAppear {
                        if let block = model.currentBlock {
                            proxy.scrollTo(block.startAtMs, anchor: .top)
                        }
                    }
                    .onChange(of: selectedBlock) { _, value in
                        guard let value else { return }
                        if reduceMotion {
                            proxy.scrollTo(value, anchor: .center)
                        } else {
                            withAnimation(OWCMotion.stateEnter) { proxy.scrollTo(value, anchor: .center) }
                        }
                    }
                }
            }
        }
        .background(OWCDesign.page)
        .navigationTitle(store.t("focusTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { quickCreateLanding = .nextBlock } label: {
                    Label(store.t("focusQuickCreate"), systemImage: "plus")
                }
                .disabled(store.focusDayCanvasIsLocked)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsTimerSettings = true } label: {
                    Label(store.t("focusTimerSettings"), systemImage: "gearshape")
                }
                .accessibilityHint(store.t("focusTimerSettingsHint"))
            }
        }
        .sheet(item: $editingBlock) { block in
            FocusBlockSheet(store: store, block: block) { result in
                apply(result)
            }
        }
        .sheet(item: $quickCreateLanding) { landing in
            FocusQuickCreateSheet(store: store, initialLanding: landing) { result in apply(result) }
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
        .alert(
            notice ?? "",
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
        ) {
            Button(store.t("okAction"), role: .cancel) { notice = nil }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
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
                guard block.isEditable else { return }
                selectedBlock = block.startAtMs
                editingBlock = block
            }
            FocusTaskLedger(store: store, model: model)
        }
    }

    // MARK: - usual

    @ViewBuilder
    private func usualScale(_ model: FocusDayCanvasModel) -> some View {
        if model.isLocked {
            FocusLockedCanvas(store: store)
        } else {
            FocusUsualScale(
                store: store,
                model: model,
                onPlaceFavorite: { favorite in
                    let result = store.placeFavoriteInNextEmptyBlock(favorite)
                    // The effect belongs where the change happened: switch to
                    // the band and select the block that took it, rather than
                    // quietly adding a row further down the page.
                    if case .placed = result {
                        withAnimation(reduceMotion ? OWCMotion.reduced : OWCMotion.stateEnter) {
                            scale = .today
                        }
                    }
                    apply(result)
                },
                onEditTemplate: { editingTemplate = $0 }
            )
        }
    }

    // MARK: - actions

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
                content.padding(18)
                if session != nil, let issue = store.focusNotificationIssue {
                    notificationIssue(issue).padding(.horizontal, 18).padding(.bottom, 12)
                }
                if let session, session.plannedEndAt > .now {
                    ProgressView(timerInterval: session.startedAt...session.plannedEndAt, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear)
                    .tint(session.kind == .focus ? Color.indigo : Color.teal)
                    .frame(height: 3)
                    .labelsHidden()
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
                Button(store.t(store.hasFocusRoom() ? "focusAddAndStart" : "focusQuickCreate"), action: onAdd)
                    .buttonStyle(OWCPrimaryButtonStyle(minimumHeight: 44))
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
                    .foregroundStyle(session.kind == .focus ? Color.indigo : Color.teal)
                Text(timerInterval: session.startedAt...max(session.startedAt, session.plannedEndAt), countsDown: true)
                    .font(.title.monospacedDigit().weight(.semibold))
                    .foregroundStyle(OWCDesign.primary)
                Text(store.t("focusEndsAt", values: ["time": store.formatTime(session.plannedEndAt)]))
                    .font(.caption).foregroundStyle(OWCDesign.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(store.t("focusStop"), action: onStop)
                .buttonStyle(OWCSecondaryButtonStyle())
                .frame(minWidth: dynamicTypeSize.isAccessibilitySize ? nil : 76)
                .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
        }
    }

    private var breakOffer: some View {
        let kind: FocusSessionKind = store.focusLastNextAction == .startLongBreak ? .longBreak : .shortBreak
        return VStack(alignment: .leading, spacing: 8) {
            Text(store.t("focusPhaseComplete")).font(.headline)
            Text(store.t("focusNextBreakBody")).font(.footnote).foregroundStyle(OWCDesign.secondary)
            layout {
                Button(store.t(kind == .longBreak ? "focusStartLongBreak" : "focusStartShortBreak")) {
                    _ = store.startBreak(kind: kind)
                }
                .buttonStyle(OWCPrimaryButtonStyle(minimumHeight: 44))
                .disabled(!store.canStartFocusBreak(kind: kind))
                Button(store.t("focusSkipBreak")) { _ = store.skipSuggestedFocusBreak() }
                    .buttonStyle(OWCSecondaryButtonStyle())
            }
        }
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
                Button(store.t("focusAddAndStart"), action: onAdd)
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

    var body: some View {
        if !model.tasks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                OWCSectionHeader(title: store.t("focusTodayTasks"))
                OWCGroupCard {
                    ForEach(Array(model.tasks.enumerated()), id: \.element.id) { index, row in
                        OWCRow(
                            icon: row.icon.systemName,
                            title: row.title,
                            subtitle: subtitle(row),
                            isLast: index == model.tasks.count - 1
                        ) {
                            if let task = store.records.state.focusTasks.first(where: { $0.id == row.id }) {
                                Menu {
                                    Button(store.t("focusStartNow"), systemImage: "play.fill") {
                                        _ = store.startFocus(task: task)
                                    }
                                    .disabled(store.focusStartAvailability(task) != .ready)
                                    Button(store.t(task.isFavorite ? "focusRemoveFavorite" : "focusMakeFavorite"), systemImage: "star") {
                                        store.toggleFocusFavorite(task)
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
                            if row.isRunning {
                                Text(store.t("focusRunning"))
                                    .font(.caption)
                                    .foregroundStyle(OWCDesign.accent)
                            } else if row.isDone {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(OWCDesign.secondary)
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

/// Locked users get a shape and a sentence, never a blurred copy of the real
/// thing: the model hands this view no assignment to leak.
struct FocusLockedCanvas: View {
    let store: OffWorkStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<6, id: \.self) { index in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(OWCDesign.control)
                    .frame(height: index.isMultiple(of: 3) ? 26 : 44)
            }
            Text(store.t("focusLockedBand"))
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
                .padding(.top, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(store.t("focusLockedBand"))
    }
}
