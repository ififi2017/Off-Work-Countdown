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
        .sensoryFeedback(.selection, trigger: scale)
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
                VStack(spacing: 4) {
                    Text(store.t(titleKey))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(OWCDesign.primary)
                    Text(store.t("plusSeePlans"))
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
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
        .accessibilityLabel(store.t(titleKey))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(help.title)
                .font(.headline)
            Text(help.body)
                .font(.body)
                .foregroundStyle(OWCDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(idealWidth: 300, alignment: .leading)
        .padding(18)
        .presentationCompactAdaptation(.popover)
    }
}

struct RecordsHeadlineView: View {
    let store: OffWorkStore
    let summary: RecordsHeadlineSummary?
    var onUnlock: () -> Void
    @State private var selectedKind: TimeAllocationKind?
    @State private var selectedHelp: RecordsMetricHelp?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let summary {
            OWCGroupCard {
                VStack(alignment: .leading, spacing: 14) {
                    let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 2
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .topLeading), count: columns),
                        alignment: .leading,
                        spacing: 8
                    ) {
                        metric("recordsWorkdays", store.formatCount(summary.workdays), icon: "calendar.badge.checkmark", helpKey: "recordsMetricWorkdaysHelp")
                        metric("recordsWorkRegular", store.formatRelativeDuration(Double(summary.regularWorkMs)), icon: "briefcase.fill", helpKey: "recordsMetricWorkHelp")
                        metric("recordsOvertime", store.formatRelativeDuration(Double(summary.overtimeMs)), icon: "clock.fill", helpKey: "recordsMetricOvertimeHelp")
                        metric("recordsFreeAwakeShort", store.formatRelativeDuration(Double(summary.wakingFreeMs)), icon: "sun.max.fill", helpKey: "recordsMetricFreeHelp")
                        if let income = summary.estimatedIncome {
                            metric(
                                "recordsIncomeCurrentSalary",
                                store.moneyText(income),
                                icon: "banknote.fill",
                                helpKey: nil
                            )
                        }
                    }

                    Divider()

                    VStack(spacing: 6) {
                        allocationBar(summary.allocation)
                        allocationLegend(summary.allocation)
                    }

