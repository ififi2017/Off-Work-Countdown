import Foundation
import Observation
import Synchronization
import WatchConnectivity
import WidgetKit

@MainActor
@Observable
final class WatchAppModel {
    enum ConnectionState: Equatable {
        case waiting
        case ready
        case persistenceFailed
        case cacheCorrupt
        case cacheIncompatible
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

    /// Bounded retries after an unusable answer. They may be scheduled from a
    /// foreground or background trigger, but never keep a system background
    /// task open; a later reachability or foreground event can start over.
    static let defaultRetryDelays: [Duration] = [.seconds(15), .seconds(45), .seconds(120)]

    let model: WatchAppModel

    private let session: WCSession
    private let cacheURL: URL?
    private let transport: Transport
    private let usesSystemSession: Bool
    private let retryDelays: [Duration]
    private var cache: WatchSnapshotCache?
    private var startTask: Task<Void, Never>?
    private var activationFinished = false
    private nonisolated let pendingDeliveries = Mutex(0)
    private var pendingContext: Data?
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
            reloadWidgets: {
                WidgetCenter.shared.reloadTimelines(ofKind: "DoneAtWatchWidget")
                // A new package can move the shift window the Smart Stack hint describes.
                WidgetCenter.shared.invalidateRelevance(ofKind: "DoneAtWatchWidget")
            }
        )
        super.init()
    }

    func start() async {
        if let startTask { await startTask.value; return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.initialize()
        }
        startTask = task
        await task.value
    }

    private func initialize() async {
        guard !usesSystemSession || WCSession.isSupported(),
              let fileURL = cacheURL ?? WatchSnapshotCache.appGroupFileURL() else {
            model.publish(nil, connectionState: .unavailable)
            return
        }
        let cache = await WatchSnapshotCache.open(fileURL: fileURL)
        self.cache = cache
        let restored = await cache.currentPackage()
        let state: WatchAppModel.ConnectionState = switch await cache.loadState() {
        case .empty: .waiting
        case .ready: restored == nil ? .waiting : .ready
        case .corrupt: .cacheCorrupt
        case .incompatible: .cacheIncompatible
        }
        model.publish(restored, connectionState: state)
        guard usesSystemSession else { return }
        session.delegate = self
        session.activate()
    }

    func receiveContext(_ data: Data?, alreadyCounted: Bool = false) async {
        guard let data else { return }
        if !alreadyCounted { beginDelivery() }
        defer { endDelivery() }
        guard let cache else { return }
        let result = await cache.receiveApplicationContext(data)
        await apply(result, cache: cache)
        switch result {
        case .rejected(.rejectWrongGeneration), .rejected(.rejectBaseline):
            // A newer configuration may supersede an outstanding large file.
            // Renew the trusted baseline instead of waiting for an app launch.
            pendingContext = data
            await requestPairing()
        default:
            break
        }
    }

    /// The system owns this short background execution window. Do not finish
    /// it while activation, delegate delivery or atomic cache writes remain.
    func handleBackgroundConnectivity() async {
        await start()
        guard usesSystemSession else { return }
        repeat {
            await Task.yield()
            if activationFinished && !session.hasContentPending && pendingDeliveryCount == 0 { return }
            do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
        } while !Task.isCancelled
    }

    /// `attempt` counts retries of one request; a new trigger starts again at 0.
    func requestPairing(attempt: Int = 0) async {
        if attempt == 0 { retryTask?.cancel() }
        guard transport.isReady(), let cache else { return }
        let hello = await cache.makePairingHello()
        guard let data = try? JSONEncoder().encode(hello), data.count <= WatchPairingContract.maximumEncodedBytes else { return }
        transport.sendHello(data, { @Sendable [weak self] reply in
            self?.beginDelivery()
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.receivePairingReply(reply, attempt: attempt, alreadyCounted: true)
            }
        }, { @Sendable [weak self] in
            Task { @MainActor [weak self] in self?.scheduleRetry(after: attempt) }
        })
    }

    private func receivePairingReply(_ data: Data, attempt: Int, alreadyCounted: Bool = false) async {
        if !alreadyCounted { beginDelivery() }
        defer { endDelivery() }
        guard let cache else { return }
        let result = await cache.receivePairingReply(data)
        await apply(result, cache: cache)
        if result == .accepted || result == .duplicate, let pending = pendingContext {
            pendingContext = nil
            await apply(await cache.receiveApplicationContext(pending), cache: cache)
        }
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
            guard model.package == nil else { break }
            switch await cache.loadState() {
            case .corrupt: model.publish(nil, connectionState: .cacheCorrupt)
            case .incompatible: model.publish(nil, connectionState: .cacheIncompatible)
            case .empty, .ready: break
            }
        }
    }

    private nonisolated var pendingDeliveryCount: Int {
        pendingDeliveries.withLock { $0 }
    }

    nonisolated var pendingDeliveryCountForTesting: Int { pendingDeliveryCount }

    private nonisolated func beginDelivery() {
        pendingDeliveries.withLock { $0 += 1 }
    }

    private nonisolated func endDelivery() {
        pendingDeliveries.withLock { $0 -= 1 }
    }
}

extension WatchSnapshotReceiver: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        let contextData = session.receivedApplicationContext[WatchPairingContract.snapshotContextKey] as? Data
        if contextData != nil { beginDelivery() }
        Task { @MainActor [weak self] in
            self?.activationFinished = true
            guard let self, activationState == .activated else {
                self?.model.publish(self?.model.package, connectionState: .unavailable)
                if contextData != nil { self?.endDelivery() }
                return
            }
            await self.receiveContext(contextData, alreadyCounted: contextData != nil)
            await self.requestPairing()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext[WatchPairingContract.snapshotContextKey] as? Data
        guard data != nil else { return }
        beginDelivery()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.receiveContext(data, alreadyCounted: true)
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // WCSession deletes this temporary file when the delegate returns.
        guard file.metadata?["watchScheduleV2"] as? Bool == true,
              let size = try? file.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= WatchSnapshotContract.maximumEncodedBytes,
              let data = try? Data(contentsOf: file.fileURL), data.count <= WatchSnapshotContract.maximumEncodedBytes
        else { return }
        beginDelivery()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.receiveContext(data, alreadyCounted: true)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        guard reachable else { return }
        Task { @MainActor [weak self] in await self?.requestPairing() }
    }
}
