import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RecordsDesignView: View {
    let store: OffWorkStore
    @State private var scale: RecordsScale
    @State private var anchor = Date()
    @State private var selectedDayKey: String?
    @State private var selectedYearMonth: Int?
    @State private var selectedLifeStageKind: LifeStageKind?
    @State private var presentedStage: LifeStageSpan?
    @State private var days: [DayResolution] = []
    @State private var cells: [RecordsDayCell] = []
    @State private var summary: RecordsHeadlineSummary?
    @State private var detail: RecordsDayDetail?
    @State private var expanded: [RecordsScale: Bool]
    @State private var pinch: CGFloat = 1
    @State private var scaleFeedback = 0
    @State private var selectionFeedback = 0
    @State private var showsLifeEditor = false
    @State private var confirmsQuarantine = false
    @State private var loadGeneration = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExpanded: Bool { expanded[scale] == true }
    private var canExpand: Bool { scale == .year || scale == .life }

    init(store: OffWorkStore) {
        self.store = store
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
        .navigationTitle("")
        // Expansion is a contained browsing mode. The calendar remains inside
        // the same navigation stack, but the surrounding tab and navigation
        // chrome must get out of the way so the canvas can use the available
        // width and height on both phones and iPad split panes.
        .toolbar(isExpanded ? .hidden : .visible, for: .navigationBar)
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
        .sheet(item: Binding(
            get: { presentedStage.map(LifeStageSheetItem.init) },
            set: { if $0 == nil { presentedStage = nil } }
        )) { item in
            LifeStageDetailSheet(store: store, stage: item.stage)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
                recordsHeader

                if let banner = store.records.archiveBanner {
                    archiveBannerCard(banner)
                }

                RecordsScalePicker(store: store, scale: scaleBinding)

                visualization(expandedPresentation: false)

                if scale == .week || scale == .month {
                    RecordsDayDetailCard(
                        store: store,
                        detail: detail,
                        locked: selectedIsLocked,
                        onUnlock: { store.paywallSheet = .charts },
                        onEdit: editSelected
                    )
                } else if scale == .year, let selectedYearMonth {
                    RecordsYearSelectionCard(
                        store: store,
                        month: selectedYearMonth,
                        cells: yearSelectionCells,
                        summary: yearSelectionSummary
                    )
                }
                if shouldOfferLifeSetup {
                    lifeSetupCard
                }
                if scale != .life, hasActualRecords {
                    RecordsHeadlineView(
                        store: store,
                        summary: summary,
                        onUnlock: { store.paywallSheet = .charts }
                    )
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 6)
            .padding(.bottom, 104)
        }
        .scrollIndicators(.hidden)
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

    private var recordsHeader: some View {
        HStack(spacing: 8) {
            Text(store.t("recordsTitle"))
                .font(.largeTitle.bold())
                .tracking(-0.85)
            Spacer(minLength: 8)
            if showsTodayButton {
                Button(action: returnToToday) {
                    Image(systemName: "scope")
                        .frame(width: 44, height: 44)
                        .background(OWCDesign.control, in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(OWCDesign.accent)
                .accessibilityLabel(store.t("recordsToday"))
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
            NavigationLink(value: RecordsRoute.allRecords) {
                Image(systemName: "list.bullet.rectangle")
                    .frame(width: 44, height: 44)
                    .background(OWCDesign.control, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(OWCDesign.secondary)
            .accessibilityLabel(store.t("recordsAllRecords"))
        }
        .padding(.horizontal, max(0, OWCDesign.contentInset - OWCDesign.pageInset))
        .padding(.top, 8)
        .animation(reduceMotion ? OWCMotion.reduced : .easeOut(duration: 0.18), value: showsTodayButton)
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
                case .week:
                    RecordsWeekStrips(store: store, cells: cells, selectedDayKey: selectedDayKey) { cell in
                        select(cell)
                    }
                case .year:
                    RecordsYearCanvas(
                        store: store,
                        cells: cells,
                        selectedMonth: selectedYearMonth,
                        showsMonthPicker: !expandedPresentation
                    ) { month in
                        selectedYearMonth = month
                        selectionFeedback += 1
                    }
                case .life:
                    lifeCanvas(expandedPresentation: expandedPresentation)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .scaleEffect(reduceMotion || pinch == 1 ? 1 : max(0.96, min(1.04, pinch)))
        .gesture(
            MagnificationGesture()
                .onChanged { pinch = $0 }
                .onEnded { value in
                    if value > 1.22 {
                        switchScale(to: scale.zoomedIn)
                    } else if value < 0.82 {
                        switchScale(to: scale.zoomedOut)
                    }
                    pinch = 1
                }
        )
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
                    presentedStage = stage
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
            presentedStage = nil
            expanded = [:]
            pinch = 1
            if nextScale == .life { selectCurrentLifeStage() }
        }
        scaleFeedback += 1
        Task { await load(selectingToday: nextScale == .week || nextScale == .month) }
    }

    private var yearSelectionSummary: RecordsHeadlineSummary? {
        let keys = Set(yearSelectionCells.map(\.dayKey))
        return store.recordsHeadline(
            cells: yearSelectionCells,
            days: days.filter { keys.contains($0.dayKey) }
        )
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
        selectedLifeStageKind = LifeStageCalculator.stage(at: now, stages: stages)?.kind
    }

    private func select(_ cell: RecordsDayCell) {
        selectedDayKey = cell.dayKey
        selectionFeedback += 1
        if let resolution = days.first(where: { $0.dayKey == cell.dayKey }) {
            detail = store.recordsDayDetail(for: resolution, includesLifeProjection: true)
        } else {
            detail = nil
        }
    }

    private func editSelected() {
        guard let selectedDayKey else { return }
        store.openDayEditor(dayKey: selectedDayKey)
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
            RecordDayDetailHost(store: store, dayKey: dayKey)
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
            return
        }
        if requestedScale == .year, selectedYearMonth == nil {
            selectedYearMonth = store.recordsCalendar.component(.month, from: .now)
        }
        let window = store.recordsWindow(for: requestedScale, anchor: requestedAnchor)
        let resolved = await store.prepareRecordsDisplayDays(from: window.0, through: window.1)
        guard generation == loadGeneration,
              requestedScale == scale,
              requestedAnchor == anchor
        else { return }
        days = resolved
        cells = resolved.map { store.recordsDayCell(for: $0, includesLifeProjection: true) }
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
