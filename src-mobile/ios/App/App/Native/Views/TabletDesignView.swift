import SwiftUI

/// iPad directions 1p/1r/1t/1u. The wide canvas has its own navigation and
/// density instead of stretching the phone's grouped list.
struct TabletShellView: View {
    @ObservedObject var store: OffWorkStore
    @State private var sidebarVisible = true

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                TabletSidebar(store: store) {
                    withAnimation(.snappy(duration: 0.28)) { sidebarVisible = false }
                }
                .frame(width: 290)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            NavigationStack {
                ZStack {
                    Group {
                        switch store.selectedTab {
                    case .timer:
                        NarrowPaneFallback { isNarrow in
                            if isNarrow {
                                // Push into this stack rather than take the
                                // default, which switches to the settings tab —
                                // the sidebar selection should not move because
                                // a row on the timer page was tapped.
                                TimerDesignView(store: store, wide: false) { route in
                                    store.presentedRoute = route
                                }
                            } else {
                                TabletTimerView(store: store, sidebarVisible: sidebarVisible) {
                                    withAnimation(.snappy(duration: 0.28)) { sidebarVisible = true }
                                }
                            }
                        }
                    case .settings:
                        NarrowPaneFallback { isNarrow in
                            if isNarrow {
                                SettingsDesignView(store: store, wide: false)
                            } else {
                                TabletSettingsView(store: store, sidebarVisible: sidebarVisible) {
                                    withAnimation(.snappy(duration: 0.28)) { sidebarVisible = true }
                                }
                            }
                        }
                        }
                    }
                    .id(store.selectedTab)
                    .transition(.opacity.combined(with: .scale(scale: 0.99)))
                }
                .animation(.smooth(duration: 0.32), value: store.selectedTab)
                .navigationDestination(item: $store.presentedRoute) { route in
                    switch route {
                    case .schedule: ScheduleSettingsView(store: store)
                    case .salary: SalaryDesignView(store: store)
                    case .notifications: NotificationDesignView(store: store)
                    case .lunch: LunchSettingsView(store: store)
                    case .health: HealthReminderSettingsView(store: store)
                    case .theme: ThemeSettingsView(store: store)
                    case .about: AboutView(store: store)
                    }
                }
            }
        }
        .background(OWCDesign.page)
    }
}

private struct TabletSidebar: View {
    @ObservedObject var store: OffWorkStore
    let hide: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image("BrandIcon")
                    .resizable()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(store.t("offWorkCountdown"))
                    .font(.system(size: 17, weight: .bold))
                    .tracking(-0.34)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 4)
                Button(action: hide) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 17))
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
                tabButton(.settings, icon: "slider.horizontal.3", title: store.t("settings"))
            }

            // Ticks with the clock. Reading the snapshot once at render time
            // froze the sidebar's countdown and bar while the main column kept
            // moving, which read as the app having stalled.
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
            if store.countdownStarted, let snapshot = store.snapshot(at: timeline.date) {
                OWCSectionHeader(title: store.selectedTab == .timer ? store.t("todaysShift") : store.t("widgetWorking"))
                    .padding(.top, 26)

                if store.selectedTab == .timer {
                    OWCGroupCard {
                        sidebarRow(store.t("shiftSection"), "\(store.timeString(store.startMinutes)) – \(store.timeString(store.endMinutes))")
                        sidebarRow(store.t("lunchBreak"), lunchLabel, last: !store.salaryEnabled)
                        if store.salaryEnabled {
                            sidebarRow(store.t("moneyEarned"), store.hideEarnings ? "••••" : store.formatMoney(snapshot.dailySalary.map { $0 * snapshot.payRatio }), last: true, bold: true)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(store.formatDuration(snapshot.remainingMs))
                            .font(.system(size: 30, weight: .bold).monospacedDigit())
                            .tracking(-0.8)
                        Text(store.t("timeLeftCaption"))
                            .font(.system(size: 13))
                            .foregroundStyle(OWCDesign.secondary)
                            .padding(.top, 6)
                        GeometryReader { proxy in
                            Capsule().fill(OWCDesign.control)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(OWCDesign.accent)
                                        .frame(width: proxy.size.width * min(1, max(0, snapshot.progress / 100)))
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

    private func tabButton(_ tab: AppTab, icon: String, title: String) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.32)) { store.selectedTab = tab }
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 17, weight: store.selectedTab == tab ? .semibold : .regular))
                .foregroundStyle(store.selectedTab == tab ? .white : OWCDesign.primary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 12)
                .glassEffect(
                    store.selectedTab == tab
                        ? .regular.tint(OWCDesign.accent).interactive()
                        : .regular.interactive(),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    private func sidebarRow(_ label: String, _ value: String, last: Bool = false, bold: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 16))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 16, weight: bold ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(bold ? OWCDesign.primary : OWCDesign.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .overlay(alignment: .bottomTrailing) {
            if !last { Rectangle().fill(OWCDesign.separator).frame(height: 0.5).padding(.leading, 14) }
        }
    }

    private var lunchLabel: String {
        guard store.lunchEnabled else { return store.t("disabledShort") }
        return "\(store.timeString(store.lunchStartMinutes)) · \(store.formatRelativeDuration(Double(store.lunchDurationMinutes) * 60_000))"
    }
}

