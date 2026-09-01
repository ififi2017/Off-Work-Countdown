import SwiftUI

/// Direction 1e: one consistent grouped-row vocabulary for every setting.
struct SettingsDesignView: View {
    let store: OffWorkStore
    @State private var showsCompactRootBar = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Scrolls, because the sections outgrow the window. Four of them
        // already reached the tab bar at accessibility text sizes; the fifth
        // put "about" under it at the standard size on every phone.
        OWCContentSizedScrollView {
            VStack(alignment: .leading, spacing: 0) {
                settingsRootHeader

                ForEach(SettingsSection.allCases) { section in
                    SettingsSectionCard(store: store, section: section)
                        .padding(.horizontal, OWCDesign.pageInset)
                        .padding(.top, 14)
                }
            }
            .padding(.bottom, 8)
        }
        // No measure cap. An iPhone is never wide enough to need one — the
        // widest is 440pt — and the old 402 was the Pro's width, so on a Pro Max
        // it left a 19pt stripe on each side that read as a layout mistake.
        // `pageInset` is what sets the margin; nothing else should.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OWCDesign.page)
        .coordinateSpace(.named("settingsRootScroll"))
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            if showsCompactRootBar {
                compactSettingsBar
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
    }

    private var settingsRootHeader: some View {
        OWCRootPageHeader(title: store.t("settings")) {
            EmptyView()
        } trailing: {
            SettingsPlusStarButton(store: store)
        }
        .padding(.horizontal, OWCDesign.contentInset)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.frame(in: .named("settingsRootScroll")).maxY < 8
        } action: { _, shouldShow in
            guard showsCompactRootBar != shouldShow else { return }
            withAnimation(reduceMotion ? OWCMotion.reduced : .easeOut(duration: 0.16)) {
                showsCompactRootBar = shouldShow
            }
        }
    }

    private var compactSettingsBar: some View {
        OWCCompactRootBar(title: store.t("settings")) {
            EmptyView()
        } trailing: {
            SettingsPlusStarButton(store: store)
        }
    }
}

struct SettingsPlusStarButton: View {
    let store: OffWorkStore

    var body: some View {
        NavigationLink(value: AppRoute.plus) {
            ZStack {
                if store.plus.isAuthorized {
                    Circle()
                        .fill(Color.yellow.opacity(0.14))
                        .frame(width: 42, height: 42)
                        .shadow(color: Color.yellow.opacity(0.42), radius: 12)
                    Circle()
                        .stroke(Color.yellow.opacity(0.34), lineWidth: 1.5)
                        .frame(width: 34, height: 34)
                } else {
                    Circle()
                        .fill(OWCDesign.control)
                        .frame(width: 42, height: 42)
                }
                Image(systemName: store.plus.isAuthorized ? "star.fill" : "star")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(store.plus.isAuthorized ? Color.yellow : OWCDesign.secondary)
                    .shadow(
                        color: store.plus.isAuthorized ? Color.orange.opacity(0.55) : .clear,
                        radius: 5
                    )
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.t("plusSettings"))
        .accessibilityValue(store.plusStatusLabel)
    }
}
