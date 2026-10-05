import SwiftUI

/// One line of the pre-start preview.
///
/// Icons are neutral, not tinted per kind. Four hues read fine on the running
/// screen where one or two rows are visible; as a list they turned the screen
/// into a colour chart and spent the accent budget the rest of the design is
/// trying to protect. What separates this from a settings row is the time
/// column, not colour.
struct ShiftPreviewRow: View {
    let locale: Locale
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: symbol)
                    .font(.callout)
                    .foregroundStyle(OWCDesign.secondary)
                    .frame(width: badgeSize, height: badgeSize)
                    .background(OWCDesign.control.opacity(0.7), in: Circle())
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.body)
                    .foregroundStyle(OWCDesign.primary)
                if let detail = entry.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                }
                if dynamicTypeSize.isAccessibilitySize {
                    timeLabel.padding(.top, 6)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)

            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }

            if !dynamicTypeSize.isAccessibilitySize { timeLabel }

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
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 12 : 0)
        .frame(minHeight: 58)
        .overlay(alignment: .bottomTrailing) {
            if showsSeparator {
                Rectangle()
                    .fill(OWCDesign.separator)
                    .frame(height: 0.5)
                    .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 16 : badgeSize + 28)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var timeLabel: some View {
        if let date = entry.date {
            Group {
                if Calendar.current.isDate(date, inSameDayAs: now) {
                    Text(date, format: .dateTime.hour().minute().locale(locale))
                } else {
                    Text(date, format: .dateTime.weekday(.abbreviated).hour().minute().locale(locale))
                }
            }
            .font(.body.monospacedDigit())
            .foregroundStyle(OWCDesign.secondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
            .environment(\.layoutDirection, .leftToRight)
        }
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
