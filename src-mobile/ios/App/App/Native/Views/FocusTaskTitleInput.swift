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
        Coordinator(text: $text, onFocusChange: onFocusChange)
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
        field.placeholder = placeholder
        field.accessibilityLabel = accessibilityTitle
        context.coordinator.updateText(field, value: text)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        var onFocusChange: (Bool) -> Void
        private var lastValue: String

        init(text: Binding<String>, onFocusChange: @escaping (Bool) -> Void) {
            self.text = text
            self.onFocusChange = onFocusChange
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

        func textFieldDidBeginEditing(_ textField: UITextField) { onFocusChange(true) }

        func textFieldDidEndEditing(_ textField: UITextField) {
            editingChanged(textField)
            onFocusChange(false)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
