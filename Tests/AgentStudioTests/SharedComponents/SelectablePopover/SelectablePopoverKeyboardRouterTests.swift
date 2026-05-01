import AppKit
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct SelectablePopoverKeyboardRouterTests {
    private let items = [
        SelectablePopoverKeyboardItem(id: "first", shortcutNumber: 1, supportsAuxiliaryAction: true),
        SelectablePopoverKeyboardItem(id: "second", shortcutNumber: 2, supportsAuxiliaryAction: true),
        SelectablePopoverKeyboardItem(id: "third", shortcutNumber: 3, supportsAuxiliaryAction: false),
    ]

    @Test
    func escape_dismissesPopover() {
        guard
            let event = makeKeyEvent(
                characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}",
                keyCode: 53
            )
        else {
            Issue.record("Expected synthetic key event")
            return
        }

        let action = SelectablePopoverKeyboardRouter.action(
            for: event,
            items: items,
            selectedItemId: "first",
            matchesAdditionalDismissShortcut: { _ in false }
        )

        #expect(action == .dismiss)
    }

    @Test
    func additionalDismissShortcut_dismissesPopover() {
        guard
            let event = makeKeyEvent(
                modifierFlags: [.command, .shift],
                characters: "i",
                charactersIgnoringModifiers: "i",
                keyCode: 34
            )
        else {
            Issue.record("Expected synthetic key event")
            return
        }

        let action = SelectablePopoverKeyboardRouter.action(
            for: event,
            items: items,
            selectedItemId: "first",
            matchesAdditionalDismissShortcut: { event in
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                return event.keyCode == 34 && flags.contains(.command) && flags.contains(.shift)
            }
        )

        #expect(action == .dismiss)
    }

    @Test
    func return_selectsCurrentItem() {
        guard let event = makeKeyEvent(keyCode: 36) else {
            Issue.record("Expected synthetic key event")
            return
        }

        let action = SelectablePopoverKeyboardRouter.action(
            for: event,
            items: items,
            selectedItemId: "second",
            matchesAdditionalDismissShortcut: { _ in false }
        )

        #expect(action == .select("second"))
    }

    @Test
    func downArrow_highlightsNextItem() {
        guard let event = makeKeyEvent(keyCode: 125) else {
            Issue.record("Expected synthetic key event")
            return
        }

        let action = SelectablePopoverKeyboardRouter.action(
            for: event,
            items: items,
            selectedItemId: "first",
            matchesAdditionalDismissShortcut: { _ in false }
        )

        #expect(action == .highlight("second"))
    }

    @Test
    func upArrow_highlightsPreviousItem() {
        guard let event = makeKeyEvent(keyCode: 126) else {
            Issue.record("Expected synthetic key event")
            return
        }

        let action = SelectablePopoverKeyboardRouter.action(
            for: event,
            items: items,
            selectedItemId: "second",
            matchesAdditionalDismissShortcut: { _ in false }
        )

        #expect(action == .highlight("first"))
    }

    @Test
    func shortcutNumber_selectsMatchingItem() {
        guard
            let event = makeKeyEvent(
                characters: "2",
                charactersIgnoringModifiers: "2",
                keyCode: 19
            )
        else {
            Issue.record("Expected synthetic key event")
            return
        }

        let action = SelectablePopoverKeyboardRouter.action(
            for: event,
            items: items,
            selectedItemId: "first",
            matchesAdditionalDismissShortcut: { _ in false }
        )

        #expect(action == .select("second"))
    }

    @Test
    func auxiliaryKey_returnsAuxiliaryActionForCurrentItem() {
        guard
            let event = makeKeyEvent(
                characters: "b",
                charactersIgnoringModifiers: "b",
                keyCode: 11
            )
        else {
            Issue.record("Expected synthetic key event")
            return
        }

        let action = SelectablePopoverKeyboardRouter.action(
            for: event,
            items: items,
            selectedItemId: "second",
            auxiliaryKey: "b",
            matchesAdditionalDismissShortcut: { _ in false }
        )

        #expect(action == .auxiliary("second"))
    }
}
