import UIKit

/// Advances a report from frames delivered by the main display.
@MainActor
final class CycleReportDisplayLink {
    private static let maximumFrameDelta: TimeInterval = 0.1

    private weak var player: CycleReportPlayer?
    private var displayLink: CADisplayLink?
    private var target: CycleReportDisplayLinkTarget?
    private var previousTimestamp: CFTimeInterval?

    init(player: CycleReportPlayer) {
        self.player = player
    }

    func start() {
        guard player?.isRunning == true, displayLink == nil else { return }
        previousTimestamp = nil

        let target = CycleReportDisplayLinkTarget(owner: self)
        let displayLink = CADisplayLink(
            target: target,
            selector: #selector(CycleReportDisplayLinkTarget.frameDidRefresh(_:))
        )
        let maximumFPS = Self.maximumFrameRate
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: min(60, maximumFPS),
            maximum: maximumFPS,
            preferred: maximumFPS
        )
        self.target = target
        self.displayLink = displayLink
        displayLink.add(to: .main, forMode: .common)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        target = nil
        previousTimestamp = nil
    }

    /// Consumes one display timestamp. Kept internal so playback tests can
    /// exercise frame gaps deterministically without starting a real run loop.
    func update(at timestamp: CFTimeInterval) {
        guard let player, player.isRunning else {
            stop()
            return
        }

        guard let previousTimestamp else {
            self.previousTimestamp = timestamp
            return
        }
        self.previousTimestamp = timestamp

        let elapsed = max(0, timestamp - previousTimestamp)
        player.advance(by: min(elapsed, Self.maximumFrameDelta))
        if player.isLastStage, player.isBuilt {
            player.pause()
            stop()
        }
    }

    private static var maximumFrameRate: Float {
        let connectedRates = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.maximumFramesPerSecond }
        let displayMaximum = connectedRates.max() ?? 60
        return Float(max(60, min(120, displayMaximum)))
    }
}

/// CADisplayLink retains its target. This proxy keeps that reference from
/// retaining the display-link owner, which in turn owns the link.
@MainActor
private final class CycleReportDisplayLinkTarget: NSObject {
    weak var owner: CycleReportDisplayLink?

    init(owner: CycleReportDisplayLink) {
        self.owner = owner
    }

    @objc func frameDidRefresh(_ displayLink: CADisplayLink) {
        guard let owner else {
            displayLink.invalidate()
            return
        }
        owner.update(at: displayLink.timestamp)
    }
}
