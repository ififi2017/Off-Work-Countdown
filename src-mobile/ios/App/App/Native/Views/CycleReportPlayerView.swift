import SwiftUI

/// Builds the strip of days for a chapter from the chapter clock.
enum ReportStripScene {
    enum State {
        /// The setup page's preview: days rising in, then still.
        case teaser(Double)
        case calendar(build: Double)
        case hours(build: Double)
        case rest(build: Double, time: Double)
        case settled
        case summaryBars(Double)
    }

    /// Prepared once per report; calendar and labels do not change on each frame.
    struct Layout {
        let weekdaySymbols: [String]
        let leadingBlanks: Int
        let dayNumbers: [Int]
        let arrivalRanks: [Int]
        let restOrders: [Int]
        let restCount: Int
        let peak: Double

        @MainActor
        init(snapshot: CycleReportSnapshot, queries: RecordsQueries) {
            let days = snapshot.days
            let blanks = snapshot.period.kind == .month
                ? days.first.map { queries.recordsGridLeadingBlanks(before: $0.date) } ?? 0 : 0
            leadingBlanks = blanks
            weekdaySymbols = queries.recordsWeekdayGridSymbols()
            dayNumbers = days.map { queries.recordsCalendar.component(.day, from: $0.date) }
            arrivalRanks = days.indices.map { i in
                snapshot.period.kind == .week ? i : (blanks + i) % 7 + (blanks + i) / 7
            }
            var order = 0
            restOrders = days.map { day in
                guard day.kind == .rest else { return 0 }
                defer { order += 1 }
                return order
            }
            restCount = order
            peak = Double(max(1, days.map { $0.workMs + $0.overtimeMs }.max() ?? 1))
        }
    }

    @MainActor
    static func art(snapshot: CycleReportSnapshot, layout: Layout, state: State) -> ReportStripArt {
        let days = snapshot.days
        let count = days.count
        let maxRank = max(1, layout.arrivalRanks.max() ?? 1)
        func arrival(_ t: Double, _ i: Int) -> Double {
            ReportEase.staggered(t, index: layout.arrivalRanks[i], count: maxRank + 1, span: 0.42)
        }

        var reveals = [Double](repeating: 1, count: count)
        var morphs = [Double](repeating: 0, count: count)
        var lights = [Double](repeating: 0, count: count)
        var dim = 0.0
        var runProgress = 0.0
        var clock = 0.0
        var labels = 0.0

        switch state {
        case .teaser(let t):
            reveals = days.indices.map { arrival(t / 1.5, $0) }
            if t > 1.6 { runProgress = 0 }
        case .calendar(let b):
            reveals = days.indices.map { arrival(b, $0) }
        case .hours(let b):
            labels = ReportEase.window(b, 0.86, 1)
            morphs = days.indices.map { i in
                snapshot.period.kind == .month
                    ? ReportEase.window(b, 0.04, 1)
                    : ReportEase.inOutCubic(ReportEase.staggered(ReportEase.window(b, 0.05, 1), index: i, count: count, span: 0.88))
            }
        case .rest(let b, let time):
            clock = time
            let back = ReportEase.inOutCubic(ReportEase.window(b, 0, 0.32))
            morphs = days.indices.map { _ in 1 - back }
            dim = ReportEase.inOutCubic(ReportEase.window(b, 0.28, 0.55))
            lights = days.indices.map { i in
                days[i].kind == .rest
                    ? ReportEase.outCubic(ReportEase.staggered(ReportEase.window(b, 0.34, 0.86), index: layout.restOrders[i], count: max(1, layout.restCount), span: 0.5))
                    : 0
            }
            runProgress = ReportEase.outCubic(ReportEase.window(b, 0.84, 1))
        case .settled:
            break
        case .summaryBars(let t):
            morphs = days.indices.map { _ in 1 }
            reveals = days.indices.map { ReportEase.staggered(t, index: $0, count: count, span: 0.7) }
            labels = ReportEase.window(t, 0.7, 1)
        }

        var art = ReportStripArt(
            snapshot: snapshot,
            weekdaySymbols: layout.weekdaySymbols,
            leadingBlanks: layout.leadingBlanks,
            dayNumbers: layout.dayNumbers, peak: layout.peak,
            reveals: reveals, morphs: morphs, lights: lights
        )
        art.dim = dim
        art.run = snapshot.longestRestStart.map { $0..<($0 + snapshot.longestRestRun) }
        art.runProgress = runProgress
        art.valueLabels = labels
        art.time = clock
        return art
    }
}

