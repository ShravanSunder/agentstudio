import AgentStudioCommandBar
import AgentStudioCore
import AgentStudioRepoExplorer
import Foundation

/// Protocol for objects that execute commands against the active workspace.
@MainActor
protocol WorkspaceCommandHandling: AnyObject {
    func ownsWorkspaceWindow(_ workspaceWindowId: UUID) -> Bool
    func execute(_ command: AppCommand)
    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType)
    func executeHeadlessIPC(_ command: AppCommand, target: UUID, targetType: SearchItemType) async -> Bool
    func canExecute(_ command: AppCommand) -> Bool
    func canExecute(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool
    func bridgePaneCommandTarget(worktreeId: UUID) -> BridgePaneCommandTarget?
    func executeExtractPaneToTab(tabId: UUID, paneId: UUID, targetTabInsertionIndex: Int?)
    func executeMovePaneToTab(sourcePaneId: UUID, sourceTabId: UUID?, targetTabId: UUID)
    func executeQuickOpenDirectory(_ directory: URL, placement: QuickOpenDirectoryPlacement)
    func repoExplorerCommandCapabilities(
        _ requests: Set<RepoExplorerCommandPresentationRequest>
    ) -> [RepoExplorerCommandPresentationRequest: Bool]
}

/// Routes app-level commands that do not belong to the workspace command handler.
@MainActor
protocol ShellCommandHandling: AnyObject {
    func ownsWorkspaceWindow(_ workspaceWindowId: UUID) -> Bool
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
}

enum AppCommandExecutionOutcome: Equatable, Sendable {
    case applied
    case stateUnavailable
    case unsupportedCommand
}

@MainActor
extension WorkspaceCommandHandling {
    func ownsWorkspaceWindow(_: UUID) -> Bool { false }

    func executeHeadlessIPC(_ command: AppCommand, target: UUID, targetType: SearchItemType) async -> Bool {
        false
    }

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
    func ownsWorkspaceWindow(_: UUID) -> Bool { false }

    func canExecute(_ command: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool {
        canExecute(command)
    }

    func execute(_ request: AppCommandExecutionRequest) -> AppCommandExecutionOutcome {
        switch request.arguments {
        case .noArguments:
            return execute(request.command) ? .applied : .unsupportedCommand
        }
    }
}
