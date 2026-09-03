import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RecordsDesignView: View {
    let store: OffWorkStore
    let showsSidebarButton: Bool
    let usesOwnHeader: Bool
    let showSidebar: () -> Void
    @State private var scale: RecordsScale
    @State private var anchor = Date()
    @State private var selectedDayKey: String?
    @State private var selectedYearMonth: Int?
    @State private var selectedLifeStageKind: LifeStageKind?
    @State private var days: [DayResolution] = []
    @State private var cells: [RecordsDayCell] = []
    @State private var summary: RecordsHeadlineSummary?
    @State private var detail: RecordsDayDetail?
    @State private var lifeModel: LifeViewModel?
    @State private var expanded: [RecordsScale: Bool]
    @State private var pinch: CGFloat = 1
    @State private var scaleFeedback = 0
    @State private var selectionFeedback = 0
    @State private var showsLifeEditor = false
    @State private var confirmsQuarantine = false
    @State private var loadGeneration = 0
    @State private var showsCompactRootBar = false
    @State private var canvasWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isExpanded: Bool { expanded[scale] == true }
    private var canExpand: Bool { scale == .year || scale == .life }
    /// Draw the title and its controls inside the page instead of borrowing a
    /// navigation bar. True in phone portrait, and on iPad, where the shell
    /// keeps its bar hidden for every root so switching tabs cannot resize the
    /// safe area under a cross-fade.
    private var usesPhonePortraitHeader: Bool {
        usesOwnHeader || (horizontalSizeClass == .compact && verticalSizeClass != .compact)
    }

    init(
        store: OffWorkStore,
        showsSidebarButton: Bool = false,
        usesOwnHeader: Bool = false,
        showSidebar: @escaping () -> Void = {}
    ) {
        self.store = store
        self.showsSidebarButton = showsSidebarButton
        self.usesOwnHeader = usesOwnHeader
        self.showSidebar = showSidebar
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
            isActive: store.selectedTab == .records && !isExpanded && !usesPhonePortraitHeader
        )
        // Expansion is a contained browsing mode. The calendar remains inside
        // the same navigation stack, but the surrounding tab and navigation
        // chrome must get out of the way so the canvas can use the available
        // width and height on both phones and iPad split panes.
        .toolbar(isExpanded || usesPhonePortraitHeader ? .hidden : .visible, for: .navigationBar)
        .toolbar(isExpanded ? .hidden : .visible, for: .tabBar)
        .navigationDestination(for: RecordsRoute.self) { route in
            recordsDestination(route)
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
            if usesPhonePortraitHeader, showsCompactRootBar, !isExpanded {
                compactRecordsBar
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .task { await load(selectingToday: true) }
        .onChange(of: store.selectedTab) { _, tab in
            if tab == .records { Task { await load() } }
        }
        .onChange(of: store.records.revision) { _, _ in
            Task { await load() }
        }
        .onChange(of: store.plus.isAuthorized) { _, _ in
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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if usesPhonePortraitHeader {
                    recordsRootHeader
                }

                if let banner = store.records.archiveBanner {
                    archiveBannerCard(banner)
                }

                RecordsScalePicker(store: store, scale: scaleBinding)

                // Side by side once there is room for both. An iPad in
                // landscape stretched a single column across the whole pane,
                // so a month grid and a summary card each ran the width of the
                // screen. The chart keeps the larger share; the conclusions
                // are text and stop at a readable measure.
                //
                // Measured rather than `ViewThatFits`: that asks each
                // candidate for its ideal width, and the legend row inside the
                // chart card reports the width it would like as one unbroken
                // line, which is enough to reject the two-column layout on a
                // pane that has ample room for it.
                if canvasWidth >= Self.twoColumnMinimum {
                    HStack(alignment: .top, spacing: 14) {
                        visualization(expandedPresentation: false)
                        conclusionColumn
                            .frame(maxWidth: Self.conclusionColumnWidth, alignment: .top)
                    }
                } else {
                    visualization(expandedPresentation: false)
                    conclusionColumn
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 12)
            .padding(.bottom, 104)
        }
        .scrollIndicators(.hidden)
        .coordinateSpace(.named("recordsRootScroll"))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { canvasWidth = $0 }
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
            if scale == .week || scale == .month {
                RecordsDaySummaryCard(
                    store: store,
                    detail: detail,
                    locked: selectedIsLocked,
                    onUnlock: { store.paywallSheet = .charts }
                )
            } else if scale == .year, let selectedYearMonth {
                RecordsYearSelectionCard(
                    store: store,
                    month: selectedYearMonth,
                    cells: yearSelectionCells,
                    summary: yearSelectionSummary
                )
            }
            // The life scale is behind Plus, so this conclusion is too. A
            // locked life view must not print a projected number under a
            // locked canvas.
            if scale == .life, store.plus.isAuthorized, store.records.state.lifeProfile != nil {
                RecordsLifeAllocationCard(store: store, model: lifeModel)
            }
            if shouldOfferLifeSetup {
                lifeSetupCard
            }
            if scale != .life, hasActualRecords, !selectedIsLocked {
                RecordsHeadlineView(
                    store: store,
                    summary: summary,
                    onUnlock: { store.paywallSheet = .charts }
                )
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

            Button {
                setExpanded(false)
            } label: {
                Label(store.t("recordsCollapseChart"), systemImage: "arrow.down.right.and.arrow.up.left")
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .background(OWCDesign.control, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(OWCDesign.primary)
            .accessibilityLabel(store.t("recordsCollapseChart"))
            .padding(.top, 8)
            .padding(.trailing, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var recordsToolbar: some ToolbarContent {
        if !isExpanded, !usesPhonePortraitHeader, store.selectedTab == .records {
            if showsSidebarButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: showSidebar) {
                        OWCGlassCircleLabel {
                            Image(systemName: "sidebar.left")
                                .foregroundStyle(OWCDesign.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(store.t("showSidebar"))
                }
                .sharedBackgroundVisibility(.hidden)
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if showsTodayButton {
                    Button(action: returnToToday) {
                        OWCGlassCircleLabel {
                            Image(systemName: "scope")
                                .foregroundStyle(OWCDesign.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(store.t("recordsToday"))
                }

                NavigationLink(value: RecordsRoute.allRecords) {
                    OWCGlassCircleLabel {
                        Image(systemName: "list.bullet.rectangle")
                            .foregroundStyle(OWCDesign.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.t("recordsAllRecords"))
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    private var recordsRootHeader: some View {
        OWCRootPageHeader(title: store.t("recordsTitle")) {
            recordsLeadingControl
        } trailing: {
            recordsTrailingControls
        }
        .padding(.horizontal, max(0, OWCDesign.contentInset - OWCDesign.pageInset))
        .padding(.top, 2)
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
                OWCGlassCircleLabel {
                    Image(systemName: "sidebar.left")
                        .foregroundStyle(OWCDesign.primary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.t("showSidebar"))
        }
    }

    private var recordsTrailingControls: some View {
        HStack(spacing: 8) {
            if showsTodayButton {
                Button(action: returnToToday) {
                    OWCGlassCircleLabel {
                        Image(systemName: "scope")
                            .foregroundStyle(OWCDesign.accent)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.t("recordsToday"))
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            NavigationLink(value: RecordsRoute.allRecords) {
                OWCGlassCircleLabel {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundStyle(OWCDesign.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.t("recordsAllRecords"))
        }
        .animation(reduceMotion ? OWCMotion.reduced : .easeOut(duration: 0.18), value: showsTodayButton)
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
            Text(periodTitle)
                .font(.title3.bold())
                .foregroundStyle(OWCDesign.primary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
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
                .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.recordsExpansion, value: expandedPresentation)
        }
    }

    @ViewBuilder
    private func visualizationContent(lockedScale: Bool, expandedPresentation: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if expandedPresentation {
                Text(periodTitle)
                    .font(.headline)
                    .foregroundStyle(OWCDesign.secondary)
                    .padding(.trailing, 44)
                    .accessibilityAddTraits(.isHeader)
            } else {
                periodHeader
                Divider()
            }

            if lockedScale {
                RecordsLockedPlaceholder(store: store, kind: .scale) {
                    store.paywallSheet = scale == .life ? .life : .charts
                }
            } else {
                switch scale {
                case .month:
                    RecordsMonthGrid(store: store, cells: cells, selectedDayKey: selectedDayKey) { cell in
                        select(cell)
                    }
                    markLegend
                case .week:
                    RecordsWeekStrips(store: store, cells: cells, selectedDayKey: selectedDayKey) { cell in
                        select(cell)
                    }
                    markLegend
                case .year:
                    // The year changes form when it is given the whole screen:
                    // the collapsed density canvas answers "when was it heavy",
                    // and the expanded rows answer "how do the months compare",
                    // which is a question a 12pt bucket cannot hold.
                    if expandedPresentation {
                        RecordsYearMonthBars(
                            store: store,
                            cells: cells,
                            selectedMonth: selectedYearMonth
                        ) { month in
                            selectedYearMonth = month
                            selectionFeedback += 1
                        }
                    } else {
                        RecordsYearCanvas(
                            store: store,
                            cells: cells,
                            selectedMonth: selectedYearMonth
                        ) { month in
                            selectedYearMonth = month
                            selectionFeedback += 1
                        }
                    }
                case .life:
                    lifeCanvas(expandedPresentation: expandedPresentation)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .scaleEffect(reduceMotion || pinch == 1 ? 1 : max(0.96, min(1.04, pinch)))
        .gesture(
            MagnifyGesture()
                .onChanged { pinch = $0.magnification }
                .onEnded { value in
                    if value.magnification > 1.22 {
                        switchScale(to: scale.zoomedIn)
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
            let stages = LifeStageCalculator.stages(profile: profile, calendar: store.recordsCalendar)
            if let bounds = LifeStageCalculator.timelineBounds(stages: stages, now: .now) {
                RecordsLifeCanvas(
                    store: store,
                    stages: stages,
                    bounds: bounds,
                    selectedStage: selectedLifeStageKind,
                    showsStageLegend: !expandedPresentation
                ) { stage in
                    selectedLifeStageKind = stage.kind
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

    private var yearSelectionCells: [RecordsDayCell] {
        guard let selectedYearMonth else { return [] }
        return cells.filter { store.recordsCalendar.component(.month, from: $0.date) == selectedYearMonth }
    }

    private var scaleBinding: Binding<RecordsScale> {
        Binding(
            get: { scale },
            set: { switchScale(to: $0) }
        )
    }

    private func switchScale(to nextScale: RecordsScale) {
        guard nextScale != scale else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            loadGeneration += 1
            scale = nextScale
            days = []
            cells = []
            summary = nil
            detail = nil
            selectedDayKey = nil
            selectedYearMonth = nextScale == .year
                ? store.recordsCalendar.component(.month, from: .now)
                : nil
            selectedLifeStageKind = nil
            expanded = [:]
            pinch = 1
            if nextScale == .life { selectCurrentLifeStage() }
        }
        scaleFeedback += 1
        Task { await load(selectingToday: nextScale == .week || nextScale == .month) }
    }

    private var yearSelectionSummary: RecordsHeadlineSummary? {
        // The whole year is handed over on purpose: the month's own totals are
        // taken from its cells, and the day before the first needs to be
        // reachable so an overnight shift is not cut at the month boundary.
        store.recordsHeadline(cells: yearSelectionCells, days: days)
    }

    private var selectedIsLocked: Bool {
        guard let selectedDayKey else { return false }
        return cells.first(where: { $0.dayKey == selectedDayKey })?.appearance == .locked
    }

    private var shouldOfferLifeSetup: Bool {
        store.plus.isAuthorized
            && store.records.state.lifeProfile == nil
            && !store.lifeSetupPromptDismissed
            && scale == .month
    }

    private var hasActualRecords: Bool {
        cells.contains { $0.appearance == .recorded || $0.appearance == .corrected }
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
            }
        }
        selectionFeedback += 1
        Task { await load(selectingToday: scale == .week || scale == .month) }
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
            selectedLifeStageKind = nil
            return
        }
        let stages = LifeStageCalculator.stages(profile: profile, calendar: store.recordsCalendar)
        let current = LifeStageCalculator.stage(at: now, stages: stages)?.kind
        selectedLifeStageKind = current == .retirement ? nil : current
    }

    private func select(_ cell: RecordsDayCell) {
        selectedDayKey = cell.dayKey
        selectionFeedback += 1
        guard let index = days.firstIndex(where: { $0.dayKey == cell.dayKey }) else {
            detail = nil
            return
        }
        detail = store.recordsDayDetail(
            for: days[index],
            previous: index > 0 ? days[index - 1] : nil,
            includesLifeProjection: true
        )
    }

    @ViewBuilder
    private func recordsDestination(_ route: RecordsRoute) -> some View {
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

    private func load(selectingToday: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        let requestedScale = scale
        let requestedAnchor = anchor
        if scale == .life {
            days = []
            cells = []
            summary = nil
            if selectedLifeStageKind == nil { selectCurrentLifeStage() }
            // Expanding a career's worth of schedule runs off the main actor;
            // the life canvas itself only needs the profile's stage dates.
            let projection = store.plus.isAuthorized ? await store.prepareLifeViewModel() : nil
            guard generation == loadGeneration, requestedScale == scale else { return }
            lifeModel = projection
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
        if selectingToday {
            let todayKey = RecordJSON.dayKey(.now, calendar: store.recordsCalendar)
            if let today = cells.first(where: { $0.dayKey == todayKey }) {
                select(today)
            } else if let latest = cells.last(where: { $0.appearance == .recorded || $0.appearance == .corrected }) {
                select(latest)
            } else {
                selectedDayKey = nil
                detail = nil
            }
        } else if let selectedDayKey, let cell = cells.first(where: { $0.dayKey == selectedDayKey }) {
            select(cell)
        } else {
            selectedDayKey = nil
            detail = nil
        }
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
