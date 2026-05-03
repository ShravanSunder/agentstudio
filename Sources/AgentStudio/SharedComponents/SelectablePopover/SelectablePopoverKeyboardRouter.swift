import AppKit

enum SelectablePopoverKeyboardRouter {
    private enum KeyCode: UInt16 {
        case escape = 53
        case returnKey = 36
        case keypadEnter = 76
        case downArrow = 125
        case upArrow = 126
    }

    static func action<ItemID: Hashable>(
        for event: NSEvent,
        items: [SelectablePopoverKeyboardItem<ItemID>],
        selectedItemId: ItemID?,
        auxiliaryKey: Character? = nil,
        matchesAdditionalDismissShortcut: (NSEvent) -> Bool
    ) -> SelectablePopoverKeyboardAction<ItemID> {
        guard event.type == .keyDown else { return .passthrough }

        if event.keyCode == KeyCode.escape.rawValue || matchesAdditionalDismissShortcut(event) {
            return .dismiss
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasModifiers = !modifiers.isDisjoint(with: [.command, .control, .option, .function, .shift])
        guard !hasModifiers else { return .passthrough }

        switch event.keyCode {
        case KeyCode.returnKey.rawValue, KeyCode.keypadEnter.rawValue:
            guard let itemId = currentSelection(items: items, selectedItemId: selectedItemId) else {
                return .consume
            }
            return .select(itemId)
        case KeyCode.downArrow.rawValue:
            guard let itemId = movedSelection(delta: 1, items: items, selectedItemId: selectedItemId) else {
                return .consume
            }
            return .highlight(itemId)
        case KeyCode.upArrow.rawValue:
            guard let itemId = movedSelection(delta: -1, items: items, selectedItemId: selectedItemId) else {
                return .consume
            }
            return .highlight(itemId)
        default:
            break
        }

        if let auxiliaryKey,
            event.charactersIgnoringModifiers?.lowercased() == String(auxiliaryKey).lowercased()
        {
            guard
                let itemId = currentSelection(items: items, selectedItemId: selectedItemId),
                items.first(where: { $0.id == itemId })?.supportsAuxiliaryAction == true
            else {
                return .consume
            }
            return .auxiliary(itemId)
        }

        if let characters = event.charactersIgnoringModifiers,
            characters.count == 1,
            let shortcutNumber = Int(characters),
            (1...AppPolicies.SelectablePopover.maxNumberedShortcuts).contains(shortcutNumber)
        {
            guard let itemId = items.first(where: { $0.shortcutNumber == shortcutNumber })?.id else {
                return .passthrough
            }
            return .select(itemId)
        }

        return .passthrough
    }

    static func defaultSelection<ItemID: Hashable>(
        items: [SelectablePopoverKeyboardItem<ItemID>],
        preferredItemId: ItemID?
    ) -> ItemID? {
        if let preferredItemId, items.contains(where: { $0.id == preferredItemId }) {
            return preferredItemId
        }

        return items.first?.id
    }

    static func currentSelection<ItemID: Hashable>(
        items: [SelectablePopoverKeyboardItem<ItemID>],
        selectedItemId: ItemID?
    ) -> ItemID? {
        if let selectedItemId, items.contains(where: { $0.id == selectedItemId }) {
            return selectedItemId
        }

        return items.first?.id
    }

    static func movedSelection<ItemID: Hashable>(
        delta: Int,
        items: [SelectablePopoverKeyboardItem<ItemID>],
        selectedItemId: ItemID?
    ) -> ItemID? {
        guard !items.isEmpty else { return nil }

        let currentIndex = items.firstIndex { $0.id == selectedItemId } ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), items.count - 1)
        return items[nextIndex].id
    }
}
