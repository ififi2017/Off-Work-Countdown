import SwiftUI
import UIKit

/// Weekly and monthly reports (plan 020 §4).
///
/// Setup first, where the person decides whether pay is part of this report,
/// then either the animated pages or the same facts as plain text. Both read
/// one `CycleReportSnapshot`, which is built once after the choice, so the
/// numbers cannot differ between pages or between the two ways of reading.
struct CycleReportView: View {
    let request: CycleReportRequest
    let queries: RecordsQueries
    let text: AppText
    let preferences: PreferencesStore
    let isAuthorized: Bool
    var onUnlock: () -> Void
    var onClose: () -> Void

    private enum Mode: Equatable {
        case setup
        case loading
        case unavailable
        case empty
        case reading
        case playing
    }

    private struct Launch: Equatable {
        let id = UUID()
        let playing: Bool
    }

    @State private var mode: Mode = .setup
    @State private var includesIncome: Bool
    @State private var snapshot: CycleReportSnapshot?
    @State private var player: CycleReportPlayer?
    @State private var launch: Launch?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var voiceOverRunning = UIAccessibility.isVoiceOverRunning

    init(
        request: CycleReportRequest,
        queries: RecordsQueries,
        text: AppText,
        preferences: PreferencesStore,
        isAuthorized: Bool,
        onUnlock: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.request = request
        self.queries = queries
        self.text = text
        self.preferences = preferences
        self.isAuthorized = isAuthorized
        self.onUnlock = onUnlock
        self.onClose = onClose
        // Pay follows the existing hide setting: hidden means off until the
        // person asks for it here, and asking passes the same owner check.
        _includesIncome = State(initialValue: !preferences.hideEarnings)
    }

    private var copy: CycleReportCopy { CycleReportCopy(text: text, queries: queries) }
    private var period: CycleReportPeriod { request.period }
    private var animationAvailable: Bool { !reduceMotion }
    /// People who asked the system for less motion, or who read with
    /// VoiceOver, start on the readable page; nothing waits for an animation.
    private var prefersReading: Bool { reduceMotion || voiceOverRunning }
    private var isInProgress: Bool { !period.isComplete(at: .now, calendar: queries.recordsGridCalendar) }

    var body: some View {
        ZStack {
            OWCDesign.page.ignoresSafeArea()
            switch mode {
            case .setup, .loading, .unavailable, .empty:
                setupPage
            case .reading:
                if let snapshot {
                    CycleReportReadingView(
                        snapshot: snapshot,
                        copy: copy,
                        canPlay: animationAvailable,
                        onPlay: { start(playing: true) },
                        onClose: onClose
                    )
                }
            case .playing:
                if let player {
                    CycleReportPlayerView(
                        player: player,
                        copy: copy,
                        onRead: { readInstead() },
                        onClose: onClose
                    )
                }
            }
        }
        .task(id: launch) {
            guard let launch else { return }
            await build(playing: launch.playing)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player?.pause() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
            voiceOverRunning = UIAccessibility.isVoiceOverRunning
        }
    }

    // MARK: Setup

    private var setupPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text(text.t(period.kind == .week ? "reportWeekly" : "reportMonthly"))
                        .font(.largeTitle.bold())
                        .foregroundStyle(OWCDesign.primary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 12)
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(OWCDesign.control, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(OWCDesign.secondary)
                    .accessibilityLabel(text.t("close"))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(copy.periodTitle(period))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(OWCDesign.primary)
                    if isInProgress {
                        Text(text.t("reportSoFar"))
                            .font(.subheadline)
                            .foregroundStyle(OWCDesign.secondary)
                    }
                }

