import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation

@MainActor
protocol AgentStudioIPCCommandDispatching: AnyObject {
    func definition(for command: AppCommand) -> CommandSpec
    func canDispatch(_ command: AppCommand) -> Bool
    func dispatch(_ command: AppCommand)
}

extension CommandDispatcher: AgentStudioIPCCommandDispatching {}

@MainActor
struct AgentStudioIPCCommandAdapter: AppIPCCommandPort, @unchecked Sendable {
    private let dispatcher: any AgentStudioIPCCommandDispatching
    private let windowLifecycleReader: any WorkspaceWindowLifecycleReading
    private let commandBarSurface: CommandBarSurfaceAtom

    init(
        dispatcher: any AgentStudioIPCCommandDispatching = CommandDispatcher.shared,
        windowLifecycleReader: any WorkspaceWindowLifecycleReading,
        commandBarSurface: CommandBarSurfaceAtom
    ) {
        self.dispatcher = dispatcher
        self.windowLifecycleReader = windowLifecycleReader
        self.commandBarSurface = commandBarSurface
    }

    func listCommands() throws -> IPCCommandListResult {
        IPCCommandListResult(
            commands: IPCCommandIdentifier.allCases.map { commandId in
                let definition = dispatcher.definition(for: commandId.appCommand)
                return IPCCommandListEntry(id: commandId, title: definition.label)
            }
        )
    }

    func executeCommand(_ params: IPCCommandExecuteParams) throws -> IPCCommandExecuteResult {
        guard params.targetHandle == nil else {
            throw AppIPCCommandError(reason: .targetNotFound)
        }
        let lifecycle = windowLifecycleReader.snapshot()
        guard
            let workspaceWindowId = lifecycle.preferredWorkspaceWindowId,
            lifecycle.registeredWindowIds.contains(workspaceWindowId)
        else {
            throw AppIPCCommandError(reason: .noActiveWindow)
        }

        let command = params.commandId.appCommand
        guard dispatcher.canDispatch(command) else {
            throw AppIPCCommandError(reason: .validationRejected)
        }

        dispatcher.dispatch(command)
        guard
            let activeSurface = commandBarSurface.activeSurface,
            activeSurface.workspaceWindowId == workspaceWindowId,
            let scope = IPCCommandBarScope(activeSurface.scope)
        else {
            throw AppIPCCommandError(reason: .validationRejected)
        }

        return IPCCommandExecuteResult(
            commandId: params.commandId,
            applied: true,
            workspaceWindowId: workspaceWindowId,
            commandBar: IPCCommandBarPostcondition(workspaceWindowId: workspaceWindowId, scope: scope)
        )
    }
}

extension IPCCommandIdentifier {
    fileprivate var appCommand: AppCommand {
        switch self {
        case .quickFind:
            .showCommandBarEverything
        case .commandPalette:
            .showCommandBarCommands
        case .panePicker:
            .showCommandBarPanes
        case .repoWorktreePicker:
            .showCommandBarRepos
        }
    }
}

extension IPCCommandBarScope {
    fileprivate init?(_ scope: CommandBarScope) {
        switch scope {
        case .everything:
            self = .everything
        case .commands:
            self = .commands
        case .panes:
            self = .panes
        case .repos:
            self = .repos
        case .inbox:
            return nil
        }
    }
}
