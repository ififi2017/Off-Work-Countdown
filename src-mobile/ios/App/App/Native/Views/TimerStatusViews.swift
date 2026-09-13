import SwiftUI
import UIKit

struct LunchBreakDesignView: View {
    @Environment(SceneState.self) private var scene
    // No semantic style goes this large; scale the display size instead.
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 56
    let shifts: ShiftSessionStore
    let snapshot: NativeShiftSnapshot
    let now: Date
    @Binding var showShare: Bool
    @Binding var showOvertime: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var timelineExpanded: Bool {
        scene.timelineExpanded(for: snapshot, at: now, session: shifts.session)
    }

    private var summaryTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }
    /// Where the timeline starts, i.e. how much room the content above it took.
    @State private var timelineTop: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            OWCAppHeader(preferences: shifts.preferences, text: shifts.text, showsFocus: true)

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            Label(shifts.text.t("lunchInProgress"), systemImage: "cup.and.saucer")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(OWCDesign.secondary)
                                .padding(.horizontal, 12)
                                .frame(height: 26)
                                .background(OWCDesign.control)
                                .clipShape(Capsule())

                            Text(shifts.text.formatDuration(breakRemainingMs))
                                .font(.system(size: countdownSize, weight: .bold).monospacedDigit())
                                .tracking(-1.4)
                                .foregroundStyle(OWCDesign.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.62)
                                .environment(\.layoutDirection, .leftToRight)
                                .owcCountdownTextTransition(milliseconds: breakRemainingMs)
                                .padding(.top, 16)

                            Text(shifts.text.t("pausedUntil", values: ["time": shifts.text.formatTime(breakEnd)]))
                                .font(.subheadline)
                                .foregroundStyle(OWCDesign.secondary)
                                .padding(.top, 8)
                        }
                        .padding(.horizontal, OWCDesign.contentInset)
                        .padding(.top, 26)

                        OWCProgressMeter(progress: snapshot.progress, label: shifts.text.t("progress"), paused: true)
                            .padding(.horizontal, OWCDesign.contentInset)
                            .padding(.top, 7)

                        // Expanding the list hides what sits above it, exactly
                        // as the running screen does — the countdown and the
                        // meter are what the user came for, and they were being
                        // pushed off to make room for rows. This state had the
                        // list but never got the hiding.
                        if !timelineExpanded {
                            VStack(alignment: .leading, spacing: 0) {
                                OWCGroupCard {
                                    OWCRow(icon: "clock", title: shifts.text.t("lunchBackAt"), isLast: !shifts.session.presentationSalaryEnabled) {
                                        Text(shifts.text.formatTime(breakEnd))
                                            .font(.body.weight(.semibold).monospacedDigit())
                                    }
                                    if shifts.session.presentationSalaryEnabled {
                                        OWCRow(icon: "banknote", title: shifts.text.t("moneyEarned"), isLast: true) {
                                            Text(shifts.text.moneyText(earned))
                                                .font(.body.weight(.semibold).monospacedDigit())
                                        }
                                    }
                                }
                                .padding(.horizontal, OWCDesign.pageInset)
                                .padding(.top, 30)

                                detailNote(shifts.text.t("lunchPauseNote"))
                            }
                            .transition(summaryTransition)
                        }

                        UpcomingTimelineView(
                            shifts: shifts,
                            snapshot: snapshot,
                            now: now,
                            isExpanded: scene.timelineExpandedBinding(for: snapshot, at: now, session: shifts.session),
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
                shifts: shifts,
                snapshot: snapshot,
                now: now,
                showShare: $showShare,
                showOvertime: $showOvertime
            )
        }
    }

    private var breakEnd: Date { snapshot.activeBreakEndDate ?? now }
    private var breakRemainingMs: Double { snapshot.heroRemainingMs(at: now) }
    private var earned: Double? { snapshot.earnedSoFar }
}
struct OvertimeDesignView: View {
    @Environment(SceneState.self) private var scene
    // No semantic style goes this large; scale the display size instead.
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 56
    let shifts: ShiftSessionStore
    let snapshot: NativeShiftSnapshot
    let now: Date
    @Binding var showShare: Bool
    @Binding var showOvertime: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var timelineExpanded: Bool {
        scene.timelineExpanded(for: snapshot, at: now, session: shifts.session)
    }

