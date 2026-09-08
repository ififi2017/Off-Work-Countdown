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
            VStack(alignment: .leading, spacing: 8) {
                OWCSectionHeader(title: store.t("focusFavorites"))
                OWCGroupCard {
                    ForEach(Array(favorites.enumerated()), id: \.element.id) { index, task in
                        Button {
                            title = task.title
                            icon = task.icon
                            selectedID = task.id
                            onSelect(task)
                        } label: {
                            OWCRow(icon: task.icon.systemName, title: task.title,
                                   subtitle: store.t("focusEstimateDetail", values: ["count": "\(task.estimatedPomodoros)", "minutes": "\(store.focusTimerSettings.normalized.focusMinutes)"]), isLast: index == favorites.count - 1) {
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
            }
            .onChange(of: icon) {
                if let selected = favorites.first(where: { $0.id == selectedID }), icon != selected.icon {
                    selectedID = nil
                }
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
        Toggle(isOn: $isFavorite) {
            Label(store.t("focusMakeFavorite"), systemImage: "star")
                .font(.callout)
        }
        .tint(OWCDesign.accent)
        .frame(minHeight: 44)
    }
}
