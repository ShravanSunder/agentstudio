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
    }

    public let reason: Reason

    public init(reason: Reason) {
        self.reason = reason
    }
}

public struct AppIPCBridgeError: Error, Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        case noActiveWindow
        case targetNotFound
        case unsupportedTarget
        case packageUnavailable
        case itemNotFound
        case contentUnavailable
        case payloadTooLarge
        case validationRejected
    }

    public let reason: Reason

    public init(reason: Reason) {
        self.reason = reason
    }
}

@MainActor
public protocol AppIPCBridgePort: Sendable {
    func openReview(_ params: IPCBridgeReviewOpenParams) throws -> IPCBridgeReviewOpenResult
    func refreshReview(_ params: IPCBridgeReviewRefreshParams) async throws -> IPCBridgeReviewRefreshResult
    func getPackage(_ handle: IPCHandle) throws -> IPCBridgeReviewPackageResult
    func renderState(_ handle: IPCHandle) async throws -> IPCBridgeRenderStateResult
    func selectFile(_ params: IPCBridgeReviewSelectFileParams) async throws -> IPCBridgeReviewSelectFileResult
    func scrollToFile(_ params: IPCBridgeDiffScrollToFileParams) async throws -> IPCBridgePageControlResult
    func searchFileTree(_ params: IPCBridgeFileTreeSearchParams) async throws -> IPCBridgePageControlResult
    func setFileTreeFilter(_ params: IPCBridgeFileTreeSetFilterParams) async throws -> IPCBridgePageControlResult
    func revealFileTreePath(_ params: IPCBridgeFileTreeRevealPathParams) async throws -> IPCBridgePageControlResult
    func showMarkdownPreview(
        _ params: IPCBridgeFileViewShowMarkdownPreviewParams
    ) async throws -> IPCBridgePageControlResult
    func getContent(_ params: IPCBridgeContentGetParams) async throws -> IPCBridgeContentGetResult
    func telemetrySnapshot(_ handle: IPCHandle) throws -> IPCBridgeTelemetrySnapshotResult
    func flushTelemetry(_ handle: IPCHandle) async throws -> IPCBridgeTelemetryFlushResult
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

public struct AgentStudioAppIPCPorts: Sendable {
    public let queryPort: any AppIPCQueryPort
    public let layoutPort: any AppIPCLayoutPort
    public let runtimePort: any AppIPCRuntimePort
    public let bridgePort: any AppIPCBridgePort
    public let commandPort: any AppIPCCommandPort
    public let uiPresentationPort: any AppIPCUIPresentationPort
    public let permissionApprovalPort: any AppIPCPermissionApprovalPort

    public init(
        queryPort: any AppIPCQueryPort,
        layoutPort: any AppIPCLayoutPort,
        runtimePort: any AppIPCRuntimePort,
        bridgePort: any AppIPCBridgePort,
        commandPort: any AppIPCCommandPort,
        uiPresentationPort: any AppIPCUIPresentationPort,
        permissionApprovalPort: any AppIPCPermissionApprovalPort
    ) {
        self.queryPort = queryPort
        self.layoutPort = layoutPort
        self.runtimePort = runtimePort
        self.bridgePort = bridgePort
        self.commandPort = commandPort
        self.uiPresentationPort = uiPresentationPort
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
