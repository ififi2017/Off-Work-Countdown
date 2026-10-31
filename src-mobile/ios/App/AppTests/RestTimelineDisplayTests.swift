import Foundation
import SwiftUI
import Testing
@testable import App

@MainActor
@Suite("Rest timeline display")
struct RestTimelineDisplayTests {
    @Test("App catalog resolves gallery fallback copy in every supported language")
    func localizedFallbacks() {
        let localizer = NativeLocalizer()
        for language in NativeLocalizer.supportedLanguages {
            for key in ["countdownNotStarted", "widgetOpenToRefresh"] {
                #expect(localizer.string(key, locale: language.id) != key)
            }
        }
    }

    @Test("Rest header breaks only at the localized semantic separator")
    func restHeader() {
        for language in NativeLocalizer.supportedLanguages {
            let model = makeModel(phase: .before, target: 146_340_000,
                                  labelKey: "widgetRestDay", locale: language.id)
            let clauses = WidgetCopy.text("widgetRestDay", locale: language.id).components(separatedBy: " · ")
            #expect(clauses.count == 2)
            #expect(model.timelineLabel == clauses.joined(separator: "\n"))
            #expect(!model.timelineLabel.contains(" · "))
        }
        let chinese = makeModel(phase: .before, target: 146_340_000,
                                labelKey: "widgetRestDay", locale: "zh-CN")
        #expect(chinese.timelineLabel == "好好休息\n距离下次上班")
        let before = makeModel(phase: .before, target: 3_600_000)
        #expect(before.timelineLabel == before.label)
    }

    @Test("Before shift without today's segments retains its real target", arguments: [Int64(3_600_000), Int64(146_340_000)])
    func before(target: Int64) {
        let model = makeModel(phase: .before, target: target)
        #expect(model.entry.segments.isEmpty)
        #expect(model.timelineWaitingTarget == Date(timeIntervalSince1970: Double(target) / 1_000))
        #expect(model.progress == 0.361)
    }

    @Test("Idle and normal work/lunch never use the waiting fallback", arguments: [WidgetTimelinePhase.idle, .working, .break, .done])
    func otherPhases(phase: WidgetTimelinePhase) {
        #expect(makeModel(phase: phase, target: 3_600_000).timelineWaitingTarget == nil)
    }

    @Test("Missing and expired before targets are not active waits")
    func invalidTargets() {
        #expect(makeModel(phase: .before, target: nil).timelineWaitingTarget == nil)
        #expect(makeModel(phase: .before, target: 0).timelineWaitingTarget == nil)
    }

    @Test("Rest, same-day before, idle, working and lunch render without fabricating segments")
    func renderStates() throws {
        let segments = [WidgetShiftSegment(startAtMs: 3_600_000, endAtMs: 7_200_000),
                        WidgetShiftSegment(startAtMs: 10_800_000, endAtMs: 14_400_000)]
        let states: [(WidgetTimelinePhase, [WidgetShiftSegment])] = [
            (.before, []), (.before, segments), (.idle, []), (.working, segments), (.break, segments)
        ]
        for (phase, work) in states {
            let base = makeModel(phase: phase, target: 146_340_000)
            let model = CountdownStyleModel(entry: CountdownStyleEntry(base: base.entry.base, segments: work))
            let renderer = ImageRenderer(content: CountdownTimelineView(model: model).frame(width: 158, height: 158))
            let image = try #require(renderer.uiImage)
            #expect(image.size.width == 158)
            #expect(model.entry.segments == work)
        }
    }

    private func makeModel(phase: WidgetTimelinePhase, target: Int64?, labelKey: String = "countdownNotStarted", locale: String = "en") -> CountdownStyleModel {
        let entry = WidgetTimelineEntry(dateMs: 0, validUntilMs: 200_000_000, phase: phase,
            labelKey: labelKey, countdownKind: .shiftStarts,
            countdownValueAtDateMs: target ?? 0, countdownTargetAtMs: target,
            remainingEffectiveMsAtDateMs: 0, progressAtDate: 36.1, nextBoundaryAtMs: target)
        return CountdownStyleModel(entry: CountdownStyleEntry(base: OffWorkCountdownWidgetEntry(
            date: Date(timeIntervalSince1970: 0), snapshotEntry: entry, locale: locale, upcoming: []), segments: []))
    }
}

@MainActor
@Suite("App filing system region")
struct AppFilingTests {
    @Test("English in mainland China shows the filing; Chinese elsewhere does not")
    func regions() {
        #expect(AppFiling.number(systemLocale: Locale(identifier: "en_CN")) == "沪ICP备2026055302号-2A")
        for region in ["US", "HK", "TW"] {
            #expect(AppFiling.number(systemLocale: Locale(identifier: "zh_\(region)")) == nil)
        }
    }
}
