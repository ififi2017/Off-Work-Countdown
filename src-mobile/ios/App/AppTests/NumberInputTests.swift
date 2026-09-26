import Foundation
import Testing
@testable import App

struct NumberInputTests {
    @Test(arguments: zip(["١٫٥", "१२,५", "𝟙𝟚.５", "0", ".5", "5.", "12345678.9"], ["1.5", "12.5", "12.5", "0", ".5", "5.", "12345678.9"]))
    func localizedDigits(input: String, expected: String) {
        let draft = NumberInput.draft(input, decimal: true, maxDigits: 9)
        #expect(draft == expected)
        #expect(NumberInput.committedText(draft, decimal: true, maxDigits: 9) == expected)
    }

    @Test(arguments: ["-500", "1.2.3", "1234567890", "1e3", "1e309", "NaN", "Infinity", "0x10", "1,234.56", "١a٢", " 5 ", "½", "²"])
    func invalidEditStaysVisible(input: String) {
        #expect(NumberInput.normalize(input, decimal: true, maxDigits: 9) == nil)
        #expect(NumberInput.draft(input, decimal: true, maxDigits: 9) == input)
        #expect(NumberInput.committedText(input, decimal: true, maxDigits: 9) == nil)
    }

    @Test func emptyZeroAndPartialDecimal() {
        #expect(NumberInput.committedText("", decimal: true, maxDigits: 9) == "")
        #expect(NumberInput.parse("") == nil)
        #expect(NumberInput.draft(",", decimal: true, maxDigits: 9) == ".")
        #expect(NumberInput.committedText(".", decimal: true, maxDigits: 9) == nil)
        #expect(NumberInput.parse("0") == 0)
        #expect(NumberInput.parse(".5") == 0.5)
        #expect(NumberInput.parse(String(repeating: "9", count: 400)) == nil)
    }

    @Test(arguments: ["1,5", "22,000", "1234", "-60"])
    func integerFieldsDoNotTruncate(input: String) {
        #expect(NumberInput.draft(input, decimal: false, maxDigits: 3) == input)
        #expect(NumberInput.committedText(input, decimal: false, maxDigits: 3) == nil)
    }

    @Test func receivingBackupTextDoesNotRewriteIt() {
        var draft = SettingsFieldDraft("")
        draft.receive("1,5")
        #expect(!draft.hasChanges)
        #expect(draft.value == "1,5")
        #expect(NumberInput.committedText(draft.value, decimal: true, maxDigits: 9) == nil)
        draft.value = NumberInput.draft(draft.value, decimal: true, maxDigits: 9)
        #expect(draft.hasChanges)
        #expect(NumberInput.committedText(draft.value, decimal: true, maxDigits: 9) == "1.5")
    }
}
