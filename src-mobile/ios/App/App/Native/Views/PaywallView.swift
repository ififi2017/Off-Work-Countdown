import StoreKit
import SwiftUI
import UIKit

/// The paywall as a page: its own scroll container, plus the shared content.
///
/// `PaywallContent` is the part Plus Settings embeds. The two used to be the
/// same view, so the settings page put one vertical `ScrollView` inside another
/// and neither of them scrolled predictably.
struct PaywallView: View {
    let store: OffWorkStore
    var reason: PlusPaywallReason = .intro
    var showsSkip: Bool = false
    /// Off when the presenter already offers a way out — a sheet has Close in
    /// its own toolbar, and a second dismiss inside the page read as a choice.
    var showsDismissButton: Bool = true
    var onDismiss: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !store.plus.isAuthorized {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(store.t(reason.lockedTitleKey))
                            .font(.largeTitle.bold())
                            .tracking(-0.6)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(store.t("plusIntroBody"))
                            .font(.callout)
                            .foregroundStyle(OWCDesign.secondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(.opacity)
                }

                PaywallContent(
                    store: store,
                    showsBenefits: true,
                    showsIntro: false,
                    loadsProductsOnAppear: true,
                    secondaryTitle: secondaryTitle,
                    secondaryAction: secondaryAction,
                    authorizedAction: finishAuthorizedFlow
                )
            }
            .padding(.horizontal, OWCDesign.contentInset)
            .padding(.top, 28)
            .animation(
                reduceMotion ? OWCMotion.reduced : OWCMotion.paywallPresentation,
                value: store.plus.isAuthorized
            )
        }
        .background(OWCDesign.page)
    }

    private func finishAuthorizedFlow() {
        store.plus.markIntroSeen()
        store.resumePendingPlusActionIfAuthorized()
        onDismiss()
    }

    private var secondaryTitle: String? {
        if reason != .intro, showsDismissButton { return store.t("plusContinueReadonly") }
        if showsSkip { return store.t("plusSkip") }
        return nil
    }

    private var secondaryAction: (() -> Void)? {
        if reason != .intro, showsDismissButton { return onDismiss }
        if showsSkip {
            return {
                store.plus.markIntroSeen()
                onDismiss()
            }
        }
        return nil
    }
}

/// Everything below the title: what Plus adds, the plans, and the legal text.
struct PaywallContent: View {
    let store: OffWorkStore
    var showsBenefits = true
    var showsIntro = true
    var loadsProductsOnAppear = true
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?
    var authorizedAction: (() -> Void)?
    @State private var selected = PlusPlanKind.yearly
    @State private var confirmsLifetime = false
    @State private var purchasedFeedback = 0
    @State private var errorFeedback = 0
    @State private var selectionFeedback = 0
    @State private var authorizedAtPresentation: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var plus: PlusEntitlement { store.plus }

    init(
        store: OffWorkStore,
        showsBenefits: Bool = true,
        showsIntro: Bool = true,
        loadsProductsOnAppear: Bool = true,
        secondaryTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil,
        authorizedAction: (() -> Void)? = nil
    ) {
        self.store = store
        self.showsBenefits = showsBenefits
        self.showsIntro = showsIntro
        self.loadsProductsOnAppear = loadsProductsOnAppear
        self.secondaryTitle = secondaryTitle
        self.secondaryAction = secondaryAction
        self.authorizedAction = authorizedAction
        _authorizedAtPresentation = State(initialValue: store.plus.isAuthorized)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if plus.isAuthorized {
                PlusSubscriberThankYouView(
                    store: store,
                    playsOnAppear: !authorizedAtPresentation,
                    onContinue: authorizedAction
                )
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .offset(y: 10))
                )
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    if showsIntro {
                        Text(store.t("plusIntroBody"))
                            .font(.callout)
                            .foregroundStyle(OWCDesign.secondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if showsBenefits { benefits }
                    purchaseSection
                }
                .transition(.opacity)
            }

