import SwiftUI

struct RecordsConflictCenter: View {
    let store: OffWorkStore
    @State private var fieldsFromAlternate: [UUID: Set<String>] = [:]
    @State private var failedAction: ConflictResolutionAction?
    @State private var showsResolutionError = false

    private var conflicts: [SyncConflictCopy] {
        store.records.state.sync.conflicts
    }

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if conflicts.isEmpty {
                    OWCGroupCard {
                        Text(store.t("recordsConflictNone"))
                            .font(.body)
                            .foregroundStyle(OWCDesign.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                } else {
                    OWCGroupCard {
                        ForEach(Array(conflicts.enumerated()), id: \.element.id) { index, conflict in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(title(conflict))
                                    .font(.body.weight(.medium))
                                Text(conflictExplanation(conflict))
                                    .font(.footnote)
                                    .foregroundStyle(OWCDesign.secondary)
                                ConflictVersionComparison(
                                    conflict: conflict,
                                    text: { store.t($0) },
                                    locale: store.locale,
                                    timeZone: store.recordsCalendar.timeZone
                                )
                                if conflict.supportsFieldMerge {
                                    ConflictFieldChooser(
                                        conflict: conflict,
                                        text: { store.t($0) },
                                        selectedFields: selectionBinding(for: conflict)
                                    )
                                    Button(store.t("recordsConflictApplySelectedFields")) {
                                        apply(.merge(
                                            conflict,
                                            fieldsFromAlternate[conflict.id] ?? []
                                        ))
                                    }
                                    .font(.footnote.weight(.semibold))
                                }
                                HStack(spacing: 12) {
                                    Button(currentActionTitle(conflict)) {
                                        apply(.keepCurrent(conflict))
                                    }
                                    Button(alternateActionTitle(conflict)) {
                                        apply(.useAlternate(conflict))
                                    }
                                    .fontWeight(.semibold)
                                }
                                .font(.footnote)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            if index < conflicts.count - 1 {
                                Divider().opacity(0.4)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.top, 14)
        }
        .background(OWCDesign.page)
        .navigationTitle(store.t("recordsConflictCenter"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(store.t("recordsArchiveSaveFailedTitle"), isPresented: $showsResolutionError) {
            Button(store.t("retryAction")) { retryFailedAction() }
            Button(store.t("close"), role: .cancel) { failedAction = nil }
        } message: {
            Text(store.t("recordsArchiveSaveFailedBody"))
        }
    }

    private func apply(_ action: ConflictResolutionAction) {
        let succeeded: Bool
        switch action {
        case .merge(let conflict, let fields):
            succeeded = store.resolveConflict(conflict, fieldsFromAlternate: fields)
        case .keepCurrent(let conflict):
            succeeded = store.keepCurrentConflict(conflict)
        case .useAlternate(let conflict):
            succeeded = store.restoreConflict(conflict)
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

    private func title(_ conflict: SyncConflictCopy) -> String {
        if conflict.entityType == .lifeProfile {
            return store.t("recordsLifeProfileRow")
        }
        let dayKey = String(conflict.logicalKey.split(separator: "#", maxSplits: 1).first ?? "")
        if RecordJSON.date(fromDayKey: dayKey, calendar: store.recordsCalendar) != nil {
            return store.formatRecordsDayTitle(dayKey: dayKey)
        }
        return conflict.logicalKey
    }

    private func conflictExplanation(_ conflict: SyncConflictCopy) -> String {
        if conflict.currentWinner == .unknown {
            return store.t("recordsConflictReviewLegacyVersions")
        }
        return store.t("recordsConflictReviewVersions")
    }

    private func currentActionTitle(_ conflict: SyncConflictCopy) -> String {
        switch conflict.currentWinner {
        case .local: return store.t("recordsConflictKeepLocal")
        case .incoming:
            return store.t(conflict.source == "import" ? "recordsConflictKeepIncoming" : "recordsConflictKeepCloud")
        case .unknown: return store.t("recordsConflictKeepCurrent")
        }
    }

    private func alternateActionTitle(_ conflict: SyncConflictCopy) -> String {
        switch conflict.currentWinner {
        case .local:
            return store.t(conflict.source == "import" ? "recordsConflictKeepIncoming" : "recordsConflictKeepCloud")
        case .incoming: return store.t("recordsConflictKeepLocal")
        case .unknown: return store.t("recordsConflictUseOther")
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

private struct ConflictVersionComparison: View {
    let conflict: SyncConflictCopy
    let text: (String) -> String
    let locale: Locale
    let timeZone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            version(text("recordsConflictCurrentVersion"), payload: currentPayload, editedAtMs: currentEditedAtMs, isCurrent: true)
            version(text("recordsConflictOtherVersion"), payload: conflict.effectiveAlternatePayload, editedAtMs: otherEditedAtMs, isCurrent: false)
            let fields = changedFields
            if !fields.isEmpty {
                Text(text("recordsConflictChangedFields") + ": \(fields.map(fieldLabel).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(OWCDesign.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var currentPayload: Data {
        switch conflict.currentWinner {
        case .local: return conflict.localPayload ?? conflict.payload
        case .incoming: return conflict.incomingPayload ?? conflict.payload
        case .unknown: return conflict.payload
        }
    }

    private var currentEditedAtMs: Double? {
        switch conflict.currentWinner {
        case .local: return conflict.localEditedAtMs
        case .incoming: return conflict.incomingEditedAtMs
        case .unknown: return nil
        }
    }

    private var otherEditedAtMs: Double? {
        switch conflict.currentWinner {
        case .local: return conflict.incomingEditedAtMs
        case .incoming: return conflict.localEditedAtMs
        case .unknown: return nil
        }
    }

    @ViewBuilder
    private func version(_ title: String, payload: Data, editedAtMs: Double?, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(isCurrent ? .semibold : .regular))
            if let editedAtMs {
                Text(text("recordsConflictEditedAt") + " " + editedDateString(editedAtMs))
                    .font(.caption2)
                    .foregroundStyle(OWCDesign.secondary)
            }
            Text(summary(of: payload))
                .font(.caption)
                .foregroundStyle(OWCDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(OWCDesign.elevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var changedFields: [String] {
        ConflictPayloadFields.changedFields(
            current: currentPayload,
            other: conflict.effectiveAlternatePayload
        )
    }

    private func summary(of payload: Data) -> String {
        let values = dictionary(from: payload)
        let keys = values.keys
            .filter {
                !["editCount", "editTieBreaker", "editedAtMs", "id", "eventID", "profileID", "dayKey"].contains($0)
            }
            .sorted()
        let text = keys.map { key in "\(fieldLabel(key)): \(display(values[key], for: key))" }.joined(separator: " · ")
        return text.isEmpty ? self.text("recordsConflictDetailsUnreadable") : text
    }

    private func editedDateString(_ editedAtMs: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("yMMMdjm")
        return formatter.string(from: Date(timeIntervalSince1970: editedAtMs / 1_000))
    }

    private func fieldLabel(_ key: String) -> String {
        switch key {
        case "kind": text("recordsSectionKind")
        case "segments": text("recordsSectionHours")
        case "note": text("recordsConflictFieldNote")
        case "timeZoneIdentifier": text("recordsTimeZone")
        case "birthDate", "birthYear", "bornOn": text("lifeBirthYear")
        case "schoolStartDate", "schoolStartedOn": text("lifeSchoolStarted")
        case "workStartDate", "workStartedOn", "workStartedPartial": text("lifeWorkStarted")
        case "retirementDate", "retirementOn": text("lifeRetirementDate")
        case "retirementAge": text("lifeRetirementAge")
        case "averageSleepHours", "averageSleepMinutes": text("lifeSleepHours")
        case "hidesExactAges": text("lifeHideAges")
        default: key.replacingOccurrences(
            of: "([a-z0-9])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        ).capitalized(with: locale)
        }
    }

    private func dictionary(from data: Data) -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { return [:] }
        return dictionary
    }

    private func display(_ value: Any?, for key: String) -> String {
        guard let value else { return "—" }
        if key == "segments", let segments = value as? [[String: Any]] {
            let ranges = segments.compactMap { segment -> String? in
                guard let startAtMs = segment["startAtMs"] as? Double,
                      let endAtMs = segment["endAtMs"] as? Double
                else { return nil }
                return "\(timeString(startAtMs))–\(timeString(endAtMs))"
            }
            return ranges.isEmpty ? "0 \(text("recordsConflictItems"))" : ranges.joined(separator: ", ")
        }
        if let array = value as? [Any] { return "\(array.count) \(text("recordsConflictItems"))" }
        if value is NSNull { return "—" }
        if key == "kind", let kind = value as? String {
            switch kind {
            case "confirmedAsScheduled": return text("recordsConfirmScheduled")
            case "customSegments": return text("recordsKindCustomHours")
            case "notWorking": return text("recordsMarkLeave")
            case "cleared": return text("recordsClearDay")
            default: break
            }
        }
        return String(describing: value)
    }

    private func timeString(_ milliseconds: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("jm")
        return formatter.string(from: Date(timeIntervalSince1970: milliseconds / 1_000))
    }
}

private struct ConflictFieldChooser: View {
    let conflict: SyncConflictCopy
    let text: (String) -> String
    @Binding var selectedFields: Set<String>

    private var fields: [String] {
        ConflictPayloadFields.changedFields(
            current: conflict.effectiveCurrentPayload,
            other: conflict.effectiveAlternatePayload
        )
    }

    var body: some View {
        if !fields.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(text("recordsConflictChooseOtherFields"))
                    .font(.caption)
                    .foregroundStyle(OWCDesign.secondary)
                ForEach(fields, id: \.self) { field in
                    Button {
                        if selectedFields.contains(field) {
                            selectedFields.remove(field)
                        } else {
                            selectedFields.insert(field)
                        }
                    } label: {
                        Label(
                            fieldLabel(field),
                            systemImage: selectedFields.contains(field) ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedFields.contains(field) ? OWCDesign.accent : OWCDesign.secondary)
                }
            }
        }
    }

    private func fieldLabel(_ key: String) -> String {
        switch key {
        case "kind": text("recordsSectionKind")
        case "segments": text("recordsSectionHours")
        case "note": text("recordsConflictFieldNote")
        case "timeZoneIdentifier": text("recordsTimeZone")
        case "birthDate", "birthYear", "bornOn": text("lifeBirthYear")
        case "schoolStartDate", "schoolStartedOn": text("lifeSchoolStarted")
        case "workStartDate", "workStartedOn", "workStartedPartial": text("lifeWorkStarted")
        case "retirementDate", "retirementOn": text("lifeRetirementDate")
        case "retirementAge": text("lifeRetirementAge")
        case "averageSleepHours", "averageSleepMinutes": text("lifeSleepHours")
        case "hidesExactAges": text("lifeHideAges")
        default: key.replacingOccurrences(
            of: "([a-z0-9])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        ).capitalized
        }
    }
}

private enum ConflictPayloadFields {
    static let metadata = Set(["editCount", "editTieBreaker", "editedAtMs"])
    static let immutable = Set(["id", "eventID", "profileID", "dayKey"])

    static func changedFields(current: Data, other: Data) -> [String] {
        let currentValues = dictionary(from: current)
        let otherValues = dictionary(from: other)
        return Set(currentValues.keys).union(otherValues.keys)
            .subtracting(metadata)
            .subtracting(immutable)
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
