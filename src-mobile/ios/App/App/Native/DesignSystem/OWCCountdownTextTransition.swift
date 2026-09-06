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
    }
}

extension View {
    func owcCountdownTextTransition(milliseconds: Double) -> some View {
        modifier(OWCCountdownTextTransition(milliseconds: milliseconds))
    }
}
