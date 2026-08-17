import Foundation
import SwiftUI
import WidgetKit
import Darwin
#if OWC_SWIFT_PACKAGE
import WidgetSnapshotContract
#endif

public let offWorkCountdownWidgetKind = "com.rainif.offworkcountdown.macappstore.widget"
public let widgetSnapshotFileName = "widget-snapshot-v1.json"
public let localWidgetSnapshotDirectoryName =
    "com.rainif.offworkcountdown.macappstore.local-widget"

private enum WidgetCopy {
    static var currentLocaleIdentifier: String {
        let preferred = (Locale.preferredLanguages.first ?? "en")
            .replacingOccurrences(of: "_", with: "-")
        let lowercased = preferred.lowercased()
        if lowercased.hasPrefix("zh") {
            if lowercased.contains("-hk") {
                return "zh-HK"
            }
            if lowercased.contains("hant") || lowercased.contains("-tw") || lowercased.contains("-mo") {
                return "zh-TW"
            }
            return "zh-CN"
        }

        switch lowercased.split(separator: "-").first.map(String.init) {
        case "hi": return "hi-IN"
        case "mr": return "mr-IN"
        case let base?: return base
        case nil: return "en"
        }
    }

    static func text(_ key: String, locale: String) -> String {
        for candidate in [locale, "en"] {
            guard let url = Bundle.main.url(
                forResource: "translation",
                withExtension: "json",
                subdirectory: "locales/\(candidate)"
            ),
            let data = try? Data(contentsOf: url),
            let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let value = dictionary[key] as? String
            else {
                continue
            }
            return value
        }
        return key
    }
}

public struct SharedWidgetSnapshotLoader: Sendable {
    public let appGroupIdentifier: String?
    public let storageMode: String

    public init(appGroupIdentifier: String?, storageMode: String = "app-group") {
        self.appGroupIdentifier = appGroupIdentifier
        self.storageMode = storageMode
    }

    public func load() -> WidgetSnapshot? {
        let containerURL: URL?
        if storageMode == "local-support" {
            if let user = getpwuid(getuid()), let home = user.pointee.pw_dir {
                containerURL = URL(
                    fileURLWithPath: String(cString: home),
                    isDirectory: true
                )
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent(localWidgetSnapshotDirectoryName, isDirectory: true)
            } else {
                containerURL = nil
            }
        } else if let appGroupIdentifier, !appGroupIdentifier.isEmpty {
            containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier
            )
        } else {
            containerURL = nil
        }

        guard let containerURL else { return nil }
        let snapshotURL = containerURL.appendingPathComponent(
            widgetSnapshotFileName,
            isDirectory: false
        )
        guard let data = try? Data(contentsOf: snapshotURL) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

public struct OffWorkCountdownWidgetEntry: TimelineEntry, Sendable {
    public let date: Date
    public let snapshotEntry: WidgetTimelineEntry?
    public let locale: String

    public init(
        date: Date,
        snapshotEntry: WidgetTimelineEntry?,
        locale: String
    ) {
        self.date = date
        self.snapshotEntry = snapshotEntry
        self.locale = locale
    }
}

public struct OffWorkCountdownTimelineProvider: TimelineProvider, Sendable {
    private let loader: SharedWidgetSnapshotLoader

    public init(appGroupIdentifier: String?, storageMode: String = "app-group") {
        loader = SharedWidgetSnapshotLoader(
            appGroupIdentifier: appGroupIdentifier,
            storageMode: storageMode
        )
    }

    public func placeholder(in _: Context) -> OffWorkCountdownWidgetEntry {
        OffWorkCountdownWidgetEntry(
            date: Date(),
            snapshotEntry: nil,
            locale: WidgetCopy.currentLocaleIdentifier
        )
    }

    public func getSnapshot(
        in _: Context,
        completion: @escaping @Sendable (OffWorkCountdownWidgetEntry) -> Void
    ) {
        completion(makeTimeline(now: Date()).entries[0])
    }

    public func getTimeline(
        in _: Context,
        completion: @escaping @Sendable (Timeline<OffWorkCountdownWidgetEntry>) -> Void
    ) {
        completion(makeTimeline(now: Date()))
    }

