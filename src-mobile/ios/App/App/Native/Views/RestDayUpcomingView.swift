import SwiftUI

/// A compact preview of the next working day.
///
/// Dates and ordering come from the same rules-backed preview as the pre-shift
/// screen. This view only decides how many rows fit in the rest-day layout.
struct RestDayUpcomingView: View {
    let shifts: ShiftSessionStore
    let snapshot: NativeShiftSnapshot
    let now: Date

    var body: some View {
        // Once per evaluation: each read builds the next shift's snapshot and
        // reminder list, and this body used to read it once per row.
        let entries = entries
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                OWCSectionHeader(title: shifts.text.t("comingUp"))
                OWCGroupCard {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        ShiftPreviewRow(
                            locale: shifts.preferences.locale,
                            entry: entry,
                            now: now,
                            showsSeparator: index < entries.count - 1,
                            showsChevron: false,
                            reservesChevron: false
                        )
                    }
                }
                HolidayCoverageNoticeView(
                    regionIdentifier: holidayRegionIdentifier,
                    dates: entries.compactMap(\.date),
                    timeZone: shifts.preferences.recordsTimeZone,
                    text: shifts.text
                )
                .padding(.top, 6)
            }
        }
    }

    private var entries: [ShiftPreviewEntry] {
        guard let nextStart = snapshot.nextShiftStartDate,
              let nextSnapshot = shifts.session.snapshot(at: nextStart) else {
            return []
        }

        return Array(shifts.shiftPreview(for: nextSnapshot, at: now).upcoming.prefix(3))
    }

    private var holidayRegionIdentifier: String? {
        guard shifts.preferences.isExtendedScheduleEnabled else { return nil }
        return shifts.preferences.extendedScheduleContent?.holidayRegionIdentifier
    }
}
