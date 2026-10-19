import SwiftUI
import UIKit
import WidgetKit

/// Copy for the widget suite. The extension reads the bundled
/// `locales/<lang>/translation.json` (as `WidgetCopy` does for the countdown
/// widget); the app, which does not ship those files, answers through
/// `appLookup` from its String Catalog. Keys used here live in both, with the
/// same wording (`npm run check:ios-strings` compares them).
nonisolated enum WidgetSuiteCopy {
    nonisolated(unsafe) static var appLookup: ((String, String) -> String?)?

    static func t(_ key: String, locale: String, values: [String: String] = [:]) -> String {
        let raw = appLookup?(key, locale) ?? table.value(forKey: key, locale: locale)
            ?? table.value(forKey: key, locale: "en") ?? key
        return values.reduce(raw) { $0.replacingOccurrences(of: "{{\($1.key)}}", with: $1.value) }
    }

    private static let table = Table()

    private final class Table: @unchecked Sendable {
        private let lock = NSLock()
        private var loaded: [String: [String: String]] = [:]

        func value(forKey key: String, locale: String) -> String? {
            lock.lock()
            defer { lock.unlock() }
            if let cached = loaded[locale] { return cached[key] }
            let table = Self.read(locale: locale)
            loaded[locale] = table
            return table[key]
        }

        private static func read(locale: String) -> [String: String] {
            for candidate in [locale, locale.components(separatedBy: "-").first ?? locale] {
                guard let url = Bundle.main.url(forResource: "translation", withExtension: "json",
                                                subdirectory: "locales/\(candidate)"),
                      let data = try? Data(contentsOf: url),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }
                return object.compactMapValues { $0 as? String }
            }
            return [:]
        }
    }

    /// The language the system gallery shows before any payload exists.
    static var systemLocale: String {
        let preferred = (Locale.preferredLanguages.first ?? "en").replacingOccurrences(of: "_", with: "-")
        let lower = preferred.lowercased()
        if lower.hasPrefix("zh") {
            if lower.contains("-hk") { return "zh-HK" }
            if lower.contains("hant") || lower.contains("-tw") || lower.contains("-mo") { return "zh-TW" }
            return "zh-CN"
        }
        switch lower.split(separator: "-").first.map(String.init) {
        case "hi": return "hi-IN"
        case "mr": return "mr-IN"
        case let base?: return base
        case nil: return "en"
        }
    }
}

/// The suite's colours: the shared orange for fills, a darker orange for
/// small text so it keeps 4.5:1 on white, and the phase colours the
/// countdown widget already uses.
enum WidgetSuitePalette {
    static let accent = Color(red: 1.0, green: 0.38, blue: 0.08)
    static let accentSoft = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.38, blue: 0.08, alpha: 0.38)
            : UIColor(red: 0.99, green: 0.73, blue: 0.55, alpha: 1)
    })
    static let accentText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.62, blue: 0.38, alpha: 1)
            : UIColor(red: 0.76, green: 0.25, blue: 0.05, alpha: 1)
    })
    static let track = Color.primary.opacity(0.10)
    static let restFill = Color.primary.opacity(0.05)
    static let breakColor = Color.cyan
    static let holiday = Color.green

    static func color(hex: String?) -> Color? {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let value = Int(hex.dropFirst(), radix: 16) else { return nil }
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }
}

/// Title row: what the widget is about, and an optional trailing note.
struct WidgetSuiteHeader: View {
    let title: String
    var trailing: String?
    var symbol: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetSuitePalette.accentText)
                    .widgetAccentable()
            }
            Text(title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }
}

/// What a Plus widget shows without Plus: no data at all, a plain promise of
/// what it does, and the way to learn more. Never a countdown or a number
/// that could be mistaken for the user's own.
struct WidgetSuitePlusLock: View {
    let title: String
    let promise: String
    let locale: String
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(verbatim: "Plus")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(WidgetSuitePalette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(WidgetSuitePalette.accentText)
            }
            Text(promise)
                .font(compact ? .caption : .subheadline.weight(.semibold))
                .lineLimit(compact ? 2 : 3)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if !compact {
                Text(WidgetSuiteCopy.t("widgetSuiteLearnPlus", locale: locale))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetSuitePalette.accentText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "offworkcountdown://plus"))
    }
}

/// A plain empty state: one sentence of what to do, and the screen to do it on.
struct WidgetSuiteEmpty: View {
    let title: String
    let message: String
    var action: String?
    var symbol = "calendar"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            if let action {
                Text(action)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetSuitePalette.accentText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A horizontal bar split into segments, each filled to its own share.
struct WidgetSuiteSegmentBar: View {
    let segments: [(weight: Double, fill: Double)]
    var height: CGFloat = 6
    var gap: CGFloat = 3
    var tint: Color = WidgetSuitePalette.accent

    var body: some View {
        GeometryReader { proxy in
            let total = max(0.000_1, segments.reduce(0) { $0 + $1.weight })
            let usable = proxy.size.width - gap * CGFloat(max(0, segments.count - 1))
            HStack(spacing: gap) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    let width = max(height, usable * segment.weight / total)
                    ZStack(alignment: .leading) {
                        Capsule().fill(WidgetSuitePalette.track)
                        Capsule().fill(tint)
                            .frame(width: width * min(1, max(0, segment.fill)))
                            .opacity(segment.fill > 0 ? 1 : 0)
                    }
                    .frame(width: width)
                }
            }
        }
        .frame(height: height)
    }
}

