import SwiftUI
import UIKit

struct LunchBreakDesignView: View {
    // No semantic style goes this large; scale the display size instead.
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 56
    let store: OffWorkStore
    let snapshot: NativeShiftSnapshot
    let now: Date
    @Binding var showShare: Bool
    @Binding var showOvertime: Bool
    private var timelineExpanded: Bool { store.timelineExpanded }
    /// Where the timeline starts, i.e. how much room the content above it took.
    @State private var timelineTop: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            OWCAppHeader(store: store)

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            Label(store.t("lunchInProgress"), systemImage: "cup.and.saucer")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(OWCDesign.secondary)
                                .padding(.horizontal, 12)
                                .frame(height: 26)
                                .background(OWCDesign.control)
                                .clipShape(Capsule())

                            Text(store.formatDuration(snapshot.remainingMs))
                                .font(.system(size: countdownSize, weight: .bold).monospacedDigit())
                                .tracking(-1.4)
                                .foregroundStyle(OWCDesign.primary.opacity(0.55))
                                .lineLimit(1)
                                .minimumScaleFactor(0.62)
                                .environment(\.layoutDirection, .leftToRight)
                                .owcCountdownTextTransition(milliseconds: snapshot.remainingMs)
                                .padding(.top, 16)

                            Text(store.t("pausedUntil", values: ["time": store.formatTime(breakEnd)]))
                                .font(.subheadline)
                                .foregroundStyle(OWCDesign.secondary)
                                .padding(.top, 8)
                        }
                        .padding(.horizontal, OWCDesign.contentInset)
                        .padding(.top, 26)

                        OWCProgressMeter(progress: snapshot.progress, label: store.t("progress"), paused: true)
                            .padding(.horizontal, OWCDesign.contentInset)
                            .padding(.top, 7)

                        OWCGroupCard {
                            OWCRow(icon: "clock", title: store.t("lunchBackAt"), isLast: !store.salaryEnabled) {
                                Text(store.formatTime(breakEnd))
                                    .font(.body.weight(.semibold).monospacedDigit())
                            }
                            if store.salaryEnabled {
                                OWCRow(icon: "banknote", title: store.t("moneyEarned"), isLast: true) {
                                    Text(store.hideEarnings ? "••••" : store.formatMoney(earned))
                                        .font(.body.weight(.semibold).monospacedDigit())
                                }
                            }
                        }
                        .padding(.horizontal, OWCDesign.pageInset)
                        .padding(.top, 30)

                        detailNote(store.t("lunchPauseNote"))

                        UpcomingTimelineView(
                            store: store,
                            snapshot: snapshot,
                            now: now,
                            isExpanded: store.timelineExpandedBinding,
                            availableHeight: proxy.size.height - timelineTop
                                - TimerContentSpace.bottomSlack
                        )
                            .onGeometryChange(for: CGFloat.self) { geometry in
                                geometry.frame(in: .named(TimerContentSpace.name)).minY
                            } action: { top in
                                // Expanding hides the summary card above, which
                                // would report a taller gap than the collapsed
                                // layout actually has. Keep the collapsed one.
                                guard !timelineExpanded else { return }
                                timelineTop = top
                            }
                            .padding(.horizontal, OWCDesign.pageInset)
                            .padding(.top, 16)

                        Spacer(minLength: 22)
                    }
                    .frame(minHeight: proxy.size.height, alignment: .top)
                    .coordinateSpace(.named(TimerContentSpace.name))
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }

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
}
struct OvertimeDesignView: View {
    // No semantic style goes this large; scale the display size instead.
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 56
    let store: OffWorkStore
    let snapshot: NativeShiftSnapshot
    let now: Date
    @Binding var showShare: Bool
    @Binding var showOvertime: Bool
    private var timelineExpanded: Bool { store.timelineExpanded }
    /// Where the timeline starts, i.e. how much room the content above it took.
    @State private var timelineTop: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            OWCAppHeader(store: store)

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            Text(store.t("overtimeUntil", values: ["time": store.formatTime(snapshot.overtimeEndDate ?? snapshot.endDate)]))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(OWCDesign.orangeDeep)
                                .padding(.horizontal, 12)
                                .frame(height: 26)
                                .background(OWCDesign.orange.opacity(0.12))
                                .clipShape(Capsule())

                            Text(store.formatDuration(snapshot.remainingMs))
                                .font(.system(size: countdownSize, weight: .bold).monospacedDigit())
                                .tracking(-1.4)
                                .lineLimit(1)
                                .minimumScaleFactor(0.62)
                                .environment(\.layoutDirection, .leftToRight)
                                .owcCountdownTextTransition(milliseconds: snapshot.remainingMs)
                                .padding(.top, 16)

