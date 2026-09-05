import SwiftUI

/// Two short, read-only previews of the Plus tools that are easiest to miss
/// when the app opens on its free countdown. The values are illustrative and
/// stay inside onboarding; neither page starts a timer or writes a record.
struct OnboardingPlusRecordsPage: View {
    let store: OffWorkStore
    let onContinue: () -> Void

    var body: some View {
        OnboardingPlusPage(
            store: store,
            title: store.t("onboardingPlusRecordsTitle"),
            body: store.t("onboardingPlusRecordsBody"),
            onContinue: onContinue
        ) {
            VStack(spacing: 14) {
                recordsCard
                lifeCard
            }
        }
    }

    private var recordsCard: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 14) {
                Label(store.t("recordsTitle"), systemImage: "calendar")
                    .font(.headline)

                timelineRow(
                    title: store.t("recordsPlanned"),
                    time: "09:00–18:00",
                    isPlanned: true
                )
                timelineRow(
                    title: store.t("onboardingPlusRecordsActual"),
                    time: "09:08–18:42",
                    isPlanned: false
                )
            }
            .padding(16)
        }
        .owcShowcaseLift()
    }

    private var lifeCard: some View {
        OWCGroupCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(store.t("lifeProfileTitle"), systemImage: "figure.timeline.selection")
                    .font(.headline)
                Text(store.t("onboardingPlusLifeBody"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

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
                            .offset(x: proxy.size.width * 0.56)
                    }
                }
                .frame(height: 18)
                .accessibilityHidden(true)

                HStack {
                    Text(store.t("lifeStageChildhood"))
                    Spacer()
                    Text(store.t("lifeStagePresent"))
                    Spacer()
                    Text(store.t("lifeStageRetirement"))
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(OWCDesign.secondary)
            }
            .padding(16)
        }
        .owcShowcaseLift()
    }

    private func timelineRow(title: String, time: String, isPlanned: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
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
            }
            .frame(height: 10)
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

struct OnboardingPlusFocusPage: View {
    let store: OffWorkStore
    let onContinue: () -> Void

    @State private var phase = DemoPhase.focus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum DemoPhase: String, CaseIterable, Identifiable {
        case focus
        case rest
        var id: String { rawValue }
    }

    var body: some View {
        OnboardingPlusPage(
            store: store,
            title: store.t("onboardingPlusFocusTitle"),
            body: store.t("onboardingPlusFocusBody"),
            onContinue: onContinue
        ) {
            OWCGroupCard {
                VStack(spacing: 16) {
                    Picker(store.t("focusTitle"), selection: $phase) {
                        Text(store.t("focusTitle")).tag(DemoPhase.focus)
                        Text(store.t("focusShortBreak")).tag(DemoPhase.rest)
                    }
                    .pickerStyle(.segmented)

                    ZStack {
                        if phase == .focus {
                            focusPreview
                                .transition(previewTransition)
                        } else {
                            breakPreview
                                .transition(previewTransition)
                        }
                    }
                    .frame(minHeight: 166, alignment: .top)
                    .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.stateEnter, value: phase)
                }
                .padding(16)
            }
            .owcShowcaseLift()
        }
    }

    private var focusPreview: some View {
        preview(
            icon: "timer",
            title: store.t("onboardingPlusFocusTask"),
            duration: "09:00",
            progress: 0.64,
            footnote: store.t("focusActivityThenBreak", values: ["count": "5"])
        )
    }

    private var breakPreview: some View {
        preview(
            icon: "cup.and.saucer.fill",
            title: store.t("focusShortBreak"),
            duration: "05:00",
            progress: 0,
            footnote: store.t("onboardingPlusFocusBreakBody")
        )
    }

    private func preview(
        icon: String,
        title: String,
        duration: String,
        progress: Double,
        footnote: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(OWCDesign.primary)

            Text(verbatim: duration)
                .font(.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit())
                .environment(\.layoutDirection, .leftToRight)

            ProgressView(value: progress)
                .tint(OWCDesign.accent)

            Text(footnote)
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var previewTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
    }
}

private struct OnboardingPlusPage<Demo: View>: View {
    let store: OffWorkStore
    let title: String
    let bodyText: String
    let onContinue: () -> Void
    @ViewBuilder let demo: Demo

    init(
        store: OffWorkStore,
        title: String,
        body: String,
        onContinue: @escaping () -> Void,
        @ViewBuilder demo: () -> Demo
    ) {
        self.store = store
        self.title = title
        bodyText = body
        self.onContinue = onContinue
        self.demo = demo()
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 18)

            Label(store.t("plusSection"), systemImage: "star.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(OWCDesign.accent)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(OWCDesign.accent.opacity(0.12), in: Capsule())

            Text(title)
                .font(.title.bold())
                .tracking(-0.6)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            Text(bodyText)
                .font(.callout)
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            demo
                .frame(maxWidth: 440)
                .padding(.top, 22)

            Spacer(minLength: 16)

            OnboardingDots(
                page: store.onboardingPage,
                includesAllSet: store.scheduleMode != .off
            )
            Button(store.t("continue"), action: onContinue)
                .buttonStyle(OWCPrimaryButtonStyle())
                .padding(.top, 16)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 560)
    }
}