/// A ring drawn as arcs, so lunch can be a gap. `segments` are shares of the
/// circle; `progress` is how far the fill has run across all of them.
struct WidgetSuiteSegmentRing: View {
    let segments: [Double]
    let progress: Double
    var lineWidth: CGFloat = 8
    var tint: Color = WidgetSuitePalette.accent
    var track: Color = WidgetSuitePalette.track

    var body: some View {
        GeometryReader { proxy in
            let total = max(0.000_1, segments.reduce(0, +))
            let gap = segments.count > 1 ? WidgetSuiteSegmentRing.gap(lineWidth: lineWidth, diameter: min(proxy.size.width, proxy.size.height)) : 0
            ZStack {
                ForEach(Array(arcs(total: total, gap: gap).enumerated()), id: \.offset) { _, arc in
                    Circle()
                        .trim(from: arc.start, to: arc.end)
                        .stroke(track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    if arc.fillEnd > arc.start {
                        Circle()
                            .trim(from: arc.start, to: arc.fillEnd)
                            .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                            .widgetAccentable()
                    }
                }
            }
            .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }

    /// The gap between segments as a share of the circumference. Round caps
    /// reach half a line width into it from each side, so the gap is a line
    /// width plus the clear space that should stay visible between segments,
    /// whatever the ring's size.
    static func gap(lineWidth: CGFloat, diameter: CGFloat) -> Double {
        let circumference = max(1, Double(diameter) * .pi)
        return min(0.2, Double(lineWidth + max(2.5, lineWidth * 0.6)) / circumference)
    }

    private func arcs(total: Double, gap: Double) -> [(start: Double, end: Double, fillEnd: Double)] {
        var result: [(Double, Double, Double)] = []
        var cursor = 0.0
        var remaining = min(1, max(0, progress)) * total
        for segment in segments {
            let share = segment / total
            let start = cursor + gap / 2
            let end = max(start, cursor + share - gap / 2)
            let filled = min(segment, remaining)
            remaining -= filled
            let fillEnd = start + (end - start) * (segment > 0 ? filled / segment : 0)
            result.append((start, end, fillEnd))
            cursor += share
        }
        return result
    }
}

extension View {
    /// Home Screen widgets draw their own plate; accessories stay clear.
    func widgetSuiteBackground() -> some View {
        containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }

    /// The extension bundle has no localizations of its own, so system-formatted
    /// text (relative dates, timers, digits) would fall back to English. Follow
    /// the language the app published instead.
    func widgetSuiteLocale(_ identifier: String?) -> some View {
        environment(\.locale, Locale(identifier: identifier ?? WidgetSuiteCopy.systemLocale))
    }
}

nonisolated enum WidgetSuiteFormat {
    static func locale(_ identifier: String) -> Locale { Locale(identifier: identifier) }

    static func time(_ ms: Int64, locale: String) -> String {
        WidgetSuiteTime.date(ms).formatted(.dateTime.hour().minute().locale(Self.locale(locale)))
    }

    static func weekday(_ ms: Int64, locale: String) -> String {
        WidgetSuiteTime.date(ms).formatted(.dateTime.weekday(.abbreviated).locale(Self.locale(locale)))
    }

    static func weekdayNarrow(_ ms: Int64, locale: String) -> String {
        WidgetSuiteTime.date(ms).formatted(.dateTime.weekday(.narrow).locale(Self.locale(locale)))
    }

    static func dayOfMonth(_ ms: Int64, locale: String) -> String {
        WidgetSuiteTime.date(ms).formatted(.dateTime.day().locale(Self.locale(locale)))
    }

    static func monthDay(_ ms: Int64, locale: String) -> String {
        WidgetSuiteTime.date(ms).formatted(.dateTime.month(.abbreviated).day().locale(Self.locale(locale)))
    }

    static func decimal(_ value: Double, locale: String, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...digits)).locale(Self.locale(locale)))
    }

    static func hours(_ ms: Int64, locale: String) -> String {
        let value = Double(ms) / 3_600_000
        let digits = value >= 100 ? 0 : 1
        return value.formatted(.number.precision(.fractionLength(0...digits)).grouping(.automatic).locale(Self.locale(locale)))
    }

    static func percent(_ value: Double, locale: String) -> String {
        value.formatted(.percent.precision(.fractionLength(0)).locale(Self.locale(locale)))
    }

    static func count(_ value: Int, locale: String) -> String {
        value.formatted(.number.locale(Self.locale(locale)))
    }
}
