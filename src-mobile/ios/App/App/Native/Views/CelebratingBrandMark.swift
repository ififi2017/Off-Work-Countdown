import SwiftUI

/// One interaction for the brand wherever it appears. About/onboarding hide
/// a turn behind five nearby taps; the subscriber page offers direct replay.
struct CelebratingBrandMark: View {
    var showsDepth = false
    var replaysOnTap = false
    var playsOnAppear = false
    var accessibilityTitle = OWCBrand.shortName
    var isActive = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var taps = BrandTapSequence()
    @State private var handRotation = 0.0
    @State private var isPlaying = false
    @State private var pulse = false
    @State private var isVisible = false
    @State private var handledInitialPlayback = false
    @State private var playbackID = 0
    @State private var tapFeedback = 0
    @State private var settledFeedback = 0

    var body: some View {
        Button(action: registerTap) {
            OWCBrandMark(
                isPressed: isPlaying,
                handRotation: .degrees(handRotation),
                showsDepth: showsDepth
            )
            .opacity(pulse ? 0.80 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(BrandMarkButtonStyle())
        .accessibilityLabel(Text(verbatim: accessibilityTitle))
        .accessibilityIdentifier("brand.celebration")
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.45), trigger: tapFeedback)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.25), trigger: settledFeedback)
        .onAppear {
            isVisible = true
            if playsOnAppear, !handledInitialPlayback, isActive {
                handledInitialPlayback = true
                // The purchase flow already confirms authorization with its
                // success haptic. Automatic playback adds no second pattern.
                play(withHaptics: false)
            }
        }
        .onDisappear {
            isVisible = false
            resetPlayback()
        }
        .onChange(of: isActive) { _, active in
            if !active { resetPlayback() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { resetPlayback() }
        }
        .onChange(of: reduceMotion) { resetPlayback() }
    }

    private func registerTap() {
        guard !isPlaying, isActive else { return }
        tapFeedback += 1
        if replaysOnTap || taps.register(at: Date.timeIntervalSinceReferenceDate) {
            play(withHaptics: true)
        }
    }

    private func play(withHaptics: Bool) {
        guard !isPlaying else { return }
        isPlaying = true
        playbackID += 1
        let id = playbackID
        if reduceMotion {
            withAnimation(OWCMotion.reduced) {
                pulse = true
            } completion: {
                guard playbackID == id, isVisible, isActive else { return }
                withAnimation(OWCMotion.reduced) { pulse = false } completion: {
                    finishPlayback(id: id, withHaptics: withHaptics)
                }
            }
        } else {
            withAnimation(OWCMotion.brandCelebration, completionCriteria: .removed) {
                handRotation += 360
            } completion: {
                finishPlayback(id: id, withHaptics: withHaptics)
            }
        }
    }

    private func finishPlayback(id: Int, withHaptics: Bool) {
        guard playbackID == id, isVisible, isActive, scenePhase == .active else { return }
        isPlaying = false
        if withHaptics { settledFeedback += 1 }
    }

    private func resetPlayback() {
        // Invalidates completion callbacks as well as the tap sequence. Leaving
        // a page mid-turn must never deliver a late haptic on the next page.
        playbackID += 1
        taps = BrandTapSequence()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isPlaying = false
            pulse = false
            handRotation = 0
        }
    }
}

private struct BrandMarkButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.press) { content in
                content
                    .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                    .opacity(configuration.isPressed ? 0.88 : 1)
            }
    }
}
