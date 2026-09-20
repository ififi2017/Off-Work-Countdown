import SwiftUI

/// One civil day, read from midnight to midnight.
///
/// The week and the month compare days; this page explains one. It has a
/// single conclusion — the waking time that was yours — and everything under
/// it is the account of where the rest went, never a second conclusion.
struct RecordsDayCanvasView: View {
    @Environment(SceneState.self) private var scene
    let records: RecordCoordinator
    let queries: RecordsQueries
    let actions: RecordsActions
    let preferences: PreferencesStore
    let focus: FocusStore
    let text: AppText
    let hours: ScheduleHoursConfiguration
    let dayKey: String

    @State private var model: RecordsDayCanvasModel?
    @State private var isLoading = true
    @State private var choosesShift = false
    @State private var nowTick = Date()
    @Environment(\.scenePhase) private var scenePhase

    private struct LoadRequest: Equatable {
        var dayKey: String
        var revision: UInt64
        var hours: ScheduleHoursConfiguration
        var timeZone: String
        var authorized: Bool
        var minute: Int
    }

    private var loadRequest: LoadRequest {
        .init(dayKey: dayKey, revision: records.contentRevision,
              hours: hours, timeZone: preferences.recordsTimeZone.identifier,
              authorized: queries.plus.isAuthorized, minute: Int(nowTick.timeIntervalSince1970 / 60))
    }

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let model {
                    if model.isLocked {
                        RecordsLockedDayCard(text: text) { scene.paywallSheet = .charts }
                    } else {
                        band(model)
                        conclusion(model)
                        segments(model)
                        observations(model)
                        RecordsFocusHistoryCard(focus: focus, text: text, dayKey: dayKey)
                        conflictCard
                        editEntry(model)
                    }
                } else if !isLoading {
                    OWCGroupCard {
                        Text(text.t("recordsNoObservations"))
                            .font(.body)
                            .foregroundStyle(OWCDesign.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 14)
            .padding(.bottom, OWCDesign.detailBottomInset)
        }
        .background(OWCDesign.page)
        // The two iPad and landscape shells decide their title from the tab,
        // so this page has to say its own name in all three navigation chromes.
        .navigationTitle(queries.formatRecordsDayTitle(dayKey: dayKey))
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: loadRequest) { await load() }
        // A retrospective page is not a countdown. The now line advances on the
        // minute, and only while the page can actually be seen.
        .onReceive(
            Timer.publish(every: 15, on: .main, in: .common).autoconnect()
        ) { value in
            guard scenePhase == .active, model?.isToday == true else { return }
            if Int(value.timeIntervalSince1970 / 60) != Int(nowTick.timeIntervalSince1970 / 60) {
                nowTick = value
            }
        }
        .confirmationDialog(
            text.t("recordsChooseShift"),
            isPresented: $choosesShift,
            titleVisibility: .visible
        ) {
            ForEach(model?.editableShifts ?? []) { shift in
                Button(shiftLabel(shift)) { scene.openDayEditor(dayKey: shift.anchorDayKey, actions: actions, queries: queries) }
            }
            Button(text.t("cancel"), role: .cancel) {}
        }
    }

    private var subtitle: String {
        guard let model else { return "" }
        return text.t(model.source.titleKey)
    }

    private func load() async {
        isLoading = true
        let next = await queries.recordsDayCanvas(dayKey: dayKey)
        guard !Task.isCancelled else { return }
        model = next
        isLoading = false
    }

    // MARK: - The band

    private func band(_ model: RecordsDayCanvasModel) -> some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 8) {
                RecordsDayBand(queries: queries, text: text, model: model)
                axis(model)
                if model.projectionStartsAtMs != nil {
                    Text(text.t("recordsSourceAfterNow"))
                        .font(.caption)
                        .foregroundStyle(OWCDesign.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
    }

    /// Midnight, six, noon, six, midnight — read in the records time zone, and
    /// laid out against the day's real length so a 23-hour day is not stretched
    /// back to 24.
    private func axis(_ model: RecordsDayCanvasModel) -> some View {
        let total = model.dayEnd.timeIntervalSince(model.dayStart)
        let calendar = preferences.recordsCalendar
        return GeometryReader { proxy in
            ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                // Built from calendar components, not from elapsed seconds: on
                // a 23-hour day six hours after midnight is 07:00 on the wall,
                // and on a 25-hour day the closing tick is next midnight rather
                // than something an hour short of the right edge.
                let moment = hour == 24
                    ? model.dayEnd
                    : calendar.date(bySettingHour: hour, minute: 0, second: 0, of: model.dayStart)
                        ?? model.dayStart.addingTimeInterval(Double(hour) * 3_600)
                let offset = total > 0
                    ? min(1, max(0, moment.timeIntervalSince(model.dayStart) / total))
                    : 0
                Text(queries.formatRecordsTime(moment))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize()
                    .position(
                        x: min(proxy.size.width - 14, max(14, proxy.size.width * offset)),
                        y: proxy.size.height / 2
                    )
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    // MARK: - The one conclusion

    private func conclusion(_ model: RecordsDayCanvasModel) -> some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(text.t("recordsFreeAwake"))
                    .font(.subheadline)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(text.formatRelativeDuration(Double(model.wakingFreeMs)))
                        .font(.largeTitle.weight(.semibold).monospacedDigit())
                        .foregroundStyle(OWCDesign.primary)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(text.formatPercent(model.wakingFreeShare * 100))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(OWCDesign.secondary)
                        .contentTransition(.numericText())
                        .accessibilityLabel(text.t("recordsShareOfDay"))
                        .accessibilityValue(text.formatPercent(model.wakingFreeShare * 100))
                }
                Text(text.t("recordsFreeAwakeFootnote"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - The account

    private func segments(_ model: RecordsDayCanvasModel) -> some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(text.t("recordsDaySegments"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OWCDesign.secondary)
                ForEach(model.intervals) { interval in
                    RecordsDayIntervalRow(
                        queries: queries,
                        text: text,
                        interval: interval,
                        daySource: model.source
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    @ViewBuilder
    private func observations(_ model: RecordsDayCanvasModel) -> some View {
        let items = queries.observations(on: model.dayStart)
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(text.t("recordsObservations"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OWCDesign.secondary)
                if items.isEmpty {
                    Text(text.t("recordsNoObservations"))
                        .font(.body)
                        .foregroundStyle(OWCDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(items) { item in
                        Text(observationLabel(item))
                            .font(.callout)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private func observationLabel(_ item: WorkObservation) -> String {
        let kind = switch item.kind {
        case .timerSurfaceFirstSeen: text.t("recordsObservedFirstSeen")
        case .countdownStarted: text.t("recordsObservedStarted")
        case .countdownStopped: text.t("recordsObservedStopped")
        case .overtimeDeclared: text.t("recordsObservedOvertime")
        }
        return "\(queries.formatRecordsTime(item.occurredAt)) · \(kind)"
    }

    /// A data problem is explained on its own terms and gets its own way out.
    /// It is never folded into a Plus message.
    @ViewBuilder
    private var conflictCard: some View {
        if let conflict = queries.recordsConflict(forDayKey: dayKey) {
            OWCGroupCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(text.t("recordsConflictCopy"))
                        .font(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Button(text.t("recordsRestoreConflict")) {
                        Task { await records.restoreConflict(conflict) }
                    }
                    .font(.body.weight(.semibold))
                    .frame(minHeight: 44)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
    }

    /// A plan, a projection or a locked day has no original input to open, so
    /// it gets an honest sentence instead of a button that would fail on tap.
    @ViewBuilder
    private func editEntry(_ model: RecordsDayCanvasModel) -> some View {
        if !queries.plus.isAuthorized {
            Text(text.t("recordsEditPlusHint"))
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        } else if !model.editableShifts.isEmpty {
            OWCGroupCard {
                Button {
                    if model.editableShifts.count == 1 {
                        scene.openDayEditor(dayKey: model.editableShifts[0].anchorDayKey, actions: actions, queries: queries)
                    } else {
                        choosesShift = true
                    }
                } label: {
                    OWCRow(icon: "pencil", title: text.t("recordsEditDay"), isLast: true) {
                        OWCDetailAccessory(text: nil)
                    }
                }
                .buttonStyle(OWCRowButtonStyle())
            }
        }
    }

    private func shiftLabel(_ shift: RecordsDayEditableShift) -> String {
        guard shift.hasHours else {
            return queries.formatRecordsDayTitle(dayKey: shift.anchorDayKey)
        }
        return OWCText.ltrRange(
            queries.formatRecordsTime(Date(timeIntervalSince1970: shift.startAtMs / 1_000)),
            queries.formatRecordsTime(Date(timeIntervalSince1970: shift.endAtMs / 1_000))
        )
    }
}

/// The 24-hour strip.
///
/// The model has already cut the day out of every shift that crosses it, so
/// this only paints: the intervals tile the strip exactly, and their order is
/// the order VoiceOver reads.
struct RecordsDayBand: View {
    let queries: RecordsQueries
    let text: AppText
    let model: RecordsDayCanvasModel
    @State private var selectedIntervalID: String?
    private var selectedInterval: RecordsDayInterval? {
        model.intervals.first { $0.id == selectedIntervalID }
            ?? model.intervals.first { $0.kind == .work }
            ?? model.intervals.first
    }
    @Environment(\.accessibilityDifferentiateWithoutColor) private var withoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Reserve the tallest description so changing intervals never moves the strip.
            ZStack(alignment: .leading) {
                ForEach(model.intervals) { interval in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "\(text.t(interval.kind.titleKey)) · \(range(of: interval))")
                            .fontWeight(.medium)
                        Text([
                            text.formatRelativeDuration(Double(interval.durationMs)),
                            text.formatPercent(percent(of: interval)),
                            text.t(interval.sourceKey),
                        ].joined(separator: " · "))
                        .foregroundStyle(OWCDesign.secondary)
                    }
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(selectedInterval?.id == interval.id ? 1 : 0)
                    .accessibilityHidden(selectedInterval?.id != interval.id)
                }
            }
            strip.frame(height: 44)
        }
        .animation(reduceMotion ? nil : OWCMotion.selection, value: selectedInterval?.id)
    }

    private var strip: some View {
        let total = model.dayEnd.timeIntervalSince(model.dayStart) * 1_000
        return GeometryReader { proxy in
            ZStack {
                HStack(spacing: 0) {
                    ForEach(Array(model.intervals.enumerated()), id: \.element.id) { index, interval in
                        let shape = UnevenRoundedRectangle(
                            cornerRadii: RectangleCornerRadii(
                                topLeading: index == 0 ? 10 : 0,
                                bottomLeading: index == 0 ? 10 : 0,
                                bottomTrailing: index == model.intervals.count - 1 ? 10 : 0,
                                topTrailing: index == model.intervals.count - 1 ? 10 : 0
                            ),
                            style: .continuous
                        )
                        shape
                            .fill(interval.kind.owcColor)
                            .owcEstimated(
                                interval.source.isEstimated,
                                tint: .white,
                                spacing: 4
                            )
                            .clipShape(shape)
                            .frame(width: width(of: interval, total: total, in: proxy.size.width), height: barHeight)
                            .overlay {
                                if selectedInterval?.id == interval.id {
                                    shape.strokeBorder(OWCDesign.primary, lineWidth: 2)
                                }
                            }
                    }
                }
                .frame(maxHeight: .infinity)
                .environment(\.layoutDirection, .leftToRight)

                if let nowAtMs = model.nowAtMs, total > 0 {
                    let offset = (nowAtMs - model.dayStart.timeIntervalSince1970 * 1_000) / total
                    Rectangle()
                        .fill(OWCDesign.accent)
                        .frame(width: 2, height: barHeight)
                        .position(
                            x: min(proxy.size.width - 1, max(1, proxy.size.width * offset)),
                            y: proxy.size.height / 2
                        )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    selectInterval(at: value.location.x, width: proxy.size.width, total: total)
                }
            )
        }
        .background {
            Capsule()
                .fill(OWCDesign.control)
                .frame(height: barHeight)
        }
        .overlay {
            Capsule()
                .stroke(OWCDesign.separator, lineWidth: withoutColor ? 1 : 0.5)
                .frame(height: barHeight)
        }
        .animation(reduceMotion ? nil : OWCMotion.selection, value: selectedInterval?.id)
        // The picture is for the eye; VoiceOver gets the ordered intervals as
        // words, never a list of pixels or sampling buckets.
        .accessibilityRepresentation {
            VStack {
                ForEach(model.intervals) { interval in
                    Button(RecordsDayIntervalRow.spokenLabel(interval, queries: queries, text: text)) {
                        selectedIntervalID = interval.id
                    }
                    .accessibilityAddTraits(selectedInterval?.id == interval.id ? .isSelected : [])
                }
            }
        }
    }

    private var barHeight: CGFloat { 26 }

    private func selectInterval(at x: CGFloat, width: CGFloat, total: Double) {
        guard width > 0, total > 0 else { return }
        let lower = model.dayStart.timeIntervalSince1970 * 1_000
        let moment = lower + Double(min(width, max(0, x)) / width) * total
        selectedIntervalID = (model.intervals.first {
            $0.startAtMs <= moment && moment < $0.endAtMs
        } ?? model.intervals.last)?.id
    }

    private func range(of interval: RecordsDayInterval) -> String {
        OWCText.ltrRange(
            queries.formatRecordsTime(Date(timeIntervalSince1970: interval.startAtMs / 1_000)),
            queries.formatRecordsTime(Date(timeIntervalSince1970: interval.endAtMs / 1_000))
        )
    }

    private func percent(of interval: RecordsDayInterval) -> Double {
        guard model.allocation.dayLengthMs > 0 else { return 0 }
        return Double(interval.durationMs) / Double(model.allocation.dayLengthMs) * 100
    }

    private func width(
        of interval: RecordsDayInterval,
        total: Double,
        in available: CGFloat
    ) -> CGFloat {
        guard total > 0 else { return 0 }
        return max(0, available * CGFloat((interval.endAtMs - interval.startAtMs) / total))
    }
}

/// One row of the account: when it ran, what it was, how long, and where the
/// app got it. This is also the full text alternative to the band above.
struct RecordsDayIntervalRow: View {
    let queries: RecordsQueries
    let text: AppText
    let interval: RecordsDayInterval
    /// What the whole day is. A row only names its own source when it differs
    /// — six rows all repeating "you recorded this" under a header that
    /// already says so is noise, not provenance. VoiceOver still hears it.
    var daySource: RecordsDaySource?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(interval.kind.owcColor)
                .owcEstimated(interval.source.isEstimated, tint: .white, spacing: 3, lineWidth: 0.8)
                .clipShape(Circle())
                .frame(width: 9, height: 9)
                .alignmentGuide(.firstTextBaseline) { $0.height - 1 }
            VStack(alignment: .leading, spacing: 2) {
                Text(range)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(OWCDesign.primary)
                if interval.source != daySource {
                    Text(text.t(interval.sourceKey))
                        .font(.caption)
                        .foregroundStyle(OWCDesign.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(text.t(interval.kind.titleKey))
                    .font(.callout)
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(text.formatRelativeDuration(Double(interval.durationMs)))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(OWCDesign.primary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenLabel(interval, queries: queries, text: text))
    }

    private var range: String {
        OWCText.ltrRange(
            queries.formatRecordsTime(Date(timeIntervalSince1970: interval.startAtMs / 1_000)),
            queries.formatRecordsTime(Date(timeIntervalSince1970: interval.endAtMs / 1_000))
        )
    }

    static func spokenLabel(_ interval: RecordsDayInterval, queries: RecordsQueries, text: AppText) -> String {
        let start = queries.formatRecordsTime(Date(timeIntervalSince1970: interval.startAtMs / 1_000))
        let end = queries.formatRecordsTime(Date(timeIntervalSince1970: interval.endAtMs / 1_000))
        return [
            OWCText.ltrRange(start, end),
            text.t(interval.kind.titleKey),
            text.formatRelativeDuration(Double(interval.durationMs)),
            text.t(interval.sourceKey),
        ].joined(separator: ", ")
    }
}

/// The locked day, in the order 013 asks for: what it is, that nothing is
/// being lost, and only then the way to unlock it.
struct RecordsLockedDayCard: View {
    let text: AppText
    var onUnlock: () -> Void

    var body: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(text.t("recordsLockedDay"), systemImage: "lock.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(OWCDesign.primary)
                Text(text.t("recordsLockedKeepsSaving"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(text.t("plusSeePlans"), action: onUnlock)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(OWCDesign.accent)
                    .frame(minHeight: 44)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }
}

/// The focus sessions that ran on a day. Lifted out of the old day detail card
/// unchanged, so the day canvas is the one place that shows them.
struct RecordsFocusHistoryCard: View {
    let focus: FocusStore
    let text: AppText
    let dayKey: String

    var body: some View {
        let sessions = Self.withoutSyncCopies(focus.focusSessions(forDayKey: dayKey))
        if !sessions.isEmpty {
            OWCGroupCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label(text.t("focusHistory"), systemImage: FocusTaskIcon.focus.systemName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(OWCDesign.secondary)
                    ForEach(sessions) { session in
                        row(session)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
    }

    /// Before sessions had derived identities, two devices each started the
    /// same planned block or break, and sync ended one copy as superseded. That
    /// copy is not something the user did, so it stays in the archive but not
    /// on the day. A superseded session with no surviving twin is still shown.
    static func withoutSyncCopies(_ sessions: [FocusSession]) -> [FocusSession] {
        sessions.filter { session in
            guard session.endReason == .supersededBySync else { return true }
            return !sessions.contains { other in
                other.id != session.id && other.endReason != .supersededBySync
                    && other.kind == session.kind && other.taskID == session.taskID
                    && abs(other.startedAt.timeIntervalSince(session.startedAt)) < 60
            }
        }
    }

    private func row(_ session: FocusSession) -> some View {
        let task = session.taskID.flatMap { id in
            focus.records.state.focusTasks.first(where: { $0.id == id })
        }
        let end = session.endedAt ?? min(.now, session.plannedEndAt)
        return HStack(spacing: 10) {
            Image(systemName: task?.icon.systemName ?? FocusTaskIcon.focus.systemName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(OWCDesign.secondary)
                .frame(width: 30, height: 30)
                .background(OWCDesign.control, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(task?.title ?? text.t("focusTitle"))
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                Text(OWCText.ltrRange(text.formatTime(session.startedAt), text.formatTime(end)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(text.formatRelativeDuration(max(0, end.timeIntervalSince(session.startedAt)) * 1_000))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                Label(
                    text.t(Self.reasonKey(session.endReason)),
                    systemImage: Self.reasonSymbol(session.endReason)
                )
                .labelStyle(.titleAndIcon)
                .font(.caption2)
                .foregroundStyle(OWCDesign.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private static func reasonKey(_ reason: FocusEndReason?) -> String {
        switch reason {
        case .completed: "focusHistoryCompleted"
        case .stoppedByUser: "focusHistoryStopped"
        case .stoppedAtBoundary: "focusHistoryBoundary"
        case .abandoned: "focusHistoryAbandoned"
        case .supersededBySync: "focusHistorySupersededBySync"
        case nil: "focusRunning"
        }
    }

    private static func reasonSymbol(_ reason: FocusEndReason?) -> String {
        switch reason {
        case .completed: "checkmark.circle.fill"
        case .stoppedByUser: "stop.circle"
        case .stoppedAtBoundary: "pause.circle"
        case .abandoned: "exclamationmark.circle"
        case .supersededBySync: "arrow.triangle.2.circlepath"
        case nil: "circle.dotted"
        }
    }
}
