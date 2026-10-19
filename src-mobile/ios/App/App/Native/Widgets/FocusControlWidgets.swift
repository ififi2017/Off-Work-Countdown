import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Intents

/// What an intent asks the app to do. The intents are compiled into the
/// extension too, so a widget or control can name them, but they run in the
/// app's process (`LiveActivityIntent`), where `WidgetIntentRouter` is set.
@MainActor
enum WidgetIntentRouter {
    static var startCountdown: (() async -> Bool)?
}

struct StartCountdownIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "widgetSuiteIntentStartCountdown"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = await WidgetIntentRouter.startCountdown?()
        return .result()
    }
}

/// Control Center labels come from the app's String Catalog. The extension
/// does not ship one, so it reads the app bundle it is embedded in.
nonisolated enum WidgetSuiteControlText {
    static var appBundle: LocalizedStringResource.BundleDescription {
        let url = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        return url.pathExtension == "app" ? .atURL(url) : .main
    }
}

// MARK: - Controls (free; starting Focus still needs Plus inside the app)

nonisolated struct CountdownControlValue: Sendable {
    var isRunning: Bool
    var endAtMs: Int64?
}

nonisolated struct CountdownControlProvider: ControlValueProvider {
    var previewValue: CountdownControlValue { CountdownControlValue(isRunning: false, endAtMs: nil) }

    func currentValue() async throws -> CountdownControlValue {
        guard let url = WidgetSuiteStore.appGroupURL(file: "widget-snapshot-v1.json"),
              let data = try? Data(contentsOf: url) else { return previewValue }
        return await MainActor.run { Self.value(from: data) ?? previewValue }
    }

    @MainActor
    private static func value(from data: Data) -> CountdownControlValue? {
        guard let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return nil }
        let nowMs = snapshot.logicalNowMs(fromRealMs: Int64(Date().timeIntervalSince1970 * 1_000))
        guard let entry = snapshot.entry(atMs: nowMs) else { return nil }
        let running = entry.phase == .working || entry.phase == .break
        let end = entry.phase == .working ? entry.countdownTargetAtMs : snapshot.shift?.segments.last?.endAtMs
        return CountdownControlValue(isRunning: running, endAtMs: running ? end.map { $0 + snapshot.clockOffsetMs } : nil)
    }
}

struct ClockInControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "\(WidgetSuiteKind.prefix).control.clockin", provider: CountdownControlProvider()) { value in
            ControlWidgetButton(action: StartCountdownIntent()) {
                if value.isRunning, let end = value.endAtMs {
                    Label {
                        Text(LocalizedStringResource("widgetSuiteControlWorking", bundle: WidgetSuiteControlText.appBundle))
                        Text(WidgetSuiteTime.date(end), style: .time)
                    } icon: {
                        Image(systemName: "briefcase.fill")
                    }
                } else {
                    Label {
                        Text(LocalizedStringResource("widgetSuiteControlClockIn", bundle: WidgetSuiteControlText.appBundle))
                    } icon: {
                        Image(systemName: "play.fill")
                    }
                }
            }
            .tint(.orange)
        }
        .displayName(LocalizedStringResource("widgetSuiteControlClockIn", bundle: WidgetSuiteControlText.appBundle))
        .description(LocalizedStringResource("widgetSuiteControlClockInDescription", bundle: WidgetSuiteControlText.appBundle))
    }
}

struct CountdownControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "\(WidgetSuiteKind.prefix).control.countdown", provider: CountdownControlProvider()) { value in
            ControlWidgetButton(action: OpenURLIntent(URL(string: "offworkcountdown://timer")!)) {
                Label {
                    Text(LocalizedStringResource("widgetSuiteControlCountdown", bundle: WidgetSuiteControlText.appBundle))
                    if let end = value.endAtMs {
                        Text(WidgetSuiteTime.date(end), style: .time)
                    }
                } icon: {
                    Image(systemName: "clock.fill")
                }
            }
            .tint(.orange)
        }
        .displayName(LocalizedStringResource("widgetSuiteControlCountdown", bundle: WidgetSuiteControlText.appBundle))
        .description(LocalizedStringResource("widgetSuiteControlCountdownDescription", bundle: WidgetSuiteControlText.appBundle))
    }
}

struct FocusControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "\(WidgetSuiteKind.prefix).control.focus") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "offworkcountdown://focus")!)) {
                Label {
                    Text(LocalizedStringResource("widgetSuiteControlFocus", bundle: WidgetSuiteControlText.appBundle))
                } icon: {
                    Image(systemName: "timer")
                }
            }
            .tint(.orange)
        }
        .displayName(LocalizedStringResource("widgetSuiteControlFocus", bundle: WidgetSuiteControlText.appBundle))
        .description(LocalizedStringResource("widgetSuiteControlFocusDescription", bundle: WidgetSuiteControlText.appBundle))
    }
}

// MARK: - Focus widget (Plus)

nonisolated struct FocusWidgetEntry: TimelineEntry {
    let date: Date
    let payload: WidgetFocusPayload?
}

