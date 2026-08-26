import SwiftUI
import UIKit

struct OvertimeSheet: View {
    let store: OffWorkStore
    @Environment(\.dismiss) private var dismiss
    @State private var endDate = Date.now
    @State private var confirmed = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(store.t("overtimeDescription"))
                    .font(.callout)
                    .foregroundStyle(OWCDesign.secondary)
                DatePicker(
                    store.t("overtimeEndTime"),
                    selection: $endDate,
                    in: minimumDate...,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                Label(store.t("overtimeNoMultiplier"), systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(OWCDesign.secondary)
                Button(store.t("confirmOvertime")) {
                    store.applyOvertime(date: endDate)
                    confirmed.toggle()
                    dismiss()
                }
                .buttonStyle(OWCPrimaryButtonStyle())
            }
            .padding(20)
            .navigationTitle(store.t("overtimeTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(store.t("close"))
                }
            }
            .onAppear {
                endDate = max(
                    minimumDate,
                    store.overtimeEndAtMs.map { Date(timeIntervalSince1970: $0 / 1_000) } ?? minimumDate
                )
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: confirmed)
        }
    }

    private var minimumDate: Date {
        let planned = store.snapshot()?.plannedEndDate ?? .now
        return max(planned, .now).addingTimeInterval(15 * 60)
    }
}