                            Text(store.t("overtimeTimeLeftCaption"))
                                .font(.subheadline)
                                .foregroundStyle(OWCDesign.secondary)
                                .padding(.top, 8)
                        }
                        .padding(.horizontal, OWCDesign.contentInset)
                        .padding(.top, 26)

                        OWCProgressMeter(progress: snapshot.progress, label: store.t("progress"), overtime: true)
                            .padding(.horizontal, OWCDesign.contentInset)
                            .padding(.top, 7)
                            .animation(.linear(duration: 0.9), value: snapshot.progress)

                        OWCGroupCard {
                            OWCRow(icon: "clock", title: store.t("shiftEnded"), isLast: !store.salaryEnabled) {
                                Text("\(store.formatTime(snapshot.plannedEndDate)) · \(store.t("timeAgo", values: ["time": store.formatRelativeDuration(now.timeIntervalSince(snapshot.plannedEndDate) * 1_000)]))")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(OWCDesign.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                            }
                            if store.salaryEnabled {
                                OWCRow(icon: "banknote", title: store.t("moneyEarned"), isLast: true) {
                                    Text(store.hideEarnings ? "••••" : store.formatMoney(earned))
                                        .font(.body.weight(.semibold).monospacedDigit())
                                }
                            }
                        }
                        .padding(.horizontal, OWCDesign.pageInset)
                        .padding(.top, 30)

                        detailNote(store.t("overtimeNoMultiplier"))

                        UpcomingTimelineView(
                            store: store,
                            snapshot: snapshot,
                            now: now,
                            isExpanded: store.timelineExpandedBinding,
                            availableHeight: proxy.size.height - timelineTop
                                - TimerContentSpace.bottomSlack
                        )
                            .onGeometryChange(for: CGFloat.self) { geometry in
                                geometry.frame(in: .named(TimerContentSpace.name)).minY
                            } action: { top in
                                // Expanding hides the summary card above, which
                                // would report a taller gap than the collapsed
                                // layout actually has. Keep the collapsed one.
                                guard !timelineExpanded else { return }
                                timelineTop = top
                            }
                            .padding(.horizontal, OWCDesign.pageInset)
                            .padding(.top, 16)

                        Spacer(minLength: 22)
                    }
                    .frame(minHeight: proxy.size.height, alignment: .top)
                    .coordinateSpace(.named(TimerContentSpace.name))
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }

            TimerActionBar(
                store: store,
                overtimeActive: true,
                showShare: $showShare,
                showOvertime: $showOvertime
            )
        }
    }

    private var earned: Double? { snapshot.dailySalary.map { $0 * snapshot.payRatio } }
}

private func detailNote(_ text: String) -> some View {
    Text(text)
        .font(.footnote)
        .foregroundStyle(OWCDesign.secondary)
        .lineSpacing(2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 36)
        .padding(.top, 8)
}

struct RestDayDesignView: View {
    let store: OffWorkStore
    let snapshot: NativeShiftSnapshot
    let onOpenSettings: (AppRoute?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            OWCAppHeader(store: store)

            Text(store.t("restDay"))
                .font(.largeTitle.bold())
                .tracking(-0.85)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OWCDesign.contentInset)
                .padding(.top, 34)

            Text(store.t("notAWorkdayBody", values: ["day": store.weekdayName(for: .now)]))
                .font(.body)
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, 12)

            OWCGroupCard {
                OWCRow(icon: "clock", title: store.t("nextShiftLabelShort")) {
                    Text(nextShiftLabel)
                        .font(.body.monospacedDigit())
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
                OWCSectionHeader(title: store.t("summaryEstimateNote"))
                OWCGroupCard {
                    WeekdayStatusStrip(store: store)

                    OWCRow(icon: "clock", title: store.t("workedSoFar"), isLast: !store.salaryEnabled) {
                        Text(weeklyDuration)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(OWCDesign.secondary)
                    }
                    if store.salaryEnabled {
                    OWCRow(icon: "banknote", title: store.t("earnedThisWeek"), isLast: true) {
                        Text(store.hideEarnings ? "••••" : store.formatMoney(weeklyEarnings))
                            .font(.body.weight(.semibold).monospacedDigit())
                    }
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 18)

            Spacer(minLength: 8)

            Button {
                store.startCountdown(force: true)
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
    let store: OffWorkStore
    let snapshot: NativeShiftSnapshot
    @Binding var showShare: Bool
    @Binding var showOvertime: Bool
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
        .onAppear { celebrateIfNeeded() }
        .onDisappear { celebrationHaptics?.cancel() }
    }

    private var hero: some View {
        VStack(spacing: 0) {
            Button { celebrate() } label: {
                Text(store.t("offWorkToday"))
                    .font(.largeTitle.bold())
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
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, OWCDesign.contentInset)
                    .padding(.top, 12)
            }

            OWCProgressMeter(progress: 100, label: store.t("progress"))
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
                        .font(.body.monospacedDigit())
                        .foregroundStyle(OWCDesign.secondary)
                }
                if store.lunchEnabled {
                    OWCRow(icon: "cup.and.saucer", title: store.t("lunchTaken")) {
                        Text("\(store.timeString(store.lunchStartMinutes)) – \(store.timeString(store.lunchStartMinutes + store.lunchDurationMinutes))")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(OWCDesign.secondary)
                    }
                }
                if store.scheduleMode != .off {
                    OWCRow(icon: "calendar", title: store.t("summaryThisWeek"), isLast: true) {
                        Text(weekSummary)
                            .font(.subheadline.monospacedDigit())
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
                        .font(.body.weight(.semibold).monospacedDigit())
                }
            }
            OWCRow(icon: "calendar", title: nextShiftDayLabel, isLast: true) {
                Text(nextShiftRange)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
            }
        }
        }
        .padding(.horizontal, OWCDesign.pageInset)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                store.stopCountdown()
            } label: {
                Label(store.t("returnToSetup"), systemImage: "arrow.left")
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .buttonStyle(OWCSecondaryButtonStyle())

            Button { showOvertime = true } label: {
                Text(store.t("overtime"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .buttonStyle(OWCSecondaryButtonStyle())

            Button { showShare = true } label: {
                Label(store.t("shareButton"), systemImage: "square.and.arrow.up")
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
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

    private func celebrateIfNeeded() {
        guard store.lastCelebratedEndAtMs != snapshot.plannedEndAtMs else { return }
        store.markCelebrated(endAtMs: snapshot.plannedEndAtMs)
        celebrate()
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
    let store: OffWorkStore

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(zip([1, 2, 3, 4, 5, 6, 0], store.weekdayLabels())), id: \.0) { day, label in
                Text(label)
                    .font(.footnote.weight(.semibold))
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
