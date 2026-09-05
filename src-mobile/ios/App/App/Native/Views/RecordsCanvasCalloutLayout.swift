import SwiftUI

/// Measures the label before placing it, so long locales and large text use
/// the same edge avoidance as a short month name. No geometry-to-state loop.
struct RecordsCanvasCalloutLayout: Layout {
    var anchor: CGRect

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let label = subviews.first else { return }
        let width = max(0, min(300, bounds.width - 16))
        let size = label.sizeThatFits(ProposedViewSize(width: width, height: nil))
        let origin = Self.origin(for: size, anchor: anchor, in: CGRect(origin: .zero, size: bounds.size))
        label.place(
            at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
            anchor: .topLeading,
            proposal: ProposedViewSize(size)
        )
    }

    static func origin(for size: CGSize, anchor: CGRect, in bounds: CGRect) -> CGPoint {
        let inset: CGFloat = 8
        let above = anchor.minY - inset - size.height
        let below = anchor.maxY + inset
        // Prefer above; flip below near the top. Clamp only when neither side
        // can contain the label (for example, maximum accessibility text).
        let y = above >= bounds.minY + inset ? above : below
        return CGPoint(
            x: min(max(bounds.minX + inset, anchor.midX - size.width / 2), max(bounds.minX + inset, bounds.maxX - inset - size.width)),
            y: min(max(bounds.minY + inset, y), max(bounds.minY + inset, bounds.maxY - inset - size.height))
        )
    }
}
