import SwiftUI

/// iPad directions 1p/1r/1t/1u. The wide canvas has its own navigation and
/// density instead of stretching the phone's grouped list.
struct TabletShellView: View {
    @Bindable var store: OffWorkStore
    @State private var sidebarVisible = true
    @State private var path = NavigationPath()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                TabletSidebar(store: store) {
                    withAnimation(shellAnimation) { sidebarVisible = false }
                }
                .frame(width: 290)
                .transition(sidebarTransition)
            }

            NavigationStack(path: $path) {
                ZStack {
                    OWCDesign.page.ignoresSafeArea()

                    tabletTimerRoot
                        .opacity(store.selectedTab == .timer ? 1 : 0)
                        .scaleEffect(store.selectedTab == .timer || reduceMotion ? 1 : 0.99)
                        .allowsHitTesting(store.selectedTab == .timer)
                        .accessibilityHidden(store.selectedTab != .timer)
                        .zIndex(store.selectedTab == .timer ? 1 : 0)

                    tabletRecordsRoot
                        .opacity(store.selectedTab == .records ? 1 : 0)
                        .scaleEffect(store.selectedTab == .records || reduceMotion ? 1 : 0.99)
                        .allowsHitTesting(store.selectedTab == .records)
                        .accessibilityHidden(store.selectedTab != .records)
                        .zIndex(store.selectedTab == .records ? 1 : 0)

                    tabletSettingsRoot
                        .opacity(store.selectedTab == .settings ? 1 : 0)
                        .scaleEffect(store.selectedTab == .settings || reduceMotion ? 1 : 0.99)
                        .allowsHitTesting(store.selectedTab == .settings)
                        .accessibilityHidden(store.selectedTab != .settings)
                        .zIndex(store.selectedTab == .settings ? 1 : 0)
                }
                .animation(shellAnimation, value: store.selectedTab)
                .navigationDestination(for: AppRoute.self) { route in
                    AppRouteDestination(route: route, store: store)
                }
            }
        }
        .onChange(of: store.presentedRoute) { _, route in
            guard let route else { return }
            path.append(route)
            store.presentedRoute = nil
        }
        .onChange(of: store.debugPresentationToken) {
            path = NavigationPath()
        }
        .onChange(of: store.selectedTab) { _, selectedTab in
            // Each iPad root owns a NavigationStack. A pushed destination can
            // otherwise remain hosted above the ZStack after the sidebar has
            // selected another root, leaving (for example) “All records” on
            // screen while Settings is highlighted.
            path = NavigationPath()
            if selectedTab != .records { store.recordsPath.removeAll() }
            if selectedTab != .settings { store.settingsPath.removeAll() }
        }
        .onAppear {
            if store.selectedTab != .records { store.recordsPath.removeAll() }
            if store.selectedTab != .settings { store.settingsPath.removeAll() }
            if store.selectedTab == .settings, !store.settingsPath.isEmpty {
                for route in store.settingsPath { path.append(route) }
                store.settingsPath.removeAll()
            }
        }
        .background(OWCDesign.page)
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
                    onOpenSettings: { route in store.presentedRoute = route },
                    timelineActive: store.selectedTab == .timer
                )
                // This pane runs the phone layout, which no longer caps its own
                // width. The pane can be up to 620pt (`tabletMinimum`), so cap
                // it at the widest iPhone rather than let a phone design stretch.
                .frame(maxWidth: 440)
            } else {
                TabletTimerView(
                    store: store,
                    sidebarVisible: sidebarVisible,
                    isActive: store.selectedTab == .timer
                ) {
                    withAnimation(shellAnimation) { sidebarVisible = true }
                }
            }
        }
    }

    private var tabletRecordsRoot: some View {
        RecordsDesignView(store: store)
            .frame(maxWidth: 620)
    }

    private var tabletSettingsRoot: some View {
        // Keep one settings hierarchy mounted at every iPad width. Swapping to
        // SettingsDesignView when the sidebar reduced the detail width changed
        // both the row order and NavigationLink style on iPad mini.
        TabletSettingsView(store: store, sidebarVisible: sidebarVisible) {
            withAnimation(shellAnimation) { sidebarVisible = true }
        }
    }

    private var shellAnimation: Animation {
        reduceMotion ? OWCMotion.reduced : OWCMotion.navigation
    }

    private var sidebarTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity)
    }

}

