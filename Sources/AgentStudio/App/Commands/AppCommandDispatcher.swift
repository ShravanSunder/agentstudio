import AgentStudioCommandBar
import AgentStudioCore
import AgentStudioRepoExplorer
import Foundation
import Observation
import os

/// App-owned execution point for keyboard, menu, command-bar, and management commands.
@Observable
@MainActor
final class AppCommandDispatcher: AppCommandDispatching {
    static let shared = AppCommandDispatcher()
    private static let logger = Logger(subsystem: "com.agentstudio", category: "AppCommandDispatcher")

    private(set) var definitions: [AppCommand: AppCommandSpec] = [:]
    weak var handler: WorkspaceCommandHandling?
    weak var appCommandRouter: ShellCommandHandling?

    private init() {
        for definition in AppCommand.allCases.map(\.definition) {
            definitions[definition.command] = definition
        }
    }

    func dispatch(_ command: AppCommand) {
        guard canDispatch(command) else {
            Self.logger.warning("Command dispatch rejected: \(command.rawValue, privacy: .public)")
            return
        }
        if appCommandRouter?.execute(command) == true {
            return
        }
        guard let handler else {
            Self.logger.warning("Command dispatch had no workspace handler: \(command.rawValue, privacy: .public)")
            return
        }
        handler.execute(command)
    }

    @discardableResult
    func dispatch(_ request: AppCommandExecutionRequest) -> AppCommandExecutionOutcome {
        guard canDispatch(request) else {
            Self.logger.warning("Command request rejected: \(request.command.rawValue, privacy: .public)")
            return .unsupportedCommand
        }
        switch request.arguments {
        case .noArguments:
            break
        case .repoSidebarSortOrder, .inboxRowStateFilter, .inboxContentMode:
            guard let appCommandRouter else { return .unsupportedCommand }
            return appCommandRouter.execute(request)
        }

        if let appCommandRouter {
            let outcome = appCommandRouter.execute(request)
            if outcome != .unsupportedCommand {
                return outcome
            }
        }
        guard let handler else {
            return .unsupportedCommand
        }
        handler.execute(request.command)
        return .applied
    }

    func dispatch(_ command: AppCommand, target: UUID, targetType: SearchItemType) {
        guard
            dispatch(
                command,
                target: target,
                targetType: targetType,
                executionContext: .interactive
            )
        else {
            Self.logger.warning(
                "Targeted command dispatch rejected: \(command.rawValue, privacy: .public) targetType=\(targetType.rawValue, privacy: .public)"
            )
            return
        }
    }

    @discardableResult
    func dispatch(
        _ command: AppCommand,
        target: UUID,
        targetType: SearchItemType,
        executionContext: AppCommandExecutionContext
    ) -> Bool {
        guard
            canDispatch(
                command,
                target: target,
                targetType: targetType,
                executionContext: executionContext
            )
        else {
            return false
        }
        if appCommandRouter?.execute(command, target: target, targetType: targetType) == true {
            return true
        }
        guard let handler else {
            return false
        }
        handler.execute(command, target: target, targetType: targetType)
        return true
    }

    func dispatchExtractPaneToTab(tabId: UUID, paneId: UUID, targetTabIndex: Int?) {
        guard canDispatch(.extractPaneToTab) else { return }
        handler?.executeExtractPaneToTab(tabId: tabId, paneId: paneId, targetTabIndex: targetTabIndex)
    }

    func dispatchMovePaneToTab(sourcePaneId: UUID, sourceTabId: UUID?, targetTabId: UUID) {
        guard let definition = definitions[.movePaneToTab],
            definition.targeting.supports(targetType: .pane),
            definition.targeting.supports(targetType: .tab),
            canDispatch(.movePaneToTab, target: sourcePaneId, targetType: .pane)
        else {
            return
        }
        handler?.executeMovePaneToTab(
            sourcePaneId: sourcePaneId,
            sourceTabId: sourceTabId,
            targetTabId: targetTabId
        )
    }

    func dispatchQuickOpenDirectory(
        _ directory: URL,
        placement: QuickOpenDirectoryPlacement
    ) {
        guard let handler else {
            Self.logger.warning("Quick Open directory dispatch had no workspace handler")
            return
        }
        handler.executeQuickOpenDirectory(directory, placement: placement)
    }

    func canDispatch(_ command: AppCommand) -> Bool {
        guard let definition = definitions[command],
            definition.targeting.supportsContextualInvocation
        else {
            return false
        }
        return canExecutionOwnersExecute(command, definition: definition)
    }

    func canDispatch(_ request: AppCommandExecutionRequest) -> Bool {
        guard let definition = definitions[request.command],
            definition.targeting.supportsContextualInvocation
        else {
            return false
        }
        guard request.arguments != .noArguments else {
            return canDispatch(request.command)
        }
        if definition.requiresManagementLayer,
            !atom(\.managementLayer).isActive
        {
            return false
        }
        return appCommandRouter?.canExecute(request) ?? false
    }

