import SwiftUI

/// What DoneAt does on Apple Watch and how to add it. Informational
/// only: nothing on this page changes a setting.
struct AppleWatchSettingsView: View {
    let text: AppText

    private let pageTitle = "Apple Watch"
    @ScaledMetric(relativeTo: .body) private var stepNumberWidth: CGFloat = 19
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = OWCDesign.rowHeight

    var body: some View {
        OWCContentSizedScrollView {
            VStack(spacing: 22) {
                intro

                section(text.t("appleWatchFeaturesSection")) {
                    OWCRow(
                        icon: "square.stack",
                        title: text.t("appleWatchSmartStackTitle"),
                        subtitle: text.t("appleWatchSmartStackBody"),
                        isLast: false
                    )
                    OWCRow(
                        icon: "applewatch",
                        title: text.t("appleWatchAppTitle"),
                        subtitle: text.t("appleWatchAppBody")
                    )
                    OWCRow(
                        icon: "watchface.applewatch.case",
                        title: text.t("appleWatchComplicationsTitle"),
                        subtitle: text.t("appleWatchComplicationsBody"), isLast: true
                    )

                }

                section(text.t("appleWatchSetupSection")) {
                    step(1, text.t("appleWatchSetupInstall"))
                    step(2, text.t("appleWatchSetupFace"), isLast: true)
                }

                Text(text.t("appleWatchPrivacyNote"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.horizontal, OWCDesign.pageInset)
            }
            .frame(maxWidth: 560)
            .padding(.top, 22)
        }
        .background(OWCDesign.page)
        .navigationTitle(pageTitle)
        .navigationBarTitleDisplayMode(.large)
        .owcDetailBack(title: text.t("settings"), pageTitle: pageTitle)
    }

    private var intro: some View {
        OWCGroupCard {
            VStack(spacing: 10) {
                Image(systemName: "applewatch")
                    .font(.largeTitle)
                    .foregroundStyle(OWCDesign.accent)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
                Text(text.t("appleWatchIntro"))
                    .font(.callout)
                    .foregroundStyle(OWCDesign.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, OWCDesign.pageInset)
    }

    /// A numbered instruction. `OWCRow` keeps a subtitle-less title to one line
    /// on purpose, so instructions use the same gutter, padding and separator
    /// inset but let the sentence wrap.
    private func step(_ number: Int, _ instruction: String, isLast: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: "\(number)")
                .font(.body.monospacedDigit())
                .foregroundStyle(OWCDesign.secondary)
                .frame(width: stepNumberWidth)
                .accessibilityHidden(true)
            Text(instruction)
                .font(.body)
                .foregroundStyle(OWCDesign.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: rowHeight)
        .overlay(alignment: .bottomTrailing) {
            if !isLast {
                Rectangle()
                    .fill(OWCDesign.separator)
                    .frame(height: 0.5)
                    .padding(.leading, stepNumberWidth + 28)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            OWCSectionHeader(title: title)
            OWCGroupCard { content() }
        }
        .padding(.horizontal, OWCDesign.pageInset)
    }
}
