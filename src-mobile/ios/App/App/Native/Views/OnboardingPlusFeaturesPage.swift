import SwiftUI

/// DoneAt Plus, shown rather than listed: one page whose stage plays through
/// four read-only demos — records, reports, focus, and time off with alarms.
/// It replaces three Plus pages; the welcome flow was long enough already.
///
/// The values are illustrative and stay inside onboarding; nothing here
/// starts a timer or writes a record. Each demo replays its small entrance
/// when it comes on stage, so a swipe back shows it again rather than a
/// finished still.
struct OnboardingPlusShowcasePage: View {
    let text: AppText
    let onContinue: () -> Void
    let onLearnMore: () -> Void

    enum Slide: Int, CaseIterable, Identifiable {
        case records, reports, focus, rest
        var id: Int { rawValue }
    }

    /// Long enough to read a caption and watch its demo land, short enough
    /// that the four play through while the user is still looking.
    static let dwellSeconds = 4.2
    /// `owcShowcaseLift` blurs 14 pt and drops 6.
    private static let shadowRoom: CGFloat = 24

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var stageHeight: CGFloat = 268
    @State private var slide = Slide.records
    /// Stops for good the first time the user picks a demo themselves: from
    /// then on the stage is theirs.
    @State private var autoplays = true
    @State private var dwell: Double = 0
    @State private var continueFeedback = 0
    @State private var selectionFeedback = 0

    var body: some View {
        OnboardingPageScaffold(page: OnboardingPages.plus, showsPageIndicator: false) { _ in
            content
        } footer: {
            if !dynamicTypeSize.isAccessibilitySize { progress }
            if !dynamicTypeSize.isAccessibilitySize { exploreButton }
            Button(text.t("onboardingStartUsing")) {
                continueFeedback += 1
                onContinue()
            }
            .buttonStyle(OWCPrimaryButtonStyle())
        }
        .sensoryFeedback(.success, trigger: continueFeedback)
        .sensoryFeedback(.selection, trigger: selectionFeedback)
        .task(id: canAutoplay) {
            if canAutoplay { await play() }
            else { stopProgress() }
        }
    }

