import SwiftUI

/// One civil day, read from midnight to midnight.
///
/// The week and the month compare days; this page explains one. It has a
/// single conclusion — the waking time that was yours — and everything under
/// it is the account of where the rest went, never a second conclusion.
struct RecordsDayCanvasView: View {
    let store: OffWorkStore
    let dayKey: String

    @State private var model: RecordsDayCanvasModel?
    @State private var isLoading = true
    @State private var choosesShift = false
    @State private var nowTick = Date()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let model {
                    if model.isLocked {
                        RecordsLockedDayCard(store: store) { store.paywallSheet = .charts }
                    } else {
                        band(model)
                        conclusion(model)
                        segments(model)
                        observations(model)
                        RecordsFocusHistoryCard(store: store, dayKey: dayKey)
                        conflictCard
                        editEntry(model)
                    }
                } else if !isLoading {
                    OWCGroupCard {
                        Text(store.t("recordsNoObservations"))
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
        .navigationTitle(store.formatRecordsDayTitle(dayKey: dayKey))
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: store.records.revision) { await load() }
        .onChange(of: store.plus.isAuthorized) { _, _ in Task { await load() } }
        // A retrospective page is not a countdown. The now line advances on the
        // minute, and only while the page can actually be seen.
        .onReceive(
            Timer.publish(every: 15, on: .main, in: .common).autoconnect()
        ) { value in
            guard scenePhase == .active, model?.isToday == true else { return }
            if Int(value.timeIntervalSince1970 / 60) != Int(nowTick.timeIntervalSince1970 / 60) {
                nowTick = value
                Task { await load() }
            }
        }
        .confirmationDialog(
            store.t("recordsChooseShift"),
            isPresented: $choosesShift,
            titleVisibility: .visible
        ) {
            ForEach(model?.editableShifts ?? []) { shift in
                Button(shiftLabel(shift)) { store.openDayEditor(dayKey: shift.anchorDayKey) }
            }
            Button(store.t("cancel"), role: .cancel) {}
        }
    }

    private var subtitle: String {
        guard let model else { return "" }
        return store.t(model.source.titleKey)
    }

    private func load() async {
        isLoading = true
        model = await store.recordsDayCanvas(dayKey: dayKey)
        isLoading = false
    }

    // MARK: - The band

