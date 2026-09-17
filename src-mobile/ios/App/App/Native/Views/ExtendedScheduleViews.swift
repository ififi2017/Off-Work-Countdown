import SwiftUI
import UIKit

// Plan 018 P8-c1b: the extended schedule on the schedule page. Everything here
// edits `ExtendedScheduleContent` through the page's draft, so it is saved —
// and asked about today — together with the rest of the page.

// MARK: - Colour

extension ShiftType {
    var displayColor: Color {
        Color(uiColor: UIColor(shiftTypeHex: colorHex) ?? .systemGray)
    }
}

extension UIColor {
    convenience init?(shiftTypeHex hex: String) {
        guard hex.wholeMatch(of: /#[0-9A-Fa-f]{6}/) != nil,
              let value = UInt32(hex.dropFirst(), radix: 16)
        else { return nil }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    /// `#RRGGBB` in sRGB, the form a shift type stores.
    var shiftTypeHex: String? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let srgb = cgColor.converted(to: space, intent: .defaultIntent, options: nil),
              let parts = srgb.components, parts.count >= 3
        else { return nil }
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(parts[0]), byte(parts[1]), byte(parts[2]))
    }
}

extension ShiftSession {
    /// "08:00–16:00", "20:00–06:00 next day", or "Rest".
    func hoursLabel(for type: ShiftType) -> String {
        guard type.kind == .work else { return text.t("extendedKindRest") }
        let start = timeString(type.startMinutes)
        let end = timeString(type.endMinutes)
        return type.endMinutes <= type.startMinutes
            ? text.t("extendedHoursOvernight", values: ["start": start, "end": end])
            : "\(start)–\(end)"
    }

    /// Whether a type's break falls inside its shift, asked of the same rule
    /// that checks the fixed hours' lunch.
    func breakFitsShift(_ type: ShiftType, at date: Date = .now) -> Bool {
        guard type.kind == .work, type.breakEnabled, type.breakDurationMinutes > 0 else { return true }
        return ScheduleRules.validateBreak(input: NativeRulesInput(
            startTime: timeString(type.startMinutes),
            endTime: timeString(type.endMinutes),
            nowMs: date.timeIntervalSince1970 * 1_000,
            workdays: [0, 1, 2, 3, 4, 5, 6],
            schedule: NativeWorkSchedule(
                mode: WorkScheduleMode.classic.rawValue,
                referenceWeekStartMs: nil,
                referenceWeekType: nil,
                singleWeekendWorkday: nil,
                rotationAnchorMs: nil,
                rotationWorkDays: nil,
                rotationRestDays: nil
            ),
            breakStartTime: timeString(type.breakStartMinutes),
            breakDurationMinutes: type.breakDurationMinutes,
            overtimeEndAtMs: nil,
            salaryAmount: "",
            salaryType: "",
            monthlyWorkingDays: 0,
            annualBonusMonths: 0,
            forcedWorkdayStartMs: nil,
            timeZoneIdentifier: rulesTimeZoneIdentifier
        ))
    }
}

// MARK: - Shift types

/// The types the schedule offers, where the fixed hours sit in the other modes.
struct ExtendedShiftTypesSection: View {
    let session: ShiftSession
    let types: [ShiftType]
    let onEdit: (ShiftType) -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OWCSectionHeader(title: session.text.t("extendedShiftTypes"))
            card.padding(.horizontal, OWCDesign.pageInset)
        }
    }

    private var card: some View {
        OWCGroupCard {
            ForEach(types) { type in
                let hours = session.hoursLabel(for: type)
                Button { onEdit(type) } label: {
                    OWCRow(icon: "circle.fill", title: type.name, iconTint: type.displayColor) {
                        // A rest type called "Rest" does not need saying twice.
                        OWCDetailAccessory(text: hours == type.name ? nil : hours)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }
                .buttonStyle(OWCRowButtonStyle())
            }
            Button(action: onAdd) {
                OWCRow(icon: "plus", title: session.text.t("extendedAddShiftType"), isLast: true)
            }
            .buttonStyle(OWCRowButtonStyle())
        }
    }
}

