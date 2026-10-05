import SwiftUI
import UIKit

/// Weekly, monthly and annual reports (plan 020 §4).
///
/// The period is measured once when the screen opens. The person then decides
/// whether pay is part of this report, and either plays the animated chapters
/// or reads the same facts as plain text. Both read that one
/// `CycleReportSnapshot`, so the numbers cannot differ between chapters or
/// between the two ways of reading.
struct CycleReportView: View {
    let request: CycleReportRequest
    let queries: RecordsQueries
    let text: AppText
    let preferences: PreferencesStore
    let isAuthorized: Bool
    var onUnlock: () -> Void
    var onClose: () -> Void

    private enum Mode: Equatable {
        case loading
        case unavailable
        case empty
        case ready
        case reading
        case playing
    }

    @State private var mode: Mode = .loading
    @State private var includesIncome: Bool
    /// What the period measured to, pay included. Only `visible` is ever drawn.
    @State private var measured: CycleReportSnapshot?
    @State private var visible: CycleReportSnapshot?
    @State private var player: CycleReportPlayer?
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
            switch mode {
            case .playing:
                if let player { CycleReportPlayerView(player: player, copy: copy, onRead: readInstead, onClose: onClose) }
            case .reading:
                ZStack {
                    ReportBackdrop(mood: .finale, time: 0)
                    if let visible {
                        CycleReportReadingView(snapshot: visible, copy: copy, canPlay: animationAvailable,
                                               onPlay: { play() }, onClose: onClose)
                    }
                }
            default:
                ZStack {
                    ReportBackdrop(mood: .dawn, time: 0)
                    setupPage
                }
            }
        }
        .preferredColorScheme(.dark)
        // A full-screen cover does not carry the root's reading direction with it.
        .environment(\.layoutDirection, preferences.layoutDirection)
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player?.pause() }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced, mode == .playing { readInstead() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
            voiceOverRunning = UIAccessibility.isVoiceOverRunning
        }
    }

    // MARK: Setup

    private var setupPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(text.t(period.kind.titleKey).uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.62))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                ReportCloseButton(label: text.t("close"), action: onClose)
            }
            .padding(.top, 8)

            Text(copy.periodTitle(period))
                .font(.system(size: 46, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.top, 28)
            if isInProgress {
                Text(text.t("reportSoFar"))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 4)
            }

            Spacer(minLength: 16)
            if let measured, isAuthorized, mode == .ready {
                ReportTeaser(snapshot: measured, copy: copy)
                    .frame(height: period.kind == .week ? 210 : 250)
                    .padding(.bottom, 8)
            }
            Spacer(minLength: 16)

            if !isAuthorized {
                lockedCard
            } else {
                VStack(spacing: 12) {
                    if preferences.salaryEnabled, mode == .ready { incomeChoice }
                    statusMessage
                    actions
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 20)
    }

    private var lockedCard: some View {
        Button(action: onUnlock) {
            VStack(spacing: 8) {
                Image(systemName: "lock.fill").font(.title2)
                Text(text.t("recordsLockedSummary")).font(.headline)
                Text(text.t("plusSeePlans")).font(.subheadline.weight(.semibold)).foregroundStyle(ReportPalette.orange)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(22)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var incomeChoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(text.t("reportIncludeIncome")).font(.body.weight(.semibold))
                Spacer()
                Toggle(text.t("reportIncludeIncome"), isOn: Binding(get: { includesIncome }, set: setIncluding))
                    .labelsHidden()
                    .tint(ReportPalette.orange)
            }
            Text(text.t("reportIncludeIncomeNote"))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
            ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 8)
        case .unavailable:
            Text(text.t("reportUnavailable")).font(.subheadline).foregroundStyle(.white.opacity(0.7))
        case .empty:
            Text(text.t("reportEmpty")).font(.subheadline).foregroundStyle(.white.opacity(0.7))
        default:
            EmptyView()
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button { prefersReading ? read() : play() } label: {
                Text(text.t(prefersReading ? "reportRead" : "reportPlay"))
            }
            .buttonStyle(ReportPillStyle(prominent: true))
            if animationAvailable {
                Button { prefersReading ? play() : read() } label: {
                    Text(text.t(prefersReading ? "reportPlay" : "reportRead"))
                }
                .buttonStyle(ReportPillStyle(prominent: false))
            }
        }
        .disabled(mode != .ready)
        .opacity(mode == .ready ? 1 : 0.4)
    }

    // MARK: Building

    private func load() async {
        guard isAuthorized else { mode = .ready; return }
        guard let snapshot = await queries.cycleReportSnapshot(for: period) else {
            mode = .unavailable
            return
        }
        measured = snapshot
        mode = snapshot.hasData ? .ready : .empty
#if DEBUG
        if UserDefaults.standard.bool(forKey: "ios.native.qaCycleReportRead"), snapshot.hasData {
            read()
            return
        }
        // `-ios.native.qaCycleReportFrame 2:0.6` plays the report parked on
        // chapter 2 at 60% of its build.
        if let frame = UserDefaults.standard.string(forKey: "ios.native.qaCycleReportFrame"), snapshot.hasData {
            let parts = frame.split(separator: ":").compactMap { Double($0) }
            if parts.count == 2 {
                play()
                player?.debugSeek(stage: Int(parts[0]), buildFraction: parts[1])
            }
        } else if snapshot.hasData, UserDefaults.standard.bool(forKey: "ios.native.qaCycleReportAutoplay") {
            play()
        }
#endif
    }

    /// Dropped here, once, rather than hidden by each chapter: a report that was
    /// not asked to show pay never carries it.
    private func settle() -> CycleReportSnapshot? {
        guard let measured else { return nil }
        let result = includesIncome ? measured : measured.withoutIncome()
        visible = result
        return result
    }

    private func play() {
        guard let snapshot = settle() else { return }
        player = CycleReportPlayer(snapshot: snapshot)
        mode = .playing
    }

    private func read() {
        guard settle() != nil else { return }
        mode = .reading
    }

    private func readInstead() {
        player?.pause()
        mode = .reading
    }
}

