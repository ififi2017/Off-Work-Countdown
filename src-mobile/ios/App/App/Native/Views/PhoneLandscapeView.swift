import SwiftUI

struct PhoneLandscapeShellView: View {
    @Bindable var store: OffWorkStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack(path: $store.activePath) {
            ZStack(alignment: .leading) {
                OWCDesign.page.ignoresSafeArea()

                ZStack {
                    // Keep both roots mounted, as the iPad shell does. Removing
                    // a tree containing interactive glass while its replacement
                    // was entering left one of the timer controls composited over
                    // the Version row for roughly a second on iPhone landscape.
                    LandscapeTimerView(
                        store: store,
                        isActive: store.selectedTab == .timer
                    )
                    .opacity(store.selectedTab == .timer ? 1 : 0)
                    .allowsHitTesting(store.selectedTab == .timer)
                    .accessibilityHidden(store.selectedTab != .timer)
                    .zIndex(store.selectedTab == .timer ? 1 : 0)

                    NavigationStack(path: $store.recordsPath) {
                        RecordsDesignView(store: store)
                    }
                        .opacity(store.selectedTab == .records ? 1 : 0)
                        .allowsHitTesting(store.selectedTab == .records)
                        .accessibilityHidden(store.selectedTab != .records)
                        .zIndex(store.selectedTab == .records ? 1 : 0)

                    LandscapeSettingsView(store: store)
                        .opacity(store.selectedTab == .settings ? 1 : 0)
                        .allowsHitTesting(store.selectedTab == .settings)
                        .accessibilityHidden(store.selectedTab != .settings)
                        .zIndex(store.selectedTab == .settings ? 1 : 0)
                }
                // The system already supplies the landscape safe-area insets.
                // Reserve only the rail's real footprint; mirroring that inset
                // on the trailing side left a large, purposeless empty column.
                .frame(maxWidth: 760, maxHeight: .infinity)
                .padding(.leading, 72)
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(pageAnimation, value: store.selectedTab)

                landscapeRail
            }
            // RootView already records URL/QA routes in presentedRoute. The
            // portrait settings stack observed it, but the dedicated landscape
            // stack did not, so a route opened while compact-height was active
            // silently stopped at the settings overview.
            .navigationDestination(for: AppRoute.self) { route in
                AppRouteDestination(route: route, store: store)
            }
        }
        .onChange(of: store.presentedRoute) { _, route in
            guard let route else { return }
            store.activePath.append(route)
            store.presentedRoute = nil
        }
        .background(OWCDesign.page)
    }

    private var landscapeRail: some View {
        VStack(spacing: 8) {
            Spacer()
            railButton(.timer, icon: "timer", title: store.t("timerTab"))
            railButton(.records, icon: "calendar", title: store.t("recordsTab"))
            railButton(.settings, icon: "slider.horizontal.3", title: store.t("settings"))
            Spacer()
        }
        .frame(width: 62)
        .padding(.leading, 8)
    }

    private func railButton(_ tab: AppTab, icon: String, title: String) -> some View {
        Button {
            store.selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title2)
                Text(title).font(.caption2.weight(store.selectedTab == tab ? .semibold : .medium))
            }
            .foregroundStyle(store.selectedTab == tab ? OWCDesign.accent : OWCDesign.tertiary)
            .frame(maxWidth: .infinity, minHeight: 64)
            .glassEffect(
                store.selectedTab == tab
                    ? .regular.tint(OWCDesign.accent.opacity(0.18)).interactive()
                    : .regular.interactive(),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var pageAnimation: Animation {
        reduceMotion ? OWCMotion.reduced : OWCMotion.navigation
    }

}

