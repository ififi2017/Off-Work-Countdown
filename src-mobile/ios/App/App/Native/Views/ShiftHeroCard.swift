import SwiftUI

/// The shift headline, and the only place it can be edited.
///
/// The rows that used to repeat these two times below the headline are gone —
/// the headline *is* the editor now. The one line underneath is the planned
/// working time, which is the single value on this screen the user can't read
/// off anything else.
struct ShiftHeroCard: View {
    let store: OffWorkStore
    let onEdit: (SetupTimeField) -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .timeChipCenter, spacing: 4) {
                ShiftHeroTimeButton(
                    title: store.t("startTime"),
                    time: store.timeString(store.startMinutes)
                ) { onEdit(.start) }

                Text(verbatim: "—")
                    .font(.title3)
                    .foregroundStyle(OWCDesign.tertiary)
                    .alignmentGuide(.timeChipCenter) { $0[VerticalAlignment.center] }
                    .accessibilityHidden(true)

                ShiftHeroTimeButton(
                    title: store.t("endTime"),
                    time: store.timeString(store.endMinutes)
                ) { onEdit(.end) }
            }
            .environment(\.layoutDirection, .leftToRight)

            Label {
                Text("\(store.t("totalWorkTime")) · \(store.plannedWorkLabel)")
            } icon: {
                Image(systemName: "hourglass")
            }
            .font(.subheadline)
            .foregroundStyle(OWCDesign.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
    }
}

extension VerticalAlignment {
    /// Lines the range dash up with the middle of the time chips rather than the
    /// middle of the whole button, which includes the role caption underneath
    /// and would drag the dash down to the chip's bottom edge.
    private enum TimeChipCenter: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    static let timeChipCenter = VerticalAlignment(TimeChipCenter.self)
}
