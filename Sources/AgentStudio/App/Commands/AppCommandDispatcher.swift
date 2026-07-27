import AgentStudioCore
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
        if request.arguments != nil {
            guard let appCommandRouter else { return .unsupportedCommand }
            return appCommandRouter.execute(request)
        }

        guard canDispatch(request.command) else {
            Self.logger.warning("Command request rejected: \(request.command.rawValue, privacy: .public)")
            return .unsupportedCommand
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
        guard canDispatch(command, target: target, targetType: targetType) else {
            Self.logger.warning(
                "Targeted command dispatch rejected: \(command.rawValue, privacy: .public) targetType=\(targetType.rawValue, privacy: .public)"
            )
            return
        }
        if appCommandRouter?.execute(command, target: target, targetType: targetType) == true {
            return
        }
        guard let handler else {
            Self.logger.warning(
                "Targeted command dispatch had no workspace handler: \(command.rawValue, privacy: .public)"
            )
            return
        }
        handler.execute(command, target: target, targetType: targetType)
    }

    func dispatchExtractPaneToTab(tabId: UUID, paneId: UUID, targetTabIndex: Int?) {
        guard canDispatch(.extractPaneToTab) else { return }
        handler?.executeExtractPaneToTab(tabId: tabId, paneId: paneId, targetTabIndex: targetTabIndex)
    }

    func dispatchMovePaneToTab(sourcePaneId: UUID, sourceTabId: UUID?, targetTabId: UUID) {
        guard canDispatch(.movePaneToTab) else { return }
        handler?.executeMovePaneToTab(
            sourcePaneId: sourcePaneId,
            sourceTabId: sourceTabId,
            targetTabId: targetTabId
        )
    }

    func canDispatch(_ command: AppCommand) -> Bool {
        if let definition = definitions[command],
            definition.requiresManagementLayer,
            !atom(\.managementLayer).isActive
        {
            return false
        }
        let appCanExecute = appCommandRouter?.canExecute(command) ?? false
        let handlerCanExecute = handler?.canExecute(command) ?? false
        return appCanExecute || handlerCanExecute
    }

    func canDispatch(_ command: AppCommand, target: UUID, targetType: SearchItemType) -> Bool {
        if let definition = definitions[command],
            definition.requiresManagementLayer,
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
        definitions.values.filter { $0.appliesTo.contains(itemType) }
    }
}
