import SwiftUI

struct OWCCountdownTextTransition: ViewModifier {
    let milliseconds: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
            .animation(
                reduceMotion ? nil : OWCMotion.countdownTick,
                value: Int(milliseconds / 1_000)
            )
    }
}

extension View {
    func owcCountdownTextTransition(milliseconds: Double) -> some View {
        modifier(OWCCountdownTextTransition(milliseconds: milliseconds))
    }
}
