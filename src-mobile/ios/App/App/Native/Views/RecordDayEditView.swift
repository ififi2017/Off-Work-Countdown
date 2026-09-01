import SwiftUI

struct RecordDayDetailHost: View {
    let store: OffWorkStore
    let dayKey: String

    var body: some View {
        if canReadDay, let resolution = store.resolvedDay(dayKey: dayKey) {
            RecordResolvedDayView(store: store, resolution: resolution)
        } else {
            RecordsLockedHistoryPlaceholder(store: store)
        }
    }

    private var canReadDay: Bool {
        RecordsAccess.canRevealDay(
            dayKey: dayKey,
            today: .now,
            calendar: store.recordsCalendar,
            authorized: store.plus.isAuthorized
        )
    }
}

struct RecordResolvedDayView: View {
    let store: OffWorkStore
    let resolution: DayResolution

    var body: some View {
        if canReadDay {
            detail
        } else {
            RecordsLockedHistoryPlaceholder(store: store)
        }
    }

    private var canReadDay: Bool {
        RecordsAccess.canRevealDay(
            dayKey: resolution.dayKey,
            today: .now,
            calendar: store.recordsCalendar,
            authorized: store.plus.isAuthorized
        )
    }

    private var detail: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 14) {
                OWCGroupCard {
                    VStack(alignment: .leading, spacing: 6) {
                        // The hours are what the day was. Where the app got
                        // them, and how long they add up to, describe them.
                        Text(hoursRangeLabel)
                            .font(.title2.weight(.semibold).monospacedDigit())
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 6) {
                                Text(sourceLabel)
                                    .fixedSize()
                                if let total = totalLabel {
                                    Text("·")
                                    Text(total)
                                        .monospacedDigit()
                                        .fixedSize()
                                }
                            }
                            .font(.footnote)
                            .foregroundStyle(OWCDesign.secondary)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(sourceLabel)
                                if let total = totalLabel {
                                    Text(total).monospacedDigit()
                                }
                            }
                            .font(.footnote)
                            .foregroundStyle(OWCDesign.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }

                OWCGroupCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.t("recordsObservations"))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(OWCDesign.secondary)
                        let items = store.observations(on: resolution.shiftAnchorDate)
                        if items.isEmpty {
                            Text(store.t("recordsNoObservations"))
                                .font(.body)
                                .foregroundStyle(OWCDesign.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(items) { item in
                                Text(observationLabel(item))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }

                if let conflict = store.records.state.sync.conflicts.first(where: { $0.logicalKey == resolution.dayKey }) {
                    OWCGroupCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.t("recordsConflictCopy"))
                                .font(.body.weight(.medium))
                            Button(store.t("recordsRestoreConflict")) {
                                store.restoreConflict(conflict)
                            }
                            .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    }
                }

                if store.plus.isAuthorized {
                    OWCGroupCard {
                        Button {
                            store.openDayEditor(dayKey: resolution.dayKey)
                        } label: {
                            OWCRow(icon: "pencil", title: store.t("recordsEditDay"), isLast: true) {
                                OWCDetailAccessory(text: nil)
                            }
                        }
                        .buttonStyle(OWCRowButtonStyle())
                    }
                } else {
                    Text(store.t("recordsEditPlusHint"))
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 14)
        }
        .background(OWCDesign.page)
        .navigationTitle(store.formatRecordsDayTitle(resolution.shiftAnchorDate))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sourceLabel: String {
        switch resolution.layer {
        case .schedule: store.t("recordsSourceSchedule")
        case .calendarException: store.t("recordsSourceException")
        case .override: store.t("recordsSourceOverride")
        case .none: store.t("recordsSourceNone")
        }
    }

    private var hoursRangeLabel: String {
        guard let first = resolution.segments.first, let last = resolution.segments.last else {
            return store.t("recordsRestDay")
        }
        let start = Date(timeIntervalSince1970: first.startAtMs / 1_000)
        let end = Date(timeIntervalSince1970: last.endAtMs / 1_000)
        return OWCText.ltrRange(store.formatRecordsTime(start), store.formatRecordsTime(end))
    }

    private var totalLabel: String? {
        guard !resolution.segments.isEmpty else { return nil }
        let ms = resolution.segments.reduce(0.0) { $0 + ($1.endAtMs - $1.startAtMs) }
        return store.formatRelativeDuration(ms)
    }

    private func observationLabel(_ item: WorkObservation) -> String {
        let time = store.formatRecordsTime(item.occurredAt)
        let kind: String
        switch item.kind {
        case .timerSurfaceFirstSeen: kind = store.t("recordsObservedFirstSeen")
        case .countdownStarted: kind = store.t("recordsObservedStarted")
        case .countdownStopped: kind = store.t("recordsObservedStopped")
        case .overtimeDeclared: kind = store.t("recordsObservedOvertime")
        }
        return "\(time) · \(kind)"
    }
}

