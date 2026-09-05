import SwiftUI
import UIKit

/// The timer surface follows Claude Design direction 1a literally. Business
/// values still come from CountdownRules; this file only owns presentation.
struct TimerDesignView: View {
    @Bindable var store: OffWorkStore
    let wide: Bool
    let onShowSidebar: (() -> Void)?
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
        onShowSidebar: (() -> Void)? = nil,
        onOpenSettings: ((AppRoute?) -> Void)? = nil,
        timelineDate: Date? = nil,
        timelineActive: Bool = true,
        animatesPhaseChanges: Bool = true
    ) {
        self.store = store
        self.wide = wide
        self.onShowSidebar = onShowSidebar
        self.onOpenSettings = onOpenSettings
        self.timelineDate = timelineDate
        self.timelineActive = timelineActive
        self.animatesPhaseChanges = animatesPhaseChanges
    }


    var body: some View {
        Group {
            if let timelineDate {
                timerContent(at: timelineDate)
            } else if timelineActive,
                      store.visualPhase(at: store.timerDate(from: .now)).usesLiveTimeline {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    timerContent(at: store.timerDate(from: timeline.date))
                }
            } else {
                timerContent(at: store.timerDate(from: .now))
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
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
        .sheet(isPresented: $store.presentAddFocus) {
            // The quick path from the timer root. It lands in the next empty
            // block by default, then opens the canvas on it — the change
            // should show up where it happened.
            FocusQuickCreateSheet(store: store) { _ in
                Task { @MainActor in
                    await Task.yield()
                    guard store.plus.isAuthorized else { return }
                    store.timerPath.append(.focus)
                }
            }
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
        let snapshot = store.shouldQuerySnapshot(at: date) ? store.snapshot(at: date) : nil
        let phase = store.visualPhase(snapshot: snapshot, at: date)

        VStack(spacing: 0) {
            OWCAppHeader(store: store, showsFocus: true, onShowSidebar: onShowSidebar)
            Group {
                switch phase {
                case .unscheduled:
                    UnscheduledTimerView(store: store, now: date) { openSettings(.lunch) }
                case .running, .lunch, .overtime, .clockIn:
                    if let snapshot {
                        RunningTimerDesignView(
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
                            now: date,
                            showShare: $showShare,
                            showOvertime: $showOvertime
                        )
                    }
                case .rest:
                    if let snapshot {
                        RestDayDesignView(
                            store: store,
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
            Text(store.t("rulesErrorBanner"))
                .font(.subheadline)
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.center)
            Button {
                openSettings(nil)
            } label: {
                Label(store.t("settings"), systemImage: "slider.horizontal.3")
            }
            .buttonStyle(OWCSecondaryButtonStyle())
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

    private var beforeStart: Bool { snapshot.isBeforeStart(at: now) }
    private var onBreak: Bool { snapshot.isOnBreak }
    private var overtime: Bool { snapshot.isOvertimeActive(at: now) }

    var body: some View {
        VStack(spacing: 0) {
            if store.isForcedWorkday(snapshot) {
                ManualTimingBanner(store: store)
                    .padding(.horizontal, OWCDesign.pageInset)
                    .padding(.top, 8)
            } else if !beforeStart, let note = store.earlyClockInNote(at: now) {
                EarlyClockInBanner(store: store, note: note)
                    .padding(.horizontal, OWCDesign.pageInset)
                    .padding(.top, 8)
            }

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            if overtime {
                                TimerPhasePill(
                                    title: store.t(
                                        "overtimeUntil",
                                        values: ["time": store.formatTime(snapshot.overtimeEndDate ?? snapshot.endDate)]
                                    ),
                                    systemImage: "clock.fill",
                                    tint: OWCDesign.orangeDeep,
                                    fill: OWCDesign.orange.opacity(0.12)
                                )
                                .padding(.bottom, 8)
                            }
                            Text(store.formatDuration(displayRemaining))
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
                            label: store.t("progress"),
                            overtime: overtime,
                            paused: onBreak
                        )
                            .padding(.horizontal, OWCDesign.contentInset)
                            .padding(.top, 7)
                            .animation(.linear(duration: 0.9), value: meterProgress)

                        if !timelineExpanded {
                            VStack(alignment: .leading, spacing: 0) {
                                if store.followsSchedule(at: now) {
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
        if beforeStart { return store.t("nextShiftLabelShort") }
        if onBreak { return store.t("lunchInProgress") }
        if overtime { return store.t("overtimeTimeLeftCaption") }
        return store.t("timeLeftCaption")
    }

    private var displayRemaining: Double {
        beforeStart
            ? store.countdownToClockInMs(snapshot: snapshot, at: now)
            : snapshot.heroRemainingMs(at: now)
    }

    private var meterProgress: Double {
        beforeStart
            ? store.countdownToClockInProgress(snapshot: snapshot)
            : snapshot.progress
    }

    private var summaryTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }

    private var summaryCard: some View {
        OWCGroupCard {
            OWCRow(icon: "clock", title: store.t("todaysShift"), isLast: !store.presentationSalaryEnabled && !store.followsSchedule(at: now)) {
                Text("\(store.formatTime(snapshot.startDate)) – \(store.formatTime(snapshot.endDate))")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
                    .environment(\.layoutDirection, .leftToRight)
            }
            if store.presentationSalaryEnabled {
            OWCRow(icon: "banknote", title: store.t("moneyEarned"), isLast: !store.followsSchedule(at: now)) {
                HStack(spacing: 8) {
                    Text(store.moneyText(earned))
                        .font(.body.weight(.semibold).monospacedDigit())
                    OWCEarningsVisibilityButton(store: store)
                }
            }
            }
            if store.followsSchedule(at: now) {
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

    private var earned: Double? { snapshot.earnedSoFar }

    private var weekSummary: NativePeriodSummary? { store.periodSummary("week", asOf: now, snapshot: snapshot) }
    private var yearSummary: NativePeriodSummary? { store.periodSummary("year", asOf: now, snapshot: snapshot) }

    private func summaryText(_ summary: NativePeriodSummary?) -> String {
        guard let summary else { return "—" }
        guard store.presentationSalaryEnabled else {
            return "\(store.formatDays(summary.days)) · \(store.formatHours(summary.hours))"
        }
        let money = store.moneyText(summary.earnings)
        return "\(store.formatDays(summary.days)) · \(store.formatHours(summary.hours)) · \(money)"
    }
}