/// One shift type being edited in a sheet.
struct ShiftTypeEditing: Identifiable {
    var type: ShiftType
    var isNew: Bool
    /// The pattern still hands this type out, so it cannot be removed.
    var isInUse: Bool
    var id: UUID { type.id }
}

struct ShiftTypeEditorSheet: View {
    let session: ShiftSession
    let editing: ShiftTypeEditing
    let onSave: (ShiftType) -> Void
    let onDelete: () -> Void
    @State private var draft: ShiftType
    @Environment(\.dismiss) private var dismiss

    init(
        session: ShiftSession,
        editing: ShiftTypeEditing,
        onSave: @escaping (ShiftType) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.session = session
        self.editing = editing
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: editing.type)
    }

    private var text: AppText { session.text }
    private var breakFits: Bool { session.breakFitsShift(draft) }
    private var trimmed: ShiftType {
        var type = draft
        type.name = type.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return type
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text.t("extendedShiftNamePlaceholder"), text: $draft.name)
                        .submitLabel(.done)
                    Picker(text.t("extendedShiftTypes"), selection: $draft.kind) {
                        Text(text.t("extendedKindWork")).tag(ShiftType.Kind.work)
                        Text(text.t("extendedKindRest")).tag(ShiftType.Kind.rest)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } footer: {
                    if draft.kind == .rest { Text(text.t("extendedRestKindNote")) }
                }

                if draft.kind == .work {
                    Section {
                        timePicker(text.t("startTime"), \.startMinutes)
                        timePicker(text.t("endTime"), \.endMinutes)
                    } footer: {
                        if draft.endMinutes <= draft.startMinutes { Text(text.t("extendedOvernightNote")) }
                    }

                    Section {
                        Toggle(text.t("extendedBreak"), isOn: $draft.breakEnabled)
                            .tint(OWCDesign.accent)
                        if draft.breakEnabled {
                            timePicker(text.t("extendedBreakStart"), \.breakStartMinutes)
                            Stepper(value: $draft.breakDurationMinutes, in: 5...240, step: 5) {
                                LabeledContent(text.t("extendedBreakDuration")) {
                                    Text(text.t("minutesShort", values: ["count": text.formatCount(draft.breakDurationMinutes)]))
                                        .monospacedDigit()
                                }
                            }
                        }
                    } footer: {
                        if !breakFits {
                            Label(text.t("extendedBreakOutside"), systemImage: "exclamationmark.circle")
                                .foregroundStyle(OWCDesign.warning)
                        }
                    }
                }

                Section {
                    ColorPicker(
                        text.t("extendedColor"),
                        selection: Binding(
                            get: { draft.displayColor },
                            set: { color in
                                if let hex = UIColor(color).shiftTypeHex { draft.colorHex = hex }
                            }
                        ),
                        supportsOpacity: false
                    )
                }

                if !editing.isNew {
                    Section {
                        Button(text.t("extendedDeleteShiftType"), role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                        .disabled(editing.isInUse)
                    } footer: {
                        if editing.isInUse { Text(text.t("extendedShiftTypeInUse")) }
                    }
                }
            }
            .navigationTitle(text.t(editing.isNew ? "extendedNewShiftType" : "extendedEditShiftType"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(text.t("cancelAction"), role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(text.t("saveAction")) {
                        onSave(trimmed)
                        dismiss()
                    }
                    .disabled(!trimmed.isValid || !breakFits)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onChange(of: draft.name) { _, name in
            if name.count > ShiftType.maximumNameLength {
                draft.name = String(name.prefix(ShiftType.maximumNameLength))
            }
        }
        .onChange(of: draft.breakEnabled) { _, enabled in
            if enabled, draft.breakDurationMinutes < 5 { draft.breakDurationMinutes = 30 }
        }
    }

    private func timePicker(_ title: String, _ field: WritableKeyPath<ShiftType, Int>) -> some View {
        DatePicker(
            title,
            selection: Binding(
                get: { session.dateForMinutes(draft[keyPath: field]) },
                set: { draft[keyPath: field] = session.minutes(from: $0) }
            ),
            displayedComponents: .hourAndMinute
        )
    }
}

// MARK: - Pattern

/// The cycle rule: which pattern it started from, how long it is, where today
/// sits in it, and the shift each of its days works.
struct ExtendedPatternSection: View {
    let session: ShiftSession
    let content: ExtendedScheduleContent
    let todayKey: String
    let onChange: (ExtendedScheduleContent) -> Void
    let onApplyTemplate: (ShiftCycleRule.Preset) -> Void
    @State private var pendingTemplate: ShiftCycleRule.Preset?

    private var text: AppText { session.text }
    private var rule: ShiftCycleRule? { content.rule }
    private var activeTypes: [ShiftType] { ExtendedScheduleEditing.activeTypes(in: content) }
    private var todayCycleDay: Int? { rule.flatMap { ExtendedScheduleEditing.cycleDay(of: $0, todayKey: todayKey) } }
    private var labelsWeekdays: Bool { rule?.preset == .weekly || rule?.preset == .alternatingWeeks }

    private static let templates: [ShiftCycleRule.Preset] = [.weekly, .alternatingWeeks, .rotation]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OWCSectionHeader(title: text.t("extendedPattern"))
            OWCGroupCard {
                templateRow
                if let rule {
                    switch rule.preset {
                    case .weekly:
                        EmptyView()
                    case .alternatingWeeks:
                        weekRow(rule)
                    case .rotation, .custom:
                        lengthRow(rule)
                        cycleDayRow(rule)
                    }
                }
            }

            if let rule {
                ForEach(dayGroups(rule), id: \.start) { group in
                    OWCSectionHeader(title: group.title)
                        .padding(.top, 22)
                    OWCGroupCard {
                        ForEach(group.start..<group.end, id: \.self) { index in
                            dayRow(rule, index: index, isLast: index == group.end - 1)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, OWCDesign.pageInset)
        .confirmationDialog(
            text.t("extendedApplyTemplateTitle"),
            isPresented: Binding(get: { pendingTemplate != nil }, set: { if !$0 { pendingTemplate = nil } }),
            titleVisibility: .visible,
            presenting: pendingTemplate
        ) { preset in
            Button(text.t("extendedApplyTemplate")) { onApplyTemplate(preset) }
            Button(text.t("cancelAction"), role: .cancel) {}
        } message: { preset in
            Text(text.t("extendedApplyTemplateMessage", values: ["pattern": templateName(preset)]))
        }
    }

    private func templateName(_ preset: ShiftCycleRule.Preset) -> String {
        switch preset {
        case .weekly: text.t("scheduleClassic")
        case .alternatingWeeks: text.t("scheduleAlternating")
        case .rotation: text.t("scheduleRotation")
        case .custom: text.t("extendedPatternCustom")
        }
    }

    private var templateRow: some View {
        Menu {
            Picker(
                text.t("extendedPatternKind"),
                selection: Binding<ShiftCycleRule.Preset?>(
                    get: { rule?.preset },
                    set: { preset in
                        guard let preset, preset != rule?.preset else { return }
                        // Nothing to overwrite yet: fill it straight away.
                        if rule == nil { onApplyTemplate(preset) } else { pendingTemplate = preset }
                    }
                )
            ) {
                // A custom cycle has no template to refill from; it is listed
                // only so the current choice shows as selected.
                ForEach(Self.templates + (rule?.preset == .custom ? [.custom] : []), id: \.self) { preset in
                    Text(templateName(preset)).tag(Optional(preset))
                }
            }
        } label: {
            OWCRow(title: text.t("extendedPatternKind"), isLast: rule == nil || rule?.preset == .weekly) {
                menuValue(rule.map { templateName($0.preset) })
            }
        }
        .buttonStyle(OWCRowButtonStyle())
    }

    private func weekRow(_ rule: ShiftCycleRule) -> some View {
        let today = (todayCycleDay ?? 1) - 1
        return OWCRow(title: text.t("alternatingCurrentWeek"), isLast: true) {
            Picker(
                text.t("alternatingCurrentWeek"),
                selection: Binding(
                    get: { today / 7 },
                    set: { week in
                        onChange(ExtendedScheduleEditing.anchoring(
                            content,
                            todayKey: todayKey,
                            atCycleDay: week * 7 + today % 7 + 1
                        ))
                    }
                )
            ) {
                ForEach(0..<max(1, rule.days.count / 7), id: \.self) { week in
                    Text(text.t("extendedWeekNumber", values: ["week": text.formatCount(week + 1)])).tag(week)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }

    private func lengthRow(_ rule: ShiftCycleRule) -> some View {
        // Stepper puts its -/+ at the trailing edge of its own bounds, outside
        // OWCRow's inset, so it needs the inset back (as on the rotation page).
        Stepper(
            value: Binding(
                get: { rule.days.count },
                set: { length in
                    onChange(ExtendedScheduleEditing.resizing(
                        content,
                        to: length,
                        restName: text.t("extendedDefaultRest")
                    ))
                }
            ),
            in: 1...ExtendedScheduleEditing.maximumCycleLength
        ) {
            OWCRow(title: text.t("extendedCycleLength")) {
                Text(text.formatCount(rule.days.count)).monospacedDigit().foregroundStyle(OWCDesign.secondary)
            }
        }
        .padding(.trailing, 16)
        .buttonStyle(OWCRowButtonStyle())
        .owcPlainDivider()
    }

    private func cycleDayRow(_ rule: ShiftCycleRule) -> some View {
        Menu {
            Picker(
                text.t("extendedTodayIs"),
                selection: Binding(
                    get: { todayCycleDay ?? 1 },
                    set: { day in
                        onChange(ExtendedScheduleEditing.anchoring(content, todayKey: todayKey, atCycleDay: day))
                    }
                )
            ) {
                ForEach(1...rule.days.count, id: \.self) { day in
                    Text(cycleDayName(day)).tag(day)
                }
            }
        } label: {
            OWCRow(title: text.t("extendedTodayIs"), isLast: true) {
                menuValue(todayCycleDay.map(cycleDayName))
            }
        }
        .buttonStyle(OWCRowButtonStyle())
    }

    private struct DayGroup {
        var title: String
        var start: Int
        var end: Int
    }

    private func dayGroups(_ rule: ShiftCycleRule) -> [DayGroup] {
        let count = rule.days.count
        guard rule.preset == .alternatingWeeks, count > 7 else {
            return [DayGroup(title: text.t("extendedCycleDays"), start: 0, end: count)]
        }
        return stride(from: 0, to: count, by: 7).map { start in
            DayGroup(
                title: text.t("extendedWeekNumber", values: ["week": text.formatCount(start / 7 + 1)]),
                start: start,
                end: min(start + 7, count)
            )
        }
    }

    private func cycleDayName(_ day: Int) -> String {
        text.t("extendedCycleDay", values: ["day": text.formatCount(day)])
    }

    private func dayName(_ rule: ShiftCycleRule, index: Int) -> String {
        guard labelsWeekdays,
              let anchor = ExtendedScheduleResolver.dayNumber(dayKey: rule.anchorDayKey)
        else { return cycleDayName(index + 1) }
        return text.weekdayName(civilDayNumber: anchor + index)
    }

    private func dayRow(_ rule: ShiftCycleRule, index: Int, isLast: Bool) -> some View {
        let typeID = rule.days[index]
        let assigned = content.shiftTypes.first { $0.id == typeID }
        // An archived type stays selectable on the day that still names it.
        let options = activeTypes + (assigned.map { $0.isArchived ? [$0] : [] } ?? [])
        return Menu {
            Picker(
                dayName(rule, index: index),
                selection: Binding(
                    get: { typeID },
                    set: { onChange(ExtendedScheduleEditing.assigning($0, at: index, in: content)) }
                )
            ) {
                ForEach(options) { type in
                    Text(type.name).tag(type.id)
                }
            }
        } label: {
            OWCRow(
                title: dayName(rule, index: index),
                subtitle: todayCycleDay == index + 1 ? text.t("extendedToday") : nil,
                isLast: isLast,
                centersVertically: true
            ) {
                HStack(spacing: 6) {
                    if let assigned {
                        Circle()
                            .fill(assigned.displayColor)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                    }
                    menuValue(assigned?.name)
                }
            }
        }
        .buttonStyle(OWCRowButtonStyle())
    }

    private func menuValue(_ value: String?) -> some View {
        HStack(spacing: 6) {
            if let value {
                Text(value)
                    .font(.body)
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(OWCDesign.tertiary)
        }
    }
}
