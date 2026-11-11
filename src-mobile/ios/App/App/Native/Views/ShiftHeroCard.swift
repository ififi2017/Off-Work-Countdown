import SwiftUI

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