    func canDispatch(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool {
        canDispatch(
            command,
            target: target,
            targetType: targetType,
            executionContext: .interactive
        )
    }

    func canDispatch(
        _ command: AppCommand,
        target: UUID,
        targetType: SearchItemType,
        executionContext: AppCommandExecutionContext
    ) -> Bool {
        guard let definition = definitions[command],
            Self.supportsTargetedDispatch(
                definition: definition,
                executionContext: executionContext,
                targetType: targetType
            )
        else {
            return false
        }
        return canExecutionOwnersExecute(
            command,
            definition: definition,
            target: target,
            targetType: targetType
        )
    }

    static func supportsTargetedDispatch(
        definition: AppCommandSpec,
        executionContext: AppCommandExecutionContext,
        targetType: SearchItemType
    ) -> Bool {
        switch executionContext {
        case .interactive:
            definition.targeting.supports(targetType: targetType)
        case .headlessIPC:
            switch definition.command.ipcSpec.exposure {
            case .headless(let durableTarget, _),
                .headlessAndInteractive(let durableTarget, _):
                durableTarget.supports(targetType: targetType)
            case .notExposed, .interactive, .uiPresentation:
                false
            }
        }
    }

    private func canExecutionOwnersExecute(
        _ command: AppCommand,
        definition: AppCommandSpec,
        target: UUID,
        targetType: SearchItemType
    ) -> Bool {
        if definition.requiresManagementLayer,
            !atom(\.managementLayer).isActive
        {
            return false
        }
        let appCanExecute = appCommandRouter?.canExecute(command, target: target, targetType: targetType) ?? false
        let handlerCanExecute = handler?.canExecute(command, target: target, targetType: targetType) ?? false
        return appCanExecute || handlerCanExecute
    }

    func bridgePaneCommandTarget(worktreeId: UUID) -> BridgePaneCommandTarget? {
        handler?.bridgePaneCommandTarget(worktreeId: worktreeId)
    }

    func definition(for command: AppCommand) -> AppCommandSpec {
        guard let definition = definitions[command] else {
            fatalError("Missing command spec for \(command.rawValue)")
        }
        return definition
    }

    func commands(for itemType: SearchItemType) -> [AppCommandSpec] {
        definitions.values.filter { $0.targeting.supports(targetType: itemType) }
    }

    func repoExplorerCommandPresentationSnapshot(
        requests: Set<RepoExplorerCommandPresentationRequest>,
        generation: UInt64
    ) -> RepoExplorerCommandPresentationSnapshot {
        let handlerCapabilities = handler?.repoExplorerCommandCapabilities(requests) ?? [:]
        var results: [RepoExplorerCommandPresentationRequest: Bool] = [:]
        results.reserveCapacity(requests.count)

        for request in requests {
            guard let definition = definitions[request.command] else { continue }
            let presentationQuery: AppCommandPresentationQuery
            if let targetType = request.targetType {
                guard request.target != nil else { continue }
                presentationQuery = AppCommandPresentationQuery(
                    surface: request.surface,
                    subject: .targeted(targetType)
                )
            } else {
                guard request.target == nil else { continue }
                presentationQuery = AppCommandPresentationQuery(
                    surface: request.surface,
                    subject: .contextual(.empty)
                )
            }
            guard definition.shouldPresent(presentationQuery) else { continue }
            guard !definition.requiresManagementLayer || atom(\.managementLayer).isActive else {
                results[request] = false
                continue
            }

            let appCanExecute: Bool
            switch request.arguments {
            case .noArguments:
                if let target = request.target, let targetType = request.targetType {
                    appCanExecute =
                        appCommandRouter?.canExecute(
                            request.command,
                            target: target,
                            targetType: targetType
                        ) ?? false
                } else {
                    appCanExecute = appCommandRouter?.canExecute(request.command) ?? false
                }
            case .repoSidebarSortOrder(let order):
                appCanExecute =
                    appCommandRouter?.canExecute(
                        AppCommandExecutionRequest(
                            command: request.command,
                            arguments: .repoSidebarSortOrder(order)
                        )
                    ) ?? false
            }
            results[request] = appCanExecute || (handlerCapabilities[request] ?? false)
        }

        return RepoExplorerCommandPresentationSnapshot(
            generation: generation,
            results: results
        )
    }

    private func canExecutionOwnersExecute(
        _ command: AppCommand,
        definition: AppCommandSpec
    ) -> Bool {
        if definition.requiresManagementLayer,
            !atom(\.managementLayer).isActive
        {
            return false
        }
        let appCanExecute = appCommandRouter?.canExecute(command) ?? false
        let handlerCanExecute = handler?.canExecute(command) ?? false
        return appCanExecute || handlerCanExecute
    }
}