    private var canAutoplay: Bool {
        autoplays && !reduceMotion && !voiceOverEnabled
            && !dynamicTypeSize.isAccessibilitySize && scenePhase == .active
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            OnboardingPlusBadge(text: text)
            Text(text.t("onboardingPlusShowcaseTitle"))
                .font(.title.bold())
                .tracking(-0.6)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            if dynamicTypeSize.isAccessibilitySize {
                // Paging a stage at these sizes clips the demos; every one is
                // simply listed, already played.
                VStack(spacing: 28) {
                    ForEach(Slide.allCases) { item in
                        slideView(item, isActive: true, fixedHeight: false)
                    }
                }
                .padding(.top, 22)
                exploreButton.padding(.top, 24)
            } else {
                carousel
                    .padding(.top, 18)
            }

            Spacer(minLength: 16)

        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 560)
    }

    private var exploreButton: some View {
        Button(text.t("onboardingExplorePlus"), action: onLearnMore)
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(minHeight: 44)
    }

    // MARK: - Stage

    private var carousel: some View {
        VStack(spacing: 12) {
            TabView(selection: Binding(get: { slide }, set: { item in
                // The system pager also writes its current selection during
                // layout and after a programmatic page change.
                guard item != slide else { return }
                selectSlide(item)
            })) {
                ForEach(Slide.allCases) { item in
                    slideView(item, isActive: slide == item, fixedHeight: true)
                        // Room for the cards' lift shadow inside the page:
                        // the pager clips to its bounds, and a cut shadow
                        // reads as a grey slab behind the stage.
                        .padding(.horizontal, Self.shadowRoom)
                        .padding(.vertical, Self.shadowRoom)
                        .tag(item)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: stageHeight + captionHeight + 16 + Self.shadowRoom * 2)
            .padding(.vertical, -Self.shadowRoom)
        }
        .padding(.horizontal, -Self.shadowRoom)
        .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in
            autoplays = false
            stopProgress()
        })
    }

    @ScaledMetric(relativeTo: .callout) private var captionHeight: CGFloat = 76

    private func slideView(_ item: Slide, isActive: Bool, fixedHeight: Bool) -> some View {
        VStack(spacing: 16) {
            Group {
                switch item {
                case .records: OnboardingRecordsDemo(text: text, isActive: isActive)
                case .reports: OnboardingReportsDemo(text: text, isActive: isActive)
                case .focus: OnboardingFocusDemo(text: text, isActive: isActive)
                case .rest: OnboardingRestDemo(text: text, isActive: isActive)
                }
            }
            .frame(maxWidth: 440)
            .frame(height: fixedHeight ? stageHeight : nil)

            // Two lines reserved on the stage, so captions of different
            // lengths do not move the demos above them while paging.
            Text(caption(item))
                .font(.callout.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)
        }
        .accessibilityElement(children: .contain)
    }

    private func caption(_ item: Slide) -> String {
        switch item {
        case .records: text.t("onboardingPlusRecordsTitle")
        case .reports: text.t("onboardingPlusReportsTitle")
        case .focus: text.t("onboardingPlusFocusTitle")
        case .rest: text.t("onboardingPlusRestTitle")
        }
    }

    /// Story-style: each segment fills while its demo is on stage, and any
    /// segment jumps straight to its demo.
    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Slide.allCases) { item in
                Button {
                    selectSlide(item)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: slideIcon(item)).font(.body)
                        Capsule()
                        .fill(OWCDesign.control)
                        .overlay(alignment: .leading) {
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(OWCDesign.accent)
                                    .frame(width: proxy.size.width * fill(for: item))
                            }
                        }
                        .frame(width: 44, height: 3)
                    }
                    .frame(width: 58, height: 48)
                    .foregroundStyle(slide == item ? OWCDesign.accent : OWCDesign.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption(slide))
        .accessibilityValue("\(slide.rawValue + 1) / \(Slide.allCases.count)")
        .accessibilityAdjustableAction { direction in
            let next: Slide? = switch direction {
            case .increment: Slide(rawValue: slide.rawValue + 1)
            case .decrement: Slide(rawValue: slide.rawValue - 1)
            @unknown default: nil
            }
            if let next { selectSlide(next) }
        }
    }

    private func slideIcon(_ item: Slide) -> String {
        switch item {
        case .records: "calendar"
        case .reports: "chart.bar.xaxis"
        case .focus: "stopwatch"
        case .rest: "sun.horizon"
        }
    }

    private func fill(for item: Slide) -> Double {
        if item.rawValue < slide.rawValue { return 1 }
        return item == slide ? dwell : 0
    }

    /// Fills the current segment over the dwell, then hands the stage to the
    /// next demo. Stops on the last one rather than looping: by then the user
    /// has seen all four and the button is the next thing to look at. One
    /// loop owns the clock; the first swipe or tap ends it.
    private func play() async {
        while canAutoplay, !Task.isCancelled {
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { dwell = 0 }
            await Task.yield()
            guard !Task.isCancelled, canAutoplay else { return }
            withAnimation(.linear(duration: Self.dwellSeconds)) { dwell = 1 }
            do { try await Task.sleep(for: .seconds(Self.dwellSeconds)) }
            catch { return }
            guard !Task.isCancelled, canAutoplay,
                  let next = Slide(rawValue: slide.rawValue + 1)
            else { return }
            withAnimation(OWCMotion.navigation) { slide = next }
        }
    }

    private func selectSlide(_ item: Slide) {
        autoplays = false
        stopProgress()
        guard item != slide else { return }
        selectionFeedback += 1
        withAnimation(reduceMotion ? OWCMotion.reduced : OWCMotion.navigation) { slide = item }
    }

    private func stopProgress() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { dwell = 1 }
    }

}

