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
    shortcutTrigger: ShortcutTrigger? = nil,
    shortcutKeys: [ShortcutKey]? = nil,
    group: String = "Commands",
    groupPriority: Int = 3,
    keywords: [String] = [],
    hasChildren: Bool = false,
    action: CommandBarAction? = nil,
    worktreePresence: WorktreePresence? = nil
) -> CommandBarItem {
    let resolvedAction =
        action
        ?? {
            if let worktreePresence {
                return .worktreeAction(presence: worktreePresence)
            }
            return .dispatch(.closeTab)
        }()

    return CommandBarItem(
        id: id,
        title: title,
        subtitle: subtitle,
        icon: icon,
        iconColor: iconColor,
        shortcutTrigger: shortcutTrigger,
        shortcutKeys: shortcutKeys,
        group: group,
        groupPriority: groupPriority,
        keywords: keywords,
        hasChildren: hasChildren,
        action: resolvedAction
    )
}

func makeWorktreePresence(
    paneCount: Int,
    worktreeId: UUID = UUID(),
    repoId: UUID = UUID()
) -> WorktreePresence {
    let openPanes: [WorkspacePaneLocation]
    switch paneCount {
    case 0:
        openPanes = []
    case 1:
        openPanes = [
            WorkspacePaneLocation(
                paneId: UUID(),
                tabId: UUID(),
                tabIndex: 0,
                paneIndexInTab: 0,
                isActiveInTab: true
            )
        ]
    default:
        let tabId = UUID()
        openPanes = [
            WorkspacePaneLocation(
                paneId: UUID(),
                tabId: tabId,
                tabIndex: 0,
                paneIndexInTab: 0,
                isActiveInTab: true
            ),
            WorkspacePaneLocation(
                paneId: UUID(),
                tabId: tabId,
                tabIndex: 0,
                paneIndexInTab: 1,
                isActiveInTab: false
            ),
        ]
    }

    return WorktreePresence(
        worktreeId: worktreeId,
        repoId: repoId,
        worktreeName: "main",
        repoName: "repo",
        isMainWorktree: true,
        openPanes: openPanes
    )
}

// MARK: - CommandBarLevel Factory

func makeCommandBarLevel(
    id: String = "test-level",
    title: String = "Test Level",
    parentLabel: String? = "Parent",
    scopeLabel: String? = nil,
    items: [CommandBarItem] = []
) -> CommandBarLevel {
    CommandBarLevel(
        id: id,
        title: title,
        parentLabel: parentLabel,
        scopeLabel: scopeLabel,
        items: items
    )
}
