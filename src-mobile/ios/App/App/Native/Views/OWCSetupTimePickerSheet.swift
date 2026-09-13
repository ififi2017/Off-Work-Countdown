import SwiftUI

/// Wheel picker for one end of the shift, presented from the hero.
struct OWCSetupTimePickerSheet: View {
    let session: ShiftSession
    let text: AppText
    let title: String
    @Binding var minutes: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(
                title,
                selection: Binding(
                    get: { session.dateForMinutes(minutes) },
                    set: { minutes = session.minutes(from: $0) }
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
                    Button(text.t("done")) { dismiss() }
                }
            }
        }
    }
}