struct OnboardingPlusBadge: View {
    let text: AppText

    var body: some View {
        Label(text.t("plusSection"), systemImage: "star.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(OWCDesign.accent)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .frame(minHeight: 28)
            .background(OWCDesign.accent.opacity(0.12), in: Capsule())
    }
}

/// Plays a demo's entrance whenever it comes on stage and resets it off
/// stage, so it is ready to play again. Reduce Motion shows the end state.
private struct DemoEntrance: ViewModifier {
    let isActive: Bool
    @Binding var shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .task(id: isActive) {
                guard isActive || reduceMotion else {
                    shown = false
                    return
                }
                // Start after insertion; the surrounding content height is
                // independent of the decorative entrance animation.
                await Task.yield()
                guard !Task.isCancelled else { return }
                shown = true
            }
            .onChange(of: reduceMotion) { _, reduced in
                if reduced { shown = true }
            }
    }
}

private extension View {
    func demoEntrance(_ isActive: Bool, shown: Binding<Bool>) -> some View {
        modifier(DemoEntrance(isActive: isActive, shown: shown))
    }

    /// One element of a demo arriving `index` beats after the first.
    func demoStep(_ shown: Bool, index: Int, reduceMotion: Bool) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .animation(
                reduceMotion ? nil : OWCMotion.reveal.delay(0.12 + Double(index) * 0.09),
                value: shown
            )
    }
}

// MARK: - Records

/// The planned day under the lived one, then the same work on a life line.
struct OnboardingRecordsDemo: View {
    let text: AppText
    let isActive: Bool
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 12) {
            recordsCard
            lifeCard
        }
        .demoEntrance(isActive, shown: $shown)
    }

    private var recordsCard: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 14) {
                Label(text.t("recordsTitle"), systemImage: "calendar")
                    .font(.headline)
                timelineRow(title: text.t("recordsPlanned"), time: "09:00–18:00", isPlanned: true)
                timelineRow(title: text.t("onboardingPlusRecordsActual"), time: "09:08–18:42", isPlanned: false)
            }
            .padding(16)
        }
        .owcShowcaseLift()
    }

    private var lifeCard: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(text.t("lifeProfileTitle"), systemImage: "person.crop.circle")
                    .font(.headline)
                GeometryReader { proxy in
                    let gap: CGFloat = 3
                    ZStack(alignment: .leading) {
                        HStack(spacing: gap) {
                            lifeSegment(OWCDesign.lifeChildhood, width: proxy.size.width * 0.18)
                            lifeSegment(OWCDesign.lifeStudy, width: proxy.size.width * 0.16)
                            lifeSegment(OWCDesign.lifeWork, width: proxy.size.width * 0.42)
                            lifeSegment(OWCDesign.lifeRetirement, width: proxy.size.width * 0.24 - gap * 3)
                        }
                        Capsule()
                            .fill(OWCDesign.primary)
                            .frame(width: 2, height: 18)
                            // The present walks along the line to where it is.
                            .offset(x: proxy.size.width * (shown ? 0.56 : 0.18))
                            .animation(reduceMotion ? nil : OWCMotion.reveal.delay(0.4), value: shown)
                    }
                }
                .frame(height: 18)
                .accessibilityHidden(true)

                (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())) {
                    Text(text.t("lifeStageChildhood"))
                    Spacer()
                    Text(text.t("lifeStagePresent"))
                    Spacer()
                    Text(text.t("lifeStageRetirement"))
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(OWCDesign.secondary)
            }
            .padding(16)
        }
        .owcShowcaseLift()
        .demoStep(shown, index: 2, reduceMotion: reduceMotion)
    }

    private func timelineRow(title: String, time: String, isPlanned: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout())) {
                Text(title).font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                Text(verbatim: time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(OWCDesign.secondary)
                    .environment(\.layoutDirection, .leftToRight)
            }

            GeometryReader { proxy in
                let gap = proxy.size.width * 0.08
                HStack(spacing: gap) {
                    workSegment(isPlanned: isPlanned)
                        .frame(width: proxy.size.width * 0.41)
                    workSegment(isPlanned: isPlanned)
                        .frame(width: proxy.size.width * (isPlanned ? 0.43 : 0.39))
                    if !isPlanned {
                        Capsule()
                            .fill(OWCDesign.recordsOvertime)
                            .frame(maxWidth: .infinity)
                    }
                }
                // The lived day draws itself across the plan above it.
                .scaleEffect(x: isPlanned || shown ? 1 : 0.001, anchor: .leading)
                .animation(
                    reduceMotion ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 0.9).delay(0.2),
                    value: shown
                )
            }
            .frame(height: 10)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private func workSegment(isPlanned: Bool) -> some View {
        Capsule()
            .fill(OWCDesign.recordsWork.opacity(isPlanned ? 0.24 : 1))
            .overlay {
                if isPlanned {
                    OWCHatchPattern(spacing: 4)
                        .stroke(OWCDesign.recordsWork.opacity(0.7), lineWidth: 0.8)
                        .clipShape(Capsule())
                }
            }
    }

    private func lifeSegment(_ color: Color, width: CGFloat) -> some View {
        Capsule().fill(color).frame(width: max(0, width))
    }
}

