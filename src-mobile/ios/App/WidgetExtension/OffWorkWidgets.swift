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
                .widgetURL(URL(string: "offworkcountdown://timer"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading, priority: 1) {
                    HStack(spacing: 8) {
                        // The bare mark, not the plated app icon: the Dynamic
                        // Island is already a container, and a second rounded
                        // plate inside it reads as a sticker.
                        AlwaysDarkBrandMark(size: 25)

                        Text(context.state.appTitle)
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
                // A fixed box with centred content: Text(style: .timer) shrinks
                // as digits drop, and without this it drifts to the leading edge
                // once the countdown reaches 0:00.
                ActivityCompactCountdown(context: context)
                    .frame(width: 50, alignment: .center)
            } minimal: {
                AlwaysDarkBrandMark(size: 18)
            }
            .widgetURL(URL(string: "offworkcountdown://timer"))
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
                AlwaysDarkBrandMark(size: 22)
                Text(context.state.appTitle)
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
            activityCountdownText(context, now: timeline.date, size: 14)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
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
