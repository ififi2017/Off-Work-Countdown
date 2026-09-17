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

// MARK: - Calendar

/// The month calendar the extended schedule opens on. This month and next are
/// planned day by day, and earlier months back to when Records began can be
/// filled in so Records counts what was really worked. Pick a shift below the
/// grid, then tap days to give them that shift. Months after next repeat by
/// date, so they are not shown.
struct ExtendedCalendarSection: View {
    let session: ShiftSession
    let content: ExtendedScheduleContent
    /// Stored hand-set days with the page's unsaved edits applied.
    let handSetDays: [String: UUID]
    let todayKey: String
    /// Days before this key predate the extended schedule: they show the fixed
    /// schedule Records has for them, unless filled in by hand.
    let backfillBefore: String
    /// How many months back the calendar goes (zero or negative).
    let earliestMonthOffset: Int
    /// Planned workdays under the fixed schedule, for a range of day keys.
    let fixedWorkdays: (_ from: String, _ through: String) -> [String: Bool]
    let onSetDay: (String, RosterDayEdit) -> Void
    @State private var monthOffset = 0
    @State private var brush: RosterDayEdit?
    @ScaledMetric(relativeTo: .callout) private var cellHeight: CGFloat = 50

    /// Back as far as Records goes, at most a year; ahead only to next month.
    private var offsets: ClosedRange<Int> { max(-12, min(0, earliestMonthOffset))...1 }

    private var text: AppText { session.text }
    private var activeTypes: [ShiftType] { ExtendedScheduleEditing.activeTypes(in: content) }
    private var shownMonth: (year: Int, month: Int)? {
        ExtendedScheduleEditing.month(of: todayKey, plus: monthOffset)
    }

    /// The chosen shift, or the first work shift while nothing valid is chosen.
    private var currentBrush: RosterDayEdit? {
        if let brush {
            switch brush {
            case .followPattern: return brush
            case .shift(let id) where activeTypes.contains(where: { $0.id == id }): return brush
            case .shift: break
            }
        }
        return (activeTypes.first { $0.kind == .work } ?? activeTypes.first).map { .shift($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OWCSectionHeader(title: text.t("extendedCalendar"))
            OWCGroupCard {
                if let shownMonth {
                    monthHeader(shownMonth)
                    grid(shownMonth)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 12)
                        .owcPlainDivider()
                }
                palette
            }
            Group {
                Text(text.t(content.rule == nil ? "extendedCalendarNoteNoPattern" : "extendedCalendarNote"))
                if let shownMonth, monthKey(shownMonth, day: 1) < backfillBefore {
                    Text(text.t("extendedCalendarBackfillNote"))
                }
            }
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }
        .padding(.horizontal, OWCDesign.pageInset)
        .sensoryFeedback(.selection, trigger: monthOffset)
    }

    private func monthHeader(_ month: (year: Int, month: Int)) -> some View {
        HStack {
            Button { monthOffset -= 1 } label: {
                Image(systemName: "chevron.backward")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(monthOffset <= offsets.lowerBound)
            .accessibilityLabel(text.t("extendedPreviousMonth"))
            Spacer()
            Text(text.formatCivilDate(year: month.year, month: month.month, template: "yMMMM"))
                .font(.headline)
            Spacer()
            Button { monthOffset += 1 } label: {
                Image(systemName: "chevron.forward")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(monthOffset >= offsets.upperBound)
            .accessibilityLabel(text.t("extendedNextMonth"))
        }
        .tint(OWCDesign.accent)
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }

    private func monthKey(_ month: (year: Int, month: Int), day: Int) -> String {
        ExtendedScheduleEditing.dayKey(dayNumber: CivilZone.dayNumber(year: month.year, month: month.month, day: day))
    }

    private func grid(_ month: (year: Int, month: Int)) -> some View {
        let plan = ExtendedSchedulePlan(shiftTypes: content.shiftTypes, rule: content.rule, handSetDays: handSetDays)
        let resolver = ExtendedScheduleResolver(plan: plan)
        let first = CivilZone.dayNumber(year: month.year, month: month.month, day: 1)
        // Monday first, as the weekday labels are.
        let leading = ((first + 4) % 7 + 7 + 6) % 7
        let count = ExtendedScheduleEditing.daysIn(year: month.year, month: month.month)
        let firstKey = monthKey(month, day: 1)
        let fixed = firstKey < backfillBefore ? fixedWorkdays(firstKey, monthKey(month, day: count)) : [:]
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(text.weekdayLabels().enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.caption)
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityHidden(true)
            }
            ForEach(0..<(leading + count), id: \.self) { slot in
                if slot < leading {
                    Color.clear.frame(height: cellHeight).accessibilityHidden(true)
                } else {
                    let number = first + slot - leading
                    dayCell(
                        month: month,
                        day: slot - leading + 1,
                        key: ExtendedScheduleEditing.dayKey(dayNumber: number),
                        look: look(dayNumber: number, resolver: resolver, fixed: fixed)
                    )
                }
            }
        }
    }

    /// What one day shows.
    private struct DayLook {
        var label: String?
        var labelColor: Color = OWCDesign.secondary
        var tint: Color = .clear
        /// Set by hand where that is worth pointing out.
        var marked = false
        /// Days no Records period covers cannot be filled in.
        var editable = true
    }

