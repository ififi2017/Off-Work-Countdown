import ActivityKit
import AppIntents
import SwiftUI
import UIKit
import WidgetKit

@main
struct OffWorkWidgets: WidgetBundle {
    var body: some Widget {
        OffWorkCountdownWidget()
        OffWorkLiveActivityWidget()
    }
}

struct OffWorkLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OffWorkActivityAttributes.self) { context in
            LockScreenActivityView(context: context)
                .activityBackgroundTint(Color.white.opacity(0.12))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(activityDestination(context))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading, priority: 1) {
                    ActivityIslandHeading(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityIslandEndTime(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityIslandBody(context: context)
                }
            } compactLeading: {
                ActivityCompactGlyph(context: context, size: 13, brandSize: 20)
            } compactTrailing: {
                ActivityCompactCountdown(context: context)
            } minimal: {
                // The one slot another app's activity can squeeze this into.
                // A single glyph has to say which of ours it is.
                ActivityCompactGlyph(context: context, size: 13, brandSize: 18)
            }
            .widgetURL(activityDestination(context))
            .keylineTint(activityTint(context, at: .now))
        }
    }
}

// MARK: - Dynamic Island

private struct ActivityIslandHeading: View {
    let context: ActivityViewContext<OffWorkActivityAttributes>

    var body: some View {
        TimelineView(activitySchedule(context)) { timeline in
            HStack(spacing: 8) {
                // The bare mark, not the plated app icon: the Dynamic Island
                // is already a container, and a second rounded plate inside it
                // reads as a sticker. Focus and break activities show their own
                // glyph instead — two activities wearing the same mark are two
                // the user cannot tell apart.
                if let symbol = activitySymbol(context, at: timeline.date) {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(activityTint(context, at: timeline.date))
                        .frame(width: 25, height: 25)
                } else {
                    AlwaysDarkBrandMark(size: 25)
                }

                Text(activityPhaseLabel(context, at: timeline.date))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: 150, alignment: .leading)
            .padding(.leading, 8)
        }
    }
}

private struct ActivityIslandEndTime: View {
    let context: ActivityViewContext<OffWorkActivityAttributes>

    var body: some View {
        TimelineView(activitySchedule(context)) { timeline in
            // The capsule rounds the corners of the expanded area, so the
            // trailing content is pulled in far enough that its last glyph is
            // not clipped by the curve.
            Text(activityEnd(context, at: timeline.date), style: .time)
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
                .environment(\.locale, activityLocale(context))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.trailing, 8)
        }
    }
}

private struct ActivityIslandBody: View {
    let context: ActivityViewContext<OffWorkActivityAttributes>

    var body: some View {
        TimelineView(activitySchedule(context)) { timeline in
            VStack(alignment: .leading, spacing: 4) {
                // A task name needs the width below the camera, not the narrow
                // leading slot and an unreadable shrink.
                if let title = activityTaskTitle(context, at: timeline.date) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ActivityCountdownPanel(
                    context: context,
                    now: timeline.date,
                    size: activityIsFocus(context) ? 48 : 40
                )
                if let support = activitySupportLine(context, at: timeline.date) {
                    Text(support)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 2)
        }
    }
}

// MARK: - Lock Screen

private struct LockScreenActivityView: View {
    let context: ActivityViewContext<OffWorkActivityAttributes>

