import SwiftUI

struct RecordsScalePicker: View {
    let store: OffWorkStore
    @Binding var scale: RecordsScale

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Picker("", selection: $scale) {
                ForEach(RecordsScale.allCases) { option in
                    Text(store.t(option.titleKey)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Menu {
                ForEach(RecordsScale.allCases) { option in
                    Button(store.t(option.titleKey)) { scale = option }
                }
            } label: {
                HStack {
                    Text(store.t(scale.titleKey))
                        .font(.body.weight(.semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(OWCDesign.control, in: RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous))
            }
            .accessibilityLabel(store.t(scale.titleKey))
        }
        // Dense chart navigation has to keep all four destinations visible.
        // Descriptive cards below continue to honor the user's full Dynamic
        // Type setting; only this compact control uses a readable upper bound.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

struct RecordsLockedPlaceholder: View {
    let store: OffWorkStore
    let kind: RecordsLockedKind
    var onUnlock: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let titleKey = switch kind {
        case .day: "recordsLockedDay"
        case .scale: "recordsLockedScale"
        case .summary: "recordsLockedSummary"
        }
        Button(action: onUnlock) {
            VStack(spacing: 12) {
                Image(systemName: "lock.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(OWCDesign.accent)
                    .symbolRenderingMode(.hierarchical)
                // Capability, then reassurance, then the way in. Someone who
                // hits a lock should learn that nothing is being lost before
                // they are shown a price.
                VStack(spacing: 6) {
                    Text(store.t(titleKey))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(OWCDesign.primary)
                    Text(store.t("recordsLockedKeepsSaving"))
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                    Text(store.t("plusSeePlans"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(OWCDesign.accent)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 148)
            .padding(20)
            .background(
                reduceTransparency ? OWCDesign.elevated : OWCDesign.control.opacity(0.72),
                in: RoundedRectangle(cornerRadius: OWCDesign.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: OWCDesign.cardRadius, style: .continuous)
                    .stroke(OWCDesign.separator, lineWidth: reduceTransparency ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(store.t(titleKey)). \(store.t("recordsLockedKeepsSaving"))")
        .accessibilityHint(store.t("plusSeePlans"))
    }
}

private struct RecordsMetricHelp: Identifiable {
    var id: String { body }
    let title: String
    let body: String
}

private struct RecordsMetricHelpButton: View {
    let title: String
    let message: String
    @Binding var selection: RecordsMetricHelp?

    var bodyView: some View {
        Button {
            selection = RecordsMetricHelp(title: title, body: message)
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.footnote.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(OWCDesign.tertiary)
        .accessibilityLabel(title)
    }

    var body: some View { bodyView }
}

private struct RecordsMetricHelpPopover: View {
    let help: RecordsMetricHelp
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    content.padding(18)
                }
                .frame(idealWidth: 480)
                .presentationDragIndicator(.visible)
            } else {
                content
                    .frame(idealWidth: 300, alignment: .leading)
                    .padding(18)
            }
        }
        .presentationCompactAdaptation(dynamicTypeSize.isAccessibilitySize ? .sheet : .popover)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(help.title)
                .font(.headline)
            Text(help.body)
                .font(.body)
                .foregroundStyle(OWCDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The 100% allocation bar and its legend.
///
/// One implementation, because the window summary and the life projection have
/// to divide a span into the same six categories with the same colours — two
/// bars drawn twice would eventually disagree about what "free" means.
struct RecordsAllocationBar: View {
    let store: OffWorkStore
    let share: TimeAllocationShare
    @State private var selectedKind: TimeAllocationKind?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            bar
            legend
            if let selectedKind, let item = slice(selectedKind) {
                Text(
                    store.t(
                        "recordsAllocationTap",
                        values: [
                            "label": store.t(selectedKind.titleKey),
                            "duration": store.formatRelativeDuration(Double(item.ms)),
                            "percent": store.formatPercent(item.percent),
                        ]
                    )
                )
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
                .contentTransition(.numericText())
            }
        }
    }

    private var bar: some View {
        let visible = slices.filter { $0.ms > 0 }
        let total = max(1, share.dayLengthMs)
        return GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                    let isFirst = index == visible.startIndex
                    let isLast = index == visible.index(before: visible.endIndex)
                    let shape = UnevenRoundedRectangle(
                        cornerRadii: RectangleCornerRadii(
                            topLeading: isFirst ? 10 : 0,
                            bottomLeading: isFirst ? 10 : 0,
                            bottomTrailing: isLast ? 10 : 0,
                            topTrailing: isLast ? 10 : 0
                        ),
                        style: .continuous
                    )
                    Button {
                        selectedKind = item.kind
                    } label: {
                        shape
                            .fill(item.color)
                            .frame(
                                width: max(1, proxy.size.width * CGFloat(item.ms) / CGFloat(total)),
                                height: 20
                            )
                            .overlay {
                                if selectedKind == item.kind {
                                    // `strokeBorder` stays inside the segment.
                                    // A centered stroke was clipped by the
                                    // outer capsule at both bar edges.
                                    shape.strokeBorder(OWCDesign.primary, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .frame(height: 44)
                    .accessibilityLabel(store.t(item.kind.titleKey))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 44)
        .background {
            Capsule()
                .fill(OWCDesign.control)
                .frame(height: 20)
        }
        .overlay {
            Capsule()
                .stroke(OWCDesign.separator, lineWidth: 0.5)
                .frame(height: 20)
        }
    }

    private var legend: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(slices.filter { $0.kind != .unclassified || $0.ms > 0 }) { item in
                Button {
                    selectedKind = item.kind
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 10, height: 10)
                        Text(store.t(item.kind.titleKey))
                            .font(.callout)
                            .foregroundStyle(OWCDesign.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Spacer(minLength: 12)
                        Text(store.formatRelativeDuration(Double(item.ms)))
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .foregroundStyle(OWCDesign.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                            .allowsTightening(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var slices: [AllocationSlice] {
        TimeAllocationKind.allCases.map { kind in
            AllocationSlice(kind: kind, ms: duration(kind), color: OWCDesign.recordsColor(kind))
        }
    }

    private func slice(_ kind: TimeAllocationKind) -> (titleKey: String, ms: Int64, percent: Double)? {
        guard share.dayLengthMs > 0 else { return nil }
        let ms = duration(kind)
        return (kind.titleKey, ms, Double(ms) / Double(share.dayLengthMs) * 100)
    }

    private func duration(_ kind: TimeAllocationKind) -> Int64 {
        switch kind {
        case .work: share.workMs
        case .overtime: share.overtimeMs
        case .workBreak: share.breakMs
        case .sleep: share.sleepMs
        case .free: share.freeMs
        case .unclassified: share.unclassifiedMs
        }
    }

    private struct AllocationSlice: Identifiable {
        var id: TimeAllocationKind { kind }
        let kind: TimeAllocationKind
        let ms: Int64
        let color: Color
    }
}

struct RecordsHeadlineView: View {
    let store: OffWorkStore
    let title: String
    let summary: RecordsHeadlineSummary?
    var isCollapsible = false
    var onUnlock: () -> Void
    @State private var isExpanded = false
    @State private var showsAllocation = false
    @State private var selectedHelp: RecordsMetricHelp?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let summary {
            OWCGroupCard {
                Group {
                    if isCollapsible {
                        DisclosureGroup(isExpanded: $isExpanded) {
                            content(summary).padding(.top, 12)
                        } label: {
                            Text(title)
                                .font(.subheadline.weight(.medium))
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(OWCDesign.secondary)
                                .frame(minHeight: 44, alignment: .leading)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(title)
                                    .font(.headline)
                                    .foregroundStyle(OWCDesign.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                RecordsMetricHelpButton(
                                    title: title,
                                    message: store.t("recordsMetricWorkHelp") + "\n\n"
                                        + store.t("recordsMetricOvertimeHelp"),
                                    selection: $selectedHelp
                                )
                            }
                            content(summary)
                        }
                    }
                }
                .padding(16)
            }
            .popover(item: $selectedHelp) { help in
                RecordsMetricHelpPopover(help: help)
            }
        } else if store.plus.isAuthorized {
            OWCGroupCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title).font(.headline)
                    Text(store.t("recordsUnrecorded"))
                        .font(.subheadline)
                        .foregroundStyle(OWCDesign.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        } else {
            RecordsLockedPlaceholder(store: store, kind: .summary, onUnlock: onUnlock)
        }
    }

    private func content(_ summary: RecordsHeadlineSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            metric("recordsWorkRegular", store.formatRelativeDuration(Double(summary.regularWorkMs)), prominent: true)
            metric("recordsRecordedDays", store.formatDays(Double(summary.workdays)))
            metric("recordsOvertime", store.formatRelativeDuration(Double(summary.overtimeMs)))

            if let income = summary.estimatedIncome {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    metric("recordsIncomeCurrentSalary", store.moneyText(income))
                    Text(store.t("recordsIncomeBasis", values: ["count": store.formatCount(summary.completedScheduledWorkdays)]))
                        .font(.caption)
                        .foregroundStyle(OWCDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()
            DisclosureGroup(isExpanded: $showsAllocation) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(store.t("recordsAllocationBasis", values: ["count": store.formatCount(summary.allocationDays)]))
                        .font(.caption)
                        .foregroundStyle(OWCDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    metric("recordsFreeAwake", store.formatRelativeDuration(Double(summary.wakingFreeMs)))
                    RecordsAllocationBar(store: store, share: summary.allocation)
                    Text(store.t(summary.sleepSourceKey))
                        .font(.caption)
                        .foregroundStyle(OWCDesign.secondary)
                }
                .padding(.top, 10)
            } label: {
                Text(store.t("recordsTimeBreakdown"))
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(OWCDesign.secondary)
                    .frame(minHeight: 44, alignment: .leading)
            }
        }
    }

    private func metric(_ titleKey: String, _ value: String, prominent: Bool = false) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            Text(store.t(titleKey))
                .font(.subheadline)
                .foregroundStyle(OWCDesign.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(prominent ? .title2.weight(.semibold).monospacedDigit() : .body.weight(.medium).monospacedDigit())
                .foregroundStyle(OWCDesign.primary)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct RecordsMonthGrid: View {
    let store: OffWorkStore
    let cells: [RecordsDayCell]
    let selectedDayKey: String?
    var onSelect: (RecordsDayCell) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
        let blanks = cells.first.map { store.recordsGridLeadingBlanks(before: $0.date) } ?? 0
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                ForEach(Array(store.recordsWeekdayGridSymbols().enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(OWCDesign.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(Array(0..<blanks), id: \.self) { _ in
                    Color.clear.aspectRatio(1, contentMode: .fit)
                }
                ForEach(cells) { cell in
                    Button {
                        onSelect(cell)
                    } label: {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(fill(cell))
                            .aspectRatio(1, contentMode: .fit)
                            .owcEstimated(
                                RecordsDayMarks.isEstimated(cell),
                                tint: OWCDesign.secondary.opacity(0.55),
                                spacing: 6
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                Text(store.formatCount(store.recordsCalendar.component(.day, from: cell.date)))
                                    .font(.callout.weight(cell.isToday || cell.dayKey == selectedDayKey ? .semibold : .regular).monospacedDigit())
                                    .foregroundStyle(label(cell))
                            }
                            .overlay(alignment: .bottom) {
                                RecordsMiniWorkBar(
                                    workMs: cell.workMs,
                                    overtimeMs: cell.overtimeMs,
                                    maxWidth: 24,
                                    height: barHeight
                                )
                                .padding(.bottom, 4)
                            }
                            .overlay(alignment: .topTrailing) {
                                stateMarker(cell)
                                    .padding(4)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(
                                        stroke(cell),
                                        lineWidth: 2
                                    )
                            }
                            .padding(3)
                            .contentShape(Rectangle())
                    }
                    // Seven columns in a phone's width leave about 42 points a
                    // side, and no amount of spacing arithmetic gets a square
                    // cell to 44 without the grid ceasing to be a calendar. The
                    // touch target reaches into the gutter instead; the drawn
                    // cell and the layout are untouched.
                    .padding(-3)
                    .buttonStyle(.plain)
                    .accessibilityLabel(RecordsDayMarks.accessibilityLabel(cell, store: store))
                }
            }
        }
        // A seven-column calendar cannot reflow without ceasing to be a
        // calendar. Cap only its dense labels while VoiceOver retains the full
        // localized date and status for every 44-point button.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// 48 points cannot hold a readable date, a bar and a status glyph at the
    /// largest sizes. The date never shrinks; the bar gives way first, and the
    /// status glyph after it — both remain in the VoiceOver value.
    private var barHeight: CGFloat {
        dynamicTypeSize >= .accessibility1 ? 2 : (dynamicTypeSize >= .xxLarge ? 2.5 : 3)
    }

    private var showsStateMarker: Bool { dynamicTypeSize < .accessibility1 }

    /// Brand orange means selection and today. Nothing here encodes hours: the
    /// bar does that, in the shared category colours. Selection is a ring
    /// rather than a solid block precisely so the bar inside keeps its own
    /// colour instead of sitting on orange.
    private func fill(_ cell: RecordsDayCell) -> Color {
        if cell.dayKey == selectedDayKey { return OWCDesign.accent.opacity(0.12) }
        return switch cell.appearance {
        case .locked: OWCDesign.control.opacity(0.45)
        case .unrecorded, .planned: Color.clear
        case .rest: OWCDesign.control.opacity(0.36)
        case .recorded, .corrected: OWCDesign.control.opacity(0.5)
        }
    }

    private func label(_ cell: RecordsDayCell) -> Color {
        if cell.appearance == .locked { return OWCDesign.tertiary }
        if cell.isToday || cell.dayKey == selectedDayKey { return OWCDesign.accent }
        return OWCDesign.primary
    }

    /// Two different structures, one colour: selection draws a ring, today
    /// only tints its own number. A 2pt and a 1.25pt ring of the same orange
    /// would have been the same state twice.
    private func stroke(_ cell: RecordsDayCell) -> Color {
        cell.dayKey == selectedDayKey ? OWCDesign.accent : .clear
    }

    @ViewBuilder
    private func stateMarker(_ cell: RecordsDayCell) -> some View {
        if showsStateMarker {
            if cell.hasConflict {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(OWCDesign.orangeDeep)
            } else if cell.appearance == .corrected {
                Image(systemName: "pencil")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(OWCDesign.secondary)
            } else if cell.appearance == .locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(OWCDesign.tertiary)
            }
        }
    }
}

/// One bar, drawn the same way in the month grid, the week column and the
/// expanded year: regular work first, declared overtime as the tail segment.
/// Overtime keeps the system orange it has always had, but it is told apart by
/// its position, never by asking anyone to compare two oranges.
struct RecordsMiniWorkBar: View {
    let workMs: Int64
    let overtimeMs: Int64
    var maxWidth: CGFloat = 24
    var height: CGFloat = 3

    var body: some View {
        let total = Double(max(0, workMs) + max(0, overtimeMs))
        if total > 0 {
            let hours = total / 3_600_000
            let width = min(maxWidth, max(8, 6 + hours * 1.8))
            let overtimeWidth = overtimeMs > 0
                ? max(2, width * CGFloat(Double(overtimeMs) / total))
                : 0
            HStack(spacing: overtimeWidth > 0 ? 1 : 0) {
                if workMs > 0 {
                    Capsule().fill(OWCDesign.recordsWork)
                        .frame(width: max(2, width - overtimeWidth), height: height)
                }
                if overtimeWidth > 0 {
                    Capsule().fill(OWCDesign.recordsOvertime)
                        .frame(width: overtimeWidth, height: height)
                }
            }
        }
    }
}

/// One vocabulary for a day's marks, shared by the month grid and the week
/// columns so the same day cannot be described two ways on two screens.
enum RecordsDayMarks {
    /// Hatching says "these hours are an estimate". A rest day inside a career
    /// projection has no hours at all, so hatching it would claim an estimated
    /// day of work where the honest answer is simply "not a workday".
    static func isEstimated(_ cell: RecordsDayCell) -> Bool {
        (cell.isProjection || cell.appearance == .planned)
            && cell.workMs + cell.overtimeMs > 0
    }

    static func sourceKey(_ cell: RecordsDayCell) -> String {
        if cell.appearance == .locked { return "recordsLockedDay" }
        if cell.isProjection { return "recordsSourceProjection" }
        return switch cell.appearance {
        case .unrecorded: "recordsUnrecorded"
        case .recorded: cell.isFromSavedSchedule ? "recordsSourceSchedule" : "recordsSourceRecorded"
        case .corrected: "recordsSourceOverride"
        case .planned: "recordsPlanned"
        case .rest: "recordsRestDay"
        case .locked: "recordsLockedDay"
        }
    }

    /// A locked day says only that it is locked — no date arithmetic, no
    /// hours, nothing a screen reader could read out from behind the lock.
    static func accessibilityLabel(_ cell: RecordsDayCell, store: OffWorkStore) -> String {
        if cell.appearance == .locked { return store.t("recordsLockedDay") }
        var parts = [store.formatRecordsDayTitle(cell.date), store.t(sourceKey(cell))]
        if cell.workMs > 0 {
            parts.append(store.formatRelativeDuration(Double(cell.workMs)))
        }
        if cell.overtimeMs > 0 {
            parts.append("\(store.t("recordsOvertime")) \(store.formatRelativeDuration(Double(cell.overtimeMs)))")
        }
        if cell.hasConflict { parts.append(store.t("recordsConflictCopy")) }
        return parts.joined(separator: ", ")
    }
}

struct RecordsWeekStrips: View {
    let store: OffWorkStore
    let cells: [RecordsDayCell]
    let selectedDayKey: String?
    var onSelect: (RecordsDayCell) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(cells) { cell in
                Button {
                    onSelect(cell)
                } label: {
                    VStack(spacing: 7) {
                        weekStack(cell)
                            .frame(maxWidth: .infinity, minHeight: 124, alignment: .bottom)
                        VStack(spacing: 2) {
                            Text(store.formatCount(store.recordsCalendar.component(.day, from: cell.date)))
                                .font(.callout.weight(cell.dayKey == selectedDayKey || cell.isToday ? .semibold : .regular).monospacedDigit())
                            Text(store.formatRecordsWeekdayNarrow(cell.date))
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(cell.dayKey == selectedDayKey ? .white : cell.isToday ? OWCDesign.accent : OWCDesign.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(cell.dayKey == selectedDayKey ? OWCDesign.accent : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 3)
                    .contentShape(Rectangle())
                }
                .padding(.horizontal, -3)
                .buttonStyle(.plain)
                .accessibilityLabel(RecordsDayMarks.accessibilityLabel(cell, store: store))
            }
        }
        .frame(height: 188)
        // Dense chart labels have a bounded scale; the full day description
        // remains available to VoiceOver and in the selected-day summary.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func weekStack(_ cell: RecordsDayCell) -> some View {
        ZStack(alignment: .bottom) {
            weekTrack(cell)
            if cell.observationCount > 0 {
                Circle()
                    .fill(OWCDesign.secondary)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(OWCDesign.card, lineWidth: 2))
                    .offset(y: 4)
            }
        }
        .overlay(alignment: .top) {
            if cell.appearance == .corrected {
                Image(systemName: "pencil")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(OWCDesign.secondary)
                    .offset(y: -2)
            }
        }
    }

    @ViewBuilder
    private func weekTrack(_ cell: RecordsDayCell) -> some View {
        if cell.appearance == .locked {
            Capsule()
                .fill(OWCDesign.control.opacity(0.6))
                .frame(width: 18, height: 116)
                .overlay {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(OWCDesign.tertiary)
                }
        } else {
            workloadColumn(cell)
        }
    }

    /// Regular work first, declared overtime stacked on its end — the same
    /// two-part bar the month cell and the expanded year draw. Colouring the
    /// whole column orange said "this day has overtime" in a hue the eye had
    /// to compare against another orange, and threw away how much.
    private func workloadColumn(_ cell: RecordsDayCell) -> some View {
        let scale = Double(RecordsWeekAxis.ceiling(for: cells))
        let work = min(1, Double(cell.workMs) / scale)
        let overtime = min(1 - work, Double(cell.overtimeMs) / scale)
        return ZStack(alignment: .bottom) {
            Capsule().fill(OWCDesign.control.opacity(0.72))
            // The minimum height is only a visibility aid for a real, short
            // work interval. Applying it to zero turned rest days into a
            // misleading coloured baseline.
            VStack(spacing: 0) {
                if overtime > 0 {
                    Rectangle().fill(OWCDesign.recordsOvertime)
                        .frame(height: max(4, 116 * overtime))
                }
                if work > 0 {
                    Rectangle().fill(OWCDesign.recordsWork)
                        .frame(height: max(4, 116 * work))
                }
            }
            // The hatch belongs to the hours, not to the track behind them.
            // Over the whole column an empty rest day read as a full day of
            // estimated work.
            .owcEstimated(RecordsDayMarks.isEstimated(cell), tint: .white, spacing: 4)
            .clipShape(Capsule())
        }
        .frame(width: 18, height: 116)
        .overlay { Capsule().stroke(OWCDesign.separator, lineWidth: 0.5) }
    }

}

struct RecordsYearCanvas: View {
    let store: OffWorkStore
    let cells: [RecordsDayCell]
    let selectedMonth: Int?
    @Binding var calloutMonth: Int?
    @Binding var selectedDate: Date?
    var onSelectMonth: (Int) -> Void
    @Environment(\.accessibilityDifferentiateWithoutColor) private var withoutColor
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeometryReader { proxy in
                if let start = cells.first?.date,
                   let last = cells.last?.date,
                   let end = store.recordsCalendar.date(byAdding: .day, value: 1, to: last) {
                    let grid = RecordsCanvasGrid(
                        size: proxy.size,
                        targetCell: 12,
                        gap: 3,
                        minimumColumns: 16,
                        minimumRows: 8
                    )
                    let buckets = RecordsYearSampler.buckets(
                        from: start,
                        to: end,
                        count: grid.count,
                        cells: cells,
                        calendar: store.recordsCalendar
                    )
                    Canvas { context, _ in
                        for bucket in buckets {
                            let rect = grid.rect(at: bucket.index)
                            let path = Path(roundedRect: rect, cornerRadius: min(3, grid.cell / 3))
                            context.fill(path, with: .color(color(bucket)))
                            if bucket.kind == .corrected || withoutColor && bucket.kind == .recorded {
                                context.stroke(
                                    Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: min(3, grid.cell / 3)),
                                    with: .color(OWCDesign.primary.opacity(0.72)),
                                    lineWidth: contrast == .increased ? 1.5 : 1
                                )
                            }
                        }
                        if let selectedMonth {
                            let outline = grid.selectionPath(for: buckets.filter { $0.month == selectedMonth }.map(\.index))
                            context.stroke(
                                outline,
                                with: .color(OWCDesign.orangeDeep.opacity(0.8)),
                                style: StrokeStyle(lineWidth: contrast == .increased ? 1.8 : 1.25, lineJoin: .round)
                            )
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { value in
                        guard let index = grid.index(at: value.location), buckets.indices.contains(index) else { return }
                        let bucket = buckets[index]
                        select(month: bucket.month, date: bucket.start.addingTimeInterval(bucket.end.timeIntervalSince(bucket.start) / 2))
                    })
                    .overlay {
                        ZStack {
                            if let calloutMonth,
                               let bucket = calloutBucket(for: calloutMonth, in: buckets) {
                                let rect = grid.rect(at: bucket.index)
                                RecordsCanvasCalloutLayout(anchor: rect) {
                                    RecordsCanvasCallout(
                                        icon: "calendar",
                                        title: monthLabel(calloutMonth),
                                        subtitle: yearLabel
                                    )
                                }
                                .transition(.opacity)
                            }
                        }
                        .animation(reduceMotion ? nil : OWCMotion.selection, value: selectedDate)
                        .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.selection, value: calloutMonth)
                    }
                    .accessibilityRepresentation {
                        VStack {
                            ForEach(1...12, id: \.self) { month in
                                Button {
                                    select(month: month, date: nil)
                                } label: {
                                    Text(monthLabel(month))
                                }
                                .accessibilityAddTraits(selectedMonth == month ? .isSelected : [])
                            }
                        }
                    }
                } else {
                    Color.clear
                }
            }
            .frame(minHeight: 184, idealHeight: 220, maxHeight: .infinity)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(1...12, id: \.self) { month in
                    Button {
                        select(month: month, date: nil)
                    } label: {
                        Text(monthLabel(month))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .font(.footnote.weight(selectedMonth == month ? .semibold : .medium))
                            .foregroundStyle(selectedMonth == month ? OWCDesign.orangeDeep : OWCDesign.secondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                selectedMonth == month
                                    ? OWCDesign.orangeDeep.opacity(0.16)
                                    : OWCDesign.control,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .overlay {
                                if selectedMonth == month {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(OWCDesign.orangeDeep, lineWidth: contrast == .increased ? 2 : 1.25)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            // The collapsed year answers "when was it heavy" with depth alone,
            // so it has to say so — and say what carries that information when
            // colour is not available.
            Text(store.t(withoutColor ? "recordsHeatWithoutColor" : "recordsHeatScale"))
                .font(.caption2)
                .foregroundStyle(OWCDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

    }

    /// Depth of the work colour is how much; brand orange stays out of it
    /// entirely, because on this canvas it already means "this is the month
    /// you picked".
    private func color(_ bucket: RecordsYearBucket) -> Color {
        let base = switch bucket.kind {
        case .locked: OWCDesign.control.opacity(0.86)
        case .unrecorded, .rest: OWCDesign.control.opacity(0.65)
        case .planned: OWCDesign.recordsWork.opacity(withoutColor ? 0.84 : 0.46)
        case .recorded: OWCDesign.recordsWork.opacity(withoutColor ? 0.96 : min(0.96, 0.54 + Double(bucket.workMs) / 57_600_000))
        case .corrected: OWCDesign.recordsWork.opacity(0.96)
        }
        guard let selectedMonth, bucket.month != selectedMonth else { return base }
        return base.opacity(0.76)
    }

    private func monthLabel(_ month: Int) -> String {
        var parts = store.recordsCalendar.dateComponents([.year], from: cells.first?.date ?? .now)
        parts.month = month
        parts.day = 1
        let date = store.recordsCalendar.date(from: parts) ?? .now
        return store.formatRecordsMonth(date)
    }

    private var yearLabel: String {
        let year = store.recordsCalendar.component(.year, from: cells.first?.date ?? .now)
        return store.formatYear(year)
    }

    private func select(month: Int, date: Date?) {
        if selectedMonth != month { onSelectMonth(month) }
        calloutMonth = month
        selectedDate = date
    }

    private func calloutBucket(
        for month: Int,
        in buckets: [RecordsYearBucket]
    ) -> RecordsYearBucket? {
        if let selectedDate,
           let tapped = buckets.first(where: { $0.start <= selectedDate && selectedDate < $0.end && $0.month == month }) {
            return tapped
        }
        return buckets.first(where: { $0.month == month })
    }
}

/// The expanded year.
///
/// Collapsed, the year stays `RecordsYearCanvas`: a few hundred small buckets
/// that read as rhythm — which stretches of the year were heavy. A bucket that
/// size carries exactly one channel, so overtime has to stay out of it, and
/// the interactive unit is a whole month regardless of how fine the dots get.
///
/// Expanding spends the screen on height, and height is what a comparison
/// wants. The same year becomes twelve rows on one shared ceiling: overtime is
/// its own segment, every month is a real 44pt button with its total beside
/// it, and VoiceOver reads twelve labelled rows instead of a canvas stand-in.
/// Nothing is recomputed — both forms read the same `RecordsDayCell` values.
struct RecordsYearMonthBars: View {
    let store: OffWorkStore
    let cells: [RecordsDayCell]
    let selectedMonth: Int?
    var onSelectMonth: (Int) -> Void

    @Environment(\.accessibilityDifferentiateWithoutColor) private var withoutColor
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// At accessibility sizes a month name, a bar and a duration stop fitting
    /// on one line, so the row becomes two lines rather than three truncated
    /// columns.
    private var stacksRow: Bool { dynamicTypeSize.isAccessibilitySize }
    private let labelWidth: CGFloat = 64
    private let valueWidth: CGFloat = 84

    var body: some View {
        let months = RecordsYearMonthSampler.months(cells: cells, calendar: store.recordsCalendar)
        let axisMs = RecordsYearMonthSampler.axisCeiling(for: months)
        VStack(alignment: .leading, spacing: 10) {
            axisRow(axisMs)
            // Expanding is a request for height, so the rows spend it: they
            // stretch to fill the canvas rather than leaving a screen of empty
            // card under twelve compact lines. Where twelve 44pt rows genuinely
            // do not fit — a small phone, an accessibility text size — the
            // second branch scrolls instead of compressing below the minimum
            // hit target.
            ViewThatFits(in: .vertical) {
                rows(months, axisMs: axisMs, stretches: true)
                ScrollView {
                    rows(months, axisMs: axisMs, stretches: false)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            legend(showsProjection: months.contains { $0.projectedMs > 0 })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : OWCMotion.selection, value: selectedMonth)
    }

    private func rows(_ months: [RecordsYearMonthBar], axisMs: Int64, stretches: Bool) -> some View {
        VStack(spacing: 2) {
            ForEach(months) { month in
                row(month, axisMs: axisMs)
                    .frame(maxHeight: stretches ? .infinity : nil)
            }
        }
    }

    /// The ruler the rows are drawn against. Without it a long bar reads as
    /// "a lot" with no idea of how much.
    private func axisRow(_ axisMs: Int64) -> some View {
        HStack(spacing: 10) {
            if !stacksRow {
                Color.clear.frame(width: labelWidth, height: 1)
            }
            VStack(alignment: .trailing, spacing: 3) {
                Text(store.formatRelativeDuration(Double(axisMs)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(OWCDesign.tertiary)
                Rectangle()
                    .fill(OWCDesign.separator)
                    .frame(height: 1)
            }
            if !stacksRow {
                Color.clear.frame(width: valueWidth, height: 1)
            }
        }
        .padding(.horizontal, 8)
        .accessibilityHidden(true)
    }

    private func row(_ month: RecordsYearMonthBar, axisMs: Int64) -> some View {
        let isSelected = selectedMonth == month.month
        return Button {
            onSelectMonth(month.month)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                if stacksRow {
                    HStack(spacing: 8) {
                        monthName(month, isSelected: isSelected)
                        Spacer(minLength: 8)
                        valueLabel(month)
                    }
                    track(month, axisMs: axisMs)
                } else {
                    HStack(spacing: 10) {
                        monthName(month, isSelected: isSelected)
                            .frame(width: labelWidth, alignment: .leading)
                        track(month, axisMs: axisMs)
                        valueLabel(month)
                            .frame(width: valueWidth, alignment: .trailing)
                    }
                }
                if isSelected, month.hasRecords {
                    Text(breakdown(month))
                        .font(.caption)
                        .foregroundStyle(OWCDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                isSelected ? OWCDesign.accent.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(OWCDesign.accent, lineWidth: contrast == .increased ? 2 : 1.25)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(monthLabel(month.month))
        .accessibilityValue(accessibilityValue(month))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func monthName(_ month: RecordsYearMonthBar, isSelected: Bool) -> some View {
        Text(monthLabel(month.month))
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(OWCDesign.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func track(_ month: RecordsYearMonthBar, axisMs: Int64) -> some View {
        GeometryReader { proxy in
            let widths = segmentWidths(month, axisMs: axisMs, available: proxy.size.width)
            ZStack(alignment: .leading) {
                Capsule().fill(OWCDesign.control)
                HStack(spacing: 2) {
                    if widths.work > 0 {
                        Capsule()
                            .fill(OWCDesign.recordsWork)
                            .frame(width: widths.work)
                    }
                    if widths.overtime > 0 {
                        Capsule()
                            .fill(OWCDesign.recordsOvertime)
                            .frame(width: widths.overtime)
                            .overlay {
                                if withoutColor {
                                    Capsule().strokeBorder(OWCDesign.primary.opacity(0.7), lineWidth: 1)
                                }
                            }
                    }
                    if widths.projected > 0 {
                        // The same 135° hatching the month cells and the day
                        // band use for "not a fact yet". A texture rather than
                        // a paler fill, so it survives Differentiate Without
                        // Color — and one texture rather than two, so a reader
                        // does not have to learn a dash here and a hatch there.
                        Capsule()
                            .fill(OWCDesign.recordsWork.opacity(0.22))
                            .owcEstimated(true, tint: OWCDesign.recordsWork, spacing: 4)
                            .clipShape(Capsule())
                            .frame(width: widths.projected)
                    }
                }
            }
        }
        .frame(height: 12)
    }

    /// Segment widths on the shared ceiling, floored so twenty minutes of
    /// overtime still draws, and rescaled if those floors would run a row past
    /// the end of its track.
    private func segmentWidths(
        _ month: RecordsYearMonthBar,
        axisMs: Int64,
        available: CGFloat
    ) -> (work: CGFloat, overtime: CGFloat, projected: CGFloat) {
        guard available > 0, axisMs > 0 else { return (0, 0, 0) }
        let scale = available / CGFloat(axisMs)
        func width(_ ms: Int64) -> CGFloat { ms > 0 ? max(4, CGFloat(ms) * scale) : 0 }
        var work = width(month.workMs)
        var overtime = width(month.overtimeMs)
        var projected = width(month.projectedMs)
        let drawn = [work, overtime, projected].filter { $0 > 0 }
        let total = drawn.reduce(0, +) + CGFloat(max(0, drawn.count - 1)) * 2
        if total > available {
            let factor = available / total
            work *= factor
            overtime *= factor
            projected *= factor
        }
        return (work, overtime, projected)
    }

    @ViewBuilder
    private func valueLabel(_ month: RecordsYearMonthBar) -> some View {
        if month.hasRecords {
            duration(month.totalMs, style: OWCDesign.secondary)
        } else if month.projectedMs > 0 {
            duration(month.projectedMs, style: OWCDesign.tertiary)
        } else {
            Text(verbatim: "—")
                .font(.footnote)
                .foregroundStyle(OWCDesign.tertiary)
        }
    }

    private func duration(_ ms: Int64, style: Color) -> some View {
        Text(store.formatRelativeDuration(Double(ms)))
            .font(.footnote.monospacedDigit())
            .foregroundStyle(style)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func legend(showsProjection: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                legendItems(showsProjection: showsProjection)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 4) {
                legendItems(showsProjection: showsProjection)
            }
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func legendItems(showsProjection: Bool) -> some View {
        legendItem(store.t("recordsWorkRegular"), color: OWCDesign.recordsWork, dashed: false)
        legendItem(store.t("recordsOvertime"), color: OWCDesign.recordsOvertime, dashed: false)
        if showsProjection {
            legendItem(store.t("recordsSourceProjection"), color: OWCDesign.recordsWork, dashed: true)
        }
    }

    private func legendItem(_ title: String, color: Color, dashed: Bool) -> some View {
        HStack(spacing: 5) {
            Group {
                if dashed {
                    Capsule()
                        .fill(color.opacity(0.22))
                        .owcEstimated(true, tint: color, spacing: 4)
                        .clipShape(Capsule())
                } else {
                    Capsule().fill(color)
                }
            }
            .frame(width: 14, height: 8)
            Text(title)
                .font(.caption)
                .foregroundStyle(OWCDesign.secondary)
                .lineLimit(1)
        }
    }

    private func breakdown(_ month: RecordsYearMonthBar) -> String {
        var parts = [
            store.t("recordsMonthWorkdays", values: ["count": store.formatCount(month.workdays)]),
            "\(store.t("recordsWorkRegular")) \(store.formatRelativeDuration(Double(month.workMs)))"
        ]
        if month.overtimeMs > 0 {
            parts.append("\(store.t("recordsOvertime")) \(store.formatRelativeDuration(Double(month.overtimeMs)))")
        }
        return parts.joined(separator: " · ")
    }

    private func accessibilityValue(_ month: RecordsYearMonthBar) -> String {
        if month.hasRecords { return breakdown(month) }
        if month.projectedMs > 0 {
            return "\(store.t("recordsSourceProjection")) \(store.formatRelativeDuration(Double(month.projectedMs)))"
        }
        // Never name the month's real numbers here; a locked month has none
        // loaded to name.
        if month.hasLockedDays { return store.t("recordsLockedScale") }
        return store.t("recordsUnrecorded")
    }

    private func monthLabel(_ month: Int) -> String {
        var parts = store.recordsCalendar.dateComponents([.year], from: cells.first?.date ?? .now)
        parts.month = month
        parts.day = 1
        let date = store.recordsCalendar.date(from: parts) ?? .now
        return store.formatRecordsMonthShort(date)
    }
}

struct RecordsCanvasGrid {
    let columns: Int
    let rows: Int
    let cell: CGFloat
    let gap: CGFloat

    var count: Int { columns * rows }

    init(size: CGSize, targetCell: CGFloat, gap: CGFloat, minimumColumns: Int, minimumRows: Int) {
        self.gap = gap
        columns = max(minimumColumns, Int((size.width + gap) / (targetCell + gap)))
        rows = max(minimumRows, Int((size.height + gap) / (targetCell + gap)))
        cell = max(
            2,
            min(
                (size.width - gap * CGFloat(max(columns - 1, 0))) / CGFloat(columns),
                (size.height - gap * CGFloat(max(rows - 1, 0))) / CGFloat(rows)
            )
        )
    }

    func rect(at index: Int) -> CGRect {
        let column = index % columns
        let row = index / columns
        return CGRect(
            x: CGFloat(column) * (cell + gap),
            y: CGFloat(row) * (cell + gap),
            width: cell,
            height: cell
        )
    }

    func index(at point: CGPoint) -> Int? {
        let pitch = cell + gap
        guard pitch > 0, point.x >= 0, point.y >= 0 else { return nil }
        let column = Int(point.x / pitch)
        let row = Int(point.y / pitch)
        guard column >= 0, column < columns, row >= 0, row < rows else { return nil }
        return row * columns + column
    }

    func selectionPath(for indices: [Int]) -> Path {
        selectionRects(for: indices).reduce(Path()) { path, rect in
            path.union(Path(rect))
        }
    }

    /// Turns a contiguous timeline selection into one outlined block per row.
    /// Painting the gaps as well as the cells makes a selected month/stage read
    /// as one range instead of dozens of independently focused dots.
    func selectionRects(for indices: [Int]) -> [CGRect] {
        let sorted = Set(indices).sorted()
        guard !sorted.isEmpty else { return [] }
        var ranges: [(Int, Int)] = []
        var start = sorted[0]
        var previous = sorted[0]
        for index in sorted.dropFirst() {
            if index == previous + 1, index / columns == previous / columns {
                previous = index
            } else {
                ranges.append((start, previous))
                start = index
                previous = index
            }
        }
        ranges.append((start, previous))
        return ranges.map { first, last in
            let leading = rect(at: first)
            let trailing = rect(at: last)
            return CGRect(
                x: leading.minX - gap / 2,
                y: leading.minY - gap / 2,
                width: trailing.maxX - leading.minX + gap,
                height: cell + gap
            )
        }
    }
}

struct RecordsLifeCanvas: View {
    let store: OffWorkStore
    let stages: [LifeStageSpan]
    let bounds: (Date, Date)
    let selectedStageID: String?
    let referenceDate: Date
    @Binding var selectedDate: Date?
    var showsStageLegend = true
    var onSelect: (LifeStageSpan) -> Void
    @Environment(\.accessibilityDifferentiateWithoutColor) private var withoutColor
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let progress = LifeStageCalculator.progress(from: bounds.0, to: bounds.1, at: context.date)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(store.t("lifeProgressTitle"))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(OWCDesign.secondary)
                        Spacer()
                        Text(store.formatPercent(progress * 100))
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .foregroundStyle(OWCDesign.orangeDeep)
                            .contentTransition(.numericText())
                    }
                    ProgressView(value: progress)
                        .tint(OWCDesign.orangeDeep)
                }
                .accessibilityElement(children: .combine)
            }

            GeometryReader { proxy in
                let grid = RecordsCanvasGrid(
                    size: proxy.size,
                    targetCell: 11,
                    gap: 3,
                    minimumColumns: 18,
                    minimumRows: 10
                )
                let buckets = LifeStageCalculator.buckets(
                    stages: stages,
                    from: bounds.0,
                    to: bounds.1,
                    count: grid.count,
                    now: referenceDate
                )
                Canvas { context, _ in
                    for bucket in buckets {
                        let rect = grid.rect(at: bucket.index)
                        let corner = min(3, grid.cell / 3)
                        let path = Path(roundedRect: rect, cornerRadius: corner)
                        let base = OWCDesign.lifeColor(bucket.kind)
                        let isDimmed = selectedStageID != nil && bucket.stageID != selectedStageID
                        let isFutureWork = bucket.kind == .work && bucket.isFuture
                        let fill = base.opacity(
                            bucket.isFuture
                                ? (isDimmed ? 0.14 : isFutureWork ? 0.20 : 0.28)
                                : (isDimmed ? 0.42 : 0.82)
                        )
                        context.fill(path, with: .color(fill))

                        if bucket.isFuture {
                            context.stroke(
                                Path(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), cornerRadius: corner),
                                with: .color(base.opacity(withoutColor ? 0.9 : isFutureWork ? 0.62 : 0.42)),
                                lineWidth: contrast == .increased ? 1.35 : 0.9
                            )
                            if isFutureWork {
                                var hatch = Path()
                                hatch.move(to: CGPoint(x: rect.minX + 2, y: rect.maxY - 2))
                                hatch.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.minY + 2))
                                context.stroke(hatch, with: .color(base.opacity(withoutColor ? 0.8 : 0.42)), lineWidth: 0.75)
                            }
                        }

                        if withoutColor, !bucket.isFuture {
                            context.stroke(
                                Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: corner),
                                with: .color(OWCDesign.primary.opacity(0.45)),
                                lineWidth: 0.75
                            )
                        }

                        if bucket.isCurrent {
                            context.stroke(
                                Path(roundedRect: rect.insetBy(dx: -1, dy: -1), cornerRadius: corner + 1),
                                with: .color(OWCDesign.primary),
                                lineWidth: contrast == .increased ? 2.2 : 1.8
                            )
                            context.stroke(
                                Path(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), cornerRadius: max(1, corner - 1)),
                                with: .color(OWCDesign.card),
                                lineWidth: contrast == .increased ? 1.5 : 1.2
                            )
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { value in
                    guard let index = grid.index(at: value.location), buckets.indices.contains(index) else { return }
                    let bucket = buckets[index]
                    let date = bucket.start.addingTimeInterval(bucket.end.timeIntervalSince(bucket.start) / 2)
                    if let stage = LifeStageCalculator.stage(at: date, stages: stages), stage.kind != .retirement {
                        select(stage, date: date)
                    }
                })
                .overlay {
                    ZStack {
                        if let stage = selectedStageSpan,
                           stage.kind != .retirement,
                           let bucket = selectedBucket(for: stage, in: buckets) {
                            let rect = grid.rect(at: bucket.index)
                            RecordsCanvasCalloutLayout(anchor: rect) {
                                RecordsCanvasCallout(
                                    icon: stage.kind.iconName,
                                    title: store.t(stage.titleKey),
                                    subtitle: stageRange(stage)
                                )
                            }
                            .transition(.opacity)
                        }
                    }
                    .animation(reduceMotion ? nil : OWCMotion.selection, value: selectedDate)
                    .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.selection, value: selectedStageID)
                }
                .accessibilityRepresentation {
                    VStack {
                        ForEach(stages) { stage in
                            if stage.kind == .retirement {
                                Text("\(store.t(stage.titleKey)), \(stageRange(stage))")
                            } else {
                                Button {
                                    select(stage, date: nil)
                                } label: {
                                    Text("\(store.t(stage.titleKey)), \(stageRange(stage))")
                                }
                                .accessibilityAddTraits(selectedStageID == stage.id ? .isSelected : [])
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 196, idealHeight: 240, maxHeight: .infinity)

            if showsStageLegend {
                VStack(spacing: 0) {
                    ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                        if stage.kind == .retirement {
                            OWCRow(
                                icon: stage.kind.iconName,
                                title: store.t(stage.titleKey),
                                subtitle: stageRange(stage),
                                isLast: index == stages.count - 1,
                                centersVertically: true
                            ) {
                                EmptyView()
                            }
                            .opacity(0.58)
                            .accessibilityLabel(store.t(stage.titleKey))
                        } else {
                            Button {
                                // A legend is not a specific point on the
                                // grid. Let the callout use the stage's first
                                // bucket instead of pretending the last tap
                                // still identifies this selection.
                                select(stage, date: nil)
                            } label: {
                                OWCRow(
                                    icon: stage.kind.iconName,
                                    title: store.t(stage.titleKey),
                                    subtitle: stageRange(stage),
                                    isLast: index == stages.count - 1,
                                    centersVertically: true
                                ) {
                                    Image(systemName: selectedStageID == stage.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(
                                            selectedStageID == stage.id
                                                ? OWCDesign.orangeDeep
                                                : OWCDesign.lifeColor(stage.kind)
                                        )
                                        .frame(width: 24, alignment: .center)
                                }
                                .background(
                                    selectedStageID == stage.id ? OWCDesign.orangeDeep.opacity(0.08) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                            }
                            .buttonStyle(OWCRowButtonStyle())
                            .accessibilityLabel(store.t(stage.titleKey))
                        }
                    }
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                if stages.contains(where: { $0.workPeriod != nil }) {
                    Text(store.t("lifeWorkPeriodBasis"))
                        .font(.caption)
                        .foregroundStyle(OWCDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        .animation(
            reduceMotion ? OWCMotion.reduced : OWCMotion.recordsScaleChange,
            value: showsStageLegend
        )
    }

    private func select(_ stage: LifeStageSpan, date: Date?) {
        selectedDate = date
        if selectedStageID != stage.id { onSelect(stage) }
    }

    private func stageRange(_ stage: LifeStageSpan) -> String {
        switch (stage.start, stage.end) {
        case (nil, nil):
            return store.t("lifeUnset")
        case (let start?, let end?):
            let startLabel = stage.workPeriod == .future && start == referenceDate
                ? store.t("lifeStagePresent") : yearLabel(start, stage.startPrecision)
            let endLabel = stage.workPeriod == .elapsed && end == referenceDate
                ? store.t("lifeStagePresent") : yearLabel(end, stage.endPrecision)
            return "\(startLabel) – \(endLabel)"
        case (let start?, nil):
            return yearLabel(start, stage.startPrecision)
        case (nil, let end?):
            return yearLabel(end, stage.endPrecision)
        }
    }

    private var selectedStageSpan: LifeStageSpan? {
        guard let selectedStageID else { return nil }
        return stages.first(where: { $0.id == selectedStageID })
    }

    private func selectedBucket(for stage: LifeStageSpan, in buckets: [LifeCanvasBucket]) -> LifeCanvasBucket? {
        if let selectedDate,
           let tapped = buckets.first(where: { $0.start <= selectedDate && selectedDate < $0.end && $0.stageID == stage.id }) {
            return tapped
        }
        if stage.workPeriod == .elapsed {
            return buckets.last(where: { $0.stageID == stage.id })
        }
        return buckets.first(where: { $0.stageID == stage.id })
    }

    private func yearLabel(_ date: Date, _ precision: CivilDatePrecision?) -> String {
        let year = store.recordsCalendar.component(.year, from: date)
        if precision == .year {
            return store.t("lifeYearApproximate", values: ["year": "\(year)"])
        }
        return "\(year)"
    }
}

private struct RecordsCanvasCallout: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(OWCDesign.secondary)
            }
        }
        // The anchor may move, but the label must immediately describe the
        // selected interval. Cross-fading glyphs makes two months overlap.
        .transaction { $0.animation = nil }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(OWCDesign.card, in: Capsule())
        .overlay { Capsule().stroke(OWCDesign.separator, lineWidth: 0.8) }
        .fixedSize(horizontal: false, vertical: true)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

private struct RecordsDayDetailHeader: View {
    let dateTitle: String
    let sourceTitle: String
    let sourceTint: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalHeader
            verticalHeader
        }
        .accessibilityElement(children: .combine)
    }

    private var horizontalHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            horizontalDate
            Spacer(minLength: 8)
            horizontalSource
        }
    }

    private var verticalHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            date
            source
        }
    }

    private var date: some View {
        Text(dateTitle)
            .font(.title3.weight(.semibold))
            .foregroundStyle(OWCDesign.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var horizontalDate: some View {
        Text(dateTitle)
            .font(.title3.weight(.semibold))
            .foregroundStyle(OWCDesign.primary)
            .fixedSize()
    }

    private var source: some View {
        Text(sourceTitle)
            .font(.caption.weight(.medium))
            .foregroundStyle(sourceTint)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(OWCDesign.control, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var horizontalSource: some View {
        Text(sourceTitle)
            .font(.caption.weight(.medium))
            .foregroundStyle(sourceTint)
            // Give ViewThatFits the real one-line width. If it cannot fit next
            // to the date, the vertical candidate below wins; this avoids
            // selecting a cramped horizontal layout merely because Text was
            // willing to wrap in its measurement pass.
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(OWCDesign.control, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// What solid, hatched, pencil and lock mean, next to the grid that uses them.
///
/// A legend shown once and then removed forever is a legend nobody can check.
/// It stays reachable: a wrapping row while it fits, an info button and a
/// popover once the text or the type size no longer allows the row.
struct RecordsMarkLegend: View {
    let store: OffWorkStore
    var includesLock: Bool
    @State private var showsPopover = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var items: [(symbol: String, key: String)] {
        var rows = [
            ("square.fill", "recordsLegendRecorded"),
            ("square.lefthalf.filled", "recordsLegendEstimated"),
            ("pencil", "recordsLegendCorrected"),
        ]
        if includesLock { rows.append(("lock.fill", "recordsLegendLocked")) }
        return rows
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Button {
                showsPopover = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(OWCDesign.tertiary)
            .accessibilityLabel(store.t("recordsLegendTitle"))
            .popover(isPresented: $showsPopover) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(store.t("recordsLegendTitle"))
                        .font(.headline)
                    ForEach(items, id: \.key) { item in
                        row(item)
                    }
                }
                .frame(idealWidth: 300, alignment: .leading)
                .padding(18)
                .presentationCompactAdaptation(.popover)
            }
        } else {
            // One row while the four fit; two columns once a language needs
            // the width. Truncating a legend defeats the point of having one.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(items, id: \.key) { item in
                        row(item).fixedSize()
                    }
                    Spacer(minLength: 0)
                }
                LazyVGrid(
                    columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                    alignment: .leading,
                    spacing: 4
                ) {
                    ForEach(items, id: \.key) { item in
                        row(item)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(store.t("recordsLegendTitle"))
        }
    }

    private func row(_ item: (symbol: String, key: String)) -> some View {
        HStack(spacing: 5) {
            Image(systemName: item.symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(store.t(item.key))
                .font(.caption2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(OWCDesign.secondary)
    }
}

/// The compact summary under the calendar.
///
/// It answers "what was this day, roughly" and then hands over: the whole
/// account of a day belongs on the day's own page, not stacked as a second
/// dense chart directly beneath the month grid.
struct RecordsDaySummaryCard: View {
    let store: OffWorkStore
    let detail: RecordsDayDetail?
    var locked: Bool
    var onUnlock: () -> Void

    var body: some View {
        if locked || detail == nil && !store.plus.isAuthorized {
            RecordsLockedPlaceholder(store: store, kind: .day, onUnlock: onUnlock)
        } else if let detail {
            OWCGroupCard {
                VStack(alignment: .leading, spacing: 12) {
                    RecordsDayDetailHeader(
                        dateTitle: store.formatRecordsDayTitle(detail.date),
                        sourceTitle: store.t(detail.sourceKey),
                        sourceTint: detail.isPlanned ? OWCDesign.accent : OWCDesign.secondary
                    )

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 18) {
                            workSummary(detail)
                            Spacer(minLength: 0)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            workSummary(detail)
                        }
                    }

                    Divider()

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(store.t("recordsFreeAwake"))
                            .font(.callout)
                            .foregroundStyle(OWCDesign.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text(store.formatRelativeDuration(Double(detail.breakMs + detail.freeMs)))
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .foregroundStyle(OWCDesign.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }

                    if detail.observations.count > 0 || detail.sleepMs > 0 {
                        markers(detail)
                    }

                    // A link, not a programmatic push: this card is hosted by
                    // three different navigation stacks and only the phone's is
                    // bound to `store.recordsPath`. Appending there did nothing
                    // at all on iPad, where the shell owns its own path.
                    NavigationLink(value: RecordsRoute.day(detail.dayKey)) {
                        HStack(spacing: 6) {
                            Text(store.t("recordsSeeThisDay"))
                                .font(.body.weight(.semibold))
                            Image(systemName: "chevron.forward")
                                .font(.footnote.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(OWCDesign.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
    }

    /// Two numbers at most, and an honest word when there are none. A rest day
    /// should say "rest", not print four zeroes.
    @ViewBuilder
    private func workSummary(_ detail: RecordsDayDetail) -> some View {
        if detail.regularWorkMs == 0 && detail.overtimeMs == 0 {
            Text(store.t(emptyKey(detail)))
                .font(.body)
                .foregroundStyle(OWCDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            amount("recordsWorkRegular", detail.regularWorkMs, color: OWCDesign.recordsWork)
            if detail.overtimeMs > 0 {
                amount("recordsOvertime", detail.overtimeMs, color: OWCDesign.recordsOvertime)
            }
        }
    }

    private func emptyKey(_ detail: RecordsDayDetail) -> String {
        switch detail.appearance {
        case .rest: "recordsRestDay"
        case .planned: "recordsPlanned"
        default: "recordsUnrecorded"
        }
    }

    private func amount(_ titleKey: String, _ milliseconds: Int64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(store.t(titleKey))
                    .font(.caption)
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(1)
            }
            Text(store.formatRelativeDuration(Double(milliseconds)))
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(OWCDesign.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }

    /// Restrained status, not a second data layer: how many things the app
    /// noticed, and where sleep came from. The detail is one tap away.
    private func markers(_ detail: RecordsDayDetail) -> some View {
        HStack(spacing: 10) {
            if !detail.observations.isEmpty {
                Label(
                    store.formatCount(detail.observations.count),
                    systemImage: "circle.dotted"
                )
            }
            Label(store.t(detail.sleepSourceKey), systemImage: "moon.zzz")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(OWCDesign.tertiary)
    }
}

/// The life scale's one conclusion.
///
/// Every other scale ends with a number that happened; this one ends with a
/// number that has not, so it says so first and stays descriptive. It reads a
/// projection held in memory and writes nothing: no override, no summary, no
/// observation, no record of any kind is created by looking at it.
struct RecordsLifeAllocationCard: View {
    let store: OffWorkStore
    let model: LifeViewModel?

    var body: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.t("lifeWhereTimeGoes"))
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(store.t("recordsSourceProjection"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(OWCDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let allocation = usableAllocation {
                    Text(
                        store.t(
                            "lifeAllocationEstimate",
                            values: [
                                "duration": store.formatRelativeDuration(
                                    Double(allocation.workMs + allocation.overtimeMs)
                                )
                            ]
                        )
                    )
                    .font(.body)
                    .foregroundStyle(OWCDesign.primary)
                    .fixedSize(horizontal: false, vertical: true)

                    RecordsAllocationBar(store: store, share: allocation)
                } else {
                    // No retirement boundary, no career, or a schedule the
                    // rules could not expand: say what is missing instead of
                    // inventing a percentage out of the parts that do exist.
                    Text(store.t("lifeAllocationMissing"))
                        .font(.body)
                        .foregroundStyle(OWCDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var usableAllocation: TimeAllocationShare? {
        guard let allocation = model?.allocation,
              allocation.dayLengthMs > 0,
              allocation.workMs > 0
        else { return nil }
        return allocation
    }
}