private struct TabletTimerView: View {
    @ObservedObject var store: OffWorkStore
    let sidebarVisible: Bool
    let showSidebar: () -> Void
    @State private var showShare = false
    @State private var showOvertime = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            ZStack {
                if !store.countdownStarted {
                    TabletSetupView(store: store, sidebarVisible: sidebarVisible, showSidebar: showSidebar)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else if let snapshot = store.snapshot(at: timeline.date), snapshot.remainingMs > 0, snapshot.isWorkday || store.forceToday {
                    TabletRunningView(
                        store: store,
                        snapshot: snapshot,
                        now: timeline.date,
                        sidebarVisible: sidebarVisible,
                        showSidebar: showSidebar,
                        showShare: $showShare,
                        showOvertime: $showOvertime
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    TimerDesignView(store: store, wide: true)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(.smooth(duration: 0.42), value: store.countdownStarted)
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
}

private struct TabletRunningView: View {
    @ObservedObject var store: OffWorkStore
    let snapshot: NativeShiftSnapshot
    let now: Date
    let sidebarVisible: Bool
    let showSidebar: () -> Void
    @Binding var showShare: Bool
    @Binding var showOvertime: Bool

    var body: some View {
        VStack(spacing: 0) {
            tabletHeader(store: store, sidebarVisible: sidebarVisible, showSidebar: showSidebar)

            VStack(spacing: 0) {
                // Lunch and overtime were missing here entirely: the iPad drew
                // the plain running layout in every phase, so a break showed a
                // frozen number under "time left" with no explanation.
                if let pill = statusPill {
                    Group {
                        if pill.symbol.isEmpty {
                            Text(pill.text)
                        } else {
                            Label(pill.text, systemImage: pill.symbol)
                        }
                    }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(pill.tint)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(pill.tint.opacity(0.12), in: Capsule())
                        .padding(.bottom, 18)
                }

                Text(store.formatDuration(displayRemaining))
                    .font(.system(size: sidebarVisible ? 88 : 150, weight: .bold).monospacedDigit())
                    .tracking(sidebarVisible ? -3 : -5)
                    .foregroundStyle(onBreak ? OWCDesign.secondary : OWCDesign.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .contentTransition(.numericText(countsDown: true))
                Text(heroCaption)
                    .font(.system(size: sidebarVisible ? 17 : 19))
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, sidebarVisible ? 14 : 18)

                if sidebarVisible {
                    OWCProgressMeter(progress: snapshot.progress, overtime: isOvertime, paused: onBreak)
                        .padding(.top, 17)

                    if store.scheduleMode != .off {
                    HStack(spacing: 14) {
                        statCard(store.t("summaryThisWeek"), summaryLabel(weekSummary, includeMoney: false))
                        statCard(store.t("summaryThisYear"), summaryLabel(yearSummary, includeMoney: store.salaryEnabled))
                    }
                    .padding(.top, 44)
                    }
                } else {
                    segmentedProgress
                        .padding(.top, 56)
                    HStack(spacing: 56) {
                        fullStat(store.t("progress"), String(format: "%.1f%%", snapshot.progress))
                        if store.salaryEnabled { fullStat(store.t("moneyEarned"), store.hideEarnings ? "••••" : store.formatMoney(snapshot.dailySalary.map { $0 * snapshot.payRatio })) }
                        if store.scheduleMode != .off { fullStat(store.t("daysUntilRest"), daysUntilRest) }
                    }
                    .padding(.top, 56)
                }

                HStack(spacing: 12) {
                    Button {
                        withAnimation(.smooth(duration: 0.42)) {
                            store.stopCountdown()
                        }
                    } label: { Label(store.t("return"), systemImage: "arrow.left") }
                    Button { showOvertime = true } label: {
                        Text(store.t(isOvertime ? "adjustOvertime" : "overtime"))
                    }
                    Button { showShare = true } label: { Label(store.t("shareButton"), systemImage: "square.and.arrow.up") }
                }
                .buttonStyle(OWCSecondaryButtonStyle())
                .padding(.top, sidebarVisible ? 24 : 56)
            }
            .frame(maxWidth: sidebarVisible ? 560 : 900)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }

    private var onBreak: Bool { snapshot.activeBreakEndAtMs != nil }

    private var isOvertime: Bool {
        snapshot.overtimeEndAtMs != nil
            && now.timeIntervalSince1970 * 1_000 >= snapshot.plannedEndAtMs
    }

    /// On a break the shift clock is frozen, so the screen counts the break down
    /// instead — the same substitution the phone makes.
    private var displayRemaining: Double {
        guard onBreak, let breakEnd = snapshot.activeBreakEndAtMs else {
            return snapshot.remainingMs
        }
        return max(0, breakEnd - now.timeIntervalSince1970 * 1_000)
    }

    private var heroCaption: String {
        if onBreak, let breakEnd = snapshot.activeBreakEndDate {
            return store.t("pausedUntil", values: ["time": store.formatTime(breakEnd)])
        }
        return store.t("timeLeftCaption")
    }

    private var statusPill: (text: String, symbol: String, tint: Color)? {
        if onBreak {
            return (store.t("lunchInProgress"), "cup.and.saucer", OWCDesign.secondary)
        }
        if isOvertime, let overtimeEnd = snapshot.overtimeEndDate {
            return (
                store.t("overtimeUntil", values: ["time": store.formatTime(overtimeEnd)]),
                "",
                OWCDesign.accent
            )
        }
        return nil
    }

    private func statCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13)).foregroundStyle(OWCDesign.secondary)
            Text(value).font(.system(size: 20, weight: .semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(OWCDesign.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func fullStat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 13)).foregroundStyle(OWCDesign.secondary)
            Text(value).font(.system(size: 28, weight: .bold).monospacedDigit())
        }
    }

    private var weekSummary: NativePeriodSummary? { store.periodSummary("week", asOf: .now, snapshot: snapshot) }
    private var yearSummary: NativePeriodSummary? { store.periodSummary("year", asOf: .now, snapshot: snapshot) }

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
                Text(store.timeString(store.startMinutes)).position(x: 30, y: 9)
                if store.lunchEnabled, snapshot.segments.count > 1 {
                    Text("\(store.timeString(store.lunchStartMinutes)) · \(store.t("lunchBreak"))")
                        .position(x: max(68, min(proxy.size.width - 68, proxy.size.width * lunchWallRatio)), y: 9)
                }
                Text(store.timeString(store.endMinutes)).position(x: proxy.size.width - 30, y: 9)
            }
            .frame(height: 18)
            .font(.system(size: 14).monospacedDigit())
            .foregroundStyle(OWCDesign.secondary)
        }
    }

    private var lunchWallRatio: Double {
        guard let lunchStart = snapshot.segments.first?.endAtMs else { return 0.5 }
        return min(1, max(0, (lunchStart - snapshot.startAtMs) / max(1, snapshot.plannedEndAtMs - snapshot.startAtMs)))
    }

    private var daysUntilRest: String {
        guard let date = snapshot.nextRestDate else { return "—" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: date)).day ?? 0
        return store.formatDays(Double(max(0, days)))
    }
}

