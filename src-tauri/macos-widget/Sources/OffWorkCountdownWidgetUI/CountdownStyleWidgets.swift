import Foundation
import SwiftUI
import WidgetKit
#if OWC_SWIFT_PACKAGE
import WidgetSnapshotContract
#endif

// Extra countdown styles (plan 023 W1). They read the same snapshot and
// timeline as the original countdown widget, which keeps its own kind and
// layout so widgets people already placed do not change.

public let countdownBigDigitsWidgetKind = "\(offWorkCountdownWidgetKind).bigdigits"
public let countdownRingWidgetKind = "\(offWorkCountdownWidgetKind).ring"
public let countdownTimelineWidgetKind = "\(offWorkCountdownWidgetKind).timeline"
public let countdownDetailWidgetKind = "\(offWorkCountdownWidgetKind).detail"

public struct CountdownStyleEntry: TimelineEntry, Sendable {
    public let base: OffWorkCountdownWidgetEntry
    /// The current shift's effective work, in the snapshot's logical time.
    public let segments: [WidgetShiftSegment]
    public var date: Date { base.date }

    public init(base: OffWorkCountdownWidgetEntry, segments: [WidgetShiftSegment]) {
        self.base = base
        self.segments = segments
    }
}

public struct CountdownStyleProvider: TimelineProvider, Sendable {
    private let inner: OffWorkCountdownTimelineProvider
    private let loader: SharedWidgetSnapshotLoader
    private let carriesUpcoming: Bool

    public init(appGroupIdentifier: String?, storageMode: String = "app-group", carriesUpcoming: Bool = false) {
        inner = OffWorkCountdownTimelineProvider(appGroupIdentifier: appGroupIdentifier, storageMode: storageMode)
        loader = SharedWidgetSnapshotLoader(appGroupIdentifier: appGroupIdentifier, storageMode: storageMode)
        self.carriesUpcoming = carriesUpcoming
    }

    public func placeholder(in context: Context) -> CountdownStyleEntry {
        CountdownStyleEntry(base: inner.placeholder(in: context), segments: [])
    }

    public func getSnapshot(in context: Context, completion: @escaping @Sendable (CountdownStyleEntry) -> Void) {
        let base = inner.makeSnapshotEntry(now: Date(), family: carriesUpcoming ? nil : context.family)
        completion(CountdownStyleEntry(base: base, segments: loader.load()?.shift?.segments ?? []))
    }

    public func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<CountdownStyleEntry>) -> Void) {
        let timeline = inner.makeTimeline(now: Date(), family: carriesUpcoming ? nil : context.family)
        let segments = loader.load()?.shift?.segments ?? []
        completion(Timeline(
            entries: timeline.entries.map { CountdownStyleEntry(base: $0, segments: segments) },
            policy: timeline.policy
        ))
    }
}

/// What every style needs from one entry, worked out once.
struct CountdownStyleModel {
    let entry: CountdownStyleEntry

    var snapshotEntry: WidgetTimelineEntry? { entry.base.snapshotEntry }
    var locale: String { entry.base.locale }
    var offset: Int64 { entry.base.clockOffsetMs }
    var phase: WidgetTimelinePhase { snapshotEntry?.phase ?? .idle }

    var label: String {
        snapshotEntry.map { WidgetCopy.text($0.labelKey, locale: locale, compact: true) }
            ?? WidgetCopy.text("countdownNotStarted", locale: locale)
    }

    /// Rest copy has two semantic clauses in every locale. Break at its
    /// localized separator rather than letting a narrow card split a clause.
    var timelineLabel: String {
        guard snapshotEntry?.labelKey == "widgetRestDay" else { return label }
        return WidgetCopy.text("widgetRestDay", locale: locale)
            .replacingOccurrences(of: " · ", with: "\n")
    }

    var isCounting: Bool { timerEnd != nil && (phase == .working || phase == .break || phase == .before) }

