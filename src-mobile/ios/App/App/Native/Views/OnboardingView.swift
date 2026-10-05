import SwiftUI
import UIKit

struct OnboardingView: View {
    @Environment(SceneState.self) private var scene
    @Bindable var preferences: PreferencesStore
    let shifts: ShiftSessionStore
    let recovery: RecoveryStore
    let actions: RecordsActions
    let text: AppText
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(NotificationService.self) private var notifications
    @State private var navigationFeedback = 0
    /// Read by the page transition. Set before `onboardingPage` changes so
    /// insertion and removal agree on direction for this hop.
    @State private var goingBack = false
    @State private var showsReturningUserSetup = false
    @State private var visitedPages: Set<Int> = []
    @State private var journeyReferenceDate = Date.now
    @State private var continuesCountdown = false
    @State private var glanceSurface: OnboardingSystemSurface = .widget

    /// Configuration pages slide in reading order. Result and system surfaces
    /// cross-fade around the persistent clock; Reduce Motion uses a short fade.
    private static let forwardTransition = AnyTransition.asymmetric(
        insertion: .move(edge: .trailing),
        removal: .move(edge: .leading)
    )
    private static let backTransition = AnyTransition.asymmetric(
        insertion: .move(edge: .leading),
        removal: .move(edge: .trailing)
    )

