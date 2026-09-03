import SwiftUI

enum OWCMotion {
    static let reduced = Animation.easeOut(duration: 0.16)
    static let countdownTick = Animation.linear(duration: 0.16)
    static let press = Animation.easeOut(duration: 0.14)
    static let selection = Animation.snappy(duration: 0.18)
    /// A compact state panel leaving before its replacement arrives.
    static let stateExit = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.10)
    /// A compact state panel settling under the control that changed it.
    static let stateEnter = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.18)
    static let navigation = Animation.snappy(duration: 0.28)
    static let phase = Animation.smooth(duration: 0.28)
    static let recordsExpansion = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.26)
    /// One chart replacing another under the scale picker. Shorter than the
    /// expansion above it: the segmented control has already snapped by the
    /// time this starts, so anything slower reads as the canvas lagging the
    /// control rather than following it.
    static let recordsScaleChange = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.20)
    static let paywallPresentation = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.32)
    static let dragReturn = Animation.spring(duration: 0.38, bounce: 0.12)
    /// A deliberately discovered brand moment. One full turn needs enough
    /// time to read as a clock hand rather than a flicker.
    static let brandCelebration = Animation.smooth(duration: 0.8)
    /// Three fluid clock-hand turns after Plus becomes available. Haptics run
    /// beside this animation without writing tick state back into SwiftUI.
    static let subscriptionCelebrationDuration: Double = 1.35
    static let subscriptionCelebration = Animation.smooth(duration: subscriptionCelebrationDuration)
    static let subscriptionCelebrationTickCount = 12
    /// A hidden, user-triggered brand response on the unscheduled screen.
    /// The spring supplies the lift; the strong ease-out gives it a quiet,
    /// grounded landing rather than a repeating bounce.
    static let brandNudge = Animation.spring(duration: 0.4, bounce: 0.2)
    static let brandSettle = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)

    /// One row of a first-run summary arriving.
    ///
    /// Rare enough to spend a little bounce on, small enough that it never
    /// reads as a bounce.
    static let reveal = Animation.spring(duration: 0.42, bounce: 0.12)

    /// Gap between consecutive rows of that reveal, and the pause before the
    /// first one, which lets the page finish sliding in before its contents
    /// start populating.
    static let revealStagger: Double = 0.06
    static let revealLeadIn: Double = 0.34
}

extension View {
    /// Staggered arrival for the rows of a first-run summary.
    ///
    /// Opacity and a 14 pt rise — no scale, and nothing that changes layout, so
    /// the list is at its final size from the first frame and the rows fill it
    /// in rather than pushing each other around.
    ///
    /// Pass `travels: false` for the card a staggered list sits in. Its rows
    /// arrive one at a time, but the container has to arrive with the first of
    /// them or the page opens on an empty white slab waiting to be filled; it
    /// only fades, because a container sliding under rows that are also sliding
    /// moves the first row twice as far as the last.
    func owcRevealed(
        _ revealed: Bool,
        index: Int,
        reduceMotion: Bool,
        travels: Bool = true
    ) -> some View {
        modifier(
            OWCRevealModifier(
                revealed: revealed,
                index: index,
                reduceMotion: reduceMotion,
                travels: travels
            )
        )
    }
}

private struct OWCRevealModifier: ViewModifier {
    let revealed: Bool
    let index: Int
    let reduceMotion: Bool
    let travels: Bool

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            // Reduce Motion keeps the fade and drops the travel, and drops the
            // stagger with it: a sequence is itself motion, and the point of
            // the setting is that the page is simply there.
            .offset(y: revealed || reduceMotion || !travels ? 0 : 14)
            .animation(
                reduceMotion
                    ? OWCMotion.reduced
                    : OWCMotion.reveal.delay(
                        OWCMotion.revealLeadIn + Double(index) * OWCMotion.revealStagger
                    ),
                value: revealed
            )
    }
}
