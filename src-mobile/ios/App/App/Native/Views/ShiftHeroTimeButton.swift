import SwiftUI

/// One end of the shift in the hero: the time, and the role it plays.
///
/// The time sits on a filled control rather than bare text — the same signal a
/// `DatePicker` gives inside a `Form` — because the previous design put the
/// shift's only headline in an inert `Text` that everybody tried to tap.
struct ShiftHeroTimeButton: View {
    let title: String
    let time: String
    let action: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var timeSize: CGFloat = 38

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(time)
                    .font(.system(size: timeSize, weight: .bold).monospacedDigit())
                    .tracking(-1.2)
                    .foregroundStyle(OWCDesign.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .environment(\.layoutDirection, .leftToRight)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(OWCDesign.control.opacity(0.7), in: .rect(cornerRadius: OWCDesign.controlRadius))
                    .alignmentGuide(.timeChipCenter) { $0[VerticalAlignment.center] }

                Text(title)
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(OWCHeroButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue(time)
    }
}