                if !isAuthorized {
                    RecordsLockedPlaceholder(text: text, kind: .summary, onUnlock: onUnlock)
                } else {
                    if preferences.salaryEnabled {
                        incomeChoice
                    }
                    statusMessage
                    actions
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 16)
            .padding(.bottom, OWCDesign.detailBottomInset)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var incomeChoice: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text(text.t("reportIncludeIncome")).font(.body)
                    Spacer()
                    Toggle(text.t("reportIncludeIncome"), isOn: Binding(
                        get: { includesIncome },
                        set: setIncluding
                    ))
                    .labelsHidden()
                }
                Text(text.t("reportIncludeIncomeNote"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .sensoryFeedback(.selection, trigger: includesIncome)
    }

    private func setIncluding(_ wanted: Bool) {
        guard wanted, preferences.hideEarnings else {
            includesIncome = wanted
            return
        }
        // Showing pay in this report does not unhide it anywhere else; it only
        // passes the same check the eye button does.
        Task { @MainActor in
            if await BiometricGate.confirmOwner(reason: text.t("unlockSalaryReason")) {
                includesIncome = true
            }
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch mode {
        case .loading:
            ProgressView().frame(maxWidth: .infinity)
        case .unavailable:
            Text(text.t("reportUnavailable"))
                .font(.subheadline)
                .foregroundStyle(OWCDesign.secondary)
        case .empty:
            Text(text.t("reportEmpty"))
                .font(.subheadline)
                .foregroundStyle(OWCDesign.secondary)
        default:
            EmptyView()
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button { start(playing: !prefersReading) } label: {
                Text(text.t(prefersReading ? "reportRead" : "reportPlay"))
            }
            .buttonStyle(OWCPrimaryButtonStyle())
            if animationAvailable, !prefersReading {
                Button { start(playing: false) } label: { Text(text.t("reportRead")) }
                    .buttonStyle(OWCSecondaryButtonStyle())
            } else if animationAvailable {
                Button { start(playing: true) } label: { Text(text.t("reportPlay")) }
                    .buttonStyle(OWCSecondaryButtonStyle())
            }
        }
        .disabled(mode == .loading)
    }

    // MARK: Building

    private func start(playing: Bool) {
        launch = Launch(playing: playing && animationAvailable)
    }

    private func readInstead() {
        player?.pause()
        mode = .reading
    }

    private func build(playing: Bool) async {
        mode = .loading
        guard let measured = await queries.cycleReportSnapshot(for: period) else {
            mode = .unavailable
            return
        }
        // Dropped here, once, rather than hidden by each page: a report that was
        // not asked to show pay never carries it.
        let visible = includesIncome ? measured : measured.withoutIncome()
        guard visible.hasData else {
            mode = .empty
            return
        }
        snapshot = visible
        if playing {
            player = CycleReportPlayer(snapshot: visible)
            mode = .playing
        } else {
            mode = .reading
        }
    }
}

/// Presents a waiting report over everything once first-run screens are out of
/// the way, so a notification tapped on a cold start still lands on its report.
/// Its own modifier: the root view's body is already near the type checker's limit.
struct CycleReportPresentationModifier: ViewModifier {
    @Environment(SceneState.self) private var scene
    let runtime: AppRuntime
    let isReady: Bool

    func body(content: Content) -> some View {
        content.fullScreenCover(item: Binding(
            get: { isReady ? scene.cycleReportRequest : nil },
            set: { if $0 == nil { scene.cycleReportRequest = nil } }
        )) { request in
            CycleReportView(
                request: request,
                queries: runtime.queries,
                text: runtime.text,
                preferences: runtime.preferences,
                isAuthorized: runtime.plus.isAuthorized,
                onUnlock: {
                    scene.cycleReportRequest = nil
                    scene.paywallSheet = .cycleEndSummaryNotifications
                },
                onClose: { scene.cycleReportRequest = nil }
            )
        }
    }
}

// MARK: - Wording

/// Every sentence a report says, built from one snapshot, so the animated pages,
/// their spoken labels and the plain reading all agree.
@MainActor
struct CycleReportCopy {
    let text: AppText
    let queries: RecordsQueries

    func periodTitle(_ period: CycleReportPeriod) -> String {
        let calendar = queries.recordsGridCalendar
        guard let start = period.startDate(calendar: calendar) else { return period.startDayKey }
        switch period.kind {
        case .month:
            return queries.formatRecordsMonthYear(start)
        case .week:
            let end = period.endDate(calendar: calendar) ?? start
            return OWCText.ltrRange(queries.formatRecordsMonthDay(start), queries.formatRecordsMonthDay(end))
        }
    }

    func hours(_ milliseconds: Int64) -> String { text.formatRelativeDuration(Double(milliseconds)) }
    func days(_ count: Int) -> String { text.t("daysShort", values: ["count": text.formatCount(count)]) }
    func workdays(_ snapshot: CycleReportSnapshot) -> String {
        text.t("recordsWorkdayCount", values: ["count": text.formatCount(snapshot.figures.workdays)])
    }

    func comparisonTitle(_ snapshot: CycleReportSnapshot) -> String {
        text.t(snapshot.period.kind == .week ? "reportCompareWeek" : "reportCompareMonth")
    }

    func comparisonSentence(_ comparison: CycleReportComparison) -> String {
        let delta = comparison.workedDeltaMs
        guard abs(delta) >= 60_000 else { return text.t("reportCompareSame") }
        return text.t(delta > 0 ? "reportCompareMore" : "reportCompareLess", values: [
            "duration": hours(abs(delta)),
        ])
    }

    func income(_ snapshot: CycleReportSnapshot) -> String? {
        snapshot.income.map { text.moneyText($0) }
    }

    /// The facts as label/value pairs, for the reading page and the summary page.
    func facts(_ snapshot: CycleReportSnapshot) -> [(label: String, value: String)] {
        var rows: [(String, String)] = [
            (text.t("reportWorkdays"), text.formatCount(snapshot.figures.workdays)),
            (text.t("recordsWorkedTime"), hours(snapshot.figures.workedMs)),
        ]
        if snapshot.figures.overtimeMs > 0 {
            rows.append((text.t("recordsOvertime"), hours(snapshot.figures.overtimeMs)))
        }
        rows.append((text.t("reportRestDays"), days(snapshot.restDayCount)))
        if snapshot.longestRestRun > 0 {
            rows.append((text.t("reportLongestRest"), days(snapshot.longestRestRun)))
        }
        if let comparison = snapshot.comparison {
            rows.append((comparisonTitle(snapshot), comparisonSentence(comparison)))
        }
        if let income = income(snapshot) {
            rows.append((text.t("reportIncomeTitle"), income))
        }
        return rows
    }

    /// What VoiceOver says for a page: its final state, never a mid-count one.
    func spoken(_ stage: CycleReportStage, snapshot: CycleReportSnapshot) -> String {
        let head = periodTitle(snapshot.period)
        switch stage {
        case .calendar:
            return [head, workdays(snapshot), snapshot.isInProgress ? text.t("reportSoFar") : nil]
                .compactMap { $0 }.joined(separator: ". ")
        case .hours:
            var parts = [text.t("recordsWorkedTime"), hours(snapshot.figures.workedMs)]
            if snapshot.figures.overtimeMs > 0 {
                parts.append(text.t("reportIncludingOvertime", values: ["overtime": hours(snapshot.figures.overtimeMs)]))
            }
            return parts.joined(separator: ". ")
        case .rest:
            guard snapshot.restDayCount > 0 else { return text.t("reportRestNone") }
            return [
                text.t("reportRestDays"), days(snapshot.restDayCount),
                text.t("reportLongestRest"), days(snapshot.longestRestRun),
            ].joined(separator: ". ")
        case .comparison:
            guard let comparison = snapshot.comparison else { return "" }
            return [comparisonTitle(snapshot), comparisonSentence(comparison)].joined(separator: ". ")
        case .income:
            return [text.t("reportIncomeTitle"), income(snapshot) ?? ""].joined(separator: ". ")
        case .summary:
            return ([head] + facts(snapshot).map { "\($0.label), \($0.value)" }).joined(separator: ". ")
        }
    }
}

// MARK: - Reading page

/// The report as plain, scrollable text. It is never gated on an animation.
private struct CycleReportReadingView: View {
    let snapshot: CycleReportSnapshot
    let copy: CycleReportCopy
    let canPlay: Bool
    var onPlay: () -> Void
    var onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(copy.text.t(snapshot.period.kind == .week ? "reportWeekly" : "reportMonthly"))
                            .font(.largeTitle.bold())
                            .foregroundStyle(OWCDesign.primary)
                            .accessibilityAddTraits(.isHeader)
                        Text(copy.periodTitle(snapshot.period))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(OWCDesign.primary)
                        if snapshot.isInProgress {
                            Text(copy.text.t("reportSoFar"))
                                .font(.subheadline)
                                .foregroundStyle(OWCDesign.secondary)
                        }
                    }
                    Spacer(minLength: 12)
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(OWCDesign.control, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(OWCDesign.secondary)
                    .accessibilityLabel(copy.text.t("close"))
                }

                OWCGroupCard {
                    let rows = copy.facts(snapshot)
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(row.label).font(.body).foregroundStyle(OWCDesign.secondary)
                            Spacer(minLength: 8)
                            Text(row.value)
                                .font(.body.weight(.semibold).monospacedDigit())
                                .foregroundStyle(OWCDesign.primary)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .accessibilityElement(children: .combine)
                        if index < rows.count - 1 { Divider().padding(.leading, 16) }
                    }
                }

                OWCGroupCard {
                    ReportCalendarGrid(
                        snapshot: snapshot, queries: copy.queries, text: copy.text,
                        revealed: snapshot.days.count, emphasis: .kinds, isCompact: false, showsLegend: true
                    )
                    .padding(16)
                }

                Text(copy.text.t("reportBasisNote"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    if canPlay {
                        Button(action: onPlay) { Text(copy.text.t("reportReplay")) }
                            .buttonStyle(OWCSecondaryButtonStyle())
                    }
                    Button(action: onClose) { Text(copy.text.t("done")) }
                        .buttonStyle(OWCPrimaryButtonStyle())
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 16)
            .padding(.bottom, OWCDesign.detailBottomInset)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - Player

private struct CycleReportPlayerView: View {
    let player: CycleReportPlayer
    let copy: CycleReportCopy
    var onRead: () -> Void
    var onClose: () -> Void

    private var snapshot: CycleReportSnapshot { player.snapshot }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                stageView
                    .id(player.stageIndex)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 14)),
                        removal: .opacity
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(OWCMotion.phase, value: player.stageIndex)
            controls
        }
        .padding(.horizontal, OWCDesign.pageInset)
        .task(id: player.isPlaying) { await player.run() }
    }

    // One bar per page, filled up to the page now showing.
    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(player.stages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index <= player.stageIndex ? OWCDesign.accent : OWCDesign.control)
                        .frame(height: 3)
                }
            }
            .animation(OWCMotion.selection, value: player.stageIndex)
            .accessibilityHidden(true)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(OWCDesign.secondary)
            .accessibilityLabel(copy.text.t("close"))
        }
        .padding(.top, 8)
    }

    private var controls: some View {
        HStack(spacing: 28) {
            controlButton("backward.end.fill", key: "reportPrevious", disabled: player.stageIndex == 0) {
                player.previous()
            }
            controlButton(player.isPlaying ? "pause.fill" : "play.fill", key: player.isPlaying ? "reportPause" : "reportResume") {
                player.togglePlayback()
            }
            controlButton("forward.end.fill", key: "reportNext", disabled: player.isLastStage) {
                player.next()
            }
            Spacer(minLength: 0)
            Button(action: onRead) {
                Label(copy.text.t("reportRead"), systemImage: "text.alignleft")
                    .font(.subheadline)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(OWCDesign.secondary)
        }
        .padding(.bottom, 12)
    }

    private func controlButton(
        _ symbol: String, key: String, disabled: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? OWCDesign.tertiary : OWCDesign.primary)
        .disabled(disabled)
        .accessibilityLabel(copy.text.t(key))
    }

    @ViewBuilder
    private var stageView: some View {
        let beat = player.beat
        Group {
            switch player.stage {
            case .calendar: calendarStage(beat: beat)
            case .hours: hoursStage(beat: beat)
            case .rest: restStage(beat: beat)
            case .comparison: comparisonStage(beat: beat)
            case .income: incomeStage(beat: beat)
            case .summary: summaryStage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(copy.spoken(player.stage, snapshot: snapshot))
    }

    // Each page makes one point, large; the calendar stays underneath it so the
    // figure always reads as made of the days above.

    private func calendarStage(beat: Int) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            pageHeader(title: copy.periodTitle(snapshot.period), subtitle: copy.workdays(snapshot))
            ReportCalendarGrid(
                snapshot: snapshot, queries: copy.queries, text: copy.text,
                revealed: beat, emphasis: .kinds, isCompact: false, showsLegend: true
            )
        }
    }

    private func hoursStage(beat: Int) -> some View {
        let workDays = snapshot.days.filter { $0.kind == .work }
        let total = max(1, workDays.reduce(Int64(0)) { $0 + $1.workMs + $1.overtimeMs })
        let built = beat >= player.beatCount
        // Count up with the bars, finishing on the figure Records prints, not on
        // the sum of the day columns.
        let risen = workDays.prefix(beat).reduce(Int64(0)) { $0 + $1.workMs + $1.overtimeMs }
        let shown = built
            ? snapshot.figures.workedMs
            : Int64(Double(snapshot.figures.workedMs) * Double(risen) / Double(total))
        return VStack(alignment: .leading, spacing: 20) {
            pageHeader(
                title: copy.text.t("recordsWorkedTime"),
                value: copy.hours(shown),
                subtitle: built && snapshot.figures.overtimeMs > 0
                    ? copy.text.t("reportIncludingOvertime", values: ["overtime": copy.hours(snapshot.figures.overtimeMs)])
                    : nil
            )
            ReportHoursBars(snapshot: snapshot, queries: copy.queries, risen: beat)
        }
    }

    private func restStage(beat: Int) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if snapshot.restDayCount == 0 {
                pageHeader(title: copy.text.t("reportRestNone"))
            } else {
                pageHeader(
                    title: copy.text.t("reportRestDays"),
                    value: beat >= 1 ? copy.days(snapshot.restDayCount) : copy.days(0),
                    subtitle: beat >= 2
                        ? "\(copy.text.t("reportLongestRest")) · \(copy.days(snapshot.longestRestRun))"
                        : nil
                )
            }
            ReportCalendarGrid(
                snapshot: snapshot, queries: copy.queries, text: copy.text,
                revealed: snapshot.days.count, emphasis: beat >= 1 ? .rest : .kinds,
                highlightedRun: beat >= 2 ? longestRun : nil, isCompact: false, showsLegend: false
            )
        }
    }

    private var longestRun: Range<Int>? {
        snapshot.longestRestStart.map { $0..<($0 + snapshot.longestRestRun) }
    }

    private func comparisonStage(beat: Int) -> some View {
        let comparison = snapshot.comparison
        let more = (comparison?.workedDeltaMs ?? 0) > 0
        return VStack(alignment: .leading, spacing: 20) {
            pageHeader(title: copy.comparisonTitle(snapshot))
            HStack(spacing: 12) {
                if abs(comparison?.workedDeltaMs ?? 0) >= 60_000 {
                    Image(systemName: more ? "arrow.up.right" : "arrow.down.right")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(more ? OWCDesign.recordsOvertime : OWCDesign.recordsWork)
                }
                Text(comparison.map(copy.comparisonSentence) ?? "")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(OWCDesign.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(beat >= 1 ? 1 : 0)
            .offset(y: beat >= 1 ? 0 : 10)
            .animation(OWCMotion.reveal, value: beat)
        }
    }

    private func incomeStage(beat: Int) -> some View {
        let income = snapshot.income ?? 0
        return VStack(alignment: .leading, spacing: 20) {
            pageHeader(
                title: copy.text.t("reportIncomeTitle"),
                value: copy.text.moneyText(beat >= 1 ? income : 0),
                subtitle: copy.text.t("reportIncomeNote")
            )
        }
    }

    private var summaryStage: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageHeader(title: copy.periodTitle(snapshot.period), subtitle: snapshot.isInProgress ? copy.text.t("reportSoFar") : nil)
            OWCGroupCard {
                let rows = copy.facts(snapshot)
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.label).font(.subheadline).foregroundStyle(OWCDesign.secondary)
                        Spacer(minLength: 8)
                        Text(row.value)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(OWCDesign.primary)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    if index < rows.count - 1 { Divider().padding(.leading, 16) }
                }
            }
            HStack(spacing: 10) {
                Button { player.replay() } label: { Text(copy.text.t("reportReplay")) }
                    .buttonStyle(OWCSecondaryButtonStyle())
                Button(action: onClose) { Text(copy.text.t("done")) }
                    .buttonStyle(OWCPrimaryButtonStyle())
            }
        }
    }

    private func pageHeader(title: String, value: String? = nil, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(value == nil ? .title.bold() : .headline)
                .foregroundStyle(value == nil ? OWCDesign.primary : OWCDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let value {
                Text(value)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(OWCDesign.primary)
                    .contentTransition(.numericText())
                    .animation(OWCMotion.recordsExpansion, value: value)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Drawings

/// The period as a calendar. `revealed` days have arrived; the rest are not
/// drawn yet, so the grid keeps its size while it fills in.
private struct ReportCalendarGrid: View {
    enum Emphasis { case kinds, rest }

    let snapshot: CycleReportSnapshot
    let queries: RecordsQueries
    let text: AppText
    let revealed: Int
    var emphasis: Emphasis
    var highlightedRun: Range<Int>? = nil
    var isCompact: Bool
    var showsLegend: Bool

    var body: some View {
        let calendar = queries.recordsCalendar
        let blanks = snapshot.period.kind == .month
            ? snapshot.days.first.map { queries.recordsGridLeadingBlanks(before: $0.date) } ?? 0
            : 0
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
        VStack(spacing: 10) {
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(Array(queries.recordsWeekdayGridSymbols().enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(OWCDesign.tertiary)
                }
                ForEach(0..<blanks, id: \.self) { _ in Color.clear.frame(height: 1) }
                ForEach(Array(snapshot.days.enumerated()), id: \.element.id) { index, day in
                    tile(day, index: index, calendar: calendar)
                }
            }
            if showsLegend { legend }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(true)
    }

    private func tile(_ day: CycleReportDay, index: Int, calendar: Calendar) -> some View {
        let shown = index < revealed
        let inRun = highlightedRun?.contains(index) ?? false
        let dimmed = emphasis == .rest && day.kind != .rest
        return RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(fill(for: day))
            .overlay {
                if day.kind == .upcoming {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(OWCDesign.tertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .overlay {
                if inRun {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(OWCDesign.accent, lineWidth: 2.5)
                }
            }
            .overlay {
                Text("\(calendar.component(.day, from: day.date))")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(day.kind == .work ? Color.white : OWCDesign.secondary)
            }
            .aspectRatio(snapshot.period.kind == .week ? 0.8 : 1, contentMode: .fit)
            .opacity(shown ? (dimmed ? 0.3 : 1) : 0)
            .scaleEffect(shown ? 1 : 0.8)
            .animation(OWCMotion.recordsScaleChange, value: revealed)
            .animation(OWCMotion.recordsScaleChange, value: emphasis)
    }

    private func fill(for day: CycleReportDay) -> Color {
        switch day.kind {
        case .work: day.overtimeMs > 0 ? OWCDesign.recordsOvertime : OWCDesign.recordsWork
        case .rest: OWCDesign.control
        case .upcoming: .clear
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(OWCDesign.recordsWork, text.t("recordsWorkRegular"))
            if snapshot.figures.overtimeMs > 0 { legendItem(OWCDesign.recordsOvertime, text.t("recordsOvertime")) }
            legendItem(OWCDesign.control, text.t("recordsRestDay"))
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(OWCDesign.secondary)
    }

    private func legendItem(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(title)
        }
    }
}

/// One column per day, each as tall as the time worked that day, rising in
/// turn. Overtime sits on top in its own colour.
private struct ReportHoursBars: View {
    let snapshot: CycleReportSnapshot
    let queries: RecordsQueries
    let risen: Int

    private static let height: CGFloat = 150

    var body: some View {
        let peak = max(1, snapshot.days.map { $0.workMs + $0.overtimeMs }.max() ?? 1)
        let ordinals = workOrdinals
        HStack(alignment: .bottom, spacing: snapshot.days.count > 10 ? 2 : 6) {
            ForEach(snapshot.days) { day in
                let up = (ordinals[day.dayKey].map { $0 < risen }) ?? false
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    let regular = CGFloat(day.workMs) / CGFloat(peak) * Self.height
                    let overtime = CGFloat(day.overtimeMs) / CGFloat(peak) * Self.height
                    Rectangle().fill(OWCDesign.recordsOvertime)
                        .frame(height: up ? overtime : 0)
                    Rectangle().fill(OWCDesign.recordsWork)
                        .frame(height: up ? regular : 0)
                }
                .frame(maxWidth: .infinity)
                .frame(height: Self.height)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(alignment: .bottom) {
                    // The day's place stays visible before its bar arrives.
                    Capsule().fill(OWCDesign.control).frame(height: 3)
                }
                .animation(OWCMotion.recordsExpansion, value: risen)
            }
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }

    private var workOrdinals: [String: Int] {
        var result: [String: Int] = [:]
        for day in snapshot.days where day.kind == .work {
            result[day.dayKey] = result.count
        }
        return result
    }
}