private struct TabletSetupView: View {
    @ObservedObject var store: OffWorkStore
    let sidebarVisible: Bool
    let showSidebar: () -> Void
    @State private var armed = false
    @State private var armResetTask: Task<Void, Never>?
    @State private var showInvalidLunch = false
    @State private var navigateLunch = false

    var body: some View {
        VStack(spacing: 0) {
            tabletHeader(store: store, sidebarVisible: sidebarVisible, showSidebar: showSidebar)

            VStack(spacing: 0) {
                Text("\(store.timeString(store.startMinutes)) — \(store.timeString(store.endMinutes))")
                    .font(.system(size: 64, weight: .bold).monospacedDigit())
                    .tracking(-2.2)
                Text("\(store.formatRelativeDuration(shiftMs)) · \(lunchLabel) · \(workdaysDescription)")
                    .font(.system(size: 17))
                    .foregroundStyle(OWCDesign.secondary)
                    .padding(.top, 12)

                OWCSectionHeader(title: store.t("shiftSection"))
                    .padding(.top, 34)
                OWCGroupCard {
                    TabletTimeRow(store: store, icon: "sunrise", title: store.t("startTime"), minutes: $store.startMinutes)
                    TabletTimeRow(store: store, icon: "sunset", title: store.t("endTime"), minutes: $store.endMinutes)
                    NavigationLink { ScheduleSettingsView(store: store) } label: {
                        OWCRow(icon: "calendar.badge.clock", title: store.t("workSchedule"), isLast: true) { OWCDetailAccessory(text: scheduleLabel) }
                    }
                    .buttonStyle(OWCRowButtonStyle())
                }

                HStack(spacing: 14) {
                    NavigationLink { LunchSettingsView(store: store) } label: {
                        tabletShortcut("cup.and.saucer", store.t("lunchBreak"), lunchLabel)
                    }
                    NavigationLink { SalaryDesignView(store: store) } label: {
                        tabletShortcut("banknote", store.t("salarySettings"), store.salaryEnabled ? (store.salaryType == .monthly ? store.t("monthly") : store.t("daily")) : store.t("disabledShort"))
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 20)

                Spacer(minLength: 20)
                Button { startTapped() } label: { Label(armed ? store.t("nonWorkdayTapAgain") : store.t("startCountdown"), systemImage: armed ? "exclamationmark.triangle.fill" : "play.fill") }
                    .buttonStyle(OWCPrimaryButtonStyle(color: armed ? OWCDesign.orangeDeep : OWCDesign.accent))
                    .disabled(startDisabled)
                    .opacity(startDisabled ? 0.45 : 1)
                    .frame(height: 56)
                    .padding(.bottom, 40)
            }
            .frame(maxWidth: 620)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 40)
        }
        .navigationDestination(isPresented: $navigateLunch) { LunchSettingsView(store: store) }
        .alert(store.t("invalidLunchTitle"), isPresented: $showInvalidLunch) {
            Button(store.t("return"), role: .cancel) {}
            Button(store.t("goToLunchSettings")) { navigateLunch = true }
        } message: { Text(store.t("invalidLunchMessage")) }
        .sensoryFeedback(.warning, trigger: armed)
        .onDisappear { armResetTask?.cancel() }
    }

