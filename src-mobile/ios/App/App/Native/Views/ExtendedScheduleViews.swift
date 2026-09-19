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
