import SwiftUI

/// A labelled, noninteractive preview of the app's system surfaces. Layouts
/// follow smallContentBody / rectangularAccessory in the widget extension and
/// LockScreenActivityView in OffWorkWidgets.swift.
enum OnboardingSystemSurface: Int, CaseIterable {
    case widget, lockScreen, liveActivity

    var titleKey: String {
        switch self {
        case .widget: "onboardingWidgetSurface"
        case .lockScreen: "onboardingLockSurface"
        case .liveActivity: "liveActivity"
        }
    }

    var clockPointSize: CGFloat {
        switch self {
        case .widget: 33
        case .lockScreen: 21
        case .liveActivity: 44
        }
    }
}

struct OnboardingSystemScene: View {
    let surface: OnboardingSystemSurface
    let snapshot: NativeShiftSnapshot
    let now: Date
    let text: AppText
    let height: CGFloat

    private var isLock: Bool { surface == .lockScreen }
    private var isWidget: Bool { surface == .widget }
    private var isUpcomingActivity: Bool { surface == .liveActivity && snapshot.isBeforeStart(at: now) }
    private var caption: String {
        snapshot.isBeforeStart(at: now) ? text.t("nextShiftLabelShort") :
        snapshot.activeBreakEndDate.map { text.t("pausedUntil", values: ["time": text.formatTime($0)]) } ?? text.t("timeLeftCaption")
    }
    private var boundary: Date {
        snapshot.isBeforeStart(at: now) ? snapshot.startDate : snapshot.activeBreakEndDate ?? snapshot.endDate
    }
    private var tint: Color { isLock ? .white : OWCDesign.accent }

