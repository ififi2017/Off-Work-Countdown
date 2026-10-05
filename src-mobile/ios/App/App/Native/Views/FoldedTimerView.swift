import SwiftUI

/// System divisions describe the usable display, including the fold's margins.
/// Keep navigation and timing state outside this presentation-only adaptation.
enum AdaptiveDisplayLayout {
    static func hasHorizontalFold(in geometry: GeometryProxy) -> Bool {
        if #available(iOS 27.1, *) {
            return geometry.reservedRegions(kind: .division).contains {
                $0.isActive && $0.frame.width > $0.frame.height
            }
        }
        return false
    }

    static func showsContentColumns(width: CGFloat, hasHorizontalFold: Bool) -> Bool {
        width >= 620 && !hasHorizontalFold
    }
}

/// The primary panel stays above the active fold; the secondary panel remains
/// independently scrollable below it. The frames include system fold margins;
/// the layout also works inside the app's navigation split view.
@available(iOS 27.1, *)
struct FoldedTimerView: View {
    @Environment(SceneState.self) private var scene
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 76
    let shifts: ShiftSessionStore
    let isActive: Bool
    var sideBySide = false

    var body: some View {
        TimelineView(PausableSecondsSchedule(isPaused: !isActive)) { timeline in
            let now = shifts.session.timerDate(from: timeline.date)
            if let snapshot = shifts.session.snapshot(at: now) {
                let phase = shifts.session.visualPhase(snapshot: snapshot, at: now)
                GeometryReader { geometry in
                    let fold = geometry.reservedRegions(kind: .division).first {
                        $0.isActive && $0.frame.width > $0.frame.height
                    }
                    if sideBySide {
                        HStack(spacing: 0) {
                            hero(snapshot: snapshot, phase: phase, now: now)
                            upcoming(snapshot: snapshot, phase: phase, now: now)
                        }
                    } else {
                    FoldedPanelLayout(
                        upperEdge: fold.map { $0.frame.minY - $0.margins.top } ?? geometry.size.height / 2,
                        lowerEdge: fold.map { $0.frame.maxY + $0.margins.bottom } ?? geometry.size.height / 2
                    ) {
                        hero(snapshot: snapshot, phase: phase, now: now)
                        upcoming(snapshot: snapshot, phase: phase, now: now)
                    }
                    }
                }
            }
        }
        .background(OWCDesign.page)
    }

