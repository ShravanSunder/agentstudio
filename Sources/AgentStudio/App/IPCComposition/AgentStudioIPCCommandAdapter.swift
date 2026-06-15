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
        IPCCommandListResult(commands: [])
    }

    func executeCommand(_ params: IPCCommandExecuteParams) throws -> IPCCommandExecuteResult {
        guard params.targetHandle == nil else {
            throw AppIPCCommandError(reason: .targetNotFound)
        }
        guard !Self.presentationOnlyCommandIds.contains(params.commandId) else {
            throw AppIPCCommandError(reason: .requiresPresentation)
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

    private static let presentationOnlyCommandIds: Set<IPCCommandIdentifier> = [
        .quickFind,
        .commandPalette,
        .panePicker,
        .repoWorktreePicker,
    ]
}