    /// When the countdown reaches zero, in real time. Work counts down
    /// effective time, so lunch is skipped; every other phase counts to its
    /// own target.
    var timerEnd: Date? {
        guard let snapshotEntry else { return nil }
        switch snapshotEntry.countdownKind {
        case .workRemaining:
            let remaining = snapshotEntry.remainingEffectiveMsAtDateMs
            guard remaining > 0 else { return nil }
            return Date(timeIntervalSince1970: Double(snapshotEntry.dateMs + remaining + offset) / 1_000)
        default:
            guard let target = snapshotEntry.countdownTargetAtMs else { return nil }
            return Date(timeIntervalSince1970: Double(target + offset) / 1_000)
        }
    }

    /// The clock time the countdown names: clock-off at work, back from lunch, clock-in before.
    var targetTime: Date? {
        guard let target = snapshotEntry?.countdownTargetAtMs else { return nil }
        return Date(timeIntervalSince1970: Double(target + offset) / 1_000)
    }

    /// A missing current shift on a rest day is not an idle countdown.
    var timelineWaitingTarget: Date? {
        guard phase == .before,
              let target = snapshotEntry?.countdownTargetAtMs,
              target > entry.base.logicalNowMs else { return nil }
        return targetTime
    }

    var progress: Double { min(1, max(0, (snapshotEntry?.progressAtDate ?? 0) / 100)) }

    /// Lunch is a gap only while the shift is under way; before clock-in the
    /// ring measures the wait, which has no lunch in it.
    var segmentWeights: [Double] {
        guard phase == .working || phase == .break else { return [1] }
        let weights = entry.segments.map { Double(max(0, $0.endAtMs - $0.startAtMs)) }
        return weights.isEmpty ? [1] : weights
    }

    /// Bounded below by a moment that has certainly passed, never by the
    /// entry's own date (see the Live Activity's `activityTimerRange`).
    var timerRange: ClosedRange<Date>? {
        guard let end = timerEnd else { return nil }
        let start = min(entry.date.addingTimeInterval(-3_600), end)
        return start...end
    }

    var phaseColor: Color {
        switch phase {
        case .before: .indigo
        case .working: CountdownStylePalette.accent
        case .break: .cyan
        case .done: .green
        case .idle: .secondary
        }
    }
}

enum CountdownStylePalette {
    static let accent = Color(red: 1.0, green: 0.38, blue: 0.08)
    static let track = Color.primary.opacity(0.10)
}

/// The countdown drawn by the system, so it keeps counting while the
/// extension sleeps. A minute-precision system timer switches to words
/// ("6 hr 53 min") in many languages, and per-minute timeline entries would
/// spend the extension's render budget, so the styles keep the seconds.
struct CountdownHoursMinutes: View {
    let range: ClosedRange<Date>

    var body: some View {
        Text(timerInterval: range, countsDown: true)
    }
}

/// A ring cut into the shift's work segments; lunch is the gap.
struct CountdownSegmentRing: View {
    let weights: [Double]
    let progress: Double
    var lineWidth: CGFloat = 8
    var tint: Color = CountdownStylePalette.accent

