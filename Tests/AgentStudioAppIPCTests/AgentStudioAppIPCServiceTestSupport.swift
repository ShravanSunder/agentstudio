import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation
import Testing

#if canImport(Darwin)
    import Darwin
#endif

struct FakeLayoutPort: AppIPCLayoutPort {
    func focusPane(_: IPCHandle) throws -> IPCPaneFocusResult {
        throw AppIPCLayoutError(reason: .targetNotFound)
    }

    func splitPane(_ params: IPCPaneSplitParams) throws -> IPCPaneSplitResult {
        let handle = try IPCHandle.parse(params.handle)
        guard case .canonicalUUID(let paneId) = handle.reference else {
            throw AppIPCLayoutError(reason: .targetNotFound)
        }
        return IPCPaneSplitResult(
            targetPaneId: paneId, direction: params.direction, correlationId: params.correlationId)
    }

    func closePane(_ params: IPCPaneCloseParams) throws -> IPCPaneCloseResult {
        let handle = try IPCHandle.parse(params.handle)
        guard case .canonicalUUID(let paneId) = handle.reference else {
            throw AppIPCLayoutError(reason: .targetNotFound)
        }
        return IPCPaneCloseResult(paneId: paneId, correlationId: params.correlationId)
    }

    func addDrawerPane(_ params: IPCDrawerAddPaneParams) throws -> IPCDrawerAddPaneResult {
        let handle = try IPCHandle.parse(params.parentPaneHandle)
        guard case .canonicalUUID(let paneId) = handle.reference else {
            throw AppIPCLayoutError(reason: .targetNotFound)
        }
        return IPCDrawerAddPaneResult(parentPaneId: paneId, correlationId: params.correlationId)
    }

    func toggleDrawer(_ params: IPCDrawerToggleParams) throws -> IPCDrawerToggleResult {
        let handle = try IPCHandle.parse(params.parentPaneHandle)
        guard case .canonicalUUID(let paneId) = handle.reference else {
            throw AppIPCLayoutError(reason: .targetNotFound)
        }
        return IPCDrawerToggleResult(parentPaneId: paneId, correlationId: params.correlationId)
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
        timeout _: Duration,
        afterSequence _: UInt64?
    ) async throws -> IPCTerminalWaitResult {
        throw AppIPCRuntimeError(reason: .timeout)
    }
}

struct FakeBridgePort: AppIPCBridgePort {
    let paneId: UUID
    let itemId: String
    let contentHandleId: String
    let pageControlStatus: String
    let pageControlReason: String?

    nonisolated init(
        paneId: UUID = UUID(),
        itemId: String = "item-source",
        contentHandleId: String = "handle-head",
        pageControlStatus: String = "accepted",
        pageControlReason: String? = nil
    ) {
        self.paneId = paneId
        self.itemId = itemId
        self.contentHandleId = contentHandleId
        self.pageControlStatus = pageControlStatus
        self.pageControlReason = pageControlReason
    }

    func openReview(_ params: IPCBridgeReviewOpenParams) throws -> IPCBridgeReviewOpenResult {
        IPCBridgeReviewOpenResult(
            paneId: paneId,
            handle: "pane:\(paneId.uuidString)",
            correlationId: params.correlationId
        )
    }

    func openFileView(_ params: IPCBridgeFileViewOpenParams) throws -> IPCBridgeFileViewOpenResult {
        IPCBridgeFileViewOpenResult(
            paneId: paneId,
            handle: "pane:\(paneId.uuidString)",
            correlationId: params.correlationId
        )
    }

    func refreshReview(_ params: IPCBridgeReviewRefreshParams) async throws -> IPCBridgeReviewRefreshResult {
        IPCBridgeReviewRefreshResult(
            paneId: paneId,
            refreshed: true,
            status: "ready",
            packageId: "package-test",
            reviewGeneration: 1,
            correlationId: params.correlationId
        )
    }

    func getPackage(_: IPCHandle) throws -> IPCBridgeReviewPackageResult {
        IPCBridgeReviewPackageResult(
            paneId: paneId,
            status: "ready",
            selectedItemId: nil,
            packageId: "package-test",
            reviewGeneration: 1,
            revision: 1,
            summary: IPCBridgeReviewPackageSummary(
                filesChanged: 1,
                additions: 2,
                deletions: 1,
                visibleFileCount: 1,
                hiddenFileCount: 0
            )
        )
    }

