import SwiftUI

struct WhatsNewView: View {
    let store: OffWorkStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var revealed = false
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.18).ignoresSafeArea()
                card
                    .frame(maxWidth: 460)
                    .frame(maxHeight: max(160, geometry.size.height - 40))
                    .padding(.horizontal, 20)
                    .opacity(revealed ? 1 : 0)
                    .scaleEffect(revealed || reduceMotion ? 1 : 0.97)
                    .animation(reduceMotion ? OWCMotion.reduced : OWCMotion.stateEnter, value: revealed)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { revealed = true }
        .tint(OWCDesign.accent)
        .accessibilityAction(.escape, store.dismissReleaseNotes)
    }

    private var card: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.t("whatsNewTitle")).font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("DoneAt \(ReleaseNotes.current)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.trailing, 36)
                feature("calendar", "whatsNewRecordsTitle", "whatsNewRecordsBody")
                feature("circle.grid.3x3", "whatsNewLifeTitle", "whatsNewLifeBody")
                feature(FocusTaskIcon.focus.systemName, "whatsNewFocusTitle", "whatsNewFocusBody")
                feature("sparkles", "whatsNewPlusTitle", "whatsNewPlusBody")
                Button(store.t("whatsNewContinue"), action: store.dismissReleaseNotes)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                contentHeight = $0
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(idealHeight: contentHeight > 0 ? contentHeight : nil, maxHeight: contentHeight > 0 ? contentHeight : nil)
        .clipShape(.rect(cornerRadius: OWCDesign.cardRadius))
        .modifier(ReleaseNotesGlass())
        .overlay(alignment: .topTrailing) {
            Button(action: store.dismissReleaseNotes) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.t("close"))
            .padding(12)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: symbol)
                    .font(.system(size: 20)).foregroundStyle(OWCDesign.accent)
                    .frame(width: 26, height: 26)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(store.t(title)).font(.headline)
                Text(store.t(body)).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ReleaseNotesGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: OWCDesign.cardRadius))
        } else {
            content.background(.regularMaterial, in: .rect(cornerRadius: OWCDesign.cardRadius))
        }
    }
}