    func makeTimeline(now: Date) -> Timeline<OffWorkCountdownWidgetEntry> {
        let nowMs = Int64(now.timeIntervalSince1970 * 1_000)
        guard let snapshot = loader.load(),
              let current = snapshot.entry(atMs: nowMs)
        else {
            return Timeline(
                entries: [
                    OffWorkCountdownWidgetEntry(
                        date: now,
                        snapshotEntry: nil,
                        locale: WidgetCopy.currentLocaleIdentifier
                    )
                ],
                policy: .never
            )
        }

        var timelineEntries = [
            OffWorkCountdownWidgetEntry(
                date: now,
                snapshotEntry: current,
                locale: snapshot.locale
            )
        ]
        timelineEntries.append(
            contentsOf: snapshot.entries
                .filter { $0.dateMs > nowMs && $0.dateMs < snapshot.expiresAtMs }
                .map {
                    OffWorkCountdownWidgetEntry(
                        date: Date(timeIntervalSince1970: Double($0.dateMs) / 1_000),
                        snapshotEntry: $0,
                        locale: snapshot.locale
                    )
                }
        )
        // 到期时主动切到保守空态，不继续用旧班次猜算。宿主在状态变化时通过
        // WidgetCenter.reloadTimelines 交付下一份快照，因此这里不轮询。
        timelineEntries.append(
            OffWorkCountdownWidgetEntry(
                date: Date(
                    timeIntervalSince1970: Double(snapshot.expiresAtMs) / 1_000
                ),
                snapshotEntry: nil,
                locale: snapshot.locale
            )
        )
        return Timeline(entries: timelineEntries, policy: .never)
    }
}

public struct OffWorkCountdownWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    public let entry: OffWorkCountdownWidgetEntry

    public init(entry: OffWorkCountdownWidgetEntry) {
        self.entry = entry
    }

    public var body: some View {
        widgetBackground {
            contentInset {
                Group {
                    if let snapshotEntry = entry.snapshotEntry {
                        if family == .systemMedium {
                            mediumContent(snapshotEntry)
                        } else {
                            smallContent(snapshotEntry)
                        }
                    } else {
                        emptyContent
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .environment(\.locale, Locale(identifier: entry.locale))
        .widgetURL(URL(string: "offworkcountdown://open"))
    }

    /// macOS 14 起 WidgetKit 自己就会给内容加一圈默认 content margins（实测
    /// 16pt），`containerBackground` 只保证**背景**铺满整块，内容仍然被缩进。
    /// 这里再叠一层自己的 padding 就是双重内边距：medium 实际缩进 34pt、small
    /// 31pt，small 的可用宽度被压到 ~96pt，倒计时会被截断成 `0:0…`。
    ///
    /// 不用 `contentMarginsDisabled()` 关掉系统那层：它是 macOS 14+ API，而
    /// `WidgetConfigurationBuilder` 没有 `buildLimitedAvailability`，`if
    /// #available` 的两个分支类型对不上（实测编译报 "branches have mismatching
    /// types"）。为它把 Widget 的部署目标抬到 14 又与决策 5「最低系统版本统一为
    /// macOS 13」冲突。ViewBuilder 有 `buildLimitedAvailability`，所以按版本决定
    /// 要不要自己加内边距，把分叉留在 View 层。
    @ViewBuilder
    private func contentInset<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(macOS 14.0, *) {
            content()
        } else {
            content().padding(family == .systemMedium ? 18 : 15)
        }
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(colorScheme == .dark ? 0.24 : 0.14))
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: compact ? 12 : 13, weight: .semibold))
                    .foregroundStyle(accentColor)
            }
            .frame(width: compact ? 25 : 27, height: compact ? 25 : 27)

