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

    private func metric(_ titleKey: String, _ value: String, icon: String, helpKey: String) -> some View {
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
                Spacer(minLength: 0)
            }
            .padding(.trailing, 32)
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

    @ViewBuilder
    private func allocationBar(_ share: TimeAllocationShare) -> some View {
        let visible = slices(share).filter { $0.ms > 0 }
        let total = max(1, share.dayLengthMs)
        GeometryReader { proxy in
            let gaps = CGFloat(max(visible.count - 1, 0)) * 3
            HStack(spacing: 3) {
                ForEach(visible) { item in
                    Button {
                        selectedKind = item.kind
                    } label: {
                        Capsule()
                            .fill(item.color)
                            .frame(width: max(8, (proxy.size.width - gaps) * CGFloat(item.ms) / CGFloat(total)), height: 14)
                            .overlay {
                                if selectedKind == item.kind {
                                    Capsule().stroke(OWCDesign.primary, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 10, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .accessibilityLabel(store.t(titleKey(item.kind)))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 44)
    }

    private func allocationLegend(_ share: TimeAllocationShare) -> some View {
        return LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(slices(share).filter { $0.kind != .unclassified || $0.ms > 0 }) { item in
                Button {
                    selectedKind = item.kind
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 8, height: 8)
                        Text(store.t(titleKey(item.kind)))
                            .font(.caption)
                            .foregroundStyle(OWCDesign.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Spacer(minLength: 12)
                        Text(store.formatRelativeDuration(Double(item.ms)))
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(OWCDesign.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                            .allowsTightening(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
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
            AllocationSlice(kind: .work, ms: share.workMs, color: OWCDesign.lifeWork),
            AllocationSlice(kind: .overtime, ms: share.overtimeMs, color: OWCDesign.orangeDeep),
            AllocationSlice(kind: .workBreak, ms: share.breakMs, color: OWCDesign.lifeStudy),
            AllocationSlice(kind: .sleep, ms: share.sleepMs, color: OWCDesign.lifeChildhood),
            AllocationSlice(kind: .free, ms: share.freeMs, color: OWCDesign.lifeRetirement),
            AllocationSlice(kind: .unclassified, ms: share.unclassifiedMs, color: OWCDesign.separator),
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
                    Color.clear.frame(height: 44)
                }
                ForEach(cells) { cell in
                    Button {
                        onSelect(cell)
                    } label: {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(fill(cell))
                            .frame(height: 44)
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
                            .overlay(alignment: .topLeading) {
                                if cell.isProjection, cell.appearance != .locked {
                                    Capsule()
                                        .fill(cell.dayKey == selectedDayKey ? Color.white.opacity(0.8) : OWCDesign.accent.opacity(0.7))
                                        .frame(width: 1.5, height: 11)
                                        .rotationEffect(.degrees(45))
                                        .padding(5)
                                        .accessibilityHidden(true)
                                }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(
                                        stroke(cell),
                                        style: StrokeStyle(
                                            lineWidth: cell.dayKey == selectedDayKey ? 2 : 1.25,
                                            dash: cell.appearance == .planned ? [3, 2] : []
                                        )
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
        case .planned: OWCDesign.accent.opacity(0.06)
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
        let total = max(1, cell.workMs + cell.overtimeMs + cell.breakMs + cell.freeMs)
        return ZStack(alignment: .bottom) {
            Capsule()
                .fill(OWCDesign.control.opacity(0.6))
                .frame(width: 18, height: 116)

            if cell.appearance == .locked {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(OWCDesign.tertiary)
                    .padding(.bottom, 10)
            } else {
                VStack(spacing: 2) {
                    if cell.freeMs > 0 {
                        Capsule().fill(OWCDesign.lifeRetirement).frame(width: 18, height: bar(cell.freeMs, total: total))
                    }
                    if cell.breakMs > 0 {
                        Capsule().fill(OWCDesign.lifeStudy).frame(width: 18, height: bar(cell.breakMs, total: total))
                    }
                    if cell.workMs > 0 {
                        Capsule().fill(OWCDesign.lifeWork).frame(width: 18, height: bar(cell.workMs, total: total))
                    }
                    if cell.overtimeMs > 0 {
                        Capsule().fill(OWCDesign.orangeDeep).frame(width: 18, height: bar(cell.overtimeMs, total: total))
                    }
                }
                .opacity(cell.isProjection ? 0.48 : 1)
            }

            if cell.observationCount > 0 {
                Circle()
                    .fill(OWCDesign.accent)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(OWCDesign.card, lineWidth: 2))
                    .offset(y: 4)
            }
        }
    }

    private func bar(_ ms: Int64, total: Int64) -> CGFloat {
        max(4, CGFloat(ms) / CGFloat(total) * 108)
    }
}

struct RecordsYearCanvas: View {
    let store: OffWorkStore
    let cells: [RecordsDayCell]
    let selectedMonth: Int?
    var showsMonthPicker = true
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
                            if bucket.kind == .planned || bucket.isProjection {
                                var marker = Path()
                                marker.move(to: CGPoint(x: rect.minX + 2, y: rect.maxY - 2))
                                marker.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.minY + 2))
                                context.stroke(marker, with: .color(OWCDesign.accent.opacity(0.7)), lineWidth: 0.8)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                        guard let index = grid.index(at: value.location), buckets.indices.contains(index) else { return }
                        onSelectMonth(buckets[index].month)
                    })
                } else {
                    Color.clear
                }
            }
            .frame(minHeight: 184, idealHeight: 220, maxHeight: .infinity)
            .accessibilityHidden(true)

            if showsMonthPicker {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(1...12, id: \.self) { month in
                        Button {
                            onSelectMonth(month)
                        } label: {
                            HStack(spacing: 4) {
                                Text(monthLabel(month))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                if selectedMonth == month {
                                    Image(systemName: "checkmark")
                                        .font(.caption2.bold())
                                        .accessibilityHidden(true)
                                }
                            }
                            .font(.footnote.weight(selectedMonth == month ? .semibold : .medium))
                            .foregroundStyle(selectedMonth == month ? OWCDesign.orangeDeep : OWCDesign.secondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                selectedMonth == month
                                    ? OWCDesign.orangeDeep.opacity(0.08)
                                    : OWCDesign.control,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .overlay(alignment: .leading) {
                                if selectedMonth == month {
                                    Capsule()
                                        .fill(OWCDesign.orangeDeep)
                                        .frame(width: 3, height: 22)
                                        .padding(.leading, 5)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(
            reduceMotion ? OWCMotion.reduced : .easeOut(duration: 0.18),
            value: selectedMonth
        )
        .animation(
            reduceMotion ? OWCMotion.reduced : .easeOut(duration: 0.2),
            value: showsMonthPicker
        )
    }

    private func color(_ bucket: RecordsYearBucket) -> Color {
        let base = switch bucket.kind {
        case .locked: OWCDesign.control.opacity(0.7)
        case .unrecorded, .rest: OWCDesign.control.opacity(0.42)
        case .planned: OWCDesign.accent.opacity(0.12)
        case .recorded: OWCDesign.accent.opacity(withoutColor ? 0.92 : min(0.88, 0.20 + Double(bucket.workMs) / 43_200_000))
        case .corrected: OWCDesign.orangeDeep.opacity(withoutColor ? 0.92 : 0.78)
        }
        guard let selectedMonth, bucket.month != selectedMonth else { return base }
        return base.opacity(0.34)
    }

    private func monthLabel(_ month: Int) -> String {
        var parts = store.recordsCalendar.dateComponents([.year], from: cells.first?.date ?? .now)
        parts.month = month
        parts.day = 1
        let date = store.recordsCalendar.date(from: parts) ?? .now
        return store.formatRecordsMonth(date)
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
                        let fill = base.opacity(
                            bucket.isFuture
                                ? (isDimmed ? 0.08 : 0.34)
                                : (isDimmed ? 0.22 : 0.82)
                        )
                        context.fill(path, with: .color(fill))

                        if bucket.isFuture {
                            var texture = Path()
                            texture.move(to: CGPoint(x: rect.minX + 1, y: rect.maxY - 1))
                            texture.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.minY + 1))
                            context.stroke(
                                texture,
                                with: .color(OWCDesign.lifeColor(bucket.kind).opacity(withoutColor ? 0.9 : 0.55)),
                                lineWidth: contrast == .increased ? 1.1 : 0.75
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
                    if let stage = LifeStageCalculator.stage(at: date, stages: stages) {
                        onSelect(stage)
                    }
                })
            }
            .frame(minHeight: 196, idealHeight: 240, maxHeight: .infinity)
            .accessibilityHidden(true)

            if showsStageLegend {
                VStack(spacing: 0) {
                    ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                        Button { onSelect(stage) } label: {
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
                            .overlay(alignment: .leading) {
                                if selectedStage == stage.kind {
                                    Capsule()
                                        .fill(OWCDesign.orangeDeep)
                                        .frame(width: 3, height: 28)
                                        .padding(.leading, 4)
                                }
                            }
                        }
                        .buttonStyle(OWCRowButtonStyle())
                        .accessibilityLabel(store.t(stage.kind.titleKey))
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

    private func yearLabel(_ date: Date, _ precision: CivilDatePrecision?) -> String {
        let year = store.recordsCalendar.component(.year, from: date)
        if precision == .year {
            return store.t("lifeYearApproximate", values: ["year": "\(year)"])
        }
        return "\(year)"
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
                            detailMetric("recordsWorkRegular", detail.regularWorkMs, color: OWCDesign.lifeWork, helpKey: "recordsMetricWorkHelp")
                            detailMetric("recordsOvertime", detail.overtimeMs, color: OWCDesign.orangeDeep, helpKey: "recordsMetricOvertimeHelp")
                            detailMetric("recordsBreakTime", detail.breakMs, color: OWCDesign.lifeStudy, helpKey: "recordsMetricBreakHelp")
                            detailMetric("recordsSleep", detail.sleepMs, color: OWCDesign.lifeChildhood, helpKey: "recordsMetricSleepHelp")
                            detailMetric("recordsFreeAwakeShort", detail.freeMs, color: OWCDesign.lifeRetirement, helpKey: "recordsMetricFreeHelp")
                        }
                    } else {
                        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                            GridRow {
                                detailMetric("recordsWorkRegular", detail.regularWorkMs, color: OWCDesign.lifeWork, helpKey: "recordsMetricWorkHelp")
                                detailMetric("recordsOvertime", detail.overtimeMs, color: OWCDesign.orangeDeep, helpKey: "recordsMetricOvertimeHelp")
                            }
                            GridRow {
                                detailMetric("recordsBreakTime", detail.breakMs, color: OWCDesign.lifeStudy, helpKey: "recordsMetricBreakHelp")
                                detailMetric("recordsSleep", detail.sleepMs, color: OWCDesign.lifeChildhood, helpKey: "recordsMetricSleepHelp")
                            }
                            GridRow {
                                wideDetailMetric("recordsFreeAwakeShort", detail.freeMs, color: OWCDesign.lifeRetirement, helpKey: "recordsMetricFreeHelp")
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
        return HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption)
                .foregroundStyle(OWCDesign.secondary)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(store.formatRelativeDuration(Double(milliseconds)))
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(OWCDesign.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
            RecordsMetricHelpButton(
                title: title,
                message: store.t(helpKey),
                selection: $selectedHelp
            )
        }
        .padding(.leading, 12)
        .padding(.trailing, 2)
        .padding(.vertical, 5)
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

    private func metric(_ titleKey: String, _ value: String, helpKey: String) -> some View {
        let label = store.t(titleKey)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.trailing, 32)
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
            RecordsMetricHelpButton(
                title: label,
                message: store.t(helpKey),
                selection: $selectedHelp
            )
            .padding(.top, 4)
            .padding(.trailing, 2)
        }
        .background(OWCDesign.elevated, in: RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous))
    }
}
