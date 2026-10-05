import SwiftUI

/// A small, shared visual of the user's draft. Gaps come from the scheduling
/// rules' effective segments, including overnight shifts; no second calculator.
struct OnboardingShiftRibbon: View {
    @Environment(SceneState.self) private var scene
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let shifts: ShiftSessionStore
    let text: AppText
    var showsReminders = false
    var showsHours = true

    var body: some View {
        if let snapshot = scene.setupProjection(using: shifts)?.snapshot {
            VStack(spacing: 10) {
                if showsHours {
                HStack {
                    Text(text.formatTime(snapshot.startDate))
                    Spacer()
                    Text(text.formatTime(snapshot.endDate))
                }
                .font(.footnote.weight(.medium).monospacedDigit())
                .foregroundStyle(OWCDesign.secondary)
                }
                GeometryReader { geometry in
                    let span = max(1, snapshot.endAtMs - snapshot.startAtMs)
                    ZStack(alignment: .leading) {
                        Capsule().fill(OWCDesign.control)
                        if !showsReminders { Capsule().fill(OWCDesign.accent) }
                        ForEach(Array((showsReminders ? snapshot.segments : []).enumerated()), id: \.offset) { _, segment in
                            Capsule().fill(OWCDesign.accent)
                                .frame(width: geometry.size.width * max(0, segment.endAtMs - segment.startAtMs) / span)
                                .offset(x: geometry.size.width * (segment.startAtMs - snapshot.startAtMs) / span)
                                .transition(.opacity)
                        }
                        if showsReminders, let preview = scene.setupPreview(using: shifts) {
                            ForEach(preview.upcoming.filter { $0.id != "shift-start" && $0.id != "shift-end" }) { entry in
                                if let date = entry.date {
                                    Circle().fill(OWCDesign.card)
                                        .frame(width: 8, height: 8)
                                        .overlay { Circle().strokeBorder(OWCDesign.accent, lineWidth: 2) }
                                        .offset(x: geometry.size.width * min(1, max(0, (date.timeIntervalSince1970 * 1000 - snapshot.startAtMs) / span)) - 4)
                                }
                            }
                        }
                    }
                }
                .frame(height: 8)
                .animation(reduceMotion ? nil : OWCMotion.onboardingDisclosure, value: snapshot.segments)
            }
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(shifts.onboardingScheduleRecap())
        }
    }
}

/// Shared by the result and the system-surface tour. Every rendition uses
/// the same draft and reference time, rather than unrelated marketing numbers.
struct OnboardingCountdownFace: View {
    let shifts: ShiftSessionStore
    let snapshot: NativeShiftSnapshot
    let now: Date

    private var caption: String {
        if snapshot.isBeforeStart(at: now) { return shifts.text.t("nextShiftLabelShort") }
        if let end = snapshot.activeBreakEndDate {
            return shifts.text.t("pausedUntil", values: ["time": shifts.text.formatTime(end)])
        }
        return shifts.text.t("timeLeftCaption")
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(snapshot.startDate.formatted(.dateTime.month().day().weekday(.wide).locale(shifts.preferences.locale)))
                .font(.title3.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(shifts.text.formatTime(snapshot.startDate))
                Text(verbatim: "–").foregroundStyle(OWCDesign.secondary)
                Text(shifts.text.formatTime(snapshot.endDate))
            }
            .font(.largeTitle.weight(.semibold).monospacedDigit())
            .lineLimit(1).minimumScaleFactor(0.65)
            .environment(\.layoutDirection, .leftToRight)
            OnboardingShiftRibbon(shifts: shifts, text: shifts.text, showsReminders: true, showsHours: false)
                .padding(.vertical, 4)
            Divider()
            Text(caption).font(.footnote).foregroundStyle(OWCDesign.secondary)
            OnboardingClockSlot(page: OnboardingPages.ready, text: shifts.text, remainingMs: snapshot.heroRemainingMs(at: now))
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(OWCDesign.card, in: RoundedRectangle(cornerRadius: OWCDesign.cardRadius))
    }
}

/// Layout anchors keep one persistent clock above the two changing pages.
struct OnboardingClockAnchorKey: PreferenceKey {
    static let viewportOffset = 100
    static let defaultValue: [Int: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct OnboardingClockSlot: View {
    let page: Int
    let text: AppText
    let remainingMs: Double
    var compact = false
    var pointSize: CGFloat = 48
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 36

    var body: some View {
        Color.clear
            .frame(height: compact ? pointSize * 1.2 : clockSize * 1.2)
            .frame(maxWidth: .infinity)
            .anchorPreference(key: OnboardingClockAnchorKey.self, value: .bounds) { [page: $0] }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text.formatDuration(remainingMs))
            .accessibilityAddTraits(.updatesFrequently)
    }
}

struct OnboardingJourneyDigits: View {
    let text: AppText
    let remainingMs: Double
    var compact = false
    var pointSize: CGFloat = 48
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 36

