import RelevanceKit
import SwiftUI
import WidgetKit

private struct DoneAtWatchEntry: TimelineEntry {
    let date: Date
    let display: WatchDisplayAvailability
    /// The shown shift's work segments, so the ring and bar can leave lunch as a gap.
    var segments: [[Int64]] = []
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
            // Keep the render archive bounded while preserving minute progress
            // for the first hour and every exact rule and expiry boundary.
            let entries = WatchDisplayProjection.timelineDates(for: package, from: now).map {
                let nowMs = Int64($0.timeIntervalSince1970 * 1_000)
                return DoneAtWatchEntry(date: $0, display: WatchDisplayProjection.project(package, nowMs: nowMs),
                                        segments: WatchCountdownSegments.segments(package, nowMs: nowMs).map { [$0.0, $0.1] })
            }
            completion(.init(entries: entries, policy: .after(now.addingTimeInterval(3_600))))
        }
    }

    /// A hint that the shift window is when this complication matters. watchOS
    /// weighs it against everything else; it does not pin the widget in place.
    func relevance() async -> WidgetRelevance<Void> {
        guard let fileURL = WatchSnapshotCache.appGroupFileURL() else { return WidgetRelevance([]) }
        let package = await WatchSnapshotCache.open(fileURL: fileURL).currentPackage()
        let intervals = WatchDisplayProjection.relevantIntervals(
            for: package, nowMs: Int64(Date.now.timeIntervalSince1970 * 1_000)
        )
        return WidgetRelevance(intervals.map {
            WidgetRelevanceAttribute(context: RelevantContext.date(interval: $0, kind: .scheduled))
        })
    }

    private func entry(at date: Date) async -> DoneAtWatchEntry {
        guard let fileURL = WatchSnapshotCache.appGroupFileURL() else { return .init(date: date, display: .waiting) }
        let cache = await WatchSnapshotCache.open(fileURL: fileURL)
        let package = await cache.currentPackage()
        let nowMs = Int64(date.timeIntervalSince1970 * 1_000)
        return .init(date: date, display: WatchDisplayProjection.project(package, nowMs: nowMs),
                     segments: WatchCountdownSegments.segments(package, nowMs: nowMs).map { [$0.0, $0.1] })
    }
}

