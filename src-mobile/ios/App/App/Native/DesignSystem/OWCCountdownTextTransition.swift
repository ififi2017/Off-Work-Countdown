import SwiftUI

struct OWCCountdownTextTransition: ViewModifier {
    let milliseconds: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let disablesTransition: Bool
#if DEBUG
        disablesTransition = reduceMotion
            || (ProcessInfo.processInfo.arguments.contains("-owcPerformanceFixture")
                && ProcessInfo.processInfo.arguments.contains("-owcPerformanceDisableNumericTransition"))
#else
        disablesTransition = reduceMotion
#endif
        return content
            .contentTransition(disablesTransition ? .identity : .numericText(countsDown: true))
            .animation(
                disablesTransition ? nil : OWCMotion.countdownTick,
                value: Int(milliseconds / 1_000)
            )
            // The numeric transition otherwise rasterises its blurred glyphs on
            // the main thread, every frame of every tick. Rendering the digits
            // as a group moves that to the GPU. The bleed keeps the blur and
            // the rolling digits from clipping at the group's edges without
            // changing layout.
            .padding(Self.bleed)
            .drawingGroup()
            .padding(-Self.bleed)
    }

    private static let bleed: CGFloat = 12
}

extension View {
    func owcCountdownTextTransition(milliseconds: Double) -> some View {
        modifier(OWCCountdownTextTransition(milliseconds: milliseconds))
    }
}
