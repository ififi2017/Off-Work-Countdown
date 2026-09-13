import SwiftUI

struct OWCRootPageHeader<Leading: View, Trailing: View>: View {
    let title: String
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    init(
        title: String,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            leading
            if !title.isEmpty {
                Text(title)
                    .font(.largeTitle.bold())
                    .tracking(-0.85)
                    .foregroundStyle(OWCDesign.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.leading, 5)
            }
            Spacer(minLength: 8)
            trailing
        }
        .frame(minHeight: OWCDesign.rootHeaderHeight)
        .padding(.horizontal, OWCDesign.rootControlInset)
        .padding(.top, OWCDesign.rootHeaderTopInset)
    }
}

/// Overlays a root after its large header scrolls away without moving content.
struct OWCCompactRootBar<Leading: View, Trailing: View>: View {
    let title: String
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    init(
        title: String,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(OWCDesign.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 72)

            HStack(spacing: 8) {
                leading
                Spacer(minLength: 8)
                trailing
            }
        }
        .padding(.horizontal, OWCDesign.rootControlInset)
        .frame(height: OWCDesign.rootHeaderHeight)
        .padding(.top, OWCDesign.rootHeaderTopInset)
        .background {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }
}

struct OWCDetailBackModifier<Trailing: View>: ViewModifier {
    let backTitle: String
    let pageTitle: String
    let titleDisplayMode: NavigationBarItem.TitleDisplayMode
    /// The page's own control, at the trailing edge of the header row. Empty on
    /// every page that has nothing to put there.
    @ViewBuilder let trailing: Trailing
    let hasUnsavedChanges: Bool
    let unsavedChangesTitle: String
    let keepEditingTitle: String
    let discardChangesTitle: String
    let onDiscardChanges: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showDiscardPrompt = false
    @State private var promptFeedback = 0
    @State private var discardFeedback = 0

    init(
        backTitle: String,
        pageTitle: String,
        titleDisplayMode: NavigationBarItem.TitleDisplayMode = .large,
        hasUnsavedChanges: Bool = false,
        unsavedChangesTitle: String = "",
        keepEditingTitle: String = "",
        discardChangesTitle: String = "",
        onDiscardChanges: @escaping () -> Void = {},
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.backTitle = backTitle
        self.pageTitle = pageTitle
        self.titleDisplayMode = titleDisplayMode
        self.trailing = trailing()
        self.hasUnsavedChanges = hasUnsavedChanges
        self.unsavedChangesTitle = unsavedChangesTitle
        self.keepEditingTitle = keepEditingTitle
        self.discardChangesTitle = discardChangesTitle
        self.onDiscardChanges = onDiscardChanges
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        content
            // Detail lists use a collapsing large title. Pages with
            // their own content headline can keep it compact.
            .navigationTitle(pageTitle)
            .navigationBarTitleDisplayMode(titleDisplayMode)
            .navigationBarBackButtonHidden(true)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: requestDismiss) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel(backTitle)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    trailing
                }
            }
        .background(
            OWCSystemBackSwipeBridge(
                blocksBackSwipe: hasUnsavedChanges,
                onBlockedBackSwipe: requestDismiss
            )
        )
        .confirmationDialog(
            unsavedChangesTitle,
            isPresented: $showDiscardPrompt,
            titleVisibility: .visible
        ) {
            Button(discardChangesTitle, role: .destructive, action: discardAndDismiss)
            Button(keepEditingTitle, role: .cancel) {}
        }
        .sensoryFeedback(.warning, trigger: promptFeedback)
        .sensoryFeedback(.impact(weight: .medium), trigger: discardFeedback)
    }

    private func requestDismiss() {
        if hasUnsavedChanges {
            promptFeedback += 1
            showDiscardPrompt = true
        } else {
            performDismiss()
        }
    }

    private func discardAndDismiss() {
        discardFeedback += 1
        onDiscardChanges()
        performDismiss()
    }

    private func performDismiss() {
        dismiss()
    }
}

extension View {
    /// Adds navigation chrome only while a permanently-mounted tab root is
    /// active. Tablet and landscape roots intentionally stay in the view tree
    /// during tab changes so Liquid Glass does not flash; an ordinary
    /// `navigationTitle` on an invisible sibling can otherwise keep winning
    /// the shared NavigationStack's preference resolution.
    @ViewBuilder
    func owcNavigationTitle(
        _ title: String,
        displayMode: NavigationBarItem.TitleDisplayMode,
        isActive: Bool
    ) -> some View {
        if isActive {
            navigationTitle(title)
                .navigationBarTitleDisplayMode(displayMode)
        } else {
            self
        }
    }

    func owcDetailBack(
        title: String,
        pageTitle: String,
        titleDisplayMode: NavigationBarItem.TitleDisplayMode = .large
    ) -> some View {
        modifier(OWCDetailBackModifier(
            backTitle: title,
            pageTitle: pageTitle,
            titleDisplayMode: titleDisplayMode
        ) { EmptyView() })
    }

    /// The same header with a control at its trailing edge — a page that can be
    /// saved, rather than one that only commits as you go.
    func owcDetailBack<Trailing: View>(
        title: String,
        pageTitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        modifier(OWCDetailBackModifier(backTitle: title, pageTitle: pageTitle, trailing: trailing))
    }

    /// Keeps a page with a local draft in place until the user explicitly
    /// discards it. The same request path handles the glass back button and the
    /// native leading-edge swipe.
    func owcDetailBack<Trailing: View>(
        title: String,
        pageTitle: String,
        hasUnsavedChanges: Bool,
        unsavedChangesTitle: String,
        keepEditingTitle: String,
        discardChangesTitle: String,
        onDiscardChanges: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        modifier(
            OWCDetailBackModifier(
                backTitle: title,
                pageTitle: pageTitle,
                hasUnsavedChanges: hasUnsavedChanges,
                unsavedChangesTitle: unsavedChangesTitle,
                keepEditingTitle: keepEditingTitle,
                discardChangesTitle: discardChangesTitle,
                onDiscardChanges: onDiscardChanges,
                trailing: trailing
            )
        )
    }

}