    private var summaryTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }
    /// Where the timeline starts, i.e. how much room the content above it took.
    @State private var timelineTop: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            OWCAppHeader(preferences: shifts.preferences, text: shifts.text, showsFocus: true)

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            TimerPhasePill(
                                title: shifts.text.t(
                                    "overtimeUntil",
                                    values: ["time": shifts.text.formatTime(snapshot.overtimeEndDate ?? snapshot.endDate)]
                                ),
                                systemImage: "clock.fill",
                                tint: OWCDesign.orangeDeep,
                                fill: OWCDesign.orange.opacity(0.12)
                            )

                            Text(shifts.text.formatDuration(snapshot.remainingMs))
                                .font(.system(size: countdownSize, weight: .bold).monospacedDigit())
                                .tracking(-1.4)
                                .lineLimit(1)
                                .minimumScaleFactor(0.62)
                                .environment(\.layoutDirection, .leftToRight)
                                .owcCountdownTextTransition(milliseconds: snapshot.remainingMs)
                                .padding(.top, 16)

                            Text(shifts.text.t("overtimeTimeLeftCaption"))
                                .font(.subheadline)
                                .foregroundStyle(OWCDesign.secondary)
                                .padding(.top, 8)
                        }
                        .padding(.horizontal, OWCDesign.contentInset)
                        .padding(.top, 26)

                        OWCProgressMeter(progress: snapshot.progress, label: shifts.text.t("progress"), overtime: true)
                            .padding(.horizontal, OWCDesign.contentInset)
                            .padding(.top, 7)
                            .animation(.linear(duration: 0.9), value: snapshot.progress)

                        // Expanding the list hides what sits above it, exactly
                        // as the running screen does — the countdown and the
                        // meter are what the user came for, and they were being
                        // pushed off to make room for rows. This state had the
                        // list but never got the hiding.
                        if !timelineExpanded {
                            VStack(alignment: .leading, spacing: 0) {
                                OWCGroupCard {
                                    OWCRow(icon: "clock", title: shifts.text.t("shiftEnded"), isLast: !shifts.session.presentationSalaryEnabled) {
                                        Text("\(shifts.text.formatTime(snapshot.plannedEndDate)) · \(shifts.text.t("timeAgo", values: ["time": shifts.text.formatRelativeDuration(now.timeIntervalSince(snapshot.plannedEndDate) * 1_000)]))")
                                            .font(.subheadline.monospacedDigit())
                                            .foregroundStyle(OWCDesign.secondary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.72)
                                    }
                                    if shifts.session.presentationSalaryEnabled {
                                        OWCRow(icon: "banknote", title: shifts.text.t("moneyEarned"), isLast: true) {
                                            Text(shifts.text.moneyText(earned))
                                                .font(.body.weight(.semibold).monospacedDigit())
                                        }
                                    }
                                }
                                .padding(.horizontal, OWCDesign.pageInset)
                                .padding(.top, 30)

                                detailNote(shifts.text.t("overtimeNoMultiplier"))
                            }
                            .transition(summaryTransition)
                        }

                        UpcomingTimelineView(
                            shifts: shifts,
                            snapshot: snapshot,
                            now: now,
                            isExpanded: scene.timelineExpandedBinding(for: snapshot, at: now, session: shifts.session),
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
                shifts: shifts,
                snapshot: snapshot,
                now: now,
                showShare: $showShare,
                showOvertime: $showOvertime
            )
        }
    }

    private var earned: Double? { snapshot.earnedSoFar }
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

struct UnscheduledTimerView: View {
    @Environment(SceneState.self) private var scene
    let shifts: ShiftSessionStore
    let now: Date
    var onOpenLunchSettings: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            CelebratingBrandMark(showsDepth: true, isActive: scene.selectedTab == .timer)
                .frame(width: 168, height: 168)
                .padding(.bottom, 26)
            Text(shifts.text.t("unscheduledTitle"))
                .font(.largeTitle.bold())
                .tracking(-0.85)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OWCDesign.contentInset)
            Text(shifts.text.t("unscheduledBody"))
                .font(.body)
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, 12)
            Text(
                "\(shifts.session.timeString(shifts.session.effectiveStartMinutes(at: now))) – "
                    + "\(shifts.session.timeString(shifts.session.effectiveEndMinutes(at: now)))"
            )
                .font(.title3.monospacedDigit())
                .foregroundStyle(OWCDesign.secondary)
                .padding(.top, 18)
                .environment(\.layoutDirection, .leftToRight)
            Spacer()
            ShiftStartButton(shifts: shifts, onOpenLunchSettings: onOpenLunchSettings)
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.bottom, 14)
        }
    }
}

