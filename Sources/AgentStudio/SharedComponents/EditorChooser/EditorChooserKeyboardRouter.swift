import AppKit

enum EditorChooserKeyboardAction: Equatable {
    case dismiss
    case select(EditorTargetId)
    case toggleBookmark(EditorTargetId)
    case highlight(EditorTargetId)
    case consume
    case passthrough
}

enum EditorChooserKeyboardRouter {
    static func action(
        for event: NSEvent,
        items: [EditorChoiceItem],
        selectedEditorId: EditorTargetId?,
        matchesAdditionalDismissShortcut: (NSEvent) -> Bool
    ) -> EditorChooserKeyboardAction {
        guard event.type == .keyDown else { return .passthrough }

        if event.keyCode == 53 || matchesAdditionalDismissShortcut(event) {
            return .dismiss
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasModifiers = !modifiers.isDisjoint(with: [.command, .control, .option, .function, .shift])

        if !hasModifiers {
            switch event.keyCode {
            case 36, 76:
                guard
                    let selectedEditorId = currentSelectionForTesting(
                        items: items,
                        selectedEditorId: selectedEditorId
                    )
                else {
                    return .consume
                }
                return .select(selectedEditorId)
            case 125:
                guard
                    let nextEditorId = movedSelectionForTesting(
                        delta: 1,
                        items: items,
                        selectedEditorId: selectedEditorId
                    )
                else {
                    return .consume
                }
                return .highlight(nextEditorId)
            case 126:
                guard
                    let previousEditorId = movedSelectionForTesting(
                        delta: -1,
                        items: items,
                        selectedEditorId: selectedEditorId
                    )
                else {
                    return .consume
                }
                return .highlight(previousEditorId)
            default:
                break
            }

            if event.charactersIgnoringModifiers?.lowercased() == "b" {
                guard
                    let selectedEditorId = currentSelectionForTesting(
                        items: items,
                        selectedEditorId: selectedEditorId
                    )
                else {
                    return .consume
                }
                return .toggleBookmark(selectedEditorId)
            }

            if let characters = event.charactersIgnoringModifiers,
                characters.count == 1,
                let shortcutNumber = Int(characters),
                (1...9).contains(shortcutNumber)
            {
                guard items.indices.contains(shortcutNumber - 1) else {
                    return .consume
                }

                return .select(items[shortcutNumber - 1].id)
            }
        }

        return .passthrough
    }

    static func defaultSelection(
        items: [EditorChoiceItem],
        bookmarkedEditorId: EditorTargetId?
    ) -> EditorTargetId? {
        if let bookmarkedEditorId, items.contains(where: { $0.id == bookmarkedEditorId }) {
            return bookmarkedEditorId
        }

        return items.first?.id
    }

    static func currentSelectionForTesting(
        items: [EditorChoiceItem],
        selectedEditorId: EditorTargetId?
    ) -> EditorTargetId? {
        if let selectedEditorId, items.contains(where: { $0.id == selectedEditorId }) {
            return selectedEditorId
        }

        return items.first?.id
    }

    static func movedSelectionForTesting(
        delta: Int,
        items: [EditorChoiceItem],
        selectedEditorId: EditorTargetId?
    ) -> EditorTargetId? {
        guard !items.isEmpty else { return nil }

        let currentIndex = items.firstIndex { $0.id == selectedEditorId } ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), items.count - 1)
        return items[nextIndex].id
    }
}