    private func band(_ model: RecordsDayCanvasModel) -> some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 8) {
                RecordsDayBand(store: store, model: model)
                    .frame(height: bandHeight)
                axis(model)
                if model.projectionStartsAtMs != nil {
                    Text(store.t("recordsSourceAfterNow"))
                        .font(.caption)
                        .foregroundStyle(OWCDesign.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
    }

    /// Deliberately close to the 20pt allocation bar elsewhere in Records.
    /// At forty points of full-strength categorical colour the band became the
    /// loudest thing on a page whose conclusion is a number.
    private var bandHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 22 : 26
    }

    /// Midnight, six, noon, six, midnight — read in the records time zone, and
    /// laid out against the day's real length so a 23-hour day is not stretched
    /// back to 24.
    private func axis(_ model: RecordsDayCanvasModel) -> some View {
        let total = model.dayEnd.timeIntervalSince(model.dayStart)
        return GeometryReader { proxy in
            ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                let moment = model.dayStart.addingTimeInterval(Double(hour) * 3_600)
                let offset = total > 0
                    ? min(1, max(0, moment.timeIntervalSince(model.dayStart) / total))
                    : 0
                Text(store.formatRecordsTime(min(moment, model.dayEnd)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(OWCDesign.tertiary)
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
                Text(store.t("recordsFreeAwake"))
                    .font(.subheadline)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(store.formatRelativeDuration(Double(model.wakingFreeMs)))
                        .font(.largeTitle.weight(.semibold).monospacedDigit())
                        .foregroundStyle(OWCDesign.primary)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(store.formatPercent(model.wakingFreeShare * 100))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(OWCDesign.secondary)
                        .contentTransition(.numericText())
                        .accessibilityLabel(store.t("recordsShareOfDay"))
                }
                Text(store.t("recordsFreeAwakeFootnote"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.tertiary)
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
                Text(store.t("recordsDaySegments"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OWCDesign.secondary)
                ForEach(model.intervals) { interval in
                    RecordsDayIntervalRow(
                        store: store,
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
        let items = store.observations(on: model.dayStart)
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(store.t("recordsObservations"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OWCDesign.secondary)
                if items.isEmpty {
                    Text(store.t("recordsNoObservations"))
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
        case .timerSurfaceFirstSeen: store.t("recordsObservedFirstSeen")
        case .countdownStarted: store.t("recordsObservedStarted")
        case .countdownStopped: store.t("recordsObservedStopped")
        case .overtimeDeclared: store.t("recordsObservedOvertime")
        }
        return "\(store.formatRecordsTime(item.occurredAt)) · \(kind)"
    }

    /// A data problem is explained on its own terms and gets its own way out.
    /// It is never folded into a Plus message.
    @ViewBuilder
    private var conflictCard: some View {
        if let conflict = store.records.state.sync.conflicts.first(where: { $0.logicalKey == dayKey }) {
            OWCGroupCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.t("recordsConflictCopy"))
                        .font(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Button(store.t("recordsRestoreConflict")) {
                        store.restoreConflict(conflict)
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
        if !store.plus.isAuthorized {
            Text(store.t("recordsEditPlusHint"))
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        } else if !model.editableShifts.isEmpty {
            OWCGroupCard {
                Button {
                    if model.editableShifts.count == 1 {
                        store.openDayEditor(dayKey: model.editableShifts[0].anchorDayKey)
                    } else {
                        choosesShift = true
                    }
                } label: {
                    OWCRow(icon: "pencil", title: store.t("recordsEditDay"), isLast: true) {
                        OWCDetailAccessory(text: nil)
                    }
                }
                .buttonStyle(OWCRowButtonStyle())
            }
        }
    }

    private func shiftLabel(_ shift: RecordsDayEditableShift) -> String {
        guard shift.hasHours else {
            return store.formatRecordsDayTitle(dayKey: shift.anchorDayKey)
        }
        return OWCText.ltrRange(
            store.formatRecordsTime(Date(timeIntervalSince1970: shift.startAtMs / 1_000)),
            store.formatRecordsTime(Date(timeIntervalSince1970: shift.endAtMs / 1_000))
        )
    }
}

/// The 24-hour strip.
///
/// The model has already cut the day out of every shift that crosses it, so
/// this only paints: the intervals tile the strip exactly, and their order is
/// the order VoiceOver reads.
struct RecordsDayBand: View {
    let store: OffWorkStore
    let model: RecordsDayCanvasModel
    @Environment(\.accessibilityDifferentiateWithoutColor) private var withoutColor

    var body: some View {
        let total = model.dayEnd.timeIntervalSince(model.dayStart) * 1_000
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(model.intervals) { interval in
                    Rectangle()
                        .fill(OWCDesign.recordsColor(interval.kind))
                        .owcEstimated(
                            interval.source.isEstimated,
                            tint: .white,
                            spacing: 4
                        )
                        .frame(width: width(of: interval, total: total, in: proxy.size.width))
                }
            }
            .overlay(alignment: .leading) {
                if let nowAtMs = model.nowAtMs, total > 0 {
                    let offset = (nowAtMs - model.dayStart.timeIntervalSince1970 * 1_000) / total
                    Rectangle()
                        .fill(OWCDesign.accent)
                        .frame(width: 2)
                        .offset(x: min(proxy.size.width - 2, max(0, proxy.size.width * offset)))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(OWCDesign.separator, lineWidth: withoutColor ? 1 : 0.5)
        }
        // The picture is for the eye; VoiceOver gets the ordered intervals as
        // words, never a list of pixels or sampling buckets.
        .accessibilityRepresentation {
            VStack {
                ForEach(model.intervals) { interval in
                    Text(RecordsDayIntervalRow.spokenLabel(interval, store: store))
                }
            }
        }
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
    let store: OffWorkStore
    let interval: RecordsDayInterval
    /// What the whole day is. A row only names its own source when it differs
    /// — six rows all repeating "you recorded this" under a header that
    /// already says so is noise, not provenance. VoiceOver still hears it.
    var daySource: RecordsDaySource?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(OWCDesign.recordsColor(interval.kind))
                .owcEstimated(interval.source.isEstimated, tint: .white, spacing: 3, lineWidth: 0.8)
                .frame(width: 9, height: 9)
                .alignmentGuide(.firstTextBaseline) { $0.height - 1 }
            VStack(alignment: .leading, spacing: 2) {
                Text(range)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(OWCDesign.primary)
                if interval.source != daySource {
                    Text(store.t(interval.sourceKey))
                        .font(.caption)
                        .foregroundStyle(OWCDesign.tertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(store.t(interval.kind.titleKey))
                    .font(.callout)
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(store.formatRelativeDuration(Double(interval.durationMs)))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(OWCDesign.primary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenLabel(interval, store: store))
    }

    private var range: String {
        OWCText.ltrRange(
            store.formatRecordsTime(Date(timeIntervalSince1970: interval.startAtMs / 1_000)),
            store.formatRecordsTime(Date(timeIntervalSince1970: interval.endAtMs / 1_000))
        )
    }

    static func spokenLabel(_ interval: RecordsDayInterval, store: OffWorkStore) -> String {
        let start = store.formatRecordsTime(Date(timeIntervalSince1970: interval.startAtMs / 1_000))
        let end = store.formatRecordsTime(Date(timeIntervalSince1970: interval.endAtMs / 1_000))
        return [
            OWCText.ltrRange(start, end),
            store.t(interval.kind.titleKey),
            store.formatRelativeDuration(Double(interval.durationMs)),
            store.t(interval.sourceKey),
        ].joined(separator: ", ")
    }
}

/// The locked day, in the order 013 asks for: what it is, that nothing is
/// being lost, and only then the way to unlock it.
struct RecordsLockedDayCard: View {
    let store: OffWorkStore
    var onUnlock: () -> Void

    var body: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(store.t("recordsLockedDay"), systemImage: "lock.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(OWCDesign.primary)
                Text(store.t("recordsLockedKeepsSaving"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(store.t("plusSeePlans"), action: onUnlock)
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
    let store: OffWorkStore
    let dayKey: String

    var body: some View {
        let sessions = store.focusSessions(forDayKey: dayKey)
        if !sessions.isEmpty {
            OWCGroupCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label(store.t("focusHistory"), systemImage: "timer")
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

    private func row(_ session: FocusSession) -> some View {
        let task = session.taskID.flatMap { id in
            store.records.state.focusTasks.first(where: { $0.id == id })
        }
        let end = session.endedAt ?? min(.now, session.plannedEndAt)
        return HStack(spacing: 10) {
            Image(systemName: task?.icon.systemName ?? "timer")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(OWCDesign.secondary)
                .frame(width: 30, height: 30)
                .background(OWCDesign.control, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(task?.title ?? store.t("focusTitle"))
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                Text(OWCText.ltrRange(store.formatTime(session.startedAt), store.formatTime(end)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(store.formatRelativeDuration(max(0, end.timeIntervalSince(session.startedAt)) * 1_000))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                Label(
                    store.t(Self.reasonKey(session.endReason)),
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
