import SwiftUI

/// Scene-local immersive cover. Because this is an overlay rather than a new
/// UIWindow, sheets remain above it and the phone navigation tree stays alive.
struct PhoneLandscapeTimerOverlay: View {
    let shifts: ShiftSessionStore

    var body: some View {
        LandscapeTimerView(shifts: shifts, isActive: true, immersive: true)
            .frame(maxWidth: 760, maxHeight: .infinity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black, ignoresSafeAreaEdges: .all)
            // This cover shares a hosting window with the user's themed app.
            // Override only its subtree instead of changing the whole scene.
            .environment(\.colorScheme, .dark)
            .ignoresSafeArea()
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
    }
}

struct LandscapeTimerView: View {
    @Environment(SceneState.self) private var scene
    // No semantic style goes this large; scale the display size instead.
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 76
    let shifts: ShiftSessionStore
    let isActive: Bool
    var immersive = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion


    var body: some View {
        Group {
            if isActive,
               shifts.session.visualPhase(at: shifts.session.timerDate(from: .now)).usesLiveTimeline {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    landscapeContent(at: shifts.session.timerDate(from: timeline.date))
                }
            } else {
                landscapeContent(at: shifts.session.timerDate(from: .now))
            }
        }
    }

    @ViewBuilder
    private func landscapeContent(at date: Date) -> some View {
        let snapshot = shifts.session.shouldQuerySnapshot(at: date) ? shifts.session.snapshot(at: date) : nil
        let phase = shifts.session.visualPhase(snapshot: snapshot, at: date)

        ZStack {
            if phase.showsActiveTimer || immersive, let snapshot {
                let beforeStart = phase == .clockIn || phase == .rest || phase == .completed
                let onBreak = phase == .lunch
                let overtime = phase == .overtime
                let remaining = beforeStart
                    ? shifts.session.countdownToClockInMs(snapshot: snapshot, at: date)
                    : snapshot.heroRemainingMs(at: date)
                VStack(spacing: 0) {
                    if !immersive, !shifts.session.isForcedWorkday(snapshot),
                       !beforeStart,
                       let note = shifts.session.earlyClockInNote(at: date) {
                        EarlyClockInBanner(shifts: shifts, note: note)
                            .padding(.bottom, 8)
                    }

                    if shifts.session.isForcedWorkday(snapshot) || onBreak || overtime {
                        HStack(spacing: 8) {
                            if shifts.session.isForcedWorkday(snapshot), !immersive {
                                ManualTimingBanner(shifts: shifts, now: date, compact: true)
                            }
                            if onBreak {
                                Label(shifts.text.t("lunchInProgress"), systemImage: "cup.and.saucer")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(OWCDesign.secondary)
                                    .padding(.horizontal, 12)
                                    .frame(height: 26)
                                    .background(OWCDesign.control, in: Capsule())
                            } else if overtime {
                                TimerPhasePill(
                                    title: shifts.text.t(
                                        "overtimeUntil",
                                        values: ["time": shifts.text.formatTime(snapshot.overtimeEndDate ?? snapshot.endDate)]
                                    ),
                                    systemImage: "clock.fill",
                                    tint: OWCDesign.orangeDeep,
                                    fill: OWCDesign.orange.opacity(0.12)
                                )
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    Text(date.formatted(.dateTime.month().day().weekday(.wide).locale(shifts.preferences.locale)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OWCDesign.secondary)
                        .padding(.bottom, 4)
                    Text(shifts.text.formatDuration(remaining))
                        .font(.system(size: countdownSize, weight: .bold).monospacedDigit())
                        .tracking(-1.4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .environment(\.layoutDirection, .leftToRight)
                        .owcCountdownTextTransition(milliseconds: remaining)
                    landscapeCaption(snapshot, phase: phase)
                        .font(.subheadline)
                        .foregroundStyle(OWCDesign.secondary)
                        .padding(.top, 6)

                    VStack(spacing: 8) {
                        GeometryReader { proxy in
                            let fill = beforeStart
                                ? shifts.session.countdownToClockInProgress(snapshot: snapshot)
                                : snapshot.progress
                            Capsule().fill(OWCDesign.control)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(OWCDesign.accent)
                                        .frame(width: proxy.size.width * min(1, max(0, fill / 100)))
                                }
                        }
                        .frame(height: 10)
                        GeometryReader { proxy in
                            if beforeStart {
                                Text(shifts.text.formatTime(countdownAnchor(snapshot, at: date)))
                                    .position(x: 24, y: 8)
                                Text(shifts.text.formatTime(snapshot.startDate))
                                    .position(x: proxy.size.width - 24, y: 8)
                            } else {
                                Text(shifts.session.timeString(shifts.session.effectiveStartMinutes(at: date)))
                                    .position(x: 24, y: 8)
                                if shifts.session.effectiveLunchEnabled(at: date), snapshot.segments.count > 1 {
                                    Text("\(shifts.session.timeString(shifts.session.effectiveLunchStartMinutes(at: date))) · \(shifts.text.t("lunchBreak"))")
                                        .position(x: max(110, min(proxy.size.width - 110, proxy.size.width * lunchWallRatio(snapshot))), y: 8)
                                }
                                Text(shifts.session.timeString(shifts.session.effectiveEndMinutes(at: date)))
                                    .position(x: proxy.size.width - 24, y: 8)
                            }
                        }
                        .frame(height: 16)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(OWCDesign.secondary)
                    }
                    .padding(.top, 20)

                    HStack(spacing: 52) {
                        landscapeStat(
                            shifts.text.t("progress"),
                            shifts.text.formatPercent(
                                beforeStart
                                    ? shifts.session.countdownToClockInProgress(snapshot: snapshot)
                                    : snapshot.progress
                            )
                        )
                        if shifts.session.presentationSalaryEnabled { landscapeStat(shifts.text.t("moneyEarned"), shifts.text.moneyText(snapshot.earnedSoFar)) }
                        if shifts.session.effectiveScheduleMode(at: date) != .off { landscapeStat(shifts.text.t("daysUntilRest"), daysUntilRest(snapshot, now: date)) }
                    }
                    .padding(.top, 20)

                    if !immersive {
                    HStack(spacing: 10) {
                        if beforeStart {
                            Button {
                                scene.requestClockInEarly(at: date, using: shifts)
                            } label: {
                                ClockInEarlyLabel(shifts: shifts, now: date)
                            }
                            Button { scene.timerSheet = .share } label: {
                                Label(shifts.text.t("shareButton"), systemImage: "square.and.arrow.up")
                            }
                        } else {
                            Button {
                                scene.requestClockOffEarly(at: date, using: shifts)
                            } label: { ClockOffEarlyLabel(shifts: shifts, now: date) }
                            Button { scene.timerSheet = .overtime } label: {
                                Text(shifts.text.t(snapshot.isOvertimeActive(at: date) ? "adjustOvertime" : "overtime"))
                            }
                            Button { scene.timerSheet = .share } label: { Label(shifts.text.t("shareButton"), systemImage: "square.and.arrow.up") }
                        }
                    }
                    .buttonStyle(LandscapeButtonStyle())
                    .padding(.top, 20)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            } else if immersive {
                Text("—").font(.system(size: countdownSize, weight: .bold).monospacedDigit())
            } else {
                TimerDesignView(
                    shifts: shifts,
                    wide: true,
                    timelineDate: date,
                    animatesPhaseChanges: false
                )
            }
        }
        .id(phase.surfaceIdentity)
        .transition(timerTransition)
        .animation(timerAnimation, value: phase)
    }

    @ViewBuilder
    private func landscapeCaption(
        _ snapshot: NativeShiftSnapshot,
        phase: TimerVisualPhase
    ) -> some View {
        if phase == .clockIn || phase == .rest || phase == .completed {
            Text(shifts.text.t("nextShiftLabelShort"))
        } else if phase == .lunch, let breakEnd = snapshot.activeBreakEndDate {
            Label(
                shifts.text.t("pausedUntil", values: ["time": shifts.text.formatTime(breakEnd)]),
                systemImage: "cup.and.saucer"
            )
        } else if phase == .overtime {
            Label(shifts.text.t("overtimeTimeLeftCaption"), systemImage: "clock.fill")
                .symbolRenderingMode(.monochrome)
        } else {
            Text(shifts.text.t("timeLeftCaption"))
        }
    }

    private func countdownAnchor(_ snapshot: NativeShiftSnapshot, at date: Date) -> Date {
        snapshot.countdownAnchorAtMs.map { Date(timeIntervalSince1970: $0 / 1_000) }
            ?? Calendar.current.startOfDay(for: date)
    }

    private var timerAnimation: Animation {
        reduceMotion ? OWCMotion.reduced : OWCMotion.phase
    }

    private var timerTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
    }

    private func landscapeStat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.caption).foregroundStyle(OWCDesign.secondary)
            Text(value).font(.title3.bold().monospacedDigit())
        }
    }

    private var weekSummary: NativePeriodSummary? {
        guard let snapshot = shifts.session.snapshot() else { return nil }
        return shifts.session.periodSummary("week", asOf: .now, snapshot: snapshot)
    }

    private func lunchWallRatio(_ snapshot: NativeShiftSnapshot) -> Double {
        guard let lunchStart = snapshot.segments.first?.endAtMs else { return 0.5 }
        return min(1, max(0, (lunchStart - snapshot.startAtMs) / max(1, snapshot.plannedEndAtMs - snapshot.startAtMs)))
    }

    private func daysUntilRest(_ snapshot: NativeShiftSnapshot, now: Date) -> String {
        guard let rest = snapshot.nextRestDate else { return "—" }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: now),
            to: Calendar.current.startOfDay(for: rest)
        ).day ?? 0
        return shifts.text.formatDays(Double(max(0, days)))
    }
}

private struct LandscapeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 20)
            .frame(height: 44)
            .background(OWCDesign.card.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .shadow(color: .black.opacity(0.07), radius: 4, y: 2)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
