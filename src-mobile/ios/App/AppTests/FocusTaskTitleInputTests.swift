import SwiftUI
import Testing
import UIKit

@testable import App

@MainActor
@Suite("Focus title input composition")
struct FocusTaskTitleInputTests {
    @Test("Form refreshes preserve the first Pinyin letter and the full composition")
    func preservesMarkedText() throws {
        var draft = ""
        let coordinator = FocusTaskTitleInput.Coordinator(
            text: Binding(get: { draft }, set: { draft = $0 }), onFocusChange: { _ in }
        )
        let field = UITextField()
        for composition in ["b", "bao", "bao'gao"] {
            field.setMarkedText(composition, selectedRange: NSRange(location: composition.utf16.count, length: 0))
            #expect(field.markedTextRange != nil)
            coordinator.editingChanged(field)
            coordinator.updateText(field, value: draft)
            #expect(draft.isEmpty)
            #expect(field.text == composition)
            #expect(field.markedTextRange != nil)
        }
        let marked = try #require(field.markedTextRange)
        field.replace(marked, withText: "报告")
        field.unmarkText()
        coordinator.editingChanged(field)
        #expect(draft == "报告")
        coordinator.updateText(field, value: draft)
        #expect(field.text == "报告")
    }

    @Test("Committed edits, deletion and favorite replacement stay in sync")
    func syncsCommittedAndExternalChanges() {
        var draft = ""
        let coordinator = FocusTaskTitleInput.Coordinator(
            text: Binding(get: { draft }, set: { draft = $0 }), onFocusChange: { _ in }
        )
        let field = UITextField()
        field.text = "Write 报告"
        coordinator.editingChanged(field)
        #expect(draft == "Write 报告")
        field.text = ""
        coordinator.editingChanged(field)
        #expect(draft.isEmpty)
        field.setMarkedText("ce", selectedRange: NSRange(location: 2, length: 0))
        coordinator.editingChanged(field)
        draft = "常用任务"
        coordinator.updateText(field, value: draft)
        #expect(field.text == "常用任务")
        #expect(field.markedTextRange == nil)
        coordinator.editingChanged(field)
        #expect(draft == "常用任务")
    }
}
