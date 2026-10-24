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
    /// The skeleton follows the real layout: a shift in the afternoon, not
    /// the "waiting for iPhone" state.
    func placeholder(in context: Context) -> DoneAtWatchEntry { Self.sample(at: .now) }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (DoneAtWatchEntry) -> Void) {
        let isPreview = context.isPreview
        Task {
            let entry = await entry(at: .now)
            // The face gallery shows what the complication looks like before any sync.
            if isPreview, case .content = entry.display { completion(entry) }
            else if isPreview { completion(Self.sample(at: .now)) }
            else { completion(entry) }
        }
    }

    /// 09:00–12:00 and 13:00–18:00, two thirds done at 15:19.
    static func sample(at date: Date) -> DoneAtWatchEntry {
        let nowMs = Int64(date.timeIntervalSince1970 * 1_000)
        let minute: Int64 = 60_000
        let start = nowMs - (6 * 60 + 19) * minute
        let end = nowMs + (2 * 60 + 41) * minute
        let content = WatchDisplayContent(
            scheduleState: .scheduled, phase: .working, remainingMs: end - nowMs, progress: 66,
            effectiveEndAtMs: end, nextBoundaryAtMs: end, nextShiftStartAtMs: nil, presentation: WatchWidgetSample.presentation
        )
        return .init(date: date, display: .content(content),
                     segments: [[start, start + 180 * minute], [start + 240 * minute, end]])
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
            // WidgetKit renders every entry up front. Only boundaries and 5%
            // progress steps get one; the countdown clocks run by themselves.
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
                WatchSegmentRing(weights: weights, progress: WatchDisplayFormat.steppedProgress(progress) / 100,
                                 lineWidth: 4.5)
                VStack(spacing: 0) {
                    if let countdown = countdown(value) {
                        countdown
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
            .accessibilityValue(accessibilitySummary(value, progress: WatchDisplayFormat.steppedProgress(progress)))
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
                } else if let countdown = countdown(value) {
                    countdown
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
                        segmentBar(progress: WatchDisplayFormat.steppedProgress(progress) / 100,
                                   finished: phase == .finished)
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

    /// A system countdown while work runs. Entries only come at boundaries and
    /// 5% steps, so a clock formatted per entry would fall up to a step behind.
    private func countdown(_ value: WatchDisplayContent) -> Text? {
        guard value.phase == .working || value.phase == .overtime, let end = timerEnd(value) else { return nil }
        return Text(timerInterval: min(entry.date.addingTimeInterval(-3_600), end)...end, countsDown: true)
    }

    private func segmentBar(progress: Double, finished: Bool) -> some View {
        WatchSegmentBar(segments: WatchSegmentBar.fills(weights: weights, progress: progress),
                        tint: finished ? .secondary : .orange, gap: 3)
    }

    // MARK: Corner — the time left along the bezel.

    @ViewBuilder private func corner(_ value: WatchDisplayContent) -> some View {
        let presentation = value.presentation
        if let progress = value.progress, let phase = value.phase, phase != .before {
            Group {
                if let countdown = countdown(value) {
                    countdown
                } else {
                    Image(systemName: WatchDisplayFormat.symbol(for: phase))
                }
            }
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .widgetCurvesContent()
            .widgetLabel {
                Gauge(value: WatchDisplayFormat.steppedProgress(progress), in: 0...100) { EmptyView() }
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
            if value.phase == .working, let countdown = countdown(value) {
                Text("\(time) · \(countdown)")
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

    /// Read with the live countdown, so VoiceOver is as current as the face.
    private func accessibilitySummary(_ value: WatchDisplayContent, progress: Double) -> Text {
        let presentation = value.presentation
        var parts: [Text] = []
        if let countdown = countdown(value) {
            let template = WatchLocalizations.text("watchTimeLeft", localeIdentifier: presentation.localeIdentifier)
                .components(separatedBy: "{{duration}}")
            parts.append(template.count == 2 ? Text("\(template[0])\(countdown)\(template[1])") : countdown)
        } else if value.phase != .finished, let remaining = value.remainingMs {
            parts.append(Text(text("watchTimeLeft", presentation,
                                   ["duration": WatchDisplayFormat.shortDuration(remaining, presentation)])))
        }
        parts.append(Text(WatchDisplayFormat.percent(progress, presentation)))
        if let footnote = WatchDisplayFormat.footnote(for: value) {
            parts.append(Text(text(footnote.key, presentation, ["time": WatchDisplayFormat.footnoteTime(footnote, presentation)])))
        }
        return parts.dropFirst().reduce(parts[0]) { Text("\($0), \($1)") }
    }

    private func text(_ key: String, _ presentation: WatchPresentationV1, _ values: [String: String] = [:]) -> String {
        WatchDisplayFormat.fill(WatchLocalizations.text(key, localeIdentifier: presentation.localeIdentifier), values)
    }
}

struct DoneAtWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchWidgetKind.countdown, provider: DoneAtWatchProvider()) { DoneAtWatchWidgetView(entry: $0) }
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
