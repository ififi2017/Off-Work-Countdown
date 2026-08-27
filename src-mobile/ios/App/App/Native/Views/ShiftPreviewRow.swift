import SwiftUI

/// One line of the pre-start preview.
///
/// Icons are neutral, not tinted per kind. Four hues read fine on the running
/// screen where one or two rows are visible; as a list they turned the screen
/// into a colour chart and spent the accent budget the rest of the design is
/// trying to protect. What separates this from a settings row is the time
/// column, not colour.
struct ShiftPreviewRow: View {
    let store: OffWorkStore
    let entry: ShiftPreviewEntry
    let now: Date
    let showsSeparator: Bool
    /// Whether the row does something when tapped. Not derived from `route`:
    /// the shift's own times open a picker rather than navigating.
    let showsChevron: Bool
    /// Whether to hold the chevron's width open on rows that do not have one.
    ///
    /// Right for a list where some rows are tappable and some are not — it is
    /// what keeps the clock column straight. Wrong for a list where none of
    /// them are, which then pays a chevron's width of empty margin on every
    /// row and pushes the times in off the edge for no reason.
    var reservesChevron = true

    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 32

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.callout)
                .foregroundStyle(OWCDesign.secondary)
                .frame(width: badgeSize, height: badgeSize)
                .background(OWCDesign.control.opacity(0.7), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.body)
                    .foregroundStyle(OWCDesign.primary)
                if let detail = entry.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                }
            }

            Spacer(minLength: 8)

            if let date = entry.date {
                // Once the shift has started, "start time" points at the next
                // working day; without the weekday the row would claim it
                // happens today.
                Group {
                    if Calendar.current.isDate(date, inSameDayAs: now) {
                        Text(date, format: .dateTime.hour().minute().locale(store.locale))
                    } else {
                        Text(date, format: .dateTime.weekday(.abbreviated).hour().minute().locale(store.locale))
                    }
                }
                .font(.body.monospacedDigit())
                .foregroundStyle(OWCDesign.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .environment(\.layoutDirection, .leftToRight)
            }

            // Always laid out, hidden when the row does nothing. Rendering it
            // conditionally let the inert rows push their time a chevron's
            // width further right, so the clock column came out ragged.
            if showsChevron || reservesChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OWCDesign.tertiary)
                    .opacity(showsChevron ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
        .overlay(alignment: .bottomTrailing) {
            if showsSeparator {
                Rectangle()
                    .fill(OWCDesign.separator)
                    .frame(height: 0.5)
                    .padding(.leading, badgeSize + 28)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch entry.kind {
        case .shiftStart: "sunrise"
        case .lunchStart: "cup.and.saucer"
        case .lunchEnd: "arrow.right.circle"
        case .health: "figure.walk"
        case .milestone: "bell.badge"
        case .liveActivity: "rectangle.inset.filled"
        case .offWorkReminder: "bell.badge"
        case .schedule: "calendar.badge.clock"
        case .shiftEnd: "flag.checkered"
        }
    }
}
