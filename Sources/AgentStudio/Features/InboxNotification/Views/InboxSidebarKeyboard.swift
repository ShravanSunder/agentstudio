import Foundation
import SwiftUI

enum InboxFocus: Hashable {
    case search
    case list
    case row(UUID)
    case groupingMenu
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

enum InboxSidebarKeyboardRouter {
    static func rootAction(
        characters: String,
        key: KeyEquivalent,
        modifiers: EventModifiers
    ) -> InboxSidebarRootKeyAction {
        if modifiers == .option {
            if characters == "f" { return .focusSearch }
            if characters == "g" { return .toggleGroupingMenu }
            if characters == "s" { return .toggleSort }
            if key == .downArrow { return .moveGroupBoundary(.next) }
            if key == .upArrow { return .moveGroupBoundary(.previous) }
        }

        if modifiers == .command {
            if key == .downArrow { return .moveEnd(.last) }
            if key == .upArrow { return .moveEnd(.first) }
        }

        return .ignored
    }

    static func rowAction(key: KeyEquivalent) -> InboxSidebarRowKeyAction {
        if key == .return { return .activate }
        if key == .space { return .toggleRead }
        return .ignored
    }
}
