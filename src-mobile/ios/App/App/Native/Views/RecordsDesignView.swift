import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RecordsDesignView: View {
    let store: OffWorkStore
    let showsSidebarButton: Bool
    let usesOwnHeader: Bool
    let showSidebar: () -> Void
    let onExpansionChanged: (Bool) -> Void
    @State private var scale: RecordsScale
    @State private var anchor = Date()
    @State private var selectedDayKey: String?
    @State private var quickDay: RecordsDayIdentified?
    @State private var selectedYearMonth: Int?
    @State private var selectedLifeStageID: String?
    @State private var yearCalloutMonth: Int?
    @State private var yearSelectionDate: Date?
    @State private var lifeSelectionDate: Date?
    @State private var days: [DayResolution] = []
    @State private var cells: [RecordsDayCell] = []
    @State private var summary: RecordsHeadlineSummary?
    @State private var lifeModel: LifeViewModel?
    @State private var lifeAllocationRequested = false
    @State private var lifeProjectionSignature: RecordsLoadSignature?
    @State private var expanded: [RecordsScale: Bool]
    @State private var pinch: CGFloat = 1
    @State private var scaleFeedback = 0
    @State private var selectionFeedback = 0
    @State private var showsLifeEditor = false
    @State private var confirmsQuarantine = false
    @State private var loadGeneration = 0
    @State private var loadedSignature: RecordsLoadSignature?
    @State private var showsCompactRootBar = false
    @State private var canvasWidth: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExpanded: Bool { expanded[scale] == true }
    private var canExpand: Bool { scale == .year || scale == .life }
    /// iPad keeps its custom root chrome so switching split-view tabs cannot
    /// resize the detail pane under a cross-fade. Phones use the system bar.
    private var usesCustomRootHeader: Bool { usesOwnHeader }

    init(
        store: OffWorkStore,
        showsSidebarButton: Bool = false,
        usesOwnHeader: Bool = false,
        showSidebar: @escaping () -> Void = {},
        onExpansionChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.store = store
        self.showsSidebarButton = showsSidebarButton
        self.usesOwnHeader = usesOwnHeader
        self.showSidebar = showSidebar
        self.onExpansionChanged = onExpansionChanged
#if DEBUG
        let requested = RecordsScale(
            rawValue: UserDefaults.standard.string(forKey: "ios.native.qaRecordsScale") ?? ""
        ) ?? .month
        let startsExpanded = UserDefaults.standard.bool(forKey: "ios.native.qaRecordsExpanded")
            && (requested == .year || requested == .life)
        _scale = State(initialValue: requested)
        _expanded = State(initialValue: startsExpanded ? [requested: true] : [:])
#else
        _scale = State(initialValue: .month)
        _expanded = State(initialValue: [:])
#endif
    }

    var body: some View {
        Group {
            if store.records.archiveBanner == .damaged {
                damagedState
            } else if isExpanded {
                immersiveCanvas
            } else {
                regularCanvas
            }
        }
        .background(OWCDesign.page)
        .owcNavigationTitle(
            store.t("recordsTitle"),
            displayMode: .large,
            isActive: store.selectedTab == .records && !isExpanded && !usesCustomRootHeader
        )
        // Expansion is a contained browsing mode. The calendar remains inside
        // the same navigation stack, but the surrounding tab and navigation
        // chrome must get out of the way so the canvas can use the available
        // width and height on both phones and iPad split panes.
        .toolbar(isExpanded || usesCustomRootHeader ? .hidden : .visible, for: .navigationBar)
        .toolbar(isExpanded ? .hidden : .visible, for: .tabBar)
        .navigationDestination(for: RecordsRoute.self) { route in
            recordsDestination(route)
        }
        .navigationDestination(item: $quickDay) { item in
            RecordsDayCanvasView(store: store, dayKey: item.dayKey)
                .onAppear { store.writeQASurfaceMarker("records.day") }
        }
        .sheet(item: Binding(
            get: { store.editingDayKey.map(RecordsDayIdentified.init) },
            set: { store.editingDayKey = $0?.dayKey }
        )) { item in
            NavigationStack {
                RecordDayEditView(store: store, dayKey: item.dayKey)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsLifeEditor) {
            LifeProfileEditView(store: store)
        }
        .toolbar { recordsToolbar }
        .overlay(alignment: .top) {
            if usesCustomRootHeader, showsCompactRootBar, !isExpanded {
                compactRecordsBar
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .task(id: scenePhase == .active && store.selectedTab == .records) {
            guard scenePhase == .active, store.selectedTab == .records else { return }
            // A minute-level check catches midnight while browsing. Returning
            // from Home refreshes immediately, without resetting the selection.
            while !Task.isCancelled {
                if loadedSignature != currentLoadSignature {
                    await load()
                }
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
            }
        }
        .onChange(of: isExpanded, initial: true) { _, expanded in
            onExpansionChanged(expanded)
        }
        .onDisappear {
            onExpansionChanged(false)
        }
        .onChange(of: store.records.revision) { _, _ in
            guard scenePhase == .active, store.selectedTab == .records else { return }
            Task { await load() }
        }
        .onChange(of: store.plus.isAuthorized) { _, _ in
            guard scenePhase == .active, store.selectedTab == .records else { return }
            Task { await load() }
        }
        .sensoryFeedback(.selection, trigger: scaleFeedback)
        .sensoryFeedback(.selection, trigger: selectionFeedback)
        .confirmationDialog(
            store.t("recordsArchiveQuarantineConfirm"),
            isPresented: $confirmsQuarantine,
            titleVisibility: .visible
        ) {
            Button(store.t("recordsArchiveQuarantine")) {
                _ = try? store.records.quarantineCorruptedArchive()
            }
            Button(store.t("cancel"), role: .cancel) {}
        }
    }

    private var regularCanvas: some View {
        Group {
            if canvasWidth >= Self.twoColumnMinimum && !dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 14) {
                    if usesCustomRootHeader {
                        recordsRootHeader
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        if let banner = store.records.archiveBanner {
                            archiveBannerCard(banner)
                        }
                        RecordsScalePicker(store: store, scale: scaleBinding)
                        HStack(alignment: .top, spacing: 14) {
                            ScrollView {
                                visualization(expandedPresentation: false)
                                    .padding(.bottom, OWCDesign.detailBottomInset)
                            }
                            .accessibilityIdentifier("records.visualizationScroll")
                            ScrollView {
                                conclusionColumn
                                    .padding(.bottom, OWCDesign.detailBottomInset)
                            }
                            .frame(maxWidth: Self.conclusionColumnWidth)
                            .accessibilityIdentifier("records.conclusionScroll")
                        }
                    }
                    .padding(.horizontal, OWCDesign.pageInset)
                }
                .padding(.top, usesCustomRootHeader ? 0 : 12)
            } else {
                singleColumnCanvas
            }
        }
        .scrollIndicators(.hidden)
        .coordinateSpace(.named("recordsRootScroll"))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { canvasWidth = $0 }
    }

    private var singleColumnCanvas: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if usesCustomRootHeader {
                    recordsRootHeader
                }

                VStack(alignment: .leading, spacing: 14) {
                    if let banner = store.records.archiveBanner {
                        archiveBannerCard(banner)
                    }

                    RecordsScalePicker(store: store, scale: scaleBinding)

                    visualization(expandedPresentation: false)
                    conclusionColumn
                }
                .padding(.horizontal, OWCDesign.pageInset)
            }
            .padding(.top, usesCustomRootHeader ? 0 : 12)
            .padding(.bottom, OWCDesign.detailBottomInset)
        }
