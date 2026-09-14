import AgentStudioAppIPC
import AgentStudioCore
import AgentStudioProgrammaticControl
import Foundation

@MainActor
protocol WorkspaceDurableTargetAuthorizing: AnyObject {
    func containsRepository(id: UUID) -> Bool
    func containsTab(id: UUID) -> Bool
    func containsPane(id: UUID) -> Bool
}

@MainActor
struct AgentStudioIPCCommandAdapter: AppIPCCommandPort, @unchecked Sendable {
    private let workspaceId: UUID
    private let targetAuthorizer: any WorkspaceDurableTargetAuthorizing
    private weak var shellCommandHandler: (any ShellCommandHandling)?

    init(
        workspaceId: UUID,
        targetAuthorizer: any WorkspaceDurableTargetAuthorizing,
        shellCommandHandler: any ShellCommandHandling
    ) {
        self.workspaceId = workspaceId
        self.targetAuthorizer = targetAuthorizer
        self.shellCommandHandler = shellCommandHandler
    }

    func listCommands() throws -> IPCCommandCatalogResult {
        let commands = try AppCommand.allCases
            .filter { $0.ipcSpec.exposure == .allChannels }
            .map(makeDescriptor)
            .sorted { $0.id.rawValue < $1.id.rawValue }
        return IPCCommandCatalogResult(compatibility: .current, commands: commands)
    }

    func prepareCommand(
        _ request: IPCCommandExecutionRequest,
        principal _: IPCPrincipal,
        tools: AppIPCTargetResolutionTools
    ) async throws -> AppIPCPreparedCommand {
        let command = try activeCommand(for: request)
        guard command.ipcSpec.argumentVariants.contains(request.arguments.variant) else {
            throw AppIPCCommandError(reason: .validationRejected)
        }
        let resolved = try await resolve(request.arguments, tools: tools)
        let privilege = command.ipcSpec.requiredPrivilege
        return AppIPCPreparedCommand(
            request: IPCCommandExecutionRequest(
                commandId: request.commandId,
                correlationId: request.correlationId,
                arguments: resolved.arguments
            ),
            canonicalHandle: resolved.handle,
            target: resolved.target,
            requiredScopes: [
                IPCPermissionScope(
                    privilege: privilege,
                    target: resolved.target,
                    dataScope: PermissionScopeCanonicalizer.dataScope(for: privilege)
                )
            ]
        )
    }

    func executeCommand(_ request: IPCCommandExecutionRequest) async throws -> IPCCommandExecutionResult {
        let command = try activeCommand(for: request)
        switch request.arguments {
        case .workspaceWindow(let value):
            try validateWindow(value.workspaceWindowId)
            return try executeShell(command, request: request)
        case .repository(let value):
            guard targetAuthorizer.containsRepository(id: value.repoId) else {
                throw AppIPCCommandError(reason: .targetNotFound)
            }
            return try await executeTargeted(
                command,
                id: value.repoId,
                type: .repo,
                workspaceWindowId: nil,
                request: request
            )
        case .standalonePane(let value):
            return try await executeTargeted(
                command,
                id: try canonicalPaneId(value.paneSelector),
                type: .pane,
                workspaceWindowId: nil,
                request: request
            )
        case .pane(let value):
            try validateWindow(value.workspaceWindowId)
            return try await executeTargeted(
                command,
                id: try canonicalPaneId(value.paneSelector),
                type: .pane,
                workspaceWindowId: value.workspaceWindowId,
                request: request
            )
        default:
            throw AppIPCCommandError(reason: .validationRejected)
        }
    }

    private func activeCommand(for request: IPCCommandExecutionRequest) throws -> AppCommand {
        guard let command = AppCommand(rawValue: request.commandId.rawValue) else {
            throw AppIPCCommandError(reason: .unknownCommand)
        }
        guard command.ipcSpec.exposure == .allChannels else {
            throw AppIPCCommandError(reason: .unsupportedCommand)
        }
        guard command.ipcSpec.argumentVariants.contains(request.arguments.variant) else {
            throw IPCSchemaValidationError(
                fieldPath: "$.arguments.kind",
                reason: .invalidValue,
                expected: "one argument variant declared by the selected command"
            )
        }
        return command
    }

    private func makeDescriptor(_ command: AppCommand) throws -> IPCCommandDescriptor {
        let example = try exampleRequest(for: command)
        let result: IPCCommandExecutionResult =
            command == .reloadBridgeWebView
            ? .accepted(
                IPCCommandAcceptedResult(
                    commandId: example.commandId, correlationId: example.correlationId, operationId: nil))
            : .applied(IPCCommandAppliedResult(commandId: example.commandId, correlationId: example.correlationId))
        return try IPCCommandDescriptorFactory.make(
            command.ipcSpec.descriptorInput(
                definition: command.definition,
                examples: [
                    IPCCommandExample(
                        description: "Execute with explicit typed context.", request: example, result: result)
                ]
            ))
    }

