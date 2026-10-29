import RelevanceKit
import SwiftUI
import WidgetKit

private struct DoneAtWatchEntry: TimelineEntry {
    let date: Date
    let display: WatchDisplayAvailability
    /// The shown shift's work segments, so the ring and bar can leave lunch as a gap.
    var segments: [[Int64]] = []
    /// The provider gave this entry a neighbour at every minute the
    /// hour-and-minute clock changes, so it may draw that clock from the entry.
    var minuteClock = false
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
            func entry(_ date: Date) -> DoneAtWatchEntry {
                let nowMs = Int64(date.timeIntervalSince1970 * 1_000)
                return DoneAtWatchEntry(date: date, display: WatchDisplayProjection.project(package, nowMs: nowMs),
                                        segments: WatchCountdownSegments.segments(package, nowMs: nowMs).map { [$0.0, $0.1] })
            }
            let dates = WatchDisplayProjection.timelineDates(for: package, from: now)
            var entries = dates.map(entry)
            // The circular and inline clocks drop seconds above an hour, so they need an
            // entry where a countdown reaches the last hour before the next one.
            let marks = entries.indices.compactMap { index -> Date? in
                guard let mark = Self.lastHourMark(entries[index]) else { return nil }
                let next = entries.indices.contains(index + 1) ? entries[index + 1].date : .distantFuture
                return mark < next ? mark : nil
            }
            if !marks.isEmpty {
                entries = Array(Set(dates + marks)).sorted().map(entry)
            }
            // No system format counts down in hours and minutes without a
            // sign, so above an hour that clock is drawn from each entry and
            // needs one per minute. Only near the start: the timeline reloads
            // hourly, and later entries keep the live clock with seconds.
            let window = now.addingTimeInterval(Self.minuteClockWindow)
            let minutes = entries.indices.flatMap { index -> [Date] in
                let next = entries.indices.contains(index + 1) ? entries[index + 1].date : .distantFuture
                return Self.minuteMarks(entries[index], until: min(next, window))
            }
            if !minutes.isEmpty {
                entries = Array(Set(entries.map(\.date) + minutes)).sorted().map(entry)
            }
            for index in entries.indices where entries[index].date < window {
                entries[index].minuteClock = true
            }
            completion(.init(entries: entries, policy: .after(now.addingTimeInterval(3_600))))
        }
    }

    /// When a running countdown in this entry falls to one hour.
    static func lastHourMark(_ entry: DoneAtWatchEntry) -> Date? {
        guard case .content(let value) = entry.display, value.phase == .working || value.phase == .overtime,
              let remaining = value.remainingMs, remaining > DoneAtWatchWidgetView.secondsThresholdMs else { return nil }
        return entry.date.addingTimeInterval(Double(remaining - DoneAtWatchWidgetView.secondsThresholdMs) / 1_000)
    }

    static let minuteClockWindow: TimeInterval = 2 * 3_600

    /// When a running countdown in this entry reaches each whole minute above
    /// one hour, before `limit`.
    static func minuteMarks(_ entry: DoneAtWatchEntry, until limit: Date) -> [Date] {
        guard case .content(let value) = entry.display, value.phase == .working || value.phase == .overtime,
              let remaining = value.remainingMs, remaining > DoneAtWatchWidgetView.secondsThresholdMs else { return [] }
        let minute: Int64 = 60_000
        var marks: [Date] = []
        var left = remaining % minute == 0 ? remaining - minute : remaining - remaining % minute
        while left > DoneAtWatchWidgetView.secondsThresholdMs {
            let date = entry.date.addingTimeInterval(Double(remaining - left) / 1_000)
            guard date < limit else { break }
            marks.append(date)
            left -= minute
        }
        return marks
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
            GeometryReader { proxy in
            // The ring's stroke ends a line width inside the square it is drawn in.
            let inner = max(0, min(proxy.size.width, proxy.size.height) - 2 * Self.circularRingWidth)
            ZStack {
                WatchSegmentRing(weights: weights, progress: WatchDisplayFormat.steppedProgress(progress) / 100,
                                 lineWidth: Self.circularRingWidth)
                VStack(spacing: 0) {
                    if let countdown = circularCountdown(value) {
                        // One line no wider than 70% of the ring's inner
                        // diameter. A live timer does not report a narrower
                        // width, so the frame is fixed; the fixed line height
                        // keeps the footnote in place when the clock scales.
                        countdown
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .multilineTextAlignment(.center)
                            .frame(width: inner * 0.7, height: Self.circularClockHeight)
                    } else {
                        Image(systemName: WatchDisplayFormat.symbol(for: phase))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    if let footnote = WatchDisplayFormat.footnote(for: value) {
                        Text(verbatim: WatchDisplayFormat.time(footnote.atMs, presentation))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .padding(5)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
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
                        // The bar keeps room for its segments; a long footnote
                        // (German, overtime) scales rather than covering it.
                        segmentBar(progress: WatchDisplayFormat.steppedProgress(progress) / 100,
                                   finished: phase == .finished)
                            .frame(minWidth: 28)
                        if phase != .finished, let footnote {
                            Text(footnote)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .layoutPriority(1)
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

    static let circularRingWidth: CGFloat = 4.5
    /// The 14 pt clock's line height, kept when it scales down to fit.
    static let circularClockHeight: CGFloat = 17
    /// Above this the circular and inline clocks show hours and minutes only.
    static let secondsThresholdMs: Int64 = 3_600_000
    /// How far a minute entry's timestamp may miss its mark through
    /// millisecond truncation and still be read as landing on it.
    static let minuteMarkToleranceMs: Int64 = 5

    /// Whole minutes left, rounded down, for an entry that stays on screen
    /// until the next minute mark. The clock is read just after the entry's
    /// date: an entry at exactly 1:15:00 left stays up until the 1:14:00
    /// entry, so it reads "1:14" — the floor of everything it is on screen
    /// for. Reading "1:15" there would run a minute ahead for that minute.
    /// One that is a few milliseconds early (1:15:00.003) is the same mark.
    /// An entry between marks (1:15:33) reads "1:15" until the 1:15:00
    /// entry replaces it.
    static func shownMinutes(_ remainingMs: Int64) -> Int64 {
        max(0, remainingMs - 1 - minuteMarkToleranceMs) / 60_000
    }

    /// The circular and inline clock, at most five characters: "1:15" or
    /// "12:34" above an hour (seconds dropped, minutes not rounded up, no
    /// sign), "15:33" within it. Above an hour it comes from the entry, which
    /// the provider places at each minute; without such entries it is the
    /// live clock with seconds. The provider also adds an entry where a
    /// countdown reaches one hour so the clock switches style there.
    private func circularCountdown(_ value: WatchDisplayContent) -> Text? {
        guard value.phase == .working || value.phase == .overtime, let end = timerEnd(value) else { return nil }
        if let remaining = value.remainingMs, remaining > Self.secondsThresholdMs + Self.minuteMarkToleranceMs {
            guard entry.minuteClock else { return countdown(value) }
            return Text(Duration.seconds(Self.shownMinutes(remaining) * 60),
                        format: .time(pattern: .hourMinute(padHourToLength: 1)))
        }
        return Text(timerInterval: min(entry.date.addingTimeInterval(-3_600), end)...end, countsDown: true, showsHours: false)
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
            // The short clock, as on the circular face. Where the whole line
            // does not fit, the end time goes and the countdown stays.
            if value.phase == .working, let countdown = circularCountdown(value) {
                ViewThatFits(in: .horizontal) {
                    Text("\(time) · \(countdown)")
                    countdown
                }
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
