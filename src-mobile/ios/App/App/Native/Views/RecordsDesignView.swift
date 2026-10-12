import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RecordsDesignView: View {
    @Environment(SceneState.self) private var scene
    @ScaledMetric(relativeTo: .subheadline) private var entryIconWidth: CGFloat = 22
    let records: RecordCoordinator
    let queries: RecordsQueries
    let actions: RecordsActions
    let shifts: ShiftSessionStore
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
    /// Plan 020 §5: recorded overtime is open to free users, as one number.
    @State private var freeOvertimeMs: Double?
    @State private var lifetimeOvertimeMs: Double?
    @State private var pinch: CGFloat = 1
    @State private var scaleFeedback = 0
    @State private var selectionFeedback = 0
    @State private var confirmsQuarantine = false
    @State private var loadGeneration = 0
    @State private var loadedSignature: RecordsLoadSignature?
    @State private var showsCompactRootBar = false
    @State private var canvasWidth: CGFloat = 0
    @State private var guidesLeaveSetup = false
    @State private var leaveSetupSaved = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 3.2.2: every scale fits the page, so the chart no longer expands.
    private let isExpanded = false
    /// iPad keeps its custom root chrome so switching split-view tabs cannot
    /// resize the detail pane under a cross-fade. Phones use the system bar.
    private var usesCustomRootHeader: Bool { usesOwnHeader }

    init(
        records: RecordCoordinator,
        queries: RecordsQueries,
        actions: RecordsActions,
        shifts: ShiftSessionStore,
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
        self.shifts = shifts
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

    @Environment(\.usesExpandedPhoneColumns) private var usesPhoneColumns

    var body: some View {
        Group {
            if records.archiveBanner == .damaged {
                damagedState
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
        .sheet(isPresented: $guidesLeaveSetup, onDismiss: {
            // Only a saved first balance continues on to the time off page.
            guard leaveSetupSaved else { return }
            leaveSetupSaved = false
            scene.recordsPath.append(.leave)
        }) {
            LeaveBalanceEditor(
                shifts: shifts,
                editing: .init(balance: LeaveView.newBalance(), isNew: true),
                isGuided: true
            ) { leaveSetupSaved = true }
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
            if (usesPhoneColumns || canvasWidth >= Self.twoColumnMinimum) && !dynamicTypeSize.isAccessibilitySize {
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
                            .frame(maxWidth: usesPhoneColumns ? canvasWidth * 0.42 : Self.conclusionColumnWidth)
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
        VStack(alignment: .leading, spacing: 12) {
            // The life scale is behind Plus, so this conclusion is too. A
            // locked life view must not print a projected number under a
            // locked canvas.
            if browsing.scale == .life, queries.plus.isAuthorized, records.state.lifeProfile != nil {
                lifeConclusion
            }
            // Life only totals overtime actually recorded, for everyone; the
            // projected career never adds to it.
            if browsing.scale == .life, let lifetimeOvertimeMs {
                RecordsOvertimeLine(text: text, milliseconds: lifetimeOvertimeMs, titleKey: "recordsOvertimeRecordedLife")
            }
            if shouldOfferLifeSetup {
                lifeSetupCard
            }
            // Plus reads the same number inside its summary. A free user gets
            // just this line; the week already prints it on the calendar.
            if browsing.scale == .month || browsing.scale == .year,
               !queries.plus.isAuthorized, let freeOvertimeMs {
                RecordsOvertimeLine(text: text, milliseconds: freeOvertimeMs)
            }
            if browsing.scale != .life, queries.plus.isAuthorized {
                if let summary {
                    periodConclusion(summary)
                } else if !chartIsLoading {
                    RecordsEmptyPeriodCard(text: text, title: periodTitle)
                }
            }
        }
    }

    @ViewBuilder
    private func periodConclusion(_ summary: RecordsHeadlineSummary) -> some View {
        RecordsInsightCard(insight: insight(for: summary))
        if summary.allocationDays > 0 {
            RecordsAllocationCard(
                text: text,
                title: text.t("recordsTimeBreakdown"),
                share: summary.allocation,
                footnote: text.t(summary.sleepSourceKey == "recordsSleepFromHealth"
                    ? "recordsAllocationFootnoteHealth" : "recordsAllocationFootnoteSettings")
            )
        }
        if let income = summary.actualForecast?.total.earnings ?? summary.estimatedIncome {
            RecordsPayCard(
                text: text,
                preferences: preferences,
                title: text.t("recordsPayTitle", values: ["period": payPeriodLabel]),
                total: income,
                earned: summary.actualForecast?.actual.earnings
            )
        }
    }

    @ViewBuilder
    private var lifeConclusion: some View {
        if let model = life.cachedLifeViewModel {
            if model.allocation.dayLengthMs > 0, model.allocation.workMs > 0 {
                RecordsLifeOwnTimeCard(text: text, share: model.allocation)
                RecordsAllocationCard(
                    text: text,
                    title: text.t("lifeWhereTimeGoes"),
                    share: model.allocation,
                    unit: .years
                )
            } else {
                RecordsLifeAllocationPlaceholder(text: text)
            }
            if let income = model.income {
                RecordsLifetimeIncomeCard(
                    text: text,
                    preferences: preferences,
                    income: income,
                    method: text.lifeIncomeMethodText(decline: records.state.lifeProfile?.futureIncomeDecline)
                )
            }
        } else {
            RecordsLifeAllocationPlaceholder(text: text, isLoading: true)
        }
    }

    private var payPeriodLabel: String {
        let window = queries.recordsWindow(for: browsing.scale, anchor: browsing.anchor)
        switch browsing.scale {
        case .week: return periodTitle
        case .month: return queries.formatRecordsMonthShort(window.0)
        case .year, .life:
            return text.t("recordsYearLabel", values: [
                "year": text.formatYear(preferences.recordsCalendar.component(.year, from: window.0)),
            ])
        }
    }

    /// One conclusion per scale, then the numbers that back it.
    private func insight(for summary: RecordsHeadlineSummary) -> RecordsInsight {
        let forecast = summary.actualForecast
        let workedMs = forecast.map { $0.actual.hours * 3_600_000 }
            ?? Double(summary.regularWorkMs + summary.overtimeMs)
        let overtimeMs = forecast.map { $0.actualOvertimeHours * 3_600_000 } ?? Double(summary.overtimeMs)
        let plannedDays = Int((forecast?.forecast.days ?? 0).rounded())
        let plannedMs = (forecast?.forecast.hours ?? 0) * 3_600_000
        let overtimeText = text.formatRelativeDuration(overtimeMs)
        let looks = cells.map { RecordsDayLook($0, preferences: preferences) }
        let recordedDays = browsing.scale == .week ? looks.filter(\.hasSolidHours).count : summary.workdays
        var chips: [RecordsInsightChip] = []
        if recordedDays > 0 {
            chips.append(.init(mark: .work, title: text.t("recordsWorkdayCount", values: ["count": text.formatCount(recordedDays)])))
        }
        if overtimeMs > 0 {
            chips.append(.init(mark: .overtime, title: text.t("recordsOvertimeAmount", values: ["duration": overtimeText])))
        }
        if plannedDays > 0, browsing.scale != .week {
            chips.append(.init(mark: .planned, title: text.t("recordsPlannedWorkdays", values: ["count": text.formatCount(plannedDays)])))
        }
        switch browsing.scale {
        case .week, .life:
            // The calendar above counts what has happened; this sentence
            // counts the same days, so the two never disagree.
            let recorded = looks.filter(\.hasSolidHours)
            let worked = max(summary.completedScheduledWorkdays, recorded.count)
            var sentences = worked == 0 ? [] : [text.t("recordsInsightWeekBody", values: [
                "worked": text.formatCount(worked),
                "recorded": text.formatCount(recorded.count),
                "hours": text.formatRelativeDuration(Double(recorded.reduce(Int64(0)) { $0 + $1.totalMs })),
            ])]
            let empty = looks.first { $0.isUnrecordedWorkday && !$0.cell.isToday }
            if let empty {
                sentences.append(text.t("recordsInsightEmptyDay", values: ["date": queries.formatRecordsMonthDay(empty.cell.date)]))
            }
            return RecordsInsight(
                eyebrow: periodTitle,
                hero: overtimeMs > 0
                    ? text.t("recordsOvertimeAmount", values: ["duration": overtimeText])
                    : text.t("recordsNoOvertime"),
                body: sentences.isEmpty ? nil : RecordsInsight.joinSentences(sentences),
                actionTitle: empty == nil ? nil : text.t("recordsInsightFillDay"),
                action: empty.map { look in { openDay(look.cell) } },
                chips: chips
            )
        case .month:
            var sentences = RecordsHolidaySummary.counts(looks).map { name, count in
                text.t("recordsInsightHolidayOff", values: ["name": name, "count": text.formatCount(count)])
            }
            if plannedDays > 0 {
                sentences.append(text.t("recordsInsightPlannedAhead", values: [
                    "count": text.formatCount(plannedDays),
                    "hours": text.formatRelativeDuration(plannedMs),
                ]))
            }
            return RecordsInsight(
                eyebrow: text.t("recordsInsightMonthWorked", values: ["month": payPeriodLabel]),
                hero: text.formatRelativeDuration(workedMs),
                body: sentences.isEmpty ? nil : RecordsInsight.joinSentences(sentences),
                actionTitle: text.t("leavePlanAction"),
                action: openLeavePlanning,
                chips: chips
            )
        case .year:
            let averageDay = summary.workdays > 0 ? Double(summary.regularWorkMs) / Double(summary.workdays) : 8 * 3_600_000
            let extraDays = averageDay > 0 ? overtimeMs / averageDay : 0
            let month = browsing.selectedYearMonth ?? preferences.recordsCalendar.component(.month, from: .now)
            return RecordsInsight(
                eyebrow: text.t("recordsInsightYearOvertime", values: ["year": payPeriodLabel]),
                hero: overtimeMs > 0 ? overtimeText : text.t("recordsNoOvertime"),
                body: [
                    overtimeMs > 0 ? text.t("recordsInsightExtraDays", values: ["days": text.formatDecimal(extraDays)]) : nil,
                    text.t("recordsInsightYearWorked", values: ["hours": text.formatRelativeDuration(workedMs)]),
                ].compactMap { $0 }.joinedSentences,
                actionTitle: text.t("recordsOpenSelectedMonth", values: ["month": queries.formatRecordsMonth(
                    preferences.recordsCalendar.date(from: DateComponents(
                        year: preferences.recordsCalendar.component(.year, from: browsing.anchor), month: month, day: 1
                    )) ?? browsing.anchor
                )]),
                action: { openMonth(month) },
                chips: chips
            )
        }
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
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
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

    private func holidayCoverageNotice(_ cells: [RecordsDayCell]) -> some View {
        HolidayCoverageNoticeView(
            regionIdentifier: preferences.isExtendedScheduleEnabled
                ? preferences.extendedScheduleContent?.holidayRegionIdentifier : nil,
            dates: cells.map(\.date), timeZone: preferences.recordsTimeZone, text: text
        )
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
        VStack(alignment: .leading, spacing: 0) {
            if browsing.scale != .life {
                periodHeader
                    .padding(.bottom, 12)
                Divider()
                    .padding(.bottom, 12)
            }

            if lockedScale {
                lockedScalePreview
            } else {
                Group {
                    switch browsing.scale {
                    case .week:
                        RecordsWeekChart(
                            queries: queries,
                            preferences: preferences,
                            text: text,
                            cells: renderedCells,
                            selectedDayKey: selectedDayLook(renderedCells)?.cell.dayKey,
                            isAuthorized: queries.plus.isAuthorized,
                            overtimeMs: freeOvertimeMs,
                            onSelect: selectFromTap,
                            onOpen: openDay
                        )
                        holidayCoverageNotice(renderedCells)
                        daySelectionRow(renderedCells)
                        RecordsCalendarLegend(text: text)
                        freeWindowNote(renderedCells)
                        entries([reportEntry(.week)])
                    case .month:
                        RecordsMonthCalendar(
                            queries: queries,
                            preferences: preferences,
                            text: text,
                            cells: renderedCells,
                            selectedDayKey: selectedDayLook(renderedCells)?.cell.dayKey,
                            onSelect: selectFromTap,
                            onOpen: openDay
                        )
                        holidayCoverageNotice(renderedCells)
                        daySelectionRow(renderedCells)
                        calendarLegend(renderedCells, style: .bars)
                        freeWindowNote(renderedCells)
                        entries([AnyView(leavePlanningEntry), reportEntry(.month)])
                    case .year:
                        RecordsYearCalendar(
                            queries: queries,
                            preferences: preferences,
                            text: text,
                            cells: renderedCells,
                            selectedMonth: browsing.selectedYearMonth,
                            onSelectMonth: { month in
                                if browsing.selectedYearMonth != month { selectionFeedback += 1 }
                                browsing.selectedYearMonth = month
                            },
                            onOpenMonth: openMonth
                        )
                        monthSelectionRow(renderedCells)
                        calendarLegend(renderedCells, style: .dots)
                        entries([reportEntry(.year)])
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

    /// The selected day, or today when nothing is selected and today is on screen.
    private func selectedDayLook(_ cells: [RecordsDayCell]) -> RecordsDayLook? {
        let cell = browsing.selectedDayKey.flatMap { key in cells.first { $0.dayKey == key } }
            ?? cells.first(where: \.isToday)
        return cell.map { RecordsDayLook($0, preferences: preferences) }
    }

    @ViewBuilder
    private func daySelectionRow(_ cells: [RecordsDayCell]) -> some View {
        if let look = selectedDayLook(cells) {
            RecordsSelectionRow(
                title: queries.formatRecordsDayTitle(look.cell.date),
                subtitle: RecordsDayDescription.subtitle(look, text: text)
            ) { openDay(look.cell) }
        }
    }

    @ViewBuilder
    private func monthSelectionRow(_ cells: [RecordsDayCell]) -> some View {
        if let month = browsing.selectedYearMonth {
            let monthCells = cells.filter { preferences.recordsCalendar.component(.month, from: $0.date) == month }
            RecordsSelectionRow(
                title: selectedMonthTitle(month),
                subtitle: RecordsDayDescription.periodSubtitle(monthCells, preferences: preferences, text: text)
            ) { openMonth(month) }
        }
    }

    private func calendarLegend(_ cells: [RecordsDayCell], style: RecordsCalendarLegend.Style) -> some View {
        let looks = cells.map { RecordsDayLook($0, preferences: preferences) }
        return RecordsCalendarLegend(
            text: text,
            style: style,
            showsHolidays: looks.contains(where: \.isHoliday),
            showsMakeup: looks.contains(where: \.isMakeupWorkday)
        )
    }

    @ViewBuilder
    private func freeWindowNote(_ cells: [RecordsDayCell]) -> some View {
        if !queries.plus.isAuthorized, cells.contains(where: { $0.appearance == .locked }) {
            RecordsFreeWindowNote(text: text) { scene.paywallSheet = .charts }
        }
    }

    /// Entry rows under the calendar, each on its own hairline.
    private func entries(_ rows: [AnyView]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Divider()
                row
            }
        }
        .padding(.top, 12)
    }

    /// Year and Life for a free user: a blurred impression of the view and
    /// one card that says what Plus adds.
    private var lockedScalePreview: some View {
        ZStack {
            RecordsLockedPreviewArt(scale: browsing.scale)
                .blur(radius: 8)
                .opacity(0.4)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            RecordsLockedCard(text: text) {
                scene.paywallSheet = browsing.scale == .life ? .life : .charts
            }
            .padding(24)
        }
        .frame(minHeight: browsing.scale == .life ? 420 : 520)
    }

    /// Plan 020: time off from the month a user is looking at. The first
    /// visit without any leave balance sets one up before the page opens.
    private var leavePlanningEntry: some View {
        Button(action: openLeavePlanning) {
            entryLabel(icon: "suitcase", titleKey: "leavePlanAction")
        }
        .buttonStyle(.plain)
    }

    /// Entry rows under the calendar. Symbols differ in width (a suitcase is
    /// wider than a play circle), so each sits in the same gutter and the
    /// titles start on one line.
    private func entryLabel(icon: String, titleKey: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: entryIconWidth)
            Text(text.t(titleKey))
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(OWCDesign.tertiary)
        }
        .font(.subheadline)
        .foregroundStyle(OWCDesign.accent)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    /// Plan 020 §4: the week, month or year on screen, played as a report. It opens
    /// from here whether or not notifications are on.
    private func reportEntry(_ kind: CycleReportKind) -> AnyView {
        AnyView(Button {
            scene.openCycleReport(CycleReportRequest(
                period: queries.reportPeriod(kind, containing: browsing.anchor)
            ))
        } label: {
            entryLabel(icon: "play.circle", titleKey: kind.entryKey)
        }
        .buttonStyle(.plain))
    }

    private func openLeavePlanning() {
        if records.state.leaveBalances.isEmpty {
            guidesLeaveSetup = true
        } else {
            scene.recordsPath.append(.leave)
        }
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
            if let bounds = LifeStageCalculator.timelineBounds(stages: profileStages, now: now) {
                lifeProgress(stages: profileStages, bounds: bounds, now: now)
                    .padding(.bottom, 14)
                RecordsLifeYears(
                    preferences: preferences,
                    text: text,
                    stages: profileStages,
                    bounds: bounds,
                    referenceDate: now,
                    selectedDate: $browsing.lifeSelectionDate
                )
                lifeSelectionRow(stages: profileStages, bounds: bounds, now: now)
                lifeStageList(profileStages)
                    .padding(.top, 12)
            } else {
                lifeSetupCard
            }
            if profile.retirementOn == nil, !expandedPresentation {
                Button(text.t("lifeSetRetirement"), action: openLifeProfile)
                    .font(.footnote.weight(.semibold))
                    .frame(minHeight: 44)
            }
        } else {
            lifeSetupCard
        }
    }

    @ViewBuilder
    private func lifeProgress(stages: [LifeStageSpan], bounds: (Date, Date), now: Date) -> some View {
        let calendar = preferences.recordsCalendar
        let work = stages.first { $0.kind == .work }
        let retirement = stages.first { $0.kind == .retirement }?.start
        if let retirement {
            let progress = LifeStageCalculator.progress(from: bounds.0, to: retirement, at: now)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(text.t("lifeProgressTitle"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(OWCDesign.secondary)
                    Spacer()
                    Text(text.formatPercent(progress * 100, fractionDigits: 0))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(OWCDesign.accent)
                }
                OWCProgressCapsule(fraction: progress, color: OWCDesign.accent, height: 6)
                    .padding(.top, 6)
                if let start = work?.start {
                    let elapsed = max(0, calendar.dateComponents([.year], from: start, to: now).year ?? 0)
                    let remaining = max(0, calendar.dateComponents([.year], from: now, to: retirement).year ?? 0)
                    Text(text.t("lifeCareerElapsed", values: [
                        "elapsed": text.formatCount(elapsed), "remaining": text.formatCount(remaining),
                    ]))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .padding(.top, 4)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func lifeSelectionRow(stages: [LifeStageSpan], bounds: (Date, Date), now: Date) -> some View {
        let calendar = preferences.recordsCalendar
        let date = browsing.lifeSelectionDate ?? now
        let age = max(0, calendar.dateComponents([.year], from: bounds.0, to: date).year ?? 0)
        let currentAge = max(0, calendar.dateComponents([.year], from: bounds.0, to: now).year ?? 0)
        let stage = LifeStageCalculator.stage(at: date, stages: stages)
        var parts = [stage.map { text.t($0.kind.titleKey) } ?? text.t("lifeStageUnset")]
        parts.append(text.t(age == currentAge ? "lifeStagePresent" : age < currentAge ? "lifeYearPast" : "lifeLegendProjected"))
        if stage?.kind == .work, let start = stage?.start {
            let number = (calendar.dateComponents([.year], from: start, to: date).year ?? 0) + 1
            parts.append(text.t("lifeWorkYearNumber", values: ["count": text.formatCount(max(1, number))]))
        }
        return RecordsSelectionRow(
            title: text.t("lifeYearAgeTitle", values: [
                "year": text.formatYear(calendar.component(.year, from: date)),
                "age": text.formatCount(age),
            ]),
            subtitle: parts.joined(separator: " · ")
        )
    }

    private func lifeStageList(_ stages: [LifeStageSpan]) -> some View {
        var seen = Set<LifeStageKind>()
        let unique = stages.filter { $0.kind != .unset && seen.insert($0.kind).inserted }
        return VStack(spacing: 0) {
            ForEach(unique) { stage in
                HStack(spacing: 10) {
                    Circle().fill(stage.kind.owcColor).frame(width: 10, height: 10)
                    Text(text.t(stage.kind.titleKey))
                        .font(.subheadline)
                        .foregroundStyle(OWCDesign.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(stageRange(stage, all: stages))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(OWCDesign.secondary)
                }
                .frame(minHeight: 36)
                .overlay(alignment: .top) { Divider() }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func stageRange(_ stage: LifeStageSpan, all: [LifeStageSpan]) -> String {
        let calendar = preferences.recordsCalendar
        let end = all.last { $0.kind == stage.kind }?.end
        let startYear = stage.start.map { text.formatYear(calendar.component(.year, from: $0)) }
        let endYear = end.map { text.formatYear(calendar.component(.year, from: $0)) }
        switch (startYear, endYear) {
        case let (start?, end?): return OWCText.ltrRange(start, end)
        case let (start?, nil): return "\(start) –"
        case let (nil, end?): return "– \(end)"
        default: return text.t("lifeUnset")
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
            freeOvertimeMs = nil
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
            case .leave:
                LeaveView(shifts: shifts, actions: actions, backTitleKey: "recordsTitle")
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
        case .leave: "records.leave"
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
            let lifetime = await queries.lifetimeRecordedOvertimeMs()
            guard generation == loadGeneration else { return }
            lifetimeOvertimeMs = lifetime
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
        freeOvertimeMs = queries.plus.isAuthorized
            ? nil
            : queries.recordedOvertimeMs(days: resolved, dayKeys: Set(cells.map(\.dayKey)))
        if let selected = browsing.selectedDayKey, !cells.contains(where: { $0.dayKey == selected }) {
            browsing.selectedDayKey = nil
        }
        loadedSignature = signature
    }
}
