import SwiftUI
import WidgetKit

private struct DoneAtWatchEntry: TimelineEntry {
    let date: Date
    let display: WatchDisplayAvailability
}

private struct DoneAtWatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> DoneAtWatchEntry { .init(date: .now, display: .waiting) }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (DoneAtWatchEntry) -> Void) {
        Task { completion(await entry(at: .now)) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<DoneAtWatchEntry>) -> Void) {
        Task {
            let now = Date.now
            guard let fileURL = WatchSnapshotCache.appGroupFileURL() else {
                completion(.init(entries: [.init(date: now, display: .waiting)], policy: .after(now.addingTimeInterval(900))))
                return
            }
            let cache = await WatchSnapshotCache.open(fileURL: fileURL)
            let package = await cache.currentPackage()
            // Minute entries plus every exact rule and expiry boundary. Values are
            // minute-granular on purpose: no second ticks on the watch face.
            let entries = WatchDisplayProjection.timelineDates(for: package, from: now).map {
                DoneAtWatchEntry(date: $0, display: WatchDisplayProjection.project(
                    package, nowMs: Int64($0.timeIntervalSince1970 * 1_000)
                ))
            }
            completion(.init(entries: entries, policy: .after(now.addingTimeInterval(3_600))))
        }
    }

    private func entry(at date: Date) async -> DoneAtWatchEntry {
        guard let fileURL = WatchSnapshotCache.appGroupFileURL() else { return .init(date: date, display: .waiting) }
        let cache = await WatchSnapshotCache.open(fileURL: fileURL)
        let package = await cache.currentPackage()
        return .init(date: date, display: WatchDisplayProjection.project(
            package, nowMs: Int64(date.timeIntervalSince1970 * 1_000)
        ))
    }
}

private struct DoneAtWatchWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DoneAtWatchEntry

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(URL(string: "offworkcountdown://timer"))
    }

    @ViewBuilder private var content: some View {
        switch entry.display {
        case .content(let value):
            Group {
                if family == .accessoryCircular { circular(value) } else { rectangular(value) }
            }
            .environment(\.locale, WatchDisplayFormat.locale(value.presentation))
        case .waiting:
            unavailable(WatchLocalizations.text("watchWaitingForIPhone"), symbol: "iphone.and.arrow.forward")
        case .locked:
            unavailable("DoneAt Plus", symbol: "lock")
        case .confirmationRequired:
            unavailable(WatchLocalizations.text("watchConfirmPlusOnIPhone"), symbol: "iphone")
        case .pending:
            unavailable(WatchLocalizations.text("watchWaitingForIPhone"), symbol: "clock")
        case .contentExpired, .invalid:
            unavailable(WatchLocalizations.text("watchSyncExpired"), symbol: "arrow.clockwise")
        }
    }

    // MARK: Circular — a closed gauge for a share of the shift, as the HIG recommends.

    @ViewBuilder private func circular(_ value: WatchDisplayContent) -> some View {
        let presentation = value.presentation
        if let progress = value.progress, let phase = value.phase {
            Gauge(value: min(100, max(0, progress)), in: 0...100) {
                Image(systemName: WatchDisplayFormat.symbol(for: phase))
            } currentValueLabel: {
                Text(verbatim: WatchDisplayFormat.percent(progress, presentation))
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(phase == .finished ? .secondary : .orange)
            .widgetAccentable()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(WatchDisplayFormat.label(for: phase, presentation))
            .accessibilityValue(accessibilitySummary(value))
        } else {
            let notConfigured = value.scheduleState == .notConfigured
            Image(systemName: notConfigured ? "calendar.badge.exclamationmark" : "moon.zzz")
                .font(.title3)
                .widgetAccentable()
                .accessibilityLabel(notConfigured ? text("watchOpenIPhone", presentation) : presentation.restingLabel)
        }
    }

    // MARK: Rectangular — title, the value with its unit, and a gauge with the time that explains it.

    private func rectangular(_ value: WatchDisplayContent) -> some View {
        let presentation = value.presentation
        let footnote = WatchDisplayFormat.footnote(for: value).map {
            text($0.key, presentation, ["time": WatchDisplayFormat.footnoteTime($0, presentation)])
        }
        return VStack(alignment: .leading, spacing: 1) {
            if let phase = value.phase {
                Label(WatchDisplayFormat.label(for: phase, presentation), systemImage: WatchDisplayFormat.symbol(for: phase))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .widgetAccentable()
                if phase == .finished, let footnote {
                    headline(footnote)
                } else if let remaining = value.remainingMs {
                    headline(text("watchTimeLeft", presentation,
                                  ["duration": WatchDisplayFormat.shortDuration(remaining, presentation)]))
                }
                if let progress = value.progress {
                    HStack(spacing: 6) {
                        Gauge(value: min(100, max(0, progress)), in: 0...100) { EmptyView() }
                            .gaugeStyle(.accessoryLinearCapacity)
                            .tint(phase == .finished ? .secondary : .orange)
                            .widgetAccentable()
                        if phase != .finished, let footnote {
                            Text(footnote)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
            } else if value.scheduleState == .notConfigured {
                Label(text("watchOpenIPhone", presentation), systemImage: "calendar.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label(value.scheduleState == .stopped ? presentation.finishedLabel : presentation.restingLabel,
                      systemImage: "moon.zzz")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .widgetAccentable()
                if let footnote { headline(footnote) }
                if let next = value.nextShiftStartAtMs {
                    Text(Date(timeIntervalSince1970: Double(next) / 1_000), style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func headline(_ string: String) -> some View {
        Text(string)
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    @ViewBuilder private func unavailable(_ message: String, symbol: String) -> some View {
        if family == .accessoryCircular {
            Image(systemName: symbol)
                .font(.title3)
                .widgetAccentable()
                .accessibilityLabel(message)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "DoneAt")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .widgetAccentable()
                Label(message, systemImage: symbol)
                    .font(.caption)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func accessibilitySummary(_ value: WatchDisplayContent) -> String {
        let presentation = value.presentation
        var parts: [String] = []
        if value.phase != .finished, let remaining = value.remainingMs {
            parts.append(text("watchTimeLeft", presentation, ["duration": WatchDisplayFormat.shortDuration(remaining, presentation)]))
        }
        if let progress = value.progress { parts.append(WatchDisplayFormat.percent(progress, presentation)) }
        if let footnote = WatchDisplayFormat.footnote(for: value) {
            parts.append(text(footnote.key, presentation, ["time": WatchDisplayFormat.footnoteTime(footnote, presentation)]))
        }
        return parts.joined(separator: ", ")
    }

    private func text(_ key: String, _ presentation: WatchPresentationV1, _ values: [String: String] = [:]) -> String {
        WatchDisplayFormat.fill(WatchLocalizations.text(key, localeIdentifier: presentation.localeIdentifier), values)
    }
}

struct DoneAtWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DoneAtWatchWidget", provider: DoneAtWatchProvider()) { DoneAtWatchWidgetView(entry: $0) }
            .configurationDisplayName("DoneAt")
            .description(WatchLocalizations.text("watchWidgetDescription"))
            .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

@main struct DoneAtWatchWidgets: WidgetBundle {
    var body: some Widget { DoneAtWatchWidget() }
}
