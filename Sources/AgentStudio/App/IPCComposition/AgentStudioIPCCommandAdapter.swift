import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation

@MainActor
struct AgentStudioIPCCommandAdapter: AppIPCCommandPort, @unchecked Sendable {
    private let windowLifecycleReader: any WorkspaceWindowLifecycleReading
    private weak var shellCommandHandler: (any ShellCommandHandling)?

    init(
        windowLifecycleReader: any WorkspaceWindowLifecycleReading,
        shellCommandHandler: any ShellCommandHandling
    ) {
        self.windowLifecycleReader = windowLifecycleReader
        self.shellCommandHandler = shellCommandHandler
    }

    func listCommands() throws -> IPCCommandListResult {
        let commands = AppCommand.allCases
            .map(\.definition)
            .map(\.ipcCommandListEntry)
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
        let executionArguments: AppCommandExecutionArguments?
        do {
            executionArguments = try AppCommandExecutionArguments.commandOwnedArguments(
                command: command,
                rawArguments: params.arguments,
                argumentsContainOnlyStrings: params.argumentsContainOnlyStrings,
                argumentSchema: definition.argumentSchema
            )
        } catch AppCommandArgumentDecodingError.validationRejected {
            throw AppIPCCommandError(reason: .validationRejected)
        }

        let lifecycle = windowLifecycleReader.snapshot()
        guard
            let workspaceWindowId = lifecycle.preferredWorkspaceWindowId,
            lifecycle.registeredWindowIds.contains(workspaceWindowId)
        else {
            throw AppIPCCommandError(reason: .noActiveWindow)
        }
        guard let shellCommandHandler else {
            throw AppIPCCommandError(reason: .stateUnavailable)
        }
        let outcome = shellCommandHandler.execute(
            AppCommandExecutionRequest(
                command: command,
                arguments: executionArguments,
                executionContext: .headlessIPC
            )
        )
        switch outcome {
        case .applied:
            return IPCCommandExecuteResult(
                commandId: params.commandId,
                applied: true,
                targetHandle: params.targetHandle
            )
        case .stateUnavailable:
            throw AppIPCCommandError(reason: .stateUnavailable)
        case .unsupportedCommand:
            throw AppIPCCommandError(reason: .unsupportedCommand)
        }
    }

}
