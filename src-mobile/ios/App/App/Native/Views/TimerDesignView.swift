import SwiftUI
import UIKit

/// The timer surface follows Claude Design direction 1a literally. Business
/// values still come from CountdownRules; this file only owns presentation.
struct TimerDesignView: View {
    @ObservedObject var store: OffWorkStore
    let wide: Bool
    let onOpenSettings: ((AppRoute?) -> Void)?

    @State private var showShare = false
    @State private var showOvertime = false

    init(
        store: OffWorkStore,
        wide: Bool,
        onOpenSettings: ((AppRoute?) -> Void)? = nil
    ) {
        self.store = store
        self.wide = wide
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            Group {
                if !store.countdownStarted {
                    ShiftSetupDesignView(store: store, onOpenSettings: openSettings)
                } else if let snapshot = store.snapshot(at: timeline.date) {
                    if !snapshot.isWorkday && !store.forceToday {
                        RestDayDesignView(
                            store: store,
                            snapshot: snapshot,
                            onOpenSettings: openSettings
                        )
                    } else if snapshot.remainingMs <= 0 {
                        CompletedShiftDesignView(
                            store: store,
                            snapshot: snapshot,
                            showShare: $showShare
                        )
                    } else if snapshot.activeBreakEndAtMs != nil {
                        LunchBreakDesignView(
                            store: store,
                            snapshot: snapshot,
                            now: timeline.date,
                            showShare: $showShare,
                            showOvertime: $showOvertime
                        )
                    } else if snapshot.overtimeEndAtMs != nil,
                              snapshot.plannedEndAtMs <= timeline.date.timeIntervalSince1970 * 1_000 {
                        OvertimeDesignView(
                            store: store,
                            snapshot: snapshot,
                            now: timeline.date,
                            showShare: $showShare,
                            showOvertime: $showOvertime
                        )
                    } else {
                        RunningTimerDesignView(
                            store: store,
                            snapshot: snapshot,
                            now: timeline.date,
                            showShare: $showShare,
                            showOvertime: $showOvertime
                        )
                    }
                } else {
                    rulesError
                }
            }
            .frame(maxWidth: wide ? 680 : 402)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OWCDesign.page)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShare) {
            ShareComposerView(store: store)
                .presentationDetents([.large])
                .presentationCornerRadius(26)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showOvertime) {
            OvertimeSheet(store: store)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
#if DEBUG
            let defaults = UserDefaults.standard
            if defaults.bool(forKey: "ios.native.qaShareComposer") {
                defaults.removeObject(forKey: "ios.native.qaShareComposer")
                showShare = true
            }
#endif
        }
    }

    private func openSettings(_ route: AppRoute?) {
        if let onOpenSettings {
            onOpenSettings(route)
        } else {
            store.selectedTab = .settings
            store.presentedRoute = route
        }
    }

    private var rulesError: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
            Text(store.lastRulesError ?? "Countdown rules unavailable")
                .font(.system(size: 15))
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.center)
            Button(store.t("return")) { store.stopCountdown() }
                .buttonStyle(OWCPrimaryButtonStyle())
        }
        .padding(20)
    }
}

private struct ShiftSetupDesignView: View {
    @ObservedObject var store: OffWorkStore
    let onOpenSettings: (AppRoute?) -> Void
    @State private var timeField: SetupTimeField?
    @State private var nonWorkdayArmed = false
    @State private var armResetTask: Task<Void, Never>?
    @State private var showInvalidLunch = false

    var body: some View {
        VStack(spacing: 0) {
            OWCAppHeader(store: store)

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 12)

            VStack(spacing: 0) {
                Text("\(store.timeString(store.startMinutes)) — \(store.timeString(store.endMinutes))")
                    .font(.system(size: 40, weight: .bold).monospacedDigit())
                    .tracking(-1.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .environment(\.layoutDirection, .leftToRight)
                Text(shiftDescription)
                    .font(.system(size: 15))
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.top, 9)
            }
            .padding(.horizontal, OWCDesign.contentInset)
            .padding(.top, 22)

            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: store.t("shiftSection"))

                OWCGroupCard {
                    OWCCompactTimeRow(title: store.t("startTime"), minutes: store.startMinutes) {
                        timeField = .start
                    }
                    OWCCompactTimeRow(title: store.t("endTime"), minutes: store.endMinutes) {
                        timeField = .end
                    }
                    Button { onOpenSettings(.schedule) } label: {
                        OWCRow(icon: "calendar.badge.clock", title: store.t("workSchedule"), isLast: true) {
                            OWCDetailAccessory(text: scheduleLabel)
                        }
                    }
                    .buttonStyle(OWCRowButtonStyle())
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 26)