    private func look(dayNumber: Int, resolver: ExtendedScheduleResolver, fixed: [String: Bool]) -> DayLook {
        let key = ExtendedScheduleEditing.dayKey(dayNumber: dayNumber)
        if key < backfillBefore {
            if let id = handSetDays[key], let type = content.shiftTypes.first(where: { $0.id == id }) {
                return look(for: type, marked: true)
            }
            guard let isWork = fixed[key] else { return DayLook(editable: false) }
            return DayLook(
                label: text.t(isWork ? "extendedKindWork" : "extendedKindRest"),
                tint: isWork ? OWCDesign.control : .clear
            )
        }
        let resolved = resolver.day(dayNumber: dayNumber)
        guard let type = resolved.shiftTypeID.flatMap({ id in content.shiftTypes.first { $0.id == id } }) else {
            return DayLook()
        }
        // Without a pattern every filled day is set by hand, so the mark would
        // say nothing.
        return look(for: type, marked: resolved.source == .handSet && content.rule != nil)
    }

    private func look(for type: ShiftType, marked: Bool) -> DayLook {
        let isWork = type.kind == .work
        return DayLook(
            label: type.name,
            labelColor: isWork ? type.displayColor : OWCDesign.secondary,
            tint: isWork ? type.displayColor.opacity(0.13) : .clear,
            marked: marked
        )
    }

    private func dayCell(month: (year: Int, month: Int), day: Int, key: String, look: DayLook) -> some View {
        let isToday = key == todayKey
        return Button {
            if let brush = currentBrush { onSetDay(key, brush) }
        } label: {
            VStack(spacing: 2) {
                Text(text.formatCount(day))
                    .font(.callout.monospacedDigit().weight(isToday ? .semibold : .regular))
                    .foregroundStyle(
                        isToday ? OWCDesign.accent : (look.editable ? OWCDesign.primary : OWCDesign.tertiary)
                    )
                Text(look.label ?? " ")
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(look.labelColor)
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, minHeight: cellHeight)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(look.tint))
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(OWCDesign.accent, lineWidth: 1.5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if look.marked {
                    Circle()
                        .fill(OWCDesign.secondary)
                        .frame(width: 4, height: 4)
                        .padding(5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!look.editable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([
            text.formatCivilDate(year: month.year, month: month.month, day: day, template: "MMMMdEEEE"),
            look.label ?? text.t("extendedUnassigned"),
            look.marked ? text.t("extendedSetByHand") : nil,
            isToday ? text.t("extendedToday") : nil,
        ].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(
            look.editable
                ? currentBrush.map { text.t("extendedFillDayHint", values: ["shift": brushName($0)]) } ?? ""
                : ""
        )
        .accessibilityAddTraits(.isButton)
    }

    private func brushName(_ brush: RosterDayEdit) -> String {
        switch brush {
        case .shift(let id): content.shiftTypes.first { $0.id == id }?.name ?? ""
        case .followPattern: text.t(content.rule == nil ? "extendedClearDay" : "extendedFollowPattern")
        }
    }

    private var palette: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(activeTypes) { type in
                    chip(.shift(type.id), title: type.name) {
                        Circle().fill(type.displayColor).frame(width: 8, height: 8)
                    }
                }
                chip(.followPattern, title: brushName(.followPattern)) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(OWCDesign.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
    }

    private func chip<Mark: View>(
        _ value: RosterDayEdit,
        title: String,
        @ViewBuilder mark: () -> Mark
    ) -> some View {
        let selected = currentBrush == value
        return Button { brush = value } label: {
            HStack(spacing: 6) {
                mark()
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(OWCDesign.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(Capsule().fill(selected ? OWCDesign.accent.opacity(0.14) : OWCDesign.control))
            .overlay(Capsule().strokeBorder(selected ? OWCDesign.accent : .clear, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: selected)
    }
}

// MARK: - Pattern

/// The optional pattern that fills the calendar: which kind it is, how long it
/// is, where today sits in it, and the shift each of its days works.
struct ExtendedPatternSection: View {
    let session: ShiftSession
    let content: ExtendedScheduleContent
    let todayKey: String
    let onChange: (ExtendedScheduleContent) -> Void
    let onApplyTemplate: (ShiftCycleRule.Preset) -> Void
    /// Drops the pattern after writing it into this month and next.
    let onRemovePattern: () -> Void
    @State private var pendingTemplate: ShiftCycleRule.Preset?
    @State private var confirmsRemoval = false

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
        .confirmationDialog(
            text.t("extendedRemovePatternTitle"),
            isPresented: $confirmsRemoval,
            titleVisibility: .visible
        ) {
            Button(text.t("extendedRemovePattern"), action: onRemovePattern)
            Button(text.t("cancelAction"), role: .cancel) {}
        } message: {
            Text(text.t("extendedRemovePatternMessage"))
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
                        guard preset != rule?.preset else { return }
                        guard let preset else {
                            confirmsRemoval = true
                            return
                        }
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
                Text(text.t("extendedPatternNone")).tag(ShiftCycleRule.Preset?.none)
            }
        } label: {
            OWCRow(title: text.t("extendedPatternKind"), isLast: rule == nil || rule?.preset == .weekly) {
                menuValue(rule.map { templateName($0.preset) } ?? text.t("extendedPatternNone"))
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