    var body: some View {
        ZStack {
            // Each page scrolls inside its own `OnboardingPageScaffold`, with
            // its Continue pinned at the bottom. The pages used to share one
            // scroll view here and carry their button at the end of their
            // content, so on any screen shorter than the design — a 6.3"
            // phone on the schedule page, landscape, accessibility sizes, and
            // the 678 pt cover screen of an iPhone Duo — Continue slid below
            // the fold and a tap aimed at it landed on whatever had moved up.
            Group {
                switch scene.onboardingPage {
                case OnboardingPages.landing:
                    welcome
                case OnboardingPages.schedule:
                    schedulePage
                case OnboardingPages.reminders:
                    OnboardingRemindersPage(
                        preferences: preferences,
                        shifts: shifts,
                        text: text,
                        onContinue: advanceFromReminders
                    )
                case OnboardingPages.ready:
                    readyPage
                case OnboardingPages.glance:
                    glance
                default:
                    OnboardingPlusShowcasePage(text: text, onContinue: onFinish) {
                        scene.paywallSheet = .intro
                    }
                }
            }
            .id(scene.onboardingPage)
            .transition(pageTransition)
        }
        .overlayPreferenceValue(OnboardingClockAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if let anchor = anchors[scene.onboardingPage] {
                    let bounds = proxy[anchor]
                    TimelineView(PausableSecondsSchedule(isPaused: reduceMotion)) { context in
                        let now = reduceMotion ? journeyReferenceDate : context.date
                        if let snapshot = scene.setupProjection(at: now, using: shifts)?.snapshot {
                            OnboardingJourneyDigits(text: text, remainingMs: snapshot.heroRemainingMs(at: now),
                                                    compact: scene.onboardingPage == OnboardingPages.glance,
                                                    pointSize: glanceSurface.clockPointSize)
                                .foregroundStyle(scene.onboardingPage == OnboardingPages.glance && glanceSurface == .lockScreen ? Color.white : OWCDesign.primary)
                                .frame(width: bounds.width, height: bounds.height)
                                .position(x: bounds.midX, y: bounds.midY)
                                .animation(reduceMotion ? nil : OWCMotion.onboardingContinuity, value: scene.onboardingPage)
                        }
                    }
                    .mask {
                        if let viewport = anchors[scene.onboardingPage + OnboardingClockAnchorKey.viewportOffset] {
                            let clip = proxy[viewport]
                            Rectangle().frame(width: clip.width, height: clip.height)
                                .position(x: clip.midX, y: clip.midY)
                        }
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            if scene.onboardingPage != OnboardingPages.landing {
                Button(action: goBack) {
                    Image(systemName: "chevron.backward")
                        .font(.title3.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .padding(.leading, 20)
                .padding(.top, 8)
                .accessibilityLabel(text.t("onboardingBack"))
            }
        }
        .animation(pageAnimation, value: scene.onboardingPage)
        // The grouped background, not the plain one: cards are
        // `secondarySystemGroupedBackground`, which is pure white in light mode
        // — exactly the same white as `systemBackground` — so on a plain
        // background every card here silently vanished and its rows were left
        // floating without a container.
        //
        // ShapeStyle `.background(color)` only ignores the *container* safe
        // area. The keyboard is a separate region, so when the lunch-duration
        // number pad dismissed the strip it vacated was the hosting
        // controller's default white fill — a one-frame overlay across the
        // continue row. Painting the same colour with `ignoresSafeArea()`
        // covers that region for the whole animation.
        .background {
            OWCDesign.page.ignoresSafeArea()
        }
        // Keep the onboarding canvas at one height while the number pad moves.
        // Otherwise UIKit animates the keyboard safe area and GeometryReader
        // solves a second bottom-button position halfway through dismissal.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .environment(\.layoutDirection, preferences.layoutDirection)
        .environment(\.locale, preferences.locale)
        .sensoryFeedback(.impact(weight: .light), trigger: navigationFeedback)
        .onChange(of: reduceMotion) { _, isReduced in
            if isReduced { journeyReferenceDate = .now }
        }
        .fullScreenCover(isPresented: $showsReturningUserSetup) {
            FirstRunRecoveryView(recovery: recovery, actions: actions) {
                showsReturningUserSetup = false
                showPage(OnboardingPages.schedule)
            }
        }
        .onAppear {
#if DEBUG
            let defaults = UserDefaults.standard
            if defaults.object(forKey: "ios.native.qaOnboardingPage") != nil {
                scene.onboardingPage = min(
                    OnboardingPages.count - 1,
                    max(0, defaults.integer(forKey: "ios.native.qaOnboardingPage"))
                )
                defaults.removeObject(forKey: "ios.native.qaOnboardingPage")
            }
#endif
        }
    }

    private var welcome: some View {
        OnboardingWelcomePage(preferences: preferences, text: text, animatesEntrance: !visitedPages.contains(OnboardingPages.landing), onContinue: {
            showPage(OnboardingPages.schedule)
        }, onRecover: {
            navigationFeedback += 1
            showsReturningUserSetup = true
        })
    }

    private var glance: some View {
        OnboardingGlancePage(shifts: shifts, text: text,
                            referenceDate: journeyReferenceDate, onFinish: onFinish, onContinue: {
            showPage(OnboardingPages.plus)
        }, surface: $glanceSurface)
    }

    /// Hours, weekdays, or no fixed schedule.
    private var schedulePage: some View {
        OnboardingSchedulePage(preferences: preferences, shifts: shifts, text: text) {
            Task {
                await preferences.applyOnboardingReminderDefaultsIfNeeded().value
                showPage(OnboardingPages.reminders)
            }
        }
    }

    /// What that schedule will do, now that lunch and reminders are set, and
    /// where the rest of the setup lives.
    private var readyPage: some View {
        OnboardingReadyPage(preferences: preferences, shifts: shifts, text: text,
                            referenceDate: journeyReferenceDate,
                            animatesEntrance: !visitedPages.contains(OnboardingPages.ready), onFinish: onFinish) {
            showPage(OnboardingPages.glance)
        }
    }


    private var remindersNeedPermission: Bool {
        preferences.notificationMode != .off
            || preferences.microBreakEnabled
            || (preferences.lunchEnabled && (preferences.lunchStartReminderEnabled || preferences.lunchEndReminderEnabled))
    }

    private func showPage(_ page: Int, reverse: Bool = false, feedback: Bool = true) {
        if feedback { navigationFeedback += 1 }
        continuesCountdown = Set([scene.onboardingPage, page]) == Set([OnboardingPages.ready, OnboardingPages.glance])
        if page == OnboardingPages.ready && !continuesCountdown { journeyReferenceDate = .now }
        visitedPages.insert(scene.onboardingPage)
        goingBack = reverse
        withAnimation(pageAnimation) {
            scene.onboardingPage = page
        }
    }

    private func goBack() {
        guard let previous = OnboardingPages.previous(from: scene.onboardingPage) else { return }
        showPage(previous, reverse: true)
    }

    /// Moves on first, then asks. The system prompt still lands right after
    /// the page that explains it, over the summary of the very reminders it
    /// is for. Waiting for the answer before moving tied the button to a
    /// system sheet the app cannot see: when the prompt was slow or appeared
    /// on another display (iPhone Duo), Continue did nothing, and every
    /// further tap queued another request.
    private func advanceFromReminders() {
        navigationFeedback += 1
        showPage(OnboardingPages.ready, feedback: false)
        guard remindersNeedPermission else { return }
        Task { _ = await notifications.request() }
    }

    private var pageAnimation: Animation {
        reduceMotion ? OWCMotion.reduced : (continuesCountdown ? OWCMotion.onboardingContinuity : OWCMotion.onboardingPage)
    }

    private var pageTransition: AnyTransition {
        if reduceMotion || [OnboardingPages.ready, OnboardingPages.glance].contains(scene.onboardingPage) { return .opacity }
        return goingBack ? Self.backTransition : Self.forwardTransition
    }
}

private struct OnboardingWelcomePage: View {
    @Bindable var preferences: PreferencesStore
    let text: AppText
    let animatesEntrance: Bool
    let onContinue: () -> Void
    let onRecover: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var arrived = false

    var body: some View {
        OnboardingPageScaffold(page: OnboardingPages.landing, showsPageIndicator: false) { size in
            content(availableHeight: size.height)
        } footer: {
            if !dynamicTypeSize.isAccessibilitySize { recoveryButton }
            OnboardingDots(page: OnboardingPages.landing)
            Button(text.t("onboardingSetMyShift"), action: onContinue)
                .buttonStyle(OWCPrimaryButtonStyle())
        }
        .onAppear { arrived = true }
    }

    private func content(availableHeight: CGFloat) -> some View {
        let compact = availableHeight < 550
        return VStack(spacing: 0) {
            Spacer(minLength: 12)
            CelebratingBrandMark(
                entranceRotation: .degrees(arrived || reduceMotion || !animatesEntrance ? 0 : -120)
            )
                .frame(width: compact ? 120 : 168, height: compact ? 120 : 168)
                .animation(reduceMotion ? nil : OWCMotion.welcomeHand, value: arrived)
                .welcomeArrival(arrived, index: 0, reduceMotion: reduceMotion || !animatesEntrance)
            Text(verbatim: OWCBrand.shortName)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.top, compact ? 18 : 26)
                .welcomeArrival(arrived, index: 1, reduceMotion: reduceMotion || !animatesEntrance)
            Text(text.t("landingTagline"))
                .font(.largeTitle.bold())
                .tracking(-0.8)
                .foregroundStyle(OWCDesign.primary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .welcomeArrival(arrived, index: 2, reduceMotion: reduceMotion || !animatesEntrance)

            Text(text.t("onboardingOfflineBody"))
                .font(.callout)
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, compact ? 18 : 24)
                .welcomeArrival(arrived, index: 3, reduceMotion: reduceMotion || !animatesEntrance)
            if dynamicTypeSize.isAccessibilitySize {
                recoveryButton.padding(.top, 24)
            }
            Spacer(minLength: 16)

        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 560)
    }

    private var recoveryButton: some View {
        Button(text.t("firstRunQuickSetup"), action: onRecover)
            .font(.body.weight(.semibold))
            .foregroundStyle(OWCDesign.accent)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
    }

}

private extension View {
    func welcomeArrival(_ arrived: Bool, index: Int, reduceMotion: Bool) -> some View {
        opacity(arrived || reduceMotion ? 1 : 0)
            .offset(y: arrived || reduceMotion ? 0 : 12)
            .animation(
                reduceMotion ? nil : OWCMotion.welcomeArrival.delay(Double(index) * OWCMotion.welcomeStagger),
                value: arrived
            )
    }
}

/// The pages, in order. One list rather than a count repeated at every call
/// site: the indicator, the QA jump and the "which page is last" question all
/// read from here, so adding a page cannot leave one of them behind.
///
/// Four setup pages, followed by two optional tours. Every page from Ready
/// onward can finish setup directly; purchasing is always an explicit action.
enum OnboardingPages {
    static let landing = 0
    static let schedule = 1
    static let reminders = 2
    static let ready = 3
    static let glance = 4
    static let plus = 5
    /// Highest page index plus one.
    static let count = 6

    static let sequence = [landing, schedule, reminders, ready, glance, plus]

    static func next(from page: Int) -> Int? {
        guard let index = sequence.firstIndex(of: page), index + 1 < sequence.count else { return nil }
        return sequence[index + 1]
    }

    static func previous(from page: Int) -> Int? {
        guard let index = sequence.firstIndex(of: page), index > 0 else { return nil }
        return sequence[index - 1]
    }
}

/// One onboarding page: content that scrolls when it does not fit, under the
/// page's controls pinned to the bottom.
///
/// `minHeight` is the visible height rather than leaving it to the scroll view,
/// which proposes unbounded height and would collapse the `Spacer`s the pages
/// use to centre themselves. A page that fits lays out exactly as before and
/// does not scroll; one that does not scrolls under the bar, which the system
/// softens with its scroll-edge effect instead of a hard cut.
struct OnboardingPageScaffold<Content: View, Footer: View>: View {
    let page: Int
    var showsPageIndicator = true
    @ViewBuilder var content: (CGSize) -> Content
    @ViewBuilder var footer: Footer

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content(proxy.size)
                    // `maxWidth: .infinity` centres the page: GeometryReader
                    // aligns its child to the top leading corner, and pages
                    // that cap themselves at 560 were otherwise pinned left
                    // on iPad.
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            // UIScrollView's default fill is systemBackground — pure white in
            // light mode, and a mismatch for every page here. While the number
            // pad is dismissing, that white showed through the strip it
            // uncovered before the content caught up.
            .scrollContentBackground(.hidden)
            .transformAnchorPreference(key: OnboardingClockAnchorKey.self, value: .bounds) { anchors, viewport in
                anchors[page + OnboardingClockAnchorKey.viewportOffset] = viewport
            }
        }
        // Room for the floating back control, so a title cannot sit under it
        // and content that scrolls up passes under the same soft edge.
        .safeAreaBar(edge: .top) {
            if page != OnboardingPages.landing {
                Color.clear.frame(height: 36)
            }
        }
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 16) {
                if showsPageIndicator && page <= OnboardingPages.ready { OnboardingDots(page: page) }
                footer
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
            .frame(maxWidth: 560)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }
}

/// Always centred in the page's column.
///
/// A bare `HStack` takes its intrinsic width and lets whatever stack it sits in
/// decide where that goes, so the dots drifted from page to page: centred
/// inside the pages built on a centred `VStack`, hard left inside the ones
/// built on `VStack(alignment: .leading)`. The indicator belongs in the same
/// place on every page — it is the one element that is supposed to look
/// identical throughout, being the thing that measures progress across them.
struct OnboardingDots: View {
    let page: Int

