import SwiftUI

/// Shared by today's creation sheets and the usual-day editor.
struct FocusFavoritePicker: View {
    let store: OffWorkStore
    var onSelect: (FocusTask) -> Void

    var body: some View {
        let favorites = store.favoriteFocusTasks()
        Menu {
            ForEach(favorites) { task in
                Button { onSelect(task) } label: {
                    Label(task.title, systemImage: "star.fill")
                }
            }
        } label: {
            HStack {
                Label(store.t("focusFavorites"), systemImage: favorites.isEmpty ? "star" : "star.fill")
                Spacer()
                Text(store.formatCount(favorites.count))
                Image(systemName: "chevron.down").font(.caption)
            }
            .font(.callout)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
        }
        .disabled(favorites.isEmpty)
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
