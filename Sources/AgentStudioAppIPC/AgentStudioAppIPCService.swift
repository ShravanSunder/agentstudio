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
    func splitPane(_ params: IPCPaneSplitParams) throws -> IPCPaneSplitResult
    func closePane(_ params: IPCPaneCloseParams) throws -> IPCPaneCloseResult
    func addDrawerPane(_ params: IPCDrawerAddPaneParams) throws -> IPCDrawerAddPaneResult
    func toggleDrawer(_ params: IPCDrawerToggleParams) throws -> IPCDrawerToggleResult
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
        case replayGap
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
        timeout: Duration,
        afterSequence: UInt64?
    ) async throws -> IPCTerminalWaitResult
}

public struct AppIPCCommandError: Error, Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        case noActiveWindow
        case targetNotFound
        case unsupportedCommand
        case requiresPresentation
        case requiresTarget
        case requiresParameters
        case validationRejected
        case stateUnavailable
    }

    public let reason: Reason

    public init(reason: Reason) {
        self.reason = reason
    }
}

@MainActor
public protocol AppIPCCommandPort: Sendable {
    func listCommands() throws -> IPCCommandListResult
    func executeCommand(_ params: IPCCommandExecuteParams) throws -> IPCCommandExecuteResult
}

public protocol AppIPCPermissionApprovalPort: Sendable {
    func decision(for record: PermissionRecord, requester: IPCPrincipal) -> ApprovalPolicyDecision
}

public struct AppIPCUIPresentationError: Error, Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        case noActiveWindow
        case validationRejected
    }

    public let reason: Reason

    public init(reason: Reason) {
        self.reason = reason
    }
}

@MainActor
public protocol AppIPCUIPresentationPort: Sendable {
    func openCommandBar(_ params: IPCCommandBarOpenParams) throws -> IPCCommandBarOpenResult
}

@MainActor
public protocol AppIPCSidebarPort: Sendable {
    func getGrouping(_ params: IPCSidebarGroupingGetParams) throws -> IPCSidebarGroupingResult
    func getSurface(_ params: IPCSidebarSurfaceGetParams) throws -> IPCSidebarSurfaceResult
}

public struct AgentStudioAppIPCPorts: Sendable {
    public let queryPort: any AppIPCQueryPort
    public let layoutPort: any AppIPCLayoutPort
    public let runtimePort: any AppIPCRuntimePort
    public let commandPort: any AppIPCCommandPort
    public let uiPresentationPort: any AppIPCUIPresentationPort
    public let sidebarPort: any AppIPCSidebarPort
    public let permissionApprovalPort: any AppIPCPermissionApprovalPort

    public init(
        queryPort: any AppIPCQueryPort,
        layoutPort: any AppIPCLayoutPort,
        runtimePort: any AppIPCRuntimePort,
        commandPort: any AppIPCCommandPort,
        uiPresentationPort: any AppIPCUIPresentationPort,
        sidebarPort: any AppIPCSidebarPort,
        permissionApprovalPort: any AppIPCPermissionApprovalPort
    ) {
        self.queryPort = queryPort
        self.layoutPort = layoutPort
        self.runtimePort = runtimePort
        self.commandPort = commandPort
        self.uiPresentationPort = uiPresentationPort
        self.sidebarPort = sidebarPort
        self.permissionApprovalPort = permissionApprovalPort
    }
}

public struct AgentStudioAppIPCConfiguration: Equatable, Sendable {
    public let runtimeId: UUID
    public let accessMode: IPCAccessMode
    public let methodDefinitions: [IPCMethodDefinition]
    public let debugTokenEscrowEnabled: Bool

    public init(
        runtimeId: UUID,
        accessMode: IPCAccessMode,
        methodDefinitions: [IPCMethodDefinition],
        debugTokenEscrowEnabled: Bool = false
    ) {
        self.runtimeId = runtimeId
        self.accessMode = accessMode
        self.methodDefinitions = methodDefinitions
        self.debugTokenEscrowEnabled = debugTokenEscrowEnabled
    }
}

public struct AgentStudioAppIPCService: Sendable {
    public let configuration: AgentStudioAppIPCConfiguration
    public let ports: AgentStudioAppIPCPorts
    public let eventBroker: IPCEventBroker
    package let methodRegistry: AppIPCMethodRegistry

    public init(
        configuration: AgentStudioAppIPCConfiguration,
        ports: AgentStudioAppIPCPorts,
        eventBroker: IPCEventBroker = IPCEventBroker()
    ) {
        self.configuration = configuration
        self.ports = ports
        self.eventBroker = eventBroker
        self.methodRegistry = AppIPCMethodRegistry(definitions: configuration.methodDefinitions)
    }

    package init(
        configuration: AgentStudioAppIPCConfiguration,
        ports: AgentStudioAppIPCPorts,
        eventBroker: IPCEventBroker = IPCEventBroker(),
        methodContributions: [AppIPCMethodContribution]
    ) throws {
        let methodRegistry = try AppIPCMethodRegistry(
            baseDefinitions: configuration.methodDefinitions,
            contributions: methodContributions
        )
        self.configuration = AgentStudioAppIPCConfiguration(
            runtimeId: configuration.runtimeId,
            accessMode: configuration.accessMode,
            methodDefinitions: methodRegistry.definitions,
            debugTokenEscrowEnabled: configuration.debugTokenEscrowEnabled
        )
        self.ports = ports
        self.eventBroker = eventBroker
        self.methodRegistry = methodRegistry
    }
}