/// A deliberately content-free destination for an expired free-history route.
/// It receives no day resolution, title, counts, or observations.
struct RecordsLockedHistoryPlaceholder: View {
    let store: OffWorkStore

    var body: some View {
        OWCContentSizedScrollView {
            OWCGroupCard {
                OWCRow(title: store.t("recordsLockedDay"), isLast: true) {
                    Image(systemName: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.tertiary)
                }
                .accessibilityLabel(store.t("recordsLockedDay"))
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 14)
        }
        .background(OWCDesign.page)
        .navigationTitle(store.t("recordsAllRecords"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RecordDayEditView: View {
    let store: OffWorkStore
    let dayKey: String

    /// What this day is, as one choice out of five. The page used to lay six
    /// buttons out flat, every one of them applying the moment it was tapped,
    /// with nothing on screen saying which of them was already true.
    private enum DayKind: String, CaseIterable, Identifiable {
        case customHours
        case asScheduled
        case leave
        case restDay
        case makeupDay

        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .customHours: "recordsKindCustomHours"
            case .asScheduled: "recordsConfirmScheduled"
            case .leave: "recordsMarkLeave"
            case .restDay: "recordsMarkRest"
            case .makeupDay: "recordsMarkMakeup"
            }
        }

        var icon: String {
            switch self {
            case .customHours: "clock"
            case .asScheduled: "calendar"
            case .leave: "airplane"
            case .restDay: "bed.double"
            case .makeupDay: "arrow.uturn.forward"
            }
        }

        /// Losing the recorded hours is a consequence worth a confirmation.
        var replacesHours: Bool { self != .customHours }
    }

    @State private var startMinutes = 9 * 60
    @State private var endMinutes = 18 * 60
    @State private var kind: DayKind = .customHours
    @State private var loadedKind: DayKind = .customHours
    @State private var loadedStart = 9 * 60
    @State private var loadedEnd = 18 * 60
    @State private var pendingKind: DayKind?
    @State private var confirmsClear = false
    @State private var confirmsDiscard = false
    @State private var savedFeedback = 0
    @State private var warningFeedback = 0
    @State private var selectionFeedback = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if kind == .customHours {
                    OWCSectionHeader(title: store.t("recordsSectionHours"))
                        .padding(.top, 8)
                    OWCGroupCard {
                        OWCRow(icon: "sunrise", title: store.t("startTime")) {
                            DatePicker("", selection: startBinding, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                        OWCRow(icon: "sunset", title: store.t("endTime"), isLast: true) {
                            DatePicker("", selection: endBinding, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                    }
                    .padding(.horizontal, OWCDesign.pageInset)
                }

                OWCSectionHeader(title: store.t("recordsSectionKind"))
                    .padding(.horizontal, OWCDesign.pageInset)
                    .padding(.top, kind == .customHours ? 22 : 8)

                OWCGroupCard {
                    ForEach(Array(DayKind.allCases.enumerated()), id: \.element.id) { index, option in
                        Button {
                            select(option)
                        } label: {
                            OWCRow(
                                icon: option.icon,
                                title: store.t(option.titleKey),
                                isLast: index == DayKind.allCases.count - 1,
                                centersVertically: true
                            ) {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(OWCDesign.accent)
                                    .opacity(kind == option ? 1 : 0)
                                    // Not just colour: the mark is present or
                                    // absent, which is the second channel.
                                    .accessibilityHidden(true)
                            }
                        }
                        .buttonStyle(OWCRowButtonStyle())
                        .accessibilityAddTraits(kind == option ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.horizontal, OWCDesign.pageInset)

                Button(store.t("saveAction"), action: save)
                    .buttonStyle(OWCPrimaryButtonStyle())
                    .disabled(!hasChanges)
                    .padding(.horizontal, OWCDesign.pageInset)
                    .padding(.top, 22)

                if loadedKind != .customHours || hasStoredOverride {
                    OWCSectionHeader(title: store.t("syncDangerZone"))
                        .padding(.horizontal, OWCDesign.pageInset)
                        .padding(.top, 26)
                    OWCGroupCard {
                        Button {
                            warningFeedback += 1
                            confirmsClear = true
                        } label: {
                            OWCRow(
                                icon: "arrow.uturn.backward",
                                title: store.t("recordsClearDay"),
                                subtitle: store.t("recordsClearDayDetail"),
                                isLast: true,
                                isDestructive: true
                            )
                        }
                        .buttonStyle(OWCRowButtonStyle())
                    }
                    .padding(.horizontal, OWCDesign.pageInset)
                }
            }
            .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.stateEnter, value: kind)
        }
        .background(OWCDesign.page)
        .navigationTitle(store.t("recordsEditDay"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(store.t("cancel")) {
                    if hasChanges {
                        confirmsDiscard = true
                    } else {
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .confirmationDialog(store.t("recordsDiscardEdits"), isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button(store.t("recordsDiscardEdits"), role: .destructive) { dismiss() }
            Button(store.t("cancel"), role: .cancel) {}
        }
        .sensoryFeedback(.selection, trigger: selectionFeedback)
        .sensoryFeedback(.success, trigger: savedFeedback)
        .sensoryFeedback(.warning, trigger: warningFeedback)
        .alert(
            store.t("recordsReplaceHoursTitle"),
            isPresented: Binding(get: { pendingKind != nil }, set: { if !$0 { pendingKind = nil } })
        ) {
            if let pendingKind {
                Button(store.t(pendingKind.titleKey)) {
                    kind = pendingKind
                    selectionFeedback += 1
                    self.pendingKind = nil
                }
            }
            Button(store.t("cancel"), role: .cancel) { pendingKind = nil }
        } message: {
            Text(store.t("recordsReplaceHoursConfirm"))
        }
        .alert(store.t("recordsClearDayTitle"), isPresented: $confirmsClear) {
            Button(store.t("recordsClearDay"), role: .destructive) {
                store.clearDayOverride(dayKey: dayKey)
                dismiss()
            }
            Button(store.t("cancel"), role: .cancel) {}
        } message: {
            Text(store.t("recordsClearDayConfirm"))
        }
        .onAppear(perform: load)
    }

    private var hasChanges: Bool {
        if kind != loadedKind { return true }
        return kind == .customHours && (startMinutes != loadedStart || endMinutes != loadedEnd)
    }

    private var hasStoredOverride: Bool {
        store.records.state.overrides.contains { $0.dayKey == dayKey && $0.kind != .cleared }
    }

    /// Switching away from recorded hours throws them away, so it asks first.
    /// Choosing the hours option back again is free and does not.
    private func select(_ option: DayKind) {
        guard option != kind else { return }
        if option.replacesHours, kind == .customHours, hasStoredOverride {
            warningFeedback += 1
            pendingKind = option
            return
        }
        kind = option
        selectionFeedback += 1
    }

    /// One Save, at the end. Every one of the six buttons used to write
    /// straight through on tap, so there was no way to change your mind and no
    /// sign that anything had happened.
    private func save() {
        guard store.canMutateRecordedDay(dayKey) else { return }
        switch kind {
        case .customHours:
            store.applyDayWrite(.customHours, dayKey: dayKey, startMinutes: startMinutes, endMinutes: endMinutes)
        case .asScheduled:
            store.applyDayWrite(.confirmed, dayKey: dayKey)
        case .leave:
            store.applyDayWrite(.leave, dayKey: dayKey)
        case .restDay:
            store.applyDayWrite(.rest, dayKey: dayKey)
        case .makeupDay:
            store.applyDayWrite(.makeup, dayKey: dayKey)
        }
        savedFeedback += 1
        dismiss()
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { date(fromMinutes: startMinutes) },
            set: { startMinutes = minutes(from: $0) }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { date(fromMinutes: endMinutes) },
            set: { endMinutes = minutes(from: $0) }
        )
    }

    private func load() {
        if let resolution = store.resolvedDay(dayKey: dayKey),
           let first = resolution.segments.first,
           let last = resolution.segments.last {
            startMinutes = minutes(from: Date(timeIntervalSince1970: first.startAtMs / 1_000))
            endMinutes = minutes(from: Date(timeIntervalSince1970: last.endAtMs / 1_000))
        }
        loadedStart = startMinutes
        loadedEnd = endMinutes
        kind = storedKind
        loadedKind = kind
    }

    private var storedKind: DayKind {
        if let override = store.records.state.overrides.first(where: { $0.dayKey == dayKey && $0.kind != .cleared }) {
            switch override.kind {
            case .customSegments: return .customHours
            case .confirmedAsScheduled: return .asScheduled
            case .notWorking: return .leave
            case .cleared: break
            }
        }
        if let exception = store.records.state.exceptions.first(where: { $0.matches(dateKey: dayKey) && !$0.isCleared }) {
            return exception.effect == .rest ? .restDay : .makeupDay
        }
        return .customHours
    }

    private func date(fromMinutes value: Int) -> Date {
        store.recordsCalendar.date(
            bySettingHour: value / 60,
            minute: value % 60,
            second: 0,
            of: store.recordsCalendar.startOfDay(for: .now)
        ) ?? .now
    }

    private func minutes(from date: Date) -> Int {
        let parts = store.recordsCalendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
