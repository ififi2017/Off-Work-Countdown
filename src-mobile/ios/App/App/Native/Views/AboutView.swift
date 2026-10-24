import SwiftUI

struct AboutView<DebugMenu: View>: View {
    @Environment(SceneState.self) private var scene
    let text: AppText
    @ViewBuilder var debugMenu: DebugMenu
    // The outlined mark spans a little more than one em (cursor top to the
    // underscore), so this keeps it on the subheadline it replaced.
    @ScaledMetric(relativeTo: .subheadline) private var studioMarkHeight: CGFloat = 16
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
                        StudioMark()
                            .frame(height: studioMarkHeight)
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

/// The studio mark shared with the web footer and finiar.app. The outline
/// leaves room for the cursor block, drawn here so it can blink with the web's
/// 1.1 s step timing; Reduce Motion keeps it lit.
private struct StudioMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Cursor frame within the asset, from scripts/generate-ios-studio-mark.py.
    private static let cursor = (x: 0.9447, y: 0.0, width: 0.0553, height: 0.902)
    private static let blinkHalfPeriod: TimeInterval = 0.55
    private static let cursorColor = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x7A / 255, green: 0xA7 / 255, blue: 0xFF / 255, alpha: 1)
            : UIColor(red: 0x2F / 255, green: 0x6F / 255, blue: 0xDB / 255, alpha: 1)
    })

    var body: some View {
        Image("StudioMark")
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { proxy in
                    TimelineView(.periodic(from: .distantPast, by: Self.blinkHalfPeriod)) { context in
                        Rectangle()
                            .fill(Self.cursorColor)
                            .opacity(isCursorLit(at: context.date) ? 0.85 : 0)
                            .frame(
                                width: proxy.size.width * Self.cursor.width,
                                height: proxy.size.height * Self.cursor.height
                            )
                            .offset(
                                x: proxy.size.width * Self.cursor.x,
                                y: proxy.size.height * Self.cursor.y
                            )
                    }
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "fi_niaR Studio"))
    }

    private func isCursorLit(at date: Date) -> Bool {
        reduceMotion
            || Int(date.timeIntervalSinceReferenceDate / Self.blinkHalfPeriod).isMultiple(of: 2)
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
