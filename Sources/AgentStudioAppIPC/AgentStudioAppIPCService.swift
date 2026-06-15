import AgentStudioProgrammaticControl
import Foundation

public struct AppIPCQueryError: Error, Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        case noActiveWindow
        case targetNotFound
    }

    public let reason: Reason

    public init(reason: Reason) {
        self.reason = reason
    }
}

@MainActor
public protocol AppIPCQueryPort: Sendable {
    func systemIdentify() throws -> IPCSystemIdentifyResult
    func systemVersion() throws -> IPCSystemVersionResult
    func systemCapabilities() throws -> IPCSystemCapabilitiesResult
    func listWindows() throws -> IPCWindowListResult
    func currentWindow() throws -> IPCCurrentWindowResult
    func listWorkspaces() throws -> IPCWorkspaceListResult
    func currentWorkspace() throws -> IPCCurrentWorkspaceResult
    func listPanes() throws -> IPCPaneListResult
    func currentPane() throws -> IPCPaneSnapshotResult
    func snapshotPane(_ paneId: UUID) throws -> IPCPaneSnapshotResult
}

public struct AppIPCLayoutError: Error, Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        case noActiveWindow
        case targetNotFound
        case validationRejected
    }

    public let reason: Reason

    public init(reason: Reason) {
        self.reason = reason
    }
}

@MainActor
public protocol AppIPCLayoutPort: Sendable {
    func focusPane(_ handle: IPCHandle) throws -> IPCPaneFocusResult
}

public struct AppIPCRuntimeError: Error, Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        case targetNotFound
        case noRuntime
        case runtimeNotReady
        case unsupportedCommand
        case backendUnavailable
        case validationRejected
        case timeout
    }

    public let reason: Reason
    public let detail: String?

    public init(reason: Reason, detail: String? = nil) {
        self.reason = reason
        self.detail = detail
    }
}

@MainActor
public protocol AppIPCRuntimePort: Sendable {
    func terminalStatus(_ handle: IPCHandle) throws -> IPCTerminalStatusResult
    func terminalSnapshot(_ handle: IPCHandle) throws -> IPCTerminalSnapshotResult
    func sendTerminalInput(
        to handle: IPCHandle,
        input: String,
        correlationId: UUID?
    ) async throws -> IPCTerminalSendInputResult
    func waitForTerminal(
        _ handle: IPCHandle,
        condition: IPCTerminalWaitCondition,
        timeout: Duration
    ) async throws -> IPCTerminalWaitResult
}

public protocol AppIPCPermissionApprovalPort: Sendable {
    func decision(for record: PermissionRecord, requester: IPCPrincipal) -> ApprovalPolicyDecision
}

public struct AgentStudioAppIPCPorts: Sendable {
    public let queryPort: any AppIPCQueryPort
    public let layoutPort: any AppIPCLayoutPort
    public let runtimePort: any AppIPCRuntimePort
    public let permissionApprovalPort: any AppIPCPermissionApprovalPort

    public init(
        queryPort: any AppIPCQueryPort,
        layoutPort: any AppIPCLayoutPort,
        runtimePort: any AppIPCRuntimePort,
        permissionApprovalPort: any AppIPCPermissionApprovalPort
    ) {
        self.queryPort = queryPort
        self.layoutPort = layoutPort
        self.runtimePort = runtimePort
        self.permissionApprovalPort = permissionApprovalPort
    }
}

public struct AgentStudioAppIPCConfiguration: Equatable, Sendable {
    public let runtimeId: UUID
    public let accessMode: IPCAccessMode
    public let methodDefinitions: [IPCMethodDefinition]

    public init(runtimeId: UUID, accessMode: IPCAccessMode, methodDefinitions: [IPCMethodDefinition]) {
        self.runtimeId = runtimeId
        self.accessMode = accessMode
        self.methodDefinitions = methodDefinitions
    }
}

public struct AgentStudioAppIPCService: Sendable {
    public let configuration: AgentStudioAppIPCConfiguration
    public let ports: AgentStudioAppIPCPorts
    public let eventBroker: IPCEventBroker

    public init(
        configuration: AgentStudioAppIPCConfiguration,
        ports: AgentStudioAppIPCPorts,
        eventBroker: IPCEventBroker = IPCEventBroker()
    ) {
        self.configuration = configuration
        self.ports = ports
        self.eventBroker = eventBroker
    }
}
