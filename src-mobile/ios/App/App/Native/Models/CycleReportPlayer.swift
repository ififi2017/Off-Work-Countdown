import Foundation
import Observation

/// The pages of a report, in the order the plan tells them: the period, the
/// time put in, the time off, how it compares, the pay, and a close.
/// Each one makes a single point; a page with nothing to say is left out.
nonisolated enum CycleReportStage: Hashable, Sendable {
    case calendar
    case hours
    case rest
    case comparison
    case income
    case summary

    /// `nil` stages are simply absent: no comparison without a previous period
    /// that holds data, no income unless the person asked for it.
    static func stages(for snapshot: CycleReportSnapshot) -> [Self] {
        guard snapshot.hasData else { return [] }
        var result: [Self] = [.calendar, .hours, .rest]
        if snapshot.comparison != nil { result.append(.comparison) }
        if snapshot.income != nil { result.append(.income) }
        result.append(.summary)
        return result
    }

    /// How many steps the page takes to build itself after it appears.
    func beatCount(for snapshot: CycleReportSnapshot) -> Int {
        switch self {
        case .calendar: snapshot.days.count
        case .hours: snapshot.days.filter { $0.kind == .work }.count + 1
        case .rest: 2
        case .comparison, .income: 1
        case .summary: 0
        }
    }

    func beatInterval(for snapshot: CycleReportSnapshot) -> Duration {
        switch self {
        case .calendar:
            // A month of days should not take a month of beats.
            .milliseconds(Int(max(40, min(140, 2_000 / max(1, snapshot.days.count)))))
        case .hours:
            .milliseconds(Int(max(60, min(220, 1_800 / max(1, beatCount(for: snapshot))))))
        default: .milliseconds(650)
        }
    }

    static let dwell: Duration = .milliseconds(1_900)
}

/// Drives a report's playback. The pages are pure functions of `stageIndex` and
/// `beat`, so pausing, skipping and replaying only move those two numbers and
/// nothing is left half-built. Every page reads the one `snapshot` it was given.
@MainActor
@Observable
final class CycleReportPlayer {
    let snapshot: CycleReportSnapshot
    let stages: [CycleReportStage]
    private(set) var stageIndex = 0
    private(set) var beat = 0
    private(set) var isPlaying: Bool
    @ObservationIgnored private let sleep: @Sendable (Duration) async -> Void

    init(
        snapshot: CycleReportSnapshot,
        autoplay: Bool = true,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.snapshot = snapshot
        stages = CycleReportStage.stages(for: snapshot)
        isPlaying = autoplay
        self.sleep = sleep
    }

    var stage: CycleReportStage { stages[stageIndex] }
    var isLastStage: Bool { stageIndex == stages.count - 1 }
    var beatCount: Int { stage.beatCount(for: snapshot) }
    var isBuilt: Bool { beat >= beatCount }

    /// Runs until paused, cancelled or the last page is up. The view re-runs it
    /// whenever `isPlaying` changes, which is what cancels a pause.
    func run() async {
        while !Task.isCancelled, isPlaying {
            if beat < beatCount {
                await sleep(stage.beatInterval(for: snapshot))
                guard !Task.isCancelled, isPlaying else { return }
                beat += 1
            } else if isLastStage {
                isPlaying = false
                return
            } else {
                await sleep(CycleReportStage.dwell)
                guard !Task.isCancelled, isPlaying else { return }
                stageIndex += 1
                beat = 0
            }
        }
    }

    func pause() { isPlaying = false }
    func resume() {
        if isLastStage, isBuilt { replay() } else { isPlaying = true }
    }
    func togglePlayback() { isPlaying ? pause() : resume() }

    func next() {
        guard !isLastStage else { return }
        stageIndex += 1
        beat = 0
    }

    func previous() {
        guard stageIndex > 0 else { return }
        stageIndex -= 1
        beat = 0
    }

    func skipToSummary() {
        stageIndex = stages.count - 1
        beat = beatCount
        isPlaying = false
    }

    func replay() {
        stageIndex = 0
        beat = 0
        isPlaying = true
    }
}
