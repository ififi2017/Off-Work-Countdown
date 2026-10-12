import SwiftUI

/// Dense calendars keep one short line under the date: the festival name, or
/// `holidayMakeupShort` ("补班" / "Work") on a make-up workday. The full
/// "Make-up workday" wording stays in VoiceOver and the selected-day callout.
/// The line scales down before it truncates, so a narrow Duo column does not
/// push into the date number above it.
struct HolidayDayCaption: View {
    let annotation: HolidayDayAnnotation
    let text: AppText
    var foreground: Color? = nil

    var body: some View {
        Text(annotation.isMakeupWorkday ? text.t("holidayMakeupShort")
             : annotation.name.isEmpty ? text.t("holidayRestDay") : annotation.name)
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
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