            OWCGroupCard {
                Button { onOpenSettings(.salary) } label: {
                    OWCRow(icon: "banknote", title: store.t("salarySettings")) {
                        OWCDetailAccessory(text: store.t("configureSalary"))
                    }
                }
                .buttonStyle(OWCRowButtonStyle())

                Button { onOpenSettings(.notifications) } label: {
                    OWCRow(icon: "bell.badge", title: store.t("offWorkReminder")) {
                        OWCDetailAccessory(text: notificationModeLabel)
                    }
                }
                .buttonStyle(OWCRowButtonStyle())

                Button { onOpenSettings(.lunch) } label: {
                    OWCRow(icon: "cup.and.saucer", title: store.t("lunchBreak")) {
                        OWCDetailAccessory(text: lunchLabel)
                    }
                }
                .buttonStyle(OWCRowButtonStyle())

                Button { onOpenSettings(.health) } label: {
                    OWCRow(icon: "figure.walk", title: store.t("microBreakReminder"), isLast: true) {
                        OWCDetailAccessory(text: healthLabel)
                    }
                }
                .buttonStyle(OWCRowButtonStyle())
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 26)

                        Spacer(minLength: 12)
                    }
                    .frame(minHeight: proxy.size.height)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }

            Button {
                startTapped()
            } label: {
                Label(
                    nonWorkdayArmed ? store.t("nonWorkdayTapAgain") : store.t("startCountdown"),
                    systemImage: nonWorkdayArmed ? "exclamationmark.triangle.fill" : "play.fill"
                )
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            }
            .buttonStyle(OWCPrimaryButtonStyle(color: nonWorkdayArmed ? OWCDesign.orangeDeep : OWCDesign.accent))
            .disabled(startDisabled)
            .opacity(startDisabled ? 0.45 : 1)
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.bottom, 14)
        }
        .sensoryFeedback(.warning, trigger: nonWorkdayArmed)
        .sheet(item: $timeField) { field in
            OWCSetupTimePickerSheet(
                store: store,
                title: store.t(field == .start ? "startTime" : "endTime"),
                minutes: Binding(
                    get: { field == .start ? store.startMinutes : store.endMinutes },
                    set: { value in
                        if field == .start { store.startMinutes = value }
                        else { store.endMinutes = value }
                    }
                )
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .alert(store.t("invalidLunchTitle"), isPresented: $showInvalidLunch) {
            Button(store.t("return"), role: .cancel) {}
            Button(store.t("goToLunchSettings")) { onOpenSettings(.lunch) }
        } message: {
            Text(store.t("invalidLunchMessage"))
        }
        .onDisappear { armResetTask?.cancel() }
    }

    private var shiftDescription: String {
        var wallMinutes = store.endMinutes - store.startMinutes
        if wallMinutes <= 0 { wallMinutes += 24 * 60 }
        let shift = store.formatDuration(Double(wallMinutes) * 60_000, includeSeconds: false)
        let lunch = store.lunchEnabled
            ? store.formatDuration(Double(store.lunchDurationMinutes) * 60_000, includeSeconds: false)
            : store.t("disabledShort")
        return "\(shift) · \(lunch) · \(workdaysDescription)"
    }

    private var workdaysDescription: String {
        if store.scheduleMode == .off { return store.t("scheduleOff") }
        if store.scheduleMode != .classic { return scheduleLabel }
        let pairs = Array(zip([1, 2, 3, 4, 5, 6, 0], store.weekdayLabels()))
            .filter { store.workdays.contains($0.0) }
            .map(\.1)
        guard let first = pairs.first else { return store.t("disabledShort") }
        return pairs.count > 1 ? "\(first) – \(pairs.last ?? first)" : first
    }

    private var scheduleLabel: String {
        switch store.scheduleMode {
        case .classic: store.t("scheduleClassic")
        case .alternating: store.t("scheduleAlternating")
        case .rotation: store.t("scheduleRotation")
        case .off: store.t("scheduleOff")
        }
    }

    private var startDisabled: Bool {
        store.startMinutes == store.endMinutes || (store.scheduleMode == .classic && store.workdays.isEmpty)
    }

    private func startTapped() {
        guard store.isLunchInsideShift else {
            showInvalidLunch = true
            return
        }
        let isNonWorkday = store.scheduleMode != .off && store.snapshot()?.isWorkday == false
        if isNonWorkday, !nonWorkdayArmed {
            withAnimation(.snappy(duration: 0.25)) { nonWorkdayArmed = true }
            armResetTask?.cancel()
            armResetTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                withAnimation(.snappy(duration: 0.25)) { nonWorkdayArmed = false }
            }
            return
        }
        armResetTask?.cancel()
        withAnimation(.snappy(duration: 0.32)) { store.startCountdown(force: isNonWorkday) }
    }

    private var notificationModeLabel: String {
        switch store.notificationMode {
        case .off: store.t("notificationModeOff")
        case .simple: store.t("notificationModeSimple")
        case .milestones: store.t("notificationModeMilestones")
        }
    }

    private var lunchLabel: String {
        guard store.lunchEnabled else { return store.t("disabledShort") }
        return "\(store.timeString(store.lunchStartMinutes)) · \(store.formatDuration(Double(store.lunchDurationMinutes) * 60_000, includeSeconds: false))"
    }

    private var healthLabel: String {
        store.microBreakEnabled
            ? store.t("minutesShort", values: ["count": "\(store.microBreakIntervalMinutes)"])
            : store.t("disabledShort")
    }
}