    private func hero(snapshot: NativeShiftSnapshot, phase: TimerVisualPhase, now: Date) -> some View {
        let beforeStart = phase == .clockIn || phase == .rest || phase == .completed
        let remaining = beforeStart
            ? shifts.session.countdownToClockInMs(snapshot: snapshot, at: now)
            : snapshot.heroRemainingMs(at: now)
        return GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 12) {
                    if sideBySide, shifts.session.isForcedWorkday(snapshot) {
                        ManualTimingBanner(shifts: shifts, now: now)
                    } else if sideBySide, !snapshot.isBeforeStart(at: now),
                              let note = shifts.session.earlyClockInNote(at: now) {
                        EarlyClockInBanner(shifts: shifts, note: note)
                    }
                    Text(now.formatted(.dateTime.month().day().weekday(.wide).locale(shifts.preferences.locale)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OWCDesign.secondary)
                    Text(shifts.text.formatDuration(remaining))
                        .font(.system(size: countdownSize, weight: .bold).monospacedDigit())
                        .tracking(-1.4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .environment(\.layoutDirection, .leftToRight)
                        .owcCountdownTextTransition(milliseconds: remaining)
                    Text(caption(phase: phase, snapshot: snapshot))
                        .font(.body)
                        .foregroundStyle(OWCDesign.secondary)
                        .multilineTextAlignment(.center)
                    OWCProgressMeter(
                        progress: beforeStart
                            ? shifts.session.countdownToClockInProgress(snapshot: snapshot) : snapshot.progress,
                        label: shifts.text.t("progress"),
                        overtime: phase == .overtime,
                        paused: phase == .lunch
                    )
                    if sideBySide, shifts.session.presentationSalaryEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(shifts.text.t("moneyEarned")).font(.footnote).foregroundStyle(OWCDesign.secondary)
                            Text(shifts.text.moneyText(snapshot.earnedSoFar)).font(.title3.weight(.semibold).monospacedDigit())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                        .background(OWCDesign.card, in: RoundedRectangle(cornerRadius: OWCDesign.cardRadius))
                    }
                    if sideBySide, shifts.session.followsSchedule(at: now) {
                        VStack(spacing: 10) {
                            periodSummary("week", title: "summaryThisWeek", snapshot: snapshot, now: now)
                            periodSummary("year", title: "summaryThisYear", snapshot: snapshot, now: now)
                        }
                        .padding(18)
                        .background(OWCDesign.card, in: RoundedRectangle(cornerRadius: OWCDesign.cardRadius))
                    }
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func upcoming(snapshot: NativeShiftSnapshot, phase: TimerVisualPhase, now: Date) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 20) {
                    if phase == .rest || phase == .completed {
                        RestDayUpcomingView(shifts: shifts, snapshot: snapshot, now: now)
                    } else {
                        UpcomingTimelineView(
                            shifts: shifts, snapshot: snapshot, now: now,
                            isExpanded: scene.timelineExpandedBinding(for: snapshot, at: now, session: shifts.session),
                            availableHeight: max(0, geometry.size.height - 120)
                        )
                    }
                    if phase == .rest || phase == .completed || phase == .unscheduled {
                        ShiftStartButton(shifts: shifts) { scene.timerPath.append(.lunch) }
                    } else {
                        TimerActionBar(
                            shifts: shifts, snapshot: snapshot, now: now,
                            showShare: scene.timerSheetBinding(.share),
                            showOvertime: scene.timerSheetBinding(.overtime)
                        )
                    }
                }
                .padding(24)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity, minHeight: sideBySide ? geometry.size.height : nil, alignment: sideBySide ? .center : .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func periodSummary(_ period: String, title: String, snapshot: NativeShiftSnapshot, now: Date) -> some View {
        let summary = shifts.session.periodSummary(period, asOf: now, snapshot: snapshot)
        return HStack {
            Text(shifts.text.t(title)).foregroundStyle(OWCDesign.secondary)
            Spacer(minLength: 8)
            if let summary {
                Text(shifts.text.formatDays(summary.days) + " · " +
                     (period == "year" && shifts.session.presentationSalaryEnabled
                      ? shifts.text.moneyText(summary.earnings) : shifts.text.formatHours(summary.hours)))
                    .monospacedDigit()
            } else { Text("—") }
        }
        .font(.footnote)
    }

    private func caption(phase: TimerVisualPhase, snapshot: NativeShiftSnapshot) -> String {
        switch phase {
        case .clockIn: shifts.text.t("nextShiftLabelShort")
        case .rest: shifts.text.t("widgetRestDay")
        case .completed: shifts.text.t("offWorkToday") + " · " + shifts.text.t("nextShiftLabelShort")
        case .lunch: shifts.text.t("pausedUntil", values: ["time": shifts.text.formatTime(snapshot.activeBreakEndDate ?? snapshot.endDate)])
        case .overtime: shifts.text.t("overtimeTimeLeftCaption")
        case .unscheduled: shifts.text.t("unscheduledTitle")
        case .running, .rulesError: shifts.text.t("timeLeftCaption")
        }
    }
}

private struct FoldedPanelLayout: Layout {
    let upperEdge: CGFloat
    let lowerEdge: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let topHeight = min(bounds.height, max(0, upperEdge))
        let bottomOrigin = min(bounds.height, max(topHeight, lowerEdge))
        subviews[0].place(at: bounds.origin, anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: topHeight))
        subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + bottomOrigin), anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: bounds.height - bottomOrigin))
    }
}