    var body: some View {
        GeometryReader { proxy in
            let total = max(0.000_1, weights.reduce(0, +))
            let gap = weights.count > 1 ? Self.gap(lineWidth: lineWidth, diameter: min(proxy.size.width, proxy.size.height)) : 0
            let arcs = Self.arcs(weights: weights, total: total, gap: gap, progress: progress)
            ZStack {
                ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
                    Circle().trim(from: arc.start, to: arc.end)
                        .stroke(CountdownStylePalette.track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    if arc.fill > arc.start {
                        Circle().trim(from: arc.start, to: arc.fill)
                            .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    }
                }
            }
            .rotationEffect(.degrees(-90))
            // A square centred in whatever frame the ring is given.
            .frame(width: min(proxy.size.width, proxy.size.height), height: min(proxy.size.width, proxy.size.height))
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .padding(lineWidth / 2)
    }

    /// The gap between segments as a share of the circumference. Round caps
    /// reach half a line width into it from each side, so the gap is a line
    /// width plus clear space that stays visible at any ring size.
    static func gap(lineWidth: CGFloat, diameter: CGFloat) -> Double {
        let circumference = max(1, Double(diameter) * .pi)
        return min(0.2, Double(lineWidth + max(2.5, lineWidth * 0.6)) / circumference)
    }

    static func arcs(weights: [Double], total: Double, gap: Double, progress: Double) -> [(start: Double, end: Double, fill: Double)] {
        var result: [(Double, Double, Double)] = []
        var cursor = 0.0
        var remaining = min(1, max(0, progress)) * total
        for weight in weights {
            let share = weight / total
            let start = cursor + gap / 2
            let end = max(start, cursor + share - gap / 2)
            let filled = min(weight, remaining)
            remaining -= filled
            result.append((start, end, start + (end - start) * (weight > 0 ? filled / weight : 0)))
            cursor += share
        }
        return result
    }
}

struct CountdownSegmentBar: View {
    let weights: [Double]
    let progress: Double
    var height: CGFloat = 6

    var body: some View {
        let total = max(0.000_1, weights.reduce(0, +))
        let fills = Self.fills(weights: weights, progress: progress, total: total)
        GeometryReader { proxy in
            let gap: CGFloat = 3
            let usable = proxy.size.width - gap * CGFloat(max(0, weights.count - 1))
            HStack(spacing: gap) {
                ForEach(Array(weights.enumerated()), id: \.offset) { index, weight in
                    let width = usable * weight / total
                    ZStack(alignment: .leading) {
                        Capsule().fill(CountdownStylePalette.track)
                        // A started segment shows at least a dot, not a sliver.
                        Capsule().fill(CountdownStylePalette.accent)
                            .frame(width: fills[index] > 0 ? max(height, width * fills[index]) : 0)
                    }
                    .frame(width: max(height, width))
                }
            }
        }
        .frame(height: height)
    }

    static func fills(weights: [Double], progress: Double, total: Double) -> [Double] {
        var remaining = min(1, max(0, progress)) * total
        return weights.map { weight in
            let filled = min(weight, max(0, remaining))
            remaining -= weight
            return weight > 0 ? filled / weight : 0
        }
    }
}

extension View {
    @ViewBuilder func countdownStyleBackground() -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            #if os(iOS)
            // The same surface as the widget suite: `.background` resolves to
            // black in dark mode, systemBackground to the elevated widget grey.
            containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
            #else
            containerBackground(for: .widget) { Color.clear.background(.background) }
            #endif
        } else {
            padding()
        }
    }
}

// MARK: - Big digits

public struct CountdownBigDigitsWidget: Widget {
    private let appGroupIdentifier: String?
    private let storageMode: String

    public init() {
        appGroupIdentifier = Bundle.main.object(forInfoDictionaryKey: "OWCAppGroupIdentifier") as? String
        storageMode = Bundle.main.object(forInfoDictionaryKey: "OWCWidgetStorageMode") as? String ?? "app-group"
    }

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: countdownBigDigitsWidgetKind,
                            provider: CountdownStyleProvider(appGroupIdentifier: appGroupIdentifier, storageMode: storageMode)) { entry in
            CountdownBigDigitsView(model: CountdownStyleModel(entry: entry))
                .environment(\.locale, Locale(identifier: entry.base.locale))
        }
        .configurationDisplayName(Text(verbatim: WidgetCopy.text("widgetStyleBigName", locale: WidgetCopy.currentLocaleIdentifier)))
        .description(Text(verbatim: WidgetCopy.text("widgetStyleBigDescription", locale: WidgetCopy.currentLocaleIdentifier)))
        .supportedFamilies([.systemSmall])
    }
}

