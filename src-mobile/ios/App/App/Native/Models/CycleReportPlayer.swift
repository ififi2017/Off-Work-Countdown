import Foundation
import Observation

/// The chapters of a report, in the order the plan tells them: the period, the
/// time put in, the time off, how it compares, the pay, and a close. Each makes
/// a single point; a chapter with nothing to say is left out.
nonisolated enum CycleReportStage: Hashable, Sendable {
    case calendar
    case hours
    case overtime
    case baseline
    case rest
    case ahead
    case focus
    case income
    case summary

    /// Chapters are told in this order. One with nothing honest to say is left
    /// out: no overtime page without overtime, no comparison without history,
    /// no income unless the person asked for it.
    static func stages(for snapshot: CycleReportSnapshot) -> [Self] {
        guard snapshot.hasData else { return [] }
        var result: [Self] = [.calendar, .hours]
        if snapshot.figures.overtimeMs > 0 { result.append(.overtime) }
        if snapshot.baseline != nil { result.append(.baseline) }
        result.append(.rest)
        if snapshot.ahead != nil { result.append(.ahead) }
        if snapshot.focus != nil { result.append(.focus) }
        if snapshot.pay != nil { result.append(.income) }
        result.append(.summary)
        return result
    }

    /// Seconds the chapter spends building itself, then holding still for the
    /// reader. The last chapter holds until the person leaves.
    func timeline(for snapshot: CycleReportSnapshot) -> CycleReportTimeline {
        let monthly = snapshot.period.kind != .week
        return switch self {
        case .calendar: CycleReportTimeline(build: monthly ? 2.6 : 2.0, hold: 1.9)
        case .hours: CycleReportTimeline(build: 2.8, hold: 2.0)
        case .overtime: CycleReportTimeline(build: 2.2, hold: 2.1)
        case .baseline: CycleReportTimeline(build: 1.9, hold: 2.2)
        case .rest: CycleReportTimeline(build: 2.4, hold: 2.1)
        case .ahead: CycleReportTimeline(build: 2.2, hold: 2.3)
        case .focus: CycleReportTimeline(build: 2.0, hold: 2.0)
        case .income: CycleReportTimeline(build: 2.1, hold: 2.2)
        case .summary: CycleReportTimeline(build: 1.4, hold: .infinity)
        }
    }
}

nonisolated struct CycleReportTimeline: Equatable, Sendable {
    var build: Double
    var hold: Double
    var duration: Double { build + hold }
}

/// Drives a report's playback from one clock. A chapter is a pure function of
/// `stageIndex` and `time`, so pausing, holding a finger on the screen, jumping
/// between chapters and replaying only move those two numbers and nothing is
/// ever left half-built. Every chapter reads the one `snapshot` it was given.
@MainActor
@Observable
final class CycleReportPlayer {
    let snapshot: CycleReportSnapshot
    let stages: [CycleReportStage]
    private(set) var stageIndex = 0
    /// Seconds into the current chapter.
    private(set) var time: Double = 0
    /// Seconds played in all, never reset; the backdrop drifts on this so a
    /// change of chapter does not make the light jump.
    private(set) var clock: Double = 0
    private(set) var isPlaying: Bool
    /// A finger resting on the screen holds the clock without changing intent.
    var isHeld = false
    @ObservationIgnored private var displayLink: CycleReportDisplayLink?

    init(snapshot: CycleReportSnapshot, autoplay: Bool = true) {
        self.snapshot = snapshot
        stages = CycleReportStage.stages(for: snapshot)
        isPlaying = autoplay
    }

    var stage: CycleReportStage { stages[stageIndex] }
    var isLastStage: Bool { stageIndex == stages.count - 1 }
    var timeline: CycleReportTimeline { stage.timeline(for: snapshot) }
    /// 0 → 1 over the chapter's build; the whole chapter is drawn from this.
    var build: Double { min(1, max(0, time / timeline.build)) }
    var isBuilt: Bool { time >= timeline.build }
    /// 0 → 1 over the whole chapter, for the progress bar.
    var progress: Double {
        isLastStage ? (isBuilt ? 1 : build) : min(1, time / timeline.duration)
    }
    var isRunning: Bool { isPlaying && !isHeld }

    /// Moves the clock. A chapter that has held long enough hands over to the
    /// next; the last one stops where it is.
    func advance(by delta: Double) {
        guard isRunning, delta > 0 else { return }
        time += delta
        clock += delta
        while time >= timeline.duration, !isLastStage {
            time -= timeline.duration
            stageIndex += 1
        }
        if isLastStage, time >= timeline.build { time = timeline.build + 0.0001 }
    }

    /// Starts the UI clock when the visible player is running.
    func startDisplayLink() {
        guard isRunning else { return }
        if displayLink == nil { displayLink = CycleReportDisplayLink(player: self) }
        displayLink?.start()
    }

    /// Stops the UI clock and discards its timestamp so resume never catches
    /// up time spent paused, held, or outside the foreground.
    func stopDisplayLink() { displayLink?.stop() }

#if DEBUG
    /// Visual QA: parks the clock on an exact frame.
    func debugSeek(stage index: Int, buildFraction: Double) {
        stageIndex = min(max(0, index), stages.count - 1)
        time = timeline.build * buildFraction
        clock = time + Double(stageIndex) * 3
        isPlaying = false
    }
#endif

    func pause() { isPlaying = false }
    func resume() {
        if isLastStage, isBuilt { replay() } else { isPlaying = true }
    }
    func togglePlayback() { isPlaying ? pause() : resume() }

    func next() {
        guard !isLastStage else { return }
        stageIndex += 1
        time = 0
    }

    /// Near the start of a chapter this goes back a chapter; otherwise it
    /// restarts this one, as story viewers do.
    func previous() {
        if time > 0.8 || stageIndex == 0 {
            time = 0
        } else {
            stageIndex -= 1
            time = 0
        }
    }

    func skipToSummary() {
        stageIndex = stages.count - 1
        time = timeline.build + 0.0001
        isPlaying = false
    }

    func replay() {
        stageIndex = 0
        time = 0
        isPlaying = true
    }
}