    func renderState(_: IPCHandle) async throws -> IPCBridgeRenderStateResult {
        IPCBridgeRenderStateResult(
            paneId: paneId,
            summary: IPCBridgeRenderSummary(
                pageTitle: "AgentStudio Bridge",
                hasAppRoot: true,
                hasEmptyShell: false,
                hasReviewShell: true,
                sidebarPosition: "right"
            ),
            diagnostics: IPCBridgeRenderDiagnostics(
                evaluateSucceeded: true,
                pageErrorCount: 0,
                pageErrorKinds: [],
                pageErrorMessages: []
            )
        )
    }

    func selectFile(_ params: IPCBridgeReviewSelectFileParams) async throws -> IPCBridgeReviewSelectFileResult {
        IPCBridgeReviewSelectFileResult(
            paneId: paneId,
            itemId: params.itemId,
            selected: true,
            correlationId: params.correlationId
        )
    }

    func scrollToFile(_ params: IPCBridgeDiffScrollToFileParams) async throws -> IPCBridgePageControlResult {
        bridgePageControlResult(
            method: "bridge.diff.scrollToFile",
            itemId: params.itemId,
            path: nil,
            correlationId: params.correlationId
        )
    }

    func expandFile(_ params: IPCBridgeDiffExpandFileParams) async throws -> IPCBridgePageControlResult {
        bridgePageControlResult(
            method: "bridge.diff.expandFile",
            itemId: params.itemId,
            path: nil,
            correlationId: params.correlationId
        )
    }

    func collapseFile(_ params: IPCBridgeDiffCollapseFileParams) async throws -> IPCBridgePageControlResult {
        bridgePageControlResult(
            method: "bridge.diff.collapseFile",
            itemId: params.itemId,
            path: nil,
            correlationId: params.correlationId
        )
    }

    func searchFileTree(_ params: IPCBridgeFileTreeSearchParams) async throws -> IPCBridgePageControlResult {
        bridgePageControlResult(
            method: "bridge.fileTree.search",
            itemId: nil,
            path: nil,
            treeSearchText: params.searchText,
            correlationId: params.correlationId
        )
    }

    func setFileTreeFilter(_ params: IPCBridgeFileTreeSetFilterParams) async throws -> IPCBridgePageControlResult {
        bridgePageControlResult(
            method: "bridge.fileTree.setFilter",
            itemId: nil,
            path: nil,
            gitStatusFilter: params.gitStatusFilter,
            fileClassFilter: params.fileClassFilter,
            correlationId: params.correlationId
        )
    }

    func revealFileTreePath(_ params: IPCBridgeFileTreeRevealPathParams) async throws -> IPCBridgePageControlResult {
        bridgePageControlResult(
            method: "bridge.fileTree.revealPath",
            itemId: itemId,
            path: params.path,
            correlationId: params.correlationId
        )
    }

    func showMarkdownPreview(
        _ params: IPCBridgeFileViewShowMarkdownPreviewParams
    ) async throws -> IPCBridgePageControlResult {
        bridgePageControlResult(
            method: "bridge.fileView.showMarkdownPreview",
            itemId: params.itemId ?? itemId,
            path: nil,
            renderMode: "markdownPreview",
            correlationId: params.correlationId
        )
    }

    func getContent(_: IPCBridgeContentGetParams) async throws -> IPCBridgeContentGetResult {
        IPCBridgeContentGetResult(
            paneId: paneId,
            handle: bridgeContentHandleSummary,
            mimeType: "text/x-swift"
        )
    }

    func telemetrySnapshot(_: IPCHandle) throws -> IPCBridgeTelemetrySnapshotResult {
        IPCBridgeTelemetrySnapshotResult(
            paneId: paneId,
            recorderAttached: true,
            traceExportEnabled: true,
            status: "ready",
            packageId: "package-test",
            reviewGeneration: 1,
            selectedItemId: itemId
        )
    }

    func flushTelemetry(_: IPCHandle) async throws -> IPCBridgeTelemetryFlushResult {
        IPCBridgeTelemetryFlushResult(paneId: paneId, flushed: true)
    }