    private func exampleRequest(for command: AppCommand) throws -> IPCCommandExecutionRequest {
        let window = Self.exampleUUID("01994abc-4000-7000-8000-000000000001")
        let target = Self.exampleUUID("01994abc-4000-7000-8000-000000000002")
        let arguments: IPCCommandArguments =
            switch command.ipcSpec.argumentVariants.first {
            case .workspaceWindow: .workspaceWindow(.init(workspaceWindowId: window))
            case .repository: .repository(.init(repoId: target))
            case .standalonePane: .standalonePane(.init(paneSelector: try .init(rawValue: target.uuidString)))
            case .pane: .pane(.init(workspaceWindowId: window, paneSelector: try .init(rawValue: target.uuidString)))
            default: throw AppIPCCommandError(reason: .validationRejected)
            }
        return IPCCommandExecutionRequest(
            commandId: .init(rawValue: command.rawValue),
            correlationId: Self.exampleUUID("01994abc-4000-7000-8000-000000000003"),
            arguments: arguments)
    }

    private func resolve(
        _ arguments: IPCCommandArguments,
        tools: AppIPCTargetResolutionTools
    ) async throws -> (arguments: IPCCommandArguments, handle: IPCHandle?, target: IPCTargetScope) {
        switch arguments {
        case .workspaceWindow(let value):
            try validateWindow(value.workspaceWindowId)
            return (
                arguments, .init(kind: .window, reference: .canonicalUUID(value.workspaceWindowId)),
                .workspace(workspaceId)
            )
        case .repository(let value):
            guard targetAuthorizer.containsRepository(id: value.repoId) else {
                throw AppIPCCommandError(reason: .targetNotFound)
            }
            return (arguments, .init(kind: .repo, reference: .canonicalUUID(value.repoId)), .workspace(workspaceId))
        case .standalonePane(let value):
            let resolved = try await resolvePane(value.paneSelector, tools: tools)
            return (.standalonePane(.init(paneSelector: resolved.selector)), resolved.handle, resolved.target)
        case .pane(let value):
            try validateWindow(value.workspaceWindowId)
            let resolved = try await resolvePane(value.paneSelector, tools: tools)
            return (
                .pane(.init(workspaceWindowId: value.workspaceWindowId, paneSelector: resolved.selector)),
                resolved.handle, resolved.target
            )
        default: throw AppIPCCommandError(reason: .validationRejected)
        }
    }

    private func resolvePane(
        _ selector: IPCPaneSelector,
        tools: AppIPCTargetResolutionTools
    ) async throws -> (selector: IPCPaneSelector, handle: IPCHandle, target: IPCTargetScope) {
        let handle = try await tools.canonicalizePaneHandle(selector.rawValue)
        guard case (.pane, .canonicalUUID(let paneId)) = (handle.kind, handle.reference),
            targetAuthorizer.containsPane(id: paneId)
        else { throw AppIPCCommandError(reason: .targetNotFound) }
        return (try .init(rawValue: paneId.uuidString), handle, .pane(paneId.uuidString))
    }

    private func executeShell(_ command: AppCommand, request: IPCCommandExecutionRequest) throws
        -> IPCCommandExecutionResult
    {
        guard let shellCommandHandler else { throw AppIPCCommandError(reason: .stateUnavailable) }
        let outcome = shellCommandHandler.execute(.init(command: command, executionContext: .headlessIPC))
        guard outcome == .applied else {
            throw AppIPCCommandError(reason: outcome == .stateUnavailable ? .stateUnavailable : .unsupportedCommand)
        }
        return .applied(.init(commandId: request.commandId, correlationId: request.correlationId))
    }

    private func executeTargeted(
        _ command: AppCommand,
        id: UUID,
        type: SearchItemType,
        workspaceWindowId: UUID?,
        request: IPCCommandExecutionRequest
    ) async throws -> IPCCommandExecutionResult {
        guard
            await AppCommandDispatcher.shared.dispatchHeadlessIPC(
                command,
                target: id,
                targetType: type,
                workspaceWindowId: workspaceWindowId
            )
        else {
            throw AppIPCCommandError(reason: .targetNotFound)
        }
        return command == .reloadBridgeWebView
            ? .accepted(.init(commandId: request.commandId, correlationId: request.correlationId, operationId: nil))
            : .applied(.init(commandId: request.commandId, correlationId: request.correlationId))
    }

    private func validateWindow(_ id: UUID) throws {
        guard let shellCommandHandler, shellCommandHandler.ownsWorkspaceWindow(id) else {
            throw AppIPCCommandError(reason: .targetNotFound)
        }
    }

    private func canonicalPaneId(_ selector: IPCPaneSelector) throws -> UUID {
        guard case .canonical(kind: .pane, id: let id) = selector.parsed,
            targetAuthorizer.containsPane(id: id)
        else { throw AppIPCCommandError(reason: .targetNotFound) }
        return id
    }

    private static func exampleUUID(_ raw: String) -> UUID {
        guard let value = UUID(uuidString: raw) else { preconditionFailure("Invalid command example UUID") }
        return value
    }

}
