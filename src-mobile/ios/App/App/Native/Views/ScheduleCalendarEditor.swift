import SwiftUI

/// Presentation-only modes. The persisted schedule retains its existing enum;
/// automatic modes are represented by the same shared cycle/roster model.
private enum ScheduleEditorMode: CaseIterable {
    case weekly, alternating, rotation, free, manual

    var titleKey: String {
        switch self {
        case .weekly: "scheduleClassic"
        case .alternating: "scheduleAlternating"
        case .rotation: "scheduleRotation"
        case .free: "scheduleFreeCalendar"
        case .manual: "scheduleManualTimer"
        }
    }
    var preset: ShiftCycleRule.Preset? {
        switch self {
        case .weekly: .weekly
        case .alternating: .alternatingWeeks
        case .rotation: .rotation
        case .free, .manual: nil
        }
    }
}

struct ScheduleCalendarEditor: View {
    let shifts: ShiftSessionStore
    let content: ExtendedScheduleContent
    let handSetDays: [String: UUID]
    let isManual: Bool
    let rosterEdits: [String: RosterDayEdit]?
    let onContentChange: (ExtendedScheduleContent) -> Void
    let onManualChange: (Bool) -> Void
    let onSetDay: (String, RosterDayEdit) -> Void
    let onRemovePattern: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var monthOffset = 0
    @State private var selectedKey: String?
    @State private var selectedWeek = 0
    @State private var showsTypes = false
    @State private var pendingMode: ScheduleEditorMode?
    @State private var editingType: ShiftTypeEditing?
    @ScaledMetric(relativeTo: .callout) private var cellHeight: CGFloat = 46