    private var pages: [Int] { Array(OnboardingPages.sequence.prefix(4)) }

    var body: some View {
        let current = pages.firstIndex(of: page) ?? 0
        HStack(spacing: 7) {
            ForEach(Array(pages.enumerated()), id: \.offset) { index, _ in
                Capsule()
                    .fill(index == current ? OWCDesign.accent : OWCDesign.control)
                    .frame(width: index == current ? 20 : 7, height: 7)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(current + 1) / \(pages.count)")
    }
}

private struct OnboardingSchedulePage: View {
    @Environment(SceneState.self) private var scene
    @Bindable var preferences: PreferencesStore
    let shifts: ShiftSessionStore
    let text: AppText
    private var session: ShiftSession { shifts.session }
    let onContinue: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var timeField: SetupTimeField?
    @State private var timeDraft = SettingsFieldDraft(0)
    @State private var showsHolidayRegions = false

    private var holidayRegion: String {
        scene.onboardingHolidayRegionIdentifier
            ?? HolidayCalendar.shared.defaultRegionIdentifier() ?? ""
    }

    /// Just the region: unlike Settings, where an untouched suggestion is not
    /// yet applied, setup applies this one when it finishes.
    private var holidayRegionLabel: String {
        guard !holidayRegion.isEmpty else { return text.t("holidayCalendarOff") }
        return HolidayCalendar.shared.regionName(holidayRegion, locale: preferences.locale)
    }

    var body: some View {
        OnboardingPageScaffold(page: OnboardingPages.schedule) { _ in
            form
        } footer: {
            Button(text.t("continue")) {
                if preferences.scheduleMode == .classic, preferences.workdays.isEmpty {
                    let command = preferences.applySetupScheduleChange(
                        ScheduleFieldChange(workdays: [1, 2, 3, 4, 5])
                    )
                    Task {
                        _ = await command.value
                        onContinue()
                    }
                } else {
                    onContinue()
                }
            }
            .buttonStyle(OWCPrimaryButtonStyle())
        }
        .sheet(isPresented: $showsHolidayRegions) {
            HolidayRegionPicker(text: text, locale: preferences.locale, selection: holidayRegion) {
                scene.onboardingHolidayRegionIdentifier = $0
                showsHolidayRegions = false
            }
        }
        .sheet(item: $timeField) { field in
            OWCSetupTimePickerSheet(
                session: session,
                text: text,
                title: text.t(field == .start ? "startTime" : "endTime"),
                minutes: $timeDraft.value
            )
            .presentationDetents([.medium])
            .onAppear { timeDraft.accept(field == .start ? preferences.startMinutes : preferences.endMinutes) }
            .onChange(of: field == .start ? preferences.startMinutes : preferences.endMinutes) { _, minutes in
                timeDraft.receive(minutes)
            }
            .onDisappear {
                guard timeDraft.hasChanges else { return }
                preferences.applySetupScheduleChange(field == .start
                    ? ScheduleFieldChange(startMinutes: timeDraft.value)
                    : ScheduleFieldChange(endMinutes: timeDraft.value))
            }
        }
        .onAppear {
            if preferences.workdays.isEmpty {
                preferences.applySetupScheduleChange(ScheduleFieldChange(workdays: [1, 2, 3, 4, 5]))
            }
        }
        .sensoryFeedback(.selection, trigger: preferences.scheduleMode)
    }

    /// Same cap as the other pages. The scaffold's `minHeight` is what lets
    /// the Spacers centre this form; a second `frame(maxWidth: .infinity)`
    /// here would report the VStack's ideal height instead, and the form
    /// would sit against the top again — the iPad landscape complaint.
    private var form: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            Text(text.t("onboardingScheduleTitle"))
                .font(.title.bold())
                .tracking(-0.6)
                .multilineTextAlignment(.center)
            Text(text.t("onboardingScheduleBody"))
                .font(.callout)
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 10)

            HStack(alignment: .timeChipCenter, spacing: 4) {
                ShiftHeroTimeButton(
                    title: text.t("startTime"),
                    time: session.timeString(preferences.startMinutes)
                ) { timeField = .start }
                Text(verbatim: "—")
                    .font(.title3)
                    .foregroundStyle(OWCDesign.tertiary)
                    .alignmentGuide(.timeChipCenter) { $0[VerticalAlignment.center] }
                    .accessibilityHidden(true)
                ShiftHeroTimeButton(
                    title: text.t("endTime"),
                    time: session.timeString(preferences.endMinutes)
                ) { timeField = .end }
            }
            .environment(\.layoutDirection, .leftToRight)
            .padding(.top, 18)

            OnboardingShiftRibbon(shifts: shifts, text: text)
                .padding(.top, 20)

            OWCGroupCard {
                OWCRow(title: text.t("extendedPattern"), isLast: true) {
                    OWCDetailAccessory(text: text.t(scheduleModeKey))
                }
                .owcRowMenu(accessibilityLabel: text.t("extendedPattern")) {
                    modeOption(.classic, titleKey: "scheduleClassic")
                    modeOption(.alternating, titleKey: "scheduleAlternating")
                    modeOption(.rotation, titleKey: "scheduleRotation")
                    modeOption(.off, titleKey: "scheduleManualTimer")
                }
                .accessibilityHint(text.t("landingFeature1Title"))
            }
            .padding(.top, 22)

            OnboardingScheduleDetailsView(preferences: preferences, text: text)
                .padding(.top, 14)

            Text(text.t(scheduleDescriptionKey))
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)

