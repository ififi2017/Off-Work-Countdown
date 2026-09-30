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
    func shiftDateLabel(_ key: String) -> String {
        guard let parts = ExtendedScheduleResolver.parse(dayKey: key) else { return key }
        return text.formatCivilDate(year: parts.year, month: parts.month, day: parts.day, template: "yMMMd")
    }

    func shiftCoverageLabel(_ coverage: ShiftTypeDateCoverage?) -> String {
        guard let coverage else { return text.t("extendedNoAssignedDates") }
        return text.t("extendedAssignedDateBounds", values: [
            "start": shiftDateLabel(coverage.firstDayKey),
            "end": shiftDateLabel(coverage.lastDayKey),
            "count": text.formatCount(coverage.dayCount)
        ])
    }

    func annualShiftRangeLabel(_ range: AnnualShiftDateRange) -> String {
        text.t("extendedAnnualRangeLabel", values: [
            "start": text.formatCivilDate(year: 2000, month: range.startMonth, day: range.startDay, template: "MMMd"),
            "end": text.formatCivilDate(year: 2000, month: range.endMonth, day: range.endDay, template: "MMMd")
        ])
    }

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
    var dateCoverage: [UUID: ShiftTypeDateCoverage] = [:]
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
                    OWCRow(icon: "circle.fill", title: type.name,
                           subtitle: subtitle(for: type), iconTint: type.displayColor) {
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

    private func subtitle(for type: ShiftType) -> String {
        let coverage = session.shiftCoverageLabel(dateCoverage[type.id])
        guard let range = type.annualDateRange else { return coverage }
        return session.annualShiftRangeLabel(range) + "\n" + coverage
    }
}

/// One shift type being edited in a sheet.
struct ShiftTypeEditing: Identifiable {
    var type: ShiftType
    var isNew: Bool
    /// The pattern still hands this type out, so it cannot be removed.
    var isInUse: Bool
    var dateCoverage: ShiftTypeDateCoverage? = nil
    var otherTypes: [ShiftType] = []
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
    private var overlappingType: ShiftType? {
        guard draft.kind == .work, let range = draft.annualDateRange else { return nil }
        return editing.otherTypes.first {
            $0.id != draft.id && $0.kind == .work && !$0.isArchived
                && $0.annualDateRange.map { range.overlaps($0) } == true
        }
    }
    private var trimmed: ShiftType {
        var type = draft
        type.name = type.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return type
    }

    var body: some View {
        NavigationStack {
            Form {
                if !editing.isNew {
                    Section {
                        Text(session.shiftCoverageLabel(editing.dateCoverage))
                            .foregroundStyle(.secondary)
                    } header: {
                        Text(text.t("extendedUpcomingYear"))
                    }
                }
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
                    annualRangeSection
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
                    .disabled(!trimmed.isValid || !breakFits || overlappingType != nil)
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
        .onChange(of: draft.kind) { _, kind in
            if kind == .rest { draft.annualDateRange = nil }
        }
    }

    private var annualRangeSection: some View {
        Section {
            Toggle(text.t("extendedAnnualDateRange"), isOn: Binding(
                get: { draft.annualDateRange != nil },
                set: { enabled in
                    draft.annualDateRange = enabled
                        ? AnnualShiftDateRange(startMonth: 1, startDay: 1, endMonth: 12, endDay: 31)
                        : nil
                }
            ))
            if draft.annualDateRange != nil {
                monthDayPicker(text.t("extendedAnnualRangeStart"), isStart: true)
                monthDayPicker(text.t("extendedAnnualRangeEnd"), isStart: false)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(text.t("extendedAnnualRangeDescription"))
                if let range = draft.annualDateRange,
                   range.endMonth * 100 + range.endDay < range.startMonth * 100 + range.startDay {
                    Text(text.t("extendedAnnualRangeWrap"))
                }
                if let overlappingType {
                    Text(text.t("extendedAnnualRangeOverlap", values: ["shift": overlappingType.name]))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func monthDayPicker(_ title: String, isStart: Bool) -> some View {
        let month = Binding<Int>(
            get: { isStart ? draft.annualDateRange?.startMonth ?? 1 : draft.annualDateRange?.endMonth ?? 12 },
            set: { value in
                guard var range = draft.annualDateRange else { return }
                let lastDay = ExtendedScheduleEditing.daysIn(year: 2000, month: value)
                if isStart { range.startMonth = value; range.startDay = min(range.startDay, lastDay) }
                else { range.endMonth = value; range.endDay = min(range.endDay, lastDay) }
                draft.annualDateRange = range
            }
        )
        let day = Binding<Int>(
            get: { isStart ? draft.annualDateRange?.startDay ?? 1 : draft.annualDateRange?.endDay ?? 31 },
            set: { value in
                guard var range = draft.annualDateRange else { return }
                if isStart { range.startDay = value } else { range.endDay = value }
                draft.annualDateRange = range
            }
        )
        return HStack {
            Text(title)
            Spacer()
            Picker(title, selection: month) {
                ForEach(1...12, id: \.self) { value in
                    Text(text.formatCivilDate(year: 2000, month: value, template: "MMMM")).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Picker(title, selection: day) {
                ForEach(1...ExtendedScheduleEditing.daysIn(year: 2000, month: month.wrappedValue), id: \.self) { value in
                    Text(value, format: .number).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
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
