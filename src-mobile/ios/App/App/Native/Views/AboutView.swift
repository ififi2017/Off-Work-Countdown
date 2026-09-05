import SwiftUI

struct AboutView: View {
    let store: OffWorkStore
#if DEBUG
    @State private var debugUnlockCount = 0
    @State private var showsDebugMenu = false
#endif

    var body: some View {
        OWCContentSizedScrollView {
            VStack(spacing: 22) {
                OWCGroupCard {
                    VStack(spacing: 12) {
                        CelebratingBrandMark(showsDepth: true, isActive: store.selectedTab == .settings)
                            .frame(width: 168, height: 168)
#if DEBUG
                        Text(verbatim: OWCBrand.shortName)
                            .font(.title2.bold())
                            .contentShape(Rectangle())
                            .onLongPressGesture(
                                minimumDuration: 0.55,
                                maximumDistance: 24,
                                perform: registerDebugLongPress
                            )
                            .accessibilityAction(named: Text(store.t("debugMenu"))) {
                                registerDebugLongPress()
                            }
#else
                        Text(verbatim: OWCBrand.shortName)
                            .font(.title2.bold())
#endif
                        Text("fi_niaR Studio")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(OWCDesign.secondary)
                        Text("\(store.t("version")) \(version)")
                            .font(.subheadline)
                            .foregroundStyle(OWCDesign.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                }
                .padding(.horizontal, OWCDesign.pageInset)

                OWCGroupCard {
                    aboutLink(
                        store.t("privacyPolicy"),
                        icon: "hand.raised",
                        destination: URL(string: "https://doneat.app/privacy")!
                    )
                    aboutLink(
                        store.t("githubRepository"),
                        icon: "chevron.left.forwardslash.chevron.right",
                        destination: URL(string: "https://github.com/ififi2017/Off-Work-Countdown")!
                    )
                    aboutLink(
                        store.t("visitOfficialWebsite"),
                        icon: "safari",
                        destination: URL(string: "https://doneat.app/")!
                    )
                    aboutLink(
                        store.t("downloadDesktopApp"),
                        icon: "desktopcomputer",
                        destination: URL(string: "https://doneat.app/download")!,
                        isLast: true
                    )
                }
                .padding(.horizontal, OWCDesign.pageInset)
            }
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .background(OWCDesign.page)
        .navigationTitle(store.t("aboutProject"))
        .navigationBarTitleDisplayMode(.large)
        .owcDetailBack(title: store.t("settings"), pageTitle: store.t("aboutProject"))
#if DEBUG
        .sensoryFeedback(.selection, trigger: debugUnlockCount)
        .sensoryFeedback(.success, trigger: showsDebugMenu)
        .sheet(isPresented: $showsDebugMenu) {
            DebugMenuView(store: store)
        }
        .onAppear(perform: presentDebugMenuForQAIfRequested)
#endif
    }

#if DEBUG
    private func registerDebugLongPress() {
        debugUnlockCount += 1
        guard debugUnlockCount >= 2 else { return }
        debugUnlockCount = 0
        showsDebugMenu = true
    }

    private func presentDebugMenuForQAIfRequested() {
        let key = "ios.native.qaDebugMenu"
        guard UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.removeObject(forKey: key)
        showsDebugMenu = true
    }
#endif

    private func aboutLink(
        _ title: String,
        icon: String,
        destination: URL,
        isLast: Bool = false
    ) -> some View {
        Link(destination: destination) {
            OWCRow(icon: icon, title: title, isLast: isLast) {
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OWCDesign.tertiary)
            }
        }
        .buttonStyle(OWCRowButtonStyle())
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

}