    var body: some View {
        TimelineView(activitySchedule(context)) { timeline in
            let leg = activityLeg(context, at: timeline.date)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    // The lock-screen card has enough room for the full icon and
                    // benefits from its solid plate against the glass material.
                    // Dynamic Island remains on the lighter transparent mark.
                    ActivityAppIcon(size: 24)
                    Text(activityTitle(context, at: timeline.date))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(0.25)
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    // A block nobody has started has no end worth printing —
                    // its hero already shows the hour it begins.
                    if leg?.isPreview != true, !activityComplete(context, at: timeline.date) {
                        Text(activityEnd(context, at: timeline.date), style: .time)
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.7))
                            .environment(\.locale, activityLocale(context))
                    }
                }
                HStack(spacing: 10) {
                    // The button has no text baseline of its own, so only the
                    // countdown and its caption share one.
                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        activityCountdownText(context, now: timeline.date, size: 44)
                        if let caption = activityCaption(context, at: timeline.date) {
                            Text(caption)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    Spacer(minLength: 8)
                    if !activityComplete(context, at: timeline.date) {
                        AddPomodoroButton(state: context.state)
                    }
                }
                .padding(.top, 12)
                if leg?.isPreview != true {
                    activityProgress(context, at: timeline.date)
                        .padding(.top, 14)
                }
                // Only one activity may be live, so a focus block ends the work
                // countdown. These two lines put the shift back: the block above,
                // the shift below — the canvas's first two scales in one card.
                let support = activitySupportLine(context, at: timeline.date)
                if support != nil || context.state.shiftEndAtMs != nil {
                    HStack(spacing: 8) {
                        if let support {
                            Text(support).lineLimit(1).minimumScaleFactor(0.85)
                        }
                        Spacer(minLength: 4)
                        if let endAtMs = context.state.shiftEndAtMs, let label = context.state.shiftEndLabel {
                            HStack(spacing: 4) {
                                Text(label)
                                Text(Date(timeIntervalSince1970: Double(endAtMs) / 1_000), style: .time)
                                    .environment(\.locale, activityLocale(context))
                            }
                            .lineLimit(1)
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
    }
}

/// One more block for the running task, without unlocking the phone.
///
/// The trailing edge of the hero row is where the system's own timer puts its
/// controls, so this is the ordinary place for it rather than an invention.
/// It disappears entirely on a break or a work countdown, and greys out when
/// the rest of the shift already belongs to other tasks — a control that can
/// be tapped and does nothing is worse than one that says it cannot act.
private struct AddPomodoroButton: View {
    let state: OffWorkActivityAttributes.ContentState

    var body: some View {
        if let label = state.addPomodoroLabel {
            Button(intent: AddFocusPomodoroIntent()) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .background(.white.opacity(state.addPomodoroEnabled ? 0.18 : 0.08), in: .circle)
            .foregroundStyle(.white.opacity(state.addPomodoroEnabled ? 0.95 : 0.35))
            .disabled(!state.addPomodoroEnabled)
            .accessibilityLabel(label)
            // `Text(_:style:.timer)` beside it reports an ideal width far
            // wider than the digits it draws, and would otherwise squeeze the
            // button out of the row entirely.
            .fixedSize()
            .layoutPriority(1)
        }
    }
}

// MARK: - Countdown surfaces

private struct ActivityCountdownPanel: View {
    let context: ActivityViewContext<OffWorkActivityAttributes>
    let now: Date
    let size: CGFloat

    var body: some View {
        VStack(spacing: activityIsFocus(context) ? 6 : 14) {
            HStack {
                if activityIsFocus(context), !activityComplete(context, at: now),
                   activityLeg(context, at: now)?.isPreview != true {
                    // The interval timer fills the available width without
                    // the .timer style's oversized ideal width shrinking it.
                    let end = activityEnd(context, at: now)
                    Text(timerInterval: now...max(now, end), countsDown: true)
                        .font(.system(size: size, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .environment(\.locale, activityLocale(context))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    activityCountdownText(context, now: now, size: size)
                    Spacer()
                }
                if activityIsFocus(context) {
                    if !activityComplete(context, at: now) {
                        AddPomodoroButton(state: context.state)
                    }
                } else {
                    Text(String(format: "%.1f%%", activityProgressValue(context, at: now)))
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(activityOrange)
                }
            }
            if activityLeg(context, at: now)?.isPreview != true {
                activityProgress(context, at: now)
            }
        }
    }
}

private struct ActivityCompactGlyph: View {
    let context: ActivityViewContext<OffWorkActivityAttributes>
    let size: CGFloat
    let brandSize: CGFloat

    var body: some View {
        TimelineView(activitySchedule(context)) { timeline in
            if let symbol = activitySymbol(context, at: timeline.date) {
                Image(systemName: symbol)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(activityTint(context, at: timeline.date))
            } else {
                AlwaysDarkBrandMark(size: brandSize)
            }
        }
    }
}

private struct ActivityCompactCountdown: View {
    let context: ActivityViewContext<OffWorkActivityAttributes>

    var body: some View {
        TimelineView(activitySchedule(context)) { timeline in
            if activityComplete(context, at: timeline.date) {
                // completedCaption is a full, localized sentence (6 characters
                // in zh-CN, 36 in fr) meant for the lock screen and expanded
                // panel where there's room for it. The compact slot has none:
                // `.fixedSize` reports the sentence's true, un-scaled width as
                // "ideal," the region doesn't fall back to minimumScaleFactor
                // the way normal layout would, and the trailing-anchored text
                // just clips off its own leading character instead. A
                // checkmark needs no localization and can't overflow.
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            } else if let leg = activityLeg(context, at: timeline.date), leg.isPreview {
                // Nothing is running, so nothing may tick. The hour it starts
                // is both shorter and the only true thing to show.
                Text(Date(timeIntervalSince1970: Double(leg.startAtMs) / 1_000), style: .time)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .environment(\.locale, activityLocale(context))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                // `Text(_:style:.timer)` is required here, not a convenience:
                // Live Activities have no timeline of their own — the widget
                // extension is suspended almost all the time, and only a real
                // `Activity.update()` push re-renders it. `.timer`-style Text
                // is one of the few primitives iOS interpolates frame-by-frame
                // outside the extension process, so it's the only thing that
                // visibly ticks without one (confirmed the hard way: an
                // earlier attempt to render this from a plain TimelineView
                // string looked right for one frame, then froze).
                //
                // Its cost is a long-standing, still-unfixed ActivityKit bug
                // (https://developer.apple.com/forums/thread/723316): inside
                // Dynamic Island's compact regions it reports a broken,
                // oversized ideal width, so `.fixedSize` blows the island out
                // to its expanded shape with the countdown rendered blank.
                // Hence the explicit width below.
                Text(activityEnd(context, at: timeline.date), style: .timer)
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .environment(\.locale, activityLocale(context))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    // Leading, not trailing: the phantom width `.timer`
                    // reserves sits on the text's own trailing edge, so
                    // anchoring the glyphs left lets the frame clip that tail
                    // instead of printing it as a gap before the capsule.
                    .frame(width: compactTimerWidth(context, now: timeline.date), alignment: .leading)
            }
        }
    }
}

/// Width for the compact island's `.timer` text, sized to the digits the
/// system is actually showing right now.
///
/// A single fixed width cannot work: `Text(_:style:.timer)` must be given a
/// bounded width (unbounded, it reports a broken ideal width and blows the
/// island out), but the format it renders shrinks from `H:MM:SS` to `MM:SS`
/// to `M:SS` as the shift runs down, and any box wide enough for the longest
/// one leaves dead space inside the shorter ones. `minimumScaleFactor` on the
/// text absorbs the rounding, so these only have to be close.
private func compactTimerWidth(
    _ context: ActivityViewContext<OffWorkActivityAttributes>,
    now: Date
) -> CGFloat {
    let endMs = activityLeg(context, at: now)?.endAtMs ?? context.state.endAtMs
    let remaining = Double(endMs) / 1_000 - now.timeIntervalSince1970
    // ~9pt per glyph at 14pt bold monospaced digits.
    if remaining >= 36_000 { return 74 }  // HH:MM:SS
    if remaining >= 3_600 { return 65 }   // H:MM:SS
    if remaining >= 600 { return 47 }     // MM:SS
    return 38                             // M:SS
}

private struct ActivityAppIcon: View {
    var size: CGFloat

    var body: some View {
        Image("BrandIcon")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Dynamic Island and the lock-screen Live Activity are always-dark
/// surfaces. `BrandMark` only swaps the hands by appearance; the light
/// catalog's plum hands disappear on the black capsule, so pin the dark
/// variant here instead of inheriting the phone's color scheme.
private struct AlwaysDarkBrandMark: View {
    var size: CGFloat

    var body: some View {
        Image(uiImage: Self.image)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private static let image: UIImage = {
        let traits = UITraitCollection(userInterfaceStyle: .dark)
        let named = UIImage(named: "BrandMark")
        return named?.imageAsset?.image(with: traits) ?? named ?? UIImage()
    }()
}

// MARK: - Update scheduling

/// When the card asks the system for a new frame.
///
/// Almost everything inside a leg draws itself: `Text(_:style:.timer)` and
/// `ProgressView(timerInterval:)` are animated by the render server without
/// waking this extension at all. What cannot draw itself is the hand-over —
/// the instant a block becomes its break, and the break becomes the block
/// queued behind it — because that swaps the whole card.
///
/// Asking per second gets that instant budgeted away: on a locked screen the
/// extension can go many minutes without a render, and the card sat on a
/// finished block while its break was already running underneath. So a chain
/// payload asks for nothing but its own boundaries, which is a request small
/// enough for the system to grant. The work countdown keeps the per-second
/// tick, because it draws its own progress bar and completion caption.
private struct ActivityUpdateSchedule: TimelineSchedule {
    var boundaries: [Date]
    var interval: TimeInterval?

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var pending = boundaries.filter { $0 > startDate }.sorted()
        var cursor = startDate
        var emittedStart = false
        // Always-On Display asks for about a frame a minute. The boundaries
        // still land exactly; only the filler ticks between them coarsen.
        let interval = interval.map { mode == .lowFrequency ? max($0, 60) : $0 }
        return AnyIterator {
            if !emittedStart {
                emittedStart = true
                return startDate
            }
            guard let interval else {
                return pending.isEmpty ? nil : pending.removeFirst()
            }
            let tick = cursor.addingTimeInterval(interval)
            if let next = pending.first, next <= tick {
                pending.removeFirst()
                cursor = next
                return next
            }
            cursor = tick
            return tick
        }
    }
}

private func activitySchedule(
    _ context: ActivityViewContext<OffWorkActivityAttributes>
) -> ActivityUpdateSchedule {
    let legs = context.state.legs ?? []
    let boundaries = legs.isEmpty
        ? [Date(timeIntervalSince1970: Double(context.state.endAtMs) / 1_000)]
        : legs.map { Date(timeIntervalSince1970: Double($0.endAtMs) / 1_000) }
    return .init(boundaries: boundaries, interval: legs.isEmpty ? 1 : nil)
}

// MARK: - Chain readers

private let activityOrange = Color(red: 0.976, green: 0.451, blue: 0.086)

/// The leg the clock is in. `nil` past the end of the chain, and on payloads
/// written before the chain existed — both fall back to the single countdown
/// those carry.
private func activityLeg(
    _ context: ActivityViewContext<OffWorkActivityAttributes>,
    at date: Date
) -> OffWorkActivityAttributes.ContentState.Leg? {
    context.state.leg(atMs: Int64(date.timeIntervalSince1970 * 1_000))
}

/// The instant this panel is counting to right now, which moves from the
/// running block to its break to the block queued behind them.
private func activityEnd(
    _ context: ActivityViewContext<OffWorkActivityAttributes>,
    at date: Date
) -> Date {
    let endMs = activityLeg(context, at: date)?.endAtMs ?? context.state.endAtMs
    return Date(timeIntervalSince1970: Double(endMs) / 1_000)
}

private func activityComplete(_ context: ActivityViewContext<OffWorkActivityAttributes>, at date: Date) -> Bool {
    context.state.phase == "complete"
        || date.timeIntervalSince1970 * 1_000 >= Double(context.state.chainEndAtMs)
}

private func activityDestination(_ context: ActivityViewContext<OffWorkActivityAttributes>) -> URL? {
    context.state.destination.flatMap(URL.init(string:)) ?? URL(string: "offworkcountdown://timer")
}

/// Whether this is a focus or break activity at all, as opposed to the work
/// countdown. Structural, so it deliberately does not depend on the clock.
private func activityIsFocus(_ context: ActivityViewContext<OffWorkActivityAttributes>) -> Bool {
    guard let surface = context.state.surface else { return false }
    return surface != "work"
}

private func activityTitle(
    _ context: ActivityViewContext<OffWorkActivityAttributes>,
    at date: Date
) -> String {
    // The task wins over the phase: "Spec review" says more than "Focus", and
    // the countdown beside it already establishes that this is a timer.
    if let leg = activityLeg(context, at: date) { return leg.title ?? leg.label }
    return context.state.taskTitle ?? context.state.timerLabel ?? context.state.appTitle
}

private func activityTaskTitle(
    _ context: ActivityViewContext<OffWorkActivityAttributes>,
    at date: Date
) -> String? {
    activityLeg(context, at: date)?.title ?? context.state.taskTitle
}

/// The phase, not the task: "Focus", "Short break", "Next block".
private func activityPhaseLabel(
    _ context: ActivityViewContext<OffWorkActivityAttributes>,
    at date: Date
) -> String {
    activityLeg(context, at: date)?.label
        ?? context.state.timerLabel
        ?? context.state.appTitle
}

private func activityCaption(
    _ context: ActivityViewContext<OffWorkActivityAttributes>,
    at date: Date
) -> String? {
    if activityComplete(context, at: date) {
        // A finished chain already prints its closing line in the hero. The
        // work countdown keeps its separate note, which says something else.
        return context.state.chainDoneCaption == nil ? context.state.completedNote : nil
    }
    return activityLeg(context, at: date)?.label ?? context.state.caption
}

/// The support line under the bar: what this block is worth, or what follows
/// it. Never both — the card has one line for it and the countdown owns the
/// attention above.
private func activitySupportLine(
    _ context: ActivityViewContext<OffWorkActivityAttributes>,
    at date: Date
) -> String? {
    guard !activityComplete(context, at: date) else { return nil }
    guard let leg = activityLeg(context, at: date) else { return context.state.nextLabel }
    let progress = [leg.detail, leg.finishNote].compactMap { $0 }
    if !progress.isEmpty { return progress.joined(separator: " · ") }
    return leg.nextNote
}

/// Focus indigo, break teal, work orange — the canvas palette, where orange
/// means "now" and "selected" rather than a kind of time.
private let activityFocusTint = Color(red: 0.368, green: 0.360, blue: 0.902)
private let activityBreakTint = Color(red: 0.251, green: 0.784, blue: 0.878)

private func activityTint(
    _ context: ActivityViewContext<OffWorkActivityAttributes>,
    at date: Date
) -> Color {
    switch activityLeg(context, at: date)?.surface ?? context.state.surface {
    case "focus": activityFocusTint
    case "shortBreak", "longBreak": activityBreakTint
    default: activityOrange
    }
}

/// nil for the work countdown, which keeps the brand mark.
private func activitySymbol(
    _ context: ActivityViewContext<OffWorkActivityAttributes>,
    at date: Date
) -> String? {
    guard activityIsFocus(context) else { return nil }
    return activityLeg(context, at: date)?.icon ?? context.state.taskIcon ?? "stopwatch"
}

@ViewBuilder
private func activityCountdownText(
    _ context: ActivityViewContext<OffWorkActivityAttributes>,
    now: Date,
    size: CGFloat
) -> some View {
    if activityComplete(context, at: now) {
        Text(context.state.chainDoneCaption ?? context.state.completedCaption)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.58)
    } else if let leg = activityLeg(context, at: now), leg.isPreview {
        // A block the plan holds and nobody has started. Its hour is the fact;
        // a running countdown here would be a claim that it began.
        Text(Date(timeIntervalSince1970: Double(leg.startAtMs) / 1_000), style: .time)
            .font(.system(size: size, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .environment(\.locale, activityLocale(context))
            .lineLimit(1)
            .minimumScaleFactor(0.58)
    } else {
        Text(activityEnd(context, at: now), style: .timer)
            .font(.system(size: size, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            // Live Activities run in the Widget extension, whose process
            // locale can differ from the language selected inside the app.
            // Always-On Display may replace the seconds timer with a coarse
            // localized duration (for example "10 minutes"), so the locale
            // must travel with the activity content instead of falling back
            // to the extension or system language.
            .environment(\.locale, activityLocale(context))
            .lineLimit(1)
            .minimumScaleFactor(0.58)
    }
}

private func activityLocale(_ context: ActivityViewContext<OffWorkActivityAttributes>) -> Locale {
    Locale(identifier: context.state.locale)
}

private func activityProgressValue(_ context: ActivityViewContext<OffWorkActivityAttributes>, at date: Date) -> Double {
    if activityComplete(context, at: date) { return 100 }
    // Focus/break payloads advance from the current leg's start to its end,
    // rather than across the shift's effective segments.
    if activityIsFocus(context) {
        let nowMs = Int64(date.timeIntervalSince1970 * 1_000)
        guard let span = activitySpan(context, at: date) else { return context.state.progress }
        let total = max(1, span.end - span.start)
        return min(100, max(0, Double(nowMs - span.start) / Double(total) * 100))
    }
    return context.state.projectedProgress(
        atMs: Int64(date.timeIntervalSince1970 * 1_000)
    )
}

private func activitySpan(
    _ context: ActivityViewContext<OffWorkActivityAttributes>,
    at date: Date
) -> (start: Int64, end: Int64)? {
    if let leg = activityLeg(context, at: date) { return (leg.startAtMs, leg.endAtMs) }
    guard let segment = context.state.segments.first else { return nil }
    return (segment.startAtMs, segment.endAtMs)
}

@ViewBuilder
private func activityProgress(_ context: ActivityViewContext<OffWorkActivityAttributes>, at date: Date) -> some View {
    if activityIsFocus(context), let span = activitySpan(context, at: date) {
        let start = Date(timeIntervalSince1970: Double(span.start) / 1_000)
        let end = Date(timeIntervalSince1970: Double(span.end) / 1_000)
        // System interpolation keeps this moving without waking the extension.
        ProgressView(timerInterval: start...max(start, end), countsDown: false) {
            EmptyView()
        } currentValueLabel: { EmptyView() }
        .tint(activityTint(context, at: date))
        .labelsHidden()
        .frame(height: 6)
    } else {
        activityProgress(activityProgressValue(context, at: date))
    }
}

private func activityProgress(_ progress: Double) -> some View {
    GeometryReader { proxy in
        Capsule().fill(.white.opacity(0.22))
            .overlay(alignment: .leading) {
                Capsule().fill(activityOrange)
                    .frame(width: proxy.size.width * min(1, max(0, progress / 100)))
            }
    }
    .frame(height: 6)
}
