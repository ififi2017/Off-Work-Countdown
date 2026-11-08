import SwiftUI

// Plan 021 §3.11: where a records day's adopted start and end came from.
// A quiet card on the day page; the details and the way to remove them sit
// one tap away. Never a score, and never more than the evidence supports.

extension WorkTimeVerificationSummary.Mark {
    var labelKey: String {
        switch self {
        case .locationVerified: "recordsVerifyMarkLocation"
        case .systemDetected: "recordsVerifyMarkDetected"
        case .shortcutAction: "recordsVerifyMarkShortcut"
        case .personConfirmed: "recordsVerifyMarkPerson"
        case .adjusted: "recordsVerifyMarkAdjusted"
        }
    }
}

extension WorkTimeVerificationSummary {
    var titleKey: String {
        switch headline {
        case .verified: "recordsVerifyHeadlineVerified"
        case .partial: "recordsVerifyHeadlinePartial"
        case .sources: "recordsVerifyHeadlineSources"
        }
    }

    var symbol: String { headline == .sources ? "clock" : "location.fill" }
}

private extension WorkTimeBoundary {
    var labelKey: String { self == .start ? "startTime" : "endTime" }
}

struct WorkTimeSourceCard: View {
    let summary: WorkTimeVerificationSummary
    let text: AppText
    let formatTime: (Date) -> String
    let open: () -> Void

    var body: some View {
        OWCGroupCard {
            Button(action: open) {
                OWCRow(
                    icon: summary.symbol,
                    title: text.t(summary.titleKey)
                        + (summary.isHistorical ? " · " + text.t("recordsVerifyHistorical") : ""),
                    subtitle: summary.items.map(line).joined(separator: "\n"),
                    isLast: true,
                    iconTint: summary.headline == .sources ? nil : OWCDesign.accent
                ) {
                    OWCDetailAccessory(text: nil)
                }
            }
            .buttonStyle(OWCRowButtonStyle())
        }
    }

    private func line(_ item: WorkTimeVerificationSummary.Item) -> String {
        "\(text.t(item.boundary.labelKey)) \(formatTime(item.entry.time)) · \(text.t(item.mark.labelKey))"
    }
}

struct WorkTimeSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let summary: WorkTimeVerificationSummary
    let text: AppText
    let formatTime: (Date) -> String
    let formatDateTime: (Date) -> String
    let remove: () async -> Bool

    @State private var confirmsRemove = false

    var body: some View {
        NavigationStack {
            OWCContentSizedScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    note(text.t("recordsVerifyNote"))
                        .padding(.top, 14)
                    if summary.isHistorical {
                        note(text.t("recordsVerifyHistoricalNote"))
                            .padding(.top, 8)
                    }
                    ForEach(summary.items) { item in
                        OWCSectionHeader(title: text.t(item.boundary.labelKey) + " · " + text.t(item.mark.labelKey))
                            .padding(.top, OWCDesign.sectionGap)
                        details(item)
                        if let explanation = explanation(item) {
                            note(explanation).padding(.top, 8)
                        }
                    }
                    OWCGroupCard {
                        Button { confirmsRemove = true } label: {
                            OWCRow(icon: "trash", title: text.t("recordsVerifyRemove"), isLast: true, isDestructive: true) {
                                EmptyView()
                            }
                        }
                        .buttonStyle(OWCRowButtonStyle())
                    }
                    .padding(.top, OWCDesign.sectionGap)
                }
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.bottom, OWCDesign.detailBottomInset)
            }
            .background(OWCDesign.page)
            .navigationTitle(text.t("recordsVerifySheetTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(text.t("done")) { dismiss() }
                }
            }
            .confirmationDialog(text.t("recordsVerifyRemove"), isPresented: $confirmsRemove, titleVisibility: .visible) {
                Button(text.t("recordsVerifyRemove"), role: .destructive) {
                    Task { if await remove() { dismiss() } }
                }
            } message: {
                Text(text.t("recordsVerifyRemoveConfirm"))
            }
        }
        .presentationDetents([.medium, .large])
        .tint(OWCDesign.accent)
    }

    private func note(_ value: String) -> some View {
        Text(value)
            .font(.footnote)
            .foregroundStyle(OWCDesign.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
    }

    private func details(_ item: WorkTimeVerificationSummary.Item) -> some View {
        let entry = item.entry
        let adopted = text.t(
            entry.appliedBy == .automatic ? "recordsVerifyAdoptedAutomatically" : "recordsVerifyAdoptedByYou",
            values: ["time": formatDateTime(entry.appliedAt)]
        )
        return OWCGroupCard {
            OWCRow(title: text.t("recordsVerifyDetected")) {
                value(entry.observedAt.map(formatTime) ?? text.t("recordsVerifyDetectedUnknown"))
            }
            OWCRow(title: text.t("recordsVerifyReceived")) { value(formatTime(entry.receivedAt)) }
            OWCRow(title: text.t("recordsVerifyAdopted"), isLast: true) { value(adopted) }
        }
    }

    private func value(_ string: String) -> some View {
        Text(string)
            .font(.body.monospacedDigit())
            .foregroundStyle(OWCDesign.secondary)
            .multilineTextAlignment(.trailing)
    }

    private func explanation(_ item: WorkTimeVerificationSummary.Item) -> String? {
        switch item.mark {
        case .locationVerified, .personConfirmed: nil
        case .systemDetected: text.t("automationUINoteLateDetection")
        case .shortcutAction: text.t("recordsVerifyShortcutNote")
        case .adjusted: text.t("recordsVerifyAdjustedNote", values: ["time": formatTime(item.entry.time)])
        }
    }
}
