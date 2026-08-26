import SwiftUI

struct PhoneLandscapeShellView: View {
    @Bindable var store: OffWorkStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack(path: $store.activePath) {
            ZStack(alignment: .leading) {
                OWCDesign.page.ignoresSafeArea()

                ZStack {
                    if store.selectedTab == .settings {
                        LandscapeSettingsView(store: store)
                            .transition(pageTransition)
                    } else {
                        LandscapeTimerView(store: store)
                            .transition(pageTransition)
                    }
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

    private var pageTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
    }
}

private struct LandscapeSetupView: View {
    let store: OffWorkStore
    @State private var timeField: SetupTimeField?

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(spacing: 18) {
                ShiftHeroCard(store: store) { timeField = $0 }
                if let note = store.earlyClockOffNote() {
                    EarlyClockOffBanner(store: store, note: note)
                }
                ShiftStartButton(store: store) { store.presentedRoute = .lunch }
            }
            .frame(maxWidth: .infinity)

            ScrollView {
                ShiftSetupTimelineView(
                    store: store,
                    onSelect: { store.presentedRoute = $0 },
                    onEditTime: { timeField = $0 }
                )
            }
            .frame(maxWidth: .infinity)
            .scrollIndicators(.hidden)
        }
        .frame(maxHeight: 330)
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .sheet(item: $timeField) { field in
            OWCSetupTimePickerSheet(
                store: store,
                title: store.t(field == .start ? "startTime" : "endTime"),
                minutes: Binding(
                    get: { field == .start ? store.displayedStartMinutes : store.displayedEndMinutes },
                    set: { value in
                        if field == .start { store.setDisplayedStartMinutes(value) }
                        else { store.setDisplayedEndMinutes(value) }
                    }
                )
            )
            .presentationDetents([.medium])
        }
    }
}

private struct LandscapeTimerView: View {
    // No semantic style goes this large; scale the display size instead.
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 76
    let store: OffWorkStore
    @State private var showShare = false
    @State private var showOvertime = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion


    var body: some View {
        Group {
            if store.visualPhase(at: .now).usesLiveTimeline {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    landscapeContent(at: timeline.date)
                }
            } else {
                landscapeContent(at: .now)
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
        let snapshot = store.countdownStarted ? store.snapshot(at: date) : nil
        let phase = store.visualPhase(snapshot: snapshot)

        ZStack {
            if phase == .setup {
                LandscapeSetupView(store: store)
            } else if phase.showsActiveTimer, let snapshot {
                let remaining = snapshot.heroRemainingMs(at: date)
                let beforeStart = snapshot.isBeforeStart(at: date)
                VStack(spacing: 0) {
                    Text(date.formatted(.dateTime.month().day().weekday(.wide).locale(store.locale)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OWCDesign.secondary)
                        .padding(.bottom, 4)
                    Text(store.formatDuration(remaining))
                        .font(.system(size: countdownSize, weight: .bold).monospacedDigit())
                        .tracking(-3)
                        .lineLimit(1)
                        .owcCountdownTextTransition(milliseconds: remaining)
                    Text(landscapeCaption(snapshot, at: date))
                        .font(.subheadline)
                        .foregroundStyle(OWCDesign.secondary)
                        .padding(.top, 6)

                    VStack(spacing: 8) {
                        GeometryReader { proxy in
                            Capsule().fill(OWCDesign.control)
                                .overlay(alignment: .leading) {
                                    if !beforeStart {
                                        Capsule().fill(OWCDesign.accent)
                                            .frame(width: proxy.size.width * min(1, max(0, snapshot.progress / 100)))
                                    }
                                }
                        }
                        .frame(height: 10)
                        GeometryReader { proxy in
                            Text(store.timeString(store.startMinutes)).position(x: 24, y: 8)
                            if store.lunchEnabled, snapshot.segments.count > 1 {
                                Text("\(store.timeString(store.lunchStartMinutes)) · \(store.t("lunchBreak"))")
                                    .position(x: max(62, min(proxy.size.width - 62, proxy.size.width * lunchWallRatio(snapshot))), y: 8)
                            }
                            Text(store.timeString(store.endMinutes)).position(x: proxy.size.width - 24, y: 8)
                        }
                        .frame(height: 16)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(OWCDesign.secondary)
                    }
                    .padding(.top, 20)

                    HStack(spacing: 52) {
                        if !beforeStart {
                            landscapeStat(store.t("progress"), store.formatPercent(snapshot.progress))
                        }
                        if store.salaryEnabled { landscapeStat(store.t("moneyEarned"), store.hideEarnings ? "••••" : store.formatMoney(snapshot.dailySalary.map { $0 * snapshot.payRatio })) }
                        if store.scheduleMode != .off { landscapeStat(store.t("daysUntilRest"), daysUntilRest(snapshot)) }
                    }
                    .padding(.top, 20)

                    HStack(spacing: 10) {
                        Button {
                            store.requestClockOffEarly()
                        } label: { ClockOffEarlyLabel(store: store) }
                        Button { showOvertime = true } label: { Text(store.t("overtime")) }
                        Button { showShare = true } label: { Label(store.t("shareButton"), systemImage: "square.and.arrow.up") }
                    }
                    .buttonStyle(LandscapeButtonStyle())
                    .padding(.top, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            } else {
                TimerDesignView(
                    store: store,
                    wide: true,
                    timelineDate: date,
                    animatesPhaseChanges: false
                )
            }
        }
        .id(phase)
        .transition(timerTransition)
        .animation(timerAnimation, value: phase)
    }

    private func landscapeCaption(_ snapshot: NativeShiftSnapshot, at now: Date) -> String {
        if snapshot.isBeforeStart(at: now) { return store.t("nextShiftLabelShort") }
        if let breakEnd = snapshot.activeBreakEndDate {
            return store.t("pausedUntil", values: ["time": store.formatTime(breakEnd)])
        }
        if snapshot.isOvertimeActive(at: now) { return store.t("overtimeTimeLeftCaption") }
        return store.t("timeLeftCaption")
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

    private func daysUntilRest(_ snapshot: NativeShiftSnapshot) -> String {
        guard let rest = snapshot.nextRestDate else { return "—" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: rest)).day ?? 0
        return store.formatDays(Double(max(0, days)))
    }
}

private struct LandscapeSettingsView: View {
    let store: OffWorkStore

    /// Same sections as portrait, two columns instead of one — landscape has
    /// the width and not the height. The contents come from `SettingsSectionCard`
    /// so the two orientations cannot drift apart again.
    private let columns: [[SettingsSection]] = [[.shift], [.reminders, .appearance, .about]]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(store.t("settings"))
                    .font(.title.bold())
                    .tracking(-0.65)
                    .frame(maxWidth: .infinity, alignment: .center)

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
