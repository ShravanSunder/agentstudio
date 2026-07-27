import AppKit
import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct CommandBarTextFieldTests {
    @Test("plain enter selector maps to the plain modifier")
    func plainEnterSelectorMapsToPlainModifier() {
        let modifier = CommandBarTextField.Coordinator.enterModifier(
            for: #selector(NSResponder.insertNewline(_:)),
            modifierFlags: []
        )

        #expect(modifier == .plain)
    }

    @Test("command enter selector maps to the command modifier")
    func commandEnterSelectorMapsToCommandModifier() {
        let modifier = CommandBarTextField.Coordinator.enterModifier(
            for: #selector(NSResponder.insertNewline(_:)),
            modifierFlags: [.command]
        )

        #expect(modifier == .command)
    }

    @Test("option enter selector maps to the option modifier")
    func optionEnterSelectorMapsToOptionModifier() {
        let modifier = CommandBarTextField.Coordinator.enterModifier(
            for: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
            modifierFlags: []
        )

        #expect(modifier == .option)
    }

    @Test("line-break selector maps to option only when option is pressed")
    func lineBreakSelectorMapsToOptionModifier() {
        let modifier = CommandBarTextField.Coordinator.enterModifier(
            for: #selector(NSResponder.insertLineBreak(_:)),
            modifierFlags: [.option]
        )

        #expect(modifier == .option)
    }

    @Test("line-break selector stays unhandled without supported modifiers")
    func lineBreakSelectorWithoutSupportedModifiersStaysUnhandled() {
        let modifier = CommandBarTextField.Coordinator.enterModifier(
            for: #selector(NSResponder.insertLineBreak(_:)),
            modifierFlags: []
        )

        #expect(modifier == nil)
    }

    @Test("command return event maps to the command modifier")
    func commandReturnEventMapsToCommandModifier() throws {
        let event = try #require(
            makeKeyEvent(
                modifierFlags: [.command],
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                keyCode: 36
            )
        )

        let trigger = try #require(ShortcutDecoder.decode(event: event))
        let modifier = CommandBarShortcutRouter.enterModifier(for: trigger)

        #expect(modifier == .command)
    }

    @Test("command return event decodes to an enter trigger")
    func commandReturnEventDecodesToEnterTrigger() throws {
        let event = try #require(
            makeKeyEvent(
                modifierFlags: [.command],
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                keyCode: 36
            )
        )

        let trigger = ShortcutDecoder.decode(event: event)

        #expect(trigger == ShortcutTrigger(key: .enter, modifiers: [.command]))
    }

    @Test("numpad enter event decodes to an enter trigger")
    func numpadEnterEventDecodesToEnterTrigger() throws {
        let event = try #require(
            makeKeyEvent(
                modifierFlags: [.option],
                characters: "\u{3}",
                charactersIgnoringModifiers: "\u{3}",
                keyCode: 76
            )
        )

        let trigger = ShortcutDecoder.decode(event: event)

        #expect(trigger == ShortcutTrigger(key: .enter, modifiers: [.option]))
    }

    @Test("option return event maps to the option modifier")
    func optionReturnEventMapsToOptionModifier() throws {
        let event = try #require(
            makeKeyEvent(
                modifierFlags: [.option],
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                keyCode: 36
            )
        )

        let trigger = try #require(ShortcutDecoder.decode(event: event))
        let modifier = CommandBarShortcutRouter.enterModifier(for: trigger)

        #expect(modifier == .option)
    }

    @Test("plain return event is not intercepted as a key equivalent")
    func plainReturnEventIsNotInterceptedAsKeyEquivalent() throws {
        let event = try #require(
            makeKeyEvent(
                modifierFlags: [],
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                keyCode: 36
            )
        )

        let trigger = try #require(ShortcutDecoder.decode(event: event))
        let modifier = CommandBarShortcutRouter.enterModifier(for: trigger)

        #expect(modifier == nil)
    }

    @Test("non-enter selectors do not map to an enter modifier")
    func nonEnterSelectorsDoNotMapToEnterModifier() {
        let modifier = CommandBarTextField.Coordinator.enterModifier(
            for: #selector(NSResponder.moveUp(_:)),
            modifierFlags: [.command, .option]
        )

        #expect(modifier == nil)
    }

    @Test("modified enter selectors return the shortcut handler result")
    func modifiedEnterSelectorsReturnShortcutHandlerResult() {
        let handledHarness = DoCommandHarness(shortcutHandled: true)
        let unhandledHarness = DoCommandHarness(shortcutHandled: false)

        let handled = handledHarness.coordinator.control(
            handledHarness.field,
            textView: handledHarness.editor,
            doCommandBy: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
        )
        let unhandled = unhandledHarness.coordinator.control(
            unhandledHarness.field,
            textView: unhandledHarness.editor,
            doCommandBy: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
        )

        #expect(handled)
        #expect(!unhandled)
    }

    @Test("Tab and Shift-Tab invoke forward and back navigation")
    func tabSelectorsInvokeNavigation() {
        let harness = DoCommandHarness(shortcutHandled: false)

        let handledTab = harness.coordinator.control(
            harness.field,
            textView: harness.editor,
            doCommandBy: #selector(NSResponder.insertTab(_:))
        )
        let handledBacktab = harness.coordinator.control(
            harness.field,
            textView: harness.editor,
            doCommandBy: #selector(NSResponder.insertBacktab(_:))
        )

        #expect(handledTab)
        #expect(handledBacktab)
        #expect(harness.forwardCount == 1)
        #expect(harness.backCount == 1)
    }

    @Test("Backspace on an empty query invokes breadcrumb navigation")
    func emptyBackspaceInvokesNavigation() {
        let harness = DoCommandHarness(shortcutHandled: false)
        harness.editor.string = ""

        let handled = harness.coordinator.control(
            harness.field,
            textView: harness.editor,
            doCommandBy: #selector(NSResponder.deleteBackward(_:))
        )

        #expect(handled)
        #expect(harness.backspaceCount == 1)
    }

    @Test("Backspace with query text remains normal text editing")
    func nonEmptyBackspaceRemainsTextEditing() {
        let harness = DoCommandHarness(shortcutHandled: false)
        harness.editor.string = "actual"

        let handled = harness.coordinator.control(
            harness.field,
            textView: harness.editor,
            doCommandBy: #selector(NSResponder.deleteBackward(_:))
        )

        #expect(!handled)
        #expect(harness.backspaceCount == 0)
    }

    @MainActor
    private final class DoCommandHarness {
        let field = NSTextField()
        let editor = NSTextView()
        let coordinator: CommandBarTextField.Coordinator
        private let backspaceCounter: Counter
        private let forwardCounter: Counter
        private let backCounter: Counter

        var backspaceCount: Int { backspaceCounter.value }
        var forwardCount: Int { forwardCounter.value }
        var backCount: Int { backCounter.value }

        init(shortcutHandled: Bool) {
            let backspaceCounter = Counter()
            let forwardCounter = Counter()
            let backCounter = Counter()
            self.backspaceCounter = backspaceCounter
            self.forwardCounter = forwardCounter
            self.backCounter = backCounter
            let textField = CommandBarTextField(
                text: .constant(""),
                placeholder: "Filter...",
                onArrowUp: {},
                onArrowDown: {},
                onEnter: { _ in },
                onShortcutTrigger: { _ in shortcutHandled },
                onBackspaceOnEmpty: { backspaceCounter.value += 1 },
                onTabForward: { forwardCounter.value += 1 },
                onShiftTabBack: { backCounter.value += 1 }
            )
            coordinator = CommandBarTextField.Coordinator(textField)
        }

        private final class Counter {
            var value = 0
        }
    }

}