                    if let selectedKind, let item = slice(selectedKind, in: summary.allocation) {
                        Text(
                            store.t(
                                "recordsAllocationTap",
                                values: [
                                    "label": store.t(titleKey(selectedKind)),
                                    "duration": store.formatRelativeDuration(Double(item.ms)),
                                    "percent": store.formatPercent(item.percent),
                                ]
                            )
                        )
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                        .contentTransition(.numericText())
                    }
                    Text(store.t(summary.sleepSourceKey))
                        .font(.caption)
                        .foregroundStyle(OWCDesign.tertiary)
                }
                .padding(16)
            }
            .popover(item: $selectedHelp) { help in
                RecordsMetricHelpPopover(help: help)
            }
        } else {
            RecordsLockedPlaceholder(store: store, kind: .summary, onUnlock: onUnlock)
        }
    }

    private func metric(_ titleKey: String, _ value: String, icon: String, helpKey: String?) -> some View {
        let title = store.t(titleKey)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OWCDesign.accent)
                    .frame(width: 28, height: 28)
                    .background(OWCDesign.accent.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: 0)
            }
            .padding(.trailing, helpKey == nil ? 0 : 32)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(OWCDesign.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.56)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, minHeight: 65, alignment: .topLeading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .topTrailing) {
            if let helpKey {
                RecordsMetricHelpButton(
                    title: title,
                    message: store.t(helpKey),
                    selection: $selectedHelp
                )
                .padding(.top, 4)
                .padding(.trailing, 2)
            }
        }
        .background(OWCDesign.elevated, in: RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous))
    }

    @ViewBuilder
    private func allocationBar(_ share: TimeAllocationShare) -> some View {
        let visible = slices(share).filter { $0.ms > 0 }
        let total = max(1, share.dayLengthMs)
        GeometryReader { proxy in
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
                    .accessibilityLabel(store.t(titleKey(item.kind)))
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

    private func allocationLegend(_ share: TimeAllocationShare) -> some View {
        return LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(slices(share).filter { $0.kind != .unclassified || $0.ms > 0 }) { item in
                Button {
                    selectedKind = item.kind
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 10, height: 10)
                        Text(store.t(titleKey(item.kind)))
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

    private func titleKey(_ kind: TimeAllocationKind) -> String {
        switch kind {
        case .work: "recordsWorkRegular"
        case .overtime: "recordsOvertime"
        case .workBreak: "recordsBreakTime"
        case .sleep: "recordsSleep"
        case .free: "recordsFreeAwakeShort"
        case .unclassified: "recordsUnclassified"
        }
    }

    private func slice(_ kind: TimeAllocationKind, in share: TimeAllocationShare) -> (titleKey: String, ms: Int64, percent: Double)? {
        let ms: Int64 = switch kind {
        case .work: share.workMs
        case .overtime: share.overtimeMs
        case .workBreak: share.breakMs
        case .sleep: share.sleepMs
        case .free: share.freeMs
        case .unclassified: share.unclassifiedMs
        }
        guard share.dayLengthMs > 0 else { return nil }
        return (titleKey(kind), ms, Double(ms) / Double(share.dayLengthMs) * 100)
    }

    private func slices(_ share: TimeAllocationShare) -> [AllocationSlice] {
        [
            AllocationSlice(kind: .work, ms: share.workMs, color: OWCDesign.recordsWork),
            AllocationSlice(kind: .overtime, ms: share.overtimeMs, color: OWCDesign.recordsOvertime),
            AllocationSlice(kind: .workBreak, ms: share.breakMs, color: OWCDesign.recordsBreak),
            AllocationSlice(kind: .sleep, ms: share.sleepMs, color: OWCDesign.recordsSleep),
            AllocationSlice(kind: .free, ms: share.freeMs, color: OWCDesign.recordsFree),
            AllocationSlice(kind: .unclassified, ms: share.unclassifiedMs, color: OWCDesign.recordsUnclassified),
        ]
    }

    private struct AllocationSlice: Identifiable {
        var id: TimeAllocationKind { kind }
        let kind: TimeAllocationKind
        let ms: Int64
        let color: Color
    }
}

struct RecordsMonthGrid: View {
    let store: OffWorkStore
    let cells: [RecordsDayCell]
    let selectedDayKey: String?
    var onSelect: (RecordsDayCell) -> Void

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
                            .overlay {
                                Text(store.formatCount(store.recordsCalendar.component(.day, from: cell.date)))
                                    .font(.callout.weight(cell.isToday || cell.dayKey == selectedDayKey ? .semibold : .regular).monospacedDigit())
                                    .foregroundStyle(label(cell))
                            }
                            .overlay(alignment: .bottom) {
                                activityMarker(cell)
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
                                        lineWidth: cell.dayKey == selectedDayKey ? 2 : 1.25
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibility(cell))
                }
            }
        }
        // A seven-column calendar cannot reflow without ceasing to be a
        // calendar. Cap only its dense labels while VoiceOver retains the full
        // localized date and status for every 44-point button.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func fill(_ cell: RecordsDayCell) -> Color {
        if cell.dayKey == selectedDayKey { return OWCDesign.accent }
        return switch cell.appearance {
        case .locked: OWCDesign.control.opacity(0.45)
        case .unrecorded: Color.clear
        case .rest: OWCDesign.control.opacity(0.36)
        case .planned: OWCDesign.accent.opacity(0.085)
        case .recorded: OWCDesign.accent.opacity(0.10)
        case .corrected: OWCDesign.accent.opacity(0.14)
        }
    }

    private func label(_ cell: RecordsDayCell) -> Color {
        if cell.dayKey == selectedDayKey { return .white }
        if cell.appearance == .locked { return OWCDesign.tertiary }
        if cell.isToday { return OWCDesign.accent }
        return OWCDesign.primary
    }

    private func stroke(_ cell: RecordsDayCell) -> Color {
        if cell.dayKey == selectedDayKey { return OWCDesign.accent }
        if cell.appearance == .corrected { return OWCDesign.accent.opacity(0.65) }
        if cell.isToday { return OWCDesign.accent }
        if cell.appearance == .planned { return OWCDesign.accent.opacity(0.45) }
        return .clear
    }

    @ViewBuilder
    private func activityMarker(_ cell: RecordsDayCell) -> some View {
        if cell.dayKey != selectedDayKey,
           cell.appearance == .recorded || cell.appearance == .corrected {
            Capsule()
                .fill(OWCDesign.accent)
                .frame(width: min(22, max(8, 8 + CGFloat(cell.workMs) / 3_600_000)), height: 3)
        }
    }

    @ViewBuilder
    private func stateMarker(_ cell: RecordsDayCell) -> some View {
        if cell.hasConflict {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(cell.dayKey == selectedDayKey ? .white : OWCDesign.orangeDeep)
        } else if cell.appearance == .corrected {
            Image(systemName: "pencil")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(cell.dayKey == selectedDayKey ? .white : OWCDesign.accent)
        } else if cell.appearance == .locked {
            Image(systemName: "lock.fill")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(OWCDesign.tertiary)
        }
    }

    private func accessibility(_ cell: RecordsDayCell) -> String {
        if cell.appearance == .locked { return store.t("recordsLockedDay") }
        let status = if cell.isProjection {
            store.t("recordsSourceProjection")
        } else { switch cell.appearance {
        case .unrecorded: store.t("recordsUnrecorded")
        case .recorded: store.t("recordsSourceSchedule")
        case .corrected: store.t("recordsSourceOverride")
        case .planned: store.t("recordsPlanned")
        case .rest: store.t("recordsRestDay")
        case .locked: store.t("recordsLockedDay")
        } }
        return "\(store.formatRecordsDayTitle(cell.date)), \(status)"
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
                }
                .buttonStyle(.plain)
                .accessibilityLabel(cell.appearance == .locked ? store.t("recordsLockedDay") : store.formatRecordsDayTitle(cell.date))
            }
        }
        .frame(height: 188)
    }

    private func weekStack(_ cell: RecordsDayCell) -> some View {
        ZStack(alignment: .bottom) {
            weekTrack(cell)
            if cell.observationCount > 0 {
                Circle()
                    .fill(OWCDesign.accent)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(OWCDesign.card, lineWidth: 2))
                    .offset(y: 4)
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

    private func workloadColumn(_ cell: RecordsDayCell) -> some View {
        let work = min(1, Double(cell.workMs + cell.overtimeMs) / (12 * 3_600_000))
        return ZStack(alignment: .bottom) {
            Capsule().fill(OWCDesign.control.opacity(0.72))
            // The minimum height is only a visibility aid for a real, short
            // work interval. Applying it to zero turned rest days into a
            // misleading orange baseline.
            if work > 0 {
                Capsule()
                    .fill(cell.overtimeMs > 0 ? OWCDesign.recordsOvertime : OWCDesign.recordsWork)
                    .frame(height: max(5, 116 * work))
            }
        }
        .frame(width: 18, height: 116)
        .overlay { Capsule().stroke(OWCDesign.separator, lineWidth: 0.5) }
    }

}

struct RecordsYearCanvas: View {
    let store: OffWorkStore
    let cells: [RecordsDayCell]
    let selectedMonth: Int?
    var onSelectMonth: (Int) -> Void
    @Environment(\.accessibilityDifferentiateWithoutColor) private var withoutColor
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var calloutMonth: Int?
    @State private var selectedBucketIndex: Int?

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
                            for rect in grid.selectionRects(for: buckets.filter { $0.month == selectedMonth }.map(\.index)) {
                                context.stroke(
                                    Path(roundedRect: rect, cornerRadius: min(4, grid.cell / 2)),
                                    with: .color(OWCDesign.primary.opacity(0.72)),
                                    lineWidth: contrast == .increased ? 1.8 : 1.25
                                )
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                        guard let index = grid.index(at: value.location), buckets.indices.contains(index) else { return }
                        select(month: buckets[index].month, bucketIndex: buckets[index].index)
                    })
                    .overlay {
                        if let calloutMonth,
                           let bucket = calloutBucket(for: calloutMonth, in: buckets) {
                            let rect = grid.rect(at: bucket.index)
                            RecordsCanvasCallout(
                                icon: "calendar",
                                title: monthLabel(calloutMonth),
                                subtitle: yearLabel
                            )
                            .position(
                                x: min(proxy.size.width - 76, max(76, rect.midX)),
                                y: min(proxy.size.height - 28, max(28, rect.minY - 18))
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        }
                    }
                    .accessibilityRepresentation {
                        VStack {
                            ForEach(1...12, id: \.self) { month in
                                Button {
                                    select(month: month, bucketIndex: nil)
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
                        select(month: month, bucketIndex: nil)
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
        }
        .animation(
            reduceMotion ? OWCMotion.reduced : .easeOut(duration: 0.18),
            value: selectedMonth
        )
    }

    private func color(_ bucket: RecordsYearBucket) -> Color {
        let base = switch bucket.kind {
        case .locked: OWCDesign.control.opacity(0.86)
        case .unrecorded, .rest: OWCDesign.control.opacity(0.65)
        case .planned: OWCDesign.accent.opacity(withoutColor ? 0.84 : 0.46)
        case .recorded: OWCDesign.accent.opacity(withoutColor ? 0.96 : min(0.96, 0.54 + Double(bucket.workMs) / 57_600_000))
        case .corrected: OWCDesign.orangeDeep.opacity(0.96)
        }
        guard let selectedMonth, bucket.month != selectedMonth else { return base }
        return base.opacity(0.58)
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

    private func select(month: Int, bucketIndex: Int?) {
        onSelectMonth(month)
        calloutMonth = month
        selectedBucketIndex = bucketIndex
    }

    private func calloutBucket(
        for month: Int,
        in buckets: [RecordsYearBucket]
    ) -> RecordsYearBucket? {
        if let selectedBucketIndex,
           let tapped = buckets.first(where: { $0.index == selectedBucketIndex && $0.month == month }) {
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
        .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.selection, value: selectedMonth)
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
                        // A dashed outline rather than a paler fill: "not yet"
                        // has to survive Differentiate Without Color, and a
                        // low-opacity solid does not.
                        Capsule()
                            .strokeBorder(
                                OWCDesign.secondary.opacity(0.65),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                            )
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
            legendItem(store.t("recordsSourceProjection"), color: OWCDesign.secondary, dashed: true)
        }
    }

    private func legendItem(_ title: String, color: Color, dashed: Bool) -> some View {
        HStack(spacing: 5) {
            Group {
                if dashed {
                    Capsule().strokeBorder(color.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
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

private struct RecordsCanvasGrid {
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
        guard pitch > 0 else { return nil }
        let column = Int(point.x / pitch)
        let row = Int(point.y / pitch)
        guard column >= 0, column < columns, row >= 0, row < rows else { return nil }
        return row * columns + column
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
                x: leading.minX - 1.5,
                y: leading.minY - 1.5,
                width: trailing.maxX - leading.minX + 3,
                height: cell + 3
            )
        }
    }
}

struct RecordsLifeCanvas: View {
    let store: OffWorkStore
    let stages: [LifeStageSpan]
    let bounds: (Date, Date)
    let selectedStage: LifeStageKind?
    var showsStageLegend = true
    var onSelect: (LifeStageSpan) -> Void
    @Environment(\.accessibilityDifferentiateWithoutColor) private var withoutColor
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedBucketIndex: Int?

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
                    now: .now
                )
                Canvas { context, _ in
                    for bucket in buckets {
                        let rect = grid.rect(at: bucket.index)
                        let corner = min(3, grid.cell / 3)
                        let path = Path(roundedRect: rect, cornerRadius: corner)
                        let base = OWCDesign.lifeColor(bucket.kind)
                        let isDimmed = selectedStage != nil && bucket.kind != selectedStage
                        let isFutureWork = bucket.kind == .work && bucket.isFuture
                        let fill = base.opacity(
                            bucket.isFuture
                                ? (isDimmed ? 0.06 : isFutureWork ? 0.20 : 0.28)
                                : (isDimmed ? 0.22 : 0.82)
                        )
                        context.fill(path, with: .color(fill))

                        if bucket.isFuture {
                            context.stroke(
                                Path(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), cornerRadius: corner),
                                with: .color(base.opacity(withoutColor ? 0.9 : isFutureWork ? 0.62 : 0.42)),
                                lineWidth: contrast == .increased ? 1.35 : 0.9
                            )
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
                .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                    guard let index = grid.index(at: value.location), buckets.indices.contains(index) else { return }
                    let bucket = buckets[index]
                    let date = bucket.start.addingTimeInterval(bucket.end.timeIntervalSince(bucket.start) / 2)
                    if let stage = LifeStageCalculator.stage(at: date, stages: stages), stage.kind != .retirement {
                        selectedBucketIndex = bucket.index
                        onSelect(stage)
                    }
                })
                .overlay {
                    if let stage = selectedStageSpan,
                       stage.kind != .retirement,
                       let bucket = selectedBucket(for: stage, in: buckets) {
                        let rect = grid.rect(at: bucket.index)
                        RecordsCanvasCallout(
                            icon: stage.kind.iconName,
                            title: store.t(stage.kind.titleKey),
                            subtitle: stageRange(stage)
                        )
                            .position(
                                x: min(proxy.size.width - 76, max(76, rect.midX)),
                                y: min(proxy.size.height - 28, max(28, rect.minY - 18))
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        }
                }
                .accessibilityRepresentation {
                    VStack {
                        ForEach(stages) { stage in
                            if stage.kind == .retirement {
                                Text("\(store.t(stage.kind.titleKey)), \(stageRange(stage))")
                            } else {
                                Button {
                                    selectedBucketIndex = selectedBucket(for: stage, in: buckets)?.index
                                    onSelect(stage)
                                } label: {
                                    Text("\(store.t(stage.kind.titleKey)), \(stageRange(stage))")
                                }
                                .accessibilityAddTraits(selectedStage == stage.kind ? .isSelected : [])
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
                                title: store.t(stage.kind.titleKey),
                                subtitle: stageRange(stage),
                                isLast: index == stages.count - 1,
                                centersVertically: true
                            ) {
                                EmptyView()
                            }
                            .opacity(0.58)
                            .accessibilityLabel(store.t(stage.kind.titleKey))
                        } else {
                            Button {
                                // A legend is not a specific point on the
                                // grid. Let the callout use the stage's first
                                // bucket instead of pretending the last tap
                                // still identifies this selection.
                                selectedBucketIndex = nil
                                onSelect(stage)
                            } label: {
                                OWCRow(
                                    icon: stage.kind.iconName,
                                    title: store.t(stage.kind.titleKey),
                                    subtitle: stageRange(stage),
                                    isLast: index == stages.count - 1,
                                    centersVertically: true
                                ) {
                                    Image(systemName: selectedStage == stage.kind ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(
                                            selectedStage == stage.kind
                                                ? OWCDesign.orangeDeep
                                                : OWCDesign.lifeColor(stage.kind)
                                        )
                                        .frame(width: 24, alignment: .center)
                                }
                                .background(
                                    selectedStage == stage.kind ? OWCDesign.orangeDeep.opacity(0.08) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                            }
                            .buttonStyle(OWCRowButtonStyle())
                            .accessibilityLabel(store.t(stage.kind.titleKey))
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(
            reduceMotion ? OWCMotion.reduced : .easeOut(duration: 0.18),
            value: selectedStage
        )
        .animation(
            reduceMotion ? OWCMotion.reduced : .easeOut(duration: 0.2),
            value: showsStageLegend
        )
    }

    private func stageRange(_ stage: LifeStageSpan) -> String {
        switch (stage.start, stage.end) {
        case (nil, nil):
            return store.t("lifeUnset")
        case (let start?, let end?):
            return "\(yearLabel(start, stage.startPrecision)) – \(yearLabel(end, stage.endPrecision))"
        case (let start?, nil):
            return yearLabel(start, stage.startPrecision)
        case (nil, let end?):
            return yearLabel(end, stage.endPrecision)
        }
    }

    private var selectedStageSpan: LifeStageSpan? {
        guard let selectedStage else { return nil }
        return stages.first(where: { $0.kind == selectedStage })
    }

    private func selectedBucket(for stage: LifeStageSpan, in buckets: [LifeCanvasBucket]) -> LifeCanvasBucket? {
        if let selectedBucketIndex,
           let tapped = buckets.first(where: { $0.index == selectedBucketIndex && $0.kind == stage.kind }) {
            return tapped
        }
        return buckets.first(where: { $0.kind == stage.kind })
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
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(OWCDesign.card, in: Capsule())
        .overlay { Capsule().stroke(OWCDesign.separator, lineWidth: 0.8) }
        .accessibilityElement(children: .combine)
    }
}

struct RecordsDayDetailCard: View {
    let store: OffWorkStore
    let detail: RecordsDayDetail?
    var locked: Bool
    var onUnlock: () -> Void
    var onEdit: () -> Void
    @State private var selectedHelp: RecordsMetricHelp?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if locked || detail == nil && !store.plus.isAuthorized {
            RecordsLockedPlaceholder(store: store, kind: .day, onUnlock: onUnlock)
        } else if let detail {
            OWCGroupCard {
                VStack(alignment: .leading, spacing: 14) {
                    RecordsDayDetailHeader(
                        dateTitle: store.formatRecordsDayTitle(detail.date),
                        sourceTitle: store.t(
                            detail.isProjection
                                ? detail.sourceKey
                                : detail.appearance == .unrecorded ? "recordsUnrecorded" : detail.sourceKey
                        ),
                        sourceTint: detail.isPlanned ? OWCDesign.accent : OWCDesign.secondary
                    )

                    if dynamicTypeSize.isAccessibilitySize {
                        LazyVGrid(columns: [GridItem(.flexible())], spacing: 8) {
                            detailMetric("recordsWorkRegular", detail.regularWorkMs, color: OWCDesign.recordsWork, helpKey: "recordsMetricWorkHelp")
                            detailMetric("recordsOvertime", detail.overtimeMs, color: OWCDesign.recordsOvertime, helpKey: "recordsMetricOvertimeHelp")
                            detailMetric("recordsBreakTime", detail.breakMs, color: OWCDesign.recordsBreak, helpKey: "recordsMetricBreakHelp")
                            detailMetric("recordsSleep", detail.sleepMs, color: OWCDesign.recordsSleep, helpKey: "recordsMetricSleepHelp")
                            detailMetric("recordsFreeAwakeShort", detail.freeMs, color: OWCDesign.recordsFree, helpKey: "recordsMetricFreeHelp")
                        }
                    } else {
                        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                            GridRow {
                                detailMetric("recordsWorkRegular", detail.regularWorkMs, color: OWCDesign.recordsWork, helpKey: "recordsMetricWorkHelp")
                                detailMetric("recordsOvertime", detail.overtimeMs, color: OWCDesign.recordsOvertime, helpKey: "recordsMetricOvertimeHelp")
                            }
                            GridRow {
                                detailMetric("recordsBreakTime", detail.breakMs, color: OWCDesign.recordsBreak, helpKey: "recordsMetricBreakHelp")
                                detailMetric("recordsSleep", detail.sleepMs, color: OWCDesign.recordsSleep, helpKey: "recordsMetricSleepHelp")
                            }
                            GridRow {
                                wideDetailMetric("recordsFreeAwakeShort", detail.freeMs, color: OWCDesign.recordsFree, helpKey: "recordsMetricFreeHelp")
                                    .gridCellColumns(2)
                            }
                        }
                    }

                    Text(store.t(detail.sleepSourceKey))
                        .font(.caption)
                        .foregroundStyle(OWCDesign.tertiary)

                    focusHistory(detail.dayKey)

                    Divider()

                    if detail.observations.isEmpty {
                        Text(store.t("recordsNoObservations"))
                            .font(.footnote)
                            .foregroundStyle(OWCDesign.secondary)
                    } else {
                        ForEach(detail.observations, id: \.self) { line in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(OWCDesign.accent)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 6)
                                Text(line)
                                    .font(.footnote)
                            }
                        }
                    }

                    if store.plus.isAuthorized {
                        Button(action: onEdit) {
                            Label(store.t("recordsEditDay"), systemImage: "pencil")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(OWCDesign.accent)
                    } else {
                        Text(store.t("recordsEditPlusHint"))
                            .font(.footnote)
                            .foregroundStyle(OWCDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .popover(item: $selectedHelp) { help in
                RecordsMetricHelpPopover(help: help)
            }
        }
    }

    @ViewBuilder
    private func focusHistory(_ dayKey: String) -> some View {
        let sessions = store.focusSessions(forDayKey: dayKey)
        if !sessions.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Label(store.t("focusHistory"), systemImage: "timer")
                    .font(.body.weight(.semibold))
                ForEach(sessions) { session in
                    let task = session.taskID.flatMap { id in
                        store.records.state.focusTasks.first(where: { $0.id == id })
                    }
                    let end = session.endedAt ?? min(.now, session.plannedEndAt)
                    HStack(spacing: 10) {
                        Image(systemName: task?.icon.systemName ?? "timer")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(OWCDesign.accent)
                            .frame(width: 30, height: 30)
                            .background(OWCDesign.accent.opacity(0.11), in: Circle())
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
                                store.t(focusReasonKey(session.endReason)),
                                systemImage: focusReasonSymbol(session.endReason)
                            )
                            .labelStyle(.titleAndIcon)
                            .font(.caption2)
                            .foregroundStyle(OWCDesign.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func focusReasonKey(_ reason: FocusEndReason?) -> String {
        switch reason {
        case .completed: "focusHistoryCompleted"
        case .stoppedByUser: "focusHistoryStopped"
        case .stoppedAtBoundary: "focusHistoryBoundary"
        case .abandoned: "focusHistoryAbandoned"
        case .supersededBySync: "focusHistorySupersededBySync"
        case nil: "focusRunning"
        }
    }

    private func focusReasonSymbol(_ reason: FocusEndReason?) -> String {
        switch reason {
        case .completed: "checkmark.circle.fill"
        case .stoppedByUser: "stop.circle"
        case .stoppedAtBoundary: "pause.circle"
        case .abandoned: "exclamationmark.circle"
        case .supersededBySync: "arrow.triangle.2.circlepath"
        case nil: "circle.dotted"
        }
    }

    private func detailMetric(_ titleKey: String, _ milliseconds: Int64, color: Color, helpKey: String) -> some View {
        let title = store.t(titleKey)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: 0)
            }
            .padding(.trailing, 32)
            Text(store.formatRelativeDuration(Double(milliseconds)))
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(OWCDesign.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .topTrailing) {
            RecordsMetricHelpButton(
                title: title,
                message: store.t(helpKey),
                selection: $selectedHelp
            )
            .padding(.top, 4)
            .padding(.trailing, 2)
        }
        .background(OWCDesign.elevated, in: RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous))
    }

    private func wideDetailMetric(_ titleKey: String, _ milliseconds: Int64, color: Color, helpKey: String) -> some View {
        let title = store.t(titleKey)
        return VStack(spacing: 5) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.callout)
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                RecordsMetricHelpButton(
                    title: title,
                    message: store.t(helpKey),
                    selection: $selectedHelp
                )
                .frame(width: 32, height: 24)
            }
            Text(store.formatRelativeDuration(Double(milliseconds)))
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(OWCDesign.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, minHeight: 70)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(OWCDesign.elevated, in: RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous))
    }
}

/// Keeps a long source/status label from competing with the date title. The
/// horizontal arrangement is used when it genuinely fits; German, Arabic,
/// and accessibility text sizes get a full-width second line instead of a
/// single-line capsule that truncates or squeezes the title.
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

struct RecordsYearSelectionCard: View {
    let store: OffWorkStore
    let month: Int
    let cells: [RecordsDayCell]
    let summary: RecordsHeadlineSummary?
    @State private var selectedHelp: RecordsMetricHelp?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let summary {
            OWCGroupCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title)
                        .font(.title3.weight(.semibold))

                    let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 2
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns),
                        alignment: .leading,
                        spacing: 8
                    ) {
                        metric("recordsWorkdays", store.formatCount(summary.workdays), helpKey: "recordsMetricWorkdaysHelp")
                        metric("recordsWorkRegular", store.formatRelativeDuration(Double(summary.regularWorkMs)), helpKey: "recordsMetricWorkHelp")
                        metric("recordsOvertime", store.formatRelativeDuration(Double(summary.overtimeMs)), helpKey: "recordsMetricOvertimeHelp")
                        metric("recordsFreeAwakeShort", store.formatRelativeDuration(Double(summary.wakingFreeMs)), helpKey: "recordsMetricFreeHelp")
                        if let income = summary.estimatedIncome {
                            metric(
                                "recordsIncomeCurrentSalary",
                                store.moneyText(income),
                                helpKey: nil
                            )
                        }
                    }
                }
                .padding(16)
            }
            .popover(item: $selectedHelp) { help in
                RecordsMetricHelpPopover(help: help)
            }
        }
    }

    private var title: String {
        var parts = store.recordsCalendar.dateComponents([.year], from: cells.first?.date ?? .now)
        parts.month = month
        parts.day = 1
        return store.formatRecordsMonthYear(store.recordsCalendar.date(from: parts) ?? .now)
    }

    private func metric(_ titleKey: String, _ value: String, helpKey: String?) -> some View {
        let label = store.t(titleKey)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.trailing, helpKey == nil ? 0 : 32)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(OWCDesign.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.56)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, minHeight: 65, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .topTrailing) {
            if let helpKey {
                RecordsMetricHelpButton(
                    title: label,
                    message: store.t(helpKey),
                    selection: $selectedHelp
                )
                .padding(.top, 4)
                .padding(.trailing, 2)
            }
        }
        .background(OWCDesign.elevated, in: RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous))
    }
}