            Text(WidgetCopy.text("offWorkCountdown", locale: entry.locale))
                .font(.caption.weight(.bold))
                .lineLimit(compact ? 2 : 1)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 0)
        }
    }

    private func statusBadge(_ snapshotEntry: WidgetTimelineEntry) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(phaseColor(snapshotEntry.phase))
                .frame(width: 6, height: 6)
            Text(WidgetCopy.text(snapshotEntry.labelKey, locale: entry.locale))
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.primary.opacity(0.82))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(phaseColor(snapshotEntry.phase).opacity(0.12), in: Capsule())
    }

    private func smallContent(_ snapshotEntry: WidgetTimelineEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(compact: true)
            Spacer(minLength: 7)
            statusBadge(snapshotEntry)
            Spacer(minLength: 6)
            countdown(for: snapshotEntry, size: 33)
            Spacer(minLength: 7)
            progressBar(snapshotEntry.progressAtDate)
            Spacer(minLength: 5)
            HStack(spacing: 6) {
                Text("\(roundedProgress(snapshotEntry.progressAtDate))%")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(accentColor)
                Spacer(minLength: 4)
                boundaryTime(snapshotEntry)
            }
        }
    }

    private func mediumContent(_ snapshotEntry: WidgetTimelineEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(compact: false)
            Spacer(minLength: 9)
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    statusBadge(snapshotEntry)
                    countdown(for: snapshotEntry, size: 38)
                    boundaryTime(snapshotEntry)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                progressRing(snapshotEntry.progressAtDate)
            }
        }
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(compact: family != .systemMedium)
            Spacer(minLength: 8)
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accentColor.opacity(colorScheme == .dark ? 0.22 : 0.12))
                    Image(systemName: "sun.horizon.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(WidgetCopy.text("countdownNotStarted", locale: entry.locale))
                        .font(.callout.weight(.bold))
                        .lineLimit(2)
                    Text(WidgetCopy.text("widgetOpenToRefresh", locale: entry.locale))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func countdown(
        for snapshotEntry: WidgetTimelineEntry,
        size: CGFloat
    ) -> some View {
        if let targetAtMs = snapshotEntry.countdownTargetAtMs {
            Text(
                Date(timeIntervalSince1970: Double(targetAtMs) / 1_000),
                style: .timer
            )
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: true))
            .lineLimit(1)
            .minimumScaleFactor(0.62)
        } else {
            // 收缩规则要和上面的动态分支一致：少了 lineLimit / minimumScaleFactor
            // 时，宽度不够不会缩字号而是直接截断，small 上就是截图里那个 `0:0…`。
            Text(verbatim: "0:00:00")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
    }

    private func progressBar(_ progress: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.10))
                Capsule()
                    .fill(accentGradient)
                    .frame(width: geometry.size.width * progressFraction(progress))
            }
        }
        .frame(height: 7)
    }

    private func progressRing(_ progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.08), lineWidth: 8)
            Circle()
                .trim(from: 0, to: progressFraction(progress))
                .stroke(
                    accentGradient,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(roundedProgress(progress))%")
                .font(.system(.callout, design: .rounded, weight: .bold))
                .monospacedDigit()
        }
        .frame(width: 76, height: 76)
        .padding(.trailing, 3)
    }

    @ViewBuilder
    private func boundaryTime(_ snapshotEntry: WidgetTimelineEntry) -> some View {
        if let nextBoundaryAtMs = snapshotEntry.nextBoundaryAtMs {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 9, weight: .semibold))
                Text(
                    Date(timeIntervalSince1970: Double(nextBoundaryAtMs) / 1_000),
                    style: .time
                )
                .monospacedDigit()
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        }
    }

    private var accentColor: Color {
        Color(red: 1.0, green: 0.38, blue: 0.08)
    }

    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accentColor, Color(red: 1.0, green: 0.68, blue: 0.16)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func phaseColor(_ phase: WidgetTimelinePhase) -> Color {
        switch phase {
        case .before: return .indigo
        case .working: return accentColor
        case .break: return .cyan
        case .done: return .green
        case .idle: return .secondary
        }
    }

    private func progressFraction(_ progress: Double) -> Double {
        min(1, max(0, progress / 100))
    }

    private func roundedProgress(_ progress: Double) -> Int {
        Int(min(100, max(0, progress)).rounded())
    }

    @ViewBuilder
    private func widgetBackground<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(macOS 14.0, *) {
            content()
                .containerBackground(for: .widget) {
                    backgroundLayer
                }
        } else {
            content().background(backgroundLayer)
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.10, green: 0.10, blue: 0.12),
                        Color(red: 0.14, green: 0.12, blue: 0.11),
                    ]
                    : [
                        Color(red: 1.0, green: 0.99, blue: 0.98),
                        Color(red: 0.98, green: 0.96, blue: 0.93),
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(accentColor.opacity(colorScheme == .dark ? 0.10 : 0.08))
                .frame(width: 180, height: 180)
                .blur(radius: 38)
                .offset(x: 95, y: -80)
        }
    }
}

public struct OffWorkCountdownWidget: Widget {
    private let appGroupIdentifier: String?
    private let storageMode: String

    public init() {
        appGroupIdentifier = Bundle.main.object(
            forInfoDictionaryKey: "OWCAppGroupIdentifier"
        ) as? String
        storageMode = Bundle.main.object(
            forInfoDictionaryKey: "OWCWidgetStorageMode"
        ) as? String ?? "app-group"
    }

    public init(appGroupIdentifier: String?, storageMode: String = "app-group") {
        self.appGroupIdentifier = appGroupIdentifier
        self.storageMode = storageMode
    }

    public var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: offWorkCountdownWidgetKind,
            provider: OffWorkCountdownTimelineProvider(
                appGroupIdentifier: appGroupIdentifier,
                storageMode: storageMode
            )
        ) { entry in
            OffWorkCountdownWidgetView(entry: entry)
        }
        .configurationDisplayName(
            Text(
                verbatim: WidgetCopy.text(
                    "offWorkCountdown",
                    locale: WidgetCopy.currentLocaleIdentifier
                )
            )
        )
        .description(
            Text(
                verbatim: WidgetCopy.text(
                    "widgetDescription",
                    locale: WidgetCopy.currentLocaleIdentifier
                )
            )
        )
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
