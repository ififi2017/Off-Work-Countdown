import SwiftUI

/// What Plus adds, shown rather than listed: one illustrative scene per page,
/// swiped through by hand above the plans. Nothing advances on its own, so the
/// price page stays still while someone decides.
struct PlusFeatureCarousel: View {
    let text: AppText
    var initialPage: Page = .reports
    @State private var current: Page?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Page: Int, CaseIterable, Identifiable {
        case reports, records, rest, focus, widgets
        var id: Int { rawValue }

        var captionKey: String {
            switch self {
            case .reports: "onboardingPlusReportsTitle"
            case .records: "onboardingPlusRecordsTitle"
            case .rest: "onboardingPlusRestTitle"
            case .focus: "onboardingPlusFocusTitle"
            case .widgets: "plusWidgetsSlideTitle"
            }
        }
    }

    var body: some View {
        let shown = current ?? initialPage
        VStack(spacing: 12) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Page.allCases) { page in
                        scene(page, isActive: page == shown)
                            .padding(.horizontal, 2)
                            .containerRelativeFrame(.horizontal)
                            .id(page)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $current)
            .onAppear { if current == nil { current = initialPage } }

            Text(text.t(shown.captionKey))
                .font(.callout.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .id(shown)
                .transition(.opacity)
                .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.selection, value: shown)

            HStack(spacing: 2) {
                ForEach(Page.allCases) { page in
                    Button {
                        withAnimation(reduceMotion ? OWCMotion.reduced : OWCMotion.phase) { current = page }
                    } label: {
                        Capsule()
                            .fill(page == shown ? OWCDesign.accent : OWCDesign.tertiary.opacity(0.5))
                            .frame(width: page == shown ? 18 : 7, height: 7)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(text.t(page.captionKey))
                    .accessibilityAddTraits(page == shown ? .isSelected : [])
                }
            }
            .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.selection, value: shown)

            Text(text.t("plusIllustration"))
                .font(.caption).foregroundStyle(OWCDesign.secondary)
        }
    }

    @ViewBuilder
    private func scene(_ page: Page, isActive: Bool) -> some View {
        switch page {
        case .reports: OnboardingReportsDemo(text: text, isActive: isActive)
        case .records: OnboardingRecordsDemo(text: text, isActive: isActive)
        case .rest: OnboardingRestDemo(text: text, isActive: isActive)
        case .focus: OnboardingFocusDemo(text: text, isActive: isActive)
        case .widgets: PlusWidgetsDemo(text: text)
        }
    }
}

/// The Plus widgets with sample figures, as WidgetKit would draw them.
private struct PlusWidgetsDemo: View {
    let text: AppText

    var body: some View {
        let now = Date.now
        let samples = WidgetGallerySamples(now: now, locale: text.languageCode, text: text)
        HStack(spacing: 12) {
            WidgetGalleryFrame(family: .systemSmall) {
                SummaryWidgetView(familyOverride: .systemSmall, entry: SummaryWidgetEntry(date: now, payload: samples.summary))
            }
            WidgetGalleryFrame(family: .systemSmall) {
                LifeWidgetView(familyOverride: .systemSmall, entry: LifeWidgetEntry(date: now, payload: samples.life))
            }
        }
        .scaleEffect(0.86)
        .frame(height: 170 * 0.86 + 24)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(WidgetGalleryColors.stage, in: RoundedRectangle(cornerRadius: OWCDesign.cardRadius, style: .continuous))
    }
}
