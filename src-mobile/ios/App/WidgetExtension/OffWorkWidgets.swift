import ActivityKit
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
                    HStack(spacing: 8) {
                        // The bare mark, not the plated app icon: the Dynamic
                        // Island is already a container, and a second rounded
                        // plate inside it reads as a sticker.
                        AlwaysDarkBrandMark(size: 25)

                        Text(activityTitle(context))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                            .allowsTightening(true)
                    }
                    .frame(maxWidth: 150, alignment: .leading)
                    .padding(.leading, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // The capsule rounds the corners of the expanded area, so
                    // the trailing content is pulled in far enough that its last
                    // glyph is not clipped by the curve.
                    Text(endDate(context), style: .time)
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                        .environment(\.locale, activityLocale(context))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: 54, alignment: .trailing)
                        .padding(.trailing, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityCountdownPanel(context: context, size: 40)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 4)
                }
            } compactLeading: {
                AlwaysDarkBrandMark(size: 20)
            } compactTrailing: {
                ActivityCompactCountdown(context: context)
            } minimal: {
                AlwaysDarkBrandMark(size: 18)
            }
            .widgetURL(activityDestination(context))
            .keylineTint(activityOrange)
        }
    }

    private func endDate(_ context: ActivityViewContext<OffWorkActivityAttributes>) -> Date {
        Date(timeIntervalSince1970: Double(context.state.endAtMs) / 1_000)
    }
}

private struct LockScreenActivityView: View {
    let context: ActivityViewContext<OffWorkActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                // The lock-screen card has enough room for the full icon and
                // benefits from its solid plate against the glass material.
                // Dynamic Island remains on the lighter transparent mark.
                ActivityAppIcon(size: 24)
                Text(activityTitle(context))
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.25)
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(Date(timeIntervalSince1970: Double(context.state.endAtMs) / 1_000), style: .time)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .environment(\.locale, activityLocale(context))
            }
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                activityCountdownText(context, now: timeline.date, size: 44)
                Text(activityComplete(context, at: timeline.date) ? context.state.completedNote : context.state.caption)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.top, 12)
            activityProgress(activityProgressValue(context, at: timeline.date))
                .padding(.top, 14)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        }
    }
}

private struct ActivityCountdownPanel: View {
    let context: ActivityViewContext<OffWorkActivityAttributes>
    let size: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(spacing: 14) {
                HStack {
                    activityCountdownText(context, now: timeline.date, size: size)
                    Spacer()
                    Text(String(format: "%.1f%%", activityProgressValue(context, at: timeline.date)))
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(activityOrange)
                }
                activityProgress(activityProgressValue(context, at: timeline.date))
            }
        }
    }
}

private struct ActivityCompactCountdown: View {
    let context: ActivityViewContext<OffWorkActivityAttributes>

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
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
                Text(Date(timeIntervalSince1970: Double(context.state.endAtMs) / 1_000), style: .timer)
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
    let remaining = Double(context.state.endAtMs) / 1_000 - now.timeIntervalSince1970
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

private let activityOrange = Color(red: 0.976, green: 0.451, blue: 0.086)

private func activityComplete(_ context: ActivityViewContext<OffWorkActivityAttributes>, at date: Date) -> Bool {
    context.state.phase == "complete" || date.timeIntervalSince1970 * 1_000 >= Double(context.state.endAtMs)
}

private func activityDestination(_ context: ActivityViewContext<OffWorkActivityAttributes>) -> URL? {
    context.state.destination.flatMap(URL.init(string:)) ?? URL(string: "offworkcountdown://timer")
}

private func activityTitle(_ context: ActivityViewContext<OffWorkActivityAttributes>) -> String {
    context.state.timerLabel ?? context.state.appTitle
}

@ViewBuilder
private func activityCountdownText(
    _ context: ActivityViewContext<OffWorkActivityAttributes>,
    now: Date,
    size: CGFloat
) -> some View {
    if activityComplete(context, at: now) {
        Text(context.state.completedCaption)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.58)
    } else {
        Text(Date(timeIntervalSince1970: Double(context.state.endAtMs) / 1_000), style: .timer)
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
    // Focus/break payloads carry one absolute segment. Unlike work progress,
    // their progress should simply advance from the session start to its end.
    if context.state.surface != nil {
        let nowMs = Int64(date.timeIntervalSince1970 * 1_000)
        guard let segment = context.state.segments.first else { return context.state.progress }
        let total = max(1, segment.endAtMs - segment.startAtMs)
        return min(100, max(0, Double(nowMs - segment.startAtMs) / Double(total) * 100))
    }
    return context.state.projectedProgress(
        atMs: Int64(date.timeIntervalSince1970 * 1_000)
    )
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
