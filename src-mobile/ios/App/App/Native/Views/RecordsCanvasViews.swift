import SwiftUI

extension TimeAllocationKind {
    var owcColor: Color {
        switch self {
        case .work: OWCDesign.recordsWork
        case .overtime: OWCDesign.recordsOvertime
        case .workBreak: OWCDesign.recordsBreak
        case .sleep: OWCDesign.recordsSleep
        case .free: OWCDesign.recordsFree
        case .unclassified: OWCDesign.recordsUnclassified
        }
    }
}

extension LifeStageKind {
    var owcColor: Color {
        switch self {
        case .childhood: OWCDesign.lifeChildhood
        case .study: OWCDesign.lifeStudy
        case .work: OWCDesign.lifeWork
        case .retirement: OWCDesign.lifeRetirement
        case .unset: OWCDesign.lifeUnset
        }
    }
}

struct RecordsScalePicker: View {
    let text: AppText
    @Binding var scale: RecordsScale

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Picker("", selection: $scale) {
                ForEach(RecordsScale.allCases) { option in
                    Text(text.t(option.titleKey)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Menu {
                ForEach(RecordsScale.allCases) { option in
                    Button(text.t(option.titleKey)) { scale = option }
                }
            } label: {
                HStack {
                    Text(text.t(scale.titleKey))
                        .font(.body.weight(.semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(OWCDesign.control, in: RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous))
            }
            .accessibilityLabel(text.t(scale.titleKey))
        }
        // Dense chart navigation has to keep all four destinations visible.
        // Descriptive cards below continue to honor the user's full Dynamic
        // Type setting; only this compact control uses a readable upper bound.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// Recorded overtime for the period as one line (plan 020 §5). Open to free
/// users, so it is given the total alone and nothing it was made from.
struct RecordsOvertimeLine: View {
    let text: AppText
    let milliseconds: Double
    var titleKey = "recordsOvertimeRecorded"

    var body: some View {
        OWCGroupCard {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(text.t(titleKey))
                    .font(.subheadline)
                    .foregroundStyle(OWCDesign.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(text.formatRelativeDuration(milliseconds))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(OWCDesign.recordsOvertime)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .accessibilityElement(children: .combine)
        }
    }
}

/// A period with nothing recorded yet.
struct RecordsEmptyPeriodCard: View {
    let text: AppText
    let title: String

    var body: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(text.t("recordsUnrecorded"))
                    .font(.subheadline)
                    .foregroundStyle(OWCDesign.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
    }
}

/// Life before its numbers are ready, or when the profile cannot produce them.
struct RecordsLifeAllocationPlaceholder: View {
    let text: AppText
    var isLoading = false

    var body: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(text.t("lifeWhereTimeGoes"))
                    .font(.subheadline.weight(.bold))
                if isLoading {
                    VStack(alignment: .leading, spacing: 14) {
                        RoundedRectangle(cornerRadius: 4).frame(height: 18)
                        RoundedRectangle(cornerRadius: 4).frame(height: 10)
                        RoundedRectangle(cornerRadius: 4).frame(width: 180, height: 14)
                    }
                    .foregroundStyle(OWCDesign.control)
                    .frame(minHeight: 100)
                    .accessibilityHidden(true)
                } else {
                    // No retirement boundary, no career, or a schedule the
                    // rules could not expand: say what is missing instead of
                    // inventing a percentage out of the parts that do exist.
                    Text(text.t("lifeAllocationMissing"))
                        .font(.subheadline)
                        .foregroundStyle(OWCDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
    }
}

/// One vocabulary for a day's marks, shared by the month grid and the week
/// columns so the same day cannot be described two ways on two screens.
enum RecordsDayMarks {
    /// Hatching says "these hours are an estimate". A rest day inside a career
    /// projection has no hours at all, so hatching it would claim an estimated
    /// day of work where the honest answer is simply "not a workday".
    static func isEstimated(_ cell: RecordsDayCell) -> Bool {
        (cell.isFuture || cell.isProjection || cell.appearance == .planned)
            && cell.workMs + cell.overtimeMs > 0
    }

    static func sourceKey(_ cell: RecordsDayCell) -> String {
        if cell.appearance == .locked { return "recordsLockedDay" }
        if cell.isProjection { return "recordsSourceProjection" }
        return switch cell.appearance {
        case .unrecorded: "recordsUnrecorded"
        case .recorded: cell.isFromSavedSchedule ? "recordsSourceSchedule" : "recordsSourceRecorded"
        case .corrected: "recordsSourceOverride"
        case .planned: "recordsPlanned"
        case .rest: "recordsRestDay"
        case .locked: "recordsLockedDay"
        }
    }

    static func holiday(_ cell: RecordsDayCell, preferences: PreferencesStore) -> HolidayDayAnnotation? {
        guard cell.appearance != .locked, preferences.isExtendedScheduleEnabled else { return nil }
        return HolidayDayAnnotation.make(dayKey: cell.dayKey,
            region: preferences.extendedScheduleContent?.holidayRegionIdentifier, language: preferences.languageCode)
    }

    /// A locked day says only that it is locked — no date arithmetic, no
    /// hours, nothing a screen reader could read out from behind the lock.
    static func accessibilityLabel(_ cell: RecordsDayCell, queries: RecordsQueries, text: AppText, holiday: HolidayDayAnnotation? = nil) -> String {
        if cell.appearance == .locked { return text.t("recordsLockedDay") }
        var parts = [queries.formatRecordsDayTitle(cell.date), text.t(sourceKey(cell))]
        if let holiday { parts.append(holiday.accessibilityLabel(text: text)) }
        if cell.workMs > 0 {
            parts.append(text.formatRecordsDuration(Double(cell.workMs)))
        }
        if cell.overtimeMs > 0 {
            parts.append("\(text.t("recordsOvertime")) \(text.formatRecordsDuration(Double(cell.overtimeMs)))")
        }
        if cell.hasConflict { parts.append(text.t("recordsConflictCopy")) }
        return parts.joined(separator: ", ")
    }
}