#if DEBUG
        .defaultScrollAnchor(
            UserDefaults.standard.bool(forKey: "ios.native.qaRecordsBottom") ? .bottom : .top
        )
#endif
    }

    /// Measured, not guessed from the device: the same iPad is wide with the
    /// sidebar hidden and narrow with it shown, and an iPhone in landscape
    /// borrows this page at about 680 pt and has to stay in one column.
    private static let twoColumnMinimum: CGFloat = 720
    private static let conclusionColumnWidth: CGFloat = 420

    /// Everything that answers the question, as opposed to drawing it.
    @ViewBuilder
    private var conclusionColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The life scale is behind Plus, so this conclusion is too. A
            // locked life view must not print a projected number under a
            // locked canvas.
            if scale == .life, store.plus.isAuthorized, store.records.state.lifeProfile != nil {
                RecordsLifeAllocationCard(
                    store: store, model: lifeModel,
                    isLoading: lifeModel == nil && lifeProjectionSignature != currentLoadSignature
                )
                .onScrollVisibilityChange(threshold: 0.1) { visible in
                    // Visibility starts loading once; layout changes must not cancel it.
                    if visible { lifeAllocationRequested = true }
                }
                .task(id: lifeAllocationRequested && scenePhase == .active && store.selectedTab == .records
                    ? currentLoadSignature : nil) {
                    guard lifeAllocationRequested, scenePhase == .active, store.selectedTab == .records else { return }
                    let signature = currentLoadSignature
                    let projection = await store.prepareLifeViewModel()
                    guard !Task.isCancelled, signature == currentLoadSignature else { return }
                    lifeModel = projection
                    lifeProjectionSignature = signature
                }
            }
            if shouldOfferLifeSetup {
                lifeSetupCard
            }
            if scale != .life, summary != nil {
                RecordsHeadlineView(
                    store: store,
                    title: scale == .year
                        ? store.t("recordsAnnualSummary", values: ["year": store.formatYear(store.recordsCalendar.component(.year, from: anchor))])
                        : periodTitle,
                    summary: summary,
                    onUnlock: { store.paywallSheet = .charts }
                )
            }
            if scale == .year, let selectedYearMonth {
                Button(action: openSelectedMonth) {
                    HStack(spacing: 6) {
                        Text(
                            store.t(
                                "recordsOpenSelectedMonth",
                                values: ["month": selectedMonthTitle(selectedYearMonth)]
                            )
                        )
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(OWCDesign.accent)
            }
        }
    }

    /// A separate layout branch keeps expansion from being a taller version
    /// of the page. It deliberately has no outer scroll view, title, scale
    /// picker, summary, or swipe-to-dismiss gesture. The only persistent
    /// control is the explicit collapse button; scrolling the canvas can never
    /// accidentally close it.
    private var immersiveCanvas: some View {
        ZStack(alignment: .topTrailing) {
            OWCDesign.page.ignoresSafeArea()

            visualization(expandedPresentation: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)


        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var recordsToolbar: some ToolbarContent {
        if !isExpanded, !usesCustomRootHeader, store.selectedTab == .records {
            if showsSidebarButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: showSidebar) {
                        Label(store.t("showSidebar"), systemImage: "sidebar.left")
                    }
                    .accessibilityLabel(store.t("showSidebar"))
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                OWCEarningsVisibilityButton(store: store)
                NavigationLink(value: RecordsRoute.allRecords) {
                    Label(store.t("recordsAllRecords"), systemImage: "list.bullet.rectangle")
                }
                .accessibilityLabel(store.t("recordsAllRecords"))
            }
        }
    }

    private var recordsRootHeader: some View {
        OWCRootPageHeader(title: store.t("recordsTitle")) {
            recordsLeadingControl
        } trailing: {
            recordsTrailingControls
        }
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.frame(in: .named("recordsRootScroll")).maxY < 8
        } action: { _, shouldShow in
            updateCompactRootBar(shouldShow)
        }
    }

    private var compactRecordsBar: some View {
        OWCCompactRootBar(title: store.t("recordsTitle")) {
            recordsLeadingControl
        } trailing: {
            recordsTrailingControls
        }
    }

    @ViewBuilder
    private var recordsLeadingControl: some View {
        if showsSidebarButton {
            Button(action: showSidebar) {
                Label(store.t("showSidebar"), systemImage: "sidebar.left")
            }
            .labelStyle(.iconOnly)
            .owcTabletGlassAction()
            .accessibilityLabel(store.t("showSidebar"))
        }
    }

    private var recordsTrailingControls: some View {
        HStack(spacing: 8) {
            OWCEarningsVisibilityButton(store: store)
                .owcTabletGlassAction()
            NavigationLink(value: RecordsRoute.allRecords) {
                Label(store.t("recordsAllRecords"), systemImage: "list.bullet.rectangle")
            }
            .labelStyle(.iconOnly)
            .owcTabletGlassAction()
            .accessibilityLabel(store.t("recordsAllRecords"))
        }
    }

    private func updateCompactRootBar(_ shouldShow: Bool) {
        guard showsCompactRootBar != shouldShow else { return }
        withAnimation(reduceMotion ? OWCMotion.reduced : .easeOut(duration: 0.16)) {
            showsCompactRootBar = shouldShow
        }
    }

    private var periodHeader: some View {
        HStack(spacing: 6) {
            if scale != .life {
                Button {
                    anchor = store.shiftRecordsAnchor(anchor, scale: scale, by: -1)
                    Task { await load() }
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                        .background(OWCDesign.control, in: Circle())
                }
                .accessibilityLabel(store.t("recordsPreviousPeriod"))
            }
            if showsTodayButton {
                Button(action: returnToToday) { periodTitleLabel }
                    .accessibilityLabel(store.t("recordsToday"))
                    .accessibilityValue(periodTitle)
            } else {
                periodTitleLabel.accessibilityAddTraits(.isHeader)
            }
            if scale != .life {
                Button {
                    anchor = store.shiftRecordsAnchor(anchor, scale: scale, by: 1)
                    Task { await load() }
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 44, height: 44)
                        .background(OWCDesign.control, in: Circle())
                }
                .accessibilityLabel(store.t("recordsNextPeriod"))
            }
            if canExpand {
                Button {
                    setExpanded(!isExpanded)
                } label: {
                    Image(systemName: isExpanded
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(store.t(isExpanded ? "recordsCollapseChart" : "recordsExpandChart"))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(OWCDesign.secondary)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var periodTitleLabel: some View {
        HStack(spacing: 6) {
            Text(periodTitle)
                .font(.title3.bold())
                .foregroundStyle(OWCDesign.primary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            if showsTodayButton {
                Image(systemName: "scope")
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.accent)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func visualization(expandedPresentation: Bool) -> some View {
        let lockedScale = scale.requiresPlus && !store.plus.isAuthorized
        OWCGroupCard {
            visualizationContent(lockedScale: lockedScale, expandedPresentation: expandedPresentation)
                .padding(18)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: expandedPresentation ? .infinity : nil,
                    alignment: .top
                )
                // The scale owns the canvas's identity: a week strip and a
                // month grid are two charts, not one chart with different
                // numbers, and without this SwiftUI tries to carry cells from
                // one into the other.
                .id(scale)
                .transition(.opacity)
                .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.recordsExpansion, value: expandedPresentation)
                // Scope scale motion to the chart. In the split layout the
                // conclusion is a separate reading surface and should not
                // inherit this cross-fade.
                .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.recordsScaleChange, value: scale)
        }
    }

    private var chartIsLoading: Bool { loadedSignature != currentLoadSignature }

    private var placeholderCells: [RecordsDayCell] {
        let window = store.recordsWindow(for: scale, anchor: anchor)
        let calendar = store.recordsCalendar
        var date = calendar.startOfDay(for: window.0)
        var result: [RecordsDayCell] = []
        while date <= window.1 {
            result.append(RecordsDayCell(
                dayKey: RecordJSON.dayKey(date, calendar: calendar), date: date,
                appearance: .unrecorded, workMs: 0, overtimeMs: 0, breakMs: 0, freeMs: 0,
                observationCount: 0, isToday: false, isFuture: false,
                isProjection: false, hasConflict: false
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return result
    }

    @ViewBuilder
    private func visualizationContent(lockedScale: Bool, expandedPresentation: Bool) -> some View {
        let renderedCells = chartIsLoading && scale != .life ? placeholderCells : cells
        VStack(alignment: .leading, spacing: 14) {
            if expandedPresentation {
                HStack {
                    Text(periodTitle)
                        .font(.headline)
                        .foregroundStyle(OWCDesign.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    Button { setExpanded(false) } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(OWCDesign.secondary)
                    .accessibilityLabel(store.t("recordsCollapseChart"))
                }
            } else {
                periodHeader
                Divider()
            }

            if lockedScale {
                RecordsLockedPlaceholder(store: store, kind: .scale) {
                    store.paywallSheet = scale == .life ? .life : .charts
                }
            } else {
                Group {
                switch scale {
                case .month:
                    RecordsMonthGrid(
                        store: store,
                        cells: renderedCells,
                        selectedDayKey: selectedDayKey,
                        onSelect: selectFromTap,
                        onOpen: openDay
                    )
                    markLegend
                case .week:
                    RecordsWeekStrips(
                        store: store,
                        cells: renderedCells,
                        selectedDayKey: selectedDayKey,
                        onSelect: selectFromTap,
                        onOpen: openDay
                    )
                    markLegend
                case .year:
                    // The year changes form when it is given the whole screen:
                    // the collapsed density canvas answers "when was it heavy",
                    // and the expanded rows answer "how do the months compare",
                    // which is a question a 12pt bucket cannot hold.
                    if expandedPresentation {
                        RecordsYearMonthBars(
                            store: store,
                            cells: renderedCells,
                            selectedMonth: selectedYearMonth,
                            onOpenMonth: openMonth
                        ) { month in
                            if selectedYearMonth != month { selectionFeedback += 1 }
                            selectedYearMonth = month
                            yearCalloutMonth = month
                            yearSelectionDate = nil
                        }
                    } else {
                        RecordsYearCanvas(
                            store: store,
                            cells: renderedCells,
                            selectedMonth: selectedYearMonth,
                            calloutMonth: $yearCalloutMonth,
                            selectedDate: $yearSelectionDate,
                            onOpenMonth: openMonth
                        ) { month in
                            if selectedYearMonth != month { selectionFeedback += 1 }
                            selectedYearMonth = month
                        }
                    }
                case .life:
                    lifeCanvas(expandedPresentation: expandedPresentation)
                }
                }
                .redacted(reason: chartIsLoading ? .placeholder : [])
                .opacity(chartIsLoading ? 0.35 : 1)
                .allowsHitTesting(!chartIsLoading)
                .accessibilityHidden(chartIsLoading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .scaleEffect(reduceMotion || pinch == 1 ? 1 : max(0.96, min(1.04, pinch)))
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    if scale != .life { pinch = value.magnification }
                }
                .onEnded { value in
                    guard scale != .life else {
                        pinch = 1
                        return
                    }
                    if value.magnification > 1.22 {
                        if scale == .year {
                            openSelectedMonth()
                        } else {
                            switchScale(to: scale.zoomedIn)
                        }
                    } else if value.magnification < 0.82 {
                        switchScale(to: scale.zoomedOut)
                    }
                    pinch = 1
                }
        )
    }

    private var markLegend: some View {
        RecordsMarkLegend(store: store, includesLock: !store.plus.isAuthorized)
    }

    @ViewBuilder
    private func lifeCanvas(expandedPresentation: Bool) -> some View {
        if let profile = store.records.state.lifeProfile {
            let now = Date.now
            let profileStages = LifeStageCalculator.stages(
                profile: profile,
                calendar: store.recordsCalendar,
                now: now
            )
            let stages = LifeStageCalculator.canvasStages(profileStages, now: now)
            if let bounds = LifeStageCalculator.timelineBounds(stages: profileStages, now: now) {
                RecordsLifeCanvas(
                    store: store,
                    stages: stages,
                    bounds: bounds,
                    selectedStageID: selectedLifeStageID,
                    referenceDate: now,
                    selectedDate: $lifeSelectionDate,
                    showsStageLegend: !expandedPresentation
                ) { stage in
                    selectedLifeStageID = stage.id
                    selectionFeedback += 1
                }
            } else {
                lifeSetupCard
            }
            if profile.retirementOn == nil, !expandedPresentation {
                Button(store.t("lifeSetRetirement"), action: openLifeProfile)
                    .font(.footnote.weight(.semibold))
            }
        } else {
            lifeSetupCard
        }
    }

    private func setExpanded(_ value: Bool) {
        guard canExpand else { return }
        withAnimation(reduceMotion ? OWCMotion.reduced : OWCMotion.recordsExpansion) {
            expanded[scale] = value
        }
    }

    private var lifeSetupCard: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(store.t("recordsLifeSetupTitle"))
                    .font(.body.weight(.medium))
                Text(store.t("recordsLifeSetupBody"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button(store.t("recordsLifeSetupNow"), action: openLifeProfile)
                        .font(.body.weight(.semibold))
                    Button(store.t("recordsLifeSetupLater")) {
                        store.lifeSetupPromptDismissed = true
                    }
                    .foregroundStyle(OWCDesign.secondary)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var damagedState: some View {
        VStack(alignment: .leading, spacing: 14) {
            archiveBannerCard(.damaged)
                .padding(.horizontal, OWCDesign.pageInset)
            Spacer()
        }
        .padding(.top, 14)
    }

    private func archiveBannerCard(_ banner: RecordsArchiveBanner) -> some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(store.t(banner == .saveFailed ? "recordsArchiveSaveFailedTitle" : "recordsArchiveDamagedTitle"))
                    .font(.body.weight(.medium))
                Text(store.t(banner == .saveFailed ? "recordsArchiveSaveFailedBody" : "recordsArchiveDamagedBody"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                if banner == .damaged {
                    Button(store.t("recordsArchiveQuarantine")) { confirmsQuarantine = true }
                        .font(.body.weight(.semibold))
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var periodTitle: String {
        let window = store.recordsWindow(for: scale, anchor: anchor)
        switch scale {
        case .week:
            return "\(store.formatRecordsMonthDay(window.0)) – \(store.formatRecordsMonthDay(window.1))"
        case .month:
            return store.formatRecordsMonthYear(window.0)
        case .year:
            return "\(store.recordsCalendar.component(.year, from: window.0))"
        case .life:
            return store.t("recordsScaleLife")
        }
    }

    private var scaleBinding: Binding<RecordsScale> {
        Binding(
            get: { scale },
            set: { switchScale(to: $0) }
        )
    }

    private func selectedMonthTitle(_ month: Int) -> String {
        var parts = store.recordsCalendar.dateComponents([.year], from: anchor)
        parts.month = month
        parts.day = 1
        return store.formatRecordsMonthYear(store.recordsCalendar.date(from: parts) ?? anchor)
    }

    private func switchScale(to nextScale: RecordsScale) {
        guard nextScale != scale else { return }
        let changesDailyScale = (scale == .week || scale == .month)
            && (nextScale == .week || nextScale == .month)
        // Week and month are frequent ways to inspect the same daily data.
        // The chart bridges the replacement itself; its conclusion updates in
        // place. Year and life change the question and keep the page transition.
        withAnimation(
            changesDailyScale ? nil : (reduceMotion ? OWCMotion.reduced : OWCMotion.recordsScaleChange)
        ) {
            loadGeneration += 1
            scale = nextScale
            days = []
            cells = []
            summary = nil
            selectedDayKey = nil
            selectedYearMonth = nextScale == .year
                ? store.recordsCalendar.component(.month, from: .now)
                : nil
            selectedLifeStageID = nil
            yearCalloutMonth = nil
            yearSelectionDate = nil
            lifeSelectionDate = nil
            expanded = [:]
            pinch = 1
            if nextScale == .life { selectCurrentLifeStage() }
        }
        scaleFeedback += 1
        Task { await load() }
    }

    private var shouldOfferLifeSetup: Bool {
        store.plus.isAuthorized
            && store.records.state.lifeProfile == nil
            && !store.lifeSetupPromptDismissed
            && scale == .month
    }

    private var showsTodayButton: Bool {
        guard scale != .life else { return false }
        let window = store.recordsWindow(for: scale, anchor: anchor)
        let today = store.recordsCalendar.startOfDay(for: .now)
        return today < store.recordsCalendar.startOfDay(for: window.0)
            || today > store.recordsCalendar.startOfDay(for: window.1)
    }

    private func returnToToday() {
        withAnimation(reduceMotion ? OWCMotion.reduced : .easeOut(duration: 0.2)) {
            anchor = .now
            if scale == .year {
                selectedYearMonth = store.recordsCalendar.component(.month, from: .now)
                yearCalloutMonth = nil
                yearSelectionDate = nil
            }
        }
        selectionFeedback += 1
        Task { await load() }
    }

    private func openLifeProfile() {
        if store.plus.isAuthorized {
            showsLifeEditor = true
        } else {
            store.paywallSheet = .life
        }
    }

    private func selectCurrentLifeStage(now: Date = .now) {
        guard let profile = store.records.state.lifeProfile else {
            selectedLifeStageID = nil
            return
        }
        let stages = LifeStageCalculator.canvasStages(
            LifeStageCalculator.stages(profile: profile, calendar: store.recordsCalendar, now: now), now: now
        )
        let current = LifeStageCalculator.stage(at: now.addingTimeInterval(-0.001), stages: stages)
        selectedLifeStageID = current?.kind == .retirement ? nil : current?.id
    }

    private func selectFromTap(_ cell: RecordsDayCell) {
        if selectedDayKey == cell.dayKey {
            openDay(cell)
        } else {
            selectionFeedback += 1
            selectedDayKey = cell.dayKey
        }
    }

    private func openDay(_ cell: RecordsDayCell) {
        guard cell.appearance != .locked else {
            store.paywallSheet = .charts
            return
        }
        withAnimation(reduceMotion ? OWCMotion.reduced : OWCMotion.navigation) {
            quickDay = RecordsDayIdentified(dayKey: cell.dayKey)
        }
    }

    private func openSelectedMonth() {
        guard let selectedYearMonth else { return }
        openMonth(selectedYearMonth)
    }

    private func openMonth(_ month: Int) {
        yearCalloutMonth = nil
        yearSelectionDate = nil
        var parts = store.recordsCalendar.dateComponents([.year], from: anchor)
        parts.month = month
        parts.day = 1
        anchor = store.recordsCalendar.date(from: parts) ?? anchor
        switchScale(to: .month)
    }

    @ViewBuilder
    private func recordsDestination(_ route: RecordsRoute) -> some View {
        Group {
            switch route {
            case .allRecords:
                RecordsAllRecordsView(store: store)
            case .yearList(let year):
                RecordsYearRecordsView(store: store, year: year)
            case .monthList(let year, let month):
                RecordsMonthRecordsView(store: store, year: year, month: month)
            case .day(let dayKey):
                RecordsDayCanvasView(store: store, dayKey: dayKey)
            case .conflictCenter:
                RecordsConflictCenter(store: store)
            }
        }
        .onAppear { store.writeQASurfaceMarker(qaSurfaceName(for: route)) }
    }

    private func qaSurfaceName(for route: RecordsRoute) -> String {
        switch route {
        case .allRecords: "records.allRecords"
        case .yearList: "records.yearList"
        case .monthList: "records.monthList"
        case .day: "records.day"
        case .conflictCenter: "records.conflicts"
        }
    }

    /// Everything the loaded window depends on. The civil day is in here
    /// because "today" decides selection, and which cells are already lived
    /// through rather than planned.
    private struct RecordsLoadSignature: Equatable {
        var scale: RecordsScale
        var anchor: Date
        var revision: UInt64
        var authorized: Bool
        var dayKey: String
        var timeZone: String
        var language: String
        var salaryEnabled: Bool
        var salaryType: SalaryType
        var salaryAmount: String
        var monthlyWorkingDays: Double
    }

    private var currentLoadSignature: RecordsLoadSignature {
        RecordsLoadSignature(
            scale: scale,
            anchor: anchor,
            revision: store.records.revision,
            authorized: store.plus.isAuthorized,
            dayKey: RecordJSON.dayKey(.now, calendar: store.recordsCalendar),
            timeZone: store.recordsTimeZone.identifier,
            language: store.languageCode,
            salaryEnabled: store.salaryEnabled,
            salaryType: store.salaryType,
            salaryAmount: store.salaryAmount,
            monthlyWorkingDays: store.monthlyWorkingDays
        )
    }

    private func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let requestedScale = scale
        let requestedAnchor = anchor
        let signature = currentLoadSignature
        if scale == .life {
            days = []
            cells = []
            summary = nil
            if selectedLifeStageID == nil { selectCurrentLifeStage() }
            // The stage grid is immediate. The expensive allocation is requested
            // once its card becomes visible; later refreshes retain the result.
            loadedSignature = signature
            return
        }
        if requestedScale == .year, selectedYearMonth == nil {
            selectedYearMonth = store.recordsCalendar.component(.month, from: .now)
        }
        let window = store.recordsWindow(for: requestedScale, anchor: requestedAnchor)
        // One day of lead-in, because the shift that ends at 06:00 on the first
        // of the month started the night before and still belongs to that
        // morning. The extra day is never drawn.
        let leadIn = store.recordsCalendar.date(byAdding: .day, value: -1, to: window.0) ?? window.0
        let resolved = await store.prepareRecordsDisplayDays(from: leadIn, through: window.1)
        guard generation == loadGeneration,
              requestedScale == scale,
              requestedAnchor == anchor
        else { return }
        let firstKey = RecordJSON.dayKey(window.0, calendar: store.recordsCalendar)
        days = resolved
        var built: [RecordsDayCell] = []
        for (index, day) in resolved.enumerated() where day.dayKey >= firstKey {
            built.append(
                store.recordsDayCell(
                    for: day,
                    previous: index > 0 ? resolved[index - 1] : nil,
                    includesLifeProjection: true
                )
            )
        }
        cells = built
        summary = store.recordsHeadline(cells: cells, days: resolved)
        if let selectedDayKey, !cells.contains(where: { $0.dayKey == selectedDayKey }) {
            self.selectedDayKey = nil
        }
        loadedSignature = signature
    }
}

private struct LifeStageSheetItem: Identifiable {
    var id: LifeStageKind { stage.kind }
    var stage: LifeStageSpan
}

private struct LifeStageDetailSheet: View {
    let store: OffWorkStore
    let stage: LifeStageSpan

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        Image(systemName: stage.kind.iconName)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(OWCDesign.orangeDeep, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.t(stage.kind.titleKey))
                                .font(.title2.weight(.semibold))
                            Text(rangeLabel)
                                .font(.body)
                                .foregroundStyle(OWCDesign.secondary)
                        }
                    }

                    if let start = stage.start {
                        let end = stage.end ?? .now
                        let days = max(0, store.recordsCalendar.dateComponents([.day], from: start, to: end).day ?? 0)
                        let elapsedDays = max(0, min(days, store.recordsCalendar.dateComponents([.day], from: start, to: .now).day ?? 0))
                        let remainingDays = stage.end == nil ? nil : max(0, days - elapsedDays)
                        let progress = LifeStageCalculator.progress(from: start, to: end, at: .now)

                        OWCGroupCard {
                            LazyVGrid(
                                columns: [GridItem(.flexible()), GridItem(.flexible())],
                                alignment: .leading,
                                spacing: 10
                            ) {
                                detailMetric(
                                    store.t("lifeStageDurationTitle"),
                                    store.t("lifeStageDuration", values: [
                                        "years": store.formatCount(days / 365),
                                        "days": store.formatCount(days),
                                    ])
                                )
                                detailMetric(store.t("lifeStageAgeRange"), ageRange(from: start, to: end))
                                detailMetric(store.t("lifeStageElapsed"), store.formatDays(Double(elapsedDays)))
                                detailMetric(
                                    store.t("lifeStageRemaining"),
                                    remainingDays.map { store.formatDays(Double($0)) } ?? "—"
                                )
                            }
                            .padding(14)
                        }

                        if stage.end != nil {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(store.t("progress"))
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(OWCDesign.secondary)
                                    Spacer()
                                    Text(store.formatPercent(progress * 100, fractionDigits: 2))
                                        .font(.footnote.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(OWCDesign.orangeDeep)
                                }
                                ProgressView(value: progress)
                                    .tint(OWCDesign.orangeDeep)
                            }
                        }

                        Text(store.t("lifeWeeksUnit", values: ["count": store.formatCount(days / 7)]))
                            .font(.body.weight(.medium))

                        if let stageEnd = stage.end, let bounds = timelineBounds {
                            let span = bounds.1.timeIntervalSince(bounds.0)
                            if span > 0 {
                                let share = stageEnd.timeIntervalSince(start) / span * 100
                                Text(store.t("lifeStageShare", values: ["percent": store.formatPercent(share)]))
                                    .font(.body)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if stage.startPrecision != nil {
                            Text(store.t(stage.startPrecision == .year ? "lifePrecisionYear" : "lifePrecisionDay"))
                        }
                        if stage.endPrecision != nil, stage.endPrecision != stage.startPrecision {
                            Text(store.t(stage.endPrecision == .year ? "lifePrecisionYear" : "lifePrecisionDay"))
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(OWCDesign.page)
            .navigationTitle(store.t(stage.kind.titleKey))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var timelineBounds: (Date, Date)? {
        guard let profile = store.records.state.lifeProfile else { return nil }
        return LifeStageCalculator.timelineBounds(
            stages: LifeStageCalculator.stages(profile: profile, calendar: store.recordsCalendar),
            now: .now
        )
    }

    private func ageRange(from start: Date, to end: Date) -> String {
        guard let profile = store.records.state.lifeProfile else { return "—" }
        var resolved = profile
        resolved.migrateLegacyFields(calendar: store.recordsCalendar)
        guard let birth = resolved.bornOn?.calculationAnchor(in: store.recordsCalendar) else { return "—" }
        let startAge = max(0, store.recordsCalendar.dateComponents([.year], from: birth, to: start).year ?? 0)
        let endAge = max(startAge, store.recordsCalendar.dateComponents([.year], from: birth, to: end).year ?? startAge)
        return "\(store.formatCount(startAge))–\(store.formatCount(endAge))"
    }

    private func detailMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(OWCDesign.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption)
                .foregroundStyle(OWCDesign.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(12)
        .background(OWCDesign.elevated, in: RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous))
    }

    private var rangeLabel: String {
        let calendar = store.recordsCalendar
        let startYear = stage.start.map { store.formatYear(calendar.component(.year, from: $0)) }
        let endYear = stage.end.map { store.formatYear(calendar.component(.year, from: $0)) }
        switch (startYear, endYear) {
        case (nil, nil):
            return store.t("lifeUnset")
        case (let start?, let end?):
            return store.t("weekdayRange", values: ["start": start, "end": end])
        case (let start?, nil):
            return start
        case (nil, let end?):
            return end
        }
    }
}