            legal
        }
        .sensoryFeedback(.success, trigger: purchasedFeedback)
        .sensoryFeedback(.error, trigger: errorFeedback)
        .sensoryFeedback(.selection, trigger: selectionFeedback)
        .animation(
            reduceMotion ? OWCMotion.reduced : OWCMotion.paywallPresentation,
            value: plus.isAuthorized
        )
        // The purchase itself is not the good news; the entitlement arriving is.
        // A haptic on the tap would have fired for Ask to Buy and for a
        // cancelled sheet too.
        .onChange(of: plus.isAuthorized) { _, authorized in
            if authorized {
                purchasedFeedback += 1
            }
        }
        .onChange(of: plus.lastProductError) { _, error in
            if error != nil { errorFeedback += 1 }
        }
        .onChange(of: plus.products.count) { _, _ in
            if product(for: selected) == nil, let first = visiblePlans.first {
                selected = first
            }
        }
        .task {
            await Task.yield()
            if loadsProductsOnAppear, plus.products.isEmpty, !plus.isBusy {
                await plus.loadProducts()
            }
        }
        .confirmationDialog(
            store.t("plusLifetimeWhileSubscribed"),
            isPresented: $confirmsLifetime,
            titleVisibility: .visible
        ) {
            Button(store.t("plusBuyLifetime")) {
                guard let product = plus.lifetimeProduct() else { return }
                Task { await plus.purchase(product) }
            }
            Button(store.t("cancel"), role: .cancel) {}
        }
    }

    // MARK: - Benefits

    private var benefits: some View {
        OWCGroupCard {
            ForEach(Array(PlusBenefit.all.enumerated()), id: \.element.id) { index, benefit in
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: benefit.icon)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(OWCDesign.accent)
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 34, height: 34)
                        .background(OWCDesign.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityHidden(true)
                    Text(store.t(benefit.titleKey))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .accessibilityElement(children: .combine)
                if index < PlusBenefit.all.count - 1 {
                    Divider().overlay(OWCDesign.separator).padding(.leading, 44)
                }
            }
        }
    }

    // MARK: - Buying

    @ViewBuilder
    private var purchaseSection: some View {
        VStack(spacing: 14) {
            if plus.isLoadingProducts, plus.products.isEmpty {
                planPickerPlaceholder
            } else if plus.products.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(store.t("plusUnavailable"))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error = plus.lastProductError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(OWCDesign.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button(store.t("retryAction")) {
                        Task { await plus.loadProducts() }
                    }
                    .buttonStyle(OWCPrimaryButtonStyle())
                    .disabled(plus.isBusy)
                }
            } else {
                planPicker

                Button {
                    purchaseSelected()
                } label: {
                    HStack(spacing: 8) {
                        if plus.purchaseInFlight {
                            ProgressView().tint(.white)
                        }
                        Text(checkoutTitle)
                    }
                }
                .buttonStyle(OWCPrimaryButtonStyle())
                .disabled(plus.isBusy || product(for: selected) == nil)
            }

            VStack(spacing: 0) {
                restoreButton
                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .font(.callout)
            .foregroundStyle(OWCDesign.secondary)

            if case .pendingAskToBuy = plus.authorization {
                statusNote(store.t("plusWaitingApproval"))
            }
            if let error = plus.lastProductError, !plus.products.isEmpty {
                statusNote(error)
            }
        }
    }

    private var restoreButton: some View {
        Button(store.t("plusRestore")) {
            Task { await plus.restore() }
        }
        .disabled(plus.isBusy)
        .opacity(plus.restoreInFlight ? 0 : 1)
        .overlay {
            if plus.restoreInFlight { ProgressView() }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    /// Keep all three prices visible in one glance. Accessibility Dynamic Type
    /// falls back to full-width rows so the labels never become tiny just to
    /// preserve the compact layout.
    @ViewBuilder
    private var planPicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                ForEach(visiblePlans) { plan in
                    planRow(plan)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                ForEach(visiblePlans) { plan in
                    planTile(plan)
                }
            }
        }
    }

    @ViewBuilder
    private var planPickerPlaceholder: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    planPlaceholder(minHeight: 62)
                }
            }
            .overlay { ProgressView() }
            .accessibilityElement(children: .ignore)
        } else {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    planPlaceholder(minHeight: 116)
                        .frame(maxWidth: .infinity)
                }
            }
            .overlay { ProgressView() }
            .accessibilityElement(children: .ignore)
        }
    }

    private func planPlaceholder(minHeight: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous)
            .fill(OWCDesign.card)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .overlay {
                RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous)
                    .strokeBorder(OWCDesign.separator, lineWidth: 1)
            }
    }

    private func planTile(_ plan: PlusPlanKind) -> some View {
        let chosen = selected == plan
        return Button {
            select(plan)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 4) {
                    Text(store.t(plan.titleKey))
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                    Spacer(minLength: 0)
                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(chosen ? OWCDesign.accent : OWCDesign.tertiary)
                        .accessibilityHidden(true)
                }

                Text(price(for: plan))
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                if let badge = badge(for: plan) {
                    Text(badge)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(chosen ? OWCDesign.accent : OWCDesign.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }
            }
            .foregroundStyle(OWCDesign.primary)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
            .background(chosen ? OWCDesign.accent.opacity(0.10) : OWCDesign.card)
            .clipShape(RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous)
                    .strokeBorder(
                        chosen ? OWCDesign.accent : Color.primary.opacity(0.16),
                        lineWidth: chosen ? 2 : 1
                    )
            }
            .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.selection, value: chosen)
        }
        .buttonStyle(OWCPlanCardButtonStyle())
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityLabel(planAccessibilityLabel(plan))
    }

    private var visiblePlans: [PlusPlanKind] {
        PlusPlanKind.allCases.filter { product(for: $0) != nil }
    }

    private func planRow(_ plan: PlusPlanKind) -> some View {
        let chosen = selected == plan
        return Button {
            select(plan)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.t(plan.titleKey))
                        .font(.body.weight(.semibold))
                    if let badge = badge(for: plan) {
                        Text(badge)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(OWCDesign.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text(price(for: plan))
                    .font(.body.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(chosen ? OWCDesign.accent : OWCDesign.tertiary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(OWCDesign.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 56)
            .background(chosen ? OWCDesign.accent.opacity(0.10) : OWCDesign.card)
            .clipShape(RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: OWCDesign.controlRadius, style: .continuous)
                    .strokeBorder(chosen ? OWCDesign.accent : Color.primary.opacity(0.16), lineWidth: chosen ? 2 : 1)
            }
            .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.selection, value: chosen)
        }
        .buttonStyle(OWCPlanCardButtonStyle())
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityLabel(planAccessibilityLabel(plan))
    }

    private func select(_ plan: PlusPlanKind) {
        guard selected != plan else { return }
        selected = plan
        selectionFeedback += 1
    }

    private func purchaseSelected() {
        guard let product = product(for: selected) else { return }
        if selected == .lifetime, plus.hasActiveSubscription {
            confirmsLifetime = true
            return
        }
        Task { await plus.purchase(product) }
    }

    private var checkoutTitle: String {
        switch selected {
        case .yearly where plus.yearlyEligibleForTrial:
            return store.t("plusStartTrialShort")
        case .lifetime:
            return store.t("plusBuyLifetime")
        case .yearly, .monthly:
            return store.t("plusSubscribe")
        }
    }

    private func product(for plan: PlusPlanKind) -> Product? {
        switch plan {
        case .yearly: plus.yearlyProduct()
        case .monthly: plus.monthlyProduct()
        case .lifetime: plus.lifetimeProduct()
        }
    }

    private func price(for plan: PlusPlanKind) -> String {
        product(for: plan)?.displayPrice ?? "—"
    }

    private func badge(for plan: PlusPlanKind) -> String? {
        switch plan {
        case .yearly:
            return plus.yearlyEligibleForTrial ? store.t("plusTrialBadge") : store.t("plusBestValue")
        case .monthly, .lifetime:
            return nil
        }
    }

    private func planAccessibilityLabel(_ plan: PlusPlanKind) -> String {
        [store.t(plan.titleKey), price(for: plan), badge(for: plan)]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    // MARK: - Already paid

    private var ownedNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.t("plusOwnedTitle"))
                .font(.body.weight(.medium))
            Text(store.t("plusOwnedBody"))
                .font(.footnote)
                .foregroundStyle(OWCDesign.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if plus.hasActiveSubscription {
                Button(store.t("plusManage")) { plus.manageSubscriptions() }
                    .font(.body.weight(.semibold))
                    .frame(minHeight: 44)
            }
        }
    }

    @ViewBuilder
    private var subscribedFooter: some View {
        if case .pendingAskToBuy = plus.authorization {
            statusNote(store.t("plusWaitingApproval"))
        }
        if case .authorized(.inGracePeriod) = plus.authorization {
            statusNote(store.t("plusGracePeriod"))
        }
        Button(store.t("plusManage")) { plus.manageSubscriptions() }
            .buttonStyle(OWCPrimaryButtonStyle(filled: false))
    }

    private func statusNote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(OWCDesign.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Legal

    private var legal: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Lifetime already owns the app. Auto-renew and trial copy
            // belong on the purchase path, not next to "you have Plus for good".
            if !plus.isLifetime {
                Text(store.t("plusAutoRenew"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    termsLink
                    privacyLink
                }
                VStack(alignment: .leading, spacing: 0) {
                    termsLink.frame(minHeight: 44)
                    privacyLink.frame(minHeight: 44)
                }
            }
            .font(.footnote)
        }
        .padding(.top, 4)
    }

    private var termsLink: some View {
        Link(
            store.t("plusTerms"),
            destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
        )
    }

    private var privacyLink: some View {
        Link(store.t("plusPrivacy"), destination: URL(string: "https://doneat.app/privacy")!)
    }
}