    private func bridgePageControlResult(
        method: String,
        itemId: String?,
        path: String?,
        treeSearchText: String = "",
        gitStatusFilter: String = "all",
        fileClassFilter: String = "all",
        renderMode: String = "codeView",
        correlationId: UUID?
    ) -> IPCBridgePageControlResult {
        IPCBridgePageControlResult(
            paneId: paneId,
            method: method,
            status: pageControlStatus,
            itemId: itemId,
            path: path,
            treeSearchText: treeSearchText,
            gitStatusFilter: gitStatusFilter,
            fileClassFilter: fileClassFilter,
            renderMode: renderMode,
            reason: pageControlReason,
            correlationId: correlationId
        )
    }

    private var bridgeContentHandleSummary: IPCBridgeContentHandleSummary {
        IPCBridgeContentHandleSummary(
            identity: IPCBridgeContentHandleIdentity(
                handleId: contentHandleId,
                itemId: itemId,
                role: "head",
                reviewGeneration: 1
            ),
            presentation: IPCBridgeContentHandlePresentation(
                resourceUrl: "agentstudio://resource/review/content/\(contentHandleId)?generation=1",
                mimeType: "text/x-swift",
                language: "swift"
            ),
            size: IPCBridgeContentHandleSize(sizeBytes: 14, isBinary: false)
        )
    }
}

struct FakeCommandPort: AppIPCCommandPort {
    let workspaceWindowId: UUID?
    let activeScope: IPCCommandBarScope?
    let supportedCommandIds: Set<IPCCommandIdentifier>

    nonisolated init(
        workspaceWindowId: UUID? = nil,
        activeScope: IPCCommandBarScope? = nil,
        supportedCommandIds: Set<IPCCommandIdentifier> = [IPCCommandIdentifier(rawValue: "showCommandBarCommands")]
    ) {
        self.workspaceWindowId = workspaceWindowId
        self.activeScope = activeScope
        self.supportedCommandIds = supportedCommandIds
    }

    func listCommands() throws -> IPCCommandListResult {
        IPCCommandListResult(commands: [])
    }

    func executeCommand(_ params: IPCCommandExecuteParams) throws -> IPCCommandExecuteResult {
        if params.targetHandle != nil {
            throw AppIPCCommandError(reason: .targetNotFound)
        }
        guard supportedCommandIds.contains(params.commandId) else {
            throw AppIPCCommandError(reason: .unsupportedCommand)
        }
        guard workspaceWindowId != nil, activeScope != nil else {
            throw AppIPCCommandError(reason: .noActiveWindow)
        }
        throw AppIPCCommandError(reason: .requiresPresentation)
    }
}

struct FakeUIPresentationPort: AppIPCUIPresentationPort {
    let workspaceWindowId: UUID?

    nonisolated init(workspaceWindowId: UUID? = UUID()) {
        self.workspaceWindowId = workspaceWindowId
    }

