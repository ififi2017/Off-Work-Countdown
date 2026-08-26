import SwiftUI
import UIKit

/// The timer surface follows Claude Design direction 1a literally. Business
/// values still come from CountdownRules; this file only owns presentation.
struct TimerDesignView: View {
    let store: OffWorkStore
    let wide: Bool
    let onOpenSettings: ((AppRoute?) -> Void)?
    let timelineDate: Date?
    let timelineActive: Bool
    let animatesPhaseChanges: Bool

    @State private var showShare = false
    @State private var showOvertime = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        store: OffWorkStore,
        wide: Bool,
        onOpenSettings: ((AppRoute?) -> Void)? = nil,
        timelineDate: Date? = nil,
        timelineActive: Bool = true,
        animatesPhaseChanges: Bool = true
    ) {
        self.store = store
        self.wide = wide
        self.onOpenSettings = onOpenSettings
        self.timelineDate = timelineDate
        self.timelineActive = timelineActive
        self.animatesPhaseChanges = animatesPhaseChanges
    }


    var body: some View {
        Group {
            if let timelineDate {
                timerContent(at: timelineDate)
            } else {
                TimelineView(.periodic(from: .now, by: timelineActive ? 1 : 86_400)) { timeline in
                    timerContent(at: timeline.date)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShare) {
            ShareComposerView(store: store)
                // One detent, fitted. The composer is a mood row, a card and
                // one button — a taller sheet has nothing to put in the extra
                // space, and .large left a screenful of empty sheet under the
                // card. The card sizes itself to whatever this leaves.
                .presentationDetents([.fraction(0.78)])
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

    @ViewBuilder
    private func timerContent(at date: Date) -> some View {
        let snapshot = store.countdownStarted ? store.snapshot(at: date) : nil
        let phase = TimerVisualPhase.resolve(
            countdownStarted: store.countdownStarted,
            snapshot: snapshot,
            forceToday: store.forceToday,
                endedEarly: snapshot.map(store.isEndedEarly) ?? false
        )

        Group {
            switch phase {
            case .setup:
                ShiftSetupView(store: store, onOpenSettings: openSettings)
            case .running:
                if let snapshot {
                    RunningTimerDesignView(
                        store: store,
                        snapshot: snapshot,
                        now: date,
                        showShare: $showShare,
                        showOvertime: $showOvertime
                    )
                }
            case .lunch:
                if let snapshot {
                    LunchBreakDesignView(
                        store: store,
                        snapshot: snapshot,
                        now: date,
                        showShare: $showShare,
                        showOvertime: $showOvertime
                    )
                }
            case .overtime:
                if let snapshot {
                    OvertimeDesignView(
                        store: store,
                        snapshot: snapshot,
                        now: date,
                        showShare: $showShare,
                        showOvertime: $showOvertime
                    )
                }
            case .completed:
                if let snapshot {
                    CompletedShiftDesignView(
                        store: store,
                        snapshot: snapshot,
                        showShare: $showShare,
                        showOvertime: $showOvertime
                    )
                }
            case .rest:
                if let snapshot {
                    RestDayDesignView(
                        store: store,
                        snapshot: snapshot,
                        onOpenSettings: openSettings
                    )
                }
            case .rulesError:
                rulesError
            }
        }
        .id(phase)
        .transition(phaseTransition)
        // See SettingsDesignView: phones fill their width, `pageInset` sets the
        // margin. The wide cap is for iPad, where a full-width countdown would
        // stretch past any comfortable measure. The one caller that renders this
        // phone layout in an iPad pane caps itself.
        .frame(maxWidth: wide ? 680 : .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OWCDesign.page)
        .animation(phaseAnimation, value: phase)
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
            store.selectedTab = .settings
            store.presentedRoute = route
        }
    }

    private var rulesError: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
            Text(store.t("countdownRulesUnavailable"))
                .font(.subheadline)
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.center)
            Button { store.requestClockOffEarly() } label: { ClockOffEarlyLabel(store: store) }
                .buttonStyle(OWCPrimaryButtonStyle())
        }
        .padding(20)
    }
}

private struct RunningTimerDesignView: View {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        VStack(spacing: 0) {
                            if overtime {
                                Text(store.t("overtimeTitle"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(OWCDesign.orangeDeep)
                                    .padding(.bottom, 8)
                            }
                            Text(store.formatDuration(displayRemaining))
                                .font(.system(size: countdownSize, weight: .bold).monospacedDigit())
                                .tracking(-1.4)
                                .lineLimit(1)
                                .minimumScaleFactor(0.62)
                                .environment(\.layoutDirection, .leftToRight)
                                .owcCountdownTextTransition(milliseconds: displayRemaining)
                            Text(caption)
                                .font(.subheadline)
                                .foregroundStyle(OWCDesign.secondary)
                                .padding(.top, 8)
                        }
                        .padding(.horizontal, OWCDesign.contentInset)
                        .padding(.top, overtime ? 12 : 16)

                        OWCProgressMeter(
                            progress: snapshot.progress,
                            label: store.t("progress"),
                            overtime: overtime,
                            paused: onBreak,
                            pending: beforeStart
                        )
                            .padding(.horizontal, OWCDesign.contentInset)
                            .padding(.top, 7)
                            .animation(.linear(duration: 0.9), value: snapshot.progress)

                        if !timelineExpanded {
                            VStack(alignment: .leading, spacing: 0) {
                                if store.scheduleMode != .off {
                                    OWCSectionHeader(title: store.t("summaryEstimateNote"))
                                }
                                summaryCard
                            }
                            .padding(.horizontal, OWCDesign.pageInset)
                            .padding(.top, 22)
                            .transition(summaryTransition)
                        }

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
                store: store,
                overtimeActive: overtime,
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
    private var beforeStart: Bool {
        now.timeIntervalSince1970 * 1_000 < snapshot.startAtMs
    }

    private var caption: String {
        if beforeStart { return store.t("nextShiftLabelShort") }
        if onBreak { return store.t("lunchInProgress") }
        if overtime { return store.t("overtimeTimeLeftCaption") }
        return store.t("timeLeftCaption")
    }

    private var displayRemaining: Double {
        if beforeStart {
            return max(0, snapshot.startAtMs - now.timeIntervalSince1970 * 1_000)
        }
        guard onBreak else { return snapshot.remainingMs }
        return max(0, (snapshot.activeBreakEndAtMs ?? now.timeIntervalSince1970 * 1_000) - now.timeIntervalSince1970 * 1_000)
    }

    private var summaryTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }

    private var summaryCard: some View {
        OWCGroupCard {
            OWCRow(icon: "clock", title: store.t("todaysShift"), isLast: !store.salaryEnabled && store.scheduleMode == .off) {
                Text("\(store.formatTime(snapshot.startDate)) – \(store.formatTime(snapshot.endDate))")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
                    .environment(\.layoutDirection, .leftToRight)
            }
            if store.salaryEnabled {
            OWCRow(icon: "banknote", title: store.t("moneyEarned"), isLast: store.scheduleMode == .off) {
                HStack(spacing: 8) {
                    Text(store.hideEarnings ? "••••" : store.formatMoney(earned))
                        .font(.body.weight(.semibold).monospacedDigit())
                    OWCEarningsVisibilityButton(store: store)
                }
            }
            }
            if store.scheduleMode != .off {
            OWCRow(icon: "calendar", title: store.t("summaryThisWeek")) {
                Text(summaryText(weekSummary))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
            }
            OWCRow(icon: "calendar.badge.clock", title: store.t("summaryThisYear"), isLast: true) {
                Text(summaryText(yearSummary))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
            }
            }
        }
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
