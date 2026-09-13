import UIKit
import Testing
@testable import App

@MainActor
@Suite("Phone landscape presentation")
struct PhoneLandscapePresentationTests {
    @Test func orientationUsesTheSceneWindowShapeAndPhoneIdiom() {
        #expect(PhoneLandscapePresentationPolicy.isLandscapePhone(
            idiom: .phone, width: 844, height: 390
        ))
        #expect(!PhoneLandscapePresentationPolicy.isLandscapePhone(
            idiom: .phone, width: 390, height: 844
        ))
        #expect(!PhoneLandscapePresentationPolicy.isLandscapePhone(
            idiom: .pad, width: 1_024, height: 768
        ))
    }

    @Test func timerOverlayNeverReplacesAnotherScenePresentation() {
        for blocked in [false, true] {
            let presented = PhoneLandscapePresentationPolicy.shouldPresent(
                isLandscapePhone: true,
                selectedTab: .timer,
                onboardingComplete: true,
                hasSeenPlusIntro: true,
                timerIsAtRoot: true,
                hasBlockingPresentation: blocked
            )
            #expect(presented == !blocked)
        }
        #expect(!PhoneLandscapePresentationPolicy.shouldPresent(
            isLandscapePhone: true,
            selectedTab: .records,
            onboardingComplete: true,
            hasSeenPlusIntro: true,
            timerIsAtRoot: true,
            hasBlockingPresentation: false
        ))
        #expect(!PhoneLandscapePresentationPolicy.shouldPresent(
            isLandscapePhone: true,
            selectedTab: .timer,
            onboardingComplete: false,
            hasSeenPlusIntro: true,
            timerIsAtRoot: true,
            hasBlockingPresentation: false
        ))
        #expect(!PhoneLandscapePresentationPolicy.shouldPresent(
            isLandscapePhone: true,
            selectedTab: .timer,
            onboardingComplete: true,
            hasSeenPlusIntro: false,
            timerIsAtRoot: true,
            hasBlockingPresentation: false
        ))
        #expect(!PhoneLandscapePresentationPolicy.shouldPresent(
            isLandscapePhone: true,
            selectedTab: .timer,
            onboardingComplete: true,
            hasSeenPlusIntro: true,
            timerIsAtRoot: false,
            hasBlockingPresentation: false
        ))
    }

    @MainActor
    @Test func timerPresentationSurvivesLayoutBindingsAndRemainsExclusive() {
        let scene = SceneState()
        let compactShare = scene.timerSheetBinding(.share)
        let wideShare = scene.timerSheetBinding(.share)
        compactShare.wrappedValue = true
        #expect(wideShare.wrappedValue)

        scene.presentAddFocus = true
        #expect(scene.timerSheet == nil)
        scene.timerSheet = .overtime
        #expect(!scene.presentAddFocus)

        // A stale binding from the replaced visual layout cannot dismiss the
        // newer presentation.
        compactShare.wrappedValue = false
        #expect(scene.timerSheet == .overtime)
    }
}
