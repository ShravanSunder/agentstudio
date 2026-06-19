import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation

@MainActor
protocol AgentStudioIPCBridgeActionExecuting: AnyObject {
    func openBridgeReview(worktreeId: UUID?) -> Pane?
}

extension WorkspaceActionExecutor: AgentStudioIPCBridgeActionExecuting {}

@MainActor
struct AgentStudioIPCBridgeAdapter: AppIPCBridgePort, @unchecked Sendable {
    private let workspaceStore: WorkspaceStore
    private let viewRegistry: ViewRegistry
    private let actionExecutor: any AgentStudioIPCBridgeActionExecuting

    init(
        workspaceStore: WorkspaceStore,
        viewRegistry: ViewRegistry,
        actionExecutor: any AgentStudioIPCBridgeActionExecuting
    ) {
        self.workspaceStore = workspaceStore
        self.viewRegistry = viewRegistry
        self.actionExecutor = actionExecutor
    }

    func openReview(_ params: IPCBridgeReviewOpenParams) throws -> IPCBridgeReviewOpenResult {
        guard let pane = actionExecutor.openBridgeReview(worktreeId: params.worktreeId) else {
            throw AppIPCBridgeError(reason: .targetNotFound)
        }
        return IPCBridgeReviewOpenResult(
            paneId: pane.id,
            handle: "pane:\(pane.id.uuidString)",
            correlationId: params.correlationId
        )
    }

    func refreshReview(_ params: IPCBridgeReviewRefreshParams) async throws -> IPCBridgeReviewRefreshResult {
        let controller = try bridgeController(for: try IPCHandle.parse(params.handle))
        return try await controller.refreshReviewForIPC(correlationId: params.correlationId)
    }

    func getPackage(_ handle: IPCHandle) throws -> IPCBridgeReviewPackageResult {
        try bridgeController(for: handle).ipcReviewPackageSnapshot()
    }

    func renderState(_ handle: IPCHandle) async throws -> IPCBridgeRenderStateResult {
        try await bridgeController(for: handle).renderStateForIPC()
    }

    func selectFile(_ params: IPCBridgeReviewSelectFileParams) async throws -> IPCBridgeReviewSelectFileResult {
        let controller = try bridgeController(for: try IPCHandle.parse(params.handle))
        return try await controller.selectReviewItemForIPC(
            itemId: params.itemId,
            correlationId: params.correlationId
        )
    }

    func getContent(_ params: IPCBridgeContentGetParams) async throws -> IPCBridgeContentGetResult {
        let controller = try bridgeController(for: try IPCHandle.parse(params.handle))
        return try await controller.loadContentForIPC(
            contentHandleId: params.contentHandleId,
            reviewGeneration: params.reviewGeneration
        )
    }

    func telemetrySnapshot(_ handle: IPCHandle) throws -> IPCBridgeTelemetrySnapshotResult {
        try bridgeController(for: handle).telemetrySnapshotForIPC()
    }

    func flushTelemetry(_ handle: IPCHandle) async throws -> IPCBridgeTelemetryFlushResult {
        try await bridgeController(for: handle).flushTelemetryForIPC()
    }

    private func bridgeController(for handle: IPCHandle) throws -> BridgePaneController {
        let paneId = try resolvePaneId(handle)
        guard
            let pane = workspaceStore.programmaticControlSnapshot().panes.first(where: { $0.id == paneId })
        else {
            throw AppIPCBridgeError(reason: .targetNotFound)
        }
        guard pane.contentKind == .bridgePanel else {
            throw AppIPCBridgeError(reason: .unsupportedTarget)
        }
        guard
            let bridgeView = viewRegistry.view(for: paneId)?
                .mountedContent(as: BridgePaneMountView.self)
        else {
            throw AppIPCBridgeError(reason: .targetNotFound)
        }
        return bridgeView.controller
    }

    private func resolvePaneId(_ handle: IPCHandle) throws -> UUID {
        guard handle.kind == .pane else {
            throw AppIPCBridgeError(reason: .validationRejected)
        }
        let snapshot = workspaceStore.programmaticControlSnapshot()
        switch handle.reference {
        case .canonicalUUID(let paneId):
            guard snapshot.panes.contains(where: { $0.id == paneId }) else {
                throw AppIPCBridgeError(reason: .targetNotFound)
            }
            return paneId

        case .friendlyOrdinal(let ordinal):
            guard let pane = snapshot.panes[safe: ordinal - 1] else {
                throw AppIPCBridgeError(reason: .targetNotFound)
            }
            return pane.id
        }
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }
        return self[index]
    }
}
