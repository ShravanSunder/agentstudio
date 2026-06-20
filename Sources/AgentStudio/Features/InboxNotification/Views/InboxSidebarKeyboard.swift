import Foundation
import SwiftUI

enum InboxFocus: Hashable {
    case search
    case list
    case row(UUID)
    case groupingMenu
}

enum InboxSidebarFocusPublisher {
    @MainActor
    static func publish(focusedField: InboxFocus?, into uiState: WorkspaceSidebarState) {
        uiState.setSidebarHasFocus(focusedField != nil)
    }
}

enum InboxSidebarRootKeyAction: Equatable {
    case focusSearch
    case toggleGroupingMenu
    case toggleSort
    case moveGroupBoundary(InboxNotificationListNavigationDirection)
    case moveEnd(InboxNotificationListEndpoint)
    case ignored
}

enum InboxSidebarRowKeyAction: Equatable {
    case activate
    case toggleRead
    case ignored
}

struct InboxSidebarShortcutDescriptor {
    enum Input {
        case characters(String)
        case key(KeyEquivalent)
    }

    let action: InboxSidebarRootKeyAction
    let input: Input
    let modifiers: EventModifiers
    let displayText: ShortcutDisplayText

    func matches(
        characters: String,
        key: KeyEquivalent,
        modifiers candidateModifiers: EventModifiers
    ) -> Bool {
        guard modifiers == candidateModifiers else { return false }

        switch input {
        case .characters(let expectedCharacters):
            return characters == expectedCharacters
        case .key(let expectedKey):
            return key == expectedKey
        }
    }
}

enum InboxSidebarShortcutCatalog {
    static let focusSearch = InboxSidebarShortcutDescriptor(
        action: .focusSearch,
        input: .characters("f"),
        modifiers: .option,
        displayText: character("f", modifiers: [.option])
    )

    static let toggleGroupingMenu = InboxSidebarShortcutDescriptor(
        action: .toggleGroupingMenu,
        input: .characters("g"),
        modifiers: .option,
        displayText: character("g", modifiers: [.option])
    )

    static let toggleSort = InboxSidebarShortcutDescriptor(
        action: .toggleSort,
        input: .characters("s"),
        modifiers: .option,
        displayText: character("s", modifiers: [.option])
    )

    static let moveNextGroup = InboxSidebarShortcutDescriptor(
        action: .moveGroupBoundary(.next),
        input: .key(.downArrow),
        modifiers: .option,
        displayText: ShortcutDisplayText(value: "⌥↓")
    )

    static let movePreviousGroup = InboxSidebarShortcutDescriptor(
        action: .moveGroupBoundary(.previous),
        input: .key(.upArrow),
        modifiers: .option,
        displayText: ShortcutDisplayText(value: "⌥↑")
    )

    static let moveLast = InboxSidebarShortcutDescriptor(
        action: .moveEnd(.last),
        input: .key(.downArrow),
        modifiers: .command,
        displayText: ShortcutDisplayText(value: "⌘↓")
    )

    static let moveFirst = InboxSidebarShortcutDescriptor(
        action: .moveEnd(.first),
        input: .key(.upArrow),
        modifiers: .command,
        displayText: ShortcutDisplayText(value: "⌘↑")
    )

    static let descriptors = [
        focusSearch,
        toggleGroupingMenu,
        toggleSort,
        moveNextGroup,
        movePreviousGroup,
        moveLast,
        moveFirst,
    ]

    static func descriptor(for action: InboxSidebarRootKeyAction) -> InboxSidebarShortcutDescriptor? {
        descriptors.first { $0.action == action }
    }

    private static func character(_ key: String, modifiers: Set<KeyBinding.Modifier>) -> ShortcutDisplayText {
        ShortcutDisplayText(value: KeyBinding(key: key, modifiers: modifiers).displayString)
    }
}

enum InboxSidebarKeyboardRouter {
    static func rootAction(
        characters: String,
        key: KeyEquivalent,
        modifiers: EventModifiers
    ) -> InboxSidebarRootKeyAction {
        for descriptor in InboxSidebarShortcutCatalog.descriptors {
            if descriptor.matches(characters: characters, key: key, modifiers: modifiers) {
                return descriptor.action
            }
        }

        return .ignored
    }

    static func rowAction(key: KeyEquivalent) -> InboxSidebarRowKeyAction {
        if key == .return { return .activate }
        if key == .space { return .toggleRead }
        return .ignored
    }
}

enum InboxSidebarKeyboardHint {
    static let focusSearch = InboxSidebarShortcutCatalog.focusSearch.displayText.value
    static let toggleGroupingMenu = InboxSidebarShortcutCatalog.toggleGroupingMenu.displayText.value
    static let toggleSort = InboxSidebarShortcutCatalog.toggleSort.displayText.value
    static let moveNextGroup = InboxSidebarShortcutCatalog.moveNextGroup.displayText.value
    static let movePreviousGroup = InboxSidebarShortcutCatalog.movePreviousGroup.displayText.value
    static let moveLast = InboxSidebarShortcutCatalog.moveLast.displayText.value
    static let moveFirst = InboxSidebarShortcutCatalog.moveFirst.displayText.value
    static let activateRow = "↵"
    static let toggleRead = "Space"
}
