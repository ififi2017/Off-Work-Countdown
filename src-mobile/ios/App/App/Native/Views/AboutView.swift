import SwiftUI

struct AboutView: View {
    @ObservedObject var store: OffWorkStore

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image("BrandIcon")
                        .resizable()
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    Text(store.t("offWorkCountdown"))
                        .font(.system(size: 22, weight: .bold))
                    Text("fi_niaR Studio")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(OWCDesign.secondary)
                    Text("\(store.t("version")) \(version)")
                        .font(.system(size: 14))
                        .foregroundStyle(OWCDesign.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }
            Section {
                Link(destination: contentURL("privacy")) {
                    Label(store.t("privacyPolicy"), systemImage: "hand.raised")
                }
                Link(destination: URL(string: "https://github.com/renmu123/Off-Work-Countdown")!) {
                    Label(store.t("githubRepository"), systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://off.rainif.com/")!) {
                    Label(store.t("visitOfficialWebsite"), systemImage: "safari")
                }
                Link(destination: downloadURL) {
                    Label(store.t("downloadDesktopApp"), systemImage: "desktopcomputer")
                }
            }
        }
        .navigationTitle(store.t("aboutProject"))
        .navigationBarTitleDisplayMode(.large)
        .owcDetailBack(title: store.t("settings"), pageTitle: store.t("aboutProject"))
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private func contentURL(_ page: String) -> URL {
        let contentLocale = store.languageCode.hasPrefix("zh") ? "zh-CN" : "en"
        return URL(string: "https://off.rainif.com/\(contentLocale)/\(page)")!
    }

    private var downloadURL: URL {
        let contentLocale = store.languageCode.hasPrefix("zh") ? "zh-CN" : "en"
        return URL(string: "https://off.rainif.com/\(contentLocale)/download")!
    }
}
