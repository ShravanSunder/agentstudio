import AgentStudioAppIPC
import AgentStudioBridge
import AgentStudioCore
import AgentStudioProgrammaticControl
import Foundation

@MainActor
protocol AgentStudioIPCBridgeActionExecuting: AnyObject {
    func openBridgeReviewInNewTab(worktreeId: UUID?) -> Pane?
    func openBridgeFilesInNewTab(worktreeId: UUID?) -> Pane?
    func searchBridgeFiles(
        _ criteria: BridgeFilesSearchCriteria,
        forPaneId paneId: UUID
    ) async -> BridgeFilesSearchRequestOutcome
    /// The mounted controller of the receiver `paneId` addresses, or nil when
    /// that receiver has none.
    func mountedBridgeController(forCommandPaneId paneId: UUID) -> BridgePaneController?
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
        guard let pane = actionExecutor.openBridgeReviewInNewTab(worktreeId: params.worktreeId) else {
            throw AppIPCBridgeError(reason: .targetNotFound)
        }
        return IPCBridgeReviewOpenResult(
            paneId: pane.id,
            handle: "pane:\(pane.id.uuidString)",
            correlationId: params.correlationId
        )
    }

    func openFileView(_ params: IPCBridgeFileViewOpenParams) throws -> IPCBridgeFileViewOpenResult {
        guard let pane = actionExecutor.openBridgeFilesInNewTab(worktreeId: params.worktreeId) else {
            throw AppIPCBridgeError(reason: .targetNotFound)
        }
        return IPCBridgeFileViewOpenResult(
            paneId: pane.id,
            handle: "pane:\(pane.id.uuidString)",
            correlationId: params.correlationId
        )
    }

    func refreshReview(
        _ params: IPCBridgeReviewRefreshParams, ownPaneAssertion: AppIPCOwnPaneAssertion?
    ) async throws -> IPCBridgeReviewRefreshResult {
        let controller = try bridgeController(
            for: try IPCHandle.parse(params.handle), ownPaneAssertion: ownPaneAssertion, method: "bridge.diff.refresh")
        return try await translateAsyncBridgeProjectionError {
            try await controller.refreshReviewForIPC(correlationId: params.correlationId)
        }
    }

    func getPackage(
        _ handle: IPCHandle, ownPaneAssertion: AppIPCOwnPaneAssertion?
    ) throws -> IPCBridgeReviewPackageResult {
        try translateBridgeProjectionError {
            try bridgeController(for: handle, ownPaneAssertion: ownPaneAssertion, method: "bridge.diff.getPackage")
                .ipcReviewPackageSnapshot()
        }
    }

    func renderState(
        _ handle: IPCHandle, ownPaneAssertion: AppIPCOwnPaneAssertion?
    ) async throws -> IPCBridgeRenderStateResult {
        try await bridgeController(for: handle, ownPaneAssertion: ownPaneAssertion, method: "bridge.diff.renderState")
            .renderStateForIPC()
    }

    func selectFile(
        _ params: IPCBridgeReviewSelectFileParams, ownPaneAssertion: AppIPCOwnPaneAssertion?
    ) async throws -> IPCBridgeReviewSelectFileResult {
        let controller = try bridgeController(
            for: try IPCHandle.parse(params.handle), ownPaneAssertion: ownPaneAssertion,
            method: "bridge.diff.selectFile")
        return try await translateAsyncBridgeProjectionError {
            try await controller.selectReviewItemForIPC(
                itemId: params.itemId,
                correlationId: params.correlationId
            )
        }
    }

    func scrollToFile(
        _ params: IPCBridgeDiffScrollToFileParams, ownPaneAssertion: AppIPCOwnPaneAssertion?
    ) async throws -> IPCBridgePageControlResult {
        let controller = try bridgeController(
            for: try IPCHandle.parse(params.handle), ownPaneAssertion: ownPaneAssertion,
            method: "bridge.diff.scrollToFile")
        return try await translateAsyncBridgeProjectionError {
            try await controller.applyPageControlForIPC(
                .scrollToFile(itemId: params.itemId),
                correlationId: params.correlationId
            )
        }
    }

    func expandFile(
        _ params: IPCBridgeDiffExpandFileParams, ownPaneAssertion: AppIPCOwnPaneAssertion?
    ) async throws -> IPCBridgePageControlResult {
        let controller = try bridgeController(
            for: try IPCHandle.parse(params.handle), ownPaneAssertion: ownPaneAssertion,
            method: "bridge.diff.expandFile")
        return try await translateAsyncBridgeProjectionError {
            try await controller.applyPageControlForIPC(
                .expandFile(itemId: params.itemId),
                correlationId: params.correlationId
            )
        }
    }

    func collapseFile(
        _ params: IPCBridgeDiffCollapseFileParams, ownPaneAssertion: AppIPCOwnPaneAssertion?
    ) async throws -> IPCBridgePageControlResult {
        let controller = try bridgeController(
            for: try IPCHandle.parse(params.handle), ownPaneAssertion: ownPaneAssertion,
            method: "bridge.diff.collapseFile")
        return try await translateAsyncBridgeProjectionError {
            try await controller.applyPageControlForIPC(
                .collapseFile(itemId: params.itemId),
                correlationId: params.correlationId
            )
        }
    }

    func searchFileTree(
        _ params: IPCBridgeFileTreeSearchParams, ownPaneAssertion: AppIPCOwnPaneAssertion?
    ) async throws -> IPCBridgePageControlResult {
        let controller = try bridgeController(
            for: try IPCHandle.parse(params.handle), ownPaneAssertion: ownPaneAssertion,
            method: "bridge.fileTree.search")
        return try await translateAsyncBridgeProjectionError {
            try await controller.applyPageControlForIPC(
                .fileTreeSearch(searchText: params.searchText, searchMode: params.searchMode),
                correlationId: params.correlationId
            )
        }
    }

    func setFileTreeFilter(
        _ params: IPCBridgeFileTreeSetFilterParams, ownPaneAssertion: AppIPCOwnPaneAssertion?
    ) async throws -> IPCBridgePageControlResult {
        let controller = try bridgeController(
            for: try IPCHandle.parse(params.handle), ownPaneAssertion: ownPaneAssertion,
            method: "bridge.fileTree.setFilter")
        return try await translateAsyncBridgeProjectionError {
            try await controller.applyPageControlForIPC(
                .fileTreeSetFilter(candidate: params.candidate),
                correlationId: params.correlationId
            )
        }
    }

    func revealFileTreePath(
        _ params: IPCBridgeFileTreeRevealPathParams, ownPaneAssertion: AppIPCOwnPaneAssertion?
    ) async throws -> IPCBridgePageControlResult {
        let controller = try bridgeController(
            for: try IPCHandle.parse(params.handle), ownPaneAssertion: ownPaneAssertion,
            method: "bridge.fileTree.revealPath")
        return try await translateAsyncBridgeProjectionError {
            try await controller.applyPageControlForIPC(
                .fileTreeRevealPath(path: params.path),
                correlationId: params.correlationId
            )
        }
    }

    func showMarkdownPreview(
        _ params: IPCBridgeFileViewShowMarkdownPreviewParams, ownPaneAssertion: AppIPCOwnPaneAssertion?
    ) async throws -> IPCBridgePageControlResult {
        let controller = try bridgeController(
            for: try IPCHandle.parse(params.handle), ownPaneAssertion: ownPaneAssertion,
            method: "bridge.fileView.showMarkdownPreview")
        return try await translateAsyncBridgeProjectionError {
            try await controller.applyPageControlForIPC(
                .fileViewShowMarkdownPreview(itemId: params.itemId),
                correlationId: params.correlationId
            )
        }
    }

    func getContent(
        _ params: IPCBridgeContentGetParams, ownPaneAssertion: AppIPCOwnPaneAssertion?
    ) async throws -> IPCBridgeContentGetResult {
        let controller = try bridgeController(
            for: try IPCHandle.parse(params.handle), ownPaneAssertion: ownPaneAssertion,
            method: "bridge.fileView.getContent")
        return try await translateAsyncBridgeProjectionError {
            try await controller.loadContentForIPC(
                contentHandleId: params.contentHandleId,
                reviewGeneration: params.reviewGeneration
            )
        }
    }

    /// Search the addressed Bridge's Files collection through its receiver.
    /// Search-level outcomes are typed results; only an unknown or non-Bridge
    /// target is an error.
    func searchFiles(
        _ params: IPCBridgeFilesSearchParams, ownPaneAssertion: AppIPCOwnPaneAssertion?
    ) async throws -> IPCBridgeFilesSearchResult {
        let paneId = try bridgePaneId(for: try IPCHandle.parse(params.handle))
        try requireOwnPane(ownPaneAssertion, paneId: paneId, method: "bridge.files.search")
        let outcome = await actionExecutor.searchBridgeFiles(
            BridgeFilesSearchIPCProjection.criteria(params),
            forPaneId: paneId
        )
        return BridgeFilesSearchIPCProjection.result(outcome, paneId: paneId)
    }

    func telemetrySnapshot(_ handle: IPCHandle) async throws -> IPCBridgeTelemetrySnapshotResult {
        try await standaloneBridgeController(for: handle).telemetrySnapshotForIPC()
    }

    func flushTelemetry(_ handle: IPCHandle) async throws -> IPCBridgeTelemetryFlushResult {
        try await standaloneBridgeController(for: handle).flushTelemetryForIPC()
    }

    /// The controller a Bridge method acts on. A standalone Bridge pane is its
    /// own receiver; a terminal pane (or its drawer child) addresses its
    /// receiving Bridge's current companion, which may not be mounted.
    private func bridgeController(
        for handle: IPCHandle,
        ownPaneAssertion: AppIPCOwnPaneAssertion?,
        method: String
    ) throws -> BridgePaneController {
        let target = try bridgeTarget(for: handle)
        try requireOwnPane(ownPaneAssertion, paneId: target.paneId, method: method)
        switch target.kind {
        case .standaloneBridge:
            return try standaloneBridgeController(paneId: target.paneId)
        case .terminal:
            guard let controller = actionExecutor.mountedBridgeController(forCommandPaneId: target.paneId) else {
                throw AppIPCBridgeError(reason: .notMounted)
            }
            return controller
        }
    }

    /// Telemetry stays addressed to a standalone Bridge pane only.
    private func standaloneBridgeController(for handle: IPCHandle) throws -> BridgePaneController {
        let target = try bridgeTarget(for: handle)
        guard target.kind == .standaloneBridge else {
            throw AppIPCBridgeError(reason: .unsupportedTarget)
        }
        return try standaloneBridgeController(paneId: target.paneId)
    }

    private func standaloneBridgeController(paneId: UUID) throws -> BridgePaneController {
        guard
            let bridgeView = viewRegistry.view(for: paneId)?
                .mountedContent(as: BridgePaneMountView.self)
        else {
            throw AppIPCBridgeError(reason: .targetNotFound)
        }
        return bridgeView.controller
    }

    private enum BridgeTargetKind {
        case standaloneBridge
        case terminal
    }

    /// The pane a Bridge method names: a Bridge pane or a terminal whose
    /// receiver it reaches. Any other pane kind is unsupported.
    private func bridgeTarget(for handle: IPCHandle) throws -> (paneId: UUID, kind: BridgeTargetKind) {
        let paneId = try resolvePaneId(handle)
        guard
            let pane = workspaceStore.programmaticControlSnapshot().panes.first(where: { $0.id == paneId })
        else {
            throw AppIPCBridgeError(reason: .targetNotFound)
        }
        switch pane.contentKind {
        case .bridgePanel:
            return (paneId, .standaloneBridge)
        case .terminal:
            return (paneId, .terminal)
        default:
            throw AppIPCBridgeError(reason: .unsupportedTarget)
        }
    }

    private func bridgePaneId(for handle: IPCHandle) throws -> UUID {
        try bridgeTarget(for: handle).paneId
    }

    /// Re-checks a pane agent's own pane in the same main-actor step that
    /// hands the request to the Bridge.
    private func requireOwnPane(_ assertion: AppIPCOwnPaneAssertion?, paneId: UUID, method: String) throws {
        guard let assertion else { return }
        guard
            workspaceStore.ownPaneAssertionHolds(
                WorkspaceOwnPaneAssertion(boundPaneId: assertion.boundPaneId), for: paneId)
        else {
            throw AuthorizationError.notYetAllowed(method)
        }
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

    private func translateBridgeProjectionError<T>(
        _ operation: () throws -> T
    ) throws -> T {
        do {
            return try operation()
        } catch let error as BridgeIPCProjectionError {
            throw AppIPCBridgeError(error)
        }
    }

    private func translateAsyncBridgeProjectionError<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch let error as BridgeIPCProjectionError {
            throw AppIPCBridgeError(error)
        }
    }
}

extension AppIPCBridgeError {
    fileprivate init(_ error: BridgeIPCProjectionError) {
        switch error.reason {
        case .packageUnavailable:
            self.init(reason: .packageUnavailable)
        case .itemNotFound:
            self.init(reason: .itemNotFound)
        case .contentUnavailable:
            self.init(reason: .contentUnavailable)
        case .payloadTooLarge:
            self.init(reason: .payloadTooLarge)
        case .validationRejected:
            self.init(reason: .validationRejected)
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
