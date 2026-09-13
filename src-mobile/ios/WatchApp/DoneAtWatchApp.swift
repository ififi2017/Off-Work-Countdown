import SwiftUI

@main
struct DoneAtWatchApp: App {
    @State private var model: WatchAppModel
    private let receiver: WatchSnapshotReceiver
    private let showsReviewFixture: Bool
    private let forcesReducedLuminance: Bool

    init() {
        let model = WatchAppModel()
        _model = State(initialValue: model)
        receiver = WatchSnapshotReceiver(model: model)
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let fixture = WatchReviewFixture(arguments: arguments)
        showsReviewFixture = fixture != nil
        forcesReducedLuminance = arguments.contains("-owcWatchReviewAlwaysOn")
        if let fixture { model.publish(fixture.package, connectionState: .ready) }
#else
        showsReviewFixture = false
        forcesReducedLuminance = false
#endif
    }

    var body: some Scene {
        WindowGroup {
            root.task {
                // A review fixture stands in for the phone; never overwrite real data with it.
                guard !showsReviewFixture else { return }
                await receiver.start()
            }
        }
    }

    @ViewBuilder private var root: some View {
        if forcesReducedLuminance {
            WatchRootView(model: model).environment(\.isLuminanceReduced, true)
        } else {
            WatchRootView(model: model)
        }
    }
}

