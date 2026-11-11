import AppIntents
import SwiftUI

/// Plan 021: how to record work with a personal automation in Shortcuts.
/// Free for everyone; iOS runs the Arrive/Leave trigger, so DoneAt never
/// asks for location on this path.
struct ShortcutsAutomationGuideView: View {
    let text: AppText

    private var steps: [String] {
        [
            text.t("automationGuideStepOpen"),
            text.t("automationGuideStepPlace"),
            text.t("automationGuideStepArrive", values: ["action": text.t("automationIntentRecordArrival")]),
            text.t("automationGuideStepLeave", values: ["action": text.t("automationIntentRecordDeparture")]),
        ]
    }

    var body: some View {
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(text.t("automationGuideIntro"))
                    .font(.footnote)
                    .foregroundStyle(OWCDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                OWCGroupCard {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            line(Text(verbatim: "\(index + 1)").font(.subheadline.weight(.semibold).monospacedDigit()), step)
                        }
                    }
                    .padding(16)
                }
                .padding(.top, OWCDesign.sectionGap)
                OWCSectionHeader(title: text.t("automationGuideTipsSection"))
                    .padding(.top, OWCDesign.sectionGap)
                OWCGroupCard {
                    VStack(alignment: .leading, spacing: 14) {
                        line(Image(systemName: "leaf"), text.t("automationGuideTipBattery"))
                        line(Image(systemName: "wifi"), text.t("automationGuideTipWiFi"))
                        line(Image(systemName: "bell.badge"), text.t("automationGuideTipNotify"))
                    }
                    .padding(16)
                }
                ShortcutsLink()
                    .shortcutsLinkStyle(.automatic)
                    .frame(maxWidth: .infinity)
                    .padding(.top, OWCDesign.sectionGap)
            }
            .padding(.horizontal, OWCDesign.pageInset)
            .padding(.bottom, OWCDesign.detailBottomInset)
        }
        .background(OWCDesign.page)
        .navigationTitle(text.t("automationGuideTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .tint(OWCDesign.accent)
    }

    private func line(_ mark: some View, _ body: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            mark
                .foregroundStyle(OWCDesign.accent)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(OWCDesign.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
