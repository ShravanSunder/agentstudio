import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation
import Testing

#if canImport(Darwin)
    import Darwin
#endif

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

struct FakeCommandPort: AppIPCCommandPort {
    let workspaceWindowId: UUID?
    let activeScope: IPCCommandBarScope?

    nonisolated init(workspaceWindowId: UUID? = nil, activeScope: IPCCommandBarScope? = nil) {
        self.workspaceWindowId = workspaceWindowId
        self.activeScope = activeScope
    }

    func listCommands() throws -> IPCCommandListResult {
        IPCCommandListResult(commands: [])
    }

    func executeCommand(_ params: IPCCommandExecuteParams) throws -> IPCCommandExecuteResult {
        if params.targetHandle != nil {
            throw AppIPCCommandError(reason: .targetNotFound)
        }
        guard IPCCommandIdentifier.allCases.contains(params.commandId) else {
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
        runtimePort: any AppIPCRuntimePort = FakeRuntimePort(),
        commandPort: any AppIPCCommandPort = FakeCommandPort(),
        uiPresentationPort: any AppIPCUIPresentationPort = FakeUIPresentationPort(),
        debugTokenEscrowEnabled: Bool = false
    ) throws {
        rootURL = URL(fileURLWithPath: "/tmp/asipc-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        #if canImport(Darwin)
            _ = chmod(rootURL.path, 0o700)
        #endif
        paths = AgentStudioIPCPathResolver().paths(rootDirectory: rootURL)
        let methodRegistry = try AppIPCMethodRegistry.phaseOne()
        let service = AgentStudioAppIPCService(
            configuration: AgentStudioAppIPCConfiguration(
                runtimeId: runtimeId,
                accessMode: accessMode,
                methodDefinitions: methodRegistry.definitions,
                debugTokenEscrowEnabled: debugTokenEscrowEnabled
            ),
            ports: AgentStudioAppIPCPorts(
                queryPort: FakeQueryPort(runtimeId: runtimeId, panes: panes),
                layoutPort: FakeLayoutPort(),
                runtimePort: runtimePort,
                commandPort: commandPort,
                uiPresentationPort: uiPresentationPort,
                permissionApprovalPort: FakePermissionApprovalPort()
            )
        )
        server = AgentStudioAppIPCServer(service: service, paths: paths, channel: channel)
    }

    func cleanup() {
        server.stop()
        try? FileManager.default.removeItem(at: rootURL)
    }
}

func makePaneSummary(id: UUID, ordinal: Int) -> IPCPaneSummary {
    IPCPaneSummary(
        id: id,
        ordinal: ordinal,
        contentKind: .terminal,
        residency: .active,
        tabId: nil,
        repoId: nil,
        worktreeId: nil,
        isActive: false,
        isDrawerChild: false
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
        if !queuedFrames.isEmpty {
            return try JSONRPCCodec.decodeResponse(queuedFrames.removeFirst())
        }
        while true {
            let data = try connection.receive(maxBytes: 4096)
            queuedFrames.append(contentsOf: try decoder.append(data))
            if !queuedFrames.isEmpty {
                return try JSONRPCCodec.decodeResponse(queuedFrames.removeFirst())
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
