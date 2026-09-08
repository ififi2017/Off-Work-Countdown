import SwiftUI
import UIKit

/// Keep uncommitted Pinyin inside UIKit. Publishing its first letter to the
/// sheet draft can refresh the form before the input method finishes marking it.
struct FocusTaskTitleInput: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let accessibilityTitle: String
    var onFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onFocusChange: onFocusChange, placeholder: placeholder)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.text = text
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.autocapitalizationType = .none
        field.returnKeyType = .done
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onFocusChange = onFocusChange
        context.coordinator.placeholder = placeholder
        let visiblePlaceholder = context.coordinator.isEditing ? nil : placeholder
        if field.placeholder != visiblePlaceholder { field.placeholder = visiblePlaceholder }
        if field.accessibilityLabel != accessibilityTitle { field.accessibilityLabel = accessibilityTitle }
        context.coordinator.updateText(field, value: text)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        var onFocusChange: (Bool) -> Void
        var placeholder: String
        private var lastValue: String
        private(set) var isEditing = false

        init(text: Binding<String>, onFocusChange: @escaping (Bool) -> Void, placeholder: String = "") {
            self.text = text
            self.onFocusChange = onFocusChange
            self.placeholder = placeholder
            lastValue = text.wrappedValue
        }

        func updateText(_ field: UITextField, value: String) {
            // An unchanged model is not an instruction to overwrite marked text.
            // A changed model is an explicit replacement, e.g. choosing a favorite.
            guard value != lastValue else { return }
            lastValue = value
            if field.text != value {
                field.text = value
            }
        }

        @objc func editingChanged(_ field: UITextField) {
            guard field.markedTextRange == nil else { return }
            let value = field.text ?? ""
            lastValue = value
            if text.wrappedValue != value { text.wrappedValue = value }
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            // IMEs may briefly expose empty text while replacing a composition.
            // Keep the hint out of the active editor for the whole session.
            isEditing = true
            textField.placeholder = nil
            onFocusChange(true)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            editingChanged(textField)
            isEditing = false
            textField.placeholder = placeholder
            onFocusChange(false)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
