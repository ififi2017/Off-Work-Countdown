import SwiftUI

/// Save failures remain visible on the surface where the edit happened. The
/// retry awaits the same persistence queue used by exports and sync receipts.
struct RecordSaveStatus: ViewModifier {
    let records: RecordCoordinator
    let title: String
    let message: String
    let retryTitle: String

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if records.persistenceError == .writeFailed {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title).font(.subheadline.weight(.semibold))
                        Spacer(minLength: 12)
                        Button(retryTitle) {
                            Task { try? await records.flush() }
                        }
                        .disabled(records.isSaving)
                    }
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, OWCDesign.pageInset)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)
            }
        }
    }
}
