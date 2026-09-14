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
    func splitPane(_ params: IPCPaneSplitParams) async throws -> IPCPaneSplitResult
    func closePane(_ params: IPCPaneCloseParams) async throws -> IPCPaneCloseResult
    func addDrawerPane(_ params: IPCDrawerAddPaneParams) async throws -> IPCDrawerAddPaneResult
    func toggleDrawer(_ params: IPCDrawerToggleParams) async throws -> IPCDrawerToggleResult
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
        case unknownCommand
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
    func openFileView(_ params: IPCBridgeFileViewOpenParams) throws -> IPCBridgeFileViewOpenResult
    func refreshReview(_ params: IPCBridgeReviewRefreshParams) async throws -> IPCBridgeReviewRefreshResult
    func getPackage(_ handle: IPCHandle) throws -> IPCBridgeReviewPackageResult
    func renderState(_ handle: IPCHandle) async throws -> IPCBridgeRenderStateResult
    func selectFile(_ params: IPCBridgeReviewSelectFileParams) async throws -> IPCBridgeReviewSelectFileResult
    func scrollToFile(_ params: IPCBridgeDiffScrollToFileParams) async throws -> IPCBridgePageControlResult
    func expandFile(_ params: IPCBridgeDiffExpandFileParams) async throws -> IPCBridgePageControlResult
    func collapseFile(_ params: IPCBridgeDiffCollapseFileParams) async throws -> IPCBridgePageControlResult
    func searchFileTree(_ params: IPCBridgeFileTreeSearchParams) async throws -> IPCBridgePageControlResult
    func setFileTreeFilter(_ params: IPCBridgeFileTreeSetFilterParams) async throws -> IPCBridgePageControlResult
    func revealFileTreePath(_ params: IPCBridgeFileTreeRevealPathParams) async throws -> IPCBridgePageControlResult
    func showMarkdownPreview(
        _ params: IPCBridgeFileViewShowMarkdownPreviewParams
    ) async throws -> IPCBridgePageControlResult
    func getContent(_ params: IPCBridgeContentGetParams) async throws -> IPCBridgeContentGetResult
    func telemetrySnapshot(_ handle: IPCHandle) async throws -> IPCBridgeTelemetrySnapshotResult
    func flushTelemetry(_ handle: IPCHandle) async throws -> IPCBridgeTelemetryFlushResult
}

package struct AppIPCPreparedCommand: Sendable {
    package let request: IPCCommandExecutionRequest
    package let canonicalHandle: IPCHandle?
    package let target: IPCTargetScope
    package let requiredScopes: [IPCPermissionScope]

    package init(
        request: IPCCommandExecutionRequest, canonicalHandle: IPCHandle?, target: IPCTargetScope,
        requiredScopes: [IPCPermissionScope]
    ) {
        self.request = request
        self.canonicalHandle = canonicalHandle
        self.target = target
        self.requiredScopes = requiredScopes
    }
}

@MainActor
package protocol AppIPCCommandPort: Sendable {
    func listCommands() throws -> IPCCommandCatalogResult
    func prepareCommand(
        _ params: IPCCommandExecutionRequest, principal: IPCPrincipal, tools: AppIPCTargetResolutionTools
    ) async throws -> AppIPCPreparedCommand
    func executeCommand(_ params: IPCCommandExecutionRequest) async throws -> IPCCommandExecutionResult
}

public protocol AppIPCPermissionApprovalPort: Sendable {
    func decision(for record: PermissionRecord, requester: IPCPrincipal) -> ApprovalPolicyDecision
}

public struct AppIPCUIPresentationError: Error, Equatable, Sendable {
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
public protocol AppIPCUIPresentationPort: Sendable {
    func openCommandBar(_ params: IPCCommandBarOpenParams) throws -> IPCCommandBarOpenResult
    func openArrangements(_ params: IPCArrangementsOpenParams) throws -> IPCArrangementsOpenResult
}

@MainActor
public protocol AppIPCSidebarPort: Sendable {
    func getGrouping(_ params: IPCSidebarGroupingGetParams) throws -> IPCSidebarGroupingResult
    func getSurface(_ params: IPCSidebarSurfaceGetParams) throws -> IPCSidebarSurfaceResult
}

package struct AgentStudioAppIPCPorts: Sendable {
    package let queryPort: any AppIPCQueryPort
    package let layoutPort: any AppIPCLayoutPort
    package let runtimePort: any AppIPCRuntimePort
    package let bridgePort: any AppIPCBridgePort
    package let commandPort: any AppIPCCommandPort
    package let uiPresentationPort: any AppIPCUIPresentationPort
    package let sidebarPort: any AppIPCSidebarPort
    package let permissionApprovalPort: any AppIPCPermissionApprovalPort

    package init(
        queryPort: any AppIPCQueryPort,
        layoutPort: any AppIPCLayoutPort,
        runtimePort: any AppIPCRuntimePort,
        bridgePort: any AppIPCBridgePort,
        commandPort: any AppIPCCommandPort,
        uiPresentationPort: any AppIPCUIPresentationPort,
        sidebarPort: any AppIPCSidebarPort,
        permissionApprovalPort: any AppIPCPermissionApprovalPort
    ) {
        self.queryPort = queryPort
        self.layoutPort = layoutPort
        self.runtimePort = runtimePort
        self.bridgePort = bridgePort
        self.commandPort = commandPort
        self.uiPresentationPort = uiPresentationPort
        self.sidebarPort = sidebarPort
        self.permissionApprovalPort = permissionApprovalPort
    }
}

public struct AgentStudioAppIPCConfiguration: Equatable, Sendable {
    public let runtimeId: UUID
    public let accessMode: IPCAccessMode
    public let debugTokenEscrowEnabled: Bool
    public let debugTokenEscrowPermissionScopes: [IPCPermissionScope]

    public init(
        runtimeId: UUID,
        accessMode: IPCAccessMode,
        debugTokenEscrowEnabled: Bool = false,
        debugTokenEscrowPermissionScopes: [IPCPermissionScope] = []
    ) {
        self.runtimeId = runtimeId
        self.accessMode = accessMode
        self.debugTokenEscrowEnabled = debugTokenEscrowEnabled
        self.debugTokenEscrowPermissionScopes = debugTokenEscrowPermissionScopes
    }
}

public struct AgentStudioAppIPCService: Sendable {
    public let configuration: AgentStudioAppIPCConfiguration
    package let ports: AgentStudioAppIPCPorts
    public let eventBroker: IPCEventBroker
    package let methodRegistry: AppIPCMethodRegistry

    package init(
        configuration: AgentStudioAppIPCConfiguration,
        ports: AgentStudioAppIPCPorts,
        methodRegistry: AppIPCMethodRegistry,
        eventBroker: IPCEventBroker = IPCEventBroker()
    ) {
        self.configuration = configuration
        self.ports = ports
        self.eventBroker = eventBroker
        self.methodRegistry = methodRegistry
    }
}