    var body: some View {
        Text(text.formatDuration(remainingMs))
            .font(.system(size: compact ? pointSize : clockSize, weight: .bold).monospacedDigit())
            .tracking(compact ? -1 : -2)
            .lineLimit(1).minimumScaleFactor(0.45)
            .environment(\.layoutDirection, .leftToRight)
            .owcCountdownTextTransition(milliseconds: remainingMs)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

struct OnboardingReadyPage: View {
    @Environment(SceneState.self) private var scene
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var preferences: PreferencesStore
    let shifts: ShiftSessionStore
    let text: AppText
    let referenceDate: Date
    let animatesEntrance: Bool
    let onFinish: () -> Void
    let onExplore: () -> Void
    @State private var revealed = false

    var body: some View {
        OnboardingPageScaffold(page: OnboardingPages.ready) { _ in
            VStack(spacing: 18) {
                Spacer(minLength: 8)
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(OWCDesign.accent)
                        .accessibilityHidden(true)
                    Text(text.t("onboardingAllSetTitle"))
                        .font(.title.bold())
                    Text(shifts.onboardingScheduleRecap())
                        .font(.callout)
                        .foregroundStyle(OWCDesign.secondary)
                }
                .multilineTextAlignment(.center)
                TimelineView(PausableSecondsSchedule(isPaused: reduceMotion)) { context in
                    let now = reduceMotion ? referenceDate : context.date
                    if let snapshot = scene.setupProjection(at: now, using: shifts)?.snapshot {
                        OnboardingCountdownFace(shifts: shifts, snapshot: snapshot, now: now)
                            .padding(.vertical, 2)
                    }
                }
                .owcRevealed(revealed || !animatesEntrance, index: 0, reduceMotion: reduceMotion)
                let entries = scene.setupPreview(using: shifts)?.upcoming ?? []
                VStack(alignment: .leading, spacing: 10) {
                    OWCSectionHeader(title: text.t("comingUp"))
                    OWCGroupCard {
                        if entries.isEmpty {
                            OWCRow(icon: "play.circle", title: text.t("scheduleManualTimer"),
                                   subtitle: text.t("scheduleOffManualStart"), isLast: true) { EmptyView() }
                        } else {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                ShiftPreviewRow(locale: preferences.locale, entry: entry, now: referenceDate,
                                                showsSeparator: index < entries.count - 1,
                                                showsChevron: false, reservesChevron: false)
                            }
                        }
                    }
                }
                .owcRevealed(revealed || !animatesEntrance, index: 1, reduceMotion: reduceMotion)
                if dynamicTypeSize.isAccessibilitySize { exploreButton }
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 560)
        } footer: {
            if !dynamicTypeSize.isAccessibilitySize { exploreButton }
            Button(text.t("onboardingStartUsing"), action: onFinish)
                .buttonStyle(OWCPrimaryButtonStyle())
        }
        .onAppear { revealed = true }
    }

    private var exploreButton: some View {
        Button(text.t("onboardingExplore"), action: onExplore)
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(minHeight: 44)
    }
}

struct OnboardingGlancePage: View {
    @Environment(SceneState.self) private var scene
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let shifts: ShiftSessionStore
    let text: AppText
    let referenceDate: Date
    let onFinish: () -> Void
    let onContinue: () -> Void
    @Binding var surface: OnboardingSystemSurface
    var body: some View {
        OnboardingPageScaffold(page: OnboardingPages.glance, showsPageIndicator: false) { viewport in
            let wide = viewport.width >= 650 && !dynamicTypeSize.isAccessibilitySize
            VStack(spacing: 16) {
                Spacer(minLength: 16)
                if wide {
                    HStack(spacing: 40) {
                        VStack(spacing: 24) {
                            introduction
                            surfaceSelector
                        }
                        .frame(maxWidth: 320)
                        preview(height: min(340, max(280, viewport.height - 32)))
                    }
                } else {
                    introduction
                    preview(height: min(320, max(280, viewport.height - 260)))
                    surfaceSelector
                }
                if dynamicTypeSize.isAccessibilitySize { exploreButton }
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: wide ? 900 : 560)
        } footer: {
            if !dynamicTypeSize.isAccessibilitySize { exploreButton }
            Button(text.t("onboardingStartUsing"), action: onFinish)
                .buttonStyle(OWCPrimaryButtonStyle())
        }
    }

    private var introduction: some View {
        VStack(spacing: 16) {
            Text(text.t("onboardingEverywhereTitle"))
                .font(.title.bold())
            Text(text.t("onboardingSystemBody"))
                .font(.callout)
                .foregroundStyle(OWCDesign.secondary)
        }
        .multilineTextAlignment(.center)
    }

    private var surfaceSelector: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { surfaceButtons }
            VStack(spacing: 8) { surfaceButtons }
        }
    }

    private func preview(height: CGFloat) -> some View {
        VStack(spacing: 16) {
            TimelineView(PausableSecondsSchedule(isPaused: reduceMotion)) { context in
                let now = reduceMotion ? referenceDate : context.date
                let snapshot = scene.setupProjection(at: now, using: shifts)?.snapshot
                Group {
                    if let snapshot {
                        OnboardingSystemScene(surface: surface, snapshot: snapshot, now: now, text: text, height: height)
                    } else {
                        Text(text.t("scheduleOffManualStart"))
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text.t("onboardingSystemTitle") + ", " + text.t(surface.titleKey))
                .accessibilityValue(snapshot.map { snapshot in
                    surface == .liveActivity && snapshot.isBeforeStart(at: now)
                        ? text.t("startTime") + ", " + snapshot.startDate.formatted(.dateTime.month().day().hour().minute().locale(shifts.preferences.locale))
                        : text.formatDuration(snapshot.heroRemainingMs(at: now))
                } ?? text.t("scheduleOffManualStart"))
            }
            Text(text.t("onboardingShiftPreview"))
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
        }
    }

    private var exploreButton: some View {
        Button(text.t("onboardingExplorePlus"), action: onContinue)
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(minHeight: 44)
    }

    private var surfaceButtons: some View {
        ForEach(OnboardingSystemSurface.allCases, id: \.self) { item in
            Button {
                withAnimation(reduceMotion ? OWCMotion.reduced : OWCMotion.phase) { surface = item }
            } label: {
                Text(text.t(item.titleKey))
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(surface == item ? OWCDesign.accent.opacity(0.12) : OWCDesign.control, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(surface == item ? .isSelected : [])
        }
    }
}
