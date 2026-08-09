import AgentStudioCommandBar
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
    func executeQuickOpenDirectory(_ directory: URL, placement: QuickOpenDirectoryPlacement)
    func repoExplorerCommandCapabilities(
        _ requests: Set<RepoExplorerCommandPresentationRequest>
    ) -> [RepoExplorerCommandPresentationRequest: Bool]
}

/// Routes app-level commands that do not belong to the workspace command handler.
@MainActor
protocol ShellCommandHandling: AnyObject {
    func canExecute(_ command: AppCommand) -> Bool
    func canExecute(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool
    func canExecute(_ request: AppCommandExecutionRequest) -> Bool
    func execute(_ command: AppCommand) -> Bool
    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool
    func execute(_ request: AppCommandExecutionRequest) -> AppCommandExecutionOutcome
    func showRepoCommandBar()
    func refreshWorktrees()
    func refocusActivePane()
}

extension ShellCommandHandling {
    func canExecute(_ request: AppCommandExecutionRequest) -> Bool {
        guard request.arguments == .noArguments else { return false }
        return canExecute(request.command)
    }
}

struct AppCommandExecutionRequest: Equatable, Sendable {
    let command: AppCommand
    let arguments: AppCommandExecutionArguments
    let executionContext: AppCommandExecutionContext

    init(
        command: AppCommand,
        arguments: AppCommandExecutionArguments = .noArguments,
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
    case noArguments
    case repoSidebarSortOrder(RepoExplorerSortOrder)
    case inboxRowStateFilter(InboxNotificationRowStateFilter)
    case inboxContentMode(InboxNotificationContentMode)

    static func commandOwnedArguments(
        contract: AppCommandIPCArgumentContract,
        rawArguments: [String: String],
        argumentsContainOnlyStrings: Bool
    ) throws -> Self {
        try validate(
            rawArguments: rawArguments,
            argumentsContainOnlyStrings: argumentsContainOnlyStrings,
            against: contract.argumentSchema
        )
        switch contract {
        case .noArguments:
            return .noArguments
        case .repoSidebarSortOrder:
            guard
                let rawOrder = rawArguments["order"],
                let order = RepoExplorerSortOrder(rawValue: rawOrder)
            else {
                throw AppCommandArgumentDecodingError.validationRejected
            }
            return .repoSidebarSortOrder(order)
        case .inboxRowStateFilter:
            guard
                let rawFilter = rawArguments["filter"],
                let filter = InboxNotificationRowStateFilter(rawValue: rawFilter)
            else {
                throw AppCommandArgumentDecodingError.validationRejected
            }
            return .inboxRowStateFilter(filter)
        case .inboxContentMode:
            guard
                let rawMode = rawArguments["mode"],
                let mode = InboxNotificationContentMode(rawValue: rawMode)
            else {
                throw AppCommandArgumentDecodingError.validationRejected
            }
            return .inboxContentMode(mode)
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
    func repoExplorerCommandCapabilities(
        _ requests: Set<RepoExplorerCommandPresentationRequest>
    ) -> [RepoExplorerCommandPresentationRequest: Bool] {
        Dictionary(
            uniqueKeysWithValues: requests.map { request in
                let isEnabled: Bool
                if let target = request.target, let targetType = request.targetType {
                    isEnabled = canExecute(request.command, target: target, targetType: targetType)
                } else {
                    isEnabled = canExecute(request.command)
                }
                return (request, isEnabled)
            })
    }

    func canExecute(_ command: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool {
        canExecute(command)
    }

    func bridgePaneCommandTarget(worktreeId _: UUID) -> BridgePaneCommandTarget? {
        nil
    }

    func executeQuickOpenDirectory(_: URL, placement _: QuickOpenDirectoryPlacement) {}
}

@MainActor
extension ShellCommandHandling {
    func canExecute(_ command: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool {
        canExecute(command)
    }

    func execute(_ request: AppCommandExecutionRequest) -> AppCommandExecutionOutcome {
        switch request.arguments {
        case .noArguments:
            return execute(request.command) ? .applied : .unsupportedCommand
        case .repoSidebarSortOrder, .inboxRowStateFilter, .inboxContentMode:
            return .unsupportedCommand
        }
    }
}
