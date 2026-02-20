import Foundation
import SwiftUI

@testable import AgentStudio

// MARK: - CommandBarItem Factory

func makeCommandBarItem(
    id: String = "test-item",
    title: String = "Test Item",
    subtitle: String? = nil,
    icon: String? = "terminal",
    iconColor: Color? = nil,
    shortcutKeys: [ShortcutKey]? = nil,
    group: String = "Commands",
    groupPriority: Int = 3,
    keywords: [String] = [],
    hasChildren: Bool = false,
    action: CommandBarAction = .dispatch(.closeTab)
) -> CommandBarItem {
    CommandBarItem(
        id: id,
        title: title,
        subtitle: subtitle,
        icon: icon,
        iconColor: iconColor,
        shortcutKeys: shortcutKeys,
        group: group,
        groupPriority: groupPriority,
        keywords: keywords,
        hasChildren: hasChildren,
        action: action
    )
}

// MARK: - CommandBarLevel Factory

func makeCommandBarLevel(
    id: String = "test-level",
    title: String = "Test Level",
    parentLabel: String? = "Parent",
    items: [CommandBarItem] = []
) -> CommandBarLevel {
    CommandBarLevel(
        id: id,
        title: title,
        parentLabel: parentLabel,
        items: items
    )
}
