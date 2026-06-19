import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation

@MainActor
struct AgentStudioIPCCommandAdapter: AppIPCCommandPort, @unchecked Sendable {
    private let windowLifecycleReader: any WorkspaceWindowLifecycleReading

    init(
        windowLifecycleReader: any WorkspaceWindowLifecycleReading
    ) {
        self.windowLifecycleReader = windowLifecycleReader
    }

    func listCommands() throws -> IPCCommandListResult {
        let commands = AppCommand.allCases
            .map(\.definition)
            .map { definition in
                IPCCommandListEntry(
                    id: IPCCommandIdentifier(rawValue: definition.command.rawValue),
                    title: definition.label,
                    executionModes: definition.ipcExposure.executionModes,
                    targetKinds: definition.ipcExposure.targetKinds,
                    requiredPrivileges: definition.ipcExposure.requiredPrivileges
                )
            }
            .sorted { left, right in
                left.id.rawValue < right.id.rawValue
            }
        return IPCCommandListResult(commands: commands)
    }

    func executeCommand(_ params: IPCCommandExecuteParams) throws -> IPCCommandExecuteResult {
        guard params.targetHandle == nil else {
            throw AppIPCCommandError(reason: .targetNotFound)
        }
        guard let command = AppCommand(rawValue: params.commandId.rawValue) else {
            throw AppIPCCommandError(reason: .unsupportedCommand)
        }
        let definition = command.definition
        guard definition.ipcExposure.commandListEntryIsHeadlessExecutable else {
            if definition.ipcExposure.executionModes.contains(.uiPresentation) {
                throw AppIPCCommandError(reason: .requiresPresentation)
            }
            throw AppIPCCommandError(reason: .requiresParameters)
        }

        let lifecycle = windowLifecycleReader.snapshot()
        guard
            let workspaceWindowId = lifecycle.preferredWorkspaceWindowId,
            lifecycle.registeredWindowIds.contains(workspaceWindowId)
        else {
            throw AppIPCCommandError(reason: .noActiveWindow)
        }
        throw AppIPCCommandError(reason: .unsupportedCommand)
    }
}