struct RestDayDesignView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 56
    let shifts: ShiftSessionStore
    let snapshot: NativeShiftSnapshot
    let now: Date
    var onOpenLunchSettings: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            OWCContentSizedScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Label(shifts.text.t("widgetRestDay"), systemImage: "bed.double.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OWCDesign.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(OWCDesign.control, in: Capsule())
                        .padding(.top, 28)

                    Text(shifts.text.formatDuration(remainingMs))
                        .font(.system(size: countdownSize, weight: .bold).monospacedDigit())
                        .tracking(-1.4)
                        .foregroundStyle(OWCDesign.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .environment(\.layoutDirection, .leftToRight)
                        .owcCountdownTextTransition(milliseconds: remainingMs)
                        .padding(.top, 16)

                    OWCProgressMeter(
                        progress: shifts.session.countdownToClockInProgress(snapshot: snapshot),
                        label: shifts.text.t("progress")
                    )
                    .padding(.horizontal, OWCDesign.contentInset)
                    .padding(.top, 7)
                    .opacity(0.72)

                    VStack(alignment: .leading, spacing: 0) {
                        OWCSectionHeader(title: shifts.text.t("summaryEstimateNote"))
                        OWCGroupCard {
                            OWCRow(icon: "calendar", title: shifts.text.t("summaryThisWeek")) {
                                Text(summaryText(weekSummary))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(OWCDesign.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.66)
                            }
                            OWCRow(icon: "calendar.badge.clock", title: shifts.text.t("summaryThisYear"), isLast: true) {
                                Text(summaryText(yearSummary))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(OWCDesign.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.66)
                            }
                        }
                    }
                    .padding(.horizontal, OWCDesign.pageInset)
                    .padding(.top, 22)

                    RestDayUpcomingView(shifts: shifts, snapshot: snapshot, now: now)
                        .padding(.horizontal, OWCDesign.pageInset)
                        .padding(.top, 22)
                }
                .padding(.bottom, 10)
            }

            ShiftStartButton(shifts: shifts, onOpenLunchSettings: onOpenLunchSettings)
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.bottom, 14)
        }
    }

    private var remainingMs: Double { shifts.session.countdownToClockInMs(snapshot: snapshot, at: now) }
    private var weekSummary: NativePeriodSummary? { shifts.session.periodSummary("week", asOf: now, snapshot: snapshot) }
    private var yearSummary: NativePeriodSummary? { shifts.session.periodSummary("year", asOf: now, snapshot: snapshot) }

    private func summaryText(_ summary: NativePeriodSummary?) -> String {
        guard let summary else { return "—" }
        guard shifts.session.presentationSalaryEnabled else {
            return "\(shifts.text.formatDays(summary.days)) · \(shifts.text.formatHours(summary.hours))"
        }
        let money = shifts.text.moneyText(summary.earnings)
        return "\(shifts.text.formatDays(summary.days)) · \(shifts.text.formatHours(summary.hours)) · \(money)"
    }
}

