import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation

struct FakeQueryPort: AppIPCQueryPort {
    let runtimeId: UUID
    let panes: [IPCPaneSummary]

    nonisolated init(runtimeId: UUID = UUID(), panes: [IPCPaneSummary] = []) {
        self.runtimeId = runtimeId
        self.panes = panes
    }

    func systemIdentify() throws -> IPCSystemIdentifyResult {
        IPCSystemIdentifyResult(runtimeId: runtimeId, accessMode: .agentStudioOnly, appVersion: "test")
    }

    func systemVersion() throws -> IPCSystemVersionResult {
        IPCSystemVersionResult(appVersion: "test")
    }

    func systemCapabilities() throws -> IPCSystemCapabilitiesResult {
        IPCSystemCapabilitiesResult(methods: [])
    }

    func listWindows() throws -> IPCWindowListResult {
        IPCWindowListResult(windows: [])
    }

    func currentWindow() throws -> IPCCurrentWindowResult {
        throw AppIPCQueryError(reason: .noActiveWindow)
    }

    func listWorkspaces() throws -> IPCWorkspaceListResult {
        IPCWorkspaceListResult(workspaces: [])
    }

    func currentWorkspace() throws -> IPCCurrentWorkspaceResult {
        throw AppIPCQueryError(reason: .noActiveWindow)
    }

    func listPanes() throws -> IPCPaneListResult {
        IPCPaneListResult(panes: panes)
    }

    func currentPane() throws -> IPCPaneSnapshotResult {
        throw AppIPCQueryError(reason: .noActiveWindow)
    }

    func snapshotPane(_: UUID) throws -> IPCPaneSnapshotResult {
        throw AppIPCQueryError(reason: .targetNotFound)
    }
}

struct FakeLayoutPort: AppIPCLayoutPort {
    func focusPane(_: IPCHandle) throws -> IPCPaneFocusResult {
        throw AppIPCLayoutError(reason: .targetNotFound)
    }
}

struct FakeRuntimePort: AppIPCRuntimePort {
    let successfulPaneId: UUID?

    nonisolated init(successfulPaneId: UUID? = nil) {
        self.successfulPaneId = successfulPaneId
    }

    func terminalStatus(_: IPCHandle) throws -> IPCTerminalStatusResult {
        guard let successfulPaneId else {
            throw AppIPCRuntimeError(reason: .noRuntime)
        }
        return IPCTerminalStatusResult(
            paneId: successfulPaneId,
            lifecycle: .ready,
            isReady: true,
            backend: .local,
            capabilities: []
        )
    }

    func terminalSnapshot(_: IPCHandle) throws -> IPCTerminalSnapshotResult {
        guard let successfulPaneId else {
            throw AppIPCRuntimeError(reason: .noRuntime)
        }
        return IPCTerminalSnapshotResult(
            paneId: successfulPaneId,
            lifecycle: .ready,
            backend: .local,
            capabilities: [],
            lastSequence: 0,
            timestamp: Date(timeIntervalSince1970: 0),
            rendererHealthy: true,
            readOnly: false,
            secureInput: false
        )
    }

    func sendTerminalInput(
        to _: IPCHandle,
        input _: String,
        correlationId: UUID?
    ) async throws -> IPCTerminalSendInputResult {
        guard let successfulPaneId else {
            throw AppIPCRuntimeError(reason: .noRuntime)
        }
        return IPCTerminalSendInputResult(
            paneId: successfulPaneId,
            commandId: UUID(),
            correlationId: correlationId,
            disposition: .accepted,
            queuePosition: nil
        )
    }

    func waitForTerminal(
        _: IPCHandle,
        condition _: IPCTerminalWaitCondition,
        timeout _: Duration
    ) async throws -> IPCTerminalWaitResult {
        throw AppIPCRuntimeError(reason: .timeout)
    }
}

struct FakeCommandPort: AppIPCCommandPort {
    let workspaceWindowId: UUID?
    let activeScope: IPCCommandBarScope?

    nonisolated init(workspaceWindowId: UUID? = nil, activeScope: IPCCommandBarScope? = nil) {
        self.workspaceWindowId = workspaceWindowId
        self.activeScope = activeScope
    }

    func listCommands() throws -> IPCCommandListResult {
        IPCCommandListResult(
            commands: IPCCommandIdentifier.allCases.map { commandId in
                IPCCommandListEntry(id: commandId, title: commandId.rawValue)
            })
    }

    func executeCommand(_ params: IPCCommandExecuteParams) throws -> IPCCommandExecuteResult {
        guard let workspaceWindowId, let activeScope else {
            throw AppIPCCommandError(reason: .noActiveWindow)
        }
        return IPCCommandExecuteResult(
            commandId: params.commandId,
            applied: true,
            workspaceWindowId: workspaceWindowId,
            commandBar: IPCCommandBarPostcondition(workspaceWindowId: workspaceWindowId, scope: activeScope)
        )
    }
}

struct FakePermissionApprovalPort: AppIPCPermissionApprovalPort {
    func decision(for _: PermissionRecord, requester _: IPCPrincipal) -> ApprovalPolicyDecision {
        .ask
    }
}

extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
