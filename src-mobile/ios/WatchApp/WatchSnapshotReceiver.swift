import Foundation
import Observation
import WatchConnectivity
import WidgetKit

@MainActor
@Observable
final class WatchAppModel {
    enum ConnectionState: Equatable {
        case waiting
        case ready
        case persistenceFailed
        case unavailable
    }

    private(set) var package: WatchSnapshotPackageV1?
    private(set) var connectionState: ConnectionState = .waiting

    func publish(_ package: WatchSnapshotPackageV1?, connectionState: ConnectionState) {
        self.package = package
        self.connectionState = connectionState
    }
}

@MainActor
final class WatchSnapshotReceiver: NSObject {
    /// The things the receiver asks of the outside world. Production uses
    /// WatchConnectivity and WidgetKit; tests record the calls instead.
    struct Transport {
        var isReady: () -> Bool
        /// Sends a hello; exactly one of `reply` or `failed` is called later,
        /// off the main actor.
        var sendHello: (
            _ data: Data,
            _ reply: @escaping @Sendable (Data) -> Void,
            _ failed: @escaping @Sendable () -> Void
        ) -> Void
        var reloadWidgets: () -> Void
    }

    /// Foreground-only retries after an unusable answer. The phone can be
    /// reachable before it can bind a baseline, and nothing else would ask
    /// again until reachability changes. Bounded: this is not a background timer.
    static let defaultRetryDelays: [Duration] = [.seconds(15), .seconds(45), .seconds(120)]

    let model: WatchAppModel

    private let session: WCSession
    private let cacheURL: URL?
    private let transport: Transport
    private let usesSystemSession: Bool
    private let retryDelays: [Duration]
    private var cache: WatchSnapshotCache?
    private var started = false
    private var retryTask: Task<Void, Never>?

    init(
        model: WatchAppModel = WatchAppModel(),
        session: WCSession = .default,
        cacheURL: URL? = nil,
        transport: Transport? = nil,
        retryDelays: [Duration] = WatchSnapshotReceiver.defaultRetryDelays
    ) {
        self.model = model
        self.session = session
        self.cacheURL = cacheURL
        self.retryDelays = retryDelays
        usesSystemSession = transport == nil
        self.transport = transport ?? Transport(
            isReady: { session.activationState == .activated && session.isReachable },
            sendHello: { data, reply, failed in
                // WatchConnectivity calls both blocks on its own queue; both
                // arrive `@Sendable`, so neither assumes main-actor isolation.
                session.sendMessageData(data, replyHandler: reply, errorHandler: { @Sendable _ in failed() })
            },
            reloadWidgets: { WidgetCenter.shared.reloadTimelines(ofKind: "DoneAtWatchWidget") }
        )
        super.init()
    }

    func start() async {
        guard !started else { return }
        started = true
        guard !usesSystemSession || WCSession.isSupported(),
              let fileURL = cacheURL ?? WatchSnapshotCache.appGroupFileURL() else {
            model.publish(nil, connectionState: .unavailable)
            return
        }
        let cache = await WatchSnapshotCache.open(fileURL: fileURL)
        self.cache = cache
        let restored = await cache.currentPackage()
        model.publish(restored, connectionState: restored == nil ? .waiting : .ready)
        guard usesSystemSession else { return }
        session.delegate = self
        session.activate()
    }

    func receiveContext(_ data: Data?) async {
        guard let cache, let data else { return }
        await apply(await cache.receiveApplicationContext(data), cache: cache)
    }

    /// `attempt` counts retries of one request; a new trigger starts again at 0.
    func requestPairing(attempt: Int = 0) async {
        if attempt == 0 { retryTask?.cancel() }
        guard transport.isReady(), let cache else { return }
        let hello = await cache.makePairingHello()
        guard let data = try? JSONEncoder().encode(hello), data.count <= WatchPairingContract.maximumEncodedBytes else { return }
        transport.sendHello(data, { @Sendable [weak self] reply in
            Task { @MainActor [weak self] in await self?.receivePairingReply(reply, attempt: attempt) }
        }, { @Sendable [weak self] in
            Task { @MainActor [weak self] in self?.scheduleRetry(after: attempt) }
        })
    }

    private func receivePairingReply(_ data: Data, attempt: Int) async {
        guard let cache else { return }
        let result = await cache.receivePairingReply(data)
        await apply(result, cache: cache)
        switch result {
        case .accepted, .duplicate:
            retryTask?.cancel()
        case .pairingResetRequired:
            await requestPairing()
        case .rejected, .persistenceFailed:
            scheduleRetry(after: attempt)
        }
    }

    private func scheduleRetry(after attempt: Int) {
        guard attempt < retryDelays.count else { return }
        retryTask?.cancel()
        let delay = retryDelays[attempt]
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.requestPairing(attempt: attempt + 1)
        }
    }

    private func apply(_ result: WatchSnapshotCacheReceiveResult, cache: WatchSnapshotCache) async {
        switch result {
        case .accepted:
            model.publish(await cache.currentPackage(), connectionState: .ready)
            transport.reloadWidgets()
        case .persistenceFailed:
            model.publish(model.package, connectionState: .persistenceFailed)
        case .pairingResetRequired:
            model.publish(nil, connectionState: .waiting)
            transport.reloadWidgets()
        case .duplicate:
            if model.package == nil {
                let restored = await cache.currentPackage()
                model.publish(restored, connectionState: restored == nil ? .waiting : .ready)
            }
        case .rejected:
            break
        }
    }
}

extension WatchSnapshotReceiver: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        let contextData = session.receivedApplicationContext[WatchPairingContract.snapshotContextKey] as? Data
        Task { @MainActor [weak self] in
            guard let self, activationState == .activated else {
                self?.model.publish(self?.model.package, connectionState: .unavailable)
                return
            }
            await self.receiveContext(contextData)
            await self.requestPairing()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext[WatchPairingContract.snapshotContextKey] as? Data
        Task { @MainActor [weak self] in await self?.receiveContext(data) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        guard reachable else { return }
        Task { @MainActor [weak self] in await self?.requestPairing() }
    }
}