struct CompletedShiftDesignView: View {
    let shifts: ShiftSessionStore
    let snapshot: NativeShiftSnapshot
    let now: Date
    @Binding var showShare: Bool
    @Binding var showOvertime: Bool
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var celebrationBurst = 0
    @State private var celebrationHaptics: Task<Void, Never>?
    var body: some View {
        GeometryReader { proxy in
            // Landscape has roughly 300 pt of height to work with, and the
            // portrait stack does not fit in it — the actions fell off the
            // bottom. Two columns instead: the instrument on the left, the
            // figures and actions on the right.
            if verticalSizeClass == .compact {
                HStack(spacing: 20) {
                    hero
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(spacing: 0) {
                                if let note = shifts.session.earlyClockOffNote(for: snapshot) {
                                    EarlyClockOffBanner(shifts: shifts, note: note)
                                        .padding(.bottom, 16)
                                }
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
                ScrollView {
                    VStack(spacing: 0) {
                        hero
                        if let note = shifts.session.earlyClockOffNote(for: snapshot) {
                            EarlyClockOffBanner(shifts: shifts, note: note)
                                .padding(.horizontal, OWCDesign.pageInset)
                                .padding(.top, 16)
                        }
                        todayInFullSection.padding(.top, 30)
                        earningsCard.padding(.top, 16)
                        actions.padding(.top, 24)
                    }
                    .frame(maxWidth: 560)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }
        .overlay { OWCConfettiOverlay(burst: celebrationBurst) }
        .onAppear { celebrateIfNeeded() }
        .onChange(of: celebrationToken) { celebrateIfNeeded() }
        .onDisappear { celebrationHaptics?.cancel() }
    }

    private var hero: some View {
        VStack(spacing: 0) {
            Button { celebrate() } label: {
                Text(shifts.text.t("offWorkToday"))
                    .font(.largeTitle.bold())
                    .tracking(-0.85)
                    .foregroundStyle(OWCDesign.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .buttonStyle(.plain)
            .accessibilityHint(shifts.text.t("replayCelebration"))
            .padding(.top, 34)

            if let nextDate = snapshot.nextShiftStartDate {
                Text(shifts.text.t("nextShiftIn", values: [
                    "time": shifts.text.formatRelativeDuration(nextDate.timeIntervalSince(now) * 1_000),
                ]))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OWCDesign.contentInset)
                    .padding(.top, 12)
            }

        }
    }

    /// Header, then the estimate caveat, then the numbers it qualifies — the
    /// note reads as a condition on the section rather than a footnote nobody
    /// reaches.
    private var todayInFullSection: some View {
        let lunch = shifts.takenLunchWindow(for: finishedSnapshot, at: now)
        let showsWeek = shifts.session.followsSchedule(at: now)
        return VStack(alignment: .leading, spacing: 0) {
            OWCSectionHeader(title: shifts.text.t("todayInFull"))
            OWCGroupCard {
                OWCRow(icon: "clock", title: shifts.text.t("worked"), isLast: lunch == nil && !showsWeek) {
                    Text(shifts.text.formatDuration(workedDurationMs, includeSeconds: false))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(OWCDesign.secondary)
                }
                if let lunch {
                    OWCRow(
                        icon: "cup.and.saucer",
                        title: shifts.text.t("lunchTaken"),
                        isLast: !showsWeek
                    ) {
                        Text("\(shifts.text.formatTime(lunch.start)) – \(shifts.text.formatTime(lunch.end))")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(OWCDesign.secondary)
                    }
                }
                if showsWeek {
                    OWCRow(icon: "calendar", title: shifts.text.t("summaryThisWeek"), isLast: true) {
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
        if shifts.session.followsSchedule(at: now) {
            OWCSectionHeader(title: shifts.text.t("summaryEstimateNote"))
        }
        OWCGroupCard {
            if shifts.session.presentationSalaryEnabled {
                OWCRow(icon: "banknote", title: shifts.text.t("moneyEarned")) {
                    Text(shifts.text.moneyText(earned))
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
            Button { showOvertime = true } label: {
                Text(shifts.text.t("overtime"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .buttonStyle(OWCSecondaryButtonStyle())

            Button { showShare = true } label: {
                Label(shifts.text.t("shareButton"), systemImage: "square.and.arrow.up")
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
        shifts.noteCountdownCompleted(endAtMs: celebrationToken)
        // Early clock-off is keyed on the moment they pressed, not the planned
        // end — otherwise undoing and finishing the shift later would skip the
        // real celebration, and clocking off early would never fire one.
        // Changing today's hours produces a new planned end, so it plays again.
        guard shifts.lastCelebratedEndAtMs != celebrationToken else { return }
        shifts.markCelebrated(endAtMs: celebrationToken)
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

    private var endedEarly: Bool { shifts.session.isEndedEarly(snapshot) }
    private var celebrationToken: Double {
        endedEarly ? (shifts.session.earlyOffAtMs ?? snapshot.plannedEndAtMs) : snapshot.endAtMs
    }
    private var finishedSnapshot: NativeShiftSnapshot { shifts.session.clockOffSnapshot(for: snapshot) }
    private var workedDurationMs: Double { endedEarly ? finishedSnapshot.elapsedMs : snapshot.durationMs }
    private var earned: Double? { finishedSnapshot.earnedSoFar }
    private var nextShiftRange: String {
        guard let start = snapshot.nextShiftStartDate, let end = snapshot.nextShiftEndDate else { return "—" }
        return "\(shifts.text.formatTime(start)) – \(shifts.text.formatTime(end))"
    }
    private var nextShiftDayLabel: String {
        guard let start = snapshot.nextShiftStartDate else { return shifts.text.t("nextShiftLabelShort") }
        return shifts.text.relativeDayLabel(for: start, from: now)
    }
    private var weekSummary: String {
        let asOf: Date
        if endedEarly, let earlyOffAtMs = shifts.session.earlyOffAtMs {
            asOf = Date(timeIntervalSince1970: earlyOffAtMs / 1_000)
        } else { asOf = now }
        guard let summary = shifts.session.periodSummary("week", asOf: asOf, snapshot: finishedSnapshot) else { return "—" }
        guard shifts.session.presentationSalaryEnabled else {
            return "\(shifts.text.formatDays(summary.days)) · \(shifts.text.formatHours(summary.hours))"
        }
        let money = shifts.text.moneyText(summary.earnings)
        return "\(shifts.text.formatDays(summary.days)) · \(shifts.text.formatHours(summary.hours)) · \(money)"
    }
}