private struct DoneAtWatchWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DoneAtWatchEntry

    var body: some View {
        // Placeholders speak the Watch's language; shift content overrides this with the iPhone app's.
        content
            .environment(\.layoutDirection, WatchDisplayFormat.isRightToLeft(
                localeIdentifier: WatchLocalizations.resolveLocale(Locale.preferredLanguages)
            ) ? .rightToLeft : .leftToRight)
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(URL(string: "offworkcountdown://timer"))
    }

    @ViewBuilder private var content: some View {
        switch entry.display {
        case .content(let value):
            Group {
                switch family {
                case .accessoryCircular: circular(value)
                case .accessoryCorner: corner(value)
                case .accessoryInline: inline(value)
                default: rectangular(value)
                }
            }
            .environment(\.locale, WatchDisplayFormat.locale(value.presentation))
            .environment(\.layoutDirection, WatchDisplayFormat.isRightToLeft(
                localeIdentifier: value.presentation.localeIdentifier
            ) ? .rightToLeft : .leftToRight)
        case .waiting:
            unavailable(WatchLocalizations.text("watchWaitingForIPhone"), symbol: "iphone.and.arrow.forward")
        case .locked:
            unavailable(WatchLocalizations.text("watchWaitingForIPhone"), symbol: "iphone")
        case .confirmationRequired:
            unavailable(WatchLocalizations.text("watchWaitingForIPhone"), symbol: "iphone")
        case .pending:
            unavailable(WatchLocalizations.text("watchWaitingForIPhone"), symbol: "clock")
        case .contentExpired, .invalid:
            unavailable(WatchLocalizations.text("watchSyncExpired"), symbol: "arrow.clockwise")
        }
    }

    // MARK: Circular — a closed gauge for a share of the shift, as the HIG recommends.

    @ViewBuilder private func circular(_ value: WatchDisplayContent) -> some View {
        let presentation = value.presentation
        if let progress = value.progress, let phase = value.phase, phase != .before {
            ZStack {
                WatchSegmentRing(weights: weights, progress: progress / 100, lineWidth: 4.5)
                VStack(spacing: 0) {
                    if phase == .working || phase == .overtime, let end = timerEnd(value) {
                        WatchHoursMinutes(end: end, from: entry.date.addingTimeInterval(-3_600))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                    } else {
                        Image(systemName: WatchDisplayFormat.symbol(for: phase))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    if let footnote = WatchDisplayFormat.footnote(for: value) {
                        Text(verbatim: WatchDisplayFormat.time(footnote.atMs, presentation))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .minimumScaleFactor(0.6)
                    }
                }
                .padding(5)
            }
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
            if let phase = value.phase, phase != .before {
                Label(WatchDisplayFormat.label(for: phase, presentation), systemImage: WatchDisplayFormat.symbol(for: phase))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .widgetAccentable()
                if phase == .finished || phase == .resting, let footnote {
                    headline(footnote)
                } else if phase == .working || phase == .overtime, let end = timerEnd(value) {
                    Text(timerInterval: min(entry.date.addingTimeInterval(-3_600), end)...end, countsDown: true)
                        .font(.headline)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else if let remaining = value.remainingMs {
                    headline(text("watchTimeLeft", presentation,
                                  ["duration": WatchDisplayFormat.shortDuration(remaining, presentation)]))
                }
                if let progress = value.progress {
                    HStack(spacing: 6) {
                        segmentBar(progress: progress / 100, finished: phase == .finished)
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
                if let next = value.upcomingShiftStartAtMs {
                    Text(Date(timeIntervalSince1970: Double(next) / 1_000), style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var weights: [Double] {
        let values = entry.segments.map { Double(max(0, $0[1] - $0[0])) }
        return values.isEmpty ? [1] : values
    }

    /// When effective work runs out, in real time: the countdown skips lunch.
    private func timerEnd(_ value: WatchDisplayContent) -> Date? {
        guard let remaining = value.remainingMs, remaining > 0 else { return nil }
        return entry.date.addingTimeInterval(Double(remaining) / 1_000)
    }

    private func segmentBar(progress: Double, finished: Bool) -> some View {
        let total = max(0.000_1, weights.reduce(0, +))
        var remaining = min(1, max(0, progress)) * total
        let fills = weights.map { weight -> Double in
            let filled = min(weight, max(0, remaining))
            remaining -= weight
            return weight > 0 ? filled / weight : 0
        }
        return HStack(spacing: 3) {
            ForEach(Array(fills.enumerated()), id: \.offset) { index, fill in
                Gauge(value: fill) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(finished ? .secondary : .orange)
                    .widgetAccentable()
                    .frame(maxWidth: .infinity)
                    .layoutPriority(weights[index] / total)
            }
        }
    }

    // MARK: Corner — the time left along the bezel.

    @ViewBuilder private func corner(_ value: WatchDisplayContent) -> some View {
        let presentation = value.presentation
        if let progress = value.progress, let phase = value.phase, phase != .before {
            Group {
                if phase == .working || phase == .overtime, let end = timerEnd(value) {
                    WatchHoursMinutes(end: end, from: entry.date.addingTimeInterval(-3_600))
                } else {
                    Image(systemName: WatchDisplayFormat.symbol(for: phase))
                }
            }
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .widgetCurvesContent()
            .widgetLabel {
                Gauge(value: min(100, max(0, progress)), in: 0...100) { EmptyView() }
                    .tint(.orange)
            }
            .accessibilityLabel(WatchDisplayFormat.label(for: phase, presentation))
        } else {
            Image(systemName: "moon.zzz").font(.title3).widgetAccentable()
                .widgetLabel(presentation.restingLabel)
        }
    }

    // MARK: Inline — one line above the time.

    @ViewBuilder private func inline(_ value: WatchDisplayContent) -> some View {
        let presentation = value.presentation
        if let footnote = WatchDisplayFormat.footnote(for: value) {
            let time = text(footnote.key, presentation, ["time": WatchDisplayFormat.footnoteTime(footnote, presentation)])
            if value.phase == .working, let remaining = value.remainingMs {
                Text(verbatim: "\(time) · \(WatchDisplayFormat.shortDuration(remaining, presentation))")
            } else {
                Text(verbatim: time)
            }
        } else {
            Text(verbatim: value.phase == nil ? presentation.restingLabel : "DoneAt")
        }
    }

    private func headline(_ string: String) -> some View {
        Text(string)
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    @ViewBuilder private func unavailable(_ message: String, symbol: String) -> some View {
        if family == .accessoryInline {
            Text(message)
        } else if family == .accessoryCircular || family == .accessoryCorner {
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
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}

@main struct DoneAtWatchWidgets: WidgetBundle {
    var body: some Widget {
        DoneAtWatchWidget()
        DoneAtWatchWeekWidget()
        DoneAtWatchShiftWidget()
        DoneAtWatchHolidayWidget()
        DoneAtWatchUpNextWidget()
    }
}
