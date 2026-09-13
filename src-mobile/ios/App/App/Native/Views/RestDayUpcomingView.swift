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
            }
        }
    }

    private var entries: [ShiftPreviewEntry] {
        guard let nextStart = snapshot.nextShiftStartDate,
              let nextSnapshot = shifts.session.snapshot(at: nextStart) else {
            return []
        }

        // Ask immediately before that shift starts, so every returned event is
        // anchored to the next working day rather than the current rest day.
        let previewAt = nextStart.addingTimeInterval(-1)
        return Array(shifts.shiftPreview(for: nextSnapshot, at: previewAt).upcoming.prefix(3))
    }
}