    private var shiftMs: Double {
        let value = store.endMinutes > store.startMinutes ? store.endMinutes - store.startMinutes : store.endMinutes + 1_440 - store.startMinutes
        return Double(value) * 60_000
    }
    private var lunchLabel: String { store.lunchEnabled ? store.formatRelativeDuration(Double(store.lunchDurationMinutes) * 60_000) : store.t("disabledShort") }
    private var workdaysDescription: String {
        if store.scheduleMode != .classic { return scheduleLabel }
        let values = Array(zip([1, 2, 3, 4, 5, 6, 0], store.weekdayLabels())).filter { store.workdays.contains($0.0) }.map(\.1)
        guard let first = values.first else { return store.t("disabledShort") }
        return values.count > 1 ? "\(first) – \(values.last ?? first)" : first
    }
    private var scheduleLabel: String { switch store.scheduleMode { case .classic: store.t("scheduleClassic"); case .alternating: store.t("scheduleAlternating"); case .rotation: store.t("scheduleRotation"); case .off: store.t("scheduleOff") } }
    private var startDisabled: Bool { store.startMinutes == store.endMinutes || (store.scheduleMode == .classic && store.workdays.isEmpty) }
    private func startTapped() {
        guard store.isLunchInsideShift else { showInvalidLunch = true; return }
        let nonWorkday = store.scheduleMode != .off && store.snapshot()?.isWorkday == false
        if nonWorkday, !armed {
            withAnimation(.snappy) { armed = true }
            resetArmedState()
            return
        }
        armResetTask?.cancel()
        withAnimation(.smooth(duration: 0.42)) {
            store.startCountdown(force: nonWorkday)
        }
    }
    private func resetArmedState() {
        armResetTask?.cancel()
        armResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { armed = false }
        }
    }
    private func tabletShortcut(_ icon: String, _ title: String, _ value: String) -> some View {
        OWCGroupCard {
            OWCRow(icon: icon, title: title, isLast: true) { OWCDetailAccessory(text: value) }
        }
    }
}