// MARK: - Controls

struct ReportCloseButton: View {
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.14), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct ReportPillStyle: ButtonStyle {
    let prominent: Bool
    /// On the finale's warm light the orange pill would disappear; it turns cream.
    var onWarm = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(prominent ? (onWarm ? ReportPalette.plum : Color.white) : Color.white.opacity(0.95))
            .frame(maxWidth: .infinity, minHeight: 54)
            .background {
                if prominent {
                    Capsule().fill(onWarm
                        ? AnyShapeStyle(ReportPalette.cream)
                        : AnyShapeStyle(LinearGradient(colors: [ReportPalette.orange, ReportPalette.orangeDeep], startPoint: .top, endPoint: .bottom)))
                } else {
                    Capsule().fill(.white.opacity(onWarm ? 0.22 : 0.12))
                        .overlay(Capsule().strokeBorder(.white.opacity(onWarm ? 0.35 : 0), lineWidth: 1))
                }
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The finished week, month or year, rising once beside the buttons, so the setup
/// page already promises what the report is about.
private struct ReportTeaser: View {
    let snapshot: CycleReportSnapshot
    private let layout: ReportStripScene.Layout
    private let monthLabels: [String]
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(snapshot: CycleReportSnapshot, copy: CycleReportCopy) {
        self.snapshot = snapshot
        monthLabels = copy.monthLabels(snapshot)
        layout = ReportStripScene.Layout(snapshot: snapshot, queries: copy.queries)
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let elapsed = reduceMotion ? 9 : timeline.date.timeIntervalSince(start) - 0.25
            if snapshot.period.kind == .year {
                ReportMetricBars(values: snapshot.months.map { Double($0.figures.workedMs) },
                                 labels: monthLabels, build: min(1, max(0, elapsed / 2)))
            } else {
                ReportStripScene.art(snapshot: snapshot, layout: layout, state: .teaser(elapsed))
            }
        }
        .accessibilityHidden(true)
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
        content
#if DEBUG
            // Visual QA: `-ios.native.qaCycleReport week|month|year` seeds
            // sample records and opens that report.
            .task {
                let defaults = UserDefaults.standard
                guard let raw = defaults.string(forKey: "ios.native.qaCycleReport"),
                      let kind = CycleReportKind(rawValue: raw) else { return }
                defaults.removeObject(forKey: "ios.native.qaCycleReport")
                runtime.shifts.disableAutomaticReviewPrompt()
                scene.showsReleaseNotes = false
                _ = await runtime.debug.debugSeedSampleRecords().value
                let queries = runtime.queries
                let calendar = queries.recordsGridCalendar
                var period = queries.reportPeriod(kind, containing: .now)
                if !defaults.bool(forKey: "ios.native.qaCycleReportCurrentPeriod") {
                    period = period.previous(calendar: calendar) ?? period
                }
                scene.openCycleReport(CycleReportRequest(period: period))
            }
#endif
            .fullScreenCover(item: Binding(
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

/// Every sentence a report says, built from one snapshot, so the animated
/// chapters, their spoken labels and the plain reading all agree.
@MainActor
struct CycleReportCopy {
    let text: AppText
    let queries: RecordsQueries

    func periodTitle(_ period: CycleReportPeriod) -> String {
        let calendar = queries.recordsGridCalendar
        guard let start = period.startDate(calendar: calendar) else { return period.startDayKey }
        switch period.kind {
        case .year:
            return text.formatYear(calendar.component(.year, from: start))
        case .month:
            return queries.formatRecordsMonthYear(start)
        case .week:
            let end = period.endDate(calendar: calendar) ?? start
            return OWCText.ltrRange(queries.formatRecordsMonthDay(start), queries.formatRecordsMonthDay(end))
        }
    }

    func hours(_ milliseconds: Int64) -> String { text.formatRelativeDuration(Double(milliseconds)) }
    func days(_ count: Int) -> String { text.t("daysShort", values: ["count": text.formatCount(count)]) }
    /// Whole and half days, as leave is kept.
    func leaveDays(halfDays: Int) -> String { text.formatDays(Double(halfDays) / 2) }
    func workdays(_ snapshot: CycleReportSnapshot) -> String {
        text.t("recordsWorkdayCount", values: ["count": text.formatCount(snapshot.figures.workdays)])
    }
    func headline(_ snapshot: CycleReportSnapshot) -> String {
        switch snapshot.headline {
        case .fullStretch:
            if let baseline = snapshot.baseline, baseline.deltaMs > 0 {
                return text.t(snapshot.headline.titleKey, values: ["duration": hours(baseline.deltaMs)])
            }
            return text.t("reportHeadlineOvertime", values: ["duration": hours(snapshot.figures.overtimeMs)])
        case .lighter:
            return text.t(snapshot.headline.titleKey, values: ["duration": hours(abs(snapshot.baseline?.deltaMs ?? 0))])
        case .roomToBreathe:
            return text.t(snapshot.headline.titleKey, values: ["count": text.formatCount(snapshot.restDayCount)])
        default:
            return text.t(snapshot.headline.titleKey)
        }
    }
    func weekday(_ date: Date) -> String { queries.formatRecordsWeekdayShort(date) }
    func weekdayLabels(_ snapshot: CycleReportSnapshot) -> [String] {
        snapshot.period.kind == .week ? snapshot.days.map { weekday($0.date) } : []
    }

    /// Pay is shown only when the person chose it for this report, so it is
    /// formatted without the global mask: that mask would hide the very number
    /// they asked to see.
    func money(_ value: Double?) -> String { text.formatMoney(value) }

    // MARK: Against your usual

    func baselineTitle(_ snapshot: CycleReportSnapshot) -> String {
        guard let baseline = snapshot.baseline else { return "" }
        switch baseline.kind {
        case .usual(let periods):
            return text.t(snapshot.period.kind == .week ? "reportUsualBasisWeek" : "reportUsualBasisMonth",
                          values: ["count": text.formatCount(periods)])
        case .previous:
            return text.t(snapshot.period.kind == .week ? "reportCompareWeek" : "reportCompareMonth")
        }
    }

    /// Label of the baseline's own bar.
    func baselineBarLabel(_ snapshot: CycleReportSnapshot) -> String {
        guard let baseline = snapshot.baseline else { return "" }
        switch baseline.kind {
        case .usual: return text.t(snapshot.period.kind == .week ? "reportUsualWeek" : "reportUsualMonth")
        case .previous:
            let calendar = queries.recordsGridCalendar
            return snapshot.period.previous(calendar: calendar).map(periodTitle) ?? ""
        }
    }

    func baselineSentence(_ snapshot: CycleReportSnapshot) -> String {
        guard let baseline = snapshot.baseline else { return "" }
        let delta = baseline.deltaMs
        guard abs(delta) >= 60_000 else {
            return text.t(baseline.kind == .previous ? "reportCompareSame" : "reportUsualSame")
        }
        let values = ["duration": hours(abs(delta))]
        switch baseline.kind {
        case .usual:
            return delta > 0 ? text.t("reportUsualMore", values: values) : text.t("reportUsualLess", values: values)
        case .previous:
            return delta > 0 ? text.t("reportCompareMore", values: values) : text.t("reportCompareLess", values: values)
        }
    }

    // MARK: Overtime

    func overtimeDays(_ overtime: CycleReportOvertime) -> String {
        text.t("reportOvertimeDays", values: ["count": text.formatCount(overtime.dayCount)])
    }

    func overtimePeak(_ overtime: CycleReportOvertime, kind: CycleReportKind) -> String {
        let peak = overtime.longestDay
        let day = kind == .week ? weekday(peak.date) : queries.formatRecordsMonthDay(peak.date)
        return text.t("reportOvertimePeak", values: ["day": day, "duration": hours(peak.overtimeMs)])
    }

    func monthLabels(_ snapshot: CycleReportSnapshot) -> [String] {
        snapshot.months.map { month in
            month.period.startDate(calendar: queries.recordsGridCalendar).map {
                text.formatCount(queries.recordsGridCalendar.component(.month, from: $0))
            } ?? ""
        }
    }

    func dayLabels(_ days: [CycleReportDay], kind: CycleReportKind) -> [String] {
        days.enumerated().map { index, day in
            if kind == .week { return weekday(day.date) }
            guard index == 0 || index == days.count - 1 || (index + 1) % 5 == 0 else { return "" }
            return text.formatCount(queries.recordsGridCalendar.component(.day, from: day.date))
        }
    }

    // MARK: Looking ahead

    func aheadTitleKey(_ ahead: CycleReportAhead) -> String {
        if ahead.nextBreak != nil { return ahead.isHistorical ? "reportAheadHistoricalTitle" : "reportAheadTitle" }
        return ahead.leaveRemainingHalfDays != nil ? "reportLeaveLeft" : "reportLeaveUsed"
    }

    func aheadHero(_ ahead: CycleReportAhead) -> String? {
        guard let next = ahead.nextBreak else { return nil }
        if ahead.isHistorical { return days(next.length) }
        return next.daysAway == 1 ? text.t("reportAheadTomorrow")
            : text.t("reportAheadInDays", values: ["days": days(next.daysAway)])
    }

    func aheadBreak(_ ahead: CycleReportAhead) -> String? {
        guard let next = ahead.nextBreak else { return nil }
        if ahead.isHistorical {
            let end = queries.recordsGridCalendar.date(byAdding: .day, value: next.length - 1, to: next.startDate) ?? next.startDate
            return OWCText.ltrRange(queries.formatRecordsMonthDay(next.startDate), queries.formatRecordsMonthDay(end))
        }
        return text.t("reportAheadBreak", values: [
            "length": days(next.length), "date": queries.formatRecordsMonthDay(next.startDate),
        ])
    }

    // MARK: Focus

    func focusBest(_ focus: CycleReportFocus, snapshot: CycleReportSnapshot) -> String? {
        guard snapshot.days.indices.contains(focus.bestDayIndex) else { return nil }
        let day = snapshot.days[focus.bestDayIndex]
        return text.t("reportFocusBest", values: [
            "day": snapshot.period.kind == .week ? weekday(day.date) : queries.formatRecordsMonthDay(day.date),
            "count": text.formatCount(focus.perDay[focus.bestDayIndex]),
        ])
    }

    // MARK: Facts and speech

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
        if snapshot.baseline != nil {
            rows.append((baselineTitle(snapshot), baselineSentence(snapshot)))
        }
        if let ahead = snapshot.ahead {
            if let next = aheadBreak(ahead) {
                let detail = ahead.isHistorical ? "\(aheadHero(ahead) ?? "") · \(next)" : next
                rows.append((text.t(aheadTitleKey(ahead)), detail))
            }
            if let left = ahead.leaveRemainingHalfDays { rows.append((text.t("reportLeaveLeft"), leaveDays(halfDays: left))) }
            if ahead.leaveUsedHalfDays > 0 { rows.append((text.t("reportLeaveUsed"), leaveDays(halfDays: ahead.leaveUsedHalfDays))) }
        }
        if snapshot.period.kind == .year {
            rows.append((text.t("reportLeaveUsed"), leaveDays(halfDays: snapshot.leaveUsedHalfDays)))
        }
        if let focus = snapshot.focus {
            rows.append((text.t("reportFocusRounds"), text.formatCount(focus.rounds)))
            rows.append((text.t("reportFocusDuration"), hours(focus.focusedMs)))
        }
        if let pay = snapshot.pay {
            rows.append((text.t("reportIncomeTitle"), money(pay.total)))
            if let perHour = pay.perHour { rows.append((text.t("reportPerHour"), money(perHour))) }
            if let extra = pay.overtimeExtra { rows.append((text.t("reportIncomeExtra"), money(extra))) }
        }
        return rows
    }

    /// What VoiceOver says for a chapter: its final state, never a mid-count one.
    func spoken(_ stage: CycleReportStage, snapshot: CycleReportSnapshot) -> String {
        let head = periodTitle(snapshot.period)
        switch stage {
        case .calendar:
            return [head, headline(snapshot), workdays(snapshot), snapshot.isInProgress ? text.t("reportSoFar") : nil]
                .compactMap { $0 }.joined(separator: ". ")
        case .hours:
            var parts = [text.t("recordsWorkedTime"), hours(snapshot.figures.workedMs)]
            if snapshot.figures.overtimeMs > 0 {
                parts.append(text.t("reportIncludingOvertime", values: ["overtime": hours(snapshot.figures.overtimeMs)]))
            }
            return parts.joined(separator: ". ")
        case .overtime:
            var parts = [text.t("recordsOvertime"), hours(snapshot.figures.overtimeMs)]
            if let overtime = snapshot.overtime {
                parts += [overtimeDays(overtime), overtimePeak(overtime, kind: snapshot.period.kind)]
            }
            return parts.joined(separator: ". ")
        case .baseline:
            return [baselineTitle(snapshot), baselineSentence(snapshot)].joined(separator: ". ")
        case .rest:
            var parts = snapshot.restDayCount > 0
                ? [text.t("reportRestDays"), days(snapshot.restDayCount),
                   text.t("reportLongestRest"), days(snapshot.longestRestRun)]
                : [text.t("reportRestNone")]
            if snapshot.period.kind == .year {
                parts += [text.t("reportLeaveUsed"), leaveDays(halfDays: snapshot.leaveUsedHalfDays)]
            }
            return parts.joined(separator: ". ")
        case .ahead:
            guard let ahead = snapshot.ahead else { return "" }
            var parts: [String] = []
            if let hero = aheadHero(ahead) { parts.append("\(text.t(aheadTitleKey(ahead))) \(hero)") }
            if let next = aheadBreak(ahead) { parts.append(next) }
            if let left = ahead.leaveRemainingHalfDays { parts.append("\(text.t("reportLeaveLeft")) \(leaveDays(halfDays: left))") }
            if ahead.leaveUsedHalfDays > 0 { parts.append("\(text.t("reportLeaveUsed")) \(leaveDays(halfDays: ahead.leaveUsedHalfDays))") }
            return parts.joined(separator: ". ")
        case .focus:
            guard let focus = snapshot.focus else { return "" }
            var parts = [text.t("reportFocusRounds"), text.formatCount(focus.rounds), text.t("reportFocusDuration"), hours(focus.focusedMs)]
            if let best = focusBest(focus, snapshot: snapshot) { parts.append(best) }
            if let icon = focus.topIcon { parts.append("\(text.t("reportFocusTop")) \(text.t(icon.titleKey))") }
            return parts.joined(separator: ". ")
        case .income:
            guard let pay = snapshot.pay else { return "" }
            var parts = [text.t("reportIncomeTitle"), money(pay.total)]
            if let perHour = pay.perHour { parts.append("\(text.t("reportPerHour")) \(money(perHour))") }
            if let extra = pay.overtimeExtra { parts.append("\(text.t("reportIncomeExtra")) \(money(extra))") }
            parts.append(text.t("reportIncomeNote"))
            return parts.joined(separator: ". ")
        case .summary:
            return ([head] + facts(snapshot).map { "\($0.label), \($0.value)" }).joined(separator: ". ")
        }
    }
}

// MARK: - Reading page

/// The report as plain, scrollable text. It is never gated on an animation.
struct CycleReportReadingView: View {
    let snapshot: CycleReportSnapshot
    let copy: CycleReportCopy
    let canPlay: Bool
    var onPlay: () -> Void
    var onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(copy.text.t(snapshot.period.kind.titleKey).uppercased())
                            .font(.caption.weight(.bold)).tracking(1.6)
                            .foregroundStyle(.white.opacity(0.62))
                            .accessibilityAddTraits(.isHeader)
                        Text(copy.periodTitle(snapshot.period))
                            .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                            .foregroundStyle(.white)
                        if snapshot.isInProgress {
                            Text(copy.text.t("reportSoFar")).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    Spacer(minLength: 12)
                    ReportCloseButton(label: copy.text.t("close"), action: onClose)
                }

                VStack(spacing: 0) {
                    let rows = copy.facts(snapshot)
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(row.label).font(.body).foregroundStyle(.white.opacity(0.68))
                            Spacer(minLength: 8)
                            Text(row.value)
                                .font(.body.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .accessibilityElement(children: .combine)
                        if index < rows.count - 1 { Divider().overlay(.white.opacity(0.12)).padding(.leading, 18) }
                    }
                }
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                if snapshot.period.kind == .year {
                    monthlyReading
                } else {
                    ReportStripScene.art(snapshot: snapshot, layout: .init(snapshot: snapshot, queries: copy.queries), state: .settled)
                        .frame(height: snapshot.period.kind == .week ? 240 : 300)
                        .padding(18)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }

                Text(copy.text.t("reportBasisNote"))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    Button(action: onClose) { Text(copy.text.t("done")) }
                        .buttonStyle(ReportPillStyle(prominent: true))
                    if canPlay {
                        Button(action: onPlay) { Text(copy.text.t("reportPlay")) }
                            .buttonStyle(ReportPillStyle(prominent: false))
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var monthlyReading: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(copy.text.t("reportMonthlyTrend")).font(.headline).accessibilityAddTraits(.isHeader)
            ForEach(snapshot.months, id: \.period) { month in
                VStack(alignment: .leading, spacing: 6) {
                    Text(copy.periodTitle(month.period)).font(.subheadline.weight(.semibold))
                    Text(verbatim: "\(copy.text.t("recordsWorkedTime")) · \(copy.hours(month.figures.workedMs))")
                    Text(verbatim: "\(copy.text.t("recordsOvertime")) · \(copy.hours(month.figures.overtimeMs))")
                    Text(verbatim: "\(copy.text.t("reportRestDays")) · \(copy.days(month.restDayCount))")
                    if month.focusRounds > 0 {
                        Text(verbatim: "\(copy.text.t("reportFocusRounds")) · \(copy.text.formatCount(month.focusRounds))")
                    }
                    if let income = month.figures.income {
                        Text(verbatim: "\(copy.text.t("reportIncomeTitle")) · \(copy.money(income))")
                    }
                }
                .font(.footnote).foregroundStyle(.white.opacity(0.8))
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
