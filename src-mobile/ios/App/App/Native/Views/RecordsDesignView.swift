import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RecordsDesignView: View {
    @Environment(SceneState.self) private var scene
    let records: RecordCoordinator
    let queries: RecordsQueries
    let actions: RecordsActions
    let life: LifeSummaryModel
    let preferences: PreferencesStore
    let focus: FocusStore
    let text: AppText
    let hours: ScheduleHoursConfiguration
    @Bindable var browsing: RecordsSceneState
    let showsSidebarButton: Bool
    let usesOwnHeader: Bool
    let showSidebar: () -> Void
    let onExpansionChanged: (Bool) -> Void
    @State private var days: [DayResolution] = []
    @State private var cells: [RecordsDayCell] = []
    @State private var summary: RecordsHeadlineSummary?
    @State private var pinch: CGFloat = 1
    @State private var scaleFeedback = 0
    @State private var selectionFeedback = 0
    @State private var confirmsQuarantine = false
    @State private var loadGeneration = 0
    @State private var loadedSignature: RecordsLoadSignature?
    @State private var showsCompactRootBar = false
    @State private var canvasWidth: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExpanded: Bool { browsing.expanded[browsing.scale] == true }
    private var canExpand: Bool { browsing.scale == .year || browsing.scale == .life }
    /// iPad keeps its custom root chrome so switching split-view tabs cannot
    /// resize the detail pane under a cross-fade. Phones use the system bar.
    private var usesCustomRootHeader: Bool { usesOwnHeader }

    init(
        records: RecordCoordinator,
        queries: RecordsQueries,
        actions: RecordsActions,
        life: LifeSummaryModel,
        preferences: PreferencesStore,
        focus: FocusStore,
        text: AppText,
        hours: ScheduleHoursConfiguration,
        browsing: RecordsSceneState,
        showsSidebarButton: Bool = false,
        usesOwnHeader: Bool = false,
        showSidebar: @escaping () -> Void = {},
        onExpansionChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.records = records
        self.queries = queries
        self.actions = actions
        self.life = life
        self.preferences = preferences
        self.focus = focus
        self.text = text
        self.hours = hours
        self.browsing = browsing
        self.showsSidebarButton = showsSidebarButton
        self.usesOwnHeader = usesOwnHeader
        self.showSidebar = showSidebar
        self.onExpansionChanged = onExpansionChanged

    }

    var body: some View {
        Group {
            if records.archiveBanner == .damaged {
                damagedState
            } else if isExpanded {
                immersiveCanvas
            } else {
                regularCanvas
            }
        }
        .background(OWCDesign.page)
        .owcNavigationTitle(
            text.t("recordsTitle"),
            displayMode: .large,
            isActive: scene.selectedTab == .records && !isExpanded && !usesCustomRootHeader
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
        .navigationDestination(item: $browsing.quickDay) { item in
            dayCanvas(dayKey: item.dayKey)
                .onAppear { writeQASurfaceMarker("records.day") }
        }
        .sheet(isPresented: $browsing.showsLifeEditor) {
            LifeProfileEditView(life: life, actions: actions, preferences: preferences, text: text)
        }
        .toolbar { recordsToolbar }
        .overlay(alignment: .top) {
            if usesCustomRootHeader, showsCompactRootBar, !isExpanded {
                compactRecordsBar
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .task(id: scenePhase == .active && scene.selectedTab == .records) {
            guard scenePhase == .active, scene.selectedTab == .records else { return }
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
        .onChange(of: isExpanded, initial: true) { _, value in
            onExpansionChanged(value)
        }
        .onDisappear {
            onExpansionChanged(false)
        }
        .onChange(of: currentLoadSignature) { _, _ in
            guard scenePhase == .active, scene.selectedTab == .records else { return }
            Task { await load() }
        }
        .sensoryFeedback(.selection, trigger: scaleFeedback)
        .sensoryFeedback(.selection, trigger: selectionFeedback)
        .confirmationDialog(
            text.t("recordsArchiveQuarantineConfirm"),
            isPresented: $confirmsQuarantine,
            titleVisibility: .visible
        ) {
            Button(text.t("recordsArchiveQuarantine")) {
                Task { _ = try? await records.quarantineCorruptedArchive() }
            }
            Button(text.t("cancel"), role: .cancel) {}
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
                        if records.archiveBanner == .damaged {
                            damagedArchiveCard
                        }
                        RecordsScalePicker(text: text, scale: scaleBinding)
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
                    if records.archiveBanner == .damaged {
                        damagedArchiveCard
                    }

                    RecordsScalePicker(text: text, scale: scaleBinding)

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
            if browsing.scale == .life, queries.plus.isAuthorized, records.state.lifeProfile != nil {
                RecordsLifeAllocationCard(
                    text: text,
                    preferences: preferences,
                    incomeDecline: records.state.lifeProfile?.futureIncomeDecline,
                    model: life.cachedLifeViewModel,
                    isLoading: life.cachedLifeViewModel == nil
                )
            }
            if shouldOfferLifeSetup {
                lifeSetupCard
            }
            if browsing.scale != .life, summary != nil {
                RecordsHeadlineView(
                    text: text,
                    preferences: preferences,
                    isAuthorized: queries.plus.isAuthorized,
                    title: browsing.scale == .year
                        ? text.t("recordsAnnualSummary", values: ["year": text.formatYear(preferences.recordsCalendar.component(.year, from: browsing.anchor))])
                        : periodTitle,
                    summary: summary,
                    onUnlock: { scene.paywallSheet = .charts }
                )
            }
            if browsing.scale == .year, let selectedMonth = browsing.selectedYearMonth {
                Button(action: openSelectedMonth) {
                    HStack(spacing: 6) {
                        Text(
                            text.t(
                                "recordsOpenSelectedMonth",
                                values: ["month": selectedMonthTitle(selectedMonth)]
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
        if !isExpanded, !usesCustomRootHeader, scene.selectedTab == .records {
            if showsSidebarButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: showSidebar) {
                        Label(text.t("showSidebar"), systemImage: "sidebar.left")
                    }
                    .accessibilityLabel(text.t("showSidebar"))
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                OWCEarningsVisibilityButton(preferences: preferences, text: text)
                NavigationLink(value: RecordsRoute.allRecords) {
                    Label(text.t("recordsAllRecords"), systemImage: "list.bullet.rectangle")
                }
                .accessibilityLabel(text.t("recordsAllRecords"))
            }
        }
    }

    private var recordsRootHeader: some View {
        OWCRootPageHeader(title: text.t("recordsTitle")) {
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
        OWCCompactRootBar(title: text.t("recordsTitle")) {
            recordsLeadingControl
        } trailing: {
            recordsTrailingControls
        }
    }

    @ViewBuilder
    private var recordsLeadingControl: some View {
        if showsSidebarButton {
            Button(action: showSidebar) {
                Label(text.t("showSidebar"), systemImage: "sidebar.left")
            }
            .labelStyle(.iconOnly)
            .owcTabletGlassAction()
            .accessibilityLabel(text.t("showSidebar"))
        }
    }

    private var recordsTrailingControls: some View {
        HStack(spacing: 8) {
            OWCEarningsVisibilityButton(preferences: preferences, text: text)
                .owcTabletGlassAction()
            NavigationLink(value: RecordsRoute.allRecords) {
                Label(text.t("recordsAllRecords"), systemImage: "list.bullet.rectangle")
            }
            .labelStyle(.iconOnly)
            .owcTabletGlassAction()
            .accessibilityLabel(text.t("recordsAllRecords"))
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
            if browsing.scale != .life {
                Button {
                    browsing.anchor = queries.shiftRecordsAnchor(browsing.anchor, scale: browsing.scale, by: -1)
                    Task { await load() }
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                        .background(OWCDesign.control, in: Circle())
                }
                .accessibilityLabel(text.t("recordsPreviousPeriod"))
            }
            if showsTodayButton {
                Button(action: returnToToday) { periodTitleLabel }
                    .accessibilityLabel(text.t("recordsToday"))
                    .accessibilityValue(periodTitle)
            } else {
                periodTitleLabel.accessibilityAddTraits(.isHeader)
            }
            if browsing.scale != .life {
                Button {
                    browsing.anchor = queries.shiftRecordsAnchor(browsing.anchor, scale: browsing.scale, by: 1)
                    Task { await load() }
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 44, height: 44)
                        .background(OWCDesign.control, in: Circle())
                }
                .accessibilityLabel(text.t("recordsNextPeriod"))
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
                .accessibilityLabel(text.t(isExpanded ? "recordsCollapseChart" : "recordsExpandChart"))
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
        let lockedScale = browsing.scale.requiresPlus && !queries.plus.isAuthorized
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
                .id(browsing.scale)
                .transition(.opacity)
                .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.recordsExpansion, value: expandedPresentation)
                // Scope scale motion to the chart. In the split layout the
                // conclusion is a separate reading surface and should not
                // inherit this cross-fade.
                .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.recordsScaleChange, value: browsing.scale)
        }
    }

    // Reconciliation and CloudKit can change the revision several times at
    // launch. Keep the last calendar visible while its replacement is prepared.
    // Life renders directly from the profile and deliberately keeps cells empty.
    // Applying calendar loading to it would dim/redact the whole grid on every
    // archive revision, then restore it when load() acknowledges that revision.
    private var chartIsLoading: Bool {
        browsing.scale != .life && cells.isEmpty && loadedSignature != currentLoadSignature
    }

    private var placeholderCells: [RecordsDayCell] {
        let window = queries.recordsWindow(for: browsing.scale, anchor: browsing.anchor)
        let calendar = preferences.recordsCalendar
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
        let renderedCells = chartIsLoading ? placeholderCells : cells
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
                    .accessibilityLabel(text.t("recordsCollapseChart"))
                }
            } else {
                periodHeader
                Divider()
            }

            if lockedScale {
                RecordsLockedPlaceholder(text: text, kind: .scale) {
                    scene.paywallSheet = browsing.scale == .life ? .life : .charts
                }
            } else {
                Group {
                switch browsing.scale {
                case .month:
                    RecordsMonthGrid(
                        queries: queries,
                        preferences: preferences,
                        text: text,
                        cells: renderedCells,
                        selectedDayKey: browsing.selectedDayKey,
                        onSelect: selectFromTap,
                        onOpen: openDay
                    )
                    markLegend
                case .week:
                    RecordsWeekStrips(
                        queries: queries,
                        preferences: preferences,
                        text: text,
                        cells: renderedCells,
                        selectedDayKey: browsing.selectedDayKey,
                        onSelect: selectFromTap,
                        onOpen: openDay
                    )
                    markLegend
                case .year:
                    // Expansion reads a selected month with the same metrics
                    // and allocation as the month screen, without another axis.
                    if expandedPresentation {
                        RecordsYearMonthsView(
                            queries: queries,
                            preferences: preferences,
                            text: text,
                            recordsRevision: records.contentRevision,
                            cells: renderedCells,
                            days: days,
                            selectedMonth: browsing.selectedYearMonth,
                            onOpenMonth: openMonth
                        ) { month in
                            if browsing.selectedYearMonth != month { selectionFeedback += 1 }
                            browsing.selectedYearMonth = month
                            browsing.yearCalloutMonth = month
                            browsing.yearSelectionDate = nil
                        }
                    } else {
                        RecordsYearCanvas(
                            queries: queries,
                            preferences: preferences,
                            text: text,
                            cells: renderedCells,
                            selectedMonth: browsing.selectedYearMonth,
                            calloutMonth: $browsing.yearCalloutMonth,
                            selectedDate: $browsing.yearSelectionDate,
                            onOpenMonth: openMonth
                        ) { month in
                            if browsing.selectedYearMonth != month { selectionFeedback += 1 }
                            browsing.selectedYearMonth = month
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
                    if browsing.scale != .life { pinch = value.magnification }
                }
                .onEnded { value in
                    guard browsing.scale != .life else {
                        pinch = 1
                        return
                    }
                    if value.magnification > 1.22 {
                        if browsing.scale == .year {
                            openSelectedMonth()
                        } else {
                            switchScale(to: browsing.scale.zoomedIn)
                        }
                    } else if value.magnification < 0.82 {
                        switchScale(to: browsing.scale.zoomedOut)
                    }
                    pinch = 1
                }
        )
    }

    private var markLegend: some View {
        VStack(alignment: .center, spacing: 4) {
            RecordsMarkLegend(text: text, includesLock: !queries.plus.isAuthorized)
            Text(text.t("recordsHeatScale"))
                .font(.caption2)
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func lifeCanvas(expandedPresentation: Bool) -> some View {
        if let profile = records.state.lifeProfile {
            // Stage selection and foreground refresh must use the same civil
            // day, rather than moving the career split on every body update.
            let now = preferences.recordsCalendar.startOfDay(for: .now)
            let profileStages = LifeStageCalculator.stages(
                profile: profile,
                calendar: preferences.recordsCalendar,
                now: now
            )
            let stages = LifeStageCalculator.canvasStages(profileStages, now: now)
            if let bounds = LifeStageCalculator.timelineBounds(stages: profileStages, now: now) {
                RecordsLifeCanvas(
                    preferences: preferences,
                    text: text,
                    stages: stages,
                    bounds: bounds,
                    selectedStageID: browsing.selectedLifeStageID,
                    referenceDate: now,
                    selectedDate: $browsing.lifeSelectionDate,
                    showsStageLegend: !expandedPresentation
                ) { stage in
                    browsing.selectedLifeStageID = stage.id
                    selectionFeedback += 1
                }
            } else {
                lifeSetupCard
            }
            if profile.retirementOn == nil, !expandedPresentation {
                Button(text.t("lifeSetRetirement"), action: openLifeProfile)
                    .font(.footnote.weight(.semibold))
            }
        } else {
            lifeSetupCard
        }
    }

    private func setExpanded(_ value: Bool) {
        guard canExpand else { return }
        withAnimation(reduceMotion ? OWCMotion.reduced : OWCMotion.recordsExpansion) {
            browsing.expanded[browsing.scale] = value
        }
    }

    private var lifeSetupCard: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(text.t("recordsLifeSetupTitle"))
                    .font(.body.weight(.medium))
                Text(text.t("recordsLifeSetupBody"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button(text.t("recordsLifeSetupNow"), action: openLifeProfile)
                        .font(.body.weight(.semibold))
                    Button(text.t("recordsLifeSetupLater")) {
                        preferences.lifeSetupPromptDismissed = true
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
            damagedArchiveCard
                .padding(.horizontal, OWCDesign.pageInset)
            Spacer()
        }
        .padding(.top, 14)
    }

    private var damagedArchiveCard: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(text.t("recordsArchiveDamagedTitle"))
                    .font(.body.weight(.medium))
                Text(text.t("recordsArchiveDamagedBody"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                Button(text.t("recordsArchiveQuarantine")) { confirmsQuarantine = true }
                    .font(.body.weight(.semibold))
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var periodTitle: String {
        let window = queries.recordsWindow(for: browsing.scale, anchor: browsing.anchor)
        switch browsing.scale {
        case .week:
            return "\(queries.formatRecordsMonthDay(window.0)) – \(queries.formatRecordsMonthDay(window.1))"
        case .month:
            return queries.formatRecordsMonthYear(window.0)
        case .year:
            return "\(preferences.recordsCalendar.component(.year, from: window.0))"
        case .life:
            return text.t("recordsScaleLife")
        }
    }

    private var scaleBinding: Binding<RecordsScale> {
        Binding(
            get: { browsing.scale },
            set: { switchScale(to: $0) }
        )
    }

    private func selectedMonthTitle(_ month: Int) -> String {
        var parts = preferences.recordsCalendar.dateComponents([.year], from: browsing.anchor)
        parts.month = month
        parts.day = 1
        return queries.formatRecordsMonthYear(preferences.recordsCalendar.date(from: parts) ?? browsing.anchor)
    }

    private func switchScale(to nextScale: RecordsScale) {
        guard nextScale != browsing.scale else { return }
        let changesDailyScale = (browsing.scale == .week || browsing.scale == .month)
            && (nextScale == .week || nextScale == .month)
        // Week and month are frequent ways to inspect the same daily data.
        // The chart bridges the replacement itself; its conclusion updates in
        // place. Year and life change the question and keep the page transition.
        withAnimation(
            changesDailyScale ? nil : (reduceMotion ? OWCMotion.reduced : OWCMotion.recordsScaleChange)
        ) {
            loadGeneration += 1
            browsing.scale = nextScale
            preferences.preferredRecordsScale = nextScale
            days = []
            cells = []
            summary = nil
            browsing.selectedDayKey = nil
            browsing.selectedYearMonth = nextScale == .year
                ? preferences.recordsCalendar.component(.month, from: .now)
                : nil
            browsing.selectedLifeStageID = nil
            browsing.yearCalloutMonth = nil
            browsing.yearSelectionDate = nil
            browsing.lifeSelectionDate = nil
            browsing.expanded = [:]
            pinch = 1
            if nextScale == .life { selectCurrentLifeStage() }
        }
        scaleFeedback += 1
        Task { await load() }
    }

    private var shouldOfferLifeSetup: Bool {
        queries.plus.isAuthorized
            && records.state.lifeProfile == nil
            && !preferences.lifeSetupPromptDismissed
            && browsing.scale == .month
    }

    private var showsTodayButton: Bool {
        guard browsing.scale != .life else { return false }
        let window = queries.recordsWindow(for: browsing.scale, anchor: browsing.anchor)
        let today = preferences.recordsCalendar.startOfDay(for: .now)
        return today < preferences.recordsCalendar.startOfDay(for: window.0)
            || today > preferences.recordsCalendar.startOfDay(for: window.1)
    }

    private func returnToToday() {
        withAnimation(reduceMotion ? OWCMotion.reduced : .easeOut(duration: 0.2)) {
            browsing.anchor = .now
            if browsing.scale == .year {
                browsing.selectedYearMonth = preferences.recordsCalendar.component(.month, from: .now)
                browsing.yearCalloutMonth = nil
                browsing.yearSelectionDate = nil
            }
        }
        selectionFeedback += 1
        Task { await load() }
    }

    private func openLifeProfile() {
        if queries.plus.isAuthorized {
            browsing.showsLifeEditor = true
        } else {
            scene.paywallSheet = .life
        }
    }

    private func selectCurrentLifeStage(now: Date = .now) {
        guard let profile = records.state.lifeProfile else {
            browsing.selectedLifeStageID = nil
            return
        }
        let stages = LifeStageCalculator.canvasStages(
            LifeStageCalculator.stages(profile: profile, calendar: preferences.recordsCalendar, now: now), now: now
        )
        let current = LifeStageCalculator.stage(at: now.addingTimeInterval(-0.001), stages: stages)
        browsing.selectedLifeStageID = current?.kind == .retirement ? nil : current?.id
    }

    private func selectFromTap(_ cell: RecordsDayCell) {
        if browsing.selectedDayKey == cell.dayKey {
            openDay(cell)
        } else {
            selectionFeedback += 1
            browsing.selectedDayKey = cell.dayKey
        }
    }

    private func openDay(_ cell: RecordsDayCell) {
        guard cell.appearance != .locked else {
            scene.paywallSheet = .charts
            return
        }
        withAnimation(reduceMotion ? OWCMotion.reduced : OWCMotion.navigation) {
            browsing.quickDay = RecordsDayIdentified(dayKey: cell.dayKey)
        }
    }

    private func openSelectedMonth() {
        guard let selectedMonth = browsing.selectedYearMonth else { return }
        openMonth(selectedMonth)
    }

    private func openMonth(_ month: Int) {
        browsing.yearCalloutMonth = nil
        browsing.yearSelectionDate = nil
        var parts = preferences.recordsCalendar.dateComponents([.year], from: browsing.anchor)
        parts.month = month
        parts.day = 1
        browsing.anchor = preferences.recordsCalendar.date(from: parts) ?? browsing.anchor
        switchScale(to: .month)
    }

    @ViewBuilder
    private func recordsDestination(_ route: RecordsRoute) -> some View {
        Group {
            switch route {
            case .allRecords:
                RecordsAllRecordsView(queries: queries, preferences: preferences, text: text)
            case .yearList(let year):
                RecordsYearRecordsView(queries: queries, preferences: preferences, text: text, year: year)
            case .monthList(let year, let month):
                RecordsMonthRecordsView(
                    queries: queries,
                    preferences: preferences,
                    text: text,
                    year: year,
                    month: month
                )
            case .day(let dayKey):
                dayCanvas(dayKey: dayKey)
            case .conflictCenter:
                RecordsConflictCenter(
                    records: records,
                    queries: queries,
                    preferences: preferences,
                    text: text
                )
            }
        }
        .onAppear { writeQASurfaceMarker(qaSurfaceName(for: route)) }
    }

    private func dayCanvas(dayKey: String) -> some View {
        RecordsDayCanvasView(
            records: records,
            queries: queries,
            actions: actions,
            preferences: preferences,
            focus: focus,
            text: text,
            hours: hours,
            dayKey: dayKey
        )
    }

    private func writeQASurfaceMarker(_ surface: String) {
        scene.writeQASurfaceMarker(
            surface,
            onboardingComplete: preferences.onboardingComplete,
            hasSeenPlusIntro: queries.plus.hasSeenIntro
        )
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
        var annualBonusEnabled: Bool
        var annualBonusMonths: Double
        var hours: ScheduleHoursConfiguration
    }

    private var currentLoadSignature: RecordsLoadSignature {
        RecordsLoadSignature(
            scale: browsing.scale,
            anchor: browsing.anchor,
            revision: records.contentRevision,
            authorized: queries.plus.isAuthorized,
            dayKey: RecordJSON.dayKey(.now, calendar: preferences.recordsCalendar),
            timeZone: preferences.recordsTimeZone.identifier,
            language: preferences.languageCode,
            salaryEnabled: preferences.salaryEnabled,
            salaryType: preferences.salaryType,
            salaryAmount: preferences.salaryAmount,
            monthlyWorkingDays: preferences.monthlyWorkingDays,
            annualBonusEnabled: preferences.annualBonusEnabled,
            annualBonusMonths: preferences.annualBonusMonths,
            hours: hours
        )
    }

    private func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let requestedScale = browsing.scale
        let requestedAnchor = browsing.anchor
        let signature = currentLoadSignature
        if browsing.scale == .life {
            days = []
            cells = []
            summary = nil
            if browsing.selectedLifeStageID == nil { selectCurrentLifeStage() }
            // The stage grid is immediate. The expensive allocation is requested
            // once its card becomes visible; later refreshes retain the result.
            loadedSignature = signature
            return
        }
        if requestedScale == .year, browsing.selectedYearMonth == nil {
            browsing.selectedYearMonth = preferences.recordsCalendar.component(.month, from: .now)
        }
        let window = queries.recordsWindow(for: requestedScale, anchor: requestedAnchor)
        // One day of lead-in, because the shift that ends at 06:00 on the first
        // of the month started the night before and still belongs to that
        // morning. The extra day is never drawn.
        let leadIn = preferences.recordsCalendar.date(byAdding: .day, value: -1, to: window.0) ?? window.0
        let resolved = await queries.prepareRecordsDisplayDays(from: leadIn, through: window.1)
        guard generation == loadGeneration,
              requestedScale == browsing.scale,
              requestedAnchor == browsing.anchor
        else { return }
        let firstKey = RecordJSON.dayKey(window.0, calendar: preferences.recordsCalendar)
        days = resolved
        var built: [RecordsDayCell] = []
        for (index, day) in resolved.enumerated() where day.dayKey >= firstKey {
            built.append(
                queries.recordsDayCell(
                    for: day,
                    previous: index > 0 ? resolved[index - 1] : nil,
                    includesLifeProjection: true
                )
            )
        }
        cells = built
        summary = queries.recordsHeadline(cells: cells, days: resolved)
        if let selected = browsing.selectedDayKey, !cells.contains(where: { $0.dayKey == selected }) {
            browsing.selectedDayKey = nil
        }
        loadedSignature = signature
    }
}

private struct LifeStageSheetItem: Identifiable {
    var id: LifeStageKind { stage.kind }
    var stage: LifeStageSpan
}

private struct LifeStageDetailSheet: View {
    let records: RecordCoordinator
    let preferences: PreferencesStore
    let text: AppText
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
                            Text(text.t(stage.kind.titleKey))
                                .font(.title2.weight(.semibold))
                            Text(rangeLabel)
                                .font(.body)
                                .foregroundStyle(OWCDesign.secondary)
                        }
                    }

                    if let start = stage.start {
                        let end = stage.end ?? .now
                        let days = max(0, preferences.recordsCalendar.dateComponents([.day], from: start, to: end).day ?? 0)
                        let elapsedDays = max(0, min(days, preferences.recordsCalendar.dateComponents([.day], from: start, to: .now).day ?? 0))
                        let remainingDays = stage.end == nil ? nil : max(0, days - elapsedDays)
                        let progress = LifeStageCalculator.progress(from: start, to: end, at: .now)

                        OWCGroupCard {
                            LazyVGrid(
                                columns: [GridItem(.flexible()), GridItem(.flexible())],
                                alignment: .leading,
                                spacing: 10
                            ) {
                                detailMetric(
                                    text.t("lifeStageDurationTitle"),
                                    text.t("lifeStageDuration", values: [
                                        "years": text.formatCount(days / 365),
                                        "days": text.formatCount(days),
                                    ])
                                )
                                detailMetric(text.t("lifeStageAgeRange"), ageRange(from: start, to: end))
                                detailMetric(text.t("lifeStageElapsed"), text.formatDays(Double(elapsedDays)))
                                detailMetric(
                                    text.t("lifeStageRemaining"),
                                    remainingDays.map { text.formatDays(Double($0)) } ?? "—"
                                )
                            }
                            .padding(14)
                        }

                        if stage.end != nil {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(text.t("progress"))
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(OWCDesign.secondary)
                                    Spacer()
                                    Text(text.formatPercent(progress * 100, fractionDigits: 2))
                                        .font(.footnote.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(OWCDesign.orangeDeep)
                                }
                                ProgressView(value: progress)
                                    .tint(OWCDesign.orangeDeep)
                            }
                        }

                        Text(text.t("lifeWeeksUnit", values: ["count": text.formatCount(days / 7)]))
                            .font(.body.weight(.medium))

                        if let stageEnd = stage.end, let bounds = timelineBounds {
                            let span = bounds.1.timeIntervalSince(bounds.0)
                            if span > 0 {
                                let share = stageEnd.timeIntervalSince(start) / span * 100
                                Text(text.t("lifeStageShare", values: ["percent": text.formatPercent(share)]))
                                    .font(.body)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if stage.startPrecision != nil {
                            Text(text.t(stage.startPrecision == .year ? "lifePrecisionYear" : "lifePrecisionDay"))
                        }
                        if stage.endPrecision != nil, stage.endPrecision != stage.startPrecision {
                            Text(text.t(stage.endPrecision == .year ? "lifePrecisionYear" : "lifePrecisionDay"))
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(OWCDesign.page)
            .navigationTitle(text.t(stage.kind.titleKey))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var timelineBounds: (Date, Date)? {
        guard let profile = records.state.lifeProfile else { return nil }
        return LifeStageCalculator.timelineBounds(
            stages: LifeStageCalculator.stages(profile: profile, calendar: preferences.recordsCalendar),
            now: .now
        )
    }

    private func ageRange(from start: Date, to end: Date) -> String {
        guard let profile = records.state.lifeProfile else { return "—" }
        var resolved = profile
        resolved.migrateLegacyFields(calendar: preferences.recordsCalendar)
        guard let birth = resolved.bornOn?.calculationAnchor(in: preferences.recordsCalendar) else { return "—" }
        let startAge = max(0, preferences.recordsCalendar.dateComponents([.year], from: birth, to: start).year ?? 0)
        let endAge = max(startAge, preferences.recordsCalendar.dateComponents([.year], from: birth, to: end).year ?? startAge)
        return "\(text.formatCount(startAge))–\(text.formatCount(endAge))"
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
        let calendar = preferences.recordsCalendar
        let startYear = stage.start.map { text.formatYear(calendar.component(.year, from: $0)) }
        let endYear = stage.end.map { text.formatYear(calendar.component(.year, from: $0)) }
        switch (startYear, endYear) {
        case (nil, nil):
            return text.t("lifeUnset")
        case (let start?, let end?):
            return text.t("weekdayRange", values: ["start": start, "end": end])
        case (let start?, nil):
            return start
        case (nil, let end?):
            return end
        }
    }
}