private struct TabletTimeRow: View {
    @ObservedObject var store: OffWorkStore
    let icon: String
    let title: String
    @Binding var minutes: Int
    @State private var showPicker = false

    var body: some View {
        Button { showPicker = true } label: {
            OWCRow(icon: icon, title: title) { OWCDetailAccessory(text: store.timeString(minutes)) }
        }
        .buttonStyle(OWCRowButtonStyle())
        .sheet(isPresented: $showPicker) {
            OWCSetupTimePickerSheet(store: store, title: title, minutes: $minutes)
                .presentationDetents([.medium])
        }
    }
}

private struct TabletSettingsView: View {
    @ObservedObject var store: OffWorkStore
    let sidebarVisible: Bool
    let showSidebar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if !sidebarVisible {
                    Button(action: showSidebar) { Image(systemName: "sidebar.left").frame(width: 38, height: 38).background(OWCDesign.card).clipShape(RoundedRectangle(cornerRadius: 12)) }
                    .buttonStyle(.plain)
                }
                Text(store.t("settings"))
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.85)
                Spacer()
            }

            // Two columns only when they actually fit. With the sidebar open an
            // 11-inch iPad leaves ~544 pt here, and splitting that in two left
            // every value truncated and "off-work reminder" wrapping onto two
            // lines. Below the threshold the same sections stack instead.
            AdaptiveSettingsColumns(spacing: 26) {
                VStack(spacing: 20) {
                    section(store.t("shiftSection")) {
                        NavigationLink { ScheduleSettingsView(store: store) } label: { OWCRow(icon: "calendar.badge.clock", title: store.t("workSchedule")) { OWCDetailAccessory(text: scheduleLabel) } }.buttonStyle(OWCRowButtonStyle())
                        NavigationLink { LunchSettingsView(store: store) } label: { OWCRow(icon: "cup.and.saucer", title: store.t("lunchBreak")) { OWCDetailAccessory(text: lunchLabel) } }.buttonStyle(OWCRowButtonStyle())
                        NavigationLink { HealthReminderSettingsView(store: store) } label: { OWCRow(icon: "figure.walk", title: store.t("microBreakReminder")) { OWCDetailAccessory(text: healthLabel) } }.buttonStyle(OWCRowButtonStyle())
                        NavigationLink { SalaryDesignView(store: store) } label: { OWCRow(icon: "banknote", title: store.t("salarySettings"), isLast: true) { OWCDetailAccessory(text: salaryLabel) } }.buttonStyle(OWCRowButtonStyle())
                    }
                    sectionNote(store.t("tabletShiftSettingsNote"))
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 20) {
                    section(store.t("remindersSection")) {
                        NavigationLink { NotificationDesignView(store: store) } label: { OWCRow(icon: "bell.badge", title: store.t("offWorkReminder"), isLast: true) { OWCDetailAccessory(text: notificationLabel) } }.buttonStyle(OWCRowButtonStyle())
                    }
                    sectionNote(store.t("notificationPrivacyNote"))
                    section(store.t("appearanceSection")) {
                        NavigationLink { ThemeSettingsView(store: store) } label: { OWCRow(icon: "display", title: store.t("theme")) { OWCDetailAccessory(text: themeLabel) } }.buttonStyle(OWCRowButtonStyle())
                        Link(destination: OWCSystemSettings.applicationURL) { OWCRow(icon: "globe", title: store.t("chooselanguage"), isLast: true) { OWCDetailAccessory(text: store.localizer.languageName(for: store.languageCode), external: true) } }.buttonStyle(OWCRowButtonStyle())
                    }
                    section(store.t("aboutSection")) {
                        NavigationLink { AboutView(store: store) } label: { OWCRow(icon: "info.circle", title: store.t("aboutProject")) { OWCDetailAccessory(text: nil) } }.buttonStyle(OWCRowButtonStyle())
                        OWCRow(icon: "tag", title: store.t("version"), isLast: true) { Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0").foregroundStyle(OWCDesign.secondary) }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 22)
            Spacer()
        }
        .padding(.leading, sidebarVisible ? 34 : 40)
        .padding(.trailing, 40)
        .padding(.top, 26)
        .background(OWCDesign.page)
        .navigationBarHidden(true)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { OWCSectionHeader(title: title); OWCGroupCard(content: content) }
    }
    private func sectionNote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(OWCDesign.secondary)
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, -12)
    }
    private var lunchLabel: String { store.lunchEnabled ? "\(store.timeString(store.lunchStartMinutes)) · \(store.formatRelativeDuration(Double(store.lunchDurationMinutes) * 60_000))" : store.t("disabledShort") }
    private var healthLabel: String { store.microBreakEnabled ? store.t("minutesShort", values: ["count": "\(store.microBreakIntervalMinutes)"]) : store.t("disabledShort") }
    private var salaryLabel: String {
        guard store.salaryEnabled else { return store.t("disabledShort") }
        let type = store.salaryType == .monthly ? store.t("monthly") : store.t("daily")
        guard let amount = Double(store.salaryAmount), !store.salaryAmount.isEmpty else { return type }
        let fractionDigits = amount.rounded() == amount ? 0 : 2
        let formatted = amount.formatted(.number.precision(.fractionLength(fractionDigits)).locale(store.locale))
        return "\(type) · \(formatted)"
    }
    private var scheduleLabel: String { switch store.scheduleMode { case .classic: store.t("scheduleClassic"); case .alternating: store.t("scheduleAlternating"); case .rotation: store.t("scheduleRotation"); case .off: store.t("scheduleOff") } }
    private var workdaysDescription: String {
        if store.scheduleMode != .classic { return scheduleLabel }
        let values = Array(zip([1, 2, 3, 4, 5, 6, 0], store.weekdayLabels()))
            .filter { store.workdays.contains($0.0) }
            .map(\.1)
        guard let first = values.first else { return store.t("disabledShort") }
        return values.count > 1 ? "\(first) – \(values.last ?? first)" : first
    }
    private var notificationLabel: String {
        switch store.notificationMode { case .off: store.t("notificationModeOff"); case .simple: store.t("notificationModeSimple"); case .milestones: store.t("notificationModeMilestones") }
    }
    private var themeLabel: String { switch store.theme { case .auto: store.t("auto"); case .light: store.t("light"); case .dark: store.t("dark") } }
}


@MainActor
private func tabletHeader(store: OffWorkStore, sidebarVisible: Bool, showSidebar: @escaping () -> Void) -> some View {
    HStack {
        if !sidebarVisible {
            Button(action: showSidebar) {
                Image(systemName: "sidebar.left")
                    .frame(width: 38, height: 38)
                    .background(OWCDesign.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        Spacer()
        Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(store.locale)).uppercased())
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.78)
            .foregroundStyle(OWCDesign.secondary)
        Spacer()
        Button { store.toggleQuickTheme() } label: {
            Group {
                if store.quickThemeIsAuto {
                    Text(verbatim: "A").font(.system(size: 17, weight: .semibold))
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

    private static var twoColumnMinimum: CGFloat { 620 }

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
