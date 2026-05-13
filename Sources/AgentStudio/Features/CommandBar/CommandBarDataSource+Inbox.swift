import Foundation
import os.log

private let commandBarInboxLogger = Logger(
    subsystem: "com.agentstudio",
    category: "CommandBarInbox"
)

@MainActor
extension CommandBarDataSource {
    static func inboxItems(commands: InboxNotificationCommands?) -> [CommandBarItem] {
        guard let commands else {
            commandBarInboxLogger.error("Inbox commands unavailable in CommandBar; check boot ordering")
            return []
        }

        let actions = commands.actions
        let snapshot = commands.snapshot()
        let clearReadInboxSpec = AppCommand.clearReadInboxNotifications.definition
        var items: [CommandBarItem] = []
        items.append(
            CommandBarItem(
                id: "inbox.markAllAsRead",
                title: "Mark all as read",
                icon: .system(.checkmarkCircle),
                group: Group.inboxCommands,
                groupPriority: Priority.commands,
                keywords: ["inbox", "notification", "read"],
                action: inboxCommandAction(actions.markAllAsRead)
            )
        )
        items.append(
            CommandBarItem(
                id: "inbox.clearReadHistory",
                title: clearReadInboxSpec.label,
                icon: clearReadInboxSpec.icon,
                group: Group.inboxCommands,
                groupPriority: Priority.commands,
                keywords: ["inbox", "notification", "clear"],
                action: .dispatch(.clearReadInboxNotifications),
                command: .clearReadInboxNotifications
            )
        )
        items.append(
            CommandBarItem(
                id: "inbox.clearAll",
                title: "Clear all notifications",
                icon: .system(.deleteLeft),
                group: Group.inboxCommands,
                groupPriority: Priority.commands,
                keywords: ["inbox", "notification", "clear", "delete"],
                action: inboxCommandAction(actions.clearAll)
            )
        )

        for grouping in InboxNotificationGrouping.allCases {
            items.append(
                CommandBarItem(
                    id: "inbox.grouping.\(grouping.rawValue)",
                    title: "Change grouping: \(inboxGroupingLabel(grouping))",
                    icon: .system(.line3Horizontal),
                    group: Group.inboxCommands,
                    groupPriority: Priority.commands,
                    keywords: ["inbox", "notification", "group", grouping.rawValue],
                    action: inboxCommandAction {
                        actions.setGrouping(grouping)
                    }
                )
            )
        }

        items.append(
            CommandBarItem(
                id: "inbox.toggleSort",
                title: "Toggle sort order",
                icon: .system(.arrowUpArrowDown),
                group: Group.inboxCommands,
                groupPriority: Priority.commands,
                keywords: ["inbox", "notification", "sort"],
                action: inboxCommandAction(actions.toggleSort)
            )
        )
        items.append(
            CommandBarItem(
                id: "inbox.toggleBell",
                title: snapshot.bellEnabled ? "Disable bell notifications" : "Enable bell notifications",
                icon: .system(.bell),
                group: Group.inboxCommands,
                groupPriority: Priority.commands,
                keywords: ["inbox", "notification", "bell"],
                action: inboxCommandAction(actions.toggleBellEnabled)
            )
        )
        items.append(
            CommandBarItem(
                id: "inbox.returnToWorktrees",
                title: "Return to worktree sidebar",
                icon: .system(.sidebarLeft),
                group: Group.inboxCommands,
                groupPriority: Priority.commands,
                keywords: ["inbox", "worktree", "sidebar"],
                action: inboxCommandAction(actions.returnToWorktreeSidebar)
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
