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
    @State private var showsQuickCreate = false
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
        let model = store.focusDayCanvas()
        return VStack(spacing: 0) {
            // Pinned, so "what am I in" survives scrolling to the far end of
            // the shift. Only this band is pinned: the scale picker costs
            // another 46 pt of the band's height and is not worth it.
            FocusNowBand(
                store: store,
                model: model,
                onStop: { confirmsStop = true },
                onStart: { start($0) }
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
                    .onChange(of: selectedBlock) { _, value in
                        guard let value else { return }
                        withAnimation(reduceMotion ? OWCMotion.reduced : OWCMotion.stateEnter) {
                            proxy.scrollTo(value, anchor: .center)
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
                Button { showsQuickCreate = true } label: {
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
        .sheet(isPresented: $showsQuickCreate) {
            FocusQuickCreateSheet(store: store) { result in apply(result) }
        }
        .sheet(isPresented: $showsTimerSettings) {
            FocusTimerSettingsSheet(store: store)
        }
        .sheet(item: $editingTemplate) { draft in
            FocusTemplateEditorView(store: store, draft: draft)
        }
        .alert(store.t("focusStopTitle"), isPresented: $confirmsStop) {
            Button(store.t("focusStop"), role: .destructive) {
                store.stopFocus(reason: .stoppedByUser)
            }
            Button(store.t("cancel"), role: .cancel) {}
        } message: {
            Text(store.t("focusStopConfirm"))
        }
        .alert(
            notice ?? "",
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
        ) {
            Button(store.t("okAction"), role: .cancel) { notice = nil }
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

    private func start(_ task: FocusTask?) {
        guard let task else { return }
        _ = store.startFocus(task: task)
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
    var onStart: (FocusTask?) -> Void

    private var session: FocusSession? { store.activeFocusSession() }

    var body: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 0) {
                content.padding(18)
                if let session, session.plannedEndAt > .now {
                    ProgressView(
                        timerInterval: session.startedAt...session.plannedEndAt,
                        countsDown: false
                    ) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear)
                    .tint(OWCDesign.accent)
                    .frame(height: 3)
                    .labelsHidden()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLocked {
            lockedContent
        } else if let session {
            runningContent(session)
        } else if let block = model.currentBlock, block.kind == .task {
            idleContent(block)
        } else if let next = model.blocks.first(where: { $0.state == .future && $0.kind == .task }) {
            idleContent(next)
        } else {
            Text(store.t("focusNoShift"))
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
        }
    }

    private var lockedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(store.t("focusLockedTitle"), systemImage: "lock")
                .font(.headline)
            Text(store.t("focusLockedBody"))
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
            Button(store.t("plusSeePlans")) { store.presentedRoute = .plus }
                .buttonStyle(OWCPrimaryButtonStyle(minimumHeight: 36))
                .frame(maxWidth: 160)
        }
    }

    private func runningContent(_ session: FocusSession) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(runningTitle(session))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OWCDesign.accent)
                Text(timerInterval: .now...session.plannedEndAt, countsDown: true)
                    .font(.title.monospacedDigit().weight(.semibold))
                    .foregroundStyle(OWCDesign.primary)
                // The end time, not only the countdown: this block may have
                // been cut short by lunch or clock-off, and the number alone
                // does not say that.
                Text(store.t("focusEndsAt", values: ["time": store.formatTime(session.plannedEndAt)]))
                    .font(.caption)
                    .foregroundStyle(OWCDesign.secondary)
            }
            Spacer(minLength: 8)
            Button(store.t("focusStop"), action: onStop)
                .buttonStyle(OWCSecondaryButtonStyle())
                .frame(width: 76)
        }
    }

    private func runningTitle(_ session: FocusSession) -> String {
        if session.kind != .focus { return store.t("focusOnBreak") }
        let title = session.taskID
            .flatMap { id in store.records.state.focusTasks.first(where: { $0.id == id }) }?
            .title
        return title.map { store.t("focusRunningOn", values: ["task": $0]) } ?? store.t("focusRunning")
    }

    private func idleContent(_ block: FocusDayCanvasModel.Block) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.t(block.state == .current ? "focusThisBlock" : "focusNextBlock"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                Text(block.taskTitle ?? idleDetail(block))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(block.taskTitle == nil ? OWCDesign.secondary : OWCDesign.primary)
                    .lineLimit(1)
                if block.taskTitle != nil {
                    Text(idleDetail(block))
                        .font(.caption)
                        .foregroundStyle(OWCDesign.secondary)
                } else {
                    Text(store.t("focusBandEmptyBlock"))
                        .font(.caption)
                        .foregroundStyle(OWCDesign.secondary)
                }
            }
            Spacer(minLength: 8)
            if let task = task(for: block) {
                Button {
                    onStart(task)
                } label: {
                    Label(store.t("focusStart"), systemImage: "play.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(OWCPrimaryButtonStyle(minimumHeight: 44))
                .frame(width: 92)
                .disabled(!store.hasFocusRoom())
            }
        }
    }

    /// Says where this block actually ends, because a block that starts now
    /// may be shorter than the cadence promises.
    private func idleDetail(_ block: FocusDayCanvasModel.Block) -> String {
        let start = Date(timeIntervalSince1970: Double(block.startAtMs) / 1_000)
        let end = Date(timeIntervalSince1970: Double(block.endAtMs) / 1_000)
        return "\(store.formatTime(start)) – \(store.formatTime(end))"
    }

    private func task(for block: FocusDayCanvasModel.Block) -> FocusTask? {
        block.taskID.flatMap { id in store.records.state.focusTasks.first(where: { $0.id == id }) }
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
