import SwiftUI

/// Press feedback for the large tappable times in the hero.
///
/// `OWCPrimaryButtonStyle` presses to 0.985, which is invisible on something
/// this big — the hero needs to visibly give under the finger.
struct OWCHeroButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.74 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.press, value: configuration.isPressed)
    }
}
