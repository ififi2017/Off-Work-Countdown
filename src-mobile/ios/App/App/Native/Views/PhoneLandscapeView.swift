import SwiftUI

struct PhoneLandscapeShellView: View {
    @ObservedObject var store: OffWorkStore

    var body: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
                OWCDesign.page.ignoresSafeArea()

                ZStack {
                    if store.selectedTab == .settings {
                        LandscapeSettingsView(store: store)
                            .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    } else {
                        LandscapeTimerView(store: store)
                            .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    }
                }
                // The system already supplies the landscape safe-area insets.
                // Reserve only the rail's real footprint; mirroring that inset
                // on the trailing side left a large, purposeless empty column.
                .frame(maxWidth: 760, maxHeight: .infinity)
                .padding(.leading, 72)
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.smooth(duration: 0.32), value: store.selectedTab)

                landscapeRail
            }
            // RootView already records URL/QA routes in presentedRoute. The
            // portrait settings stack observed it, but the dedicated landscape
            // stack did not, so a route opened while compact-height was active
            // silently stopped at the settings overview.
            .navigationDestination(item: $store.presentedRoute) { route in
                routeDestination(route)
            }
        }
        .background(OWCDesign.page)
    }

    @ViewBuilder
    private func routeDestination(_ route: AppRoute) -> some View {
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
            withAnimation(.smooth(duration: 0.32)) {
                store.selectedTab = tab
            }
        } label: {
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
        HStack(alignment: .center, spacing: 24) {
            VStack(spacing: 12) {
                Text(Date.now.formatted(.dateTime.month().day().weekday(.wide).locale(store.locale)))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OWCDesign.secondary)
                Text("\(store.timeString(store.startMinutes)) — \(store.timeString(store.endMinutes))")
                    .font(.system(size: 42, weight: .bold).monospacedDigit())
                    .tracking(-1.3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                OWCGroupCard {
                    landscapeTimeRow("sunrise", store.t("startTime"), store.startMinutes) { timeField = .start }
                    landscapeTimeRow("sunset", store.t("endTime"), store.endMinutes) { timeField = .end }
                }

                Button { startTapped() } label: {
                    Label(armed ? store.t("nonWorkdayTapAgain") : store.t("startCountdown"), systemImage: armed ? "exclamationmark.triangle.fill" : "play.fill")
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(OWCPrimaryButtonStyle(color: armed ? OWCDesign.orangeDeep : OWCDesign.accent))
                .disabled(startDisabled)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 10) {
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
            .frame(maxWidth: .infinity)
            .buttonStyle(OWCRowButtonStyle())
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

    private func landscapeTimeRow(_ icon: String, _ title: String, _ minutes: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            OWCRow(icon: icon, title: title) {
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
}

private struct LandscapeTimerView: View {
    @ObservedObject var store: OffWorkStore
    @State private var showShare = false
    @State private var showOvertime = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            ZStack {
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
                        Button {
                            withAnimation(.smooth(duration: 0.42)) {
                                store.stopCountdown()
                            }
                        } label: { Label(store.t("return"), systemImage: "arrow.left") }
                        Button { showOvertime = true } label: { Text(store.t("overtime")) }
                        Button { showShare = true } label: { Label(store.t("shareButton"), systemImage: "square.and.arrow.up") }
                    }
                    .buttonStyle(LandscapeButtonStyle())
                    .padding(.top, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .transition(.opacity.combined(with: .scale(scale: 0.975)))
                } else if !store.countdownStarted {
                    LandscapeSetupView(store: store)
                        .transition(.opacity.combined(with: .scale(scale: 0.975)))
                } else {
                    TimerDesignView(store: store, wide: true)
                        .transition(.opacity.combined(with: .scale(scale: 0.975)))
                }
            }
            .animation(.smooth(duration: 0.42), value: store.countdownStarted)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(store.t("settings"))
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.65)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(alignment: .center, spacing: 18) {
                    VStack(spacing: 10) {
                        compactSection(store.t("appearanceSection")) {
                            compactLink("display", store.t("theme"), themeLabel) { ThemeSettingsView(store: store) }
                            Link(destination: OWCSystemSettings.applicationURL) {
                                OWCRow(icon: "globe", title: store.t("chooselanguage"), isLast: true) {
                                    OWCDetailAccessory(
                                        text: store.localizer.languageName(for: store.languageCode),
                                        external: true
                                    )
                                }
                            }
                            .buttonStyle(OWCRowButtonStyle())
                        }
                        compactSection(store.t("aboutSection")) {
                            compactLink("info.circle", store.t("aboutProject"), nil) { AboutView(store: store) }
                            OWCRow(icon: "tag", title: store.t("version"), isLast: true) {
                                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                                    .font(.system(size: 17).monospacedDigit())
                                    .foregroundStyle(OWCDesign.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 10) {
                        compactSection(store.t("shiftSection")) {
                            compactLink("calendar.badge.clock", store.t("workSchedule"), scheduleLabel) { ScheduleSettingsView(store: store) }
                            compactLink("cup.and.saucer", store.t("lunchBreak"), lunchLabel) { LunchSettingsView(store: store) }
                            compactLink("figure.walk", store.t("microBreakReminder"), healthLabel) { HealthReminderSettingsView(store: store) }
                            compactLink("banknote", store.t("salarySettings"), store.salaryEnabled ? (store.salaryType == .monthly ? store.t("monthly") : store.t("daily")) : store.t("disabledShort"), last: true) { SalaryDesignView(store: store) }
                        }
                        compactSection(store.t("remindersSection")) {
                            compactLink("bell.badge", store.t("offWorkReminder"), notificationLabel, last: true) { NotificationDesignView(store: store) }
                        }
                    }
                    .frame(maxWidth: .infinity)
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

    private func compactSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased()).font(.system(size: 12)).foregroundStyle(OWCDesign.secondary).padding(.horizontal, 14).padding(.bottom, 5)
            VStack(spacing: 0) { content() }
                .frame(maxWidth: .infinity)
                .background(OWCDesign.card)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func compactLink<Destination: View>(_ icon: String, _ title: String, _ value: String?, last: Bool = false, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            OWCRow(icon: icon, title: title, isLast: last) {
                OWCDetailAccessory(text: value)
            }
        }
        .buttonStyle(OWCRowButtonStyle())
    }
    private var themeLabel: String { switch store.theme { case .auto: store.t("auto"); case .light: store.t("light"); case .dark: store.t("dark") } }
    private var scheduleLabel: String { switch store.scheduleMode { case .classic: store.t("scheduleClassic"); case .alternating: store.t("scheduleAlternating"); case .rotation: store.t("scheduleRotation"); case .off: store.t("scheduleOff") } }
    private var lunchLabel: String { store.lunchEnabled ? "\(store.timeString(store.lunchStartMinutes)) · \(store.formatRelativeDuration(Double(store.lunchDurationMinutes) * 60_000))" : store.t("disabledShort") }
    private var healthLabel: String { store.microBreakEnabled ? store.t("minutesShort", values: ["count": "\(store.microBreakIntervalMinutes)"]) : store.t("disabledShort") }
    private var notificationLabel: String { switch store.notificationMode { case .off: store.t("notificationModeOff"); case .simple: store.t("notificationModeSimple"); case .milestones: store.t("notificationModeMilestones") } }
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
