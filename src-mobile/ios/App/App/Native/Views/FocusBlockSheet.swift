import SwiftUI

/// Tap an empty block, make the task inside it.
///
/// New comes first on purpose. That ordering is what "block-first" means on
/// this sheet: you are not meant to scroll past a list of existing tasks to
/// find a way to create one — the block is already chosen, so naming the work
/// is the whole remaining step.
struct FocusBlockSheet: View {
    let store: OffWorkStore
    let block: FocusDayCanvasModel.Block
    var onResult: (FocusPlacementResult) -> Void

    @State private var title = ""
    @State private var icon = FocusTaskIcon.focus
    @FocusState private var titleFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var tasks: [FocusTask] { store.focusTasksForCanvas() }
    private var canCreate: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            OWCContentSizedScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 7) {
                        OWCSectionHeader(title: store.t("focusBlockWhat"))
                        FocusTitleField(
                            store: store,
                            title: $title,
                            icon: icon,
                            focused: $titleFocused,
                            placeholder: store.t("focusBlockNewPlaceholder")
                        )
                        .onSubmit(create)
                    }
                    if titleFocused || canCreate {
                        FocusTaskIconPicker(store: store, selection: $icon)
                        Button(store.t("focusBlockCreateHere"), action: create)
                            .buttonStyle(OWCPrimaryButtonStyle())
                            .disabled(!canCreate)
                    }

                    if !tasks.isEmpty {
                        OWCSectionHeader(title: store.t("focusBlockExisting"))
                        OWCGroupCard {
                            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                                Button {
                                    finish(store.assign(task, toBlockStartingAt: block.startAtMs))
                                } label: {
                                    OWCRow(
                                        icon: task.icon.systemName,
                                        title: task.title,
                                        subtitle: subtitle(task),
                                        isLast: index == tasks.count - 1
                                    ) {
                                        if block.taskID == task.id {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(OWCDesign.accent)
                                        }
                                    }
                                }
                                .buttonStyle(OWCRowButtonStyle())
                            }
                        }
                    }

                    OWCGroupCard {
                        // The only way to get a break: the cadence's own break
                        // blocks are not editable, so this is not a duplicate
                        // of something the band already offers.
                        Button {
                            store.markBlockAsBreak(startingAt: block.startAtMs)
                            finish(.placed(taskID: UUID(), blockStartAtMs: block.startAtMs))
                        } label: {
                            OWCRow(
                                icon: "cup.and.saucer.fill",
                                title: store.t("focusBlockMakeBreak"),
                                isLast: !block.hasAssignment
                            ) {
                                // Without this, "make a break" and "clear"
                                // looked like the same action: the block came
                                // back empty either way and the sheet showed
                                // no sign that a break was already set.
                                if block.isUserBreak {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(OWCDesign.accent)
                                }
                            }
                        }
                        .buttonStyle(OWCRowButtonStyle())
                        if block.hasAssignment {
                            Button {
                                store.clearBlock(startingAt: block.startAtMs)
                                dismiss()
                            } label: {
                                OWCRow(
                                    icon: "xmark.circle",
                                    title: store.t("focusBlockClear"),
                                    isLast: true,
                                    isDestructive: true
                                ) { EmptyView() }
                            }
                            .buttonStyle(OWCRowButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.top, 14)
                .padding(.bottom, OWCDesign.detailBottomInset)
            }
            .background(OWCDesign.page)
            .navigationTitle(range)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(store.t("close")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var range: String {
        let start = Date(timeIntervalSince1970: Double(block.startAtMs) / 1_000)
        let end = Date(timeIntervalSince1970: Double(block.endAtMs) / 1_000)
        return "\(store.formatTime(start)) – \(store.formatTime(end))"
    }

    private func subtitle(_ task: FocusTask) -> String? {
        let done = store.completedFocusBlocks(for: task)
        guard done > 0 else { return nil }
        return store.t("focusBlocksDone", values: ["count": "\(done)"])
    }

    private func create() {
        guard canCreate else { return }
        finish(store.createFocusTask(title: title, icon: icon, inBlockStartingAt: block.startAtMs))
    }

    private func finish(_ result: FocusPlacementResult) {
        onResult(result)
        dismiss()
    }
}

/// The secondary creation path, for when there is no block on screen to tap.
///
/// This is where the two halves finally meet: the sheet that could pick a
/// landing but hard-coded the estimate to one, and the page card that had an
/// estimate but no way to say where the task should go. The old sheet was
/// unreachable anyway — nothing ever called the flag that presented it.
struct FocusQuickCreateSheet: View {
    let store: OffWorkStore
    var onResult: (FocusPlacementResult) -> Void

    init(store: OffWorkStore, initialLanding: Landing = .nextBlock, onResult: @escaping (FocusPlacementResult) -> Void) {
        self.store = store
        self.onResult = onResult
        _landing = State(initialValue: initialLanding)
    }

    enum Landing: String, CaseIterable, Identifiable {
        case nextBlock
        case startNow
        var id: String { rawValue }
    }

    @State private var title = ""
    @State private var icon = FocusTaskIcon.focus
    @State private var pomodoros = 1
    @State private var isFavorite = false
    @State private var landing: Landing = .nextBlock
    @FocusState private var titleFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var canStart: Bool { store.activeFocusSession() == nil && store.hasFocusRoom() }
    private var nextBlock: FocusWorkBlock? { store.nextEmptyFocusBlock() }

    var body: some View {
        NavigationStack {
            OWCContentSizedScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FocusTitleField(
                        store: store,
                        title: $title,
                        icon: icon,
                        focused: $titleFocused,
                        placeholder: store.t("focusTaskPlaceholder")
                    )
                    OWCSectionHeader(title: store.t("focusLanding"))
                    OWCGroupCard {
                        landingRow(.nextBlock, icon: "calendar.badge.plus", title: nextBlockTitle)
                        landingRow(.startNow, icon: "play.fill", title: store.t("focusStartNow"), isLast: true)
                    }
                    Button(store.t(landing == .startNow ? "focusAddAndStart" : "focusSaveTask"), action: save)
                        .buttonStyle(OWCPrimaryButtonStyle())
                        .disabled(!canSave || (landing == .startNow && !canStart))
                    DisclosureGroup(store.t("moreActions")) {
                        VStack(alignment: .leading, spacing: 14) {
                            FocusTaskIconPicker(store: store, selection: $icon)

                            OWCGroupCard {
                                // The estimate lives only on this path. On the
                                // block-first path the number of blocks you place says
                                // it, so a stepper there would be a second answer to
                                // the same question.
                                OWCRow(
                                    icon: "number",
                                    title: store.t("focusEstimate"),
                                    subtitle: store.t("focusEstimateDetail", values: [
                                        "count": "\(pomodoros)",
                                        "minutes": "\(store.focusTimerSettings.normalized.focusMinutes)"
                                    ]),
                                    isLast: true
                                ) {
                                    Stepper("", value: $pomodoros, in: 1...12)
                                        .labelsHidden()
                                        .accessibilityLabel(store.t("focusEstimate"))
                                }
                            }

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
                        }.padding(.top, 12)
                    }
                }
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.top, 14)
                .padding(.bottom, OWCDesign.detailBottomInset)
            }
            .background(OWCDesign.page)
            .navigationTitle(store.t("focusNewTask"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(store.t("cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { titleFocused = true }
    }

    private var nextBlockTitle: String {
        guard let nextBlock else { return store.t("focusNoEmptyBlockShort") }
        return store.t("focusLandingNextBlock", values: ["time": store.formatTime(nextBlock.start)])
    }

    @ViewBuilder
    private func landingRow(_ value: Landing, icon: String, title: String, isLast: Bool = false) -> some View {
        Button { landing = value } label: {
            OWCRow(icon: icon, title: title, isLast: isLast) {
                if landing == value {
                    Image(systemName: "checkmark").foregroundStyle(OWCDesign.accent)
                }
            }
        }
        .buttonStyle(OWCRowButtonStyle())
        .disabled(value == .nextBlock ? nextBlock == nil : !canStart)
    }

    private func save() {
        guard canSave else { return }
        switch landing {
        case .nextBlock:
            onResult(store.createFocusTaskInNextEmptyBlock(
                title: title,
                pomodoros: pomodoros,
                icon: icon,
                isFavorite: isFavorite
            ))
        case .startNow:
            guard canStart else { return }
            store.addAndStartFocusTask(title: title, pomodoros: pomodoros, icon: icon, isFavorite: isFavorite)
        }
        dismiss()
    }
}

/// The title row both creation paths use, so they cannot drift apart again.
struct FocusTitleField: View {
    let store: OffWorkStore
    @Binding var title: String
    let icon: FocusTaskIcon
    @FocusState.Binding var focused: Bool
    let placeholder: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon.systemName)
                .foregroundStyle(focused ? OWCDesign.accent : OWCDesign.secondary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $title)
                .textFieldStyle(.plain)
                .font(.body)
                .accessibilityLabel(store.t("focusTaskTitle"))
                .focused($focused)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
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
