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
                Group {
                    switch store.selectedTab {
                    case .timer:
                        TabletTimerView(store: store, sidebarVisible: sidebarVisible) {
                            withAnimation(.snappy(duration: 0.28)) { sidebarVisible = true }
                        }
                    case .settings:
                        TabletSettingsView(store: store, sidebarVisible: sidebarVisible) {
                            withAnimation(.snappy(duration: 0.28)) { sidebarVisible = true }
                        }
                    }
                }
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
            .padding(.horizontal, 10)
            .padding(.bottom, 22)

            VStack(spacing: 4) {
                tabButton(.timer, icon: "timer", title: store.t("timerTab"))
                tabButton(.settings, icon: "slider.horizontal.3", title: store.t("settings"))
            }

            if store.countdownStarted, let snapshot = store.snapshot() {
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
            withAnimation(.snappy(duration: 0.22)) { store.selectedTab = tab }
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
            Group {
                if !store.countdownStarted {
                    TabletSetupView(store: store, sidebarVisible: sidebarVisible, showSidebar: showSidebar)
                } else if let snapshot = store.snapshot(at: timeline.date), snapshot.remainingMs > 0, snapshot.isWorkday || store.forceToday {
                    TabletRunningView(
                        store: store,
                        snapshot: snapshot,
                        sidebarVisible: sidebarVisible,
                        showSidebar: showSidebar,
                        showShare: $showShare,
                        showOvertime: $showOvertime
                    )
                } else {
                    TimerDesignView(store: store, wide: true)
                }
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
}

private struct TabletRunningView: View {
    @ObservedObject var store: OffWorkStore
    let snapshot: NativeShiftSnapshot
    let sidebarVisible: Bool
    let showSidebar: () -> Void
    @Binding var showShare: Bool
    @Binding var showOvertime: Bool

    var body: some View {
        VStack(spacing: 0) {
            tabletHeader(store: store, sidebarVisible: sidebarVisible, showSidebar: showSidebar)

            VStack(spacing: 0) {
                Text(store.formatDuration(snapshot.remainingMs))
                    .font(.system(size: sidebarVisible ? 88 : 150, weight: .bold).monospacedDigit())
                    .tracking(sidebarVisible ? -3 : -5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .contentTransition(.numericText(countsDown: true))
                Text(store.t("timeLeftCaption"))
                    .font(.system(size: sidebarVisible ? 17 : 19))
                    .foregroundStyle(OWCDesign.secondary)
                    .padding(.top, sidebarVisible ? 14 : 18)

                if sidebarVisible {
                    OWCProgressMeter(progress: snapshot.progress)
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
                    Button { store.stopCountdown() } label: { Label(store.t("return"), systemImage: "arrow.left") }
                    Button { showOvertime = true } label: { Text(store.t("overtime")) }
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
                    TabletTimeRow(store: store, title: store.t("startTime"), minutes: $store.startMinutes)
                    TabletTimeRow(store: store, title: store.t("endTime"), minutes: $store.endMinutes)
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
        store.startCountdown(force: nonWorkday)
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
    let title: String
    @Binding var minutes: Int
    @State private var showPicker = false

    var body: some View {
        Button { showPicker = true } label: {
            OWCRow(title: title) { OWCDetailAccessory(text: store.timeString(minutes)) }
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

            HStack(alignment: .top, spacing: 26) {
                VStack(spacing: 20) {
                    section(store.t("shiftSection")) {
                        Button { store.selectedTab = .timer } label: {
                            OWCRow(icon: "timer", title: store.t("todaysShift")) {
                                OWCDetailAccessory(text: "\(store.timeString(store.startMinutes)) – \(store.timeString(store.endMinutes)) · \(workdaysDescription)")
                            }
                        }
                        .buttonStyle(OWCRowButtonStyle())
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
        .padding(.horizontal, 40)
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

struct PhoneLandscapeShellView: View {
    @ObservedObject var store: OffWorkStore

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                landscapeRail
                Group {
                    if store.selectedTab == .settings {
                    LandscapeSettingsView(store: store)
                    } else {
                        LandscapeTimerView(store: store)
                    }
                }
            }
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
        Button { store.selectedTab = tab } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 24))
                Text(title).font(.system(size: 11, weight: store.selectedTab == tab ? .semibold : .medium))
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
}

private enum LandscapeSetupTimeField: String, Identifiable {
    case start, end
    var id: String { rawValue }
}

private struct LandscapeSetupView: View {
    @ObservedObject var store: OffWorkStore
    @State private var timeField: LandscapeSetupTimeField?
    @State private var armed = false
    @State private var armResetTask: Task<Void, Never>?
    @State private var showInvalidLunch = false
    @State private var navigateLunch = false

    var body: some View {
        HStack(alignment: .top, spacing: 30) {
            VStack(alignment: .leading, spacing: 14) {
                Text(Date.now.formatted(.dateTime.month().day().weekday(.wide).locale(store.locale)))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OWCDesign.secondary)
                Text("\(store.timeString(store.startMinutes)) — \(store.timeString(store.endMinutes))")
                    .font(.system(size: 42, weight: .bold).monospacedDigit())
                    .tracking(-1.3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                OWCGroupCard {
                    landscapeTimeRow(store.t("startTime"), store.startMinutes) { timeField = .start }
                    landscapeTimeRow(store.t("endTime"), store.endMinutes) { timeField = .end }
                }

                Spacer(minLength: 4)
                Button { startTapped() } label: {
                    Label(armed ? store.t("nonWorkdayTapAgain") : store.t("startCountdown"), systemImage: armed ? "exclamationmark.triangle.fill" : "play.fill")
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(OWCPrimaryButtonStyle(color: armed ? OWCDesign.orangeDeep : OWCDesign.accent))
                .disabled(startDisabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ScrollView {
                VStack(spacing: 12) {
                    NavigationLink { ScheduleSettingsView(store: store) } label: {
                        setupShortcut("calendar.badge.clock", store.t("workSchedule"), scheduleLabel)
                    }
                    NavigationLink { LunchSettingsView(store: store) } label: {
                        setupShortcut("cup.and.saucer", store.t("lunchBreak"), lunchLabel)
                    }
                    NavigationLink { SalaryDesignView(store: store) } label: {
                        setupShortcut("banknote", store.t("salarySettings"), salaryLabel)
                    }
                    NavigationLink { NotificationDesignView(store: store) } label: {
                        setupShortcut("bell.badge", store.t("offWorkReminder"), notificationLabel)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.leading, 22)
        .padding(.trailing, 58)
        .padding(.vertical, 18)
        .sheet(item: $timeField) { field in
            OWCSetupTimePickerSheet(
                store: store,
                title: store.t(field == .start ? "startTime" : "endTime"),
                minutes: Binding(
                    get: { field == .start ? store.startMinutes : store.endMinutes },
                    set: { if field == .start { store.startMinutes = $0 } else { store.endMinutes = $0 } }
                )
            )
            .presentationDetents([.medium])
        }
        .alert(store.t("invalidLunchTitle"), isPresented: $showInvalidLunch) {
            Button(store.t("return"), role: .cancel) {}
            Button(store.t("goToLunchSettings")) { navigateLunch = true }
        } message: { Text(store.t("invalidLunchMessage")) }
        .navigationDestination(isPresented: $navigateLunch) { LunchSettingsView(store: store) }
        .sensoryFeedback(.warning, trigger: armed)
        .onDisappear { armResetTask?.cancel() }
    }

    private func landscapeTimeRow(_ title: String, _ minutes: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            OWCRow(title: title) {
                OWCDetailAccessory(text: store.timeString(minutes))
            }
        }
        .buttonStyle(OWCRowButtonStyle())
    }

    private func setupShortcut(_ icon: String, _ title: String, _ value: String) -> some View {
        OWCGroupCard { OWCRow(icon: icon, title: title, isLast: true) { OWCDetailAccessory(text: value) } }
    }

    private var startDisabled: Bool { store.startMinutes == store.endMinutes || (store.scheduleMode == .classic && store.workdays.isEmpty) }
    private var scheduleLabel: String { switch store.scheduleMode { case .classic: store.t("scheduleClassic"); case .alternating: store.t("scheduleAlternating"); case .rotation: store.t("scheduleRotation"); case .off: store.t("scheduleOff") } }
    private var lunchLabel: String { store.lunchEnabled ? "\(store.timeString(store.lunchStartMinutes)) · \(store.formatRelativeDuration(Double(store.lunchDurationMinutes) * 60_000))" : store.t("disabledShort") }
    private var salaryLabel: String { store.salaryEnabled ? (store.salaryType == .monthly ? store.t("monthly") : store.t("daily")) : store.t("disabledShort") }
    private var notificationLabel: String { switch store.notificationMode { case .off: store.t("notificationModeOff"); case .simple: store.t("notificationModeSimple"); case .milestones: store.t("notificationModeMilestones") } }

    private func startTapped() {
        guard store.isLunchInsideShift else { showInvalidLunch = true; return }
        let nonWorkday = store.scheduleMode != .off && store.snapshot()?.isWorkday == false
        if nonWorkday, !armed {
            withAnimation(.snappy) { armed = true }
            resetArmedState()
            return
        }
        armResetTask?.cancel()
        store.startCountdown(force: nonWorkday)
    }
    private func resetArmedState() {
        armResetTask?.cancel()
        armResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { armed = false }
        }
    }
}

private struct LandscapeTimerView: View {
    @ObservedObject var store: OffWorkStore
    @State private var showShare = false
    @State private var showOvertime = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            if store.countdownStarted, let snapshot = store.snapshot(at: timeline.date), snapshot.remainingMs > 0 {
                VStack(spacing: 0) {
                    Text(timeline.date.formatted(.dateTime.month().day().weekday(.wide).locale(store.locale)))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(OWCDesign.secondary)
                        .padding(.bottom, 4)
                    Text(store.formatDuration(snapshot.remainingMs))
                        .font(.system(size: 76, weight: .bold).monospacedDigit())
                        .tracking(-3)
                        .lineLimit(1)
                        .contentTransition(.numericText(countsDown: true))
                    Text(store.t("timeLeftCaption"))
                        .font(.system(size: 14))
                        .foregroundStyle(OWCDesign.secondary)
                        .padding(.top, 6)

                    VStack(spacing: 8) {
                        GeometryReader { proxy in
                            Capsule().fill(OWCDesign.control)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(OWCDesign.accent)
                                        .frame(width: proxy.size.width * min(1, max(0, snapshot.progress / 100)))
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
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(OWCDesign.secondary)
                    }
                    .padding(.top, 20)

                    HStack(spacing: 52) {
                        landscapeStat(store.t("progress"), String(format: "%.1f%%", snapshot.progress))
                        if store.salaryEnabled { landscapeStat(store.t("moneyEarned"), store.hideEarnings ? "••••" : store.formatMoney(snapshot.dailySalary.map { $0 * snapshot.payRatio })) }
                        if store.scheduleMode != .off { landscapeStat(store.t("daysUntilRest"), daysUntilRest(snapshot)) }
                    }
                    .padding(.top, 20)

                    HStack(spacing: 10) {
                        Button { store.stopCountdown() } label: { Label(store.t("return"), systemImage: "arrow.left") }
                        Button { showOvertime = true } label: { Text(store.t("overtime")) }
                        Button { showShare = true } label: { Label(store.t("shareButton"), systemImage: "square.and.arrow.up") }
                    }
                    .buttonStyle(LandscapeButtonStyle())
                    .padding(.top, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 62)
                .padding(.vertical, 20)
            } else if !store.countdownStarted {
                LandscapeSetupView(store: store)
            } else {
                TimerDesignView(store: store, wide: true)
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showShare) { ShareComposerView(store: store).presentationDetents([.large]) }
        .sheet(isPresented: $showOvertime) { OvertimeSheet(store: store).presentationDetents([.large]) }
    }

    private func landscapeStat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.system(size: 12)).foregroundStyle(OWCDesign.secondary)
            Text(value).font(.system(size: 20, weight: .bold).monospacedDigit())
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
    @ObservedObject var store: OffWorkStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(store.t("settings"))
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.65)

            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 14) {
                    compactSection(store.t("appearanceSection")) {
                        compactLink("display", store.t("theme"), themeLabel) { ThemeSettingsView(store: store) }
                        Link(destination: OWCSystemSettings.applicationURL) {
                            LandscapeRow(
                                icon: "globe",
                                title: store.t("chooselanguage"),
                                value: store.localizer.languageName(for: store.languageCode),
                                last: true,
                                external: true
                            )
                        }
                        .buttonStyle(OWCRowButtonStyle())
                    }
                    compactSection(store.t("shiftSection")) {
                        compactLink("calendar.badge.clock", store.t("workSchedule"), scheduleLabel) { ScheduleSettingsView(store: store) }
                        compactLink("cup.and.saucer", store.t("lunchBreak"), lunchLabel) { LunchSettingsView(store: store) }
                        compactLink("figure.walk", store.t("microBreakReminder"), healthLabel) { HealthReminderSettingsView(store: store) }
                        compactLink("banknote", store.t("salarySettings"), store.salaryEnabled ? (store.salaryType == .monthly ? store.t("monthly") : store.t("daily")) : store.t("disabledShort"), last: true) { SalaryDesignView(store: store) }
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 14) {
                    compactSection(store.t("remindersSection")) {
                        compactLink("bell.badge", store.t("offWorkReminder"), notificationLabel, last: true) { NotificationDesignView(store: store) }
                    }
                    compactSection(store.t("aboutSection")) {
                        compactLink("info.circle", store.t("aboutProject"), nil) { AboutView(store: store) }
                        LandscapeRow(icon: "tag", title: store.t("version"), value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0", last: true)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 12)
        }
        .padding(.leading, 8)
        .padding(.trailing, 62)
        .padding(.vertical, 16)
        .navigationBarHidden(true)
    }

    private func compactSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased()).font(.system(size: 12)).foregroundStyle(OWCDesign.secondary).padding(.horizontal, 14).padding(.bottom, 5)
            VStack(spacing: 0) { content() }.background(OWCDesign.card).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func compactLink<Destination: View>(_ icon: String, _ title: String, _ value: String?, last: Bool = false, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination) { LandscapeRow(icon: icon, title: title, value: value, last: last) }.buttonStyle(OWCRowButtonStyle())
    }
    private var themeLabel: String { switch store.theme { case .auto: store.t("auto"); case .light: store.t("light"); case .dark: store.t("dark") } }
    private var scheduleLabel: String { switch store.scheduleMode { case .classic: store.t("scheduleClassic"); case .alternating: store.t("scheduleAlternating"); case .rotation: store.t("scheduleRotation"); case .off: store.t("scheduleOff") } }
    private var lunchLabel: String { store.lunchEnabled ? "\(store.timeString(store.lunchStartMinutes)) · \(store.formatRelativeDuration(Double(store.lunchDurationMinutes) * 60_000))" : store.t("disabledShort") }
    private var healthLabel: String { store.microBreakEnabled ? store.t("minutesShort", values: ["count": "\(store.microBreakIntervalMinutes)"]) : store.t("disabledShort") }
    private var notificationLabel: String { switch store.notificationMode { case .off: store.t("notificationModeOff"); case .simple: store.t("notificationModeSimple"); case .milestones: store.t("notificationModeMilestones") } }
}

private struct LandscapeRow: View {
    let icon: String
    let title: String
    let value: String?
    var last = false
    var external = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(OWCDesign.secondary).frame(width: 17)
            Text(title).font(.system(size: 15)).lineLimit(1)
            Spacer(minLength: 6)
            if let value { Text(value).font(.system(size: 15)).foregroundStyle(OWCDesign.secondary).lineLimit(1).minimumScaleFactor(0.7) }
            Image(systemName: external ? "arrow.up.right" : "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(OWCDesign.tertiary)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .overlay(alignment: .bottomTrailing) { if !last { Rectangle().fill(OWCDesign.separator).frame(height: 0.5).padding(.leading, 41) } }
    }
}

private struct LandscapeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 20)
            .frame(height: 44)
            .background(OWCDesign.card.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .shadow(color: .black.opacity(0.07), radius: 4, y: 2)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
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
            Image(systemName: store.quickThemeIcon)
                .frame(width: 38, height: 38)
                .background(OWCDesign.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
    .padding(.horizontal, sidebarVisible ? 40 : 26)
    .padding(.top, 22)
}
