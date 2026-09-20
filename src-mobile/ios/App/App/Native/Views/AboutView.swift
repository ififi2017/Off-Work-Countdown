import SwiftUI

struct AboutView<DebugMenu: View>: View {
    @Environment(SceneState.self) private var scene
    let text: AppText
    @ViewBuilder var debugMenu: DebugMenu
#if DEBUG
    @State private var debugUnlockCount = 0
    @State private var showsDebugMenu = false
#endif

    var body: some View {
        OWCContentSizedScrollView {
            VStack(spacing: 22) {
                OWCGroupCard {
                    VStack(spacing: 12) {
                        CelebratingBrandMark(showsDepth: true, isActive: scene.selectedTab == .settings)
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
                            .accessibilityAction(named: Text(text.t("debugMenu"))) {
                                registerDebugLongPress()
                            }
#else
                        Text(verbatim: OWCBrand.shortName)
                            .font(.title2.bold())
#endif
                        Text(verbatim: "fi_niaR Studio")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(OWCDesign.secondary)
                        Text(verbatim: "\(text.t("version")) \(version)")
                            .font(.subheadline)
                            .foregroundStyle(OWCDesign.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                }
                .padding(.horizontal, OWCDesign.pageInset)

                OWCGroupCard {
                    NavigationLink {
                        HolidayAcknowledgementsView(text: text)
                    } label: {
                        OWCRow(icon: "text.book.closed", title: text.t("acknowledgements"), isLast: true) {
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(OWCDesign.tertiary)
                        }
                    }
                    .buttonStyle(OWCRowButtonStyle())
                }
                .padding(.horizontal, OWCDesign.pageInset)

                OWCGroupCard {
                    aboutLink(
                        text.t("privacyPolicy"),
                        icon: "hand.raised",
                        destination: URL(string: "https://doneat.app/privacy")!
                    )
                    aboutLink(
                        text.t("githubRepository"),
                        icon: "chevron.left.forwardslash.chevron.right",
                        destination: URL(string: "https://github.com/ififi2017/Off-Work-Countdown")!
                    )
                    aboutLink(
                        text.t("visitOfficialWebsite"),
                        icon: "safari",
                        destination: URL(string: "https://doneat.app/")!
                    )
                    aboutLink(
                        text.t("downloadDesktopApp"),
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
        .navigationTitle(text.t("aboutProject"))
        .navigationBarTitleDisplayMode(.large)
        .owcDetailBack(title: text.t("settings"), pageTitle: text.t("aboutProject"))
#if DEBUG
        .sensoryFeedback(.selection, trigger: debugUnlockCount)
        .sensoryFeedback(.success, trigger: showsDebugMenu)
        .sheet(isPresented: $showsDebugMenu) {
            debugMenu
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

private struct HolidayTemplateAttribution: Decodable, Identifiable {
    let name: String
    let sourceURL: URL
    let license: String

    var id: String { name }

    static var bundled: [Self] {
        guard let url = Bundle.main.url(forResource: "HolidayTemplateAttributions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([Self].self, from: data)
        else { return [] }
        return values
    }
}

private struct HolidayAcknowledgementsView: View {
    let text: AppText
    private let attributions = HolidayTemplateAttribution.bundled

    var body: some View {
        List(attributions) { attribution in
            NavigationLink(attribution.name) {
                HolidayLicenseView(text: text, attribution: attribution)
            }
        }
        .navigationTitle(text.t("acknowledgements"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HolidayLicenseView: View {
    let text: AppText
    let attribution: HolidayTemplateAttribution

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Link(destination: attribution.sourceURL) {
                    Label(attribution.name, systemImage: "arrow.up.right")
                        .font(.headline)
                }
                Text(attribution.license)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OWCDesign.pageInset)
        }
        .background(OWCDesign.page)
        .navigationTitle(text.t("openSourceLicenses"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