private struct TabletSidebar: View {
    let store: OffWorkStore
    let hide: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                OWCBrandMark()
                    .frame(width: 30, height: 30)
                Text(verbatim: OWCBrand.shortName)
                    .font(.body.bold())
                    .tracking(-0.34)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 4)
                Button(action: hide) {
                    Image(systemName: "sidebar.left")
                        .font(.body)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
            }
            .padding(.leading, 10)
            // The collapse control belongs near the sidebar's own edge. With the
            // container's 14 pt inset on top of another 10 it sat 24 pt in,
            // reading as floating in the middle rather than attached to the
            // divider it acts on.
            .padding(.trailing, -4)
            .padding(.bottom, 22)

            VStack(spacing: 4) {
                tabButton(.timer, icon: "timer", title: store.t("timerTab"))
                tabButton(.records, icon: "calendar", title: store.t("recordsTab"))
                tabButton(.settings, icon: "slider.horizontal.3", title: store.t("settings"))
            }

            // Ticks with the clock. Reading the snapshot once at render time
            // froze the sidebar's countdown and bar while the main column kept
            // moving, which read as the app having stalled.
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let date = store.timerDate(from: timeline.date)
                if store.shouldQuerySnapshot(at: date), let snapshot = store.snapshot(at: date) {
                    OWCSectionHeader(title: store.selectedTab == .timer ? store.t("todaysShift") : store.t("widgetWorking"))
                        .padding(.top, 26)

                    if store.selectedTab == .timer {
                        OWCGroupCard {
                            sidebarRow(
                                store.t("shiftSection"),
                                "\(store.timeString(store.effectiveStartMinutes(at: date))) – \(store.timeString(store.effectiveEndMinutes(at: date)))"
                            )
                            sidebarRow(store.t("lunchBreak"), store.lunchLabel(at: date), last: !store.presentationSalaryEnabled)
                            if store.presentationSalaryEnabled {
                                // The sidebar is where the figure lives while
                                // the sidebar is open, so this is where the eye
                                // belongs. Without it the iPad could blank the
                                // salary from the phone and never restore it,
                                // and never blank it from here at all.
                                sidebarRow(
                                    store.t("moneyEarned"),
                                    store.hideEarnings ? "••••" : store.formatMoney(snapshot.dailySalary.map { $0 * snapshot.payRatio }),
                                    last: true,
                                    bold: true,
                                    accessory: { OWCEarningsVisibilityButton(store: store) }
                                )
                            }
                        }
                    } else {
                        let phase = store.visualPhase(snapshot: snapshot, at: date)
                        let remaining = sidebarMiniRemaining(snapshot, phase: phase, at: date)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(store.formatDuration(remaining))
                                .font(.title.bold().monospacedDigit())
                                .tracking(-0.8)
                                .owcCountdownTextTransition(milliseconds: remaining)
                            Text(sidebarMiniCaption(snapshot, phase: phase, at: date))
                                .font(.footnote)
                                .foregroundStyle(OWCDesign.secondary)
                                .padding(.top, 6)
                            GeometryReader { proxy in
                                let fill = sidebarMiniFill(snapshot, phase: phase, at: date)
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
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 28)
        .background(.regularMaterial)
        .overlay(alignment: .trailing) {
            Rectangle().fill(OWCDesign.separator).frame(width: 0.5)
        }
    }

    private func sidebarMiniCaption(_ snapshot: NativeShiftSnapshot, phase: TimerVisualPhase, at date: Date) -> String {
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

    private func sidebarMiniRemaining(
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

    private func sidebarMiniFill(
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
                .foregroundStyle(store.selectedTab == tab ? .white : OWCDesign.primary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 12)
                .glassEffect(
                    store.selectedTab == tab
                        ? .regular.tint(OWCDesign.accent).interactive()
                        : .regular.interactive(),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                // Glass only paints around the visible label. Define the
                // interaction shape explicitly so the blank part of the row
                // remains a full-size tab target as users expect on iPad.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sidebarRow<Accessory: View>(
        _ label: String,
        _ value: String,
        last: Bool = false,
        bold: Bool = false,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) -> some View {
        HStack {
            Text(label).font(.callout)
            Spacer(minLength: 8)
            Text(value)
                .font(.callout.weight(bold ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(bold ? OWCDesign.primary : OWCDesign.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            accessory()
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .overlay(alignment: .bottomTrailing) {
            if !last { Rectangle().fill(OWCDesign.separator).frame(height: 0.5).padding(.leading, 14) }
        }
    }
}

private struct TabletTimerView: View {
    let store: OffWorkStore
    let sidebarVisible: Bool
    let isActive: Bool
    let showSidebar: () -> Void
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
        .navigationBarHidden(true)
        .sheet(isPresented: $showShare) {
            ShareComposerView(store: store)
                .presentationSizing(.page)
                .presentationCornerRadius(26)
        }
        .sheet(isPresented: $showOvertime) {
            OvertimeSheet(store: store)
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
                    sidebarVisible: sidebarVisible,
                    showSidebar: showSidebar,
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
        .overlay(alignment: .topLeading) {
            // Completed, rest-day and rules-error states reuse the common
            // timer surface, which does not know about the custom iPad
            // sidebar. Keep the reveal control at the shell boundary so
            // none of those states can strand the user in full screen.
            if !sidebarVisible, phase.usesCommonTimerSurface {
                Button(action: showSidebar) {
                    Image(systemName: "sidebar.left")
                        .frame(width: 38, height: 38)
                        .background(OWCDesign.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
                .padding(.top, 22)
                .zIndex(10)
            }
        }
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
    @ScaledMetric(relativeTo: .largeTitle) private var wideCountdownSize: CGFloat = 150
    // Two display sizes, both scaled: the sidebar squeezes the number.
    @ScaledMetric(relativeTo: .largeTitle) private var compactCountdownSize: CGFloat = 88
    let store: OffWorkStore
    let snapshot: NativeShiftSnapshot
    let now: Date
    let sidebarVisible: Bool
    let showSidebar: () -> Void
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
        let chrome = headHeight + actionsHeight + 22 + TimerContentSpace.bottomSlack
        return max(0, columnHeight - chrome)
    }


    var body: some View {
        VStack(spacing: 0) {
            tabletHeader(store: store, now: now, sidebarVisible: sidebarVisible, showSidebar: showSidebar)

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
            // the column taller than the pane, and without this the collapse
            // button and the action row went off the bottom — expandable with no
            // way back. `minHeight` keeps the fitting case identical: the column
            // still fills the pane and still centres itself.
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
                    .font(.system(size: sidebarVisible ? compactCountdownSize : wideCountdownSize, weight: .bold).monospacedDigit())
                    .tracking(sidebarVisible ? -3 : -5)
                    .foregroundStyle(onBreak ? OWCDesign.secondary : OWCDesign.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .owcCountdownTextTransition(milliseconds: displayRemaining)
                Text(heroCaption)
                    .font(sidebarVisible ? .body : .title3)
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, sidebarVisible ? 14 : 18)

                if sidebarVisible {
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

                    if store.followsSchedule(at: now) {
                    HStack(spacing: 14) {
                        statCard(store.t("summaryThisWeek"), summaryLabel(weekSummary, includeMoney: false))
                        statCard(store.t("summaryThisYear"), summaryLabel(yearSummary, includeMoney: store.presentationSalaryEnabled))
                    }
                    .padding(.top, 44)
                    }
                } else {
                    if snapshot.isBeforeStart(at: now) {
                        OWCProgressMeter(
                            progress: store.countdownToClockInProgress(snapshot: snapshot),
                            label: store.t("progress")
                        )
                        .padding(.top, 56)
                    } else {
                        segmentedProgress
                            .padding(.top, 56)
                    }
                    HStack(spacing: 56) {
                        fullStat(
                            store.t("progress"),
                            store.formatPercent(
                                snapshot.isBeforeStart(at: now)
                                    ? store.countdownToClockInProgress(snapshot: snapshot)
                                    : snapshot.progress
                            )
                        )
                        if store.presentationSalaryEnabled {
                            fullStat(
                                store.t("moneyEarned"),
                                store.hideEarnings ? "••••" : store.formatMoney(snapshot.dailySalary.map { $0 * snapshot.payRatio }),
                                accessory: { OWCEarningsVisibilityButton(store: store) }
                            )
                        }
                        if store.followsSchedule(at: now) { fullStat(store.t("daysUntilRest"), daysUntilRest) }
                    }
                    .padding(.top, 56)
                }

                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headHeight = $0 }

                // Collapsing the sidebar is how this app goes full screen, and
                // a full-screen countdown is one thing on purpose. The list and
                // the controls belong to the sidebar-open layout; here they
                // would be exactly the furniture the user just cleared away.
                //
                // Nothing becomes unreachable. The header keeps the control that
                // brings the sidebar back, and the sidebar is where stopping,
                // overtime and sharing live — one tap from here, and a tap the
                // user already made to get into this mode.
                if sidebarVisible {
                    UpcomingTimelineView(
                        store: store,
                        snapshot: snapshot,
                        now: now,
                        isExpanded: store.timelineExpandedBinding,
                        availableHeight: timelineHeight
                    )
                    .padding(.top, 22)
                }

                Group {
                    if snapshot.isBeforeStart(at: now) {
                        HStack(spacing: 12) {
                            Button {
                                store.requestClockInEarly(at: now)
                            } label: {
                                ClockInEarlyLabel(store: store)
                            }
                            Button { showShare = true } label: {
                                Label(store.t("shareButton"), systemImage: "square.and.arrow.up")
                            }
                        }
                    } else {
                        HStack(spacing: 12) {
                            Button {
                                store.requestClockOffEarly(at: now)
                            } label: { ClockOffEarlyLabel(store: store) }
                            Button { showOvertime = true } label: {
                                Text(store.t(isOvertime ? "adjustOvertime" : "overtime"))
                            }
                            Button { showShare = true } label: {
                                Label(store.t("shareButton"), systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
                .buttonStyle(OWCSecondaryButtonStyle())
                .padding(.top, 24)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { actionsHeight = $0 }
            }
                    .frame(maxWidth: sidebarVisible ? 560 : 900)
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
                    // Top-aligned only where the column can outgrow the pane.
                    //
                    // With the sidebar open it can: expanding the list made the
                    // column taller than the minimum, and centred, it overflowed
                    // the frame in both directions while the scrollable extent
                    // covered only the frame — the countdown clipped at the top,
                    // the collapse button at the bottom, neither reachable.
                    // Top-aligned, overflow only ever goes down, which is what
                    // scrolling is for.
                    //
                    // Immersive has no timeline, so nothing here can grow: the
                    // countdown, meter, stats and action row are a fixed stack
                    // that reports its true height. Top-aligning it left the
                    // whole instrument hugging the header with a screen of empty
                    // page underneath — the one layout that is supposed to be
                    // nothing but the clock, and the clock was off-centre.
                    // Centred, and if an accessibility text size ever does push
                    // it past the pane the frame simply grows to the content and
                    // the alignment stops applying.
                    .frame(
                        minHeight: proxy.size.height,
                        alignment: sidebarVisible ? .top : .center
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

    private func fullStat<Accessory: View>(
        _ title: String,
        _ value: String,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.footnote).foregroundStyle(OWCDesign.secondary)
            HStack(spacing: 8) {
                Text(value).font(.title.bold().monospacedDigit())
                accessory()
            }
        }
    }

    private var weekSummary: NativePeriodSummary? { store.periodSummary("week", asOf: now, snapshot: snapshot) }
    private var yearSummary: NativePeriodSummary? { store.periodSummary("year", asOf: now, snapshot: snapshot) }

    private func summaryLabel(_ summary: NativePeriodSummary?, includeMoney: Bool) -> String {
        guard let summary else { return "—" }
        if includeMoney {
            let money = store.hideEarnings ? "••••" : store.formatMoney(summary.earnings)
            return "\(store.formatDays(summary.days)) · \(money)"
        }
        return "\(store.formatDays(summary.days)) · \(store.formatHours(summary.hours))"
    }

    private var segmentedProgress: some View {
        VStack(spacing: 12) {
            GeometryReader { proxy in
                Capsule().fill(OWCDesign.control)
                    .overlay(alignment: .leading) {
                        Capsule().fill(OWCDesign.accent)
                            .frame(width: proxy.size.width * min(1, max(0, snapshot.progress / 100)))
                    }
            }
            .frame(height: 12)
            GeometryReader { proxy in
                Text(store.timeString(store.effectiveStartMinutes(at: now))).position(x: 30, y: 9)
                if store.effectiveLunchEnabled(at: now), snapshot.segments.count > 1 {
                    Text("\(store.timeString(store.effectiveLunchStartMinutes(at: now))) · \(store.t("lunchBreak"))")
                        .position(x: max(68, min(proxy.size.width - 68, proxy.size.width * lunchWallRatio)), y: 9)
                }
                Text(store.timeString(store.effectiveEndMinutes(at: now))).position(x: proxy.size.width - 30, y: 9)
            }
            .frame(height: 18)
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(OWCDesign.secondary)
        }
    }

    private var lunchWallRatio: Double {
        guard let lunchStart = snapshot.segments.first?.endAtMs else { return 0.5 }
        return min(1, max(0, (lunchStart - snapshot.startAtMs) / max(1, snapshot.plannedEndAtMs - snapshot.startAtMs)))
    }

    private var daysUntilRest: String {
        guard let date = snapshot.nextRestDate else { return "—" }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: now),
            to: Calendar.current.startOfDay(for: date)
        ).day ?? 0
        return store.formatDays(Double(max(0, days)))
    }
}

private struct TabletSettingsView: View {
    let store: OffWorkStore
    let sidebarVisible: Bool
    let showSidebar: () -> Void

    var body: some View {
        // Scrolls for the same reason portrait does: once the stacked
        // single-column fallback kicks in on an iPad mini, five sections are
        // taller than the pane.
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    if !sidebarVisible {
                        Button(action: showSidebar) { Image(systemName: "sidebar.left").frame(width: 38, height: 38).background(OWCDesign.card).clipShape(RoundedRectangle(cornerRadius: 12)) }
                        .buttonStyle(.plain)
                    }
                    Text(store.t("settings"))
                        .font(.largeTitle.bold())
                        .tracking(-0.85)
                    Spacer()
                    SettingsPlusStarButton(store: store)
                }

                // Two columns only when they actually fit. With the sidebar open an
                // 11-inch iPad leaves ~544 pt here, and splitting that in two left
                // every value truncated and "off-work reminder" wrapping onto two
                // lines. Below the threshold the same sections stack instead.
                AdaptiveSettingsColumns(spacing: 26) {
                    ForEach(SettingsSection.twoColumns.indices, id: \.self) { column in
                        VStack(spacing: 20) {
                            ForEach(SettingsSection.twoColumns[column]) { section in
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
                .padding(.top, 22)
            }
            .padding(.leading, sidebarVisible ? 34 : 40)
            .padding(.trailing, 40)
            .padding(.top, 26)
        }
        .background(OWCDesign.page)
        .navigationBarHidden(true)
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
    private var workdaysDescription: String {
        if store.scheduleMode != .classic { return store.scheduleLabel }
        let values = Array(zip([1, 2, 3, 4, 5, 6, 0], store.weekdayLabels()))
            .filter { store.workdays.contains($0.0) }
            .map(\.1)
        guard let first = values.first else { return store.t("disabledShort") }
        return values.count > 1 ? "\(first) – \(values.last ?? first)" : first
    }
}


@MainActor
private func tabletHeader(
    store: OffWorkStore,
    now: Date,
    sidebarVisible: Bool,
    showSidebar: @escaping () -> Void
) -> some View {
    HStack {
        HStack(spacing: 8) {
            if !sidebarVisible {
                Button(action: showSidebar) {
                    Image(systemName: "sidebar.left")
                        .frame(width: 38, height: 38)
                        .background(OWCDesign.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button {
                store.openPaidOrRun(.focus, action: .openFocus)
            } label: {
                Image(systemName: "timer")
                    .frame(width: 38, height: 38)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                Group {
                    if store.quickThemeIsAuto {
                        Text(verbatim: "A").font(.body.weight(.semibold))
                    } else {
                        Image(systemName: store.quickThemeIcon)
                    }
                }
                .frame(width: 38, height: 38)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.t("theme"))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding(.horizontal, sidebarVisible ? 40 : 26)
    .padding(.top, 22)
}

/// Lays two settings columns side by side when the pane is wide enough, and
/// stacks them when it is not. The breakpoint is measured, not guessed from the
/// device: the same iPad is wide with the sidebar hidden and narrow with it
/// shown, and only the second case needs a single column.
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
