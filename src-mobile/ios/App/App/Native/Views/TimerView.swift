import SwiftUI
import UIKit

struct OvertimeSheet: View {
    @ObservedObject var store: OffWorkStore
    @Environment(\.dismiss) private var dismiss
    @State private var endDate = Date.now
    @State private var confirmed = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(store.t("overtimeDescription"))
                    .font(.system(size: 16))
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
                    .font(.system(size: 14))
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
    @ObservedObject var store: OffWorkStore
    @Environment(\.dismiss) private var dismiss
    @State private var shareItems: [Any] = []
    @State private var showSystemShare = false
    @FocusState private var customEmojiFocused: Bool

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                if proxy.size.width > 560 {
                    HStack(spacing: 28) {
                        sharePreview(maxWidth: min(340, proxy.size.height * 0.72))
                            .frame(maxWidth: .infinity)
                        VStack(spacing: 18) {
                            moodPicker
                            Spacer(minLength: 0)
                            shareButton
                        }
                        .frame(maxWidth: 330, maxHeight: 440)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 18)
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            moodPicker
                            sharePreview(maxWidth: min(300, proxy.size.height * 0.54))
                        }
                        .padding(.horizontal, OWCDesign.pageInset)
                        .padding(.top, 6)
                        .padding(.bottom, 78)
                    }
                    .safeAreaInset(edge: .bottom) {
                        shareButton
                            .padding(.horizontal, OWCDesign.pageInset)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                    }
                }
            }
            .background(OWCDesign.page)
            .navigationTitle(store.t("shareButton"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .accessibilityLabel(store.t("close"))
                }
            }
        }
        .sheet(isPresented: $showSystemShare) {
            ShareSheet(items: shareItems)
        }
        .sensoryFeedback(.selection, trigger: store.shareMood)
    }

    private var moodPicker: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(ShareMood.allCases) { mood in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            store.shareMood = mood
                            store.shareUsesCustomEmoji = false
                        }
                    } label: {
                        Image(mood.assetName)
                            .resizable()
                            .scaledToFit()
                            .padding(3)
                            .frame(width: 34, height: 34)
                            .background(!store.shareUsesCustomEmoji && store.shareMood == mood ? OWCDesign.control : .clear)
                            .clipShape(Circle())
                            .overlay {
                                if !store.shareUsesCustomEmoji && store.shareMood == mood {
                                    Circle().stroke(OWCDesign.accent, lineWidth: 1.5)
                                }
                            }
                            .opacity(!store.shareUsesCustomEmoji && store.shareMood == mood ? 1 : 0.74)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 10) {
                TextField(store.t("customEmoji"), text: $store.shareCustomEmoji)
                    .font(.system(size: 22))
                    .focused($customEmojiFocused)
                    .onChange(of: store.shareCustomEmoji) {
                        store.shareCustomEmoji = String(store.shareCustomEmoji.prefix(4))
                        store.shareUsesCustomEmoji = !store.shareCustomEmoji.isEmpty
                    }
                if !store.shareCustomEmoji.isEmpty {
                    Button(store.t("useCustomEmoji")) {
                        store.shareUsesCustomEmoji = true
                        customEmojiFocused = false
                    }
                    .font(.system(size: 14, weight: .semibold))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(OWCDesign.control)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func sharePreview(maxWidth: CGFloat) -> some View {
        ShareCard(store: store)
            .frame(maxWidth: maxWidth)
            .aspectRatio(4 / 5, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 7)
    }

    private var shareButton: some View {
        Button { Task { await prepareShare() } } label: {
            Label(store.t("shareNative"), systemImage: "square.and.arrow.up")
        }
        .buttonStyle(OWCPrimaryButtonStyle())
    }

    @MainActor
    private func prepareShare() async {
        customEmojiFocused = false
        await Task.yield()
        let card = ShareCard(store: store)
            .frame(width: 360, height: 450)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 360, height: 450)
        renderer.isOpaque = true
        guard let image = renderer.uiImage else { return }
        let metadata = ShareMetadataItemSource(
            title: store.t("offWorkCountdown"),
            text: shareCopy,
            url: store.shareURL(),
            icon: UIImage(named: "BrandIcon") ?? image
        )
        shareItems = [image, metadata]
        showSystemShare = true
    }

    private var shareCopy: String {
        let remaining = store.snapshot()?.remainingMs ?? 0
        if remaining <= 0 { return store.t("shareOffWorkText") }
        return store.t("shareText", values: ["time": store.formatRelativeDuration(remaining)])
    }
}

private struct ShareCard: View {
    @ObservedObject var store: OffWorkStore

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [OWCDesign.orange, Color(red: 0.91, green: 0.18, blue: 0.24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image("BrandIcon")
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
                if store.shareUsesCustomEmoji, !store.shareCustomEmoji.isEmpty {
                    Text(store.shareCustomEmoji)
                        .font(.system(size: 68))
                        .frame(height: 76)
                } else {
                    Image(store.shareMood.assetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 76, height: 76)
                }
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
                                .frame(width: proxy.size.width * min(1, max(0, snapshot?.progress ?? 0) / 100))
                        }
                }
                .frame(height: 5)

                HStack {
                    Text(String(format: "%.1f%%", snapshot?.progress ?? 0))
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

    private var snapshot: NativeShiftSnapshot? { store.snapshot() }
    private var isComplete: Bool { (snapshot?.remainingMs ?? 0) <= 0 }
    private var heroText: String {
        isComplete ? store.t("shareDone") : store.formatRelativeDuration(snapshot?.remainingMs ?? 0)
    }
    private var messageText: String {
        isComplete
            ? store.t("shareOffWorkText")
            : store.t("shareText", values: ["time": store.formatRelativeDuration(snapshot?.remainingMs ?? 0)])
    }
}
