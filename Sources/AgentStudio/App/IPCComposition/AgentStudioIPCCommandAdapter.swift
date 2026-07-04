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
        let executionArguments = try executionArguments(
            command: command,
            rawArguments: params.arguments,
            argumentsContainOnlyStrings: params.argumentsContainOnlyStrings,
            argumentSchema: definition.argumentSchema
        )

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
                arguments: executionArguments
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

    private func executionArguments(
        command: AppCommand,
        rawArguments: [String: String],
        argumentsContainOnlyStrings: Bool,
        argumentSchema: [IPCCommandArgumentSchema]
    ) throws -> AppCommandExecutionArguments? {
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
                throw AppIPCCommandError(reason: .validationRejected)
            }
            return .repoSidebarVisibilityMode(mode)
        case .setRepoSidebarSortOrder:
            guard
                let rawOrder = rawArguments["order"],
                let order = RepoExplorerSortOrder(rawValue: rawOrder)
            else {
                throw AppIPCCommandError(reason: .validationRejected)
            }
            return .repoSidebarSortOrder(order)
        default:
            guard rawArguments.isEmpty else {
                throw AppIPCCommandError(reason: .validationRejected)
            }
            return nil
        }
    }

    private func validate(
        rawArguments: [String: String],
        argumentsContainOnlyStrings: Bool,
        against argumentSchema: [IPCCommandArgumentSchema]
    ) throws {
        guard argumentsContainOnlyStrings else {
            throw AppIPCCommandError(reason: .validationRejected)
        }
        let schemaByName = Dictionary(uniqueKeysWithValues: argumentSchema.map { ($0.name, $0) })
        guard Set(rawArguments.keys).isSubset(of: Set(schemaByName.keys)) else {
            throw AppIPCCommandError(reason: .validationRejected)
        }

        for argument in argumentSchema where argument.isRequired {
            guard rawArguments[argument.name] != nil else {
                throw AppIPCCommandError(reason: .validationRejected)
            }
        }

        for (name, value) in rawArguments {
            guard let schema = schemaByName[name] else {
                throw AppIPCCommandError(reason: .validationRejected)
            }
            switch schema.kind {
            case .stringEnum(let values):
                guard values.contains(value) else {
                    throw AppIPCCommandError(reason: .validationRejected)
                }
            }
        }
    }
}