private enum SetupTimeField: String, Identifiable {
    case start, end
    var id: String { rawValue }
}

private struct OWCCompactTimeRow: View {
    let title: String
    let minutes: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 17)).tracking(-0.43)
                Spacer()
                Text(String(format: "%02d:%02d", minutes / 60, minutes % 60))
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(OWCDesign.primary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(OWCDesign.control)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
        .buttonStyle(OWCRowButtonStyle())
        .padding(.horizontal, 16)
        .frame(height: 56)
        .overlay(alignment: .bottomTrailing) {
            Rectangle()
                .fill(OWCDesign.separator)
                .frame(height: 0.5)
                .padding(.leading, 16)
        }
    }

}

struct OWCSetupTimePickerSheet: View {
    @ObservedObject var store: OffWorkStore
    let title: String
    @Binding var minutes: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(
                title,
                selection: Binding(
                    get: { store.dateForMinutes(minutes) },
                    set: { minutes = store.minutes(from: $0) }
                ),
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.t("done")) { dismiss() }
                }
            }
        }
    }
}

private struct RunningTimerDesignView: View {
    @ObservedObject var store: OffWorkStore
    let snapshot: NativeShiftSnapshot
    let now: Date
    @Binding var showShare: Bool
    @Binding var showOvertime: Bool

    private var onBreak: Bool { snapshot.activeBreakEndAtMs != nil }
    private var overtime: Bool {
        snapshot.overtimeEndAtMs != nil && snapshot.plannedEndAtMs <= now.timeIntervalSince1970 * 1_000
    }

