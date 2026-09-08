import SwiftUI

struct FocusFavoritePicker: View {
    let store: OffWorkStore
    @Binding var title: String
    @Binding var icon: FocusTaskIcon
    @Binding var selectedID: UUID?
    var onSelect: (FocusTask) -> Void = { _ in }

    var body: some View {
        let favorites = store.favoriteFocusTasks()
        if !favorites.isEmpty {
            DisclosureGroup(store.t("focusFavorites")) {
                OWCGroupCard {
                    ForEach(Array(favorites.enumerated()), id: \.element.id) { index, task in
                        Button {
                            title = task.title
                            icon = task.icon
                            selectedID = task.id
                            onSelect(task)
                        } label: {
                            OWCRow(icon: task.icon.systemName, title: task.title, isLast: index == favorites.count - 1) {
                                if selectedID == task.id {
                                    Image(systemName: "checkmark").foregroundStyle(OWCDesign.accent)
                                }
                            }
                        }
                        .buttonStyle(OWCRowButtonStyle())
                        .accessibilityAddTraits(selectedID == task.id ? .isSelected : [])
                        .contextMenu {
                            Button(store.t("focusRemoveFavorite"), systemImage: "trash", role: .destructive) {
                                store.toggleFocusFavorite(task)
                                if selectedID == task.id { selectedID = nil }
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
            .onChange(of: title) {
                if let selected = favorites.first(where: { $0.id == selectedID }), title != selected.title {
                    selectedID = nil
                }
            }
        }
    }
}


struct FocusFavoriteToggle: View {
    let store: OffWorkStore
    @Binding var isFavorite: Bool

    var body: some View {
        Button { isFavorite.toggle() } label: {
            Label(store.t(isFavorite ? "focusFavoriteOn" : "focusMakeFavorite"),
                  systemImage: isFavorite ? "star.fill" : "star")
                .font(.callout.weight(.medium))
                .foregroundStyle(isFavorite ? OWCDesign.orangeDeep : OWCDesign.secondary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}