nonisolated struct FocusWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusWidgetEntry { FocusWidgetEntry(date: .now, payload: nil) }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (FocusWidgetEntry) -> Void) {
        completion(FocusWidgetEntry(date: .now, payload: WidgetSuiteStore.load(WidgetFocusPayload.self, from: .focus)))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<FocusWidgetEntry>) -> Void) {
        let now = Date()
        let payload = WidgetSuiteStore.load(WidgetFocusPayload.self, from: .focus)
        let nowMs = WidgetSuiteTime.ms(now)
        var points = Set<Int64>([nowMs])
        for block in payload?.blocks ?? [] {
            if block.startMs > nowMs { points.insert(block.startMs) }
            if block.endMs > nowMs { points.insert(block.endMs) }
        }
        if let until = payload?.access.validUntilMs, until > nowMs { points.insert(until) }
        let entries = points.sorted().prefix(40).map { FocusWidgetEntry(date: WidgetSuiteTime.date($0), payload: payload) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3 * 3_600))))
    }
}

struct FocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSuiteKind.focus, provider: FocusWidgetProvider()) { entry in
            FocusWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetSuiteCopy.t("widgetSuiteFocusName", locale: WidgetSuiteCopy.systemLocale))
        .description(WidgetSuiteCopy.t("widgetSuiteFocusDescription", locale: WidgetSuiteCopy.systemLocale))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FocusWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    /// Settings › Widgets renders these views at sizes the app's own
    /// environment cannot claim; widgets leave it nil.
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? environmentFamily }
    let entry: FocusWidgetEntry

    private var locale: String { entry.payload?.locale ?? WidgetSuiteCopy.systemLocale }
    private func t(_ key: String, _ values: [String: String] = [:]) -> String {
        WidgetSuiteCopy.t(key, locale: locale, values: values)
    }

    var body: some View {
        content
            .widgetSuiteBackground()
            .widgetURL(URL(string: "offworkcountdown://focus"))
    }

    @ViewBuilder private var content: some View {
        let atMs = WidgetSuiteTime.ms(entry.date)
        if let payload = entry.payload, payload.access.isUnlocked(atMs: atMs) {
            if let current = payload.current(atMs: atMs) {
                running(current, payload: payload, atMs: atMs)
            } else if let next = payload.next(afterMs: atMs) {
                upcoming(next)
            } else {
                WidgetSuiteEmpty(title: t("widgetSuiteFocusName"), message: t("widgetSuiteFocusEmpty"),
                                 action: t("widgetSuiteFocusPlan"), symbol: "timer")
            }
        } else {
            WidgetSuitePlusLock(title: t("widgetSuiteFocusName"), promise: t("widgetSuiteFocusPromise"), locale: locale)
        }
    }

    private func running(_ block: WidgetFocusPayload.Block, payload: WidgetFocusPayload, atMs: Int64) -> some View {
        let start = WidgetSuiteTime.date(block.startMs)
        let end = WidgetSuiteTime.date(block.endMs)
        let label = block.isBreak ? t("widgetSuiteFocusBreakNow") : t("widgetSuiteFocusNow")
        let next = payload.next(afterMs: block.endMs - 1)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(label, systemImage: block.isBreak ? "cup.and.saucer.fill" : "timer")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(block.isBreak ? Color.cyan : WidgetSuitePalette.accentText)
                Spacer(minLength: 4)
                if !block.isBreak, family == .systemMedium {
                    Text(t("widgetSuiteFocusRound", ["round": WidgetSuiteFormat.count(block.round, locale: locale),
                                                     "rounds": WidgetSuiteFormat.count(block.rounds, locale: locale)]))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(block.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(timerInterval: start...end, countsDown: true)
                        .font(.system(size: family == .systemMedium ? 34 : 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                if family == .systemMedium, !block.isBreak {
                    Spacer(minLength: 4)
                    Link(destination: focusURL("addPomodoros", start: block.startMs)) {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(Color.primary.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel(t("widgetSuiteFocusAdd"))
                    Link(destination: focusURL("stop", start: block.startMs)) {
                        Image(systemName: "stop.fill")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(Color.primary.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel(t("widgetSuiteFocusStop"))
                }
            }
            .padding(.top, 6)
            Spacer(minLength: 6)
            ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(block.isBreak ? Color.cyan : WidgetSuitePalette.accent)
            if let next, family == .systemMedium {
                Text(t("widgetSuiteFocusNextAt", ["time": WidgetSuiteFormat.time(next.startMs, locale: locale), "title": next.title]))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).padding(.top, 5)
            }
        }
        .foregroundStyle(.primary)
    }

    private func upcoming(_ block: WidgetFocusPayload.Block) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(t("widgetSuiteFocusNext"), systemImage: "timer")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WidgetSuitePalette.accentText)
            Text(WidgetSuiteFormat.time(block.startMs, locale: locale))
                .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit().padding(.top, 6)
            Text(t("widgetSuiteFocusBlockDetail", [
                "minutes": WidgetSuiteFormat.count(Int((block.endMs - block.startMs) / 60_000), locale: locale),
                "title": block.title,
            ]))
            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Spacer(minLength: 6)
            Text(t("widgetSuiteFocusOpen"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetSuitePalette.accentText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func focusURL(_ action: String, start: Int64) -> URL {
        URL(string: "offworkcountdown://focus?action=\(action)&start=\(start)")!
    }
}
