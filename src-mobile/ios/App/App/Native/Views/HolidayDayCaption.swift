import SwiftUI

/// Dense calendars keep the holiday name under the date; VoiceOver and the
/// selected-day callout retain the full name and workday/prediction status.
struct HolidayDayCaption: View {
    let annotation: HolidayDayAnnotation
    let text: AppText
    var foreground: Color? = nil

    var body: some View {
        Text(annotation.isMakeupWorkday ? text.t("holidayMakeupShort")
             : annotation.name.isEmpty ? text.t("holidayRestDay") : annotation.name)
            .font(.caption2)
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(foreground ?? (annotation.isMakeupWorkday ? OWCDesign.accent : OWCDesign.secondary))
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

extension HolidayDayAnnotation {
    @MainActor func accessibilityLabel(text: AppText) -> String {
        [name, text.t(isMakeupWorkday ? "holidayMakeupWorkday" : "holidayRestDay"),
         isEstimated ? text.t("holidayEstimatedLabel") : nil]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