public struct CountdownBigDigitsView: View {
    let model: CountdownStyleModel

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)
            Label(model.label, systemImage: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let range = model.timerRange, model.isCounting {
                CountdownHoursMinutes(range: range)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            } else {
                Image(systemName: model.phase == .done ? "checkmark.circle.fill" : "sun.horizon.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(model.phaseColor)
                    .padding(.vertical, 6)
            }
            if let target = model.targetTime, model.isCounting {
                Text(target, style: .time)
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(model.phaseColor)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .countdownStyleBackground()
        .widgetURL(URL(string: "offworkcountdown://timer"))
    }

    private var symbol: String {
        switch model.phase {
        case .working: "briefcase.fill"
        case .break: "cup.and.saucer.fill"
        case .before: "sunrise.fill"
        case .done: "checkmark"
        case .idle: "play.fill"
        }
    }
}

// MARK: - Ring

public struct CountdownRingWidget: Widget {
    private let appGroupIdentifier: String?
    private let storageMode: String

    public init() {
        appGroupIdentifier = Bundle.main.object(forInfoDictionaryKey: "OWCAppGroupIdentifier") as? String
        storageMode = Bundle.main.object(forInfoDictionaryKey: "OWCWidgetStorageMode") as? String ?? "app-group"
    }

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: countdownRingWidgetKind,
                            provider: CountdownStyleProvider(appGroupIdentifier: appGroupIdentifier, storageMode: storageMode)) { entry in
            CountdownRingView(model: CountdownStyleModel(entry: entry))
                .environment(\.locale, Locale(identifier: entry.base.locale))
        }
        .configurationDisplayName(Text(verbatim: WidgetCopy.text("widgetStyleRingName", locale: WidgetCopy.currentLocaleIdentifier)))
        .description(Text(verbatim: WidgetCopy.text("widgetStyleRingDescription", locale: WidgetCopy.currentLocaleIdentifier)))
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .accessoryCircular]
        #else
        [.systemSmall]
        #endif
    }
}