struct WatchRootView: View {
    let model: WatchAppModel
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        // Seconds tick only while the screen is fully awake; Always On updates by the minute.
        TimelineView(.periodic(from: .now, by: isLuminanceReduced ? 60 : 1)) { timeline in
            // Notices speak the Watch's language; shift content overrides this with the iPhone app's.
            let screen = content(at: timeline.date)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
                .environment(\.layoutDirection, WatchDisplayFormat.isRightToLeft(
                    localeIdentifier: WatchLocalizations.resolveLocale(Locale.preferredLanguages)
                ) ? .rightToLeft : .leftToRight)
            // Centred when it fits; larger text sizes scroll instead of clipping.
            ViewThatFits(in: .vertical) {
                screen
                ScrollView { screen }
            }
        }
    }

    @ViewBuilder
    private func content(at date: Date) -> some View {
        let nowMs = Int64(date.timeIntervalSince1970 * 1_000)
        switch WatchDisplayProjection.project(model.package, nowMs: nowMs) {
        case .waiting:
            notice(WatchLocalizations.text("watchWaitingForIPhone"), symbol: "iphone.and.arrow.forward")
        case .locked:
            plusNotice
        case .confirmationRequired, .pending:
            notice(WatchLocalizations.text("watchConfirmPlusOnIPhone"), symbol: "iphone")
        case .contentExpired:
            notice(WatchLocalizations.text("watchSyncExpired"), symbol: "arrow.clockwise")
        case .invalid:
            notice(WatchLocalizations.text("watchOpenIPhone"), symbol: "exclamationmark.triangle")
        case .content(let value):
            shift(value)
                .environment(\.locale, WatchDisplayFormat.locale(value.presentation))
                .environment(\.layoutDirection, WatchDisplayFormat.isRightToLeft(
                    localeIdentifier: value.presentation.localeIdentifier
                ) ? .rightToLeft : .leftToRight)
        }
    }

    // MARK: Shift

    @ViewBuilder
    private func shift(_ value: WatchDisplayContent) -> some View {
        let presentation = value.presentation
        let footnote = WatchDisplayFormat.footnote(for: value).map {
            text($0.key, presentation, ["time": WatchDisplayFormat.footnoteTime($0, presentation)])
        }
        if value.scheduleState == .notConfigured {
            notice(text("watchOpenIPhone", presentation), symbol: "calendar.badge.exclamationmark")
        } else if let phase = value.phase {
            VStack(spacing: 4) {
                Label(WatchDisplayFormat.label(for: phase, presentation), systemImage: WatchDisplayFormat.symbol(for: phase))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(phase == .finished ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                if phase != .finished, let remaining = value.remainingMs {
                    VStack(spacing: 0) {
                        Text(text("watchTimeLeftTitle", presentation))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(verbatim: WatchDisplayFormat.clock(remaining, showsSeconds: !isLuminanceReduced, presentation))
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                if let progress = value.progress {
                    ProgressView(value: min(100, max(0, progress)), total: 100)
                        .tint(phase == .finished ? .secondary : .orange)
                        .opacity(isLuminanceReduced ? 0.6 : 1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                if let footnote {
                    secondary(footnote)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(spacing: 4) {
                Label(value.scheduleState == .stopped ? presentation.finishedLabel : presentation.restingLabel,
                      systemImage: "moon.zzz")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let next = value.nextShiftStartAtMs {
                    Text(Date(timeIntervalSince1970: Double(next) / 1_000), style: .relative)
                        .font(.system(.title3, design: .rounded, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if let footnote {
                    secondary(footnote)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func secondary(_ string: String) -> some View {
        Text(string)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .opacity(isLuminanceReduced ? 0.8 : 1)
            .multilineTextAlignment(.center)
            .lineLimit(2)
    }

    // MARK: Notices

    private func notice(_ message: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }

    /// Explains what Plus adds on the wrist without taking away what stays free.
    private var plusNotice: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock")
                .font(.title3)
                .foregroundStyle(.orange)
            Text(verbatim: "DoneAt Plus")
                .font(.headline)
            Text(WatchLocalizations.text("watchPlusIncludes"))
                .font(.footnote)
                .multilineTextAlignment(.center)
            Text(WatchLocalizations.text("watchPlusOnIPhone"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }

    private func text(_ key: String, _ presentation: WatchPresentationV1, _ values: [String: String] = [:]) -> String {
        WatchDisplayFormat.fill(WatchLocalizations.text(key, localeIdentifier: presentation.localeIdentifier), values)
    }
}

#if DEBUG
/// Simulator review states, so every screen can be captured without editing
/// real data: launch with `-owcWatchReviewState <state>` where state is one of
/// working, lunch, overtime, finished, rest, unconfigured, locked, confirm,
/// expired or waiting; optionally `-owcWatchReviewLocale zh-CN` and
/// `-owcWatchReviewAlwaysOn`. Debug builds only; the receiver never starts.
private struct WatchReviewFixture {
    let package: WatchSnapshotPackageV1?

    init?(arguments: [String]) {
        guard let state = Self.value(after: "-owcWatchReviewState", in: arguments) else { return nil }
        let locale = Self.value(after: "-owcWatchReviewLocale", in: arguments) ?? "en"
        let now = Int64(Date.now.timeIntervalSince1970 * 1_000)
        let minute: Int64 = 60_000
        let hour = 60 * minute
        let chinese = locale.hasPrefix("zh")
        let presentation = WatchPresentationV1(
            localeIdentifier: locale, timeZoneIdentifier: TimeZone.current.identifier,
            workingLabel: chinese ? "工作中" : "Working", lunchLabel: chinese ? "午休" : "Lunch",
            restingLabel: chinese ? "休息" : "Resting", overtimeLabel: chinese ? "加班" : "Overtime",
            finishedLabel: chinese ? "已下班" : "Off work")

        func scheduled(_ shift: WatchShiftProjectionV1?, next: WatchNextShiftV1? = nil) -> WatchShiftContentV1 {
            .init(scheduleState: .scheduled, shift: shift, nextShift: next, presentation: presentation)
        }
        func twoPart(_ first: ClosedRange<Int64>, _ second: ClosedRange<Int64>) -> WatchShiftProjectionV1 {
            .init(segments: [.init(startAtMs: first.lowerBound, endAtMs: first.upperBound),
                             .init(startAtMs: second.lowerBound, endAtMs: second.upperBound)],
                  plannedEndAtMs: second.upperBound, overtimeEndAtMs: nil, finishedAtMs: nil, isRunning: true,
                  transitions: [.init(atMs: first.lowerBound, state: .working), .init(atMs: first.upperBound, state: .lunch),
                                .init(atMs: second.lowerBound, state: .working), .init(atMs: second.upperBound, state: .finished)])
        }

        switch state {
        case "working":
            package = Self.package(now: now, content: scheduled(twoPart((now - 3 * hour)...(now - hour), (now - 10 * minute)...(now + 3 * hour + 30 * minute))))
        case "lunch":
            package = Self.package(now: now, content: scheduled(twoPart((now - 3 * hour)...(now - 15 * minute), (now + 45 * minute)...(now + 4 * hour + 30 * minute))))
        case "overtime":
            let start = now - 9 * hour, planned = now - 30 * minute, end = now + 90 * minute
            package = Self.package(now: now, content: scheduled(.init(
                segments: [.init(startAtMs: start, endAtMs: end)], plannedEndAtMs: planned, overtimeEndAtMs: end,
                finishedAtMs: nil, isRunning: true,
                transitions: [.init(atMs: start, state: .working), .init(atMs: planned, state: .overtime), .init(atMs: end, state: .finished)])))
        case "finished":
            let start = now - 8 * hour, planned = now + hour, finished = now - 20 * minute
            package = Self.package(now: now, content: scheduled(.init(
                segments: [.init(startAtMs: start, endAtMs: planned)], plannedEndAtMs: planned, overtimeEndAtMs: nil,
                finishedAtMs: finished, isRunning: false,
                transitions: [.init(atMs: start, state: .working), .init(atMs: finished, state: .finished)])))
        case "rest":
            let next = now + 15 * hour
            package = Self.package(now: now, content: scheduled(nil, next: .init(startAtMs: next, validUntilMs: next)))
        case "unconfigured":
            package = Self.package(now: now, content: .init(scheduleState: .notConfigured, shift: nil, nextShift: nil, presentation: presentation))
        case "locked":
            package = Self.package(now: now, access: .locked, content: nil)
        case "confirm":
            package = Self.package(now: now, access: .unknown, content: nil)
        case "expired":
            package = Self.package(now: now, content: .init(scheduleState: .notConfigured, shift: nil, nextShift: nil, presentation: presentation),
                                   generatedAtMs: now - 3 * hour, expiresAtMs: now - minute)
        case "waiting":
            package = nil
        default:
            return nil
        }
    }

    private static func package(
        now: Int64, access: WatchAccessProjectionV1.Status = .lifetime, content: WatchShiftContentV1?,
        generatedAtMs: Int64? = nil, expiresAtMs: Int64? = nil
    ) -> WatchSnapshotPackageV1 {
        let generated = generatedAtMs ?? now - 60_000
        return .init(
            schemaVersion: 1, sourceGeneration: "review", revision: 1, generatedAtMs: generated,
            expiresAtMs: expiresAtMs ?? now + 20 * 3_600_000,
            access: .init(schemaVersion: 1, revision: 1, verifiedAtMs: generated, status: access, validUntilMs: nil),
            content: content)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
#endif
