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
                .environment(\.colorScheme, .dark)
                .activityBackgroundTint(.black.opacity(0.38))
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
            if !activityComplete(context, at: timeline.date) {
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
                    size: 36
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
            .padding(.bottom, 12)
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
                        .foregroundStyle(.secondary)
                    Spacer()
                    // A block nobody has started has no end worth printing —
                    // its hero already shows the hour it begins.
                    if leg?.isPreview != true, !activityComplete(context, at: timeline.date) {
                        Group {
                            if let finishNote = leg?.finishNote {
                                Text(finishNote)
                            } else {
                                Text(activityEnd(context, at: timeline.date), style: .time)
                            }
                        }
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .environment(\.locale, activityLocale(context))
                    }
                }
                HStack(spacing: 10) {
                    // The button has no text baseline of its own, so only the
                    // countdown and its caption share one.
                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        activityCountdownText(context, now: timeline.date, size: 44, foreground: .primary)
                        if !activityIsFocus(context), let caption = activityCaption(context, at: timeline.date) {
                            Text(caption)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    Spacer(minLength: 8)
                    if !activityComplete(context, at: timeline.date) {
                        AddPomodoroButton(state: context.state, now: timeline.date, startAtMs: leg?.startAtMs ?? context.attributes.shiftStartAtMs)
                        if let label = context.state.stopFocusLabel,
                           leg?.surface == "focus", leg?.isPreview != true {
                            Link(destination: focusActionURL(.stop, startAtMs: leg?.startAtMs ?? context.attributes.shiftStartAtMs)) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(width: 44, height: 44)
                                    .background(.primary.opacity(0.12), in: .circle)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                            .fixedSize()
                            .accessibilityLabel(label)
                        }
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
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
    }
}

/// Opens the running task in the app to choose and confirm additional blocks.
///
/// The trailing edge of the hero row is where the system's own timer puts its
/// controls, so this is the ordinary place for it rather than an invention.
/// It disappears entirely on a break or a work countdown, and greys out when
/// the rest of the shift already belongs to other tasks — a control that can
/// be tapped and does nothing is worse than one that says it cannot act.
private struct AddPomodoroButton: View {
    let state: OffWorkActivityAttributes.ContentState
    let now: Date
    let startAtMs: Int64

    var body: some View {
        if state.showsAddPomodoro(atMs: Int64(now.timeIntervalSince1970 * 1_000)),
           let label = state.addPomodoroLabel {
            Link(destination: focusActionURL(.addPomodoros, startAtMs: startAtMs)) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.primary.opacity(0.12), in: .circle)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .disabled(!state.addPomodoroEnabled)
            .accessibilityLabel(label)
            // The timer text beside it reports an ideal width far wider than
            // the digits it draws, and would otherwise squeeze the button out
            // of the row entirely.
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
                if !activityIsFocus(context) {
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
                // The render server interpolates this bounded timer while the
                // extension sleeps. It stops at zero even if the next leg has
                // not received a redraw; a date-style timer would count up again.
                //
                // The explicit width below is still required. Timer text in
                // Dynamic Island's compact regions reports a broken, oversized
                // ideal width (https://developer.apple.com/forums/thread/723316),
                // and unbounded it blows the island out to its expanded shape
                // with the countdown rendered blank.
                Text(timerInterval: timeline.date...max(timeline.date, activityEnd(context, at: timeline.date)), countsDown: true)
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .environment(\.locale, activityLocale(context))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    // Align the timer's glyphs inside its reserved width, not
                    // just the outer frame. Seconds stay against the capsule
                    // edge even when the timer loses a minute or hour digit.
                    .multilineTextAlignment(.trailing)
                    .frame(width: compactTimerWidth(context, now: timeline.date), alignment: .trailing)
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
/// These boundaries are best-effort redraw requests, not scheduled ActivityKit
/// updates. iOS can suspend the extension across all of them. Bounded timer
/// text remains safe then; notifications deliver the transitions independently.
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
    return .init(boundaries: boundaries, interval: legs.isEmpty ? 1 : 60)
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
    if let detail = leg.detail { return detail }
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
    size: CGFloat,
    foreground: Color = .white
) -> some View {
    if activityComplete(context, at: now) {
        Text(context.state.chainDoneCaption ?? context.state.completedCaption)
            .font(.system(size: activityIsFocus(context) ? min(size, 22) : size, weight: activityIsFocus(context) ? .semibold : .bold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.58)
    } else if let leg = activityLeg(context, at: now), leg.isPreview {
        // A block the plan holds and nobody has started. Its hour is the fact;
        // a running countdown here would be a claim that it began.
        Text(Date(timeIntervalSince1970: Double(leg.startAtMs) / 1_000), style: .time)
            .font(.system(size: size, weight: .bold).monospacedDigit())
            .foregroundStyle(foreground)
            .environment(\.locale, activityLocale(context))
            .lineLimit(1)
            .minimumScaleFactor(0.58)
    } else {
        // The render server owns this text and keeps counting while the
        // extension is suspended, which is the whole of Always-On Display: a
        // duration computed here from `now` freezes at whatever minute the
        // screen dimmed on, because nothing wakes us to draw the next one.
        // Coarsening to minutes on the dimmed screen is the system's call to
        // make, not ours.
        Text(timerInterval: now...max(now, activityEnd(context, at: now)), countsDown: true)
            .font(.system(size: size, weight: .bold).monospacedDigit())
            .foregroundStyle(foreground)
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
    } else if !activityComplete(context, at: date), !context.state.segments.isEmpty {
        activitySegmentedProgress(context.state.segments)
    } else {
        activityProgress(activityProgressValue(context, at: date))
    }
}

/// The shift's effective segments, side by side, each filling over its own
/// interval so the render server can animate them with the extension asleep.
///
/// A width computed here from `now` needs a wake-up per frame, which is what
/// Always-On Display does not give — the bar froze while the countdown above
/// it kept moving. One `ProgressView(timerInterval:)` stretched across the
/// whole shift would draw itself, but it would also count the lunch gap as
/// worked time. Per segment, the gap simply has no bar to advance, which is
/// the same arithmetic `projectedProgress` does.
private func activitySegmentedProgress(
    _ segments: [OffWorkActivityAttributes.ContentState.Segment]
) -> some View {
    let durations = segments.map { max(0, $0.endAtMs - $0.startAtMs) }
    let total = durations.reduce(Int64(0), +)
    return GeometryReader { proxy in
        HStack(spacing: 0) {
            ForEach(Array(zip(segments, durations)), id: \.0.startAtMs) { segment, duration in
                let start = Date(timeIntervalSince1970: Double(segment.startAtMs) / 1_000)
                let end = Date(timeIntervalSince1970: Double(segment.endAtMs) / 1_000)
                ProgressView(timerInterval: start...max(start, end), countsDown: false) {
                    EmptyView()
                } currentValueLabel: { EmptyView() }
                    .tint(activityOrange)
                    .labelsHidden()
                    .frame(width: proxy.size.width * Double(duration) / Double(max(1, total)))
            }
        }
    }
    .frame(height: 6)
}

private func activityProgress(_ progress: Double) -> some View {
    GeometryReader { proxy in
        Capsule().fill(.primary.opacity(0.16))
            .overlay(alignment: .leading) {
                Capsule().fill(activityOrange)
                    .frame(width: proxy.size.width * min(1, max(0, progress / 100)))
            }
    }
    .frame(height: 6)
}

private func focusActionURL(_ action: FocusActivityRequest.Action, startAtMs: Int64) -> URL {
    // Only a fixed action and an integer enter this URL; no task title or salary.
    URL(string: "offworkcountdown://focus?action=\(action.rawValue)&start=\(startAtMs)")!
}