            // One row, as in Work Hours & Schedule: the picker it opens already
            // offers Off. A separate switch above it made this the tallest
            // card on the page and pushed Continue below the fold on a 6.3"
            // phone, where a tap aimed at it landed on this row instead.
            OWCGroupCard {
                Button { showsHolidayRegions = true } label: {
                    HStack(spacing: 12) {
                        Text(text.t("holidayCalendar"))
                        Spacer(minLength: 8)
                        Text(holidayRegionLabel)
                            .foregroundStyle(OWCDesign.secondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.forward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(OWCDesign.tertiary)
                    }
                    .foregroundStyle(OWCDesign.primary)
                    .padding(16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(OWCRowButtonStyle())
                .accessibilityElement(children: .combine)
            }
            .padding(.top, 14)

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 560)
    }

    private var scheduleModeKey: String {
        switch preferences.scheduleMode {
        case .classic: "scheduleClassic"
        case .alternating: "scheduleAlternating"
        case .rotation: "scheduleRotation"
        case .off: "scheduleManualTimer"
        }
    }

    private var scheduleDescriptionKey: String {
        switch preferences.scheduleMode {
        case .classic: "scheduleClassicDescription"
        case .alternating: "scheduleAlternatingDescription"
        case .rotation: "scheduleRotationDescription"
        case .off: "scheduleOffDescription"
        }
    }

    private func modeOption(_ mode: WorkScheduleMode, titleKey: String) -> some View {
        Button {
            preferences.applySetupScheduleChange(ScheduleFieldChange(
                workdays: mode == .classic && preferences.workdays.isEmpty ? [1, 2, 3, 4, 5] : nil,
                scheduleMode: mode
            ))
        } label: {
            Label(text.t(titleKey), systemImage: preferences.scheduleMode == mode ? "checkmark" : "calendar")
        }
    }


}

/// The radio mark on a schedule-mode row.
///
/// One `Image` whose symbol changes, plus a content transition, rather than two
/// images swapped by a conditional. The row highlight responds on touch-down;
/// on commit, `.symbolEffect(.replace)` gives the circle-to-checkmark change the
/// shape SF Symbols draws deliberately instead of cross-fading two glyphs in
/// one 20 pt slot.
struct ScheduleModeMark: View {
    let selected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(selected ? OWCDesign.accent : OWCDesign.tertiary)
            .contentTransition(.symbolEffect(.replace))
            .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.selection, value: selected)
    }
}