public struct CountdownRingView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    /// Settings › Widgets renders these views at sizes the app's own
    /// environment cannot claim; widgets leave it nil.
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? environmentFamily }
    let model: CountdownStyleModel

    public var body: some View {
        ZStack {
            CountdownSegmentRing(weights: model.segmentWeights, progress: model.progress,
                                 lineWidth: isAccessory ? 5 : 9,
                                 tint: isAccessory ? .primary : model.phaseColor)
            VStack(spacing: 0) {
                if !isAccessory, model.phase == .working || model.phase == .break {
                    Image(systemName: model.phase == .break ? "cup.and.saucer.fill" : "briefcase.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(model.phaseColor)
                }
                if let range = model.timerRange, model.isCounting {
                    CountdownHoursMinutes(range: range)
                        .font(.system(size: isAccessory ? 14 : 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .multilineTextAlignment(.center)
                } else {
                    Image(systemName: model.phase == .done ? "checkmark" : "play.fill")
                        .font(isAccessory ? .body.bold() : .title.bold())
                }
                if !isAccessory, let target = model.targetTime, model.isCounting {
                    Text(target, style: .time)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(isAccessory ? 6 : 18)
        }
        .padding(isAccessory ? 0 : 4)
        .countdownStyleBackground()
        .widgetURL(URL(string: "offworkcountdown://timer"))
    }

    private var isAccessory: Bool {
        #if os(iOS)
        family == .accessoryCircular
        #else
        false
        #endif
    }
}

// MARK: - Today's timeline

public struct CountdownTimelineWidget: Widget {
    private let appGroupIdentifier: String?
    private let storageMode: String

    public init() {
        appGroupIdentifier = Bundle.main.object(forInfoDictionaryKey: "OWCAppGroupIdentifier") as? String
        storageMode = Bundle.main.object(forInfoDictionaryKey: "OWCWidgetStorageMode") as? String ?? "app-group"
    }

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: countdownTimelineWidgetKind,
                            provider: CountdownStyleProvider(appGroupIdentifier: appGroupIdentifier, storageMode: storageMode)) { entry in
            CountdownTimelineView(model: CountdownStyleModel(entry: entry))
                .environment(\.locale, Locale(identifier: entry.base.locale))
        }
        .configurationDisplayName(Text(verbatim: WidgetCopy.text("widgetStyleTimelineName", locale: WidgetCopy.currentLocaleIdentifier)))
        .description(Text(verbatim: WidgetCopy.text("widgetStyleTimelineDescription", locale: WidgetCopy.currentLocaleIdentifier)))
        .supportedFamilies([.systemSmall])
    }
}

public struct CountdownTimelineView: View {
    let model: CountdownStyleModel

    public var body: some View {
        let segments = model.entry.segments
        VStack(alignment: .leading, spacing: 8) {
            Label(model.timelineLabel, systemImage: "calendar.day.timeline.left")
                .multilineTextAlignment(.leading)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let first = segments.first, let last = segments.last, last.endAtMs > first.startAtMs {
                CountdownDayAxis(segments: segments, nowMs: model.entry.base.logicalNowMs,
                                 offset: model.offset, locale: Locale(identifier: model.locale))
            } else {
                Spacer(minLength: 0)
                if let target = model.timelineWaitingTarget, let range = model.timerRange {
                    CountdownHoursMinutes(range: range)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(CountdownDetailView.when(Int64(target.timeIntervalSince1970 * 1_000),
                                                  now: model.entry.date, locale: Locale(identifier: model.locale)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text(model.label)
                        .font(.footnote.weight(.semibold))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .countdownStyleBackground()
        .widgetURL(URL(string: "offworkcountdown://timer"))
    }
}

/// The shift drawn to scale down the side: work as bars, lunch as the gap
/// between them, and labels at each boundary and at now.
struct CountdownDayAxis: View {
    let segments: [WidgetShiftSegment]
    let nowMs: Int64
    let offset: Int64
    let locale: Locale

    private struct Mark: Identifiable {
        let id: Int
        let atMs: Int64
        let text: String
        let isNow: Bool
    }

    var body: some View {
        let startMs = segments.first?.startAtMs ?? 0
        let span = Double(max(1, (segments.last?.endAtMs ?? 1) - startMs))
        GeometryReader { proxy in
            let height = proxy.size.height
            let y: (Int64) -> CGFloat = { CGFloat(Double($0 - startMs) / span) * height }
            ZStack(alignment: .topLeading) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    let top = y(segment.startAtMs)
                    let bottom = y(segment.endAtMs)
                    let done = min(1, max(0, Double(nowMs - segment.startAtMs) / Double(max(1, segment.endAtMs - segment.startAtMs))))
                    ZStack(alignment: .top) {
                        Capsule().fill(CountdownStylePalette.track)
                        Capsule().fill(CountdownStylePalette.accent).frame(height: (bottom - top) * done)
                    }
                    .frame(width: 6, height: max(6, bottom - top))
                    .offset(y: top)
                }
                ForEach(marks) { mark in
                    Text(mark.text)
                        .font(.caption2.weight(mark.isNow ? .bold : .regular).monospacedDigit())
                        .foregroundStyle(mark.isNow ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(height: 14)
                        .offset(x: 16, y: min(max(0, y(mark.atMs) - 7), height - 14))
                }
            }
        }
    }

    private var marks: [Mark] {
        func time(_ ms: Int64) -> String {
            Date(timeIntervalSince1970: Double(ms + offset) / 1_000).formatted(.dateTime.hour().minute().locale(locale))
        }
        var result: [Mark] = []
        guard let first = segments.first, let last = segments.last else { return [] }
        result.append(Mark(id: 0, atMs: first.startAtMs, text: time(first.startAtMs), isNow: false))
        for index in segments.indices.dropLast() {
            let gapStart = segments[index].endAtMs
            let gapEnd = segments[index + 1].startAtMs
            result.append(Mark(id: index + 1, atMs: (gapStart + gapEnd) / 2, text: "\(time(gapStart))–\(time(gapEnd))", isNow: false))
        }
        result.append(Mark(id: 100, atMs: last.endAtMs, text: time(last.endAtMs), isNow: false))
        if nowMs > first.startAtMs, nowMs < last.endAtMs {
            // Now replaces whichever label it would sit on.
            let span = Double(max(1, last.endAtMs - first.startAtMs))
            result.removeAll { abs(Double($0.atMs - nowMs)) / span < 0.12 }
            result.append(Mark(id: 200, atMs: nowMs, text: "▸ \(time(nowMs))", isNow: true))
        }
        return result
    }
}

// MARK: - Detail (medium / large / extra large)

public struct CountdownDetailWidget: Widget {
    private let appGroupIdentifier: String?
    private let storageMode: String

    public init() {
        appGroupIdentifier = Bundle.main.object(forInfoDictionaryKey: "OWCAppGroupIdentifier") as? String
        storageMode = Bundle.main.object(forInfoDictionaryKey: "OWCWidgetStorageMode") as? String ?? "app-group"
    }

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: countdownDetailWidgetKind,
                            provider: CountdownStyleProvider(appGroupIdentifier: appGroupIdentifier, storageMode: storageMode,
                                                             carriesUpcoming: true)) { entry in
            CountdownDetailView(model: CountdownStyleModel(entry: entry))
                .environment(\.locale, Locale(identifier: entry.base.locale))
        }
        .configurationDisplayName(Text(verbatim: WidgetCopy.text("widgetStyleDetailName", locale: WidgetCopy.currentLocaleIdentifier)))
        .description(Text(verbatim: WidgetCopy.text("widgetStyleDetailDescription", locale: WidgetCopy.currentLocaleIdentifier)))
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemMedium, .systemLarge, .systemExtraLarge]
        #else
        [.systemMedium, .systemLarge]
        #endif
    }
}

public struct CountdownDetailView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    /// Settings › Widgets renders these views at sizes the app's own
    /// environment cannot claim; widgets leave it nil.
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? environmentFamily }
    let model: CountdownStyleModel

    public var body: some View {
        Group {
            switch family {
            case .systemLarge: large
            #if os(iOS)
            case .systemExtraLarge: extraLarge
            #endif
            default: medium
            }
        }
        .countdownStyleBackground()
        .widgetURL(URL(string: "offworkcountdown://timer"))
    }

    private var upcoming: [WidgetUpcomingItem] {
        let nowMs = model.entry.base.logicalNowMs
        return model.entry.base.upcoming.filter { $0.dateMs > nowMs }
    }

    private var percent: String {
        model.progress.formatted(.percent.precision(.fractionLength(0)).locale(Locale(identifier: model.locale)))
    }

    private var status: some View {
        HStack(spacing: 6) {
            Circle().fill(model.phaseColor).frame(width: 6, height: 6)
            Text(model.label).font(.caption.weight(.semibold)).lineLimit(1)
        }
    }

    @ViewBuilder private func countdown(size: CGFloat) -> some View {
        if let range = model.timerRange, model.isCounting {
            Text(timerInterval: range, countsDown: true)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else {
            Text(model.label)
                .font(.system(size: size * 0.6, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private var targetLine: some View {
        HStack(spacing: 4) {
            if let target = model.targetTime {
                Image(systemName: "clock").font(.caption2.weight(.semibold))
                Text(target, style: .time).monospacedDigit()
                Text(verbatim: "·")
            }
            Text(percent).monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                status
                countdown(size: 34)
                targetLine
                Spacer(minLength: 4)
                CountdownSegmentBar(weights: model.segmentWeights, progress: model.progress)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            upcomingList(limit: 3, compact: true)
                .frame(width: 140, alignment: .topLeading)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 6) {
            status
            countdown(size: 50)
            targetLine
            CountdownSegmentBar(weights: model.segmentWeights, progress: model.progress).padding(.top, 4)
            Divider().padding(.vertical, 6)
            // Eight rows fill the large widget; fewer left its lower third empty.
            upcomingList(limit: 8, compact: false)
            Spacer(minLength: 0)
        }
    }

    private var extraLarge: some View {
        HStack(spacing: 20) {
            ZStack {
                CountdownSegmentRing(weights: model.segmentWeights, progress: model.progress, lineWidth: 12, tint: model.phaseColor)
                VStack(spacing: 2) {
                    status
                    // The system timer takes the width it is offered and
                    // starts at its leading edge; centre it in the ring.
                    countdown(size: 34)
                        .multilineTextAlignment(.center)
                    targetLine
                }
                .padding(28)
            }
            .frame(width: 230)
            Divider()
            upcomingList(limit: 6, compact: false)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func upcomingList(limit: Int, compact: Bool) -> some View {
        let items = Array(upcoming.prefix(limit))
        return VStack(alignment: .leading, spacing: compact ? 7 : 9) {
            Text(WidgetCopy.text("comingUp", locale: model.locale))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            if compact {
                // The medium column is narrow. "13:30 午休" fits on one row;
                // "Fri 6:23 AM Clock-in" does not, and the time used to wrap
                // to "Fri / 6:23 AM". When any row is too wide, every row
                // puts its title under a one-line time instead.
                ViewThatFits(in: .horizontal) {
                    upcomingRows(items, compact: true, stacked: false)
                    upcomingRows(items, compact: true, stacked: true)
                }
            } else {
                upcomingRows(items, compact: false, stacked: false)
            }
            if items.isEmpty {
                Text(WidgetCopy.text("widgetOpenToRefresh", locale: model.locale))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func upcomingRows(_ items: [WidgetUpcomingItem], compact: Bool, stacked: Bool) -> some View {
        let locale = Locale(identifier: model.locale)
        return VStack(alignment: .leading, spacing: compact ? 7 : 9) {
            ForEach(items) { item in
                let when = Text(Self.when(item.dateMs + model.offset, now: model.entry.date, locale: locale))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                let title = Text(item.title)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 7) {
                    Image(systemName: Self.glyph(item))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CountdownStylePalette.accent)
                        .frame(width: 14)
                    if stacked {
                        VStack(alignment: .leading, spacing: 0) {
                            when
                            title.foregroundStyle(.secondary)
                        }
                    } else {
                        when.layoutPriority(1)
                        title
                    }
                    if !compact, !item.detail.isEmpty {
                        Spacer(minLength: 4)
                        Text(item.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }

    /// The clock time, with the weekday in front for anything not today, as
    /// the original widget's coming-up list does.
    static func when(_ ms: Int64, now: Date, locale: Locale) -> String {
        let date = Date(timeIntervalSince1970: Double(ms) / 1_000)
        return widgetUpcomingDateShowsWeekday(date, relativeTo: now, calendar: .current)
            ? date.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(locale))
            : date.formatted(.dateTime.hour().minute().locale(locale))
    }

    static func glyph(_ item: WidgetUpcomingItem) -> String {
        if let symbol = item.symbolName, !symbol.isEmpty { return symbol }
        return switch item.kind {
        case "shiftStart": "sunrise.fill"
        case "lunchStart": "cup.and.saucer.fill"
        case "lunchEnd": "arrow.right.circle.fill"
        case "health": "figure.walk"
        case "focus": "timer"
        case "focusBreak": "cup.and.saucer.fill"
        case "milestone": "bell.badge.fill"
        case "shiftEnd": "flag.checkered"
        default: "clock"
        }
    }
}
