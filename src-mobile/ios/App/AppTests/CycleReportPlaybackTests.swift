import Foundation
import Testing
@testable import App

@Suite("Cycle report playback")
struct CycleReportPlaybackTests {
    private let hour: Int64 = 3_600_000

    @MainActor
    private func player() -> CycleReportPlayer {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let period = CycleReportPeriod(
            kind: .week,
            startDayKey: "2026-09-21",
            endDayKey: "2026-09-27",
            timeZoneIdentifier: "Asia/Shanghai"
        )
        let cells = (21...27).map { day -> RecordsDayCell in
            let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 12))!
            let work = day == 21 || day == 22 || day == 25
            let key = String(format: "2026-09-%02d", day)
            return RecordsDayCell(
                dayKey: key,
                date: date,
                appearance: work ? .recorded : .rest,
                workMs: work ? 8 * hour : 0,
                overtimeMs: 0,
                breakMs: 0,
                freeMs: 0,
                observationCount: 0,
                isToday: false,
                isFuture: false,
                isProjection: false,
                hasConflict: false
            )
        }
        let snapshot = CycleReportBuilder.snapshot(
            period: period,
            cells: cells,
            figures: .init(workdays: 3, workedMs: 24 * hour, overtimeMs: 0, income: nil),
            isInProgress: false
        )
        return CycleReportPlayer(snapshot: snapshot)
    }

    @Test("A long frame gap advances one capped frame, not several chapters")
    @MainActor
    func capsLongFrameGap() {
        let player = player()
        let displayLink = CycleReportDisplayLink(player: player)

        displayLink.update(at: 10)
        displayLink.update(at: 40)

        #expect(player.stageIndex == 0)
        #expect(player.time == 0.1)
    }

    @Test("Pausing or holding drops elapsed background time before playback resumes")
    @MainActor
    func pauseAndHoldDiscardGaps() {
        let player = player()
        let displayLink = CycleReportDisplayLink(player: player)

        displayLink.update(at: 0)
        displayLink.update(at: 0.05)
        let beforeHold = player.time

        player.isHeld = true
        displayLink.update(at: 0.1)
        player.isHeld = false
        displayLink.update(at: 20) // The first frame after restart establishes a new timestamp.
        #expect(player.time == beforeHold)
        displayLink.update(at: 20.05)
        #expect(player.time > beforeHold)

        player.pause()
        displayLink.update(at: 20.1)
        let pausedAt = player.time
        player.resume()
        displayLink.update(at: 200)
        #expect(player.time == pausedAt)
    }

    @Test("The display clock stops playback when the final chapter is built")
    @MainActor
    func finalChapterStopsPlayback() {
        let player = player()
        let displayLink = CycleReportDisplayLink(player: player)
        var timestamp = 0.0
        displayLink.update(at: timestamp)

        for _ in 0..<1_000 where player.isPlaying {
            timestamp += 0.1
            displayLink.update(at: timestamp)
        }

        #expect(player.isLastStage)
        #expect(player.isBuilt)
        #expect(!player.isPlaying)
    }

    @Test("Paused navigation shows complete chapters and keeps playback paused")
    @MainActor
    func pausedNavigationShowsContent() {
        let player = player()
        player.advance(by: 1)
        player.pause()

        player.next()
        #expect(player.stage == .hours)
        #expect(player.build == 1)
        #expect(player.isPlaying == false)

        player.previous()
        #expect(player.stage == .calendar)
        #expect(player.build == 1)
        player.previous()
        #expect(player.stageIndex == 0)
        #expect(player.build == 1)
        #expect(player.isPlaying == false)

        player.resume()
        player.advance(by: 0.1)
        #expect(player.stage == .calendar)
        #expect(player.build == 1)
        #expect(player.isPlaying)
    }

    @Test("Going back from the stopped summary reveals the preceding chapter")
    @MainActor
    func previousFromSummaryShowsContent() {
        let player = player()
        player.skipToSummary()

        player.previous()
        #expect(player.stageIndex == player.stages.count - 2)
        #expect(player.build == 1)
        #expect(player.isPlaying == false)

        player.next()
        #expect(player.isLastStage)
        #expect(player.build == 1)
        player.replay()
        #expect(player.stageIndex == 0)
        #expect(player.build == 0)
        #expect(player.isPlaying)
    }

    @Test("Playing navigation keeps chapter animations, including during a temporary hold")
    @MainActor
    func playingNavigationStartsAnimation() {
        let player = player()
        player.next()
        #expect(player.stage == .hours)
        #expect(player.build == 0)

        player.advance(by: 1)
        player.previous()
        #expect(player.stage == .hours)
        #expect(player.build == 0)
        player.previous()
        #expect(player.stage == .calendar)

        player.isHeld = true
        player.next()
        #expect(player.stage == .hours)
        #expect(player.build == 0)
        #expect(player.isPlaying)
        player.isHeld = false
        player.advance(by: 0.1)
        #expect(player.build > 0)
    }
}
