import Foundation

/// Number-pad input. Normalizing digits/separators must never remove a sign or truncate an amount.
nonisolated enum NumberInput {
    /// Nil rejects the entire edit. Empty and a lone separator are editable drafts.
    static func normalize(_ text: String, decimal: Bool, maxDigits: Int) -> String? {
        var folded = ""
        var digits = 0
        var seenSeparator = false
        for scalar in text.unicodeScalars {
            if scalar.properties.numericType == .decimal,
               let value = Character(String(scalar)).wholeNumberValue, (0...9).contains(value) {
                digits += 1
                guard digits <= maxDigits else { return nil }
                folded += String(value)
            } else if decimal, [".", ",", "\u{066B}"].contains(String(scalar)), !seenSeparator {
                seenSeparator = true
                folded += "."
            } else {
                return nil
            }
        }
        return folded
    }

    /// Invalid text stays visible so it can be corrected; it must not be committed.
    static func draft(_ text: String, decimal: Bool, maxDigits: Int) -> String {
        normalize(text, decimal: decimal, maxDigits: maxDigits) ?? text
    }

    /// Empty clears the amount; zero remains a real value. Invalid drafts never reach settings.
    static func committedText(_ text: String, decimal: Bool, maxDigits: Int) -> String? {
        guard text == normalize(text, decimal: decimal, maxDigits: maxDigits),
              text.isEmpty || parse(text) != nil else { return nil }
        return text
    }

    /// Canonical decimal values exclude signs, exponents, non-finite values and partial drafts.
    static func parse(_ text: String) -> Double? {
        guard !text.isEmpty, text != ".",
              text == normalize(text, decimal: true, maxDigits: .max),
              let value = Double(text), value.isFinite, value >= 0 else { return nil }
        return value
    }
}
