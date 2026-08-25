import SwiftUI

/// Wheel picker for one end of the shift, presented from the hero.
struct OWCSetupTimePickerSheet: View {
    let store: OffWorkStore
    let title: String
    @Binding var minutes: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(
                title,
                selection: Binding(
                    get: { store.dateForMinutes(minutes) },
                    set: { minutes = store.minutes(from: $0) }
                ),
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.t("done")) { dismiss() }
                }
            }
        }
    }
}
