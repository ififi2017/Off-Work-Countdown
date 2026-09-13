import SwiftUI
import UIKit

/// The timer surface follows Claude Design direction 1a literally. Business
/// values still come from CountdownRules; this file only owns presentation.
struct TimerDesignView: View {
    @Environment(SceneState.self) private var scene
    @Bindable var shifts: ShiftSessionStore
    let wide: Bool
    let onShowSidebar: (() -> Void)?
    let onOpenSettings: ((AppRoute?) -> Void)?
    let timelineDate: Date?
    let timelineActive: Bool
    let animatesPhaseChanges: Bool
    let usesExternalRootToolbar: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    init(
        shifts: ShiftSessionStore,
        wide: Bool,
        onShowSidebar: (() -> Void)? = nil,
        onOpenSettings: ((AppRoute?) -> Void)? = nil,
        timelineDate: Date? = nil,
        timelineActive: Bool = true,
        animatesPhaseChanges: Bool = true,
        usesExternalRootToolbar: Bool = false
    ) {
        self.shifts = shifts
        self.wide = wide
        self.onShowSidebar = onShowSidebar
        self.onOpenSettings = onOpenSettings
        self.timelineDate = timelineDate
        self.timelineActive = timelineActive
        self.animatesPhaseChanges = animatesPhaseChanges
        self.usesExternalRootToolbar = usesExternalRootToolbar
    }


    var body: some View {
        Group {
            if let timelineDate {
                timerContent(at: timelineDate)
            } else if timelineActive,
                      shifts.session.visualPhase(at: shifts.session.timerDate(from: .now)).usesLiveTimeline {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    timerContent(at: shifts.session.timerDate(from: timeline.date))
                }
            } else {
                timerContent(at: shifts.session.timerDate(from: .now))
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(usesSystemRootToolbar || usesExternalRootToolbar ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            if usesSystemRootToolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    OWCEarningsVisibilityButton(preferences: shifts.preferences, text: shifts.text)
                    Button {
                        withAnimation(reduceMotion ? OWCMotion.reduced : OWCMotion.navigation) {
                            _ = shifts.preferences.toggleQuickTheme()
                        }
                    } label: {
                        Image(systemName: shifts.preferences.quickThemeIcon)
                    }
                    .accessibilityLabel(shifts.text.t("theme"))
                }
            }
        }
    }

    @ViewBuilder
    private func timerContent(at date: Date) -> some View {
        let _ = LaunchTrace.signposter.emitEvent("timerContentUpdate")
        let snapshot = shifts.session.shouldQuerySnapshot(at: date) ? shifts.session.snapshot(at: date) : nil
        let phase = shifts.session.visualPhase(snapshot: snapshot, at: date)

        VStack(spacing: 0) {
            if !usesSystemRootToolbar, !usesExternalRootToolbar {
                OWCAppHeader(preferences: shifts.preferences, text: shifts.text, showsFocus: true, onShowSidebar: onShowSidebar)
            }
            Group {
                switch phase {
                case .unscheduled:
                    UnscheduledTimerView(shifts: shifts, now: date) { openSettings(.lunch) }
                case .running, .lunch, .overtime, .clockIn:
                    if let snapshot {
                        RunningTimerDesignView(
                            shifts: shifts,
                            snapshot: snapshot,
                            now: date,
                            showShare: scene.timerSheetBinding(.share),
                            showOvertime: scene.timerSheetBinding(.overtime)
                        )
                    }
                case .completed:
                    if let snapshot {
                        CompletedShiftDesignView(
                            shifts: shifts,
                            snapshot: snapshot,
                            now: date,
                            showShare: scene.timerSheetBinding(.share),
                            showOvertime: scene.timerSheetBinding(.overtime)
                        )
                    }
                case .rest:
                    if let snapshot {
                        RestDayDesignView(
                            shifts: shifts,
                            snapshot: snapshot,
                            now: date
                        ) { openSettings(.lunch) }
                    }
                case .rulesError:
                    rulesError
                }
            }
            .id(phase.surfaceIdentity)
            .transition(phaseTransition)
            // Cap the instrument, while its header keeps the pane-wide alignment
            // used by Records and Settings in every timer phase.
            .frame(maxWidth: wide ? 680 : .infinity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(OWCDesign.page)
        .animation(phaseAnimation, value: phase)
    }

    private var usesSystemRootToolbar: Bool {
        !usesExternalRootToolbar
            && horizontalSizeClass == .compact
            && verticalSizeClass != .compact
    }

    private var phaseAnimation: Animation? {
        guard animatesPhaseChanges else { return nil }
        return reduceMotion ? OWCMotion.reduced : OWCMotion.phase
    }

    private var phaseTransition: AnyTransition {
        guard animatesPhaseChanges else { return .identity }
        return reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
    }

    private func openSettings(_ route: AppRoute?) {
        if let onOpenSettings {
            onOpenSettings(route)
        } else {
            scene.selectedTab = .settings
            scene.presentedRoute = route
        }
    }

    private var rulesError: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
            Text(shifts.text.t("rulesErrorBanner"))
                .font(.subheadline)
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.center)
            Button {
                openSettings(nil)
            } label: {
                Label(shifts.text.t("settings"), systemImage: "slider.horizontal.3")
            }
            .buttonStyle(OWCSecondaryButtonStyle())
        }
        .padding(20)
    }
}