/// The animated chapters. Each is drawn straight from the player's clock: no
/// implicit chapter animation is in play, so what is on screen is always exactly the
/// chapter at that moment.
struct CycleReportPlayerView: View {
    let player: CycleReportPlayer
    let copy: CycleReportCopy
    var onRead: () -> Void
    var onClose: () -> Void
    private let stripLayout: ReportStripScene.Layout
    private let monthLabels: [String]
    private let overtimeLabels: [String]
    @State private var previousMood: ReportBackdrop.Mood?

    init(player: CycleReportPlayer, copy: CycleReportCopy, onRead: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.player = player
        self.copy = copy
        self.onRead = onRead
        self.onClose = onClose
        stripLayout = ReportStripScene.Layout(snapshot: player.snapshot, queries: copy.queries)
        monthLabels = copy.monthLabels(player.snapshot)
        overtimeLabels = copy.dayLabels(player.snapshot.overtime?.days ?? [], kind: player.snapshot.period.kind)
    }

    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 76
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var snapshot: CycleReportSnapshot { player.snapshot }
    private var b: Double { player.build }
    private var text: AppText { copy.text }

    var body: some View {
        ZStack {
            ReportBackdrop(mood: mood, time: player.clock, previousMood: previousMood,
                           blend: ReportEase.outCubic(player.time / OWCMotion.reportBackdropDuration))
            VStack(spacing: 0) {
                hud
                stage
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, 22)

                controls
            }
        }
        .onChange(of: player.isRunning, initial: true) {
            if player.isRunning { player.startDisplayLink() } else { player.stopDisplayLink() }
        }
        .onDisappear { player.stopDisplayLink() }
        .onChange(of: player.stageIndex) { old, _ in
            previousMood = player.isRunning ? mood(for: player.stages[old]) : nil
        }
        .sensoryFeedback(.impact(weight: .light), trigger: player.stageIndex)
        .sensoryFeedback(.success, trigger: player.isLastStage && player.isBuilt)
        .accessibilityAction(named: Text(text.t("reportNext"))) { player.next() }
        .accessibilityAction(named: Text(text.t("reportPrevious"))) { player.previous() }
    }

    private var mood: ReportBackdrop.Mood {
        mood(for: player.stage)
    }

    private func mood(for stage: CycleReportStage) -> ReportBackdrop.Mood {
        switch stage {
        case .calendar: .dawn
        case .hours: .energy
        case .overtime: .contrast
        case .baseline: .contrast
        case .rest: .calm
        case .ahead: .calm
        case .focus: .dawn
        case .income: .gold
        case .summary: .finale
        }
    }

    // MARK: Chrome

    private var hud: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(player.stages.indices, id: \.self) { index in
                    GeometryReader { geo in
                        Capsule().fill(.white.opacity(0.22))
                            .overlay(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.95))
                                    .frame(width: geo.size.width * fill(index))
                            }
                    }
                    .frame(height: 3)
                }
            }
            .accessibilityHidden(true)
            HStack {
                Text(verbatim: "\(text.t(snapshot.period.kind.titleKey)) · \(copy.periodTitle(snapshot.period))".uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                ReportCloseButton(label: text.t("close"), action: onClose)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    private func fill(_ index: Int) -> Double {
        if index < player.stageIndex { return 1 }
        if index == player.stageIndex { return player.progress }
        return 0
    }

    private var controls: some View {
        HStack {
            Button { player.togglePlayback() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(text.t(player.isPlaying ? "reportPause" : "reportResume"))
            Spacer()
            Button(action: onRead) {
                Label(text.t("reportRead"), systemImage: "text.alignleft")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
        .opacity(player.isLastStage && player.isBuilt ? 0 : 1)
        .allowsHitTesting(!(player.isLastStage && player.isBuilt))
        .accessibilityHidden(player.isLastStage && player.isBuilt)
    }

    // MARK: Chapters

    @ViewBuilder
    private var stage: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch player.stage {
            case .calendar, .hours:
                if snapshot.period.kind == .year { yearTimeChapters } else { timeChapters }
            case .overtime: overtimeChapter
            case .baseline: baselineChapter
            case .rest: restChapter
            case .ahead: aheadChapter
            case .focus: focusChapter
            case .income: incomeChapter
            case .summary: summaryChapter
            }
        }
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { tap in
            if tap.location.x < 120 { player.previous() } else { player.next() }
        }, including: .gesture)
        .onLongPressGesture(minimumDuration: 0.18, maximumDistance: 60, perform: {}, onPressingChanged: { player.isHeld = $0 })
        .accessibilityElement(children: .contain)
        .accessibilityLabel(copy.spoken(player.stage, snapshot: snapshot))
    }

    private var stripHeight: CGFloat { snapshot.period.kind == .week ? 330 : 360 }

    private func strip(_ state: ReportStripScene.State) -> some View {
        ReportStripScene.art(snapshot: snapshot, layout: stripLayout, state: state)
    }

    /// The calendar and hours share one drawing surface and one baseline.
    /// Only their heading changes; the dates themselves remain on screen.
    private var timeChapters: some View {
        GeometryReader { geometry in
            let artHeight = min(stripHeight, geometry.size.height * 0.55)
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if player.stage == .calendar {
                        heading(eyebrow: copy.workdays(snapshot), hero: copy.headline(snapshot), size: 0.62,
                                caption: snapshot.isInProgress ? text.t("reportSoFar") : nil,
                                appear: ReportEase.window(b, 0, 0.28), lines: 3)
                    } else {
                        hoursHeading
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                ReportStripScene.art(snapshot: snapshot, layout: stripLayout,
                                     state: player.stage == .calendar ? .calendar(build: b) : .hours(build: b))
                    .frame(height: artHeight)
                legend
                    .frame(height: 30, alignment: .topLeading)
                    .opacity(player.stage == .calendar ? ReportEase.window(b, 0.7, 1) : 0)
                Spacer().frame(height: 20)
            }
        }
    }

    private var hoursHeading: some View {
        let counted = Int64(Double(snapshot.figures.workedMs) * ReportEase.outCubic(ReportEase.window(b, 0.08, 1)))
        return VStack(alignment: .leading, spacing: 6) {
            Text(text.t("recordsWorkedTime").uppercased())
                .font(.caption.weight(.bold)).tracking(1.4)
                .foregroundStyle(.white.opacity(0.62))
            ReportDurationText(value: copy.hours(counted), numberSize: heroSize * 0.85)
            if snapshot.figures.overtimeMs > 0 {
                Text(text.t("reportIncludingOvertime", values: ["overtime": copy.hours(snapshot.figures.overtimeMs)]))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ReportPalette.cream)
                    .opacity(ReportEase.window(b, 0.82, 1))
            }
        }
        .opacity(ReportEase.outCubic(ReportEase.window(b, 0, 0.18)))
        .padding(.top, 18)
    }

    private var yearTimeChapters: some View {
        VStack(alignment: .leading, spacing: 0) {
            if player.stage == .calendar {
                heading(eyebrow: copy.workdays(snapshot), hero: copy.headline(snapshot), size: 0.62,
                        caption: snapshot.isInProgress ? text.t("reportSoFar") : copy.periodTitle(snapshot.period),
                        appear: ReportEase.window(b, 0, 0.28), lines: 3)
            } else {
                hoursHeading
            }
            Spacer(minLength: 16)
            yearBars(snapshot.months.map { Double($0.figures.workedMs) }, label: text.t("recordsWorkedTime"))
            Spacer(minLength: 24)
        }
    }

    private func yearBars(_ values: [Double], label: String, color: Color = ReportPalette.orange) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "\(text.t("reportMonthlyTrend")) · \(label)")
                .font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.65))
            ReportMetricBars(values: values, labels: monthLabels, build: b, color: color)
                .frame(height: 230)
        }
    }

    /// The same overtime total as Records, with daily or monthly detail.
    private var overtimeChapter: some View {
        let counted = Int64(Double(snapshot.figures.overtimeMs) * ReportEase.outCubic(ReportEase.window(b, 0.08, 0.85)))
        return VStack(alignment: .leading, spacing: 0) {
            Text(text.t("recordsOvertime").uppercased())
                .font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(.white.opacity(0.62))
            ReportDurationText(value: copy.hours(counted), numberSize: heroSize * 0.85)
                .padding(.top, 14)
            if let overtime = snapshot.overtime {
                Text(copy.overtimeDays(overtime))
                    .font(.subheadline).foregroundStyle(.white.opacity(0.7)).padding(.top, 8)
                Text(copy.overtimePeak(overtime, kind: snapshot.period.kind))
                    .font(.title3.weight(.semibold)).foregroundStyle(ReportPalette.cream)
                    .opacity(ReportEase.window(b, 0.7, 1)).padding(.top, 12)
            }
            Spacer(minLength: 12)
            if snapshot.period.kind == .year {
                yearBars(snapshot.months.map { Double($0.figures.overtimeMs) }, label: text.t("recordsOvertime"), color: ReportPalette.hot)
            } else if let overtime = snapshot.overtime {
                ReportMetricBars(values: overtime.days.map { Double($0.overtimeMs) },
                                 labels: overtimeLabels, build: b, color: ReportPalette.hot)
                    .frame(height: 250)
            }
            Spacer(minLength: 24)
        }
    }

    private var restChapter: some View {
        let progress = ReportEase.window(b, 0.34, 0.86)
        let shown = Int((Double(snapshot.restDayCount) * progress).rounded())
        return VStack(alignment: .leading, spacing: 0) {
            if snapshot.restDayCount == 0 {
                heading(eyebrow: nil, hero: text.t("reportRestNone"), size: 0.5, caption: nil, appear: ReportEase.window(b, 0.2, 0.5))
            } else {
                heading(eyebrow: text.t("reportRestDays"), hero: text.formatCount(shown), size: 1.25,
                        caption: nil, appear: ReportEase.window(b, 0, 0.18))
                Text(verbatim: "\(text.t("reportLongestRest")) · \(copy.days(snapshot.longestRestRun))")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ReportPalette.cream)
                    .opacity(ReportEase.window(b, 0.86, 1))
                    .offset(y: 8 * (1 - ReportEase.window(b, 0.86, 1)))
                    .padding(.top, 6)
            }
            Spacer(minLength: 12)
            if snapshot.period.kind == .year {
                Text(verbatim: "\(text.t("reportLeaveUsed")) · \(copy.leaveDays(halfDays: snapshot.leaveUsedHalfDays))")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.75)).padding(.bottom, 20)
                yearBars(snapshot.months.map { Double($0.restDayCount) }, label: text.t("reportRestDays"), color: ReportPalette.moon)
            } else {
                strip(.rest(build: b, time: player.clock)).frame(height: stripHeight)
            }
            Spacer(minLength: 24)
        }
    }

    /// This period against the person's own usual, in two bars and one sentence.
    @ViewBuilder
    private var baselineChapter: some View {
        if let baseline = snapshot.baseline {
            let current = Double(snapshot.figures.workedMs)
            let reference = Double(baseline.baselineWorkedMs)
            let peak = max(1, current, reference)
            let draw = ReportEase.outCubic(ReportEase.window(b, 0.12, 0.78))
            VStack(alignment: .leading, spacing: 0) {
                Text(copy.baselineTitle(snapshot).uppercased())
                    .font(.caption.weight(.bold)).tracking(1.4)
                    .foregroundStyle(.white.opacity(0.62))
                    .opacity(ReportEase.window(b, 0, 0.2))
                baselineHero(baseline)
                    .opacity(ReportEase.window(b, 0.55, 0.9))
                    .offset(y: 14 * (1 - ReportEase.window(b, 0.55, 0.9)))
                    .padding(.top, 14)
                Spacer(minLength: 28)
                comparisonBar(label: copy.baselineBarLabel(snapshot), value: copy.hours(Int64(reference)), fraction: reference / peak * draw, hot: false)
                comparisonBar(label: copy.periodTitle(snapshot.period), value: copy.hours(Int64(current * draw)), fraction: current / peak * draw, hot: true)
                    .padding(.top, 22)
                Spacer(minLength: 24)
            }
        }
    }

    @ViewBuilder
    private func baselineHero(_ baseline: CycleReportBaseline) -> some View {
        let sentence = copy.baselineSentence(snapshot)
        let amount = abs(baseline.deltaMs) >= 60_000 ? copy.hours(abs(baseline.deltaMs)) : nil
        VStack(alignment: .leading, spacing: 6) {
            if let amount, let range = sentence.range(of: amount) {
                let rest = sentence.replacingCharacters(in: range, with: "").trimmingCharacters(in: .whitespaces)
                HStack(spacing: 10) {
                    Image(systemName: baseline.deltaMs > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: heroSize * 0.5, weight: .heavy))
                        .foregroundStyle(baseline.deltaMs > 0 ? ReportPalette.hot : ReportPalette.moon)
                    Text(amount)
                        .font(.system(size: heroSize * 0.78, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.5).lineLimit(1)
                        .foregroundStyle(.white)
                }
                Text(rest).font(.title3.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
            } else {
                Text(sentence)
                    .font(.system(size: heroSize * 0.55, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }

    private func comparisonBar(label: String, value: String, fraction: Double, hot: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(hot ? 0.95 : 0.6))
                Spacer()
                Text(value).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(.white.opacity(hot ? 1 : 0.7))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule()
                        .fill(hot ? AnyShapeStyle(LinearGradient(colors: [ReportPalette.cream, ReportPalette.orange], startPoint: .leading, endPoint: .trailing))
                                  : AnyShapeStyle(Color.white.opacity(0.32)))
                        .frame(width: max(18, geo.size.width * fraction))
                }
            }
            .frame(height: 22)
        }
    }

    /// The next break, how far off it is, and the leave still to spend.
    @ViewBuilder
    private var aheadChapter: some View {
        if let ahead = snapshot.ahead {
            let hero = copy.aheadHero(ahead)
                ?? ahead.leaveRemainingHalfDays.map { copy.leaveDays(halfDays: $0) }
                ?? copy.leaveDays(halfDays: ahead.leaveUsedHalfDays)
            VStack(alignment: .leading, spacing: 0) {
                heading(eyebrow: text.t(copy.aheadTitleKey(ahead)),
                        hero: hero, size: 1.15, caption: copy.aheadBreak(ahead),
                        appear: ReportEase.window(b, 0, 0.22), emphasizeNumbers: ahead.isHistorical || ahead.nextBreak == nil)
                Spacer(minLength: 16)
                if ahead.nextBreak != nil {
                    ReportHorizonArt(ahead: ahead, build: b, time: player.clock)
                        .frame(height: 150)
                    Spacer(minLength: 16)
                } else {
                    leaveShare(ahead)
                    Spacer(minLength: 16)
                }
                leaveCard(ahead)
                    .opacity(ReportEase.window(b, 0.6, 0.95))
                    .offset(y: 12 * (1 - ReportEase.window(b, 0.6, 0.95)))
                Spacer(minLength: 24)
            }
        }
    }

    /// What is left of the year's leave, as a share of what was granted.
    @ViewBuilder
    private func leaveShare(_ ahead: CycleReportAhead) -> some View {
        if let left = ahead.leaveRemainingHalfDays, let granted = ahead.leaveEntitledHalfDays, granted > 0 {
            let fraction = Double(left) / Double(granted) * ReportEase.outCubic(ReportEase.window(b, 0.1, 0.8))
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.1))
                        Capsule()
                            .fill(LinearGradient(colors: [ReportPalette.cream, ReportPalette.moon], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(24, geo.size.width * fraction))
                    }
                }
                .frame(height: 26)
                HStack {
                    Text(copy.leaveDays(halfDays: left)).foregroundStyle(.white)
                    Spacer()
                    Text(copy.leaveDays(halfDays: granted)).foregroundStyle(.white.opacity(0.55))
                }
                .font(.footnote.weight(.semibold).monospacedDigit())
            }
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func leaveCard(_ ahead: CycleReportAhead) -> some View {
        let rows: [(String, String)] = [
            ahead.nextBreak != nil ? ahead.leaveRemainingHalfDays.map { (text.t("reportLeaveLeft"), copy.leaveDays(halfDays: $0)) } : nil,
            ahead.leaveUsedHalfDays > 0 && (ahead.nextBreak != nil || ahead.leaveRemainingHalfDays != nil) ? (text.t("reportLeaveUsed"), copy.leaveDays(halfDays: ahead.leaveUsedHalfDays)) : nil,
        ].compactMap { $0 }
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack {
                        Text(row.0).font(.body).foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text(row.1).font(.body.weight(.bold).monospacedDigit()).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    if index < rows.count - 1 { Divider().overlay(.white.opacity(0.12)).padding(.leading, 18) }
                }
            }
            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    /// Completed focus rounds, the best day, and what they were mostly spent on.
    @ViewBuilder
    private var focusChapter: some View {
        if let focus = snapshot.focus {
            let shown = Int((Double(focus.rounds) * ReportEase.outCubic(ReportEase.window(b, 0.1, 0.85))).rounded())
            VStack(alignment: .leading, spacing: 0) {
                heading(eyebrow: text.t("reportFocusRounds"), hero: text.formatCount(shown), size: 1.5,
                        caption: copy.focusBest(focus, snapshot: snapshot), appear: ReportEase.window(b, 0, 0.2))
                Spacer(minLength: 16)
                Text(verbatim: "\(text.t("reportFocusDuration")) · \(copy.hours(focus.focusedMs))")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.75)).padding(.bottom, 16)
                if snapshot.period.kind == .year {
                    yearBars(snapshot.months.map { Double($0.focusRounds) }, label: text.t("reportFocusRounds"), color: ReportPalette.gold)
                } else {
                    ReportFocusArt(focus: focus, labels: copy.weekdayLabels(snapshot), build: b)
                        .frame(height: 220)
                }
                if let icon = focus.topIcon {
                    HStack(spacing: 10) {
                        Image(systemName: icon.systemName).font(.body.weight(.semibold)).foregroundStyle(ReportPalette.gold)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(text.t("reportFocusTop")).font(.caption).foregroundStyle(.white.opacity(0.6))
                            Text(text.t(icon.titleKey)).font(.headline).foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(.white.opacity(0.1), in: Capsule())
                    .opacity(ReportEase.window(b, 0.7, 1))
                    .padding(.top, 20)
                }
                Spacer(minLength: 24)
            }
        }
    }

    /// Pay as a rate and what overtime added to it, drawn as one gold ring.
    @ViewBuilder
    private var incomeChapter: some View {
        if let pay = snapshot.pay {
            let grow = ReportEase.outCubic(ReportEase.window(b, 0.05, 0.9))
            let share = pay.overtimeExtra.map { $0 / max(0.01, pay.total) } ?? 0
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 16)
                ZStack {
                    incomeRing(grow: grow, overtimeShare: share)
                    VStack(spacing: 4) {
                        Text((pay.perHour != nil ? text.t("reportPerHour") : text.t("reportIncomeTitle")).uppercased())
                            .font(.caption.weight(.bold)).tracking(1.4)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(copy.money((pay.perHour ?? pay.total) * grow))
                            .font(.system(size: heroSize * 0.74, weight: .heavy, design: .rounded))
                            .minimumScaleFactor(0.4).lineLimit(1)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 44)
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 12)
                VStack(spacing: 0) {
                    incomeRow(text.t("reportIncomeTotal"), copy.money(pay.total * grow))
                    if let extra = pay.overtimeExtra {
                        Divider().overlay(.white.opacity(0.12)).padding(.leading, 18)
                        incomeRow(text.t("reportIncomeExtra"), copy.money(extra * grow), hot: true)
                    }
                }
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .opacity(ReportEase.window(b, 0.55, 0.95))
                .padding(.top, 20)
                Text(text.t("reportIncomeNote"))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.top, 12)
                    .opacity(ReportEase.window(b, 0.7, 1))
                Spacer(minLength: 16)
            }
        }
    }

    private func incomeRing(grow: Double, overtimeShare: Double) -> some View {
        let sweep = 0.9 * grow
        let regular = sweep * (1 - overtimeShare)
        return ZStack {
            Circle().stroke(.white.opacity(0.08), lineWidth: 12).padding(6)
            Circle()
                .trim(from: 0.04, to: 0.04 + regular)
                .stroke(AngularGradient(colors: [ReportPalette.gold.opacity(0.4), ReportPalette.cream, ReportPalette.gold], center: .center),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .padding(6)
            if overtimeShare > 0.001 {
                Circle()
                    .trim(from: 0.04 + regular, to: 0.04 + sweep)
                    .stroke(LinearGradient(colors: [Color(red: 1.0, green: 0.55, blue: 0.30), ReportPalette.hot], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .padding(6)
            }
        }
        .rotationEffect(.degrees(-90 - 18))
        .shadow(color: ReportPalette.gold.opacity(0.45), radius: 16)
    }

    private func incomeRow(_ label: String, _ value: String, hot: Bool = false) -> some View {
        HStack {
            Text(label).font(.body).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(.body.weight(.bold).monospacedDigit())
                .foregroundStyle(hot ? Color(red: 1.0, green: 0.62, blue: 0.40) : .white)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private var summaryChapter: some View {
        let ring = ReportEase.window(b, 0, 0.9)
        let reveal = ReportEase.window(b, 0.55, 1)
        return VStack(alignment: .leading, spacing: 0) {
            Text(copy.headline(snapshot))
                .font(.system(size: heroSize * 0.5, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.5).lineLimit(2)
                .foregroundStyle(.white)
                .opacity(ReportEase.window(b, 0, 0.2))
            Text(snapshot.isInProgress ? text.t("reportSoFar") : copy.periodTitle(snapshot.period))
                .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.7))
                .padding(.top, 2)
            Group {
                if snapshot.period.kind != .month {
                    VStack(alignment: .leading, spacing: 8) {
                        ReportDurationText(value: copy.hours(snapshot.figures.workedMs), numberSize: heroSize * 0.48)
                        Text(text.t("recordsWorkedTime"))
                            .font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.65))
                        if snapshot.period.kind == .year {
                            ReportMetricBars(values: snapshot.months.map { Double($0.figures.workedMs) },
                                             labels: monthLabels, build: ring)
                                .frame(height: 180)
                        } else {
                            strip(.summaryBars(ring)).frame(height: 180)
                        }
                    }
                    .padding(.top, 28)
                } else {
                    ZStack {
                        ReportRingArt(snapshot: snapshot, build: ring, peak: stripLayout.peak)
                        GeometryReader { geo in
                            let inner = min(geo.size.width, geo.size.height) * 0.58 * 0.8
                            VStack(spacing: 2) {
                                Text(copy.hours(snapshot.figures.workedMs))
                                    .font(.system(size: heroSize * 0.32, weight: .heavy, design: .rounded))
                                    .minimumScaleFactor(0.3).lineLimit(1)
                                    .foregroundStyle(.white)
                                Text(text.t("recordsWorkedTime"))
                                    .font(.footnote.weight(.semibold))
                                    .minimumScaleFactor(0.5).lineLimit(1)
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                            .frame(width: inner)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                            .opacity(ReportEase.window(b, 0.3, 0.7))
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
            }

            // Three columns until the text is large enough to break words.
            let stats = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
            stats {
                summaryStat(text.formatCount(snapshot.figures.workdays), text.t("reportWorkdays"))
                summaryStat(text.formatCount(snapshot.restDayCount), text.t("reportRestDays"))
                if let pay = snapshot.pay {
                    summaryStat(copy.money(pay.total), text.t("reportIncomeTitle"))
                } else if snapshot.figures.overtimeMs > 0 {
                    summaryStat(copy.hours(snapshot.figures.overtimeMs), text.t("recordsOvertime"))
                } else if snapshot.longestRestRun > 0 {
                    summaryStat(copy.days(snapshot.longestRestRun), text.t("reportLongestRest"))
                }
            }
            .opacity(reveal)
            .offset(y: 14 * (1 - reveal))
            .padding(.top, 18)

            Spacer(minLength: 12)
            HStack(spacing: 10) {
                Button { player.replay() } label: { Text(text.t("reportReplay")) }
                    .buttonStyle(ReportPillStyle(prominent: false, onWarm: true))
                Button(action: onClose) { Text(text.t("done")) }
                    .buttonStyle(ReportPillStyle(prominent: true, onWarm: true))
            }
            .opacity(reveal)
            .padding(.bottom, 12)
        }
    }

    private func summaryStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.heavy).monospacedDigit())
                .minimumScaleFactor(0.6).lineLimit(1)
                .foregroundStyle(.white)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Pieces

    private func heading(eyebrow: String?, hero: String, size: CGFloat, caption: String?, appear: Double, lines: Int = 2, emphasizeNumbers: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.bold)).tracking(1.4)
                    .foregroundStyle(.white.opacity(0.62))
            }
            if emphasizeNumbers {
                ReportDurationText(value: hero, numberSize: heroSize * size)
            } else {
                Text(hero)
                    .font(.system(size: heroSize * size, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.45).lineLimit(lines)
                    .foregroundStyle(.white)
            }
            if let caption {
                Text(caption).font(.title3.weight(.medium)).foregroundStyle(.white.opacity(0.7))
            }
        }
        .opacity(ReportEase.outCubic(appear))
        .offset(y: 18 * (1 - ReportEase.outCubic(appear)))
        .padding(.top, 18)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(ReportPalette.orange, text.t("recordsWorkRegular"))
            if snapshot.figures.overtimeMs > 0 { legendItem(ReportPalette.hot, text.t("recordsOvertime")) }
            legendItem(.white.opacity(0.3), text.t("recordsRestDay"))
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white.opacity(0.7))
        .padding(.top, 6)
    }

    private func legendItem(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title)
        }
    }
}

/// Keeps a localized duration intact while giving its numbers more weight than
/// its units. The original formatted string also remains the spoken value.
private struct ReportDurationText: View {
    let value: String
    let numberSize: CGFloat

    var body: some View {
        Text(styled)
            .lineLimit(1).minimumScaleFactor(0.45)
            .foregroundStyle(.white)
            .accessibilityLabel(value)
    }

    private var styled: AttributedString {
        var result = AttributedString(value)
        result.font = .system(size: numberSize * 0.38, weight: .semibold, design: .rounded)
        var start: String.Index?
        func emphasize(until end: String.Index) {
            guard let begin = start,
                  let lower = AttributedString.Index(begin, within: result),
                  let upper = AttributedString.Index(end, within: result) else { return }
            result[lower..<upper].font = .system(size: numberSize, weight: .bold, design: .rounded).monospacedDigit()
        }
        for index in value.indices {
            if value[index].isNumber {
                if start == nil { start = index }
            } else {
                emphasize(until: index)
                start = nil
            }
        }
        emphasize(until: value.endIndex)
        return result
    }
}