struct ShareComposerView: View {
    let store: OffWorkStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                if proxy.size.width >= 840 {
                    let previewWidth = min(360, proxy.size.height * 0.72)
                    HStack(spacing: 32) {
                        sharePreview(maxWidth: previewWidth)
                            .frame(width: previewWidth)
                        wideShareControls
                            .frame(maxWidth: 390, maxHeight: previewWidth * 1.25)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 18)
                } else if proxy.size.width >= 520, proxy.size.height >= 340 {
                    let horizontalPadding: CGFloat = 20
                    let columnSpacing: CGFloat = 20
                    let contentWidth = proxy.size.width - horizontalPadding * 2 - columnSpacing
                    let previewWidth = min(
                        300,
                        contentWidth * 0.48,
                        (proxy.size.height - 28) * 0.8
                    )
                    let controlsWidth = contentWidth - previewWidth

                    HStack(spacing: columnSpacing) {
                        sharePreview(maxWidth: previewWidth)
                            .frame(width: previewWidth)
                        wideShareControls
                            .frame(width: controlsWidth)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, 14)
                } else {
                    // No scroll view and no arithmetic: the mood row and the
                    // button take their natural height, and the card is handed
                    // whatever is between them. `aspectRatio(.fit)` then picks
                    // the smaller of that height and the available width, so the
                    // card can never end up behind the button — which is exactly
                    // what deriving its size from a height fraction kept doing.
                    VStack(spacing: 14) {
                        moodPicker
                        sharePreview(maxWidth: proxy.size.width - OWCDesign.pageInset * 2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        shareButton
                    }
                    .padding(.horizontal, OWCDesign.pageInset)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                }
            }
            .background(OWCDesign.page)
            .navigationTitle(store.t("shareButton"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityLabel(store.t("close"))
                }
            }
        }
        .sensoryFeedback(.selection, trigger: store.shareMood)
    }


    private var moodPicker: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                ForEach(ShareMood.allCases) { mood in
                    moodButton(mood)
                }
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4),
                spacing: 4
            ) {
                ForEach(ShareMood.allCases) { mood in
                    moodButton(mood)
                }
            }
        }
    }

    /// On a wide sheet the preview and controls read as two deliberate columns.
    /// `ViewThatFits` keeps that arrangement useful on a short landscape iPhone
    /// without making the iPad version sparse again.
    private var wideShareControls: some View {
        ViewThatFits(in: .vertical) {
            expandedShareControls
            compactShareControls
        }
    }

    private var expandedShareControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(store.t("shareMoodLabel"))
                .font(.title3.weight(.semibold))
            moodPicker
            shareDetailsCard
            shareButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactShareControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.t("shareMoodLabel"))
                .font(.subheadline.weight(.semibold))
            moodPicker
            Text(shareCopy)
                .font(.subheadline)
                .foregroundStyle(OWCDesign.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(OWCDesign.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            shareButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shareDetailsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            shareDetailRow("text.quote", text: shareCopy, emphasized: true)
            Divider()
            shareDetailRow("square.and.arrow.up", text: store.t("shareComposerNote"))
            shareDetailRow("lock", text: store.t("sharePrivacyNote"))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OWCDesign.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func shareDetailRow(_ icon: String, text: String, emphasized: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(emphasized ? OWCDesign.accent : OWCDesign.secondary)
                .frame(width: 18)
            Text(text)
                .font(.subheadline.weight(emphasized ? .medium : .regular))
                .foregroundStyle(emphasized ? OWCDesign.primary : OWCDesign.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sharePreview(maxWidth: CGFloat) -> some View {
        ShareCard(store: store)
            .frame(maxWidth: maxWidth)
            .aspectRatio(4 / 5, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 7)
    }

    @ViewBuilder
    private func moodButton(_ mood: ShareMood) -> some View {
        let selected = store.shareMood == mood
        Button {
            withAnimation(.snappy(duration: 0.2)) { store.shareMood = mood }
        } label: {
            Text(verbatim: mood.emoji)
                .font(.title)
                .frame(width: 34, height: 34)
                .background(selected ? OWCDesign.control : Color.clear)
                .clipShape(Circle())
                .overlay { moodRing(selected) }
                .opacity(selected ? 1 : 0.74)
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.t(mood.labelKey))
    }

    @ViewBuilder
    private func moodRing(_ selected: Bool) -> some View {
        if selected {
            Circle().stroke(OWCDesign.accent, lineWidth: 1.5)
        }
    }

    private var shareButton: some View {
        Button { Task { await prepareShare() } } label: {
            Label(store.t("shareNative"), systemImage: "square.and.arrow.up")
        }
        .buttonStyle(OWCPrimaryButtonStyle())
    }

    @MainActor
    private func prepareShare() async {
        await Task.yield()
        let card = ShareCard(store: store)
            .frame(width: 360, height: 450)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 360, height: 450)
        renderer.isOpaque = true
        guard let image = renderer.uiImage else { return }
        // Two items, no overlap: the picture, and one string carrying both the
        // message and the link. Previously the item source also returned that
        // string, so targets took one or the other and the image was dropped.
        let metadata = ShareMetadataItemSource(
            title: store.t("offWorkCountdown"),
            text: "\(shareCopy) \(store.shareURL().absoluteString)",
            icon: UIImage(named: "BrandIcon") ?? image
        )
        SystemShare.present(items: [image, metadata])
    }

    private var shareCopy: String {
        store.shareCopy()
    }
}

/// The shareable image, drawn by `ImageRenderer`.
///
/// Every size in here is deliberately fixed rather than a Dynamic Type style:
/// this view is rasterised into a PNG that leaves the device, so its layout has
/// to be identical for everyone. Do not "migrate" these to semantic fonts.
private struct ShareCard: View {
    let store: OffWorkStore

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [OWCDesign.orange, Color(red: 0.91, green: 0.18, blue: 0.24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(.brandIcon)
                        .resizable()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text(store.t("offWorkCountdown").uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.25)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 8)
                }
                Spacer()
                Text(verbatim: store.shareMood.emoji)
                    .font(.system(size: 72))
                    .frame(width: 82, height: 82)
                    .accessibilityHidden(true)
                Text(heroText)
                    .font(.system(size: 38, weight: .heavy).monospacedDigit())
                    .tracking(-1)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .padding(.top, 12)
                Text(messageText)
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                    .padding(.top, 10)
                Spacer()

                GeometryReader { proxy in
                    Capsule()
                        .fill(.white.opacity(0.35))
                        .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.white)
                        .frame(width: proxy.size.width * min(1, max(0, store.shareProgress() / 100)))
                        }
                }
                .frame(height: 5)

                HStack {
                    Text(store.formatPercent(store.shareProgress()))
                    Spacer()
                    Text("OFF.RAINIF.COM")
                }
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .tracking(0.35)
                .opacity(0.85)
                .padding(.top, 8)
            }
            .foregroundStyle(.white)
            .padding(22)
        }
    }

    private var heroText: String { store.shareHeroText() }
    private var messageText: String { store.shareCopy() }
}
