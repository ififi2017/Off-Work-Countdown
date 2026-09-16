import SwiftUI

struct RecordsConflictCenter: View {
    let records: RecordCoordinator
    let queries: RecordsQueries
    let preferences: PreferencesStore
    let text: AppText
    @State private var fieldsFromAlternate: [UUID: Set<String>] = [:]
    @State private var failedAction: ConflictResolutionAction?
    @State private var showsResolutionError = false

    private var conflicts: [SyncConflictCopy] {
        records.state.sync.conflicts
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if conflicts.isEmpty {
                    ContentUnavailableView(
                        text.t("recordsConflictNone"),
                        systemImage: "checkmark.icloud"
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    ForEach(conflicts, id: \.id) { conflict in
                        ConflictReviewCard(
                            queries: queries,
                            preferences: preferences,
                            text: text,
                            conflict: conflict,
                            selectedFields: selectionBinding(for: conflict),
                            currentActionTitle: currentActionTitle(conflict),
                            alternateActionTitle: alternateActionTitle(conflict),
                            applyMerge: {
                                apply(.merge(conflict, fieldsFromAlternate[conflict.id] ?? []))
                            },
                            keepCurrent: { apply(.keepCurrent(conflict)) },
                            useAlternate: { apply(.useAlternate(conflict)) }
                        )
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 14)
            .padding(.bottom, OWCDesign.detailBottomInset)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(OWCDesign.page)
        .navigationTitle(text.t("recordsConflictCenter"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(text.t("recordsArchiveSaveFailedTitle"), isPresented: $showsResolutionError) {
            Button(text.t("retryAction")) { retryFailedAction() }
            Button(text.t("close"), role: .cancel) { failedAction = nil }
        } message: {
            Text(text.t("recordsArchiveSaveFailedBody"))
        }
    }

    private func apply(_ action: ConflictResolutionAction) {
        Task { await perform(action) }
    }

    private func perform(_ action: ConflictResolutionAction) async {
        let succeeded: Bool
        switch action {
        case .merge(let conflict, let fields):
            succeeded = await records.resolveConflict(conflict, fieldsFromAlternate: fields)
        case .keepCurrent(let conflict):
            succeeded = await records.keepCurrentConflict(conflict)
        case .useAlternate(let conflict):
            succeeded = await records.restoreConflict(conflict)
        }
        if succeeded {
            fieldsFromAlternate[action.conflictID] = nil
            failedAction = nil
        } else {
            failedAction = action
            showsResolutionError = true
        }
    }

    private func retryFailedAction() {
        guard let failedAction else { return }
        Task { @MainActor in
            // Alerts dismiss their current presentation after the button
            // action. Retry on the next actor turn so another failed write can
            // present the same recovery affordance again.
            await Task.yield()
            apply(failedAction)
        }
    }

    private func currentActionTitle(_ conflict: SyncConflictCopy) -> String {
        switch conflict.currentWinner {
        case .local: return text.t("recordsConflictKeepLocal")
        case .incoming:
            return text.t(conflict.source == "import" ? "recordsConflictKeepIncoming" : "recordsConflictKeepCloud")
        case .unknown: return text.t("recordsConflictKeepCurrent")
        }
    }

    private func alternateActionTitle(_ conflict: SyncConflictCopy) -> String {
        switch conflict.currentWinner {
        case .local:
            return text.t(conflict.source == "import" ? "recordsConflictKeepIncoming" : "recordsConflictKeepCloud")
        case .incoming: return text.t("recordsConflictKeepLocal")
        case .unknown: return text.t("recordsConflictUseOther")
        }
    }

    private func selectionBinding(for conflict: SyncConflictCopy) -> Binding<Set<String>> {
        Binding(
            get: { fieldsFromAlternate[conflict.id] ?? [] },
            set: { fieldsFromAlternate[conflict.id] = $0 }
        )
    }
}

private enum ConflictResolutionAction {
    case merge(SyncConflictCopy, Set<String>)
    case keepCurrent(SyncConflictCopy)
    case useAlternate(SyncConflictCopy)

    var conflictID: UUID {
        switch self {
        case .merge(let conflict, _), .keepCurrent(let conflict), .useAlternate(let conflict):
            conflict.id
        }
    }
}

private struct ConflictReviewCard: View {
    let queries: RecordsQueries
    let preferences: PreferencesStore
    let text: AppText
    let conflict: SyncConflictCopy
    @Binding var selectedFields: Set<String>
    let currentActionTitle: String
    let alternateActionTitle: String
    let applyMerge: () -> Void
    let keepCurrent: () -> Void
    let useAlternate: () -> Void

    private var title: String {
        if conflict.entityType == .lifeProfile {
            return text.t("recordsLifeProfileRow")
        }
        let dayKey = String(conflict.logicalKey.split(separator: "#", maxSplits: 1).first ?? "")
        if RecordJSON.date(fromDayKey: dayKey, calendar: preferences.recordsCalendar) != nil {
            return queries.formatRecordsDayTitle(dayKey: dayKey)
        }
        switch conflict.entityType {
        case .careerPeriod, .scheduleSnapshot, .extendedSchedule, .rosterDay:
            return text.t("workSchedule")
        case .calendarException, .dayOverride, .workObservation:
            return text.t("recordsTitle")
        case .focusTask:
            return ConflictPayloadPresenter.taskTitle(
                in: conflict.localPayload ?? conflict.incomingPayload ?? conflict.payload
            ) ?? text.t("focusTaskTitle")
        case .focusSession:
            return text.t("focusHistory")
        case .focusPlanningConfiguration:
            return text.t("focusPlanTitle")
        case .syncedPreferences:
            return text.t("settings")
        case .lifeProfile:
            return text.t("recordsLifeProfileRow")
        }
    }

    private var selectableFields: [String] {
        ConflictPayloadFields.changedFields(
            current: conflict.effectiveCurrentPayload,
            other: conflict.effectiveAlternatePayload,
            type: conflict.entityType
        )
    }

    private var explanation: String {
        text.t(
            conflict.currentWinner == .unknown
                ? "recordsConflictReviewLegacyVersions"
                : "recordsConflictReviewVersions"
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(OWCDesign.primary)
                    Text(explanation)
                        .font(.subheadline)
                        .foregroundStyle(OWCDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(OWCDesign.accent)
                    .frame(width: 32, height: 32)
            }
            .labelStyle(ConflictHeaderLabelStyle())

            ConflictVersionComparison(
                queries: queries,
                preferences: preferences,
                text: text,
                conflict: conflict
            )

            if conflict.supportsFieldMerge, !selectableFields.isEmpty {
                ConflictFieldChooser(
                    text: text,
                    conflict: conflict,
                    selectedFields: $selectedFields
                )

                Button(text.t("recordsConflictApplySelectedFields"), action: applyMerge)
                    .buttonStyle(OWCPrimaryButtonStyle())
                    .disabled(selectedFields.isEmpty)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { resolutionButtons }
                VStack(spacing: 10) { resolutionButtons }
            }
        }
        .padding(16)
        .background(OWCDesign.card)
        .clipShape(.rect(cornerRadius: OWCDesign.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private var resolutionButtons: some View {
        Button(currentActionTitle, action: keepCurrent)
            .buttonStyle(ConflictResolutionButtonStyle())
        Button(alternateActionTitle, action: useAlternate)
            .buttonStyle(ConflictResolutionButtonStyle())
    }
}

private struct ConflictHeaderLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 12) {
            configuration.icon
            configuration.title
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ConflictResolutionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(OWCDesign.accent.opacity(isEnabled ? 1 : 0.45))
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                OWCDesign.control.opacity(configuration.isPressed ? 0.65 : 1),
                in: .rect(cornerRadius: OWCDesign.controlRadius, style: .continuous)
            )
            .contentShape(.rect(cornerRadius: OWCDesign.controlRadius, style: .continuous))
    }
}

private struct ConflictVersionComparison: View {
    let queries: RecordsQueries
    let preferences: PreferencesStore
    let text: AppText
    let conflict: SyncConflictCopy

    private var changedFields: [String] {
        ConflictPayloadFields.changedFields(
            current: conflict.localPayload ?? conflict.effectiveCurrentPayload,
            other: conflict.incomingPayload ?? conflict.effectiveAlternatePayload,
            type: conflict.entityType
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            if let localPayload = conflict.localPayload,
               let incomingPayload = conflict.incomingPayload {
                ConflictVersionCard(
                    queries: queries,
                    preferences: preferences,
                    text: text,
                    title: text.t("recordsTimeZoneThisDevice"),
                    payload: localPayload,
                    editedAtMs: conflict.localEditedAtMs,
                    emphasized: conflict.currentWinner == .local,
                    entityType: conflict.entityType,
                    fieldKeys: changedFields
                )
                ConflictVersionCard(
                    queries: queries,
                    preferences: preferences,
                    text: text,
                    title: text.t(conflict.source == "import" ? "recordsImport" : "syncTitle"),
                    payload: incomingPayload,
                    editedAtMs: conflict.incomingEditedAtMs,
                    emphasized: conflict.currentWinner == .incoming,
                    entityType: conflict.entityType,
                    fieldKeys: changedFields
                )
            } else {
                ConflictVersionCard(
                    queries: queries,
                    preferences: preferences,
                    text: text,
                    title: text.t("recordsConflictCurrentVersion"),
                    payload: conflict.effectiveCurrentPayload,
                    editedAtMs: nil,
                    emphasized: true,
                    entityType: conflict.entityType,
                    fieldKeys: changedFields
                )
                ConflictVersionCard(
                    queries: queries,
                    preferences: preferences,
                    text: text,
                    title: text.t("recordsConflictOtherVersion"),
                    payload: conflict.effectiveAlternatePayload,
                    editedAtMs: nil,
                    emphasized: false,
                    entityType: conflict.entityType,
                    fieldKeys: changedFields
                )
            }
        }
    }
}

private struct ConflictVersionCard: View {
    let queries: RecordsQueries
    let preferences: PreferencesStore
    let text: AppText
    let title: String
    let payload: Data
    let editedAtMs: Double?
    let emphasized: Bool
    let entityType: RecordEntityType
    let fieldKeys: [String]

    private var fields: [PresentedConflictField] {
        ConflictPayloadPresenter.fields(
            in: payload,
            keys: fieldKeys,
            type: entityType,
            queries: queries,
            preferences: preferences,
            text: text
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: emphasized ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(emphasized ? OWCDesign.accent : OWCDesign.tertiary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OWCDesign.primary)
                Spacer(minLength: 8)
                if let editedAtMs {
                    Text(editedDateString(editedAtMs))
                        .font(.caption)
                        .foregroundStyle(OWCDesign.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            if fields.isEmpty {
                Text(text.t("recordsConflictDetailsUnreadable"))
                    .font(.subheadline)
                    .foregroundStyle(OWCDesign.secondary)
            } else {
                VStack(spacing: 7) {
                    ForEach(fields.enumerated(), id: \.element.id) { index, field in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(field.label)
                                .font(.caption)
                                .foregroundStyle(OWCDesign.secondary)
                            Spacer(minLength: 8)
                            Text(field.value)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(OWCDesign.primary)
                                .multilineTextAlignment(.trailing)
                        }
                        if index < fields.count - 1 {
                            Divider().opacity(0.45)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            emphasized ? OWCDesign.accent.opacity(0.08) : OWCDesign.elevated,
            in: .rect(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            if emphasized {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(OWCDesign.accent.opacity(0.28), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func editedDateString(_ editedAtMs: Double) -> String {
        let format = Date.FormatStyle(
            date: .abbreviated,
            time: .shortened,
            locale: preferences.locale,
            calendar: preferences.recordsCalendar,
            timeZone: preferences.recordsCalendar.timeZone
        )
        return Date(timeIntervalSince1970: editedAtMs / 1_000).formatted(format)
    }
}

private struct ConflictFieldChooser: View {
    let text: AppText
    let conflict: SyncConflictCopy
    @Binding var selectedFields: Set<String>

    private var fields: [String] {
        ConflictPayloadFields.changedFields(
            current: conflict.effectiveCurrentPayload,
            other: conflict.effectiveAlternatePayload,
            type: conflict.entityType
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text.t("recordsConflictChooseOtherFields"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OWCDesign.primary)

            VStack(spacing: 0) {
                ForEach(Array(fields.enumerated()), id: \.element) { index, field in
                    Button { toggle(field) } label: {
                        HStack(spacing: 12) {
                            Text(ConflictPayloadPresenter.fieldLabel(field, type: conflict.entityType, text: text))
                                .font(.body)
                                .foregroundStyle(OWCDesign.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: selectedFields.contains(field) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selectedFields.contains(field) ? OWCDesign.accent : OWCDesign.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 46)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < fields.count - 1 {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(OWCDesign.elevated, in: .rect(cornerRadius: 14, style: .continuous))
        }
    }

    private func toggle(_ field: String) {
        if selectedFields.contains(field) {
            selectedFields.remove(field)
        } else {
            selectedFields.insert(field)
        }
    }
}

private enum ConflictPayloadPresenter {
    static func userFacingKeys(for type: RecordEntityType) -> Set<String> {
        switch type {
        case .careerPeriod: ["startsOn", "endsBefore", "label"]
        case .scheduleSnapshot: ["effectiveFrom", "configurationData"]
        case .calendarException: ["effect", "isCleared", "label"]
        case .dayOverride: ["kind", "segments", "note"]
        case .workObservation: ["shiftAnchorDate", "occurredAtMs", "kind", "valueData"]
        case .lifeProfile: [
            "birthYear", "workStartedOn", "retirementAge", "averageSleepHours",
            "hidesExactAges", "bornOn", "schoolStartedOn", "workStartedPartial",
            "retirementOn", "averageSleepMinutes", "sleepSource",
            "workHistoryMode", "roughCurrentSalary", "employmentPeriods",
        ]
        case .focusTask: [
            "plannedForDate", "scheduledStartAtMs", "title", "estimatedPomodoros",
            "icon", "isFavorite", "completedAtMs", "deletedAtMs",
        ]
        case .focusSession: [
            "shiftAnchorDate", "startedAtMs", "plannedEndAtMs", "endedAtMs",
            "endReason", "kind", "actualDurationSeconds", "plannedEndReason",
        ]
        case .focusPlanningConfiguration: []
        case .syncedPreferences: []
        case .extendedSchedule: []
        case .rosterDay: ["shiftTypeID"]
        }
    }

    static func fields(
        in data: Data,
        keys: [String],
        type: RecordEntityType,
        queries: RecordsQueries,
        preferences: PreferencesStore,
        text: AppText
    ) -> [PresentedConflictField] {
        let values = dictionary(from: data)
        return keys.compactMap { key in
            guard let value = values[key] else { return nil }
            return PresentedConflictField(
                id: key,
                label: fieldLabel(key, type: type, text: text),
                value: display(value, for: key, queries: queries, preferences: preferences, text: text)
            )
        }
    }

    static func taskTitle(in data: Data) -> String? {
        (try? JSONDecoder().decode(FocusTaskDTO.self, from: data))?.title
    }

    static func fieldLabel(_ key: String, type: RecordEntityType, text: AppText) -> String {
        switch key {
        case "kind": text.t("recordsSectionKind")
        case "segments": text.t("recordsSectionHours")
        case "note", "label": text.t("recordsConflictFieldNote")
        case "startsOn", "startedAtMs", "occurredAtMs": text.t("startTime")
        case "endsBefore", "plannedEndAtMs", "endedAtMs": text.t("endTime")
        case "effectiveFrom", "configurationData": text.t("workSchedule")
        case "effect", "isCleared": text.t("recordsSectionKind")
        case "shiftAnchorDate", "plannedForDate", "scheduledStartAtMs": text.t("focusSchedule")
        case "birthDate", "birthYear", "bornOn": text.t("lifeBirthYear")
        case "schoolStartDate", "schoolStartedOn": text.t("lifeSchoolStarted")
        case "workStartDate", "workStartedOn", "workStartedPartial": text.t("lifeWorkStarted")
        case "retirementDate", "retirementOn": text.t("lifeRetirementDate")
        case "retirementAge": text.t("lifeRetirementAge")
        case "averageSleepHours", "averageSleepMinutes": text.t("lifeSleepHours")
        case "hidesExactAges": text.t("lifeHideAges")
        case "sleepSource": text.t("recordsSleep")
        case "title": text.t("focusTaskTitle")
        case "estimatedPomodoros": text.t("focusPomodoros")
        case "icon": text.t("focusChooseIcon")
        case "isFavorite": text.t("focusFavorites")
        case "completedAtMs", "deletedAtMs", "endReason", "plannedEndReason": text.t("plusStatus")
        case "actualDurationSeconds": text.t("lifeStageDurationTitle")
        default: text.t(type == .focusTask ? "focusTaskTitle" : "recordsSectionKind")
        }
    }

    private static func dictionary(from data: Data) -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { return [:] }
        return dictionary
    }

    private static func display(
        _ value: Any,
        for key: String,
        queries: RecordsQueries,
        preferences: PreferencesStore,
        text: AppText
    ) -> String {
        if key == "segments", let segments = value as? [[String: Any]] {
            let ranges = segments.compactMap { segment -> String? in
                guard let startAtMs = segment["startAtMs"] as? Double,
                      let endAtMs = segment["endAtMs"] as? Double
                else { return nil }
                let start = queries.formatRecordsTime(Date(timeIntervalSince1970: startAtMs / 1_000))
                let end = queries.formatRecordsTime(Date(timeIntervalSince1970: endAtMs / 1_000))
                return OWCText.ltrRange(start, end)
            }
            return ranges.isEmpty
                ? "0 \(text.t("recordsConflictItems"))"
                : ranges.joined(separator: ", ")
        }
        if let array = value as? [Any] {
            return "\(array.count) \(text.t("recordsConflictItems"))"
        }
        if value is NSNull { return "—" }
        if let milliseconds = value as? Double,
           key.hasSuffix("AtMs") || key == "occurredAtMs" || key == "scheduledStartAtMs" {
            return queries.formatRecordsTime(Date(timeIntervalSince1970: milliseconds / 1_000))
        }
        if key == "actualDurationSeconds", let seconds = value as? Int {
            return text.formatDuration(Double(seconds) * 1_000, includeSeconds: false)
        }
        if let dateKey = value as? String,
           ["startsOn", "endsBefore", "effectiveFrom", "shiftAnchorDate", "plannedForDate"].contains(key),
           RecordJSON.date(fromDayKey: dateKey, calendar: preferences.recordsCalendar) != nil {
            return queries.formatRecordsDayTitle(dayKey: dateKey)
        }
        if key == "configurationData", let encoded = value as? String,
           let data = Data(base64Encoded: encoded),
           let hours = try? JSONDecoder().decode(ScheduleHoursConfiguration.self, from: data) {
            return OWCText.ltrRange(hours.startTime, hours.endTime)
        }
        if key == "valueData", let encoded = value as? String,
           let data = Data(base64Encoded: encoded),
           let overtime = try? JSONDecoder().decode(OvertimeDeclarationPayload.self, from: data) {
            return queries.formatRecordsTime(Date(timeIntervalSince1970: overtime.overtimeEndAtMs / 1_000))
        }
        if let partial = value as? [String: Any], let year = partial["year"] as? Int {
            let month = partial["month"] as? Int
            let day = partial["day"] as? Int
            return [year, month, day].compactMap { $0 }.map(String.init).joined(separator: "-")
        }
        if let flag = value as? Bool {
            return flag ? "✓" : "—"
        }
        if key == "kind", let kind = value as? String {
            switch kind {
            case "confirmedAsScheduled": return text.t("recordsConfirmScheduled")
            case "customSegments": return text.t("recordsKindCustomHours")
            case "notWorking": return text.t("recordsMarkLeave")
            case "cleared": return text.t("recordsClearDay")
            case "timerSurfaceFirstSeen": return text.t("recordsObservedFirstSeen")
            case "countdownStarted": return text.t("recordsObservedStarted")
            case "countdownStopped": return text.t("recordsObservedStopped")
            case "overtimeDeclared": return text.t("recordsObservedOvertime")
            case "focus": return text.t("focusTitle")
            case "shortBreak": return text.t("focusShortBreak")
            case "longBreak": return text.t("focusLongBreak")
            default: break
            }
        }
        if key == "effect", let effect = value as? String {
            return text.t(effect == "work" ? "recordsConfirmScheduled" : "recordsMarkLeave")
        }
        if ["endReason", "plannedEndReason"].contains(key), let reason = value as? String {
            switch reason {
            case "completed": return text.t("focusHistoryCompleted")
            case "stoppedByUser": return text.t("focusHistoryStopped")
            case "stoppedAtBoundary": return text.t("focusHistoryBoundary")
            case "abandoned": return text.t("focusHistoryAbandoned")
            case "supersededBySync": return text.t("focusHistorySupersededBySync")
            default: break
            }
        }
        return String(describing: value)
    }
}

private struct PresentedConflictField: Identifiable {
    let id: String
    let label: String
    let value: String
}

private enum ConflictPayloadFields {
    static func changedFields(current: Data, other: Data, type: RecordEntityType) -> [String] {
        let currentValues = dictionary(from: current)
        let otherValues = dictionary(from: other)
        return Set(currentValues.keys).union(otherValues.keys)
            .intersection(ConflictPayloadPresenter.userFacingKeys(for: type))
            .filter { String(describing: currentValues[$0]) != String(describing: otherValues[$0]) }
            .sorted()
    }

    private static func dictionary(from data: Data) -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { return [:] }
        return dictionary
    }
}
