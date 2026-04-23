import Foundation

@MainActor
extension CommandBarDataSource {
    static func inboxItems(commands: InboxNotificationCommands?) -> [CommandBarItem] {
        guard let commands else { return [] }

        var items: [CommandBarItem] = []
        items.append(
            CommandBarItem(
                id: "inbox.markAllAsRead",
                title: "Mark all as read",
                icon: "checkmark.circle",
                group: Group.inboxCommands,
                groupPriority: Priority.commands,
                keywords: ["inbox", "notification", "read"],
                action: inboxCommandAction(commands.markAllAsRead)
            )
        )
        items.append(
            CommandBarItem(
                id: "inbox.clearReadHistory",
                title: "Clear read history",
                icon: "trash",
                group: Group.inboxCommands,
                groupPriority: Priority.commands,
                keywords: ["inbox", "notification", "clear"],
                action: inboxCommandAction(commands.clearReadHistory)
            )
        )
        items.append(
            CommandBarItem(
                id: "inbox.clearAll",
                title: "Clear all notifications",
                icon: "trash.fill",
                group: Group.inboxCommands,
                groupPriority: Priority.commands,
                keywords: ["inbox", "notification", "clear", "delete"],
                action: inboxCommandAction(commands.clearAll)
            )
        )

        for grouping in InboxNotificationGrouping.allCases {
            items.append(
                CommandBarItem(
                    id: "inbox.grouping.\(grouping.rawValue)",
                    title: "Change grouping: \(inboxGroupingLabel(grouping))",
                    icon: "line.3.horizontal",
                    group: Group.inboxCommands,
                    groupPriority: Priority.commands,
                    keywords: ["inbox", "notification", "group", grouping.rawValue],
                    action: inboxCommandAction {
                        commands.setGrouping(grouping)
                    }
                )
            )
        }

        items.append(
            CommandBarItem(
                id: "inbox.toggleSort",
                title: "Toggle sort order",
                icon: "arrow.up.arrow.down",
                group: Group.inboxCommands,
                groupPriority: Priority.commands,
                keywords: ["inbox", "notification", "sort"],
                action: inboxCommandAction(commands.toggleSort)
            )
        )
        items.append(
            CommandBarItem(
                id: "inbox.toggleBell",
                title: commands.bellEnabled() ? "Disable bell notifications" : "Enable bell notifications",
                icon: "bell",
                group: Group.inboxCommands,
                groupPriority: Priority.commands,
                keywords: ["inbox", "notification", "bell"],
                action: inboxCommandAction(commands.toggleBellEnabled)
            )
        )
        items.append(
            CommandBarItem(
                id: "inbox.returnToWorktrees",
                title: "Return to worktree sidebar",
                icon: "sidebar.left",
                group: Group.inboxCommands,
                groupPriority: Priority.commands,
                keywords: ["inbox", "worktree", "sidebar"],
                action: inboxCommandAction(commands.returnToWorktreeSidebar)
            )
        )
        return items
    }

    private static func inboxCommandAction(
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> CommandBarAction {
        .custom {
            Task { @MainActor in
                action()
            }
        }
    }

    private static func inboxGroupingLabel(_ grouping: InboxNotificationGrouping) -> String {
        switch grouping {
        case .none:
            return "None"
        case .byRepo:
            return "Repository"
        case .byPane:
            return "Pane"
        case .byTab:
            return "Tab"
        }
    }
}