// MARK: - Reports

/// A still from a weekly report, on the report's own plum stage: the week's
/// hours rising day by day, with the overtime on top.
struct OnboardingReportsDemo: View {
    let text: AppText
    let isActive: Bool
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Work and overtime hours, Monday to Sunday.
    private let days: [(work: Double, overtime: Double)] = [
        (8, 0.5), (8, 0), (8, 1.5), (8, 0), (7, 0), (0, 0), (0, 0),
    ]
    private var total: Double { days.reduce(0) { $0 + $1.work + $1.overtime } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(text.t("reportWeekly"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ReportPalette.cream.opacity(0.7))
                Spacer()
                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundStyle(ReportPalette.cream.opacity(0.7))
            }
            Text(text.t("reportHeadlineOvertime", values: ["duration": text.formatHours(2)]))
                .font(.headline)
                .foregroundStyle(ReportPalette.cream)
                .padding(.top, 10)
            Text(text.formatHours(shown ? total : 0))
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(ReportPalette.orange)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.9).delay(0.2), value: shown)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 2)

            Spacer(minLength: 12)
            chart
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(colors: [ReportPalette.plum, ReportPalette.deep], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: OWCDesign.cardRadius, style: .continuous)
        )
        .owcShowcaseLift()
        .environment(\.colorScheme, .dark)
        .demoEntrance(isActive, shown: $shown)
    }

    private var chart: some View {
        let labels = text.weekdayLabels()
        let peak = days.map { $0.work + $0.overtime }.max() ?? 1
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                VStack(spacing: 6) {
                    VStack(spacing: 2) {
                        if day.overtime > 0 {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(LinearGradient(gradient: ReportPalette.overtime, startPoint: .bottom, endPoint: .top))
                                .frame(height: 96 * day.overtime / peak)
                        }
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(day.work > 0
                                  ? AnyShapeStyle(LinearGradient(gradient: ReportPalette.work, startPoint: .bottom, endPoint: .top))
                                  : AnyShapeStyle(ReportPalette.cream.opacity(0.12)))
                            .frame(height: day.work > 0 ? 96 * day.work / peak : 4)
                    }
                    .frame(height: 96, alignment: .bottom)
                    .scaleEffect(y: shown ? 1 : 0.02, anchor: .bottom)
                    .animation(
                        reduceMotion ? nil : OWCMotion.reveal.delay(0.15 + Double(index) * 0.06),
                        value: shown
                    )
                    Text(labels[index % labels.count])
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(ReportPalette.cream.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Focus

/// One task's round counting down inside the shift, with the break that will
/// wait for the user rather than start on its own.
struct OnboardingFocusDemo: View {
    let text: AppText
    let isActive: Bool
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            OWCGroupCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label(text.t("onboardingPlusFocusTask"), systemImage: FocusTaskIcon.focus.systemName)
                        .font(.headline)
                    Text(verbatim: shown ? "09:00" : "25:00")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.9).delay(0.2), value: shown)
                        .environment(\.layoutDirection, .leftToRight)
                    ProgressView(value: shown ? 0.64 : 0.04)
                        .tint(OWCDesign.accent)
                        .animation(reduceMotion ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 1).delay(0.2), value: shown)
                    Text(text.t("focusActivityThenBreak", values: ["count": text.formatCount(5)]))
                        .font(.footnote)
                        .foregroundStyle(OWCDesign.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .owcShowcaseLift()

            OWCGroupCard {
                HStack(spacing: 12) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(OWCDesign.accent)
                        .frame(width: 34, height: 34)
                        .background(OWCDesign.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(text.t("focusShortBreak"))
                            .font(.subheadline.weight(.semibold))
                        Text(text.t("onboardingPlusFocusBreakBody"))
                            .font(.footnote)
                            .foregroundStyle(OWCDesign.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
            }
            .owcShowcaseLift()
            .demoStep(shown, index: 3, reduceMotion: reduceMotion)
        }
        .demoEntrance(isActive, shown: $shown)
    }
}

// MARK: - Time off and alarms

/// Three days of leave bridging two holidays into nine days off, and the
/// alarm an hour before a day shift, as the alarm itself words it.
struct OnboardingRestDemo: View {
    let text: AppText
    let isActive: Bool
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum Mark { case holiday, leave }
    private let days: [Mark] = [.holiday, .holiday, .holiday, .leave, .leave, .leave, .holiday, .holiday, .holiday]

    var body: some View {
        VStack(spacing: 12) {
            leaveCard
            alarmCard
                .demoStep(shown, index: 4, reduceMotion: reduceMotion)
        }
        .demoEntrance(isActive, shown: $shown)
    }

    private var leaveCard: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 14) {
                Label(text.t("leaveTitle"), systemImage: "suitcase")
                    .font(.headline)
                HStack(spacing: 4) {
                    ForEach(Array(days.enumerated()), id: \.offset) { index, mark in
                        let filled = mark == .leave && shown
                        Image(systemName: mark == .leave ? "suitcase.fill" : "flag")
                            .font(.system(size: 12))
                            .foregroundStyle(filled ? OWCDesign.accent : OWCDesign.secondary)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(
                                filled ? OWCDesign.accent.opacity(0.16) : OWCDesign.control,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .scaleEffect(filled || reduceMotion || mark == .holiday ? 1 : 0.86)
                            // The leave days fill in one by one, bridging the gap.
                            .animation(
                                reduceMotion ? nil : OWCMotion.reveal.delay(0.25 + Double(max(0, index - 3)) * 0.12),
                                value: shown
                            )
                    }
                }
                .accessibilityHidden(true)
                (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())) {
                    Text(text.t("leaveDaysOff", count: 9))
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(text.t("leaveUses", values: ["days": text.formatDays(3)]))
                        .font(.subheadline)
                        .foregroundStyle(OWCDesign.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .owcShowcaseLift()
    }

    private var alarmCard: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(text.t("shiftAlarmsTitle"), systemImage: "alarm")
                    .font(.headline)
                (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))) {
                    Text(clock(hour: 7))
                        .font(.system(.title, design: .rounded).weight(.semibold).monospacedDigit())
                    Spacer(minLength: 8)
                    Text(text.t("shiftAlarmTitle", values: [
                        "shift": text.t("extendedDefaultWorkShift"), "time": clock(hour: 8),
                    ]))
                    .font(.subheadline)
                    .foregroundStyle(OWCDesign.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .owcShowcaseLift()
    }

    private func clock(hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return text.formatTime(date)
    }
}
