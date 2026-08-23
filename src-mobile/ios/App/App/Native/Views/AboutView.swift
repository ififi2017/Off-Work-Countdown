import SwiftUI

struct AboutView: View {
    @ObservedObject var store: OffWorkStore

    var body: some View {
        OWCContentSizedScrollView {
            VStack(spacing: 22) {
                OWCGroupCard {
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
                .padding(.horizontal, OWCDesign.pageInset)

                OWCGroupCard {
                    aboutLink(
                        store.t("privacyPolicy"),
                        icon: "hand.raised",
                        destination: contentURL("privacy")
                    )
                    aboutLink(
                        store.t("githubRepository"),
                        icon: "chevron.left.forwardslash.chevron.right",
                        destination: URL(string: "https://github.com/renmu123/Off-Work-Countdown")!
                    )
                    aboutLink(
                        store.t("visitOfficialWebsite"),
                        icon: "safari",
                        destination: URL(string: "https://off.rainif.com/")!
                    )
                    aboutLink(
                        store.t("downloadDesktopApp"),
                        icon: "desktopcomputer",
                        destination: downloadURL,
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
    }

    private func aboutLink(
        _ title: String,
        icon: String,
        destination: URL,
        isLast: Bool = false
    ) -> some View {
        Link(destination: destination) {
            OWCRow(icon: icon, title: title, isLast: isLast) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OWCDesign.tertiary)
            }
        }
        .buttonStyle(OWCRowButtonStyle())
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
