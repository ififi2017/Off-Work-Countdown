import SwiftUI

/// A small piece of purposeful play for the otherwise sparse no-schedule state.
/// The system's interactive glass supplies the optical press response; this
/// gesture only follows the finger and springs the mark home.
struct DraggableBrandIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var drag = DragState()
    @State private var tracking = false
    @State private var pressFeedback = 0
    @State private var releaseFeedback = 0

    var body: some View {
        OWCBrandMark(interactionOffset: drag.translation, isPressed: drag.active)
            .frame(width: 104, height: 104)
            .scaleEffect(drag.active && !reduceMotion ? 0.97 : 1)
            .offset(resisted(drag.translation))
            .animation(reduceMotion ? nil : OWCMotion.press, value: drag.active)
            .animation(reduceMotion || drag.active ? nil : OWCMotion.dragReturn, value: drag.translation)
            .gesture(dragGesture)
            .sensoryFeedback(.impact(weight: .light), trigger: pressFeedback)
            .sensoryFeedback(.selection, trigger: releaseFeedback)
            .contentShape(Rectangle())
            // This is purposeful play, not an action. Hiding it prevents
            // VoiceOver from announcing a button that has no product effect.
            .accessibilityHidden(true)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($drag) { value, state, _ in
                state = DragState(active: true, translation: value.translation)
            }
            .onChanged { _ in
                guard !tracking else { return }
                tracking = true
                pressFeedback += 1
            }
            .onEnded { _ in
                tracking = false
                releaseFeedback += 1
            }
    }

    private func resisted(_ translation: CGSize) -> CGSize {
        CGSize(
            width: rubberBand(translation.width, limit: 74),
            height: rubberBand(translation.height, limit: 48)
        )
    }

    private func rubberBand(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        let magnitude = abs(value)
        guard magnitude > limit else { return value }
        let sign: CGFloat = value < 0 ? -1 : 1
        return sign * (limit + (magnitude - limit) * 0.2)
    }

    private struct DragState: Equatable {
        var active = false
        var translation: CGSize = .zero
    }
}
