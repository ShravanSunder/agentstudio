import AgentStudioCore
import Foundation
import os.log

private let commandBarInboxLogger = Logger(
    subsystem: "com.agentstudio",
    category: "CommandBarInbox"
)

@MainActor
extension CommandBarDataSource {
    static func inboxItems(
        commands: InboxNotificationCommands?,
        commandContext: CommandContext
    ) -> [CommandBarItem] {
        guard let commands else {
            commandBarInboxLogger.error("Inbox commands unavailable in CommandBar; check boot ordering")
            return []
        }

        let actions = commands.actions
        let snapshot = commands.snapshot()
        var items: [CommandBarItem] = [
            CommandBarItem(
                id: "inbox.markAllAsRead",
                title: "Mark all as read",
                icon: .system(.checkmarkCircle),
                group: Group.inboxCommands,
                groupPriority: Priority.commands,
                keywords: ["inbox", "notification", "read"],
                action: inboxCommandAction(actions.markAllAsRead)
            )
        ]
        if let clearReadInboxSpec = CommandBarCommandPresentation.contextualSpec(
            for: .clearReadInboxNotifications,
            commandContext: commandContext
        ) {
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
        }
        if let clearAllInboxSpec = CommandBarCommandPresentation.contextualSpec(
            for: .clearAllInboxNotifications,
            commandContext: commandContext
        ) {
            items.append(
                CommandBarItem(
                    id: "inbox.clearAll",
                    title: clearAllInboxSpec.label,
                    icon: clearAllInboxSpec.icon,
                    group: Group.inboxCommands,
                    groupPriority: Priority.commands,
                    keywords: ["inbox", "notification", "clear", "delete"],
                    action: .dispatch(.clearAllInboxNotifications),
                    command: .clearAllInboxNotifications
                )
            )
        }

        items.append(contentsOf: inboxGroupingItems(commandContext: commandContext))

        if let toggleSortSpec = CommandBarCommandPresentation.contextualSpec(
            for: .toggleInboxNotificationSort,
            commandContext: commandContext
        ) {
            items.append(
                CommandBarItem(
                    id: "inbox.toggleSort",
                    title: toggleSortSpec.label,
                    icon: toggleSortSpec.icon,
                    group: Group.inboxCommands,
                    groupPriority: Priority.commands,
                    keywords: ["inbox", "notification", "sort"],
                    action: .dispatch(.toggleInboxNotificationSort),
                    command: .toggleInboxNotificationSort
                ))
        }
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

    private static func inboxGroupingItems(
        commandContext: CommandContext
    ) -> [CommandBarItem] {
        InboxNotificationGrouping.allCases.compactMap { grouping in
            guard
                let groupingSpec = CommandBarCommandPresentation.contextualSpec(
                    for: inboxGroupingCommand(for: grouping),
                    commandContext: commandContext
                )
            else {
                return nil
            }
            return CommandBarItem(
                id: "inbox.grouping.\(grouping.rawValue)",
                title: groupingSpec.label,
                icon: groupingSpec.icon,
                group: Group.inboxCommands,
                groupPriority: Priority.commands,
                keywords: ["inbox", "notification", "group", grouping.rawValue],
                action: .dispatch(groupingSpec.command),
                command: groupingSpec.command
            )
        }
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

    private static func inboxGroupingCommand(for grouping: InboxNotificationGrouping) -> AppCommand {
        switch grouping {
        case .none:
            return .setInboxGroupingNone
        case .byRepo:
            return .setInboxGroupingRepo
        case .byPane:
            return .setInboxGroupingPane
        case .byTab:
            return .setInboxGroupingTab
        }
    }
}
