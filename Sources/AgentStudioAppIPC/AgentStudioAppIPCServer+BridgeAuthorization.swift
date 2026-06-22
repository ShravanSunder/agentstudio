import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation

extension AgentStudioAppIPCServer {
    func bridgeAuthorizationContext(for request: JSONRPCRequest) async throws -> AuthorizedRequestContext {
        switch request.method {
        case "bridge.diff.getPackage", "bridge.diff.renderState", "bridge.telemetry.snapshot",
            "bridge.telemetry.flush":
            let params = try decodeParams(IPCBridgePaneParams.self, from: request.params)
            return try await authorizedBridgeContext(for: request, rawHandle: params.handle) {
                IPCBridgePaneParams(handle: $0)
            }
        case "bridge.diff.refresh":
            let params = try decodeParams(IPCBridgeReviewRefreshParams.self, from: request.params)
            return try await authorizedBridgeContext(for: request, rawHandle: params.handle) {
                IPCBridgeReviewRefreshParams(handle: $0, correlationId: params.correlationId)
            }
        case "bridge.diff.selectFile":
            let params = try decodeParams(IPCBridgeReviewSelectFileParams.self, from: request.params)
            return try await authorizedBridgeContext(for: request, rawHandle: params.handle) {
                IPCBridgeReviewSelectFileParams(handle: $0, itemId: params.itemId, correlationId: params.correlationId)
            }
        case "bridge.diff.scrollToFile":
            let params = try decodeParams(IPCBridgeDiffScrollToFileParams.self, from: request.params)
            return try await authorizedBridgeContext(for: request, rawHandle: params.handle) {
                IPCBridgeDiffScrollToFileParams(handle: $0, itemId: params.itemId, correlationId: params.correlationId)
            }
        case "bridge.diff.expandFile":
            let params = try decodeParams(IPCBridgeDiffExpandFileParams.self, from: request.params)
            return try await authorizedBridgeContext(for: request, rawHandle: params.handle) {
                IPCBridgeDiffExpandFileParams(handle: $0, itemId: params.itemId, correlationId: params.correlationId)
            }
        case "bridge.diff.collapseFile":
            let params = try decodeParams(IPCBridgeDiffCollapseFileParams.self, from: request.params)
            return try await authorizedBridgeContext(for: request, rawHandle: params.handle) {
                IPCBridgeDiffCollapseFileParams(handle: $0, itemId: params.itemId, correlationId: params.correlationId)
            }
        case "bridge.fileTree.search":
            let params = try decodeParams(IPCBridgeFileTreeSearchParams.self, from: request.params)
            return try await authorizedBridgeContext(for: request, rawHandle: params.handle) {
                IPCBridgeFileTreeSearchParams(
                    handle: $0,
                    searchText: params.searchText,
                    correlationId: params.correlationId
                )
            }
        case "bridge.fileTree.setFilter":
            let params = try decodeParams(IPCBridgeFileTreeSetFilterParams.self, from: request.params)
            return try await authorizedBridgeContext(for: request, rawHandle: params.handle) {
                IPCBridgeFileTreeSetFilterParams(
                    handle: $0,
                    gitStatusFilter: params.gitStatusFilter,
                    fileClassFilter: params.fileClassFilter,
                    correlationId: params.correlationId
                )
            }
        case "bridge.fileTree.revealPath":
            let params = try decodeParams(IPCBridgeFileTreeRevealPathParams.self, from: request.params)
            return try await authorizedBridgeContext(for: request, rawHandle: params.handle) {
                IPCBridgeFileTreeRevealPathParams(handle: $0, path: params.path, correlationId: params.correlationId)
            }
        case "bridge.fileView.showMarkdownPreview":
            let params = try decodeParams(IPCBridgeFileViewShowMarkdownPreviewParams.self, from: request.params)
            return try await authorizedBridgeContext(for: request, rawHandle: params.handle) {
                IPCBridgeFileViewShowMarkdownPreviewParams(
                    handle: $0,
                    itemId: params.itemId,
                    correlationId: params.correlationId
                )
            }
        case "bridge.fileView.getContent":
            let params = try decodeParams(IPCBridgeContentGetParams.self, from: request.params)
            return try await authorizedBridgeContext(for: request, rawHandle: params.handle) {
                IPCBridgeContentGetParams(
                    handle: $0,
                    contentHandleId: params.contentHandleId,
                    reviewGeneration: params.reviewGeneration
                )
            }
        default:
            throw AgentStudioAppIPCRequestError.methodNotFound
        }
    }

    private func authorizedBridgeContext<TParams: Encodable>(
        for request: JSONRPCRequest,
        rawHandle: String,
        makeCanonicalParams: (String) -> TParams
    ) async throws -> AuthorizedRequestContext {
        let canonicalHandle = try await canonicalPaneHandle(fromRawHandle: rawHandle)
        return try AuthorizedRequestContext(
            request: JSONRPCRequest(
                id: request.id,
                method: request.method,
                params: JSONRPCCodec.encodeJSONValue(makeCanonicalParams(rawIPCHandleString(canonicalHandle)))
            ),
            target: bridgePaneTargetScope(fromCanonicalHandle: canonicalHandle)
        )
    }

    func requireAuthorizedBridgePaneTarget(for request: JSONRPCRequest) async throws {
        guard request.method != "bridge.diff.load" else {
            return
        }

        let params = try decodeParams(IPCBridgePaneParams.self, from: request.params)
        let handle = try IPCHandle.parse(params.handle)
        guard case (.pane, .canonicalUUID(let paneId)) = (handle.kind, handle.reference) else {
            throw AgentStudioAppIPCRequestError.invalidParams
        }

        let panes = try await service.ports.queryPort.listPanes().panes
        guard let pane = panes.first(where: { $0.id == paneId }) else {
            throw AppIPCBridgeError(reason: .targetNotFound)
        }
        guard pane.contentKind == .bridgePanel else {
            throw AppIPCBridgeError(reason: .unsupportedTarget)
        }
    }

    private func canonicalPaneHandle(fromRawHandle rawHandle: String) async throws -> IPCHandle {
        let handle = try IPCHandle.parse(rawHandle)
        guard handle.kind == .pane else {
            throw AppIPCBridgeError(reason: .unsupportedTarget)
        }

        let panes = try await service.ports.queryPort.listPanes().panes
        let pane: IPCPaneSummary?
        switch handle.reference {
        case .canonicalUUID(let paneId):
            pane = panes.first { $0.id == paneId }
        case .friendlyOrdinal(let ordinal):
            let paneIndex = ordinal - 1
            pane = panes.indices.contains(paneIndex) ? panes[paneIndex] : nil
        }

        guard let pane else {
            throw AppIPCBridgeError(reason: .targetNotFound)
        }
        return IPCHandle(kind: .pane, reference: .canonicalUUID(pane.id))
    }

    private func bridgePaneTargetScope(fromCanonicalHandle handle: IPCHandle) throws -> IPCTargetScope {
        guard case (.pane, .canonicalUUID(let paneId)) = (handle.kind, handle.reference) else {
            throw AgentStudioAppIPCRequestError.invalidParams
        }
        return .pane(paneId.uuidString)
    }

    private func rawIPCHandleString(_ handle: IPCHandle) -> String {
        switch handle.reference {
        case .friendlyOrdinal(let ordinal):
            "\(handle.kind.rawValue):\(ordinal)"
        case .canonicalUUID(let uuid):
            "\(handle.kind.rawValue):\(uuid.uuidString)"
        }
    }
}
