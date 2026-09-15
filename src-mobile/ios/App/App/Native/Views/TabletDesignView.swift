import SwiftUI

/// One stable system tab and navigation tree for every scene size. The native
/// sidebar-adaptable style supplies a tab bar in compact space and a sidebar
/// when wider space allows it.
struct AdaptiveAppShellView: View {
    @Environment(SceneState.self) private var scene
    let runtime: AppRuntime

    var body: some View {
        TabView(selection: Bindable(scene).selectedTab) {
                Tab(runtime.text.t("timerTab"), systemImage: "timer", value: AppTab.timer) {
                    timerStack
                }
                Tab(runtime.text.t("focusTitle"), systemImage: "stopwatch", value: AppTab.focus) {
                    NavigationStack(path: Bindable(scene).focusPath) {
                        FocusCanvasView(
                            focus: runtime.focus,
                            text: runtime.text,
                            queries: runtime.queries,
                            preferences: runtime.preferences,
                            onboardingComplete: runtime.preferences.onboardingComplete,
                            hasSeenPlusIntro: runtime.plus.hasSeenIntro,
                            browsing: scene.focus
                        )
                            .navigationDestination(for: AppRoute.self) { route in
                                AppRouteDestination(route: route, runtime: runtime)
                            }
                    }
                }
                Tab(runtime.text.t("recordsTab"), systemImage: "calendar", value: AppTab.records) {
                    recordsStack
                }
                Tab(runtime.text.t("settings"), systemImage: "slider.horizontal.3", value: AppTab.settings) {
                    settingsStack
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .tabViewSidebarFooter {
                TabletSidebarFooter(shifts: runtime.shifts, text: runtime.text)
            }
            .onChange(of: scene.presentedRoute) { _, route in
                guard let route else { return }
                if route == .focus || route == .focusPlan {
                    scene.openFocusTab()
                    return
                }
                if scene.selectedTab == .timer {
                    scene.timerPath.append(route)
                } else if scene.selectedTab == .focus {
                    scene.focusPath.append(route)
                } else {
                    if scene.selectedTab == .records { scene.selectedTab = .settings }
                    scene.settingsPath.append(route)
                }
                scene.presentedRoute = nil
            }
            .onChange(of: runtime.session.debugPresentationToken) {
                scene.timerPath.removeAll()
                scene.focusPath.removeAll()
                scene.recordsPath.removeAll()
                scene.settingsPath.removeAll()
            }
            .background(OWCDesign.page)
    }

    private var timerStack: some View {
        NavigationStack(path: Bindable(scene).timerPath) {
            TabletTimerRoot(shifts: runtime.shifts, preferences: runtime.preferences, text: runtime.text)
                .navigationDestination(for: AppRoute.self) { route in
                    AppRouteDestination(route: route, runtime: runtime)
                }
        }
    }

    private var recordsStack: some View {
        NavigationStack(path: Bindable(scene).recordsPath) {
            tabletRecordsRoot
        }
    }

    private var settingsStack: some View {
        NavigationStack(path: Bindable(scene).settingsPath) {
            tabletSettingsRoot
                .navigationDestination(for: AppRoute.self) { route in
                    AppRouteDestination(route: route, runtime: runtime)
                }
        }
    }

    private var tabletRecordsRoot: some View {
        RecordsDesignView(
            records: runtime.records,
            queries: runtime.queries,
            actions: runtime.recordActions,
            life: runtime.life,
            preferences: runtime.preferences,
            focus: runtime.focus,
            text: runtime.text,
            hours: runtime.session.hoursConfiguration(),
            browsing: scene.records,
            showsSidebarButton: false
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var tabletSettingsRoot: some View {
        TabletSettingsView(
            shifts: runtime.shifts,
            recovery: runtime.recovery,
            plus: runtime.plus,
            text: runtime.text
        )
    }

}

private struct TabletTimerRoot: View {
    @Environment(SceneState.self) private var scene
    let shifts: ShiftSessionStore
    let preferences: PreferencesStore
    let text: AppText
    @Environment(\.tabBarPlacement) private var tabBarPlacement
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NarrowPaneFallback { isNarrow in
            // Only expansion of the detail pane replaces the compact timer
            // with the wide layout. Crossfade that replacement; preserve the
            // existing sidebar-opening transition in the opposite direction.
            ZStack {
                if isNarrow {
                    // Push into this stack rather than take the default, which
                    // switches to the settings tab. The sidebar selection should
                    // not move because a row on the timer page was tapped.
                    TimerDesignView(
                        shifts: shifts,
                        wide: false,
                        onOpenSettings: openTimerSettings,
                        timelineActive: scene.selectedTab == .timer,
                        usesExternalRootToolbar: true
                    )
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
                } else {
                    TabletTimerView(
                        shifts: shifts,
                        text: text,
                        isActive: scene.selectedTab == .timer
                    )
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
                }
            }
            .animation(shellAnimation, value: isNarrow)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if tabBarPlacement == .sidebar {
                ToolbarItem(placement: .principal) {
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        Text(
                            shifts.session.timerDate(from: timeline.date)
                                .formatted(.dateTime.weekday(.wide).day().month(.wide).locale(preferences.locale))
                                .uppercased()
                        )
                        .font(.footnote.weight(.semibold))
                        .tracking(0.78)
                        .foregroundStyle(OWCDesign.secondary)
                    }
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                OWCEarningsVisibilityButton(preferences: preferences, text: text)
                Button {
                    withAnimation(reduceMotion ? OWCMotion.reduced : OWCMotion.navigation) {
                        _ = preferences.toggleQuickTheme()
                    }
                } label: {
                    Image(systemName: preferences.quickThemeIcon)
                }
                .accessibilityLabel(text.t("theme"))
            }
        }
    }

    private var shellAnimation: Animation {
        reduceMotion ? OWCMotion.reduced : OWCMotion.navigation
    }

    private func openTimerSettings(_ route: AppRoute?) {
        if let route {
            scene.timerPath.append(route)
        } else {
            scene.settingsPath.removeAll()
            scene.selectedTab = .settings
        }
    }
}

private struct TabletSidebarFooter: View {
    let shifts: ShiftSessionStore
    let text: AppText

    var body: some View {
        compactShiftCountdown
            .padding(.bottom, 16)
    }

    private var compactShiftCountdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let _ = LaunchTrace.signposter.emitEvent("sidebarTimerUpdate")
            let date = shifts.session.timerDate(from: timeline.date)
            if shifts.session.shouldQuerySnapshot(at: date), let snapshot = shifts.session.snapshot(at: date) {
                let phase = shifts.session.visualPhase(snapshot: snapshot, at: date)
                let remaining = miniRemaining(snapshot, phase: phase, at: date)

                VStack(alignment: .leading, spacing: 0) {
                    OWCSectionHeader(title: text.t("shiftSection"))

                    VStack(alignment: .leading, spacing: 0) {
                        Text(text.formatDuration(remaining))
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
        case .rest: text.t("widgetRestDay")
        case .completed: text.t("offWorkToday")
        case .unscheduled: text.t("unscheduledTitle")
        case .lunch: text.t("lunchInProgress")
        case .overtime: text.t("overtimeTimeLeftCaption")
        case .clockIn: text.t("nextShiftLabelShort")
        case .running, .rulesError:
            snapshot.isBeforeStart(at: date) ? text.t("nextShiftLabelShort") : text.t("timeLeftCaption")
        }
    }

    private func miniRemaining(
        _ snapshot: NativeShiftSnapshot,
        phase: TimerVisualPhase,
        at date: Date
    ) -> Double {
        switch phase {
        case .completed: 0
        case .rest: shifts.session.countdownToClockInMs(snapshot: snapshot, at: date)
        case .running where snapshot.isBeforeStart(at: date), .clockIn:
            shifts.session.countdownToClockInMs(snapshot: snapshot, at: date)
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
        case .rest: shifts.session.countdownToClockInProgress(snapshot: snapshot)
        case .running where snapshot.isBeforeStart(at: date), .clockIn:
            shifts.session.countdownToClockInProgress(snapshot: snapshot)
        default:
            snapshot.progress
        }
    }
}

private struct TabletTimerView: View {
    @Environment(SceneState.self) private var scene
    let shifts: ShiftSessionStore
    let text: AppText
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isActive,
               shifts.session.visualPhase(at: shifts.session.timerDate(from: .now)).usesLiveTimeline {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    tabletTimerContent(at: shifts.session.timerDate(from: timeline.date))
                }
            } else {
                tabletTimerContent(at: shifts.session.timerDate(from: .now))
            }
        }
        .background(OWCDesign.page)
    }

    @ViewBuilder
    private func tabletTimerContent(at date: Date) -> some View {
        let _ = LaunchTrace.signposter.emitEvent("tabletTimerContentUpdate")
        let snapshot = shifts.session.shouldQuerySnapshot(at: date) ? shifts.session.snapshot(at: date) : nil
        let phase = shifts.session.visualPhase(snapshot: snapshot, at: date)

        ZStack {
            if phase.showsActiveTimer, let snapshot {
                TabletRunningView(
                    shifts: shifts,
                    text: text,
                    snapshot: snapshot,
                    now: date,
                    showShare: scene.timerSheetBinding(.share),
                    showOvertime: scene.timerSheetBinding(.overtime)
                )
            } else {
                TimerDesignView(
                    shifts: shifts,
                    wide: true,
                    timelineDate: date,
                    animatesPhaseChanges: false,
                    usesExternalRootToolbar: true
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
    @Environment(SceneState.self) private var scene
    @ScaledMetric(relativeTo: .largeTitle) private var compactCountdownSize: CGFloat = 88
    let shifts: ShiftSessionStore
    let text: AppText
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
            if shifts.session.isForcedWorkday(snapshot) {
                ManualTimingBanner(shifts: shifts, now: now)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
            } else if !snapshot.isBeforeStart(at: now), let note = shifts.session.earlyClockInNote(at: now) {
                EarlyClockInBanner(shifts: shifts, note: note)
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

                Text(text.formatDuration(displayRemaining))
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
                        progress: shifts.session.countdownToClockInProgress(snapshot: snapshot),
                        label: text.t("progress")
                    )
                    .padding(.top, 17)
                } else {
                    OWCProgressMeter(progress: snapshot.progress, label: text.t("progress"), overtime: isOvertime, paused: onBreak)
                        .padding(.top, 17)
                }

                if shifts.session.presentationSalaryEnabled {
                    earningsCard
                        .padding(.top, 44)
                }

                if shifts.session.followsSchedule(at: now) {
                    HStack(spacing: 14) {
                        statCard(text.t("summaryThisWeek"), summaryLabel(weekSummary, includeMoney: false))
                        statCard(text.t("summaryThisYear"), summaryLabel(yearSummary, includeMoney: shifts.session.presentationSalaryEnabled))
                    }
                    .padding(.top, shifts.session.presentationSalaryEnabled ? 14 : 44)
                }

                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headHeight = $0 }

                UpcomingTimelineView(
                    shifts: shifts,
                    snapshot: snapshot,
                    now: now,
                    isExpanded: scene.timelineExpandedBinding(for: snapshot, at: now, session: shifts.session),
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
                    shifts: shifts,
                    text: text,
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
            ? shifts.session.countdownToClockInMs(snapshot: snapshot, at: now)
            : snapshot.heroRemainingMs(at: now)
    }

    private var heroCaption: String {
        if snapshot.isBeforeStart(at: now) { return text.t("nextShiftLabelShort") }
        if onBreak, let breakEnd = snapshot.activeBreakEndDate {
            return text.t("pausedUntil", values: ["time": text.formatTime(breakEnd)])
        }
        if isOvertime { return text.t("overtimeTimeLeftCaption") }
        return text.t("timeLeftCaption")
    }

    private var statusPill: (text: String, symbol: String, tint: Color)? {
        if onBreak {
            return (text.t("lunchInProgress"), "cup.and.saucer", OWCDesign.secondary)
        }
        if isOvertime, let overtimeEnd = snapshot.overtimeEndDate {
            return (
                text.t("overtimeUntil", values: ["time": text.formatTime(overtimeEnd)]),
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
                Text(text.t("moneyEarned"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                Text(text.moneyText(snapshot.earnedSoFar))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
        }
        .padding(18)
        .background(OWCDesign.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var weekSummary: NativePeriodSummary? { shifts.session.periodSummary("week", asOf: now, snapshot: snapshot) }
    private var yearSummary: NativePeriodSummary? { shifts.session.periodSummary("year", asOf: now, snapshot: snapshot) }

    private func summaryLabel(_ summary: NativePeriodSummary?, includeMoney: Bool) -> String {
        guard let summary else { return "—" }
        if includeMoney {
            let money = text.moneyText(summary.earnings)
            return "\(text.formatDays(summary.days)) · \(money)"
        }
        return "\(text.formatDays(summary.days)) · \(text.formatHours(summary.hours))"
    }

}

/// The share affordance has a fixed circular footprint, leaving the two
/// labelled actions enough horizontal room even with long localisations.
private struct TabletTimerActionBar: View {
    @Environment(SceneState.self) private var scene
    let shifts: ShiftSessionStore
    let text: AppText
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
                    scene.requestClockInEarly(at: now, using: shifts)
                } label: {
                    ClockInEarlyLabel(shifts: shifts, now: now)
                }
                .buttonStyle(OWCSecondaryButtonStyle())
                .layoutPriority(1)
            } else {
                Button {
                    scene.requestClockOffEarly(at: now, using: shifts)
                } label: {
                    ClockOffEarlyLabel(shifts: shifts, now: now)
                }
                .buttonStyle(OWCSecondaryButtonStyle())
                .layoutPriority(1)

                Button {
                    showOvertime = true
                } label: {
                    Text(text.t(overtimeActive ? "adjustOvertime" : "overtime"))
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
            .accessibilityLabel(text.t("shareButton"))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TabletSettingsView: View {
    let shifts: ShiftSessionStore
    let recovery: RecoveryStore
    let plus: PlusEntitlement
    let text: AppText

    var body: some View {
        // Let the system navigation container track the root scroll view so
        // large titles and the tab bar share the correct scroll/safe-area layout.
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Two columns only when they actually fit. With the sidebar open an
                // 11-inch iPad leaves ~544 pt here, and splitting that in two left
                // every value truncated and "off-work reminder" wrapping onto two
                // lines. Below the threshold the same sections stack instead.
                AdaptiveSettingsColumns(spacing: 26) {
                    ForEach(SettingsSection.twoColumns, id: \.self) { column in
                        VStack(spacing: 20) {
                            ForEach(column) { section in
                                SettingsSectionCard(shifts: shifts, recovery: recovery, section: section)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 14)
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.bottom, OWCDesign.detailBottomInset)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(OWCDesign.page)
        .navigationTitle(text.t("settings"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SettingsPlusStarToolbarButton(plus: plus, text: text)
            }
        }
    }
}


/// Lays two settings columns side by side when the pane is wide enough, and
/// stacks them when it is not. The breakpoint follows the detail pane's actual
/// width, including changes made by the system sidebar.
private struct AdaptiveSettingsColumns<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content
    @State private var availableWidth: CGFloat = 0

    // The iPad mini portrait content area is about 664 pt with the sidebar
    // hidden. Keep it in one column in both sidebar states so collapsing the
    // sidebar does not unexpectedly reorder the same settings.
    private static var twoColumnMinimum: CGFloat { 720 }

    var body: some View {
        let layout = availableWidth >= Self.twoColumnMinimum
            ? AnyLayout(HStackLayout(alignment: .top, spacing: spacing))
            : AnyLayout(VStackLayout(spacing: spacing))
        layout {
            content
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
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
