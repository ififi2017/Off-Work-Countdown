import SwiftUI

struct OnboardingView: View {
    @ObservedObject var store: OffWorkStore
    @StateObject private var notifications = NotificationService()

    var body: some View {
        ZStack {
            switch store.onboardingPage {
            case 0:
                welcome
            case 1:
                notificationPrimer
            case 2:
                systemSurfaces
            default:
                adaptiveLayouts
            }
        }
        .animation(.snappy(duration: 0.32), value: store.onboardingPage)
        .background(Color(uiColor: .systemBackground))
        .environment(\.layoutDirection, store.layoutDirection)
        .environment(\.locale, store.locale)
        .onAppear {
#if DEBUG
            let defaults = UserDefaults.standard
            if defaults.object(forKey: "ios.native.qaOnboardingPage") != nil {
                store.onboardingPage = min(3, max(0, defaults.integer(forKey: "ios.native.qaOnboardingPage")))
                defaults.removeObject(forKey: "ios.native.qaOnboardingPage")
            }
#endif
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            Image("BrandIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 14, y: 7)
            Text(store.t("offWorkCountdown"))
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.8)
                .multilineTextAlignment(.center)
                .padding(.top, 26)
            Text(store.t("landingTagline"))
                .font(.system(size: 17))
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 18) {
                feature("clock", store.t("landingFeature1Title"), store.t("onboardingShiftBody"))
                feature("wifi.slash", store.t("onboardingOfflineTitle"), store.t("onboardingOfflineBody"))
                feature("rectangle", store.t("onboardingSystemTitle"), store.t("onboardingSystemBody"))
            }
            .padding(.top, 34)
            .frame(maxWidth: 420)
            Spacer()

            Button(store.t("onboardingSetShift")) {
                withAnimation(.snappy) { store.onboardingPage = 1 }
            }
            .buttonStyle(OWCPrimaryButtonStyle())
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 12)
    }

    private var notificationPrimer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Image(systemName: "bell.badge")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(OWCDesign.orangeDeep)
                .frame(width: 52, height: 52)
                .background(OWCDesign.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(store.t("enableNotificationsTitle"))
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.6)
                .padding(.top, 22)
            Text(store.t("mobileNotificationPrimerBody"))
                .font(.system(size: 17))
                .foregroundStyle(OWCDesign.secondary)
                .lineSpacing(4)
                .padding(.top, 12)
            Text(store.t("onboardingSystemBody"))
                .font(.system(size: 17, weight: .semibold))
                .padding(.top, 14)

            OWCGroupCard {
                OWCRow(title: store.t("notificationModeSimple")) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(OWCDesign.orange)
                }
                OWCRow(title: store.t("liveActivityLead", values: ["count": "15"])) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(OWCDesign.orange)
                }
                OWCRow(title: store.t("notificationModeMilestones"), isLast: true)
                    .opacity(0.5)
            }
            .padding(.top, 28)
            Spacer()

            VStack(spacing: 10) {
                Button(store.t("notificationContinue")) {
                    Task {
                        let granted = await notifications.request()
                        if granted { store.notificationMode = .simple }
                        withAnimation(.snappy) { store.onboardingPage = 2 }
                    }
                }
                .buttonStyle(OWCPrimaryButtonStyle())
                Button(store.t("notNow")) {
                    withAnimation(.snappy) { store.onboardingPage = 2 }
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(OWCDesign.secondary)
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 560)
    }

    private var systemSurfaces: some View {
        onboardingShowcase(
            title: store.t("onboardingEverywhereTitle"),
            body: store.t("onboardingEverywhereBody"),
            button: store.t("continue")
        ) {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Image("BrandIcon").resizable().frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 6))
                    Text(store.t("offWorkCountdown")).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("00:14:59").font(.system(size: 13, weight: .bold).monospacedDigit())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(.black)
                .clipShape(Capsule())

                HStack(spacing: 14) {
                    onboardingWidget
                    ZStack {
                        Circle().stroke(OWCDesign.control, lineWidth: 8)
                        Circle().trim(from: 0, to: 0.7286).stroke(OWCDesign.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                        Text("72.86%").font(.system(size: 11, weight: .bold).monospacedDigit())
                    }
                    .frame(width: 94, height: 94)
                }
            }
        } action: {
            withAnimation(.snappy) { store.onboardingPage = 3 }
        }
    }

    private var adaptiveLayouts: some View {
        onboardingShowcase(
            title: store.t("onboardingAdaptiveTitle"),
            body: store.t("onboardingAdaptiveBody"),
            button: store.t("onboardingStartUsing")
        ) {
            VStack(spacing: 14) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(store.t("timerTab"), systemImage: "timer")
                        Label(store.t("settings"), systemImage: "slider.horizontal.3")
                        Spacer()
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(12)
                    .frame(width: 104, height: 150, alignment: .topLeading)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    VStack(spacing: 12) {
                        Text("02:34:18").font(.system(size: 28, weight: .bold).monospacedDigit())
                        Capsule().fill(OWCDesign.control).frame(height: 7).overlay(alignment: .leading) { Capsule().fill(OWCDesign.accent).frame(width: 92) }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .background(OWCDesign.card)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack {
                    Text(Date.now.formatted(.dateTime.month().day().weekday(.wide).locale(store.locale)))
                    Spacer()
                    Text("02:34:18").font(.system(size: 24, weight: .bold).monospacedDigit())
                }
                .padding(16)
                .background(OWCDesign.card)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        } action: {
            store.completeOnboarding(enableNotifications: false)
        }
    }

    private func onboardingShowcase<Showcase: View>(
        title: String,
        body: String,
        button: String,
        @ViewBuilder showcase: () -> Showcase,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 18)
            Text(title)
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.6)
                .multilineTextAlignment(.center)
            Text(body)
                .font(.system(size: 16))
                .foregroundStyle(OWCDesign.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 10)
            showcase()
                .frame(maxWidth: 420)
                .padding(.top, 28)
            Spacer(minLength: 18)
            pageDots
            Button(button, action: action)
                .buttonStyle(OWCPrimaryButtonStyle())
                .padding(.top, 16)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
    }

    private var onboardingWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(store.t("offWorkCountdown"), systemImage: "clock.badge.checkmark").font(.system(size: 11, weight: .bold))
            Text("02:34:18").font(.system(size: 24, weight: .bold).monospacedDigit())
            Capsule().fill(OWCDesign.control).frame(height: 6).overlay(alignment: .leading) { Capsule().fill(OWCDesign.accent).frame(width: 76) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(OWCDesign.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<4, id: \.self) { page in
                Capsule()
                    .fill(page == store.onboardingPage ? OWCDesign.accent : OWCDesign.control)
                    .frame(width: page == store.onboardingPage ? 20 : 7, height: 7)
            }
        }
    }

    private func feature(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(body)
                    .font(.system(size: 15))
                    .foregroundStyle(OWCDesign.secondary)
            }
        }
    }
}
