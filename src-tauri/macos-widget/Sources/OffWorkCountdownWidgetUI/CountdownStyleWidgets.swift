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

    var progress: Double { min(1, max(0, (snapshotEntry?.progressAtDate ?? 0) / 100)) }

    var segmentWeights: [Double] {
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

/// Hours and minutes, drawn by the system so it keeps counting while the
/// extension sleeps. Before iOS 18 / macOS 15 it falls back to the seconds timer.
struct CountdownHoursMinutes: View {
    let range: ClosedRange<Date>

    var body: some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            Text(.currentDate, format: .timer(countingDownIn: range.lowerBound..<range.upperBound,
                                              showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(60)))
        } else {
            Text(timerInterval: range, countsDown: true)
        }
    }
}

/// A ring cut into the shift's work segments; lunch is the gap.
struct CountdownSegmentRing: View {
    let weights: [Double]
    let progress: Double
    var lineWidth: CGFloat = 8
    var tint: Color = CountdownStylePalette.accent

    var body: some View {
        let total = max(0.000_1, weights.reduce(0, +))
        let gap = weights.count > 1 ? 0.025 : 0
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
        .padding(lineWidth / 2)
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
                        Capsule().fill(CountdownStylePalette.accent).frame(width: width * fills[index])
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
            containerBackground(for: .widget) { Color.clear.background(.background) }
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
        let nowMs = Int64(model.entry.date.timeIntervalSince1970 * 1_000) - model.offset
        VStack(alignment: .leading, spacing: 6) {
            Label(model.label, systemImage: "calendar.day.timeline.left")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if segments.isEmpty {
                Spacer(minLength: 0)
                Text(WidgetCopy.text("countdownNotStarted", locale: model.locale))
                    .font(.footnote.weight(.semibold))
                Spacer(minLength: 0)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 3) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                            let total = Double(max(1, segment.endAtMs - segment.startAtMs))
                            let done = min(1, max(0, Double(nowMs - segment.startAtMs) / total))
                            GeometryReader { proxy in
                                ZStack(alignment: .top) {
                                    Capsule().fill(CountdownStylePalette.track)
                                    Capsule().fill(CountdownStylePalette.accent)
                                        .frame(height: proxy.size.height * done)
                                }
                            }
                            .frame(width: 6)
                            .frame(maxHeight: .infinity)
                            .layoutPriority(total)
                            if index < segments.count - 1 { Spacer().frame(height: 6) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows(segments: segments, nowMs: nowMs).enumerated()), id: \.offset) { _, row in
                            Text(row.text)
                                .font(.caption2.weight(row.isNow ? .bold : .regular).monospacedDigit())
                                .foregroundStyle(row.isNow ? .primary : .secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .countdownStyleBackground()
        .widgetURL(URL(string: "offworkcountdown://timer"))
    }

    private struct Row { let text: String; let isNow: Bool }

    private func rows(segments: [WidgetShiftSegment], nowMs: Int64) -> [Row] {
        let locale = Locale(identifier: model.locale)
        func time(_ ms: Int64) -> String {
            Date(timeIntervalSince1970: Double(ms + model.offset) / 1_000).formatted(.dateTime.hour().minute().locale(locale))
        }
        var result: [Row] = []
        for (index, segment) in segments.enumerated() {
            result.append(Row(text: time(segment.startAtMs), isNow: false))
            if nowMs >= segment.startAtMs, nowMs < segment.endAtMs {
                result.append(Row(text: "▸ \(time(nowMs))", isNow: true))
            }
            if index == segments.count - 1 { result.append(Row(text: time(segment.endAtMs), isNow: false)) }
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
            countdown(size: 44)
            targetLine
            CountdownSegmentBar(weights: model.segmentWeights, progress: model.progress).padding(.top, 4)
            Divider().padding(.vertical, 6)
            upcomingList(limit: 5, compact: false)
            Spacer(minLength: 0)
        }
    }

    private var extraLarge: some View {
        HStack(spacing: 20) {
            ZStack {
                CountdownSegmentRing(weights: model.segmentWeights, progress: model.progress, lineWidth: 12, tint: model.phaseColor)
                VStack(spacing: 2) {
                    status
                    countdown(size: 34)
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
        let locale = Locale(identifier: model.locale)
        return VStack(alignment: .leading, spacing: compact ? 7 : 9) {
            Text(WidgetCopy.text("comingUp", locale: model.locale))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(items) { item in
                HStack(spacing: 7) {
                    Image(systemName: Self.glyph(item))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CountdownStylePalette.accent)
                        .frame(width: 14)
                    Text(Date(timeIntervalSince1970: Double(item.dateMs + model.offset) / 1_000)
                        .formatted(.dateTime.hour().minute().locale(locale)))
                        .font(.caption.weight(.semibold).monospacedDigit())
                    Text(item.title)
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if !compact, !item.detail.isEmpty {
                        Spacer(minLength: 4)
                        Text(item.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            if items.isEmpty {
                Text(WidgetCopy.text("widgetOpenToRefresh", locale: model.locale))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
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
