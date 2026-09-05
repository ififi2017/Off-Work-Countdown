import SwiftUI

/// iPad uses a native split container for the sidebar and keeps one navigation
/// stack per section. The compact tab bar is a separate view because the
/// system's adaptable tab bar morphs between the two presentations, while this
/// shell deliberately gives them independent horizontal and vertical paths.
struct TabletShellView: View {
    @Bindable var store: OffWorkStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if !sidebarVisible {
                TabletTopTabBar(store: store, showSidebar: showSidebar)
                    .transition(topBarTransition)
                    .zIndex(1)
            }

            NavigationSplitView(columnVisibility: $columnVisibility) {
                TabletSidebar(store: store, hide: hideSidebar)
                    .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 320)
                    // NavigationSplitView wraps its sidebar in a navigation
                    // container. Suppress that column's default bar here, at
                    // the scope that owns it, so the system toggle cannot
                    // reserve a separate row above the app's header.
                    .toolbar(.hidden, for: .navigationBar)
                    .toolbar(removing: .sidebarToggle)
            } detail: {
                selectedDetailStack
                    .background(OWCDesign.page)
            }
            .navigationSplitViewStyle(.balanced)
            .toolbar(removing: .sidebarToggle)
        }
        .animation(shellAnimation, value: columnVisibility)
        .onChange(of: store.presentedRoute) { _, route in
            guard let route else { return }
            if store.selectedTab == .timer {
                store.timerPath.append(route)
            } else {
                if store.selectedTab == .records { store.selectedTab = .settings }
                store.settingsPath.append(route)
            }
            store.presentedRoute = nil
        }
        .onChange(of: store.debugPresentationToken) {
            store.timerPath.removeAll()
            store.recordsPath.removeAll()
            store.settingsPath.removeAll()
        }
        .background(OWCDesign.page)
    }

    private var sidebarVisible: Bool {
        columnVisibility != .detailOnly
    }

    @ViewBuilder
    private var selectedDetailStack: some View {
        switch store.selectedTab {
        case .timer:
            timerStack
        case .records:
            recordsStack
        case .settings:
            settingsStack
        }
    }

    private var timerStack: some View {
        NavigationStack(path: $store.timerPath) {
            tabletTimerRoot
                .navigationDestination(for: AppRoute.self) { route in
                    AppRouteDestination(route: route, store: store)
                }
        }
    }

    private var recordsStack: some View {
        NavigationStack(path: $store.recordsPath) {
            tabletRecordsRoot
        }
    }

    private var settingsStack: some View {
        NavigationStack(path: $store.settingsPath) {
            tabletSettingsRoot
                .navigationDestination(for: AppRoute.self) { route in
                    AppRouteDestination(route: route, store: store)
                }
        }
    }

    private func hideSidebar() {
        withAnimation(shellAnimation) { columnVisibility = .detailOnly }
    }

    private func showSidebar() {
        withAnimation(shellAnimation) { columnVisibility = .all }
    }

    private var shellAnimation: Animation {
        reduceMotion ? OWCMotion.reduced : OWCMotion.navigation
    }

    private var topBarTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

    private var tabletTimerRoot: some View {
        NarrowPaneFallback { isNarrow in
            if isNarrow {
                // Push into this stack rather than take the default, which
                // switches to the settings tab. The sidebar selection should
                // not move because a row on the timer page was tapped.
                TimerDesignView(
                    store: store,
                    wide: false,
                    onOpenSettings: openTimerSettings,
                    timelineActive: store.selectedTab == .timer
                )
            } else {
                TabletTimerView(
                    store: store,
                    isActive: store.selectedTab == .timer
                )
            }
        }
    }

    private var tabletRecordsRoot: some View {
        RecordsDesignView(
            store: store,
            showsSidebarButton: false,
            usesOwnHeader: true
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var tabletSettingsRoot: some View {
        TabletSettingsView(store: store)
    }

    private func openTimerSettings(_ route: AppRoute?) {
        if let route {
            store.timerPath.append(route)
        } else {
            store.settingsPath.removeAll()
            store.selectedTab = .settings
        }
    }
}

private struct TabletTopTabBar: View {
    let store: OffWorkStore
    let showSidebar: () -> Void

    var body: some View {
        ZStack {
            HStack {
                Button(action: showSidebar) {
                    OWCGlassCircleLabel {
                        Image(systemName: "sidebar.left")
                            .foregroundStyle(OWCDesign.primary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.t("showSidebar"))

                Spacer(minLength: 0)
            }

            HStack(spacing: 2) {
                tabButton(.timer, icon: "timer", title: store.t("timerTab"))
                tabButton(.records, icon: "calendar", title: store.t("recordsTab"))
                tabButton(.settings, icon: "slider.horizontal.3", title: store.t("settings"))
            }
            .padding(5)
            .glassEffect(.regular, in: Capsule())
        }
        .frame(minHeight: 48)
        .padding(.horizontal, OWCDesign.rootControlInset)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private func tabButton(_ tab: AppTab, icon: String, title: String) -> some View {
        Button {
            store.selectedTab = tab
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(store.selectedTab == tab ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(store.selectedTab == tab ? Color.white : OWCDesign.primary)
                .padding(.horizontal, 13)
                .frame(minHeight: 34)
                .background(
                    store.selectedTab == tab ? OWCDesign.accent : Color.clear,
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(store.selectedTab == tab ? .isSelected : [])
    }
}

private struct TabletSidebar: View {
    let store: OffWorkStore
    let hide: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader

            VStack(spacing: 4) {
                tabButton(.timer, icon: "timer", title: store.t("timerTab"))
                tabButton(.records, icon: "calendar", title: store.t("recordsTab"))
                tabButton(.settings, icon: "slider.horizontal.3", title: store.t("settings"))
            }

            compactShiftCountdown
            Spacer(minLength: 16)
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .background(.regularMaterial)
    }

    private var sidebarHeader: some View {
        HStack(spacing: 9) {
            Button(action: hide) {
                OWCGlassCircleLabel {
                    Image(systemName: "sidebar.left")
                        .foregroundStyle(OWCDesign.primary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.t("onboardingSidebarTitle"))

            OWCBrandMark()
                .frame(width: 30, height: 30)

            Text(verbatim: OWCBrand.shortName)
                .font(.body.bold())
                .tracking(-0.34)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 18)
    }

    private var compactShiftCountdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let date = store.timerDate(from: timeline.date)
            if store.shouldQuerySnapshot(at: date), let snapshot = store.snapshot(at: date) {
                let phase = store.visualPhase(snapshot: snapshot, at: date)
                let remaining = miniRemaining(snapshot, phase: phase, at: date)

                VStack(alignment: .leading, spacing: 0) {
                    OWCSectionHeader(title: store.t("shiftSection"))

                    VStack(alignment: .leading, spacing: 0) {
                        Text(store.formatDuration(remaining))
                            .font(.title.bold().monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .tracking(-0.8)
                            .owcCountdownTextTransition(milliseconds: remaining)
                        Text(miniCaption(snapshot, phase: phase, at: date))
                            .font(.footnote)
                            .foregroundStyle(OWCDesign.secondary)
                            .padding(.top, 6)
                        GeometryReader { proxy in
                            let fill = miniFill(snapshot, phase: phase, at: date)
                            Capsule().fill(OWCDesign.control)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(OWCDesign.accent)
                                        .frame(width: proxy.size.width * min(1, max(0, fill / 100)))
                                }
                        }
                        .frame(height: 6)
                        .padding(.top, 12)
                    }
                    .padding(16)
                    .background(OWCDesign.card)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(.top, 26)
            }
        }
    }

    private func miniCaption(_ snapshot: NativeShiftSnapshot, phase: TimerVisualPhase, at date: Date) -> String {
        switch phase {
        case .rest: store.t("widgetRestDay")
        case .completed: store.t("offWorkToday")
        case .unscheduled: store.t("unscheduledTitle")
        case .lunch: store.t("lunchInProgress")
        case .overtime: store.t("overtimeTimeLeftCaption")
        case .clockIn: store.t("nextShiftLabelShort")
        case .running, .rulesError:
            snapshot.isBeforeStart(at: date) ? store.t("nextShiftLabelShort") : store.t("timeLeftCaption")
        }
    }

    private func miniRemaining(
        _ snapshot: NativeShiftSnapshot,
        phase: TimerVisualPhase,
        at date: Date
    ) -> Double {
        switch phase {
        case .completed: 0
        case .rest: store.countdownToClockInMs(snapshot: snapshot, at: date)
        case .running where snapshot.isBeforeStart(at: date), .clockIn:
            store.countdownToClockInMs(snapshot: snapshot, at: date)
        default:
            snapshot.heroRemainingMs(at: date)
        }
    }

    private func miniFill(
        _ snapshot: NativeShiftSnapshot,
        phase: TimerVisualPhase,
        at date: Date
    ) -> Double {
        switch phase {
        case .completed: 100
        case .rest: store.countdownToClockInProgress(snapshot: snapshot)
        case .running where snapshot.isBeforeStart(at: date), .clockIn:
            store.countdownToClockInProgress(snapshot: snapshot)
        default:
            snapshot.progress
        }
    }

    private func tabButton(_ tab: AppTab, icon: String, title: String) -> some View {
        Button {
            store.selectedTab = tab
        } label: {
            Label(title, systemImage: icon)
                .font(.body.weight(store.selectedTab == tab ? .semibold : .regular))
                .foregroundStyle(store.selectedTab == tab ? OWCDesign.accent : OWCDesign.primary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 12)
                .background(
                    store.selectedTab == tab ? OWCDesign.accent.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(store.selectedTab == tab ? .isSelected : [])
    }
}

private struct TabletTimerView: View {
    let store: OffWorkStore
    let isActive: Bool
    @State private var showShare = false
    @State private var showOvertime = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isActive,
               store.visualPhase(at: store.timerDate(from: .now)).usesLiveTimeline {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    tabletTimerContent(at: store.timerDate(from: timeline.date))
                }
            } else {
                tabletTimerContent(at: store.timerDate(from: .now))
            }
        }
        .background(OWCDesign.page)
        .sheet(isPresented: $showShare) {
            ShareComposerView(store: store)
                .presentationSizing(.page)
                .presentationCornerRadius(26)
        }
        .sheet(isPresented: $showOvertime) {
            OvertimeSheet(store: store)
                // Deliberately plain `.form`, not `.fitted`: fitted sizing
                // measures the content without accounting for the sheet's
                // NavigationStack title bar, which lays the description out
                // underneath the title instead of below it. The sheet keeps
                // its fixed standard size and the content scrolls inside it.
                .presentationSizing(.form)
        }
    }

    @ViewBuilder
    private func tabletTimerContent(at date: Date) -> some View {
        let snapshot = store.shouldQuerySnapshot(at: date) ? store.snapshot(at: date) : nil
        let phase = store.visualPhase(snapshot: snapshot, at: date)

        ZStack {
            if phase.showsActiveTimer, let snapshot {
                TabletRunningView(
                    store: store,
                    snapshot: snapshot,
                    now: date,
                    showShare: $showShare,
                    showOvertime: $showOvertime
                )
            } else {
                TimerDesignView(
                    store: store,
                    wide: true,
                    timelineDate: date,
                    animatesPhaseChanges: false
                )
            }
        }
        .id(phase.surfaceIdentity)
        .transition(timerTransition)
        .animation(timerAnimation, value: phase)
    }

    private var timerTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
    }

    private var timerAnimation: Animation {
        reduceMotion ? OWCMotion.reduced : OWCMotion.phase
    }
}

private struct TabletRunningView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var compactCountdownSize: CGFloat = 88
    let store: OffWorkStore
    let snapshot: NativeShiftSnapshot
    let now: Date
    @Binding var showShare: Bool
    @Binding var showOvertime: Bool
    /// The countdown, the meter and the stats — everything whose height the
    /// timeline cannot change.
    @State private var headHeight: CGFloat = 0
    /// The action row under the list, which must never be pushed off either.
    @State private var actionsHeight: CGFloat = 0
    @State private var columnHeight: CGFloat = 0

    /// What is left for the list once the parts that outrank it have taken
    /// theirs.
    ///
    /// Measured either side of the list rather than at the list's own origin.
    /// The phone can take that shortcut because its timeline sits last in a
    /// top-aligned scroll view, where the offset of the list does not move when
    /// the list grows. This column is centred, so it does: more rows made it
    /// taller, centring shifted it up, the measurement read more room, and it
    /// took more rows — until the countdown itself was pushed off the top of
    /// the screen. Measuring the head and the actions breaks that loop, because
    /// neither depends on how many rows the list draws.
    private var timelineHeight: CGFloat {
        let chrome = headHeight + actionsHeight + 22 + 24 + TimerContentSpace.bottomSlack
        return max(0, columnHeight - chrome)
    }


    var body: some View {
        VStack(spacing: 0) {
            tabletHeader(store: store, now: now)

            if store.isForcedWorkday(snapshot) {
                ManualTimingBanner(store: store)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
            } else if !snapshot.isBeforeStart(at: now), let note = store.earlyClockInNote(at: now) {
                EarlyClockInBanner(store: store, note: note)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
            }

            // Scrollable, but only when it has to be. Expanding the list makes
            // the column taller than the pane; without this the countdown and
            // action row can end up outside the visible region.
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                // Everything from here to the stats is the head: the parts that
                // outrank the list and must keep their room. Grouped so it can
                // be measured as one, which is what the list's budget is
                // subtracted from.
                VStack(spacing: 0) {
                // Lunch and overtime were missing here entirely: the iPad drew
                // the plain running layout in every phase, so a break showed a
                // frozen number under "time left" with no explanation.
                if let pill = statusPill {
                    TimerPhasePill(
                        title: pill.text,
                        systemImage: pill.symbol,
                        tint: pill.tint,
                        fill: pill.tint.opacity(0.12),
                        font: .subheadline.weight(.semibold)
                    )
                    .padding(.bottom, 18)
                }

                Text(store.formatDuration(displayRemaining))
                    .font(.system(size: compactCountdownSize, weight: .bold).monospacedDigit())
                    .tracking(-3)
                    .foregroundStyle(onBreak ? OWCDesign.secondary : OWCDesign.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .owcCountdownTextTransition(milliseconds: displayRemaining)
                Text(heroCaption)
                    .font(.body)
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 14)

                if snapshot.isBeforeStart(at: now) {
                    OWCProgressMeter(
                        progress: store.countdownToClockInProgress(snapshot: snapshot),
                        label: store.t("progress")
                    )
                    .padding(.top, 17)
                } else {
                    OWCProgressMeter(progress: snapshot.progress, label: store.t("progress"), overtime: isOvertime, paused: onBreak)
                        .padding(.top, 17)
                }

                if store.presentationSalaryEnabled {
                    earningsCard
                        .padding(.top, 44)
                }

                if store.followsSchedule(at: now) {
                    HStack(spacing: 14) {
                        statCard(store.t("summaryThisWeek"), summaryLabel(weekSummary, includeMoney: false))
                        statCard(store.t("summaryThisYear"), summaryLabel(yearSummary, includeMoney: store.presentationSalaryEnabled))
                    }
                    .padding(.top, store.presentationSalaryEnabled ? 14 : 44)
                }

                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headHeight = $0 }

                UpcomingTimelineView(
                    store: store,
                    snapshot: snapshot,
                    now: now,
                    isExpanded: store.timelineExpandedBinding,
                    availableHeight: timelineHeight
                )
                .padding(.top, 22)
                // The expandable timeline may be shorter than the pane.
                // Let this spacer consume that difference so the actions
                // remain anchored by the lower edge rather than floating
                // directly below a short list. In the overflowing case it
                // stays at its minimum and the whole column scrolls.
                Spacer(minLength: 24)

                TabletTimerActionBar(
                    store: store,
                    snapshot: snapshot,
                    now: now,
                    showShare: $showShare,
                    showOvertime: $showOvertime
                )
                .padding(.top, 24)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { actionsHeight = $0 }
            }
                    .frame(maxWidth: 560)
                    // Centres the capped column. `GeometryReader` aligns its
                    // child `.topLeading`, so a cap on its own leaves the whole
                    // countdown pinned to the left with the leftover width
                    // sitting empty beside it — the same trap the onboarding
                    // pages fell into. The cap decides how wide, never where.
                    .frame(maxWidth: .infinity)
                    // `minHeight` alone, no `maxHeight: .infinity`. Inside a
                    // scroll view the proposal is unbounded, so a greedy maximum
                    // fights the minimum and the content's real height stops
                    // being reported — the list scrolled but its last rows and
                    // the buttons stayed clipped at the edge. The minimum still
                    // centres the column when it fits, which is all the maximum
                    // was doing here.
                    // Expanding the list can make the column taller than the
                    // minimum, and centred, it overflowed
                    // the frame in both directions while the scrollable extent
                    // covered only the frame — the countdown clipped at the top,
                    // the action row at the bottom, neither reachable.
                    // Top-aligned, overflow only ever goes down, which is what
                    // scrolling is for.
                    .frame(
                        minHeight: proxy.size.height,
                        alignment: .top
                    )
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                // The viewport, not the content: the budget is what the pane
                // can show, and the content's own height is the thing being
                // budgeted.
                .onAppear { columnHeight = proxy.size.height }
                .onChange(of: proxy.size.height) { _, height in columnHeight = height }
            }
        }
    }

    private var onBreak: Bool { snapshot.isOnBreak }

    private var isOvertime: Bool { snapshot.isOvertimeActive(at: now) }

    private var displayRemaining: Double {
        snapshot.isBeforeStart(at: now)
            ? store.countdownToClockInMs(snapshot: snapshot, at: now)
            : snapshot.heroRemainingMs(at: now)
    }

    private var heroCaption: String {
        if snapshot.isBeforeStart(at: now) { return store.t("nextShiftLabelShort") }
        if onBreak, let breakEnd = snapshot.activeBreakEndDate {
            return store.t("pausedUntil", values: ["time": store.formatTime(breakEnd)])
        }
        if isOvertime { return store.t("overtimeTimeLeftCaption") }
        return store.t("timeLeftCaption")
    }

    private var statusPill: (text: String, symbol: String, tint: Color)? {
        if onBreak {
            return (store.t("lunchInProgress"), "cup.and.saucer", OWCDesign.secondary)
        }
        if isOvertime, let overtimeEnd = snapshot.overtimeEndDate {
            return (
                store.t("overtimeUntil", values: ["time": store.formatTime(overtimeEnd)]),
                "clock.fill",
                OWCDesign.accent
            )
        }
        return nil
    }

    private func statCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote).foregroundStyle(OWCDesign.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(OWCDesign.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var earningsCard: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.t("moneyEarned"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                Text(store.moneyText(snapshot.earnedSoFar))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            OWCEarningsVisibilityButton(store: store)
        }
        .padding(18)
        .background(OWCDesign.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var weekSummary: NativePeriodSummary? { store.periodSummary("week", asOf: now, snapshot: snapshot) }
    private var yearSummary: NativePeriodSummary? { store.periodSummary("year", asOf: now, snapshot: snapshot) }

    private func summaryLabel(_ summary: NativePeriodSummary?, includeMoney: Bool) -> String {
        guard let summary else { return "—" }
        if includeMoney {
            let money = store.moneyText(summary.earnings)
            return "\(store.formatDays(summary.days)) · \(money)"
        }
        return "\(store.formatDays(summary.days)) · \(store.formatHours(summary.hours))"
    }

}

/// The share affordance has a fixed circular footprint, leaving the two
/// labelled actions enough horizontal room even with long localisations.
private struct TabletTimerActionBar: View {
    let store: OffWorkStore
    let snapshot: NativeShiftSnapshot
    let now: Date
    @Binding var showShare: Bool
    @Binding var showOvertime: Bool

    private var beforeStart: Bool { snapshot.isBeforeStart(at: now) }
    private var overtimeActive: Bool { snapshot.isOvertimeActive(at: now) }

    var body: some View {
        HStack(spacing: 12) {
            if beforeStart {
                Button {
                    store.requestClockInEarly(at: now)
                } label: {
                    ClockInEarlyLabel(store: store)
                }
                .buttonStyle(OWCSecondaryButtonStyle())
                .layoutPriority(1)
            } else {
                Button {
                    store.requestClockOffEarly(at: now)
                } label: {
                    ClockOffEarlyLabel(store: store)
                }
                .buttonStyle(OWCSecondaryButtonStyle())
                .layoutPriority(1)

                Button {
                    showOvertime = true
                } label: {
                    Text(store.t(overtimeActive ? "adjustOvertime" : "overtime"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .buttonStyle(OWCSecondaryButtonStyle())
                .layoutPriority(1)
            }

            Button {
                showShare = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.body)
                    .frame(width: 50, height: 50)
                    .foregroundStyle(OWCDesign.primary)
                    .background(OWCDesign.control, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.t("shareButton"))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TabletSettingsView: View {
    let store: OffWorkStore

    var body: some View {
        // Scrolls for the same reason portrait does: once the stacked
        // single-column fallback kicks in on an iPad mini, five sections are
        // taller than the pane.
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // The shell's navigation bar is hidden for every root now, so
                // the title and its two controls live in the page.
                OWCRootPageHeader(title: store.t("settings")) {
                    EmptyView()
                } trailing: {
                    SettingsPlusStarButton(store: store)
                }

                // Two columns only when they actually fit. With the sidebar open an
                // 11-inch iPad leaves ~544 pt here, and splitting that in two left
                // every value truncated and "off-work reminder" wrapping onto two
                // lines. Below the threshold the same sections stack instead.
                AdaptiveSettingsColumns(spacing: 26) {
                    ForEach(SettingsSection.twoColumns, id: \.self) { column in
                        VStack(spacing: 20) {
                            ForEach(column) { section in
                                SettingsSectionCard(store: store, section: section)
                                // The privacy note belongs to this section, so
                                // it travels with it rather than with a column.
                                if section == .reminders {
                                    sectionNote(store.t("notificationPrivacyNote"))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 14)
                .padding(.horizontal, OWCDesign.pageInset)
            }
        }
        .background(OWCDesign.page)
        .toolbar(.hidden, for: .navigationBar)
    }
    private func sectionNote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(OWCDesign.secondary)
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, -12)
    }
}


@MainActor
private func tabletHeader(
    store: OffWorkStore,
    now: Date
) -> some View {
    HStack {
        HStack {
            Button {
                store.openPaidOrRun(.focus, action: .openFocus)
            } label: {
                OWCGlassCircleLabel {
                    Image(systemName: "timer")
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.t("focusTitle"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(store.locale)).uppercased())
            .font(.footnote.weight(.semibold))
            .tracking(0.78)
            .foregroundStyle(OWCDesign.secondary)

        HStack {
            Spacer(minLength: 0)
            Button { store.toggleQuickTheme() } label: {
                OWCGlassCircleLabel {
                    Group {
                        if store.quickThemeIsAuto {
                            Text(verbatim: "A").font(.body.weight(.semibold))
                        } else {
                            Image(systemName: store.quickThemeIcon)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.t("theme"))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .frame(minHeight: OWCDesign.rootHeaderHeight)
    .padding(.horizontal, OWCDesign.rootControlInset)
    .padding(.top, OWCDesign.rootHeaderTopInset)
}

/// Lays two settings columns side by side when the pane is wide enough, and
/// stacks them when it is not. The breakpoint follows the detail pane's actual
/// width, including changes made by the system sidebar.
private struct AdaptiveSettingsColumns<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    // The iPad mini portrait content area is about 664 pt with the sidebar
    // hidden. Keep it in one column in both sidebar states so collapsing the
    // sidebar does not unexpectedly reorder the same settings.
    private static var twoColumnMinimum: CGFloat { 720 }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: spacing) { content }
                .frame(minWidth: Self.twoColumnMinimum)
            VStack(spacing: spacing) { content }
        }
    }
}

/// Falls back to the phone layout when the detail pane is too narrow for the
/// tablet one.
///
/// An iPad mini with the sidebar open leaves about 454 pt here — narrower than
/// an iPhone — and the tablet layout, which assumes a wide canvas, truncated
/// every value. The phone layout is built for exactly this width, so it is the
/// right answer rather than a compromise.
///
/// The reader sits inside the NavigationStack and wraps only the root content:
/// pushed screens are presented by the stack itself, so a keyboard-driven
/// resize here cannot churn their identity the way it did on iPhone.
private struct NarrowPaneFallback<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content

    private static var tabletMinimum: CGFloat { 620 }

    var body: some View {
        GeometryReader { proxy in
            content(proxy.size.width < Self.tabletMinimum)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