    var body: some View {
        VStack(spacing: 10) {
            contextHeader
            if surface == .liveActivity { Spacer(minLength: 0) }
            Group {
                if surface == .liveActivity { liveActivityCard }
                else { countdownPanel }
            }
                .frame(maxWidth: isLock ? 164 : isWidget ? 218 : .infinity)
                .padding(.horizontal, isWidget ? 0 : 14)
            Spacer(minLength: 0)
            if isWidget { appGrid }
            Capsule().fill(.white.opacity(0.65)).frame(width: 90, height: 4)
                .padding(.bottom, 10)
        }
        .padding(.top, 14)
        .frame(maxWidth: 350)
        .frame(height: height)
        .background {
            LinearGradient(colors: [OWCDesign.brandPlum, OWCDesign.brandPlum.opacity(0.92),
                                    OWCDesign.orangeDeep.opacity(0.65)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        // These are system-size previews, not additional app controls. Keep
        // their geometry recognizable; the surrounding title, description,
        // scene selector and primary action retain unrestricted Dynamic Type.
        .dynamicTypeSize(.large)
        .environment(\.layoutDirection, .leftToRight)
        .allowsHitTesting(false)
    }

    @ViewBuilder private var contextHeader: some View {
        if !isWidget {
            VStack(spacing: 2) {
                Image(systemName: "lock.fill").font(.system(size: 13))
                    .padding(.bottom, 8)
                Text(now, format: .dateTime.month().day().weekday(.wide))
                    .font(.system(size: 13, weight: .medium))
                Text(now, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                    .font(.system(size: surface == .liveActivity ? 44 : 64, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.65)
            }
            .foregroundStyle(.white)
        } else if isWidget {
            HStack(spacing: 5) {
                Text(now, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute()).font(.system(size: 12, weight: .semibold))
                Spacer()
                Image(systemName: "wifi")
                Image(systemName: "battery.100percent")
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 24)
        }
    }

    /// Same hierarchy and spacing as LockScreenActivityView: app icon/title,
    /// end time, baseline-aligned hero/caption, progress and supporting line.
    private var liveActivityCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image("BrandIcon").resizable().scaledToFit().frame(width: 24, height: 24)
                Text(OWCBrand.shortName).font(.system(size: 13, weight: .semibold))
                Spacer()
                if !isUpcomingActivity { Text(text.formatTime(boundary)).font(.system(size: 13).monospacedDigit()) }
            }
            .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                if isUpcomingActivity {
                    Text(text.formatTime(snapshot.startDate))
                        .font(.system(size: 44, weight: .bold).monospacedDigit())
                } else {
                    OnboardingClockSlot(page: OnboardingPages.glance, text: text,
                        remainingMs: snapshot.heroRemainingMs(at: now), compact: true, pointSize: 44)
                }
                Text(isUpcomingActivity ? text.t("startTime") : caption)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.top, 12)
            if !isUpcomingActivity { progress.padding(.top, 14) }
            HStack(spacing: 8) {
                Text(snapshot.startDate, format: .dateTime.month().day().weekday(.wide))
                Spacer(minLength: 4)
                Text(text.t("endTime"))
                Text(text.formatTime(snapshot.endDate))
            }
            .font(.system(size: 12)).foregroundStyle(.secondary)
            .padding(.top, 10)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .foregroundStyle(OWCDesign.primary)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private var countdownPanel: some View {
        VStack(alignment: .leading, spacing: isLock ? 3 : 10) {
            if surface == .liveActivity {
                // Negative space occupied by the camera in the expanded island.
                Color.clear.frame(height: 18)
            }
            HStack(spacing: isLock ? 4 : 8) {
                Image(.brandMark).resizable().renderingMode(isLock ? .template : .original).scaledToFit()
                    .frame(width: isLock ? 12 : 22, height: isLock ? 12 : 22)
                    .environment(\.colorScheme, isWidget ? colorScheme : .dark)
                Text(surface == .liveActivity ? (isUpcomingActivity ? text.t("startTime") : caption) : OWCBrand.shortName)
                    .font(.system(size: isLock ? 11 : 13, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                if surface == .liveActivity && !isUpcomingActivity {
                    Text(text.formatTime(boundary)).font(.system(size: 12).monospacedDigit())
                } else if isLock {
                    Image(systemName: snapshot.isBeforeStart(at: now) ? "sunrise.fill" : "briefcase.fill")
                        .font(.system(size: 11))
                }
            }
            if isWidget {
                HStack(spacing: 5) {
                    Circle().fill(tint).frame(width: 5, height: 5)
                    Text(caption).font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(tint.opacity(0.12), in: Capsule())
            }
            if isUpcomingActivity {
                // Match the extension's future-leg presentation: a start hour,
                // never a running activity that onboarding has not started.
                Text(text.formatTime(snapshot.startDate))
                    .font(.system(size: surface.clockPointSize, weight: .bold).monospacedDigit())
                Text(snapshot.startDate, format: .dateTime.month().day().weekday(.wide))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
            } else {
                OnboardingClockSlot(page: OnboardingPages.glance, text: text,
                                    remainingMs: snapshot.heroRemainingMs(at: now), compact: true,
                                    pointSize: surface.clockPointSize)
            }
            if !isUpcomingActivity { progress }
            if !isLock && !isUpcomingActivity {
                HStack {
                    Text(snapshot.progress / 100, format: .percent.precision(.fractionLength(0)))
                        .foregroundStyle(tint)
                    Spacer()
                    if isWidget { Text(text.formatTime(boundary)) }
                }
                .font(.system(size: 11, weight: .medium).monospacedDigit())
            }
        }
        .padding(isLock ? 0 : 16)
        .foregroundStyle(isWidget ? OWCDesign.primary : .white)
        .background {
            if !isLock {
                RoundedRectangle(cornerRadius: isWidget ? 24 : 34, style: .continuous)
                    .fill(isWidget ? OWCDesign.card : .black)
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private var progress: some View {
        GeometryReader { proxy in
            Capsule().fill(tint.opacity(0.22))
            Capsule().fill(tint)
                .frame(width: proxy.size.width * min(1, max(0, snapshot.progress / 100)))
        }
        .frame(height: isLock ? 4 : 5)
    }

    /// Context silhouettes deliberately contain no invented third-party apps.
    private var appGrid: some View {
        HStack(spacing: 22) {
            ForEach(0..<4) { _ in
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.bottom, 5)
        .accessibilityHidden(true)
    }
}