private struct LandscapeTimerView: View {
    // No semantic style goes this large; scale the display size instead.
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 76
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
                    landscapeContent(at: store.timerDate(from: timeline.date))
                }
            } else {
                landscapeContent(at: store.timerDate(from: .now))
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showShare) {
            ShareComposerView(store: store).presentationDetents([.large])
        }
        .sheet(isPresented: $showOvertime) {
            // A time picker and one button. On iPad .large filled the display
            // with a sheet that was mostly empty.
            OvertimeSheet(store: store)
                .presentationDetents([.height(340)])
                .presentationCornerRadius(26)
        }
    }

    @ViewBuilder
    private func landscapeContent(at date: Date) -> some View {
        let snapshot = store.shouldQuerySnapshot(at: date) ? store.snapshot(at: date) : nil
        let phase = store.visualPhase(snapshot: snapshot, at: date)

        ZStack {
            if phase.showsActiveTimer, let snapshot {
                let beforeStart = phase == .clockIn
                let onBreak = phase == .lunch
                let overtime = phase == .overtime
                let remaining = beforeStart
                    ? store.countdownToClockInMs(snapshot: snapshot, at: date)
                    : snapshot.heroRemainingMs(at: date)
                VStack(spacing: 0) {
                    if !store.isForcedWorkday(snapshot),
                       !beforeStart,
                       let note = store.earlyClockInNote(at: date) {
                        EarlyClockInBanner(store: store, note: note)
                            .padding(.bottom, 8)
                    }

                    if store.isForcedWorkday(snapshot) || onBreak || overtime {
                        HStack(spacing: 8) {
                            if store.isForcedWorkday(snapshot) {
                                ManualTimingBanner(store: store, compact: true)
                            }
                            if onBreak {
                                Label(store.t("lunchInProgress"), systemImage: "cup.and.saucer")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(OWCDesign.secondary)
                                    .padding(.horizontal, 12)
                                    .frame(height: 26)
                                    .background(OWCDesign.control, in: Capsule())
                            } else if overtime {
                                TimerPhasePill(
                                    title: store.t(
                                        "overtimeUntil",
                                        values: ["time": store.formatTime(snapshot.overtimeEndDate ?? snapshot.endDate)]
                                    ),
                                    systemImage: "clock.fill",
                                    tint: OWCDesign.orangeDeep,
                                    fill: OWCDesign.orange.opacity(0.12)
                                )
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    Text(date.formatted(.dateTime.month().day().weekday(.wide).locale(store.locale)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OWCDesign.secondary)
                        .padding(.bottom, 4)
                    Text(store.formatDuration(remaining))
                        .font(.system(size: countdownSize, weight: .bold).monospacedDigit())
                        .tracking(-3)
                        .lineLimit(1)
                        .owcCountdownTextTransition(milliseconds: remaining)
                    landscapeCaption(snapshot, phase: phase)
                        .font(.subheadline)
                        .foregroundStyle(OWCDesign.secondary)
                        .padding(.top, 6)

                    VStack(spacing: 8) {
                        GeometryReader { proxy in
                            let fill = beforeStart
                                ? store.countdownToClockInProgress(snapshot: snapshot)
                                : snapshot.progress
                            Capsule().fill(OWCDesign.control)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(OWCDesign.accent)
                                        .frame(width: proxy.size.width * min(1, max(0, fill / 100)))
                                }
                        }
                        .frame(height: 10)
                        GeometryReader { proxy in
                            if beforeStart {
                                Text(store.formatTime(countdownAnchor(snapshot, at: date)))
                                    .position(x: 24, y: 8)
                                Text(store.formatTime(snapshot.startDate))
                                    .position(x: proxy.size.width - 24, y: 8)
                            } else {
                                Text(store.timeString(store.effectiveStartMinutes(at: date)))
                                    .position(x: 24, y: 8)
                                if store.effectiveLunchEnabled(at: date), snapshot.segments.count > 1 {
                                    Text("\(store.timeString(store.effectiveLunchStartMinutes(at: date))) · \(store.t("lunchBreak"))")
                                        .position(x: max(110, min(proxy.size.width - 110, proxy.size.width * lunchWallRatio(snapshot))), y: 8)
                                }
                                Text(store.timeString(store.effectiveEndMinutes(at: date)))
                                    .position(x: proxy.size.width - 24, y: 8)
                            }
                        }
                        .frame(height: 16)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(OWCDesign.secondary)
                    }
                    .padding(.top, 20)

                    HStack(spacing: 52) {
                        landscapeStat(
                            store.t("progress"),
                            store.formatPercent(
                                beforeStart
                                    ? store.countdownToClockInProgress(snapshot: snapshot)
                                    : snapshot.progress
                            )
                        )
                        if store.presentationSalaryEnabled { landscapeStat(store.t("moneyEarned"), store.hideEarnings ? "••••" : store.formatMoney(snapshot.dailySalary.map { $0 * snapshot.payRatio })) }
                        if store.effectiveScheduleMode(at: date) != .off { landscapeStat(store.t("daysUntilRest"), daysUntilRest(snapshot, now: date)) }
                    }
                    .padding(.top, 20)

                    HStack(spacing: 10) {
                        if beforeStart {
                            Button {
                                store.requestClockInEarly(at: date)
                            } label: {
                                ClockInEarlyLabel(store: store)
                            }
                            Button { showShare = true } label: {
                                Label(store.t("shareButton"), systemImage: "square.and.arrow.up")
                            }
                        } else {
                            Button {
                                store.requestClockOffEarly(at: date)
                            } label: { ClockOffEarlyLabel(store: store) }
                            Button { showOvertime = true } label: {
                                Text(store.t(snapshot.isOvertimeActive(at: date) ? "adjustOvertime" : "overtime"))
                            }
                            Button { showShare = true } label: { Label(store.t("shareButton"), systemImage: "square.and.arrow.up") }
                        }
                    }
                    .buttonStyle(LandscapeButtonStyle())
                    .padding(.top, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
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

    @ViewBuilder
    private func landscapeCaption(
        _ snapshot: NativeShiftSnapshot,
        phase: TimerVisualPhase
    ) -> some View {
        if phase == .clockIn {
            Text(store.t("nextShiftLabelShort"))
        } else if phase == .lunch, let breakEnd = snapshot.activeBreakEndDate {
            Label(
                store.t("pausedUntil", values: ["time": store.formatTime(breakEnd)]),
                systemImage: "cup.and.saucer"
            )
        } else if phase == .overtime {
            Label(store.t("overtimeTimeLeftCaption"), systemImage: "clock.fill")
                .symbolRenderingMode(.monochrome)
        } else {
            Text(store.t("timeLeftCaption"))
        }
    }

    private func countdownAnchor(_ snapshot: NativeShiftSnapshot, at date: Date) -> Date {
        snapshot.countdownAnchorAtMs.map { Date(timeIntervalSince1970: $0 / 1_000) }
            ?? Calendar.current.startOfDay(for: date)
    }

    private var timerAnimation: Animation {
        reduceMotion ? OWCMotion.reduced : OWCMotion.phase
    }

    private var timerTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
    }

    private func landscapeStat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.caption).foregroundStyle(OWCDesign.secondary)
            Text(value).font(.title3.bold().monospacedDigit())
        }
    }

    private var weekSummary: NativePeriodSummary? {
        guard let snapshot = store.snapshot() else { return nil }
        return store.periodSummary("week", asOf: .now, snapshot: snapshot)
    }

    private func lunchWallRatio(_ snapshot: NativeShiftSnapshot) -> Double {
        guard let lunchStart = snapshot.segments.first?.endAtMs else { return 0.5 }
        return min(1, max(0, (lunchStart - snapshot.startAtMs) / max(1, snapshot.plannedEndAtMs - snapshot.startAtMs)))
    }

    private func daysUntilRest(_ snapshot: NativeShiftSnapshot, now: Date) -> String {
        guard let rest = snapshot.nextRestDate else { return "—" }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: now),
            to: Calendar.current.startOfDay(for: rest)
        ).day ?? 0
        return store.formatDays(Double(max(0, days)))
    }
}

private struct LandscapeSettingsView: View {
    let store: OffWorkStore

    /// Same sections as portrait, two columns instead of one — landscape has
    /// the width and not the height. Both the contents and the split come from
    /// shared code, so the two orientations cannot drift apart again.
    private var columns: [[SettingsSection]] { SettingsSection.twoColumns }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Text(store.t("settings"))
                        .font(.title.bold())
                        .tracking(-0.65)
                    HStack {
                        Spacer()
                        SettingsPlusStarButton(store: store)
                    }
                }
                .frame(maxWidth: .infinity)

                HStack(alignment: .top, spacing: 18) {
                    ForEach(columns.indices, id: \.self) { column in
                        VStack(spacing: 14) {
                            ForEach(columns[column]) { section in
                                SettingsSectionCard(store: store, section: section)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 10)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(OWCDesign.page)
        .navigationBarHidden(true)
    }
}

private struct LandscapeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 20)
            .frame(height: 44)
            .background(OWCDesign.card.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .shadow(color: .black.opacity(0.07), radius: 4, y: 2)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
