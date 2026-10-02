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
        case settledBars
    }

    @MainActor
    static func art(snapshot: CycleReportSnapshot, queries: RecordsQueries, state: State) -> ReportStripArt {
        let days = snapshot.days
        let count = days.count
        let calendar = queries.recordsCalendar
        let blanks = snapshot.period.kind == .month
            ? days.first.map { queries.recordsGridLeadingBlanks(before: $0.date) } ?? 0
            : 0
        // Weeks arrive left to right, months in a diagonal wave from the corner.
        let ranks = days.indices.map { i -> Int in
            snapshot.period.kind == .week ? i : (blanks + i) % 7 + (blanks + i) / 7
        }
        let maxRank = max(1, (ranks.max() ?? 1))
        func arrival(_ t: Double, _ i: Int) -> Double {
            ReportEase.staggered(t, index: ranks[i], count: maxRank + 1, span: 0.42)
        }
        let rest = days.indices.filter { days[$0].kind == .rest }
        func restOrder(_ i: Int) -> Int { rest.firstIndex(of: i) ?? 0 }

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
            morphs = days.indices.map { ReportEase.inOutCubic(ReportEase.staggered(ReportEase.window(b, 0.05, 1), index: $0, count: count, span: 0.55)) }
        case .rest(let b, let time):
            clock = time
            let back = ReportEase.inOutCubic(ReportEase.window(b, 0, 0.32))
            morphs = days.indices.map { _ in 1 - back }
            dim = ReportEase.inOutCubic(ReportEase.window(b, 0.28, 0.55))
            lights = days.indices.map { i in
                days[i].kind == .rest
                    ? ReportEase.outCubic(ReportEase.staggered(ReportEase.window(b, 0.34, 0.86), index: restOrder(i), count: max(1, rest.count), span: 0.5))
                    : 0
            }
            runProgress = ReportEase.outCubic(ReportEase.window(b, 0.84, 1))
        case .settled:
            break
        case .settledBars:
            morphs = days.indices.map { _ in 1 }
        }

        var art = ReportStripArt(
            snapshot: snapshot,
            weekdaySymbols: queries.recordsWeekdayGridSymbols(),
            leadingBlanks: blanks,
            dayNumbers: days.map { calendar.component(.day, from: $0.date) },
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
/// SwiftUI animation is in play, so what is on screen is always exactly the
/// chapter at that moment.
struct CycleReportPlayerView: View {
    let player: CycleReportPlayer
    let copy: CycleReportCopy
    var onRead: () -> Void
    var onClose: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 76
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var snapshot: CycleReportSnapshot { player.snapshot }
    private var b: Double { player.build }
    private var text: AppText { copy.text }

    var body: some View {
        ZStack {
            ReportBackdrop(mood: mood, time: player.clock)
            VStack(spacing: 0) {
                hud
                stage
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, 22)
                    .id(player.stageIndex)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: player.stageIndex)
                controls
            }
        }
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { tap in
                if tap.location.x < 120 { player.previous() } else { player.next() }
            }
        )
        .onLongPressGesture(minimumDuration: 0.18, maximumDistance: 60, perform: {}, onPressingChanged: { player.isHeld = $0 })
        .task(id: player.isPlaying) { await player.run() }
        .sensoryFeedback(.impact(weight: .light), trigger: player.stageIndex)
        .sensoryFeedback(.success, trigger: player.isLastStage && player.isBuilt)
        .accessibilityAction(named: Text(text.t("reportNext"))) { player.next() }
        .accessibilityAction(named: Text(text.t("reportPrevious"))) { player.previous() }
    }

    private var mood: ReportBackdrop.Mood {
        switch player.stage {
        case .calendar: .dawn
        case .hours: .energy
        case .rest: .calm
        case .comparison: .contrast
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
                Text("\(text.t(snapshot.period.kind == .week ? "reportWeekly" : "reportMonthly")) · \(copy.periodTitle(snapshot.period))".uppercased())
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
        .animation(.easeOut(duration: 0.3), value: player.isLastStage && player.isBuilt)
    }

    // MARK: Chapters

    @ViewBuilder
    private var stage: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch player.stage {
            case .calendar: calendarChapter
            case .hours: hoursChapter
            case .rest: restChapter
            case .comparison: comparisonChapter
            case .income: incomeChapter
            case .summary: summaryChapter
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(copy.spoken(player.stage, snapshot: snapshot))
    }

    private var stripHeight: CGFloat { snapshot.period.kind == .week ? 330 : 360 }

    private func strip(_ state: ReportStripScene.State) -> some View {
        ReportStripScene.art(snapshot: snapshot, queries: copy.queries, state: state)
            .frame(height: stripHeight)
    }

    private var calendarChapter: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading(eyebrow: text.t("reportWorkdays"), hero: text.formatCount(snapshot.figures.workdays), size: 1.5,
                    caption: snapshot.isInProgress ? text.t("reportSoFar") : nil,
                    appear: ReportEase.window(b, 0, 0.28))
            Spacer(minLength: 12)
            strip(.calendar(build: b))
            legend.opacity(ReportEase.window(b, 0.7, 1))
            Spacer(minLength: 24)
        }
    }

    private var hoursChapter: some View {
        let counted = Int64(Double(snapshot.figures.workedMs) * ReportEase.outCubic(ReportEase.window(b, 0.08, 1)))
        return VStack(alignment: .leading, spacing: 0) {
            heading(eyebrow: text.t("recordsWorkedTime"), hero: copy.hours(counted), size: 0.9,
                    caption: nil, appear: ReportEase.window(b, 0, 0.18))
            if snapshot.figures.overtimeMs > 0 {
                Text(text.t("reportIncludingOvertime", values: ["overtime": copy.hours(snapshot.figures.overtimeMs)]))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(
                        LinearGradient(colors: [Color(red: 1.0, green: 0.62, blue: 0.40), ReportPalette.hot], startPoint: .leading, endPoint: .trailing)
                    )
                    .opacity(ReportEase.window(b, 0.82, 1))
                    .offset(y: 8 * (1 - ReportEase.window(b, 0.82, 1)))
                    .padding(.top, 6)
            }
            Spacer(minLength: 12)
            strip(.hours(build: b))
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
                Text("\(text.t("reportLongestRest")) · \(copy.days(snapshot.longestRestRun))")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ReportPalette.cream)
                    .opacity(ReportEase.window(b, 0.86, 1))
                    .offset(y: 8 * (1 - ReportEase.window(b, 0.86, 1)))
                    .padding(.top, 6)
            }
            Spacer(minLength: 12)
            strip(.rest(build: b, time: player.clock))
            Spacer(minLength: 24)
        }
    }

    private var comparisonChapter: some View {
        let comparison = snapshot.comparison
        let current = Double(snapshot.figures.workedMs)
        let previous = current - Double(comparison?.workedDeltaMs ?? 0)
        let peak = max(1, current, previous)
        let calendar = copy.queries.recordsGridCalendar
        let before = snapshot.period.previous(calendar: calendar).map(copy.periodTitle) ?? ""
        let draw = ReportEase.outCubic(ReportEase.window(b, 0.12, 0.78))
        return VStack(alignment: .leading, spacing: 0) {
            Text(copy.comparisonTitle(snapshot).uppercased())
                .font(.caption.weight(.bold)).tracking(1.4)
                .foregroundStyle(.white.opacity(0.62))
                .opacity(ReportEase.window(b, 0, 0.2))
            comparisonHero(comparison)
                .opacity(ReportEase.window(b, 0.55, 0.9))
                .offset(y: 14 * (1 - ReportEase.window(b, 0.55, 0.9)))
                .padding(.top, 14)
            Spacer(minLength: 28)
            comparisonBar(label: before, value: copy.hours(Int64(previous)), fraction: previous / peak * draw, hot: false)
            comparisonBar(label: copy.periodTitle(snapshot.period), value: copy.hours(Int64(current * draw)), fraction: current / peak * draw, hot: true)
                .padding(.top, 22)
            Spacer(minLength: 24)
        }
    }

    @ViewBuilder
    private func comparisonHero(_ comparison: CycleReportComparison?) -> some View {
        if let comparison {
            let sentence = copy.comparisonSentence(comparison)
            let amount = abs(comparison.workedDeltaMs) >= 60_000 ? copy.hours(abs(comparison.workedDeltaMs)) : nil
            VStack(alignment: .leading, spacing: 6) {
                if let amount, let range = sentence.range(of: amount) {
                    let rest = sentence.replacingCharacters(in: range, with: "").trimmingCharacters(in: .whitespaces)
                    HStack(spacing: 10) {
                        Image(systemName: comparison.workedDeltaMs > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: heroSize * 0.5, weight: .heavy))
                            .foregroundStyle(comparison.workedDeltaMs > 0 ? ReportPalette.hot : ReportPalette.moon)
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

    private var incomeChapter: some View {
        let income = snapshot.income ?? 0
        let grow = ReportEase.outCubic(ReportEase.window(b, 0.05, 0.9))
        return VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 20)
            ZStack {
                Circle()
                    .trim(from: 0.04, to: 0.04 + 0.9 * grow)
                    .stroke(
                        AngularGradient(colors: [ReportPalette.gold.opacity(0.35), ReportPalette.cream, ReportPalette.gold], center: .center),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90 + 0.04 * 360 - 18))
                    .shadow(color: ReportPalette.gold.opacity(0.5), radius: 18)
                VStack(spacing: 6) {
                    Text(text.t("reportIncomeTitle").uppercased())
                        .font(.caption.weight(.bold)).tracking(1.4)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(text.moneyText(income * grow))
                        .font(.system(size: heroSize * 0.74, weight: .heavy, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.4).lineLimit(1)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 34)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal, 12)
            Text(text.t("reportIncomeNote"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .opacity(ReportEase.window(b, 0.7, 1))
            Spacer(minLength: 24)
        }
    }

    private var summaryChapter: some View {
        let ring = ReportEase.window(b, 0, 0.9)
        let reveal = ReportEase.window(b, 0.55, 1)
        return VStack(alignment: .leading, spacing: 0) {
            Text(copy.periodTitle(snapshot.period))
                .font(.system(size: heroSize * 0.55, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.5).lineLimit(1)
                .foregroundStyle(.white)
                .opacity(ReportEase.window(b, 0, 0.2))
            if snapshot.isInProgress {
                Text(text.t("reportSoFar")).font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.7))
            }
            ZStack {
                ReportRingArt(snapshot: snapshot, build: ring, time: player.clock)
                VStack(spacing: 2) {
                    Text(copy.hours(snapshot.figures.workedMs))
                        .font(.system(size: heroSize * 0.42, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.5).lineLimit(1)
                        .foregroundStyle(.white)
                    Text(text.t("recordsWorkedTime"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .opacity(ReportEase.window(b, 0.3, 0.7))
                .padding(.horizontal, 60)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            // Three columns until the text is large enough to break words.
            let stats = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
            stats {
                summaryStat(text.formatCount(snapshot.figures.workdays), text.t("reportWorkdays"))
                summaryStat(text.formatCount(snapshot.restDayCount), text.t("reportRestDays"))
                if let income = copy.income(snapshot) {
                    summaryStat(income, text.t("reportIncomeTitle"))
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

    private func heading(eyebrow: String?, hero: String, size: CGFloat, caption: String?, appear: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.bold)).tracking(1.4)
                    .foregroundStyle(.white.opacity(0.62))
            }
            Text(hero)
                .font(.system(size: heroSize * size, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.45).lineLimit(2)
                .foregroundStyle(.white)
            if let caption {
                Text(caption).font(.title3.weight(.medium)).foregroundStyle(.white.opacity(0.7))
            }
        }
        .opacity(appear)
        .offset(y: 16 * (1 - appear))
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
