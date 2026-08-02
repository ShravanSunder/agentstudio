import AgentStudioCore
import Foundation

@MainActor
enum InboxCommandContextProjection {
    static func current(workspacePane: WorkspacePaneAtom) -> CommandContext {
        let workspaceTab = atom(\.workspaceTab)
        let focusedPane = atom(\.workspaceFocusedPane).resolve(
            workspaceTab: workspaceTab,
            workspacePane: workspacePane,
            requestedOwner: atom(\.workspaceFocusOwner).owner
        )
        return atom(\.commandContext).currentContext(
            workspaceTab: workspaceTab,
            workspacePane: workspacePane,
            focusedPane: focusedPane,
            workspacePanePresentation: atom(\.workspacePanePresentation)
        )
    }
}

struct InboxGroupingCommandPresentation {
    let grouping: InboxNotificationGrouping
    let spec: AppCommandSpec
}

struct InboxSidebarCommandPresentation {
    let sort: AppCommandSpec?
    let rowStateFilter: AppCommandSpec?
    let contentMode: AppCommandSpec?
    let clearRead: AppCommandSpec?
    let clearAll: AppCommandSpec?
    let groupingOptions: [InboxGroupingCommandPresentation]

    init(commandContext: CommandContext) {
        sort = Self.contextualInlineSpec(
            command: .toggleInboxNotificationSort,
            commandContext: commandContext
        )
        rowStateFilter = Self.contextualInlineSpec(
            command: .setInboxRowStateFilter,
            commandContext: commandContext
        )
        contentMode = Self.contextualInlineSpec(
            command: .setInboxContentMode,
            commandContext: commandContext
        )
        clearRead = Self.contextualInlineSpec(
            command: .clearReadInboxNotifications,
            commandContext: commandContext
        )
        clearAll = Self.contextualInlineSpec(
            command: .clearAllInboxNotifications,
            commandContext: commandContext
        )
        groupingOptions = InboxNotificationGrouping.allCases.compactMap { grouping in
            let command = Self.groupingCommand(for: grouping)
            guard
                let spec = Self.contextualInlineSpec(
                    command: command,
                    commandContext: commandContext
                )
            else {
                return nil
            }
            return InboxGroupingCommandPresentation(grouping: grouping, spec: spec)
        }
    }

    private static func contextualInlineSpec(
        command: AppCommand,
        commandContext: CommandContext
    ) -> AppCommandSpec? {
        let spec = command.definition
        let query = AppCommandPresentationQuery(
            surface: .inlineControl,
            subject: .contextual(commandContext)
        )
        return spec.shouldPresent(query) ? spec : nil
    }

    private static func groupingCommand(
        for grouping: InboxNotificationGrouping
    ) -> AppCommand {
        switch grouping {
        case .byTab:
            return .setInboxGroupingTab
        case .byRepo:
            return .setInboxGroupingRepo
        case .byPane:
            return .setInboxGroupingPane
        case .none:
            return .setInboxGroupingNone
        }
    }
}

@MainActor
struct InboxSidebarCommandCapability {
    private let dispatchableCommands: Set<AppCommand>

    init(
        dispatcher: any AppCommandDispatching,
        capabilityOverrides: [AppCommand: Bool] = [:]
    ) {
        dispatchableCommands = Set(
            Self.commands.filter { command in
                capabilityOverrides[command] ?? dispatcher.canDispatch(command)
            }
        )
    }

    func canDispatch(_ command: AppCommand) -> Bool {
        dispatchableCommands.contains(command)
    }

    private static let commands: [AppCommand] = [
        .toggleInboxNotificationSort,
        .setInboxRowStateFilter,
        .setInboxContentMode,
        .clearReadInboxNotifications,
        .clearAllInboxNotifications,
        .setInboxGroupingTab,
        .setInboxGroupingRepo,
        .setInboxGroupingPane,
        .setInboxGroupingNone,
    ]
}

@MainActor
struct PaneInboxClearCommandPresentation {
    let spec: AppCommandSpec
    let isEnabled: Bool
    private let targetPaneId: UUID
    private let dispatcher: any AppCommandDispatching

    static func resolve(
        targetPaneId: UUID,
        dispatcher: any AppCommandDispatching
    ) -> Self? {
        let spec = AppCommand.clearPaneInboxNotifications.definition
        let query = AppCommandPresentationQuery(
            surface: .inlineControl,
            subject: .targeted(.pane)
        )
        guard spec.shouldPresent(query) else { return nil }
        return Self(
            spec: spec,
            isEnabled: dispatcher.canDispatch(
                spec.command,
                target: targetPaneId,
                targetType: .pane
            ),
            targetPaneId: targetPaneId,
            dispatcher: dispatcher
        )
    }

    func perform() {
        guard
            dispatcher.canDispatch(
                spec.command,
                target: targetPaneId,
                targetType: .pane
            )
        else {
            return
        }
        dispatcher.dispatch(
            spec.command,
            target: targetPaneId,
            targetType: .pane
        )
    }
}
