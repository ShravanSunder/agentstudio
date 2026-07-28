import AgentStudioAppIPC
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
    private let windowLifecycleReader: any WorkspaceWindowLifecycleReading
    private weak var shellCommandHandler: (any ShellCommandHandling)?

    init(
        workspaceId: UUID,
        targetAuthorizer: any WorkspaceDurableTargetAuthorizing,
        windowLifecycleReader: any WorkspaceWindowLifecycleReading,
        shellCommandHandler: any ShellCommandHandling
    ) {
        self.workspaceId = workspaceId
        self.targetAuthorizer = targetAuthorizer
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

    func requiredPermissionScopes(for command: IPCCommandListEntry) throws -> [IPCPermissionScope] {
        guard let appCommand = AppCommand(rawValue: command.id.rawValue) else {
            throw AppIPCCommandError(reason: .unsupportedCommand)
        }
        return appCommand.definition.ipcExposure.requiredPrivileges.map { privilege in
            IPCPermissionScope(
                privilege: privilege,
                target: permissionTarget(for: privilege),
                dataScope: PermissionScopeCanonicalizer.dataScope(for: privilege)
            )
        }
    }

    func executeCommand(_ params: IPCCommandExecuteParams) throws -> IPCCommandExecuteResult {
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
        guard params.targetHandle != nil || definition.ipcExposure.targetKinds.isEmpty else {
            throw AppIPCCommandError(reason: .requiresTarget)
        }

        let lifecycle = windowLifecycleReader.snapshot()
        guard
            let workspaceWindowId = lifecycle.preferredWorkspaceWindowId,
            lifecycle.registeredWindowIds.contains(workspaceWindowId)
        else {
            throw AppIPCCommandError(reason: .noActiveWindow)
        }
        if let targetHandle = params.targetHandle {
            let target = try targetedCommandTarget(
                rawHandle: targetHandle,
                allowedKinds: definition.ipcExposure.targetKinds
            )
            guard
                AppCommandDispatcher.shared.canDispatch(
                    command,
                    target: target.id,
                    targetType: target.type
                )
            else {
                throw AppIPCCommandError(reason: .targetNotFound)
            }
            AppCommandDispatcher.shared.dispatch(
                command,
                target: target.id,
                targetType: target.type
            )
            return IPCCommandExecuteResult(
                commandId: params.commandId,
                applied: true,
                targetHandle: targetHandle
            )
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

    private func targetedCommandTarget(
        rawHandle: String,
        allowedKinds: [IPCHandleKind]
    ) throws -> (id: UUID, type: SearchItemType) {
        let handle: IPCHandle
        do {
            handle = try IPCHandle.parse(rawHandle)
        } catch {
            throw AppIPCCommandError(reason: .targetNotFound)
        }
        guard allowedKinds.contains(handle.kind), case .canonicalUUID(let targetId) = handle.reference else {
            throw AppIPCCommandError(reason: .targetNotFound)
        }
        switch handle.kind {
        case .repo:
            guard targetAuthorizer.containsRepository(id: targetId) else {
                throw AppIPCCommandError(reason: .targetNotFound)
            }
            return (targetId, .repo)
        case .tab:
            guard targetAuthorizer.containsTab(id: targetId) else {
                throw AppIPCCommandError(reason: .targetNotFound)
            }
            return (targetId, .tab)
        case .pane:
            guard targetAuthorizer.containsPane(id: targetId) else {
                throw AppIPCCommandError(reason: .targetNotFound)
            }
            return (targetId, .pane)
        case .window, .workspace:
            throw AppIPCCommandError(reason: .targetNotFound)
        }
    }

    private func permissionTarget(for privilege: IPCPrivilegeClass) -> IPCTargetScope {
        switch privilege {
        case .sidebarStateMutate:
            .workspace(workspaceId)
        default:
            .app
        }
    }
}