    var body: some View {
        VStack(spacing: 0) {
            OWCAppHeader(store: store)

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 12)

                        VStack(spacing: 0) {
                            if overtime {
                                Text(store.t("overtimeTitle"))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(OWCDesign.orangeDeep)
                                    .padding(.bottom, 8)
                            }
                            Text(store.formatDuration(displayRemaining))
                                .font(.system(size: 56, weight: .bold).monospacedDigit())
                                .tracking(-1.4)
                                .lineLimit(1)
                                .minimumScaleFactor(0.62)
                                .environment(\.layoutDirection, .leftToRight)
                                .contentTransition(.numericText(countsDown: true))
                            Text(caption)
                                .font(.system(size: 15))
                                .foregroundStyle(OWCDesign.secondary)
                                .padding(.top, 8)
                        }
                        .padding(.horizontal, OWCDesign.contentInset)
                        .padding(.top, overtime ? 18 : 26)
                        .animation(.linear(duration: 0.16), value: Int(displayRemaining / 1_000))

                        OWCProgressMeter(progress: snapshot.progress, overtime: overtime, paused: onBreak)
                            .padding(.horizontal, OWCDesign.contentInset)
                            .padding(.top, 7)
                            .animation(.linear(duration: 0.9), value: snapshot.progress)

                        summaryCard
                            .padding(.horizontal, OWCDesign.pageInset)
                            .padding(.top, 30)

                        if store.scheduleMode != .off {
                            Text(store.t("summaryEstimateNote"))
                                .font(.system(size: 13))
                                .foregroundStyle(OWCDesign.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 36)
                                .padding(.top, 8)
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            OWCSectionHeader(title: store.t("comingUp"))
                            upcomingCard
                        }
                        .padding(.horizontal, OWCDesign.pageInset)
                        .padding(.top, 16)

                        Spacer(minLength: 12)
                    }
                    .frame(minHeight: proxy.size.height)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }

            HStack(spacing: 10) {
                Button {
                    withAnimation(.snappy(duration: 0.3)) { store.stopCountdown() }
                } label: {
                    Label(store.t("return"), systemImage: "arrow.left")
                }
                .buttonStyle(OWCSecondaryButtonStyle())

                Button { showOvertime = true } label: {
                    Text(overtime ? store.t("adjustOvertime") : store.t("overtime"))
                }
                .buttonStyle(OWCSecondaryButtonStyle())

                Button { showShare = true } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 19, weight: .medium))
                        .frame(width: 50, height: 50)
                }
                .foregroundStyle(OWCDesign.primary)
                .background(OWCDesign.control)
                .clipShape(RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous))
                .buttonStyle(.plain)
                .accessibilityLabel(store.t("shareButton"))
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.bottom, 14)
        }
    }

    private var caption: String {
        if onBreak { return store.t("lunchInProgress") }
        if overtime { return store.t("overtimeTimeLeftCaption") }
        return store.t("timeLeftCaption")
    }

    private var displayRemaining: Double {
        guard onBreak else { return snapshot.remainingMs }
        return max(0, (snapshot.activeBreakEndAtMs ?? now.timeIntervalSince1970 * 1_000) - now.timeIntervalSince1970 * 1_000)
    }

    private var summaryCard: some View {
        OWCGroupCard {
            OWCRow(icon: "clock", title: store.t("todaysShift"), isLast: !store.salaryEnabled && store.scheduleMode == .off) {
                Text("\(store.formatTime(snapshot.startDate)) – \(store.formatTime(snapshot.endDate))")
                    .font(.system(size: 17).monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
                    .environment(\.layoutDirection, .leftToRight)
            }
            if store.salaryEnabled {
            OWCRow(icon: "banknote", title: store.t("moneyEarned"), isLast: store.scheduleMode == .off) {
                HStack(spacing: 8) {
                    Text(store.hideEarnings ? "••••" : store.formatMoney(earned))
                        .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    Button { store.hideEarnings.toggle() } label: {
                        Image(systemName: store.hideEarnings ? "eye" : "eye.slash")
                            .font(.system(size: 17))
                            .foregroundStyle(OWCDesign.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            }
            if store.scheduleMode != .off {
            OWCRow(icon: "calendar", title: store.t("summaryThisWeek")) {
                Text(summaryText(weekSummary))
                    .font(.system(size: 15).monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
            }
            OWCRow(icon: "calendar.badge.clock", title: store.t("summaryThisYear"), isLast: true) {
                Text(summaryText(yearSummary))
                    .font(.system(size: 15).monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
            }
            }
        }
    }

    private var upcomingCard: some View {
        OWCGroupCard {
            OWCRow(icon: "figure.walk", title: store.t("microBreakReminder")) {
                Text(nextHealthLabel)
                    .font(.system(size: 17).monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(1)
            }
            OWCRow(icon: "rectangle.inset.filled", title: store.t("liveActivity"), isLast: true) {
                Text(liveActivityLabel)
                    .font(.system(size: 17).monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var nextHealthLabel: String {
        guard store.microBreakEnabled,
              let reminders = try? CountdownRules.shared.reminders(
                  input: store.rulesInput(at: now),
                  reminderInputs: store.reminderInputs()
              ),
              let reminder = reminders.first(where: { $0.kind == "microBreak" && $0.atMs > now.timeIntervalSince1970 * 1_000 })
        else { return store.t("disabledShort") }
        let date = Date(timeIntervalSince1970: reminder.atMs / 1_000)
        let minutes = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        return "\(store.formatTime(date)) · \(store.t("minutesShort", values: ["count": "\(minutes)"]))"
    }

    private var liveActivityLabel: String {
        guard store.liveActivityEnabled else { return store.t("disabledShort") }
        let start = Date(timeIntervalSince1970: snapshot.plannedEndAtMs / 1_000)
            .addingTimeInterval(Double(-store.liveActivityLeadMinutes * 60))
        return store.formatTime(start)
    }

    private var earned: Double? { snapshot.dailySalary.map { $0 * snapshot.payRatio } }

    private var weekSummary: NativePeriodSummary? { store.periodSummary("week", asOf: now, snapshot: snapshot) }
    private var yearSummary: NativePeriodSummary? { store.periodSummary("year", asOf: now, snapshot: snapshot) }

    private func summaryText(_ summary: NativePeriodSummary?) -> String {
        guard let summary else { return "—" }
        guard store.salaryEnabled else {
            return "\(store.formatDays(summary.days)) · \(store.formatHours(summary.hours))"
        }
        let money = store.hideEarnings ? "••••" : store.formatMoney(summary.earnings)
        return "\(store.formatDays(summary.days)) · \(store.formatHours(summary.hours)) · \(money)"
    }
}

private struct LunchBreakDesignView: View {
    @ObservedObject var store: OffWorkStore
    let snapshot: NativeShiftSnapshot
    let now: Date
    @Binding var showShare: Bool
    @Binding var showOvertime: Bool

    var body: some View {
        VStack(spacing: 0) {
            OWCAppHeader(store: store)

            VStack(spacing: 0) {
                Label(store.t("lunchInProgress"), systemImage: "cup.and.saucer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OWCDesign.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(OWCDesign.control)
                    .clipShape(Capsule())

                Text(store.formatDuration(snapshot.remainingMs))
                    .font(.system(size: 56, weight: .bold).monospacedDigit())
                    .tracking(-1.4)
                    .foregroundStyle(OWCDesign.primary.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .environment(\.layoutDirection, .leftToRight)
                    .contentTransition(.numericText(countsDown: false))
                    .padding(.top, 16)

                Text(store.t("pausedUntil", values: ["time": store.formatTime(breakEnd)]))
                    .font(.system(size: 15))
                    .foregroundStyle(OWCDesign.secondary)
                    .padding(.top, 8)
            }
            .padding(.horizontal, OWCDesign.contentInset)
            .padding(.top, 26)

            OWCProgressMeter(progress: snapshot.progress, paused: true)
                .padding(.horizontal, OWCDesign.contentInset)
                .padding(.top, 7)

            OWCGroupCard {
                OWCRow(icon: "clock", title: store.t("lunchBackAt"), isLast: !store.salaryEnabled) {
                    Text(store.formatTime(breakEnd))
                        .font(.system(size: 17, weight: .semibold).monospacedDigit())
                }
                if store.salaryEnabled {
                    OWCRow(icon: "banknote", title: store.t("moneyEarned"), isLast: true) {
                    Text(store.hideEarnings ? "••••" : store.formatMoney(earned))
                        .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 30)

            detailNote(store.t("lunchPauseNote"))

            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: store.t("comingUp"))
                OWCGroupCard {
                    OWCRow(icon: "figure.walk", title: store.t("microBreakReminder")) {
                        Text(store.microBreakEnabled
                             ? store.t("pausedUntil", values: ["time": store.formatTime(breakEnd)])
                             : store.t("disabledShort"))
                            .font(.system(size: 16).monospacedDigit())
                            .foregroundStyle(OWCDesign.secondary)
                    }
                    OWCRow(icon: "rectangle.inset.filled", title: store.t("liveActivity"), isLast: true) {
                        Text(liveActivityLabel)
                            .font(.system(size: 17).monospacedDigit())
                            .foregroundStyle(OWCDesign.secondary)
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 16)

            Spacer(minLength: 8)
            TimerActionBar(
                store: store,
                overtimeActive: false,
                showShare: $showShare,
                showOvertime: $showOvertime
            )
        }
    }

    private var breakEnd: Date { snapshot.activeBreakEndDate ?? now }
    private var earned: Double? { snapshot.dailySalary.map { $0 * snapshot.payRatio } }
    private var liveActivityLabel: String {
        guard store.liveActivityEnabled else { return store.t("disabledShort") }
        return store.formatTime(snapshot.plannedEndDate.addingTimeInterval(Double(-store.liveActivityLeadMinutes * 60)))
    }
}

private struct OvertimeDesignView: View {
    @ObservedObject var store: OffWorkStore
    let snapshot: NativeShiftSnapshot
    let now: Date
    @Binding var showShare: Bool
    @Binding var showOvertime: Bool

    var body: some View {
        VStack(spacing: 0) {
            OWCAppHeader(store: store)

            VStack(spacing: 0) {
                Text(store.t("overtimeUntil", values: ["time": store.formatTime(snapshot.overtimeEndDate ?? snapshot.endDate)]))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OWCDesign.orangeDeep)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(OWCDesign.orange.opacity(0.12))
                    .clipShape(Capsule())

                Text(store.formatDuration(snapshot.remainingMs))
                    .font(.system(size: 56, weight: .bold).monospacedDigit())
                    .tracking(-1.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .environment(\.layoutDirection, .leftToRight)
                    .contentTransition(.numericText(countsDown: true))
                    .padding(.top, 16)

                Text(store.t("overtimeTimeLeftCaption"))
                    .font(.system(size: 15))
                    .foregroundStyle(OWCDesign.secondary)
                    .padding(.top, 8)
            }
            .padding(.horizontal, OWCDesign.contentInset)
            .padding(.top, 26)

            OWCProgressMeter(progress: snapshot.progress, overtime: true)
                .padding(.horizontal, OWCDesign.contentInset)
                .padding(.top, 7)
                .animation(.linear(duration: 0.9), value: snapshot.progress)

            OWCGroupCard {
                OWCRow(icon: "clock", title: store.t("shiftEnded"), isLast: !store.salaryEnabled) {
                    Text("\(store.formatTime(snapshot.plannedEndDate)) · \(store.t("timeAgo", values: ["time": store.formatRelativeDuration(now.timeIntervalSince(snapshot.plannedEndDate) * 1_000)]))")
                        .font(.system(size: 15).monospacedDigit())
                        .foregroundStyle(OWCDesign.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                if store.salaryEnabled {
                    OWCRow(icon: "banknote", title: store.t("moneyEarned"), isLast: true) {
                    Text(store.hideEarnings ? "••••" : store.formatMoney(earned))
                        .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 30)

            detailNote(store.t("overtimeNoMultiplier"))

            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: store.t("comingUp"))
                OWCGroupCard {
                    OWCRow(icon: "figure.walk", title: store.t("microBreakReminder")) {
                        Text(nextHealthLabel)
                            .font(.system(size: 16).monospacedDigit())
                            .foregroundStyle(OWCDesign.secondary)
                    }
                    OWCRow(icon: "rectangle.inset.filled", title: store.t("liveActivity"), isLast: true) {
                        Text(store.liveActivityEnabled
                             ? store.t("overtimeUntil", values: ["time": store.formatTime(snapshot.overtimeEndDate ?? snapshot.endDate)])
                             : store.t("disabledShort"))
                            .font(.system(size: 15).monospacedDigit())
                            .foregroundStyle(store.liveActivityEnabled ? OWCDesign.orangeDeep : OWCDesign.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 16)

            Spacer(minLength: 8)
            TimerActionBar(
                store: store,
                overtimeActive: true,
                showShare: $showShare,
                showOvertime: $showOvertime
            )
        }
    }

    private var earned: Double? { snapshot.dailySalary.map { $0 * snapshot.payRatio } }
    private var nextHealthLabel: String {
        guard store.microBreakEnabled,
              let reminders = try? CountdownRules.shared.reminders(
                  input: store.rulesInput(at: now),
                  reminderInputs: store.reminderInputs()
              ),
              let reminder = reminders.first(where: { $0.kind == "microBreak" && $0.atMs > now.timeIntervalSince1970 * 1_000 })
        else { return store.t("disabledShort") }
        let date = Date(timeIntervalSince1970: reminder.atMs / 1_000)
        let minutes = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        return "\(store.formatTime(date)) · \(store.t("inTime", values: ["time": store.t("minutesShort", values: ["count": "\(minutes)"]) ]))"
    }
}

private struct TimerActionBar: View {
    @ObservedObject var store: OffWorkStore
    let overtimeActive: Bool
    @Binding var showShare: Bool
    @Binding var showOvertime: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button { withAnimation(.snappy(duration: 0.3)) { store.stopCountdown() } } label: {
                Label(store.t("return"), systemImage: "arrow.left")
            }
            .buttonStyle(OWCSecondaryButtonStyle())

            Button { showOvertime = true } label: {
                Text(overtimeActive ? store.t("adjustOvertime") : store.t("overtime"))
            }
            .buttonStyle(OWCSecondaryButtonStyle())

            Button { showShare = true } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 50, height: 50)
            }
            .foregroundStyle(OWCDesign.primary)
            .background(OWCDesign.control)
            .clipShape(RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous))
            .buttonStyle(.plain)
            .accessibilityLabel(store.t("shareButton"))
        }
        .padding(.horizontal, OWCDesign.pageInset)
        .padding(.bottom, 14)
    }
}

private func detailNote(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 13))
        .foregroundStyle(OWCDesign.secondary)
        .lineSpacing(2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 36)
        .padding(.top, 8)
}

private struct RestDayDesignView: View {
    @ObservedObject var store: OffWorkStore
    let snapshot: NativeShiftSnapshot
    let onOpenSettings: (AppRoute?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            OWCAppHeader(store: store)

            Text(store.t("restDay"))
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.85)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OWCDesign.contentInset)
                .padding(.top, 34)

            Text(store.t("notAWorkdayBody", values: ["day": store.weekdayName(for: .now)]))
                .font(.system(size: 17))
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, 12)

            OWCGroupCard {
                OWCRow(icon: "clock", title: store.t("nextShiftLabelShort")) {
                    Text(nextShiftLabel)
                        .font(.system(size: 17).monospacedDigit())
                        .foregroundStyle(OWCDesign.secondary)
                }
                Button { onOpenSettings(nil) } label: {
                    OWCRow(icon: "calendar", title: store.t("workdaysLabel"), isLast: true) {
                        OWCDetailAccessory(text: workdaysDescription)
                    }
                }
                .buttonStyle(OWCRowButtonStyle())
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 34)

            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: store.t("summaryThisWeek"))
                OWCGroupCard {
                    WeekdayStatusStrip(store: store)

                    OWCRow(icon: "clock", title: store.t("workedSoFar"), isLast: !store.salaryEnabled) {
                        Text(weeklyDuration)
                            .font(.system(size: 15).monospacedDigit())
                            .foregroundStyle(OWCDesign.secondary)
                    }
                    if store.salaryEnabled {
                    OWCRow(icon: "banknote", title: store.t("earnedThisWeek"), isLast: true) {
                        Text(store.hideEarnings ? "••••" : store.formatMoney(weeklyEarnings))
                            .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    }
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 18)

            detailNote(store.t("summaryEstimateNote"))
            Spacer(minLength: 8)

            Button {
                withAnimation(.snappy(duration: 0.3)) { store.startCountdown(force: true) }
            } label: { Label(store.t("startCountdown"), systemImage: "play.fill") }
            .buttonStyle(OWCPrimaryButtonStyle())
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.bottom, 14)
        }
    }

    private var nextShiftLabel: String {
        guard let date = snapshot.nextShiftStartDate else { return "—" }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(store.locale))
    }

    private var workdaysDescription: String {
        let labels = Array(zip([1, 2, 3, 4, 5, 6, 0], store.weekdayLabels()))
            .filter { store.workdays.contains($0.0) }
            .map(\.1)
        guard let first = labels.first else { return store.t("disabledShort") }
        return labels.count > 1 ? "\(first) – \(labels.last ?? first)" : first
    }

    private var weeklyDuration: String {
        guard let summary = weeklySummary else { return "—" }
        return "\(store.formatDays(summary.days)) · \(store.formatHours(summary.hours))"
    }

    private var weeklySummary: NativePeriodSummary? { store.periodSummary("week", asOf: .now, snapshot: snapshot) }
    private var weeklyEarnings: Double? { weeklySummary?.earnings }
}

private struct CompletedShiftDesignView: View {
    @ObservedObject var store: OffWorkStore
    let snapshot: NativeShiftSnapshot
    @Binding var showShare: Bool
    @State private var showCelebration = false

    var body: some View {
        VStack(spacing: 0) {
            OWCAppHeader(store: store)

            Text(store.t("offWorkToday"))
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.85)
                .padding(.top, 34)

            if let nextDate = snapshot.nextShiftStartDate {
                Text(store.t("nextShiftIn", values: ["time": store.formatRelativeDuration(nextDate.timeIntervalSinceNow * 1_000)]))
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, OWCDesign.contentInset)
                    .padding(.top, 12)
            }

            OWCProgressMeter(progress: 100)
                .padding(.horizontal, OWCDesign.contentInset)
                .padding(.top, 3)

            OWCGroupCard {
                if store.salaryEnabled {
                OWCRow(icon: "banknote", title: store.t("moneyEarned")) {
                    Text(store.hideEarnings ? "••••" : store.formatMoney(earned))
                        .font(.system(size: 17, weight: .semibold).monospacedDigit())
                }
                }
                OWCRow(icon: "calendar", title: nextShiftDayLabel, isLast: true) {
                    Text(nextShiftRange)
                        .font(.system(size: 17).monospacedDigit())
                        .foregroundStyle(OWCDesign.secondary)
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 30)

            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: store.t("todayInFull"))
                OWCGroupCard {
                    OWCRow(icon: "clock", title: store.t("worked")) {
                        Text(store.formatDuration(snapshot.durationMs, includeSeconds: false))
                            .font(.system(size: 17).monospacedDigit())
                            .foregroundStyle(OWCDesign.secondary)
                    }
                    if store.lunchEnabled {
                        OWCRow(icon: "cup.and.saucer", title: store.t("lunchTaken")) {
                            Text("\(store.timeString(store.lunchStartMinutes)) – \(store.timeString(store.lunchStartMinutes + store.lunchDurationMinutes))")
                                .font(.system(size: 17).monospacedDigit())
                                .foregroundStyle(OWCDesign.secondary)
                        }
                    }
                    if store.scheduleMode != .off {
                    OWCRow(icon: "calendar", title: store.t("summaryThisWeek"), isLast: true) {
                        Text(weekSummary)
                            .font(.system(size: 15).monospacedDigit())
                            .foregroundStyle(OWCDesign.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 18)

            if store.scheduleMode != .off { detailNote(store.t("summaryEstimateNote")) }
            Spacer(minLength: 8)

            HStack(spacing: 10) {
                Button {
                    withAnimation(.snappy(duration: 0.3)) { store.stopCountdown() }
                } label: {
                    Label(store.t("return"), systemImage: "arrow.left")
                }
                .buttonStyle(OWCSecondaryButtonStyle())

                Button { showShare = true } label: {
                    Label(store.t("shareButton"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(OWCSecondaryButtonStyle())
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.bottom, 14)
        }
        .overlay { OWCConfettiOverlay(isActive: showCelebration).allowsHitTesting(false) }
        .onAppear {
            showCelebration = true
            playCelebrationHaptics()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { showCelebration = false }
        }
        .sensoryFeedback(.success, trigger: showCelebration)
    }

    private func playCelebrationHaptics() {
        let notification = UINotificationFeedbackGenerator()
        notification.prepare()
        notification.notificationOccurred(.success)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(130))
            let impact = UIImpactFeedbackGenerator(style: .rigid)
            impact.prepare()
            impact.impactOccurred(intensity: 0.82)
        }
    }

    private var earned: Double? { snapshot.dailySalary.map { $0 * snapshot.payRatio } }
    private var nextShiftRange: String {
        guard let start = snapshot.nextShiftStartDate, let end = snapshot.nextShiftEndDate else { return "—" }
        return "\(store.formatTime(start)) – \(store.formatTime(end))"
    }
    private var nextShiftDayLabel: String {
        guard let start = snapshot.nextShiftStartDate else { return store.t("nextShiftLabelShort") }
        return store.relativeDayLabel(for: start)
    }
    private var weekSummary: String {
        guard let summary = store.periodSummary("week", asOf: .now, snapshot: snapshot) else { return "—" }
        guard store.salaryEnabled else {
            return "\(store.formatDays(summary.days)) · \(store.formatHours(summary.hours))"
        }
        let money = store.hideEarnings ? "••••" : store.formatMoney(summary.earnings)
        return "\(store.formatDays(summary.days)) · \(store.formatHours(summary.hours)) · \(money)"
    }
}

private struct WeekdayStatusStrip: View {
    @ObservedObject var store: OffWorkStore

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(zip([1, 2, 3, 4, 5, 6, 0], store.weekdayLabels())), id: \.0) { day, label in
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .foregroundStyle(store.workdays.contains(day) ? Color(uiColor: .systemBackground) : OWCDesign.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(store.workdays.contains(day) ? OWCDesign.primary : OWCDesign.control)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottomTrailing) {
            Rectangle().fill(OWCDesign.separator).frame(height: 0.5).padding(.leading, 16)
        }
    }
}
