import SwiftUI
import UIKit

struct LunchBreakDesignView: View {
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
struct OvertimeDesignView: View {
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

struct RestDayDesignView: View {
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

struct CompletedShiftDesignView: View {
    @ObservedObject var store: OffWorkStore
    let snapshot: NativeShiftSnapshot
    @Binding var showShare: Bool
    @State private var celebrationBurst = 0
    @State private var celebrationHaptics: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            // Landscape has roughly 300 pt of height to work with, and the
            // portrait stack does not fit in it — the actions fell off the
            // bottom. Two columns instead: the instrument on the left, the
            // figures and actions on the right.
            if proxy.size.width > proxy.size.height {
                HStack(spacing: 20) {
                    hero
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(spacing: 0) {
                                todayInFullSection
                                earningsCard.padding(.top, 16)
                            }
                            .padding(.bottom, 8)
                        }
                        .scrollIndicators(.hidden)
                        actions
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            } else {
                VStack(spacing: 0) {
                    OWCAppHeader(store: store)
                    hero
                    todayInFullSection.padding(.top, 26)
                    earningsCard.padding(.top, 16)
                    Spacer(minLength: 8)
                    actions
                }
            }
        }
        .overlay { OWCConfettiOverlay(burst: celebrationBurst) }
        .onAppear { celebrate() }
        .onDisappear { celebrationHaptics?.cancel() }
    }

    private var hero: some View {
        VStack(spacing: 0) {
            Button { celebrate() } label: {
                Text(store.t("offWorkToday"))
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.85)
                    .foregroundStyle(OWCDesign.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .buttonStyle(.plain)
            .accessibilityHint(store.t("replayCelebration"))
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
        }
    }

    /// Header, then the estimate caveat, then the numbers it qualifies — the
    /// note reads as a condition on the section rather than a footnote nobody
    /// reaches.
    private var todayInFullSection: some View {
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
    }

    /// The estimate caveat sits at section-header level above the earnings card,
    /// because that card is the estimated one — "worked" and "this week" are
    /// read off the shift itself.
    private var earningsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
        if store.scheduleMode != .off {
            OWCSectionHeader(title: store.t("summaryEstimateNote"))
        }
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
        }
        .padding(.horizontal, OWCDesign.pageInset)
    }

    private var actions: some View {
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

    private func celebrate() {
        celebrationBurst += 1
        playCelebrationHaptics()
    }

    /// Paced against the five-second animation rather than fired at once: the
    /// cannons land as a heavy hit, the centre pop follows, then two soft taps
    /// under the falling curtain. Restrained on purpose — a buzz per beat over
    /// five seconds stops reading as celebration and starts reading as an alarm.
    private func playCelebrationHaptics() {
        let cannon = UIImpactFeedbackGenerator(style: .heavy)
        cannon.prepare()
        cannon.impactOccurred(intensity: 1.0)

        celebrationHaptics?.cancel()
        celebrationHaptics = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            let echo = UIImpactFeedbackGenerator(style: .light)
            echo.prepare()
            echo.impactOccurred(intensity: 0.72)

            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            let notification = UINotificationFeedbackGenerator()
            notification.prepare()
            notification.notificationOccurred(.success)

            for gap in [1_150, 1_500] {
                try? await Task.sleep(for: .milliseconds(gap))
                guard !Task.isCancelled else { return }
                let drift = UIImpactFeedbackGenerator(style: .soft)
                drift.prepare()
                drift.impactOccurred(intensity: 0.45)
            }
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