    func openCommandBar(_ params: IPCCommandBarOpenParams) throws -> IPCCommandBarOpenResult {
        guard let workspaceWindowId else {
            throw AppIPCUIPresentationError(reason: .noActiveWindow)
        }
        return IPCCommandBarOpenResult(
            workspaceWindowId: workspaceWindowId,
            scope: params.scope,
            correlationId: params.correlationId
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

struct LiveServerFixture {
    let runtimeId = UUID()
    let boundPaneId = UUID()
    let rootURL: URL
    let paths: AgentStudioIPCPaths
    let server: AgentStudioAppIPCServer

    init(
        accessMode: IPCAccessMode = .agentStudioOnly,
        channel: AgentStudioIPCChannel = .debug,
        panes: [IPCPaneSummary] = [],
        queryPort: (any AppIPCQueryPort)? = nil,
        runtimePort: any AppIPCRuntimePort = FakeRuntimePort(),
        bridgePort: (any AppIPCBridgePort)? = nil,
        commandPort: any AppIPCCommandPort = FakeCommandPort(),
        uiPresentationPort: any AppIPCUIPresentationPort = FakeUIPresentationPort(),
        debugTokenEscrowEnabled: Bool = false,
        methodContributions: [AppIPCMethodContribution] = []
    ) throws {
        rootURL = URL(
            fileURLWithPath: "/tmp/asipc-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        #if canImport(Darwin)
            _ = chmod(rootURL.path, 0o700)
        #endif
        paths = AgentStudioIPCPathResolver().paths(rootDirectory: rootURL)
        let methodRegistry = try AppIPCMethodRegistry.phaseOne()
        let mergedMethodRegistry = try AppIPCMethodRegistry(
            baseDefinitions: methodRegistry.definitions,
            contributions: methodContributions
        )
        let ports = AgentStudioAppIPCPorts(
            queryPort: queryPort.map {
                MethodCapabilitiesQueryPort(
                    base: $0,
                    methodDefinitions: mergedMethodRegistry.definitions
                )
            }
                ?? FakeQueryPort(
                    runtimeId: runtimeId,
                    panes: panes,
                    methodDefinitions: mergedMethodRegistry.definitions
                ),
            layoutPort: FakeLayoutPort(),
            runtimePort: runtimePort,
            bridgePort: bridgePort ?? FakeBridgePort(paneId: panes.first?.id ?? boundPaneId),
            commandPort: commandPort,
            uiPresentationPort: uiPresentationPort,
            permissionApprovalPort: FakePermissionApprovalPort()
        )
        let service = try AgentStudioAppIPCService(
            configuration: AgentStudioAppIPCConfiguration(
                runtimeId: runtimeId,
                accessMode: accessMode,
                methodDefinitions: methodRegistry.definitions,
                debugTokenEscrowEnabled: debugTokenEscrowEnabled
            ),
            ports: ports,
            methodContributions: methodContributions
        )
        server = AgentStudioAppIPCServer(service: service, paths: paths, channel: channel)
    }

    func cleanup() {
        server.stop()
        try? FileManager.default.removeItem(at: rootURL)
    }
}

func makePaneSummary(
    id: UUID,
    ordinal: Int,
    contentKind: IPCPaneContentKind = .terminal
) -> IPCPaneSummary {
    IPCPaneSummary(
        id: id,
        ordinal: ordinal,
        contentKind: contentKind,
        residency: .active,
        tabId: nil,
        repoId: nil,
        worktreeId: nil,
        isActive: false,
        isDrawerChild: false
    )
}

func makePaneSnapshotTestContribution() throws -> AppIPCMethodContribution {
    try AppIPCMethodContribution(
        definition: IPCMethodDefinition(
            name: "pane.snapshot",
            paramsSchema: IPCSchemaDescription(name: "pane.snapshot.params"),
            resultSchema: IPCSchemaDescription(name: "pane.snapshot.result"),
            privilegeClasses: [.paneContextRead],
            executionOwner: .queryReader,
            resultSemantics: .applied
        ),
        securityContract: AppIPCContributionSecurityContract(
            targetVocabulary: [.pane],
            dataScopes: [.paneContext],
            sensitiveDataExclusions: [
                "cwd",
                "paneTitle",
                "rawTerminalOutput",
                "rawRuntimePayload",
                "tabTitle",
                "url",
                "zmxSessionIdentifier",
            ]
        ),
        authorizationContext: { request, _, tools in
            let params = try decodeContributionHandleParams(from: request.params)
            let canonicalHandle = try await tools.canonicalizePaneHandle(params.handle)
            guard case .canonicalUUID(let paneId) = canonicalHandle.reference else {
                throw AppIPCQueryError(reason: .targetNotFound)
            }
            return try AppIPCAuthorizedRequestContext(
                request: request.replacingHandle(canonicalHandle.rawIPCHandleString),
                target: .pane(paneId.uuidString)
            )
        },
        dispatch: { request, _, context in
            let params = try decodeContributionHandleParams(from: request.params)
            let paneId = try context.uuidFromPaneHandle(params.handle)
            let snapshot = try await context.snapshotPane(paneId)
            return try JSONRPCCodec.encodeJSONValue(snapshot)
        }
    )
}

struct ContributionHandleParams: Decodable {
    let handle: String
}

private func decodeContributionHandleParams(from params: JSONValue?) throws -> ContributionHandleParams {
    let value = params ?? .object([:])
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(ContributionHandleParams.self, from: data)
}

func makePaneSnapshotResult(pane: IPCPaneSummary, paneCount: Int) -> IPCPaneSnapshotResult {
    IPCPaneSnapshotResult(
        pane: pane,
        tab: nil,
        workspace: IPCWorkspaceSummary(
            id: UUID(),
            ordinal: 1,
            name: "Test Workspace",
            tabCount: 1,
            paneCount: paneCount,
            isCurrent: true
        )
    )
}

struct DelegatedApprovalSocketScenario {
    let requestedScope: IPCPermissionScope
    let approverPrincipalId: UUID
    let requesterToken: AgentStudioIPCSubjectToken
    let approverToken: AgentStudioIPCSubjectToken
}

func makeDelegatedApprovalSocketScenario(fixture: LiveServerFixture) throws -> DelegatedApprovalSocketScenario {
    let requestedScope = IPCPermissionScope(
        privilege: .terminalInputWrite,
        target: .pane(UUID().uuidString),
        dataScope: .terminalInput
    )
    let requester = IPCPrincipal(
        principalId: UUID(),
        runtimeId: fixture.runtimeId,
        accessMode: .agentStudioOnly,
        kind: .spawnedPaneAgent(boundPaneId: fixture.boundPaneId.uuidString, boundWorkspaceId: nil),
        approvalAuthority: .noApprovalAuthority
    )
    let approver = IPCPrincipal(
        principalId: UUID(),
        runtimeId: fixture.runtimeId,
        accessMode: .agentStudioOnly,
        kind: .spawnedPaneAgent(boundPaneId: UUID().uuidString, boundWorkspaceId: nil),
        approvalAuthority: .delegatedApprover(
            scopes: [
                IPCApprovalScope(
                    privilege: requestedScope.privilege,
                    target: requestedScope.target,
                    dataScope: requestedScope.dataScope
                )
            ]
        )
    )

    return try DelegatedApprovalSocketScenario(
        requestedScope: requestedScope,
        approverPrincipalId: approver.principalId,
        requesterToken: fixture.server.principalRegistry.issueSubjectToken(for: requester),
        approverToken: fixture.server.principalRegistry.issueSubjectToken(for: approver)
    )
}

func requestDelegatedPermission(
    connection: UnixSocketConnection,
    reader: inout TestFrameReader,
    scenario: DelegatedApprovalSocketScenario
) throws -> IPCPermissionRequestResult {
    let requestParams = IPCPermissionRequestParams(
        scope: scenario.requestedScope,
        reason: "paired pane",
        approvalRoute: .delegatedPrincipal(scenario.approverPrincipalId)
    )
    try sendRequest(
        connection: connection,
        request: JSONRPCClientRequest(
            id: .number(21),
            method: "permission.request",
            params: try JSONRPCCodec.encodeJSONValue(requestParams)
        )
    )
    let permissionRequest = try reader.receiveResponse(connection: connection)
    #expect(permissionRequest.error == nil)
    let permissionResult = try decodeResponseResult(
        IPCPermissionRequestResult.self,
        from: permissionRequest
    )
    #expect(permissionResult.state == .pending)
    return permissionResult
}

func resolveDelegatedPermission(
    connection: UnixSocketConnection,
    reader: inout TestFrameReader,
    permissionResult: IPCPermissionRequestResult
) throws {
    try assertPendingApprovalVisible(
        connection: connection,
        reader: &reader,
        permissionResult: permissionResult
    )
    try sendRequest(
        connection: connection,
        request: JSONRPCClientRequest(
            id: .number(32),
            method: "permission.resolveRequest",
            params: .object([
                "requestId": .string(permissionResult.requestId.uuidString),
                "decision": .string(ApprovalPolicyDecision.approve.rawValue),
            ])
        )
    )
    let resolvedApproval = try reader.receiveResponse(connection: connection)
    #expect(resolvedApproval.error == nil)
    let resolvedResult = try decodeResponseResult(
        IPCPermissionRequestResult.self,
        from: resolvedApproval
    )
    #expect(resolvedResult.state == .granted)
}

func assertPendingApprovalVisible(
    connection: UnixSocketConnection,
    reader: inout TestFrameReader,
    permissionResult: IPCPermissionRequestResult
) throws {
    try sendRequest(
        connection: connection,
        request: JSONRPCClientRequest(id: .number(31), method: "permission.pendingApprovals", params: .object([:]))
    )
    let pendingApprovals = try reader.receiveResponse(connection: connection)
    #expect(pendingApprovals.error == nil)
    guard
        case .object(let pendingResult)? = pendingApprovals.result,
        case .array(let requests)? = pendingResult["requests"]
    else {
        Issue.record("expected pending approval requests array")
        return
    }
    #expect(requests.count == 1)
    let pendingResultValue = try decodeJSONValue(IPCPermissionRequestResult.self, from: requests[0])
    #expect(pendingResultValue.requestId == permissionResult.requestId)
}

func assertGrantIsActive(
    connection: UnixSocketConnection,
    reader: inout TestFrameReader,
    permissionResult: IPCPermissionRequestResult
) throws {
    try sendRequest(
        connection: connection,
        request: JSONRPCClientRequest(
            id: .number(22),
            method: "permission.grantStatus",
            params: .object(["requestId": .string(permissionResult.requestId.uuidString)])
        )
    )
    let grantStatus = try reader.receiveResponse(connection: connection)
    let grantStatusResult = try decodeResponseResult(IPCPermissionGrantStatusResult.self, from: grantStatus)
    #expect(grantStatusResult.state == .granted)
    #expect(grantStatusResult.active)
}

final class RecordingWaitRuntimePort: AppIPCRuntimePort, @unchecked Sendable {
    private let successfulPaneId: UUID
    private let lock = NSLock()
    nonisolated(unsafe) private var recordedAfterSequence: UInt64?
    nonisolated(unsafe) private var recordedHandle: IPCHandle?

    nonisolated init(successfulPaneId: UUID) {
        self.successfulPaneId = successfulPaneId
    }

    nonisolated var lastAfterSequence: UInt64? {
        lock.withLock {
            recordedAfterSequence
        }
    }

    nonisolated var lastHandle: IPCHandle? {
        lock.withLock {
            recordedHandle
        }
    }

    func terminalStatus(_: IPCHandle) throws -> IPCTerminalStatusResult {
        throw AppIPCRuntimeError(reason: .noRuntime)
    }

    func terminalSnapshot(_: IPCHandle) throws -> IPCTerminalSnapshotResult {
        throw AppIPCRuntimeError(reason: .noRuntime)
    }

    func sendTerminalInput(
        to _: IPCHandle,
        input _: String,
        correlationId _: UUID?
    ) async throws -> IPCTerminalSendInputResult {
        throw AppIPCRuntimeError(reason: .noRuntime)
    }

    func waitForTerminal(
        _ handle: IPCHandle,
        condition: IPCTerminalWaitCondition,
        timeout _: Duration,
        afterSequence: UInt64?
    ) async throws -> IPCTerminalWaitResult {
        lock.withLock {
            recordedHandle = handle
            recordedAfterSequence = afterSequence
        }
        return IPCTerminalWaitResult(
            paneId: successfulPaneId,
            condition: condition,
            eventName: .terminalCommandFinished,
            commandId: nil,
            correlationId: nil,
            exitCode: 0,
            duration: 1,
            healthy: nil
        )
    }
}

func sendRequest(socketPath: String, request: JSONRPCClientRequest) throws -> JSONRPCResponseMessage {
    let connection = try UnixSocketClient.connect(endpoint: UnixSocketEndpoint(path: socketPath))
    defer {
        connection.close()
    }
    try sendRequest(connection: connection, request: request)
    var reader = TestFrameReader()
    return try reader.receiveResponse(connection: connection)
}

func sendRequestWithoutBlockingMainActor(socketPath: String, request: JSONRPCClientRequest) async throws
    -> JSONRPCResponseMessage
{
    let connection = try UnixSocketClient.connect(endpoint: UnixSocketEndpoint(path: socketPath))
    defer {
        connection.close()
    }
    try sendRequest(connection: connection, request: request)
    var reader = TestFrameReader()
    return try await reader.receiveResponseWithoutBlockingMainActor(connection: connection)
}

func sendRequest(connection: UnixSocketConnection, request: JSONRPCClientRequest) throws {
    try connection.send(
        try NDJSONFrameEncoder.encode(
            JSONRPCCodec.encodeRequest(request),
            maxFrameBytes: 65_536
        ))
}

func login(
    connection: UnixSocketConnection,
    token: AgentStudioIPCSubjectToken,
    requestId: Int,
    reader: inout TestFrameReader
) throws {
    try sendRequest(
        connection: connection,
        request: JSONRPCClientRequest(
            id: .number(requestId),
            method: "auth.login",
            params: .object(["token": .string(token.rawValue)])
        )
    )
    let response = try reader.receiveResponse(connection: connection)
    #expect(response.id == .number(requestId))
    #expect(response.error == nil)
}

func loginWithoutBlockingMainActor(
    connection: UnixSocketConnection,
    token: AgentStudioIPCSubjectToken,
    requestId: Int,
    reader: inout TestFrameReader
) async throws {
    try sendRequest(
        connection: connection,
        request: JSONRPCClientRequest(
            id: .number(requestId),
            method: "auth.login",
            params: .object(["token": .string(token.rawValue)])
        )
    )
    let response = try await reader.receiveResponseWithoutBlockingMainActor(connection: connection)
    #expect(response.id == .number(requestId))
    #expect(response.error == nil)
}

func decodeResponseResult<T: Decodable>(
    _ type: T.Type,
    from response: JSONRPCResponseMessage
) throws -> T {
    let result = try #require(response.result)
    return try decodeJSONValue(type, from: result)
}

func decodeJSONValue<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(type, from: data)
}

struct TestFrameReader {
    var decoder = NDJSONFrameDecoder(maxFrameBytes: 65_536)
    var queuedFrames: [String] = []

    mutating func receiveResponse(connection: UnixSocketConnection) throws -> JSONRPCResponseMessage {
        try JSONRPCCodec.decodeResponse(receiveFrame(connection: connection))
    }

    mutating func receiveFrame(connection: UnixSocketConnection) throws -> String {
        if !queuedFrames.isEmpty {
            return queuedFrames.removeFirst()
        }
        while true {
            let data = try connection.receive(maxBytes: 4096)
            queuedFrames.append(contentsOf: try decoder.append(data))
            if !queuedFrames.isEmpty {
                return queuedFrames.removeFirst()
            }
        }
    }

    func hasBufferedFrame(containing text: String) -> Bool {
        queuedFrames.contains { $0.contains(text) }
    }

    mutating func receiveResponseWithoutBlockingMainActor(connection: UnixSocketConnection) async throws
        -> JSONRPCResponseMessage
    {
        if !queuedFrames.isEmpty {
            return try JSONRPCCodec.decodeResponse(queuedFrames.removeFirst())
        }
        while true {
            let data = try await receiveDataWithoutBlockingMainActor(connection: connection)
            queuedFrames.append(contentsOf: try decoder.append(data))
            if !queuedFrames.isEmpty {
                return try JSONRPCCodec.decodeResponse(queuedFrames.removeFirst())
            }
        }
    }

    private func receiveDataWithoutBlockingMainActor(connection: UnixSocketConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(returning: try connection.receive(maxBytes: 4096))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

func readBootstrapToken(fileDescriptor: Int32) throws -> AgentStudioIPCSubjectToken {
    #if canImport(Darwin)
        var buffer = [UInt8](repeating: 0, count: 128)
        let bytesRead = Darwin.read(fileDescriptor, &buffer, buffer.count)
        guard bytesRead > 0 else {
            throw AgentStudioIPCPaneBootstrapError(reason: .tokenWriteFailed, errnoCode: errno)
        }
        guard
            let rawValue = String(bytes: buffer.prefix(bytesRead), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            throw AgentStudioIPCPaneBootstrapError(reason: .tokenWriteFailed, errnoCode: errno)
        }
        return AgentStudioIPCSubjectToken(rawValue: rawValue)
    #else
        throw AgentStudioIPCPaneBootstrapError(reason: .unsupportedPlatform)
    #endif
}

func isCloseOnExec(fileDescriptor: Int32) throws -> Bool {
    #if canImport(Darwin)
        let flags = fcntl(fileDescriptor, F_GETFD)
        guard flags >= 0 else {
            throw AgentStudioIPCPaneBootstrapError(reason: .pipeConfigurationFailed, errnoCode: errno)
        }
        return flags & FD_CLOEXEC == FD_CLOEXEC
    #else
        throw AgentStudioIPCPaneBootstrapError(reason: .unsupportedPlatform)
    #endif
}

func fileMode(for url: URL) throws -> mode_t {
    var statBuffer = stat()
    guard lstat(url.path, &statBuffer) == 0 else {
        throw POSIXError(.ENOENT)
    }
    return statBuffer.st_mode
}