private struct RunningTimerDesignView: View {
    @Environment(SceneState.self) private var scene
    // No semantic style goes this large; scale the display size instead.
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 56
    let shifts: ShiftSessionStore
    let snapshot: NativeShiftSnapshot
    let now: Date
    @Binding var showShare: Bool
    @Binding var showOvertime: Bool
    private var timelineExpanded: Bool {
        scene.timelineExpanded(for: snapshot, at: now, session: shifts.session)
    }
    /// Where the timeline starts, i.e. how much room the content above it took.
    @State private var timelineTop: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var beforeStart: Bool { snapshot.isBeforeStart(at: now) }
    private var onBreak: Bool { snapshot.isOnBreak }
    private var overtime: Bool { snapshot.isOvertimeActive(at: now) }

    var body: some View {
        VStack(spacing: 0) {
            if shifts.session.isForcedWorkday(snapshot) {
                ManualTimingBanner(shifts: shifts, now: now)
                    .padding(.horizontal, OWCDesign.pageInset)
                    .padding(.top, 8)
            } else if !beforeStart, let note = shifts.session.earlyClockInNote(at: now) {
                EarlyClockInBanner(shifts: shifts, note: note)
                    .padding(.horizontal, OWCDesign.pageInset)
                    .padding(.top, 8)
            }

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            if overtime {
                                TimerPhasePill(
                                    title: shifts.text.t(
                                        "overtimeUntil",
                                        values: ["time": shifts.text.formatTime(snapshot.overtimeEndDate ?? snapshot.endDate)]
                                    ),
                                    systemImage: "clock.fill",
                                    tint: OWCDesign.orangeDeep,
                                    fill: OWCDesign.orange.opacity(0.12)
                                )
                                .padding(.bottom, 8)
                            }
                            Text(shifts.text.formatDuration(displayRemaining))
                                .font(.system(size: countdownSize, weight: .bold).monospacedDigit())
                                .tracking(-1.4)
                                .lineLimit(1)
                                .minimumScaleFactor(0.62)
                                .environment(\.layoutDirection, .leftToRight)
                                .owcCountdownTextTransition(milliseconds: displayRemaining)
                            Group {
                                if onBreak {
                                    Label(caption, systemImage: "cup.and.saucer")
                                } else {
                                    Text(caption)
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(OWCDesign.secondary)
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, OWCDesign.contentInset)
                        .padding(.top, overtime ? 12 : 16)

                        OWCProgressMeter(
                            progress: meterProgress,
                            label: shifts.text.t("progress"),
                            overtime: overtime,
                            paused: onBreak
                        )
                            .padding(.horizontal, OWCDesign.contentInset)
                            .padding(.top, 7)
                            .animation(.linear(duration: 0.9), value: meterProgress)

                        if !timelineExpanded {
                            VStack(alignment: .leading, spacing: 0) {
                                if shifts.session.followsSchedule(at: now) {
                                    OWCSectionHeader(title: shifts.text.t("summaryEstimateNote"))
                                }
                                summaryCard
                            }
                            .padding(.horizontal, OWCDesign.pageInset)
                            .padding(.top, 22)
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
                            .padding(.top, timelineExpanded ? 20 : 14)

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

    /// Before the shift begins. The countdown is armed but nothing has started,
    /// and saying "8 hours left in today's shift" at 08:30 is simply not true —
    /// none of it has been worked yet. The screen counts to clock-in instead,
    /// and flips to the shift itself when the hour arrives, with nothing for the
    /// user to press either way.
    private var caption: String {
        if beforeStart { return shifts.text.t("nextShiftLabelShort") }
        if onBreak { return shifts.text.t("lunchInProgress") }
        if overtime { return shifts.text.t("overtimeTimeLeftCaption") }
        return shifts.text.t("timeLeftCaption")
    }

    private var displayRemaining: Double {
        beforeStart
            ? shifts.session.countdownToClockInMs(snapshot: snapshot, at: now)
            : snapshot.heroRemainingMs(at: now)
    }

    private var meterProgress: Double {
        beforeStart
            ? shifts.session.countdownToClockInProgress(snapshot: snapshot)
            : snapshot.progress
    }

    private var summaryTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }

    private var summaryCard: some View {
        OWCGroupCard {
            OWCRow(icon: "clock", title: shifts.text.t("todaysShift"), isLast: !shifts.session.presentationSalaryEnabled && !shifts.session.followsSchedule(at: now)) {
                Text("\(shifts.text.formatTime(snapshot.startDate)) – \(shifts.text.formatTime(snapshot.endDate))")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
                    .environment(\.layoutDirection, .leftToRight)
            }
            if shifts.session.presentationSalaryEnabled {
            OWCRow(icon: "banknote", title: shifts.text.t("moneyEarned"), isLast: !shifts.session.followsSchedule(at: now)) {
                Text(shifts.text.moneyText(earned))
                    .font(.body.weight(.semibold).monospacedDigit())
            }
            }
            if shifts.session.followsSchedule(at: now) {
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
    }

    private var earned: Double? { snapshot.earnedSoFar }

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