private struct PlusSubscriberThankYouView: View {
    let store: OffWorkStore
    let playsOnAppear: Bool
    let onContinue: (() -> Void)?
    @State private var handRotation = 0.0
    @State private var textVisible: Bool
    @State private var isPlaying = false
    @State private var markDimmed = false
    @State private var handledInitialPlayback = false
    @State private var rotationHaptics: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        store: OffWorkStore,
        playsOnAppear: Bool,
        onContinue: (() -> Void)?
    ) {
        self.store = store
        self.playsOnAppear = playsOnAppear
        self.onContinue = onContinue
        _textVisible = State(initialValue: !playsOnAppear)
    }

    var body: some View {
        VStack(spacing: 0) {
            replayableMark
                .frame(maxWidth: 290)
                .frame(height: 290)

            VStack(spacing: 8) {
                Text(store.t("plusThanksTitle"))
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(store.t("plusThanksBody"))
                    .font(.callout)
                    .foregroundStyle(OWCDesign.secondary)
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(textVisible ? 1 : 0)
            .offset(y: textVisible || reduceMotion ? 0 : 8)

            OWCGroupCard {
                OWCRow(
                    icon: store.plus.isLifetime ? "infinity" : "arrow.triangle.2.circlepath",
                    title: store.t(store.plus.isLifetime ? "plusOwnedTitle" : "plusThanksCurrentPlan"),
                    subtitle: store.plus.isLifetime ? store.t("plusOwnedBody") : store.plusStatusLabel,
                    isLast: true,
                    centersVertically: true
                ) {
                    if store.plus.hasActiveSubscription {
                        Button(store.t("plusThanksManagePlan")) {
                            store.plus.manageSubscriptions()
                        }
                        .font(.callout.weight(.semibold))
                        .frame(minHeight: 44)
                    }
                }
            }
            .padding(.top, 22)

            if let onContinue {
                Button(store.t("plusThanksContinue"), action: onContinue)
                    .buttonStyle(OWCPrimaryButtonStyle())
                    .padding(.top, 22)
            }
        }
        .frame(maxWidth: .infinity)
        .task {
            guard playsOnAppear, !handledInitialPlayback else { return }
            handledInitialPlayback = true
            play(revealsText: true)
        }
        .onDisappear { rotationHaptics?.cancel() }
    }

    private var replayableMark: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let scale = side / 1024
            let endpointDiameter = max(44, 172 * scale)
            ZStack {
                OWCBrandMark(
                    handRotation: .degrees(handRotation),
                    showsDepth: true
                )
                    .opacity(markDimmed ? 0.72 : 1)
                    .frame(width: side, height: side)

                Button { play(revealsText: false) } label: {
                    Circle()
                        .fill(Color.clear)
                        .contentShape(Circle())
                        .frame(width: endpointDiameter, height: endpointDiameter)
                }
                .buttonStyle(.plain)
                .position(x: 664.5 * scale, y: 776.1 * scale)
                .accessibilityLabel(store.t("plusReplayCelebration"))
            }
            .frame(width: side, height: side)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func play(revealsText: Bool) {
        guard !isPlaying else { return }
        isPlaying = true
        if revealsText { textVisible = false }
        if reduceMotion {
            if revealsText {
                withAnimation(OWCMotion.reduced) {
                    textVisible = true
                } completion: {
                    isPlaying = false
                }
            } else {
                withAnimation(OWCMotion.reduced) {
                    markDimmed = true
                } completion: {
                    withAnimation(OWCMotion.reduced) {
                        markDimmed = false
                    } completion: {
                        isPlaying = false
                    }
                }
            }
            return
        }
        playRotationHaptics()
        withAnimation(OWCMotion.subscriptionCelebration) {
            handRotation += 1_080
        } completion: {
            if revealsText {
                withAnimation(.easeOut(duration: 0.32)) {
                    textVisible = true
                } completion: {
                    isPlaying = false
                }
            } else {
                isPlaying = false
            }
        }
    }

    private func playRotationHaptics() {
        rotationHaptics?.cancel()
        let interval = OWCMotion.subscriptionCelebrationDuration
            / Double(OWCMotion.subscriptionCelebrationTickCount)
        rotationHaptics = Task { @MainActor in
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            for _ in 0..<OWCMotion.subscriptionCelebrationTickCount {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                generator.selectionChanged()
                generator.prepare()
            }
        }
    }
}

