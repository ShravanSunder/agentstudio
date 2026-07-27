import AgentStudioCore
import AgentStudioInboxNotification
import AgentStudioProgrammaticControl
import AgentStudioRepoExplorer
import Foundation

/// Protocol for objects that execute commands against the active workspace.
@MainActor
protocol WorkspaceCommandHandling: AnyObject {
    func execute(_ command: AppCommand)
    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType)
    func canExecute(_ command: AppCommand) -> Bool
    func canExecute(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool
    func bridgePaneCommandTarget(worktreeId: UUID) -> BridgePaneCommandTarget?
    func executeExtractPaneToTab(tabId: UUID, paneId: UUID, targetTabIndex: Int?)
    func executeMovePaneToTab(sourcePaneId: UUID, sourceTabId: UUID?, targetTabId: UUID)
}

/// Routes app-level commands that do not belong to the workspace command handler.
@MainActor
protocol ShellCommandHandling: AnyObject {
    func canExecute(_ command: AppCommand) -> Bool
    func canExecute(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool
    func execute(_ command: AppCommand) -> Bool
    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool
    func execute(_ request: AppCommandExecutionRequest) -> AppCommandExecutionOutcome
    func showRepoCommandBar()
    func refreshWorktrees()
    func refocusActivePane()
}

struct AppCommandExecutionRequest: Equatable, Sendable {
    let command: AppCommand
    let arguments: AppCommandExecutionArguments?
    let executionContext: AppCommandExecutionContext

    init(
        command: AppCommand,
        arguments: AppCommandExecutionArguments? = nil,
        executionContext: AppCommandExecutionContext = .interactive
    ) {
        self.command = command
        self.arguments = arguments
        self.executionContext = executionContext
    }
}

enum AppCommandExecutionContext: Equatable, Sendable {
    case interactive
    case headlessIPC
}

enum AppCommandExecutionArguments: Equatable, Sendable {
    case repoSidebarVisibilityMode(RepoExplorerVisibilityMode)
    case repoSidebarSortOrder(RepoExplorerSortOrder)
    case inboxRowStateFilter(InboxNotificationRowStateFilter)
    case inboxContentMode(InboxNotificationContentMode)

    static func commandOwnedArguments(
        command: AppCommand,
        rawArguments: [String: String],
        argumentsContainOnlyStrings: Bool,
        argumentSchema: [IPCCommandArgumentSchema]
    ) throws -> Self? {
        try validate(
            rawArguments: rawArguments,
            argumentsContainOnlyStrings: argumentsContainOnlyStrings,
            against: argumentSchema
        )
        switch command {
        case .setRepoSidebarVisibilityMode:
            guard
                let rawMode = rawArguments["mode"],
                let mode = RepoExplorerVisibilityMode(rawValue: rawMode)
            else {
                throw AppCommandArgumentDecodingError.validationRejected
            }
            return .repoSidebarVisibilityMode(mode)
        case .setRepoSidebarSortOrder:
            guard
                let rawOrder = rawArguments["order"],
                let order = RepoExplorerSortOrder(rawValue: rawOrder)
            else {
                throw AppCommandArgumentDecodingError.validationRejected
            }
            return .repoSidebarSortOrder(order)
        case .setInboxRowStateFilter:
            guard
                let rawFilter = rawArguments["filter"],
                let filter = InboxNotificationRowStateFilter(rawValue: rawFilter)
            else {
                throw AppCommandArgumentDecodingError.validationRejected
            }
            return .inboxRowStateFilter(filter)
        case .setInboxContentMode:
            guard
                let rawMode = rawArguments["mode"],
                let mode = InboxNotificationContentMode(rawValue: rawMode)
            else {
                throw AppCommandArgumentDecodingError.validationRejected
            }
            return .inboxContentMode(mode)
        default:
            guard rawArguments.isEmpty else {
                throw AppCommandArgumentDecodingError.validationRejected
            }
            return nil
        }
    }

    private static func validate(
        rawArguments: [String: String],
        argumentsContainOnlyStrings: Bool,
        against argumentSchema: [IPCCommandArgumentSchema]
    ) throws {
        guard argumentsContainOnlyStrings else {
            throw AppCommandArgumentDecodingError.validationRejected
        }
        let schemaByName = Dictionary(uniqueKeysWithValues: argumentSchema.map { ($0.name, $0) })
        guard Set(rawArguments.keys).isSubset(of: Set(schemaByName.keys)) else {
            throw AppCommandArgumentDecodingError.validationRejected
        }

        for argument in argumentSchema where argument.isRequired {
            guard rawArguments[argument.name] != nil else {
                throw AppCommandArgumentDecodingError.validationRejected
            }
        }

        for (name, value) in rawArguments {
            guard let schema = schemaByName[name] else {
                throw AppCommandArgumentDecodingError.validationRejected
            }
            switch schema.kind {
            case .stringEnum(let values):
                guard values.contains(value) else {
                    throw AppCommandArgumentDecodingError.validationRejected
                }
            }
        }
    }
}

enum AppCommandArgumentDecodingError: Error, Equatable {
    case validationRejected
}

enum AppCommandExecutionOutcome: Equatable, Sendable {
    case applied
    case stateUnavailable
    case unsupportedCommand
}

@MainActor
extension WorkspaceCommandHandling {
    func canExecute(_ command: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool {
        canExecute(command)
    }

    func bridgePaneCommandTarget(worktreeId _: UUID) -> BridgePaneCommandTarget? {
        nil
    }
}

@MainActor
extension ShellCommandHandling {
    func canExecute(_ command: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool {
        canExecute(command)
    }

    func execute(_ request: AppCommandExecutionRequest) -> AppCommandExecutionOutcome {
        guard request.arguments == nil else {
            return .unsupportedCommand
        }
        return execute(request.command) ? .applied : .unsupportedCommand
    }
}
