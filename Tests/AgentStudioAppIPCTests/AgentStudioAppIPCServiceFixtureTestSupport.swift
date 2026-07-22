import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation
import Testing

#if canImport(Darwin)
    import Darwin
#endif

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
        sidebarPort: any AppIPCSidebarPort = FakeSidebarPort(),
        debugTokenEscrowEnabled: Bool = false,
        debugTokenEscrowPermissionScopes: [IPCPermissionScope] = [],
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
        let contributedMethodNames = Set(methodContributions.map(\.definition.name))
        let baseDefinitions = methodRegistry.definitions
            .filter { !contributedMethodNames.contains($0.name) }
        let mergedMethodRegistry = try AppIPCMethodRegistry(
            baseDefinitions: baseDefinitions,
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
            sidebarPort: sidebarPort,
            permissionApprovalPort: FakePermissionApprovalPort()
        )
        let service = try AgentStudioAppIPCService(
            configuration: AgentStudioAppIPCConfiguration(
                runtimeId: runtimeId,
                accessMode: accessMode,
                methodDefinitions: baseDefinitions,
                debugTokenEscrowEnabled: debugTokenEscrowEnabled,
                debugTokenEscrowPermissionScopes: debugTokenEscrowPermissionScopes
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