private struct OWCPlanCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.press, value: configuration.isPressed)
    }
}

private enum PlusPlanKind: String, CaseIterable, Identifiable {
    case yearly
    case monthly
    case lifetime

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .yearly: "plusYearly"
        case .monthly: "plusMonthly"
        case .lifetime: "plusLifetime"
        }
    }
}

/// What Plus adds, in the order they matter.
struct PlusBenefit: Identifiable {
    let id: String
    let icon: String
    let titleKey: String

    static let all = [
        PlusBenefit(id: "charts", icon: "chart.bar", titleKey: "plusBenefitCharts"),
        PlusBenefit(id: "life", icon: "circle.grid.3x3", titleKey: "plusBenefitLife"),
        PlusBenefit(id: "edit", icon: "pencil", titleKey: "plusBenefitEdit"),
        PlusBenefit(id: "focus", icon: "timer", titleKey: "plusBenefitFocus"),
        PlusBenefit(id: "sync", icon: "icloud", titleKey: "plusBenefitSync"),
    ]
}

extension PlusPaywallReason {
    /// What the user was reaching for. Also the paywall's own title.
    var lockedTitleKey: String {
        switch self {
        case .intro: "plusIntroTitle"
        case .charts: "plusChartsLocked"
        case .life: "plusLifeLocked"
        case .historyEdit: "plusEditLocked"
        case .sync: "plusSyncLocked"
        case .focus: "plusFocusLocked"
        case .cycleEndSummaryNotifications: "cycleEndSummaryNotificationTitle"
        }
    }
}

struct PlusIntroView: View {
    let store: OffWorkStore

    var body: some View {
        PaywallView(store: store, reason: .intro, showsSkip: true) {
            store.plus.markIntroSeen()
        }
    }
}
