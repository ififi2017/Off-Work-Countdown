import SwiftUI

/// What's new in this release. 3.2.3 is the widget suite, shown as the real
/// widgets with the user's own schedule. A lifetime gift is left on the timer
/// rather than offered here, so this page stays about the update.
struct WhatsNewView: View {
    let shifts: ShiftSessionStore
    let onDismiss: () -> Void
    let onShowWidgets: () -> Void
    @State private var widgets: WidgetGalleryData?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var text: AppText { shifts.text }
    private var plus: PlusEntitlement { shifts.plus }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: "DoneAt \(ReleaseNotes.current)")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(OWCDesign.accent)
                        Text(text.t("whatsNewWidgetsTitle"))
                            .font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    }
                    WidgetSuiteShowcase(data: widgets)
                    VStack(alignment: .leading, spacing: 20) {
                        feature("square.grid.2x2", text.t("whatsNewHomeTitle"), "whatsNewHomeBody")
                        feature("lock", text.t("whatsNewLockTitle"), "whatsNewLockBody")
                        feature("applewatch", "Apple Watch", "whatsNewWatchBody")
                    }
                    VStack(spacing: 8) {
                        Button(text.t("whatsNewHowToAdd"), action: onShowWidgets)
                            .font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                        Button(text.t("whatsNewContinue"), action: onDismiss)
                            .buttonStyle(OWCPrimaryButtonStyle())
                    }
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(OWCDesign.page)
        }
        .tint(OWCDesign.accent)
        .interactiveDismissDisabled()
        .task {
            await plus.checkCurrentEntitlements()
            // Left on the timer, wrapped, for after this page closes.
            plus.inviteUpdateGift()
            if !plus.isAuthorized, plus.products.isEmpty { await plus.loadProducts() }
        }
        .task { widgets = await WidgetGalleryData.load(shifts: shifts) }
    }

    private func feature(_ symbol: String, _ title: String, _ bodyKey: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: symbol).font(.title3).foregroundStyle(OWCDesign.accent)
                    .frame(width: 26).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: title).font(.headline)
                Text(text.t(bodyKey)).font(.subheadline).foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Three free widgets as a Home Screen would hold them: the countdown across
/// the top, the ring and this week beneath, scaled to the page's width.
private struct WidgetSuiteShowcase: View {
    let data: WidgetGalleryData?

    private static let gap: CGFloat = 12
    private static let medium = WidgetGalleryFrame<EmptyView>.size(.systemMedium)
    private static let small = WidgetGalleryFrame<EmptyView>.size(.systemSmall)
    private static let contentHeight = medium.height + gap + small.height

    var body: some View {
        GeometryReader { geometry in
            let scale = min(1, (geometry.size.width - 24) / Self.medium.width)
            Group {
                if let data {
                    VStack(spacing: Self.gap) {
                        WidgetGalleryFrame(family: .systemMedium) {
                            OffWorkCountdownWidgetView(entry: data.countdown.base, familyOverride: .systemMedium)
                        }
                        HStack(spacing: Self.medium.width - 2 * Self.small.width) {
                            WidgetGalleryFrame(family: .systemSmall) {
                                CountdownRingView(familyOverride: .systemSmall, model: CountdownStyleModel(entry: data.countdown))
                            }
                            WidgetGalleryFrame(family: .systemSmall) {
                                WeekProgressView(familyOverride: .systemSmall, entry: CalendarWidgetEntry(date: data.now, payload: data.calendar))
                            }
                        }
                    }
                    .scaleEffect(scale)
                    .transition(.opacity)
                } else {
                    ProgressView()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio((Self.medium.width + 24) / (Self.contentHeight + 24), contentMode: .fit)
        .background(WidgetGalleryColors.stage, in: RoundedRectangle(cornerRadius: OWCDesign.cardRadius, style: .continuous))
        .animation(.smooth(duration: 0.3), value: data == nil)
        .accessibilityHidden(true)
    }
}
