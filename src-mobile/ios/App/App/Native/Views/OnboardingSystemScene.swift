import SwiftUI

/// A labelled, noninteractive preview of the app's system surfaces. Layouts
/// follow smallContentBody / rectangularAccessory in the widget extension and
/// LockScreenActivityView in OffWorkWidgets.swift.
enum OnboardingSystemSurface: Int, CaseIterable {
    case widget, lockScreen, liveActivity, watch

    /// Apple Watch pairs with iPhone only.
    static var available: [Self] {
        UIDevice.current.userInterfaceIdiom == .phone ? allCases : [.widget, .lockScreen, .liveActivity]
    }

    func title(_ text: AppText) -> String {
        switch self {
        case .widget: text.t("onboardingWidgetSurface")
        case .lockScreen: text.t("onboardingLockSurface")
        case .liveActivity: text.t("liveActivity")
        case .watch: "Apple Watch"
        }
    }

    var clockPointSize: CGFloat {
        switch self {
        case .widget: 33
        case .lockScreen: 21
        case .liveActivity: 44
        case .watch: 30
        }
    }

    /// Surfaces whose clock sits on a dark ground.
    var hasLightClock: Bool { self == .lockScreen || self == .watch }
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
            if surface == .liveActivity { dynamicIsland }
            contextHeader
            if surface == .liveActivity { Spacer(minLength: 0) }
            if surface == .watch {
                Spacer(minLength: 0)
                watchFace
            } else if isLock {
                HStack(spacing: 10) {
                    circularRing
                    countdownPanel.frame(maxWidth: 164)
                }
            } else {
                Group {
                    if surface == .liveActivity { liveActivityCard }
                    else { countdownPanel }
                }
                    .frame(maxWidth: isWidget ? 218 : .infinity)
                    .padding(.horizontal, isWidget ? 0 : 14)
            }
            if isWidget { smallWidgets }
            Spacer(minLength: 0)
            if isLock { lockControls }
            if surface != .watch {
                Capsule().fill(.white.opacity(0.65)).frame(width: 90, height: 4)
                    .padding(.bottom, 10)
            }
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
        if surface == .watch {
            EmptyView()
        } else if !isWidget {
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

    // MARK: 3.2.3 widget suite

    private var ringProgress: Double { min(1, max(0, snapshot.progress / 100)) }

    private func ring(lineWidth: CGFloat) -> some View {
        ZStack {
            Circle().stroke(tint.opacity(0.22), lineWidth: lineWidth)
            Circle().trim(from: 0, to: ringProgress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    /// Two small Home Screen widgets beside the countdown: the ring and the
    /// clock-off time, both from the schedule just set.
    private var smallWidgets: some View {
        HStack(spacing: 10) {
            ZStack {
                ring(lineWidth: 9).padding(14)
                Text(snapshot.progress / 100, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
            }
            .frame(width: 104, height: 104)
            .background(OWCDesign.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(text.t("endTime")).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(OWCDesign.secondary)
                Spacer(minLength: 0)
                Text(text.formatTime(snapshot.endDate))
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(snapshot.endDate, format: .dateTime.weekday(.wide))
                    .font(.system(size: 11)).foregroundStyle(OWCDesign.secondary)
            }
            .padding(14)
            .frame(width: 104, height: 104, alignment: .leading)
            .background(OWCDesign.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .foregroundStyle(OWCDesign.primary)
    }

    /// The circular Lock Screen accessory beside the rectangular countdown.
    private var circularRing: some View {
        ZStack {
            ring(lineWidth: 5)
            Image(.brandMark).resizable().renderingMode(.template).scaledToFit()
                .frame(width: 18, height: 18)
        }
        .foregroundStyle(.white)
        .frame(width: 50, height: 50)
    }

    /// The Start shift control in the Lock Screen's control slot.
    private var lockControls: some View {
        HStack {
            Image(systemName: "play.fill")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 46, height: 46)
                .background(.white.opacity(0.18), in: Circle())
            Spacer()
            Image(systemName: "camera.fill")
                .font(.system(size: 16))
                .frame(width: 46, height: 46)
                .background(.white.opacity(0.18), in: Circle())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 30)
        .padding(.bottom, 4)
    }

    /// The compact Dynamic Island while a shift runs.
    private var dynamicIsland: some View {
        HStack(spacing: 6) {
            Image(.brandMark).resizable().renderingMode(.template).scaledToFit()
                .frame(width: 14, height: 14)
            Spacer(minLength: 0)
            Text(isUpcomingActivity ? text.formatTime(snapshot.startDate) : text.formatDuration(snapshot.heroRemainingMs(at: now)))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(OWCDesign.accent)
        .padding(.horizontal, 12)
        .frame(width: 150, height: 32)
        .background(.black, in: Capsule())
    }

    /// The Watch app's countdown: ring and time left, with the clock-off time.
    private var watchFace: some View {
        VStack(spacing: 6) {
            HStack {
                Text(OWCBrand.shortName).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OWCDesign.accent)
                Spacer()
                Text(now, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
            }
            ZStack {
                ring(lineWidth: 9)
                    .foregroundStyle(OWCDesign.accent)
                VStack(spacing: 0) {
                    if isUpcomingActivity {
                        Text(text.formatTime(snapshot.startDate))
                            .font(.system(size: surface.clockPointSize, weight: .bold).monospacedDigit())
                    } else {
                        OnboardingClockSlot(page: OnboardingPages.glance, text: text,
                            remainingMs: snapshot.heroRemainingMs(at: now), compact: true,
                            pointSize: surface.clockPointSize)
                    }
                    Text(isUpcomingActivity ? text.t("startTime") : caption)
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 22)
            }
            .frame(width: 150, height: 150)
            Text("\(text.t("endTime")) \(text.formatTime(snapshot.endDate))")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20).padding(.vertical, 18)
        .frame(width: 200, height: 248)
        .background(.black, in: RoundedRectangle(cornerRadius: 54, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 54, style: .continuous)
                .strokeBorder(Color(white: 0.28), lineWidth: 7)
        }
        .padding(.bottom, 24)
    }
}