    private var session: ShiftSession { shifts.session }
    private var text: AppText { shifts.text }
    private var today: String { session.extendedTodayKey(at: .now) }
    private var selected: String { selectedKey ?? today }
    private var types: [ShiftType] { ExtendedScheduleEditing.activeTypes(in: content) }
    private var resolver: ExtendedScheduleResolver {
        ExtendedScheduleResolver(plan: ExtendedSchedulePlan(
            shiftTypes: content.shiftTypes, rule: content.rule, handSetDays: handSetDays,
            frozenShiftTypes: shifts.records.frozenRosterShiftTypes.filter { rosterEdits?[$0.key] == nil }
        ))
    }
    private var mode: ScheduleEditorMode {
        if isManual { return .manual }
        guard let rule = content.rule else { return .free }
        switch rule.preset {
        case .weekly: return .weekly
        case .alternatingWeeks: return .alternating
        case .rotation, .custom: return .rotation
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let month = ExtendedScheduleEditing.month(of: today, plus: monthOffset) {
                calendar(month)
            }
            modePicker
            controls
            selectedDay
        }
        .fixedSize(horizontal: false, vertical: true)
        .tint(OWCDesign.accent)
        .sensoryFeedback(.selection, trigger: selected)
        .sheet(isPresented: $showsTypes) {
            NavigationStack {
                ExtendedShiftTypesSection(
                    session: session, types: types,
                    onEdit: { editType($0) }, onAdd: addType
                )
                .frame(maxHeight: .infinity, alignment: .top)
                .background(OWCDesign.page)
                .navigationTitle(text.t("extendedShiftTypes"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(text.t("done")) { showsTypes = false }
                    }
                }
                .sheet(item: $editingType, content: typeEditor)
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            text.t(pendingMode == .free ? "extendedRemovePatternTitle" : "extendedApplyTemplateTitle"),
            isPresented: Binding(get: { pendingMode != nil }, set: { if !$0 { pendingMode = nil } }),
            titleVisibility: .visible
        ) {
            if let pendingMode {
                Button(text.t(pendingMode.titleKey)) { applyMode(pendingMode) }
            }
            Button(text.t("cancelAction"), role: .cancel) { pendingMode = nil }
        } message: {
            Text(pendingMode == .free ? text.t("extendedRemovePatternMessage") : text.t("extendedApplyTemplateMessage", values: ["pattern": text.t(pendingMode?.titleKey ?? mode.titleKey)]))
        }
    }

    private var modePicker: some View {
        Menu {
            Picker(text.t("workSchedule"), selection: Binding(
                get: { mode }, set: { next in
                    guard next != mode else { return }
                    if next == .manual || mode == .manual { applyMode(next) }
                    else { pendingMode = next }
                }
            )) {
                ForEach(ScheduleEditorMode.allCases, id: \.self) { option in
                    Text(text.t(option.titleKey)).tag(option)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(text.t(mode.titleKey))
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(text.t("workSchedule") + ", " + text.t(mode.titleKey))
    }

    private var weekdayLabels: [String] {
        guard dynamicTypeSize.isAccessibilitySize else { return text.weekdayLabels() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = shifts.preferences.locale
        let names = calendar.veryShortStandaloneWeekdaySymbols
        return Array(names.dropFirst()) + [names[0]]
    }

    private func calendar(_ month: (year: Int, month: Int)) -> some View {
        let first = CivilZone.dayNumber(year: month.year, month: month.month, day: 1)
        let leading = ((first + 4) % 7 + 7 + 6) % 7
        let count = ExtendedScheduleEditing.daysIn(year: month.year, month: month.month)
        let slots = ((leading + count + 6) / 7) * 7
        let resolved = resolver
        return VStack(spacing: 2) {
            HStack {
                Button { changeMonth(-1) } label: {
                    Image(systemName: "chevron.backward").frame(width: 44, height: 44)
                }
                .accessibilityLabel(text.t("extendedPreviousMonth"))
                Spacer()
                Button { monthOffset = 0; selectedKey = today } label: {
                    Text(text.formatCivilDate(year: month.year, month: month.month, template: "yMMMM"))
                        .font(.headline).foregroundStyle(OWCDesign.primary)
                        .frame(minHeight: 44)
                }
                .accessibilityHint(text.t("extendedToday"))
                Spacer()
                Button { changeMonth(1) } label: {
                    Image(systemName: "chevron.forward").frame(width: 44, height: 44)
                }
                .accessibilityLabel(text.t("extendedNextMonth"))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                    Text(label).font(.caption).foregroundStyle(OWCDesign.secondary)
                        .lineLimit(1).accessibilityHidden(true)
                }
                ForEach(0..<slots, id: \.self) { slot in
                    if slot < leading || slot >= leading + count {
                        Color.clear.frame(height: cellHeight).accessibilityHidden(true)
                    } else {
                        dayCell(number: first + slot - leading, day: slot - leading + 1, resolver: resolved)
                    }
                }
            }
        }
    }

    private func dayCell(number: Int, day: Int, resolver: ExtendedScheduleResolver) -> some View {
        let key = ExtendedScheduleEditing.dayKey(dayNumber: number)
        let result = resolver.day(dayNumber: number)
        let type = typeForDay(key, id: result.shiftTypeID)
        let chosen = key == selected
        let isToday = key == today
        return Button { selectedKey = key } label: {
            VStack(spacing: 1) {
                Text(text.formatCount(day)).font(.callout.monospacedDigit())
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(isToday ? OWCDesign.accent : OWCDesign.primary)
                Text(type.map { shortName($0) } ?? "–")
                    .font(.caption2).lineLimit(1)
                    .foregroundStyle(type?.displayColor ?? OWCDesign.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: cellHeight)
            .background(chosen ? OWCDesign.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: OWCDesign.controlRadius))
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: OWCDesign.controlRadius)
                        .strokeBorder(OWCDesign.accent, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dayLabel(key: key, type: type, isToday: isToday))
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }

    @ViewBuilder private var controls: some View {
        if isManual {
            Text(text.t("scheduleOffManualStart"))
                .font(.footnote).foregroundStyle(OWCDesign.secondary)
        } else if let rule = content.rule {
            VStack(spacing: 6) {
                if mode == .alternating {
                    Picker(text.t("alternatingCurrentWeek"), selection: $selectedWeek) {
                        ForEach(0..<2) { week in
                            Text(text.t("extendedWeekNumber", values: ["week": text.formatCount(week + 1)])).tag(week)
                        }
                    }.pickerStyle(.segmented)
                } else if mode == .rotation {
                    HStack {
                        Stepper(value: Binding(
                            get: { rule.days.count },
                            set: { onContentChange(ExtendedScheduleEditing.resizing(content, to: $0, restName: text.t("extendedDefaultRest"))) }
                        ), in: 1...max(ExtendedScheduleEditing.maximumCycleLength, rule.days.count)) {
                            Text(text.t("extendedCycleLength") + ": " + text.formatCount(rule.days.count))
                                .font(.subheadline)
                        }
                    }.frame(minHeight: 44)
                    Picker(text.t("extendedTodayIs"), selection: Binding(
                        get: { ExtendedScheduleEditing.cycleDay(of: rule, todayKey: today) ?? 1 },
                        set: { onContentChange(ExtendedScheduleEditing.anchoring(content, todayKey: today, atCycleDay: $0)) }
                    )) {
                        ForEach(1...max(1, rule.days.count), id: \.self) { day in
                            Text(text.t("extendedCycleDay", values: ["day": text.formatCount(day)])).tag(day)
                        }
                    }.pickerStyle(.menu).frame(minHeight: 44)
                }
                cycleGrid(rule)
            }
        }
    }

    private func cycleGrid(_ rule: ShiftCycleRule) -> some View {
        let start = mode == .alternating ? selectedWeek * 7 : 0
        let end = mode == .alternating ? min(start + 7, rule.days.count) : rule.days.count
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
            ForEach(start..<max(start, end), id: \.self) { index in
                let type = content.shiftTypes.first { $0.id == rule.days[index] }
                Menu {
                    ForEach(types) { option in
                        Button(option.name) { onContentChange(ExtendedScheduleEditing.assigning(option.id, at: index, in: content)) }
                    }
                } label: {
                    VStack(spacing: 2) {
                        Text(mode == .rotation ? text.formatCount(index + 1) : weekdayLabels[index % 7])
                            .foregroundStyle(OWCDesign.secondary)
                        Text(type.map { shortName($0) } ?? "–").foregroundStyle(type?.displayColor ?? OWCDesign.secondary)
                    }
                    .font(.caption).lineLimit(1).frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityLabel((mode == .rotation ? text.formatCount(index + 1) : weekdayLabels[index % 7]) + ", " + (type?.name ?? text.t("extendedUnassigned")))
            }
        }
    }

    private var selectedDay: some View {
        let result = ExtendedScheduleResolver.dayNumber(dayKey: selected).map { resolver.day(dayNumber: $0) }
        let type = typeForDay(selected, id: result?.shiftTypeID)
        let canEdit = selected >= today || shifts.records.canEditRosterDay(selected, timeZoneIdentifier: session.rulesTimeZoneIdentifier ?? shifts.preferences.recordsTimeZone.identifier)
        return VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Text(dayLabel(key: selected, type: nil, isToday: false)).font(.subheadline.weight(.semibold))
                Spacer()
                Button { showsTypes = true } label: {
                    Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
                }.accessibilityLabel(text.t("extendedShiftTypes"))
            }
            if let type {
                Text(type.name + " · " + session.hoursLabel(for: type))
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(text.t("extendedUnassigned")).font(.subheadline)
            }
            if !canEdit {
                Text(text.t("extendedHistoryNeedsCareer")).font(.footnote).foregroundStyle(OWCDesign.secondary)
            }
            Text(text.t(sourceKey(result?.source)))
                .font(.caption).foregroundStyle(OWCDesign.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(types) { option in
                        Button { onSetDay(selected, .shift(option.id)) } label: {
                            HStack(spacing: 5) {
                                Circle().fill(option.displayColor).frame(width: 7, height: 7)
                                Text(option.name).font(.subheadline)
                            }
                            .padding(.horizontal, 12).frame(minHeight: 44)
                            .background(type?.id == option.id ? OWCDesign.accent.opacity(0.12) : OWCDesign.control, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(type?.id == option.id ? [.isSelected] : [])
                    }
                    Button { onSetDay(selected, .followPattern) } label: {
                        Label(text.t(content.rule == nil ? "extendedClearDay" : "extendedFollowPattern"), systemImage: "arrow.uturn.backward")
                            .font(.subheadline).padding(.horizontal, 8).frame(minHeight: 44)
                    }
                }
            }.disabled(!canEdit)
        }
    }

    private func typeForDay(_ key: String, id: UUID?) -> ShiftType? {
        if case .shift(let assigned) = rosterEdits?[key] {
            return content.shiftTypes.first { $0.id == assigned }
        }
        if key < today {
            switch shifts.records.plannedRosterPreview(
                dayKey: key,
                timeZoneIdentifier: session.rulesTimeZoneIdentifier ?? shifts.preferences.recordsTimeZone.identifier,
                fallbackTypes: content.shiftTypes,
                ignoringRosterAssignment: rosterEdits?[key] == .followPattern
            ) {
            case .shift(let type): return type
            case .rest: return content.shiftTypes.first { $0.kind == .rest }
            case .noPlan: return nil
            }
        }
        if rosterEdits?[key] == nil, let frozen = shifts.records.frozenRosterShiftTypes[key] { return frozen }
        return id.flatMap { id in content.shiftTypes.first { $0.id == id } }
    }

    private func sourceKey(_ source: ExtendedScheduleDay.Source?) -> String {
        switch source {
        case .handSet: "extendedSetByHand"
        case .rule: "extendedPattern"
        case .carriedOver: "extendedCarriedOver"
        case .unassigned, nil: "extendedUnassigned"
        }
    }

    private func shortName(_ type: ShiftType) -> String {
        // Keep the cue legible, with the full name and hours directly below.
        String(type.name.prefix(dynamicTypeSize.isAccessibilitySize ? 1 : 3))
    }
    private func dayLabel(key: String, type: ShiftType?, isToday: Bool) -> String {
        guard let parts = ExtendedScheduleResolver.parse(dayKey: key) else { return key }
        return [text.formatCivilDate(year: parts.year, month: parts.month, day: parts.day, template: "MMMMdEEEE"),
                type?.name, isToday ? text.t("extendedToday") : nil].compactMap { $0 }.joined(separator: ", ")
    }
    private func changeMonth(_ delta: Int) {
        monthOffset += delta
        if let month = ExtendedScheduleEditing.month(of: today, plus: monthOffset) {
            selectedKey = ExtendedScheduleEditing.dayKey(dayNumber: CivilZone.dayNumber(year: month.year, month: month.month, day: 1))
        }
    }
    private func applyMode(_ next: ScheduleEditorMode) {
        pendingMode = nil
        selectedWeek = 0
        if next == .manual { onManualChange(true); return }
        onManualChange(false)
        if next == .free { onRemovePattern() }
        else if let preset = next.preset {
            onContentChange(session.applyingTemplate(preset, to: content, at: .now))
        }
    }
    private func editType(_ type: ShiftType) {
        editingType = ShiftTypeEditing(type: type, isNew: false, isInUse: ExtendedScheduleEditing.ruleUses(type.id, in: content)
            || (shifts.preferences.extendedScheduleContent?.shiftTypes.contains { $0.id == type.id } != true
                && handSetDays.values.contains(type.id)))
    }
    private func addType() {
        editingType = ShiftTypeEditing(type: ShiftType(
            id: UUID(), name: "", kind: .work,
            startMinutes: shifts.preferences.startMinutes, endMinutes: shifts.preferences.endMinutes,
            breakEnabled: false, breakStartMinutes: 720, breakDurationMinutes: 30,
            colorHex: ExtendedScheduleEditing.nextColor(after: content.shiftTypes), isArchived: false
        ), isNew: true, isInUse: false)
    }
    private func typeEditor(_ editing: ShiftTypeEditing) -> some View {
        ShiftTypeEditorSheet(session: session, editing: editing,
            onSave: { onContentChange(ExtendedScheduleEditing.upserting($0, in: content)) },
            onDelete: { onContentChange(ExtendedScheduleEditing.removing(editing.type.id, from: content, saved: shifts.preferences.extendedScheduleContent)) }
        )
    }
}
